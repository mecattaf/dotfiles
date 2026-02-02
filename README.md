TODO: Add claude code install instructions since was not able to get it done with bluebuild install.. which is fine since we would need to authenticate anyway


# BluePrint Linux &nbsp; [![build-ublue](https://github.com/blue-build/template/actions/workflows/build.yml/badge.svg)](https://github.com/blue-build/template/actions/workflows/build.yml)

Using the Framework Desktop simultaneously as personal desktop AND a secure homelab/homeserver. This distribution is specialized for the highest-spec framework desktop available on the market. Use on other devices at your own risks and perils. 

# Features:
- Dedicated Quadlets module to automate podman quadlets management
- Verified ISO installation process
- Works with Secure Boot
- Framework Desktop-specific adjustments:
    - Press F2 during early boot to enter BIOS  → Set minimum VRAM (static allocation). 
    - Optimized kargs module with `amdttm`
- Desktop behavior:
    - Auto-login with SDDM
    - Enabled --user quadlet lingering by default
- Configuration files managed with chezmoi
    - Homeserver benefits with Cockpit, Tailscale and Caddy
    - Secure api key management with encrypted external (physical) USB drives

## Installation (ISO) [Recommended]

> [!CAUTION]
> This ISO installation guide assumes that you want to install BluePrint Linux on single-boot single-disk setup.

### [DOWNLOAD LINK](https://github.com/leger-labs/blueprint/actions/workflows/build-iso.yml)
Click on the most recent successful build, then download the ISO artifact.  
ISOs are named in DD-MM-YYYY date format for easy identification.

- Download and extract the ISO artifact from GitHub Actions
- ISO doesn't require an active internet connection during its usage (but it is recommended to have it for NTP functionality)
- Boot from the ISO and proceed with installation
- When ISO is booted, complete the following mandatory configuration:
  - **Network & Host Name**: Configure your WiFi connection if needed
  - **Installation Destination**: Select target disk, choose "Storage Configuration" → Automatic, then "Free up space by removing or shrinking existing partitions"
    - When "Reclaim disk space" screen appears, click "Delete all" and "Reclaim space"
  - **User Creation**: Input your full name, username, and password. Click Done.
  - **Root Password**: Set a root password for system administration (recommended for Sway environments)
- Optionally configure "Keyboard", "Language Support", "Time & Date", etc.
- Click "Begin Installation"
- After installation completes, reboot and enjoy your new Duo Linux system

### Device Configuration

We use another USB drive that contains the encryption key for API secrets (managed by chezmoi)
- Tailscale: [follow instructions](docs/tailscale.md)
- Decrypting API keys with Age: [follow instructions](docs/age-encrypt-secrets.md)

### Manual Steps

- Sign in to github wih `gh auth login`
- Copy over git credentials
```
git config --global user.name "Thomas Mecattaf"
git config --global user.email "thomas@mecattaf.dev"
```
- Authenticate to google chrome and [follow instructions](docs/chrome.md)
- Authenticate to gh from the CLI
- Set icon and gtk theme with GTK Settings
- If flatpaks are not loaded automatically:
```
mako #to have a notification daemon running
bluebuild-flatpak-manager apply all
```

### Enabling systemd services

We use a single command to detect and enable all systemd services in one go. The snippets below show us testing for a subset of available podman quadlets to be used. Do the same for testing other systemd units (wayland graphical session)
```
# Reload systemd
echo "Reloading systemd daemon..."
systemctl --user daemon-reload
```

## Alternative Installation (Rebase)

To rebase an existing atomic Fedora installation to the latest build:

- First rebase to the unsigned image, to get the proper signing keys and policies installed:
  ```
  sudo rpm-ostree rebase ostree-unverified-registry:ghcr.io/leger-labs/blueprint:latest
  ```
- Reboot to complete the rebase:
  ```
  systemctl reboot
  ```
- Then rebase to the signed image, like so:
  ```
  sudo rpm-ostree rebase ostree-image-signed:docker://ghcr.io/leger-labs/blueprint:latest
  ```
- Reboot again to complete the installation
  ```
  systemctl reboot
  ```


### Troubleshooting flatpaks

If a flatpak is broken, revert versions using:
```
flatpak list
flatpak remote-info --log flathub com.google.Chrome
flatpak update --commit=<commit-of-working-version> com.google.Chrome
```

### Rolling back to previous versions

View the list of available builds by entering:
```
skopeo list-tags docker://ghcr.io/leger-labs/blueprint | sort -rV
```

## ISO Verification

### 1. Download the public key
```bash
curl -O https://raw.githubusercontent.com/leger-labs/blueprint/main/.github/keys/blueprint-public.gpg
gpg --import blueprint-public.gpg
```

### 2. Download ISO and checksum
```bash
# Download from R2
curl -O https://downloads.leger.run/blueprint-YYYYMMDD.iso
curl -O https://downloads.leger.run/blueprint-YYYYMMDD.iso-CHECKSUM
```

### 3. Verify signature and checksum
```bash
# Verify the signature on the checksum file
gpg --verify blueprint-YYYYMMDD.iso-CHECKSUM

# If signature is good, verify the ISO checksum
sha256sum -c blueprint-YYYYMMDD.iso-CHECKSUM
```

If both checks pass, your ISO is authentic and untampered! ✅
