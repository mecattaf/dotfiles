# OCR Plugin for DankMaterialShell

A powerful Optical Character Recognition (OCR) plugin for DankMaterialShell that allows you to capture text from any region of your screen.

## Features

- **Area Selection**: Click to select any screen region for text recognition
- **Multi-Language Support**: Choose from multiple Tesseract language packs
- **Quick Access**: Right-click to change OCR language on the fly
- **Clipboard Integration**: Automatically copies recognized text to clipboard
- **Customizable**: Configure icon, label, and notification behavior
- **Visual Feedback**: Toast notifications for successful/failed operations

## Requirements

The following dependencies must be installed on your system:

- `grim` - Screenshot utility for Wayland
- `slurp` - Region selection tool for Wayland
- `tesseract` - OCR engine
- `wl-copy` - Wayland clipboard utility (from wl-clipboard package)
- `notify-send` - Desktop notification utility

### Installation on Arch Linux

```bash
sudo pacman -S grim slurp tesseract wl-clipboard libnotify
```

### Installing Additional Languages

To add support for more languages, install additional Tesseract language packs:

```bash
# Example: Install Spanish, French, and German
sudo pacman -S tesseract-data-spa tesseract-data-fra tesseract-data-deu
```

## Usage

### Basic Operation

1. **Left-click** the OCR widget in DankBar to start text recognition
2. Select a screen region by dragging your cursor
3. The recognized text is automatically copied to your clipboard
4. A notification confirms the operation status

### Language Selection

1. **Right-click** the OCR widget to open the language menu
2. Select your desired language from the list
3. The selected language will be saved for future use

## Configuration

Access settings via Settings → Plugins → OCR

### Available Settings

- **Default Language**: Choose the default OCR language (default: English)
- **Quiet Mode**: Disable notifications after OCR operations
- **Show Icon**: Display the OCR icon in the bar
- **Show Label**: Display the 'OCR' text label in the bar
- **Custom Icon**: Change the icon using Nerd Font characters

### Supported Languages (default)

- English (eng)
- Spanish (spa)
- French (fra)
- German (deu)
- Italian (ita)
- Portuguese (por)
- Chinese Simplified (chi_sim)
- Chinese Traditional (chi_tra)
- Japanese (jpn)
- Korean (kor)
- Russian (rus)
- Arabic (ara)
- Hindi (hin)

*Additional languages available through Tesseract language packs*

## Technical Details

### Plugin Architecture

- **Type**: Widget
- **Component**: OcrWidget.qml
- **Settings**: OcrSettings.qml
- **Script**: ocr.sh
- **Permissions**: settings_read, settings_write, process

### How It Works

1. The widget triggers the `ocr.sh` script with the selected language
2. Slurp launches to allow region selection with your cursor
3. Grim captures a screenshot of the selected area and pipes it to stdout
4. Tesseract processes the image and extracts text
5. The text is copied to the clipboard via wl-copy
6. A notification displays the operation result

### Script Options

The `ocr.sh` script supports the following options:

```bash
./ocr.sh [--no-notify] [--lang <tesseract_lang>]
```

- `--no-notify`: Suppress desktop notifications
- `--lang`: Specify the OCR language (default: eng)

## Troubleshooting

### Dependencies Not Found

If you receive a "Missing dependency" error:

1. Verify all required packages are installed
2. Ensure the commands are in your system PATH
3. Check that you're running a Wayland session (required for grim, slurp, and wl-copy)

### OCR Recognition Issues

- Ensure good contrast between text and background
- Use larger text areas for better accuracy
- Try different language packs if text is not in English
- Check that Tesseract is properly installed with language data

### Script Not Executable

If the OCR doesn't trigger:

```bash
chmod +x ~/.config/DankMaterialShell/plugins/ocr/ocr.sh
```

## Contributing

This plugin is part of the DankMaterialShell ecosystem. Contributions, bug reports, and feature requests are welcome!

## License

This plugin is distributed as part of DankMaterialShell dotfiles.

## Credits

- Original OCR implementation reference scripts
- DankMaterialShell plugin system
- Tesseract OCR engine
- grim and slurp screenshot utilities

## Version History

### 1.0.0 (Initial Release)
- Basic OCR functionality with area selection
- Multi-language support
- Clipboard integration
- Customizable appearance
- Settings interface
