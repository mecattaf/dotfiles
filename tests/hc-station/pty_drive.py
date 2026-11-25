"""Run one command in a pseudo-terminal, the way a Kitty window would.

  pty_drive.py [--cols C] [--rows R] [--timeout S] [--until TEXT] [--hup-after S]
               [--send TEXT --send-after S] -- command [args...]

Answers `hc attach`'s display probe (DA1, OSC 10/11/12) and fish's DA1 at once,
as Kitty does, so probe deadlines do not inflate timings. Prints one JSON line:
{"rc", "first_byte_ms", "until_ms", "elapsed_ms", "output"} (output: the text
with escape sequences removed, last 4000 characters).
"""
import argparse
import fcntl
import json
import os
import pty
import re
import select
import signal
import struct
import subprocess
import termios
import time

ANSWERS = [
    (b"\x1b]10;?", b"\x1b]10;rgb:dddd/dddd/dddd\x1b\\"),
    (b"\x1b]11;?", b"\x1b]11;rgb:1111/1111/1111\x1b\\"),
    (b"\x1b]12;?", b"\x1b]12;rgb:dddd/dddd/dddd\x1b\\"),
    (b"\x1b[16t", b"\x1b[6;20;10t"),
    (b"\x1b[c", b"\x1b[?62;22c"),
    # fish 4 on the plain path (no hc in between) asks these and waits for DA1.
    (b"\x1b[0c", b"\x1b[?62;22c"),
    (b"\x1b[?u", b"\x1b[?0u"),
]
ESCAPES = re.compile(rb"\x1b\][^\x07\x1b]*(\x07|\x1b\\)|\x1b\[[0-9;?<>=!]*[ -/]*[@-~]|\x1b[()][0-9A-Za-z]|\x1b[=>78DEHMNOPZc\\]")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--cols", type=int, default=100)
    parser.add_argument("--rows", type=int, default=30)
    parser.add_argument("--timeout", type=float, default=20)
    parser.add_argument("--until")
    parser.add_argument("--hup-after", type=float)
    parser.add_argument("--send")
    parser.add_argument("--send-after", type=float, default=1.0)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    options = parser.parse_args()
    command = options.command[1:] if options.command[:1] == ["--"] else options.command

    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", options.rows, options.cols, 0, 0))
    began = time.monotonic()
    child = subprocess.Popen(command, stdin=slave, stdout=slave, stderr=slave, start_new_session=True,
                             preexec_fn=lambda: fcntl.ioctl(0, termios.TIOCSCTTY, 0))
    os.close(slave)
    raw, first, until, hupped, sent = b"", None, None, False, False
    answered = {probe: 0 for probe, _ in ANSWERS}
    while True:
        now = time.monotonic() - began
        if now > options.timeout:
            child.kill()
            break
        if options.hup_after is not None and not hupped and now >= options.hup_after:
            child.send_signal(signal.SIGHUP)
            hupped = True
        if options.send is not None and not sent and now >= options.send_after:
            os.write(master, options.send.encode().decode("unicode_escape").encode())
            sent = True
        ready, _, _ = select.select([master], [], [], 0.02)
        if ready:
            try:
                chunk = os.read(master, 65536)
            except OSError:
                chunk = b""
            if not chunk:
                break
            if first is None:
                first = time.monotonic() - began
            raw += chunk
            for probe, answer in ANSWERS:
                count = raw.count(probe)
                if count > answered[probe]:
                    os.write(master, answer * (count - answered[probe]))
                    answered[probe] = count
            if options.until and until is None and options.until.encode() in ESCAPES.sub(b"", raw):
                until = time.monotonic() - began
        elif child.poll() is not None:
            break
    try:
        rc = child.wait(5)
    except subprocess.TimeoutExpired:
        child.kill()
        rc = child.wait()
    os.close(master)
    text = ESCAPES.sub(b"", raw).decode("utf-8", "replace")
    ms = lambda value: None if value is None else round(value * 1000, 1)
    print(json.dumps({"rc": rc, "first_byte_ms": ms(first), "until_ms": ms(until),
                      "elapsed_ms": ms(time.monotonic() - began), "output": text[-4000:]}))


if __name__ == "__main__":
    main()
