#!/bin/bash

# Configuration
FIREFOX_BASE="$HOME/.var/app/org.mozilla.firefox/.mozilla/firefox"
CONFIG_DIR="$HOME/.config/firefox-setup"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if Firefox Flatpak is installed
if ! flatpak list | grep -q "org.mozilla.firefox"; then
    echo -e "${RED}Error: Firefox Flatpak is not installed${NC}"
    echo "Install with: flatpak install flathub org.mozilla.firefox"
    exit 1
fi

echo -e "${GREEN}Firefox Flatpak detected${NC}"

# Create config directory if it doesn't exist
mkdir -p "$CONFIG_DIR"

# Deploy clock.html startpage if it exists
if [[ -f "$CONFIG_DIR/clock.html" ]]; then
    echo -e "${GREEN}Clock startpage found${NC}"
    # Update the path in user.js to use the correct location
    sed -i "s|file:///home/.config/firefox-setup/clock.html|file://$CONFIG_DIR/clock.html|g" "$CONFIG_DIR/user.js"
else
    echo -e "${YELLOW}Warning: clock.html not found in $CONFIG_DIR${NC}"
    echo "The minimal clock startpage will not be available"
fi

# Create profiles
echo -e "${YELLOW}Creating Firefox profiles...${NC}"
for profile in default webapp work; do
    if [[ ! -d "$FIREFOX_BASE/$profile" ]]; then
        echo "Creating profile: $profile"
        flatpak run --command=firefox org.mozilla.firefox -headless \
            -CreateProfile "$profile $FIREFOX_BASE/$profile"
    else
        echo "Profile already exists: $profile"
    fi
    
    # Create chrome directory for each profile
    mkdir -p "$FIREFOX_BASE/$profile/chrome"
    
    # Deploy user.js (same for all profiles)
    if [[ -f "$CONFIG_DIR/user.js" ]]; then
        cp "$CONFIG_DIR/user.js" "$FIREFOX_BASE/$profile/"
        echo "  ✓ Deployed user.js to $profile"
    fi
    
    # Deploy profile-specific CSS
    if [[ "$profile" == "webapp" ]]; then
        # Webapp profile gets special CSS for native app mode
        if [[ -f "$CONFIG_DIR/userChrome-webapp.css" ]]; then
            cp "$CONFIG_DIR/userChrome-webapp.css" "$FIREFOX_BASE/$profile/chrome/userChrome.css"
            echo "  ✓ Deployed webapp userChrome.css to $profile"
        fi
        if [[ -f "$CONFIG_DIR/userContent.css" ]]; then
            cp "$CONFIG_DIR/userContent.css" "$FIREFOX_BASE/$profile/chrome/userContent.css"
            echo "  ✓ Deployed userContent.css to $profile"
        fi
    else
        # Default and work profiles get standard CSS
        if [[ -f "$CONFIG_DIR/userChrome.css" ]]; then
            cp "$CONFIG_DIR/userChrome.css" "$FIREFOX_BASE/$profile/chrome/"
            echo "  ✓ Deployed standard userChrome.css to $profile"
        fi
        if [[ -f "$CONFIG_DIR/userContent.css" ]]; then
            cp "$CONFIG_DIR/userContent.css" "$FIREFOX_BASE/$profile/chrome/"
            echo "  ✓ Deployed userContent.css to $profile"
        fi
    fi
done

# Write profiles.ini
echo -e "${YELLOW}Configuring profiles.ini...${NC}"
cat > "$FIREFOX_BASE/profiles.ini" << EOF
[Profile0]
Name=default
IsRelative=1
Path=default
Default=1

[Profile1]
Name=webapp
IsRelative=1
Path=webapp

[Profile2]
Name=work
IsRelative=1
Path=work

[General]
StartWithLastProfile=1
Version=2
EOF

# Summary
echo -e "\n${GREEN}═══════════════════════════════════════${NC}"
echo -e "${GREEN}Firefox setup complete!${NC}"
echo -e "${GREEN}═══════════════════════════════════════${NC}"
echo -e "\nProfiles created:"
echo -e "  • ${YELLOW}default${NC} - Standard browsing with one-line UI & clock startpage"
echo -e "  • ${YELLOW}webapp${NC} - Native app mode (no UI)"
echo -e "  • ${YELLOW}work${NC} - Work browsing with one-line UI & clock startpage"
echo -e "\nStartpage:"
if [[ -f "$CONFIG_DIR/clock.html" ]]; then
    echo -e "  • ${GREEN}Minimal clock startpage installed${NC}"
    echo -e "    Location: $CONFIG_DIR/clock.html"
else
    echo -e "  • ${YELLOW}Clock startpage not found${NC}"
    echo -e "    Add clock.html to: $CONFIG_DIR/"
fi
echo -e "\nUsage examples:"
echo -e "  ${YELLOW}flatpak run org.mozilla.firefox${NC} (uses default profile)"
echo -e "  ${YELLOW}flatpak run org.mozilla.firefox -P webapp --new-window URL${NC}"
echo -e "  ${YELLOW}flatpak run org.mozilla.firefox -P work${NC}"
echo -e "\nDesktop launchers available in your applications menu"
