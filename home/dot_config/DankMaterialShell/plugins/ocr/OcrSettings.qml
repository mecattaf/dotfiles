import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "ocr"

    Column {
        width: parent.width
        spacing: Theme.spacingL

        StyledText {
            width: parent.width
            text: "OCR Settings"
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Font.Bold
            color: Theme.surfaceText
        }

        StyledText {
            width: parent.width
            text: "Configure optical character recognition behavior and appearance"
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
        }

        // Language Selection
        SelectionSetting {
            settingKey: "language"
            label: "Default Language"
            description: "Select the default OCR language (Tesseract)"
            options: [
                {label: "English", value: "eng"},
                {label: "Spanish", value: "spa"},
                {label: "French", value: "fra"},
                {label: "German", value: "deu"},
                {label: "Italian", value: "ita"},
                {label: "Portuguese", value: "por"},
                {label: "Chinese (Simplified)", value: "chi_sim"},
                {label: "Chinese (Traditional)", value: "chi_tra"},
                {label: "Japanese", value: "jpn"},
                {label: "Korean", value: "kor"},
                {label: "Russian", value: "rus"},
                {label: "Arabic", value: "ara"},
                {label: "Hindi", value: "hin"}
            ]
            defaultValue: "eng"
        }

        // Quiet Mode Toggle
        ToggleSetting {
            settingKey: "quietMode"
            label: "Quiet Mode"
            description: "Disable notifications after OCR operations"
            defaultValue: false
        }

        StyledText {
            width: parent.width
            text: "Appearance"
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.Bold
            color: Theme.surfaceText
        }

        // Show Icon Toggle
        ToggleSetting {
            settingKey: "showIcon"
            label: "Show Icon"
            description: "Display the OCR icon in the bar"
            defaultValue: true
        }

        // Show Label Toggle
        ToggleSetting {
            settingKey: "showLabel"
            label: "Show Label"
            description: "Display the 'OCR' text label in the bar"
            defaultValue: true
        }

        // Custom Icon
        StringSetting {
            settingKey: "customIcon"
            label: "Custom Icon"
            description: "Enter a Nerd Font icon (e.g., 󰕸)"
            placeholder: "󰕸"
            defaultValue: "󰕸"
        }

        StyledText {
            width: parent.width
            text: "Usage"
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.Bold
            color: Theme.surfaceText
        }

        StyledText {
            width: parent.width
            text: "• Left-click: Start OCR area selection\n• Right-click: Choose OCR language\n\nRequired dependencies: grim, slurp, tesseract, wl-copy"
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
            lineHeight: 1.5
        }
    }
}
