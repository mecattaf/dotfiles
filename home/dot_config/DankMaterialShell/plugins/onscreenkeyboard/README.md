# On-Screen Keyboard (OSK) Plugin

A virtual on-screen keyboard plugin for DankMaterialShell with ydotool integration, providing touchscreen support and accessibility features.

## Features

- **Full QWERTY Layout**: Complete keyboard with function keys, modifiers, and all standard keys
- **Shift & Caps Lock**: Single tap for shift, double-tap for caps lock
- **Modifier Keys**: Toggle Ctrl, Alt, and other modifiers
- **Touch-Friendly**: Large, easy-to-tap keys optimized for touchscreens
- **DankBar Integration**: Quick access from your bar
- **Control Center**: Toggle keyboard from Control Center
- **Pinnable**: Keep keyboard visible while working
- **ydotool Integration**: Reliable key input using ydotool

## Requirements

This plugin requires `ydotool` to be installed and running:

### Installation

**Arch Linux:**
```bash
sudo pacman -S ydotool
```

**Other distributions:**
```bash
# Ubuntu/Debian
sudo apt install ydotool

# Fedora
sudo dnf install ydotool
```

### Setup

1. Enable the ydotool daemon:
```bash
sudo systemctl enable --now ydotoold
```

2. Add your user to the input group:
```bash
sudo usermod -aG input $USER
```

3. Reboot or re-login for the changes to take effect

### Verification

Test that ydotool works:
```bash
ydotool type "Hello World"
```

## Installation

1. Copy this directory to your DMS plugins folder:
```bash
cp -r onscreenkeyboard ~/.config/DankMaterialShell/plugins/
```

2. Open DMS Settings → Plugins
3. Click "Scan for Plugins"
4. Enable "On-Screen Keyboard"
5. Add the OSK widget to your DankBar layout

## Usage

### Opening the Keyboard

- **From DankBar**: Click the OSK widget
- **From Control Center**: Toggle the "On-Screen Keyboard" control
- **Keyboard Shortcut**: Configure a custom shortcut in your system settings

### Keyboard Features

- **Regular Keys**: Tap to type
- **Shift**: Single tap for one capital letter
- **Caps Lock**: Double-tap Shift quickly
- **Modifiers**: Tap Ctrl/Alt to toggle (they stay pressed)
- **Function Keys**: F1-F12, Esc, Delete, Print Screen
- **Special Keys**: Tab, Enter, Backspace, Space

### Controls

- **Pin Button**: Keep keyboard visible when clicking elsewhere
- **Hide Button**: Close the keyboard and release all keys
- **Close Button**: Close the popout (keyboard state persists)

## Configuration

Access settings in DMS Settings → Plugins → On-Screen Keyboard:

- **Layout**: Choose your keyboard layout (currently US English)
- More layouts can be added by editing `layouts.js`

## Keyboard Layouts

The plugin currently supports:
- English (US) - QWERTY Full

To add more layouts, edit `layouts.js` following the existing structure.

## Troubleshooting

### Keys Not Working

1. **Check ydotool daemon**:
```bash
systemctl status ydotoold
```

2. **Check user permissions**:
```bash
groups $USER | grep input
```

3. **Test ydotool manually**:
```bash
ydotool key 30:1 30:0  # Should press 'a'
```

### Keyboard Not Showing

1. Ensure the plugin is enabled in Settings → Plugins
2. Check that the OSK widget is added to your DankBar layout
3. Look for errors in the console: `qs -v`

### Keys Stay Pressed

- Click the "Hide" button to release all keys
- The keyboard automatically releases all keys when closed

## Architecture

### Files

- `plugin.json` - Plugin manifest
- `OnScreenKeyboardWidget.qml` - Main widget component
- `OnScreenKeyboardSettings.qml` - Settings UI
- `OskContent.qml` - Keyboard layout renderer
- `OskKey.qml` - Individual key component
- `YdotoolService.qml` - ydotool integration service
- `layouts.js` - Keyboard layout definitions
- `README.md` - This file

### How It Works

1. The widget displays a keyboard icon in DankBar
2. Clicking opens a popout with the full keyboard
3. Key presses are sent via ydotool to the system
4. Modifier states (Shift, Caps, Ctrl, Alt) are tracked
5. All keys are released when the keyboard closes

## Contributing

To add keyboard layouts:

1. Edit `layouts.js`
2. Add a new layout following the existing structure
3. Use Linux keycodes from `/usr/include/linux/input-event-codes.h`
4. Test thoroughly with different key combinations

## License

This plugin is part of the DankMaterialShell ecosystem and follows the same license.

## Credits

Based on the on-screen keyboard implementation from the end4 reference shell, adapted for DankMaterialShell plugin architecture.

## Version History

- **1.0.0** - Initial release
  - English (US) QWERTY layout
  - ydotool integration
  - DankBar and Control Center support
  - Shift/Caps Lock functionality
  - Modifier key support
