#!/bin/bash

# Configuration - Flatpak uses a different path!
FIREFOX_BASE="$HOME/.var/app/org.mozilla.firefox/.mozilla/firefox"
CONFIG_DIR="$HOME/.config/firefox-setup"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

# Ensure Firefox directories exist
mkdir -p "$FIREFOX_BASE"

# First, let's check if there are existing profiles and back them up
if [[ -f "$FIREFOX_BASE/profiles.ini" ]]; then
    echo -e "${YELLOW}Backing up existing profiles.ini...${NC}"
    cp "$FIREFOX_BASE/profiles.ini" "$FIREFOX_BASE/profiles.ini.backup.$(date +%Y%m%d_%H%M%S)"
fi

# Find existing profile directories (usually has random string like abc123.default)
echo -e "${BLUE}Looking for existing profiles...${NC}"
EXISTING_DEFAULT=""
for dir in "$FIREFOX_BASE"/*.default* "$FIREFOX_BASE"/*.default-release*; do
    if [[ -d "$dir" ]]; then
        EXISTING_DEFAULT=$(basename "$dir")
        echo "Found existing profile: $EXISTING_DEFAULT"
        break
    fi
done

# Deploy clock.html startpage if it exists
if [[ -f "$CONFIG_DIR/clock.html" ]]; then
    echo -e "${GREEN}Clock startpage found${NC}"
else
    echo -e "${YELLOW}Warning: clock.html not found in $CONFIG_DIR${NC}"
    echo "The minimal clock startpage will not be available"
fi

# Fix the user.js path for clock.html
if [[ -f "$CONFIG_DIR/user.js" ]]; then
    sed -i "s|file:///home/.config/firefox-setup/clock.html|file://$CONFIG_DIR/clock.html|g" "$CONFIG_DIR/user.js"
fi

# Create or update profiles
echo -e "${YELLOW}Setting up Firefox profiles...${NC}"

# Setup default profile
if [[ -n "$EXISTING_DEFAULT" ]]; then
    echo "Using existing default profile: $EXISTING_DEFAULT"
    PROFILE_DEFAULT="$EXISTING_DEFAULT"
    PROFILE_DEFAULT_PATH="$FIREFOX_BASE/$EXISTING_DEFAULT"
else
    echo "Creating new default profile"
    PROFILE_DEFAULT="default"
    PROFILE_DEFAULT_PATH="$FIREFOX_BASE/default"
    mkdir -p "$PROFILE_DEFAULT_PATH"
fi

# Always create webapp profile
PROFILE_WEBAPP="webapp"
PROFILE_WEBAPP_PATH="$FIREFOX_BASE/webapp"
mkdir -p "$PROFILE_WEBAPP_PATH"

# Deploy files to both profiles
for profile_path in "$PROFILE_DEFAULT_PATH" "$PROFILE_WEBAPP_PATH"; do
    profile_name=$(basename "$profile_path")
    echo -e "${BLUE}Configuring profile: $profile_name${NC}"
    
    # Create chrome directory
    mkdir -p "$profile_path/chrome"
    
    # Deploy user.js (same for all profiles)
    if [[ -f "$CONFIG_DIR/user.js" ]]; then
        cp "$CONFIG_DIR/user.js" "$profile_path/"
        echo "  ✓ Deployed user.js"
    fi
    
    # Deploy profile-specific CSS
    if [[ "$profile_name" == "webapp" ]]; then
        # Webapp profile gets special CSS for native app mode
        if [[ -f "$CONFIG_DIR/userChrome-webapp.css" ]]; then
            cp "$CONFIG_DIR/userChrome-webapp.css" "$profile_path/chrome/userChrome.css"
            echo "  ✓ Deployed webapp userChrome.css"
        fi
    else
        # Default profile gets standard CSS
        if [[ -f "$CONFIG_DIR/userChrome.css" ]]; then
            cp "$CONFIG_DIR/userChrome.css" "$profile_path/chrome/"
            echo "  ✓ Deployed standard userChrome.css"
        fi
    fi
    
    # Deploy userContent.css to both
    if [[ -f "$CONFIG_DIR/userContent.css" ]]; then
        cp "$CONFIG_DIR/userContent.css" "$profile_path/chrome/"
        echo "  ✓ Deployed userContent.css"
    fi
done

# Write profiles.ini
echo -e "${YELLOW}Configuring profiles.ini...${NC}"
cat > "$FIREFOX_BASE/profiles.ini" << EOF
[Install4F96D1932A9F858E]
Default=$PROFILE_DEFAULT
Locked=1

[Profile0]
Name=default
IsRelative=1
Path=$PROFILE_DEFAULT

[Profile1]
Name=webapp
IsRelative=1
Path=webapp

[General]
StartWithLastProfile=0
Version=2
EOF

echo "profiles.ini written to: $FIREFOX_BASE/profiles.ini"

# Verify the deployment
echo -e "\n${BLUE}Verifying deployment...${NC}"
if [[ -f "$PROFILE_DEFAULT_PATH/chrome/userChrome.css" ]]; then
    echo "  ✓ Default profile CSS deployed"
else
    echo "  ✗ Default profile CSS missing"
fi

if [[ -f "$PROFILE_WEBAPP_PATH/chrome/userChrome.css" ]]; then
    echo "  ✓ Webapp profile CSS deployed"
else
    echo "  ✗ Webapp profile CSS missing"
fi

# Summary
echo -e "\n${GREEN}═══════════════════════════════════════${NC}"
echo -e "${GREEN}Firefox setup complete!${NC}"
echo -e "${GREEN}═══════════════════════════════════════${NC}"
echo -e "\nProfiles configured:"
echo -e "  • ${YELLOW}default${NC} ($PROFILE_DEFAULT) - Standard browsing with one-line UI & clock startpage"
echo -e "  • ${YELLOW}webapp${NC} - Native app mode (no UI)"
echo -e "\nFile locations:"
echo -e "  Firefox base: $FIREFOX_BASE"
echo -e "  Config files: $CONFIG_DIR"
if [[ -f "$CONFIG_DIR/clock.html" ]]; then
    echo -e "  Clock page: $CONFIG_DIR/clock.html"
fi
echo -e "\nUsage examples:"
echo -e "  ${YELLOW}flatpak run org.mozilla.firefox${NC} (uses default profile)"
echo -e "  ${YELLOW}flatpak run org.mozilla.firefox -P webapp --new-window https://chatgpt.com${NC}"
echo -e "\n${YELLOW}IMPORTANT:${NC}"
echo -e "1. Restart Firefox completely for changes to take effect"
echo -e "2. You may need to select the profile on first launch"
echo -e "3. Check about:config that toolkit.legacyUserProfileCustomizations.stylesheets = true"
