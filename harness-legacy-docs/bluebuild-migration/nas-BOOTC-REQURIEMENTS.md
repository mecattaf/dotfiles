# Bootc image requirements for quadlet NAS setup

These are the OS-level changes needed in the Containerfile so that the
user-level quadlets (navidrome, immich) and SMB mount units work out of the box.

## 1. Package: cifs-utils

Required for mounting SMB shares. Without it the `mnt-nas.mount` unit fails.

```dockerfile
RUN dnf install -y cifs-utils && dnf clean all
```

## 2. Directory: /mnt/nas

The mount target must exist. On atomic Fedora `/mnt` is writable but empty by default.

```dockerfile
RUN mkdir -p /mnt/nas
```

## 3. Sysctl: IP forwarding

The desktop acts as a gateway for the TP-Link router (AP mode). All devices
behind the router need the desktop to forward packets from eth0 to wlan0.

```dockerfile
COPY etc/sysctl.d/99-router.conf /etc/sysctl.d/99-router.conf
```

Contents of `99-router.conf`:
```
net.ipv4.ip_forward=1
```

## 4. Firewalld zones

NAT masquerade on the Wi-Fi interface (internet-facing), permissive internal
zone on ethernet (router-facing). Baking the zone XML files is more stable
than a first-boot script — firewalld reads them at service start.

```dockerfile
COPY etc/firewalld/zones/external.xml /etc/firewalld/zones/external.xml
COPY etc/firewalld/zones/internal.xml /etc/firewalld/zones/internal.xml
```

Contents of `external.xml` (internet-facing, wlan0):
```xml
<?xml version="1.0" encoding="utf-8"?>
<zone>
  <short>External</short>
  <interface name="wlan0"/>
  <masquerade/>
</zone>
```

Contents of `internal.xml` (router-facing, eth0):
```xml
<?xml version="1.0" encoding="utf-8"?>
<zone>
  <short>Internal</short>
  <interface name="eth0"/>
  <service name="dns"/>
  <service name="dhcp"/>
  <service name="samba-client"/>
</zone>
```

## 5. NetworkManager connection: static ethernet

Static IP on the ethernet port facing the router. This file can also be baked
into the image. NetworkManager picks it up at boot.

```dockerfile
COPY etc/NetworkManager/system-connections/router-link.nmconnection \
     /etc/NetworkManager/system-connections/router-link.nmconnection
RUN chmod 600 /etc/NetworkManager/system-connections/router-link.nmconnection
```

Contents of `router-link.nmconnection`:
```ini
[connection]
id=router-link
type=ethernet
interface-name=eth0
autoconnect=true

[ipv4]
method=manual
addresses=10.0.0.1/24
never-default=true

[ipv6]
method=disabled
```

## 6. SMB mount units (system-level)

The SMB mount for the router's USB SSD runs as a system service, not user-level.
CIFS mounts are a privileged operation — user-level systemd cannot mount them
without polkit workarounds. The user-level quadlets (navidrome, immich) depend
on this mount via `Requires=mnt-nas.automount` in their unit files; systemd
resolves cross-level dependencies correctly when the system unit exists.

```dockerfile
COPY etc/systemd/system/mnt-nas.mount /etc/systemd/system/mnt-nas.mount
COPY etc/systemd/system/mnt-nas.automount /etc/systemd/system/mnt-nas.automount
RUN systemctl enable mnt-nas.automount
```

Contents of `mnt-nas.mount`:
```ini
[Unit]
Description=Router NAS SMB Mount
After=network-online.target
Wants=network-online.target

[Mount]
What=//10.0.0.2/share
Where=/mnt/nas
Type=cifs
Options=guest,vers=3.1.1,_netdev,uid=1000,gid=1000

[Install]
WantedBy=multi-user.target
```

Contents of `mnt-nas.automount`:
```ini
[Unit]
Description=Automount Router NAS

[Automount]
Where=/mnt/nas
TimeoutIdleSec=0

[Install]
WantedBy=multi-user.target
```

## Summary

| Change | Type | Why |
|--------|------|-----|
| `cifs-utils` | Package | SMB mount support |
| `/mnt/nas` | Directory | Mount target for router SSD |
| `99-router.conf` | Sysctl | IP forwarding (desktop is gateway) |
| `external.xml` | Firewalld zone | NAT masquerade on wlan0 |
| `internal.xml` | Firewalld zone | Allow DNS/DHCP/SMB on eth0 |
| `router-link.nmconnection` | NetworkManager | Static 10.0.0.1/24 on eth0 |
| `mnt-nas.mount` | Systemd mount | SMB share from router SSD |
| `mnt-nas.automount` | Systemd automount | Mount on first access, not at boot |

All eight are declarative files baked into the image. No first-boot scripts needed.

The separation: OS image owns the infrastructure (networking, mount, firewall).
User-level dotfiles own the services (quadlets deployed via chezmoi to
`~/.config/containers/systemd/`). Quadlets depend on the system mount
transparently.
