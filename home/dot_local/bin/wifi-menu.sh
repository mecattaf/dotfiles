#!/usr/bin/env bash
# wifi-menu.sh -- rofi wifi menu using iwmenu (no quickshell IPC)

BG="#000000"
BG_ALT="#010101"
BG_DARKER="#020202"
FG="#cdd6f4"
ACCENT="#cba6f7"
RED="#f38ba8"

if ! command -v iwmenu &> /dev/null; then
    echo "iwmenu is not installed. Please install it first."
    echo "Visit: https://github.com/e-tho/iwmenu for installation instructions."
    exit 1
fi

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

iwmenu --launcher rofi \
    --launcher-command "rofi -dmenu -i -show-icons -theme-str '${ROFI_THEME}'" \
    --icon xdg

exit $?
