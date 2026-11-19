// Read battery notifications from an already paired AirPods AAP channel.
// Protocol facts: librepods-org/librepods/docs/AAP Definitions.md. No ANC,
// volume, ear detection, head tracking or other user settings are changed.
use serde_json::{json, Value};
use std::fs::File;
use std::io::{self, Read, Write};
use std::os::fd::{FromRawFd, RawFd};
use std::time::{Duration, Instant};

#[repr(C)]
struct Address {
    family: libc::sa_family_t,
    psm: u16,
    device: [u8; 6],
    cid: u16,
    kind: u8,
}

fn option(fd: RawFd, level: i32, name: i32, bytes: &[u8]) -> io::Result<()> {
    let result = unsafe { libc::setsockopt(fd, level, name, bytes.as_ptr().cast(), bytes.len() as _) };
    if result == -1 { Err(io::Error::last_os_error()) } else { Ok(()) }
}

fn timeout(fd: RawFd, option_name: i32, millis: i64) -> io::Result<()> {
    let value = libc::timeval { tv_sec: millis / 1000, tv_usec: (millis % 1000) * 1000 };
    let bytes = unsafe { std::slice::from_raw_parts((&value as *const libc::timeval).cast(), std::mem::size_of_val(&value)) };
    option(fd, libc::SOL_SOCKET, option_name, bytes)
}

pub fn decode(frame: &[u8], model: Option<u16>) -> Option<Value> {
    if frame.len() < 7 || frame[..6] != [4, 0, 4, 0, 4, 0] { return None; }
    let count = frame[6] as usize;
    if count == 0 || count > 4 || frame.len() != 7 + 5 * count { return None; }
    let mut components = Vec::new();
    for entry in frame[7..].chunks_exact(5) {
        if entry[1] != 1 || entry[4] != 1 { return None; }
        let name = match entry[0] { 1 => "headphones", 2 => "right", 4 => "left", 8 => "case", _ => continue };
        if entry[2] > 100 || !matches!(entry[3], 1..=3) { continue; }
        if components.iter().any(|c: &Value| c["name"] == name) { return None; }
        components.push(json!({"name": name, "battery": entry[2], "charging": entry[3] == 1}));
    }
    if components.is_empty() { return None; }
    components.sort_by_key(|part| match part["name"].as_str() { Some("left" | "headphones") => 0, Some("right") => 1, _ => 2 });
    let battery = components.iter().filter(|part| part["name"] != "case").filter_map(|part| part["battery"].as_u64()).min();
    let single = components.iter().any(|part| part["name"] == "headphones");
    Some(json!({"type": if single { "over_ear" } else { "in_ear" },
        "model": super::model_name(model.unwrap_or(0)), "battery": battery,
        "components": components, "source": "device"}))
}

pub fn read(address: &str, model: Option<u16>) -> io::Result<Value> {
    let octets: Vec<u8> = address.split(':').map(|part| u8::from_str_radix(part, 16)).collect::<Result<_, _>>()
        .map_err(|_| io::Error::new(io::ErrorKind::InvalidInput, "invalid Bluetooth address"))?;
    if octets.len() != 6 { return Err(io::Error::new(io::ErrorKind::InvalidInput, "invalid Bluetooth address")); }
    let fd = unsafe { libc::socket(libc::AF_BLUETOOTH, libc::SOCK_SEQPACKET | libc::SOCK_CLOEXEC, 0) };
    if fd == -1 { return Err(io::Error::last_os_error()); }
    let mut socket = unsafe { File::from_raw_fd(fd) };
    // Reuse the existing encrypted, paired BR/EDR link; no scan or pairing.
    option(fd, 274, 4, &[2, 0])?; // SOL_BLUETOOTH, BT_SECURITY, MEDIUM
    timeout(fd, libc::SO_SNDTIMEO, 2000)?;
    timeout(fd, libc::SO_RCVTIMEO, 250)?;
    let target = Address { family: libc::AF_BLUETOOTH as _, psm: 0x1001_u16.to_le(),
        device: [octets[5], octets[4], octets[3], octets[2], octets[1], octets[0]], cid: 0, kind: 0 };
    if unsafe { libc::connect(fd, (&target as *const Address).cast(), std::mem::size_of_val(&target) as _) } == -1 {
        return Err(io::Error::last_os_error());
    }
    socket.write_all(&[0, 0, 4, 0, 1, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0])?;
    // Subscribe to device notifications. The all-FF mask includes battery on
    // Pro 2 firmware that sends no battery with the older FF FF FE FF mask.
    socket.write_all(&[4, 0, 4, 0, 15, 0, 255, 255, 255, 255])?;
    let deadline = Instant::now() + Duration::from_secs(3);
    let mut buffer = [0; 4096];
    while Instant::now() < deadline {
        match socket.read(&mut buffer) {
            Ok(0) => break,
            Ok(size) => if let Some(status) = decode(&buffer[..size], model) { return Ok(status); },
            Err(error) if matches!(error.kind(), io::ErrorKind::WouldBlock | io::ErrorKind::TimedOut | io::ErrorKind::Interrupted) => continue,
            Err(error) => return Err(error),
        }
    }
    Err(io::Error::new(io::ErrorKind::TimedOut, "AirPods have not reported battery status"))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn device_levels_are_exact_and_sides_follow_component_ids() {
        let data = decode(&[4,0,4,0,4,0,3, 2,1,64,2,1, 4,1,73,1,1, 8,1,28,2,1], Some(0x1420)).unwrap();
        assert_eq!(data["source"], "device");
        assert_eq!(data["components"][0]["name"], "left");
        assert_eq!(data["components"][0]["battery"], 73);
        assert_eq!(data["components"][0]["charging"], true);
        assert_eq!(data["components"][1]["battery"], 64);
        assert_eq!(data["components"][2]["battery"], 28);
    }
    #[test]
    fn absent_case_and_malformed_frames_are_never_invented() {
        let data = decode(&[4,0,4,0,4,0,2, 2,1,50,2,1, 8,1,0,4,1], None).unwrap();
        assert_eq!(data["components"].as_array().unwrap().len(), 1);
        assert!(decode(&[4,0,4,0,4,0,3, 2,1,50,2,1], None).is_none());
        assert!(decode(&[4,0,4,0,4,0,1, 2,0,50,2,1], None).is_none());
        assert!(decode(&[4,0,4,0,4,0,1, 2,1,255,2,1], None).is_none());
    }
}
