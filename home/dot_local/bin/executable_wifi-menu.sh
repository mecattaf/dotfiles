#!/usr/bin/env bash

# wifi-menu.sh - A rofi-based network menu using iwmenu
# Uses custom black Catppuccin theme with Mauve accent

# Define Catppuccin custom colors
BG="#000000"       # Base (modified black)
BG_ALT="#010101"   # Mantle (modified black)
BG_DARKER="#020202" # Crust (modified black)
FG="#cdd6f4"       # Text
ACCENT="#cba6f7"   # Mauve
RED="#f38ba8"      # Red

# Check if iwmenu is installed
if ! command -v iwmenu &> /dev/null; then
    echo "iwmenu is not installed. Please install it first."
    echo "Visit: https://github.com/e-tho/iwmenu for installation instructions."
    exit 1
fi

# Define rofi theme with custom Catppuccin black variant
ROFI_THEME="window { \
    background-color: ${BG}; \
    border: 4px solid; \
    border-color: ${ACCENT}; \
    border-radius: 0px; \
} \
mainbox { background-color: ${BG}; } \
inputbar { background-color: ${BG}; } \
entry { background-color: ${BG}; text-color: ${FG}; } \
element { padding: 12px; background-color: ${BG_DARKER}; border: 4px solid; border-color: ${BG_DARKER}; border-radius: 0px; } \
element-text { background-color: inherit; text-color: ${FG}; } \
element selected.normal { background-color: ${ACCENT}; text-color: ${BG}; }"

# Use rofi as the launcher for iwmenu with the custom theme
iwmenu --launcher rofi \
    --launcher-command "rofi -dmenu -i -show-icons -theme-str '${ROFI_THEME}'" \
    --icon xdg

# Exit status
exit $?
