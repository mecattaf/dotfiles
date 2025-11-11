# Tailscale Plugin for DankMaterialShell

A comprehensive Tailscale VPN management plugin for DankMaterialShell (DMS) that provides seamless integration with the Tailscale VPN service.

## Features

- **Real-time Status Monitoring**: View your Tailscale connection status at a glance
- **Exit Node Management**: Easily switch between exit nodes or disable them
- **Node List**: View all available nodes in your tailnet with online/offline status
- **Settings Control**: Manage Tailscale settings directly from the UI:
  - Accept DNS
  - Accept Routes
  - Allow LAN Access
  - Shields Up
  - SSH
- **DankBar Integration**: Shows connection status and exit node in the bar
- **Control Center Integration**: Quick toggle for Tailscale connection
- **Popout Interface**: Comprehensive management interface with full node list and settings

## Requirements

- Tailscale installed and configured on your system
- `tailscale` CLI command available in PATH
- `jq` command-line JSON processor (for parsing tailscale status)
- DankMaterialShell 0.1.0 or higher

### Installation

#### Tailscale

```bash
# On most Linux distributions
curl -fsSL https://tailscale.com/install.sh | sh

# Start Tailscale
sudo tailscale up
```

#### jq

```bash
# Debian/Ubuntu
sudo apt install jq

# Fedora
sudo dnf install jq

# Arch
sudo pacman -S jq
```

## Installation

1. Copy the `tailscale` folder to your DMS plugins directory:
   ```bash
   cp -r plugins/tailscale ~/.config/DankMaterialShell/plugins/
   ```

2. Open DMS Settings (usually Ctrl+,)

3. Navigate to the Plugins tab

4. Click "Scan for Plugins" if the plugin doesn't appear

5. Enable the Tailscale plugin with the toggle switch

6. Add the plugin to your DankBar configuration:
   - Go to Settings → Appearance → DankBar Layout
   - Add "tailscale" to your desired section (left, center, or right)

## Usage

### DankBar Widget

The widget displays:
- VPN icon (locked when connected, unlocked when disconnected)
- Connection status text
- Exit node name (if active)

Click the widget to open the management popout.

### Control Center

Toggle Tailscale connection on/off from the Control Center quick settings panel.

### Popout Interface

The popout provides comprehensive management:

#### Connection Control
- View current connection status
- Connect/Disconnect button
- Real-time status updates

#### Exit Nodes
- List of all available exit nodes
- Current exit node highlighted
- Click any node to use it as an exit node
- Click "Disable" to remove the current exit node
- Visual indicators for:
  - Online/offline status
  - Exit node availability
  - Node type (computer, mobile, Mullvad)

#### Settings
Toggle various Tailscale settings:
- **Accept DNS**: Use Tailscale's DNS servers
- **Accept Routes**: Accept subnet routes from other nodes
- **Allow LAN Access**: Access local network when using exit node
- **Shields Up**: Block incoming connections
- **SSH**: Enable Tailscale SSH server

## Features in Detail

### Exit Nodes

Exit nodes allow you to route your internet traffic through another device in your tailnet. This is useful for:
- Accessing geo-restricted content
- Securing your connection on public WiFi
- Routing through a specific country/region

The plugin automatically detects:
- Available exit nodes (advertised by other nodes)
- Mullvad VPN exit nodes (if integrated with your tailnet)
- Current active exit node

### Node Management

The nodes list shows:
- Node name
- Online/offline status
- Device type (computer, phone, Mullvad)
- Exit node capability
- Current exit node indicator

### Settings Persistence

All Tailscale settings are persisted by the Tailscale daemon and will be remembered across restarts.

## Architecture

The plugin consists of:

- **plugin.json**: Plugin manifest with metadata
- **TailscaleService.qml**: Service layer that communicates with Tailscale CLI
- **TailscaleWidget.qml**: Main widget component with DankBar and popout integration
- **SettingRow.qml**: Reusable settings toggle component

### How It Works

The plugin uses the `tailscale` CLI to:
1. Poll status every 5 seconds using `tailscale status --json`
2. Parse node information and preferences
3. Execute commands for toggling settings and changing exit nodes
4. Update the UI reactively based on state changes

## Troubleshooting

### Plugin doesn't appear

- Ensure Tailscale is installed: `which tailscale`
- Ensure jq is installed: `which jq`
- Check plugin files are in: `~/.config/DankMaterialShell/plugins/tailscale/`
- Click "Scan for Plugins" in Settings → Plugins

### No nodes appear

- Ensure Tailscale is running: `tailscale status`
- Check you're logged in: `tailscale status | grep Logged`
- Verify you have other devices in your tailnet
- Some nodes need to advertise as exit nodes to appear in that list

### Settings don't change

- Verify you have permission to change settings
- Check Tailscale logs: `journalctl -u tailscaled -f`
- Ensure you're not using `--operator` restricted mode

### Commands fail

- Check Tailscale service is running: `systemctl status tailscaled`
- Verify CLI access: `tailscale status`
- Check system logs for errors

## Contributing

This plugin is part of the DankMaterialShell ecosystem. Contributions are welcome!

## License

Same as DankMaterialShell

## Credits

Based on the Tailscale GNOME Shell extension design and adapted for DMS.

## Roadmap

Future enhancements:
- Profile switching support
- Mullvad exit node filtering and search
- Node IP address display and clipboard copy
- Connection statistics
- ACL and sharing management
- Peer suggestions and invites
