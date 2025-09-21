# Firefox Custom Configuration

## Installation Instructions

### Prerequisites
1. **Firefox Flatpak** must be installed:
   ```bash
   flatpak install flathub org.mozilla.firefox
   ```

2. **Authenticate to Google/Mozilla** (if needed):
   - Launch Firefox once to set up sync
   - Sign in to your Mozilla account
   - Close Firefox completely

3. **Run the setup script**:
   ```bash
   cd ~/.config/firefox-setup
   chmod +x setup-firefox.sh
   ./setup-firefox.sh
   ```

4. **Restart Firefox** to apply all changes

## Features

### 🎨 **Theme System**
- **Dark Mode**: Pure OLED black (#000000) for perfect blacks
- **Light Mode**: Transparent overlays with 80% opacity
- Automatic switching based on system preferences

### ⏰ **Minimal Clock Startpage**
- Clean, centered clock display
- Pure black background
- No distractions, just time
- Automatically set as homepage and new tab page

### 🖥️ **Two Profile System**

#### **Default Profile**
- One-line UI with tabs and URL bar on same line
- Minimal interface with keyboard navigation
- Clock startpage
- Container tabs support

#### **Webapp Profile**  
- **Complete UI removal** - no tabs, no URL bar, nothing
- Perfect for web apps (ChatGPT, Slack, Discord, etc.)
- Launch with: `flatpak run org.mozilla.firefox -P webapp --new-window URL`

### ⌨️ **Keyboard Navigation**
Essential shortcuts since navigation buttons are hidden:
- `Alt + ←/→` - Back/Forward
- `Ctrl + L` - Focus URL bar
- `Ctrl + T` - New tab
- `Ctrl + W` - Close tab
- `Ctrl + Shift + T` - Reopen closed tab
- `Ctrl + B` - Bookmarks sidebar
- `Ctrl + Tab` - Cycle tabs
- `F11` - Fullscreen

### 🖱️ **Chrome-like Scrolling**
- Smooth physics matching Chrome
- No overscroll bounce
- Fast, responsive scrolling

## Usage Examples

### Standard Browsing
```bash
# Launch with default profile
flatpak run org.mozilla.firefox
```

### Web Apps (No UI)
```bash
# ChatGPT as native app
flatpak run org.mozilla.firefox -P webapp --new-window https://chatgpt.com/

# Any other web app
flatpak run org.mozilla.firefox -P webapp --new-window https://discord.com/app
flatpak run org.mozilla.firefox -P webapp --new-window https://slack.com/
```

## Customization

### Modifying the Clock
Edit `clock.html` to customize:
- Font size: Change `font-size: 20vh` in the CSS
- Color: Modify `color: #ffffff`
- Format: Edit the JavaScript to add seconds, date, etc.

### Theme Colors
Edit `userChrome.css` and `userContent.css`:
- Dark mode colors in `@media (prefers-color-scheme: dark)`
- Light mode colors in `@media (prefers-color-scheme: light)`

### URL Bar Width
In `userChrome.css`, adjust:
```css
--uc-urlbar-min-width: 35vw;
--uc-urlbar-max-width: 35vw;
```

## Troubleshooting

### Clock not showing
- Ensure `clock.html` is in `~/.config/firefox-setup/`
- Check that the path is correct in `user.js`
- Restart Firefox after changes

### UI elements still visible
- Verify `toolkit.legacyUserProfileCustomizations.stylesheets` is `true` in `about:config`
- Ensure CSS files are in the correct `chrome/` directory
- Check you're using the right profile

### One-line layout not working
- Only activates on screens ≥1000px width
- Check window is maximized
- Verify CSS is loaded correctly

## File Locations

After setup, files are deployed to:
```
~/.var/app/org.mozilla.firefox/.mozilla/firefox/
├── default/
│   ├── chrome/
│   │   ├── userChrome.css
│   │   └── userContent.css
│   └── user.js
├── webapp/
│   ├── chrome/
│   │   ├── userChrome.css  # (webapp version)
│   │   └── userContent.css
│   └── user.js
└── profiles.ini
```

## Credits

Configuration consolidated from:
- [**Hypr**](https://github.com/JwpAT/hypr) - OLED black theme
- [**Cascade**](https://github.com/cascadefox/cascade) - One-line layout
- [**SimpleFox**](https://github.com/migueravila/simplefox) - Minimalist approach
- [**ff-chrome-folder**](https://github.com/steventheworker/ff-chrome-folder) - Various UI tweaks

## Firefox Minimal Clock Startpage Setup

### Clock Startpage Features
- **Pure minimalism**: Only shows time (HH:MM format)
- **Pure black background**: #000000 as requested
- **Optional date display**: Shows day and date below clock
- **Click interaction**: Click clock to toggle seconds display
- **Fade-in animation**: Smooth appearance on load
- **Responsive sizing**: Scales with viewport

## Customization Options

### Modify Clock Appearance
Edit `clock.html` to customize:
- Change font size: Adjust `font-size: clamp(10vh, 15vw, 20vh)`
- Hide date: Remove the `<div id="date"></div>` section
- Change colors: Modify `--clock-color` and `--bg-color` in CSS
- Add seconds by default: Change `showSeconds = false` to `true`

### Time Format Options
In clock.html JavaScript:
```javascript
// 12-hour format (uncomment to use)
// const hours = now.getHours() % 12 || 12;
// const ampm = now.getHours() >= 12 ? 'PM' : 'AM';
// document.getElementById('clock').textContent = `${hours}:${minutes} ${ampm}`;
```

## Troubleshooting

### Clock doesn't appear as new tab
- Firefox requires extensions to override new tab page
- Install the Custom New Tab Page extension mentioned above
- Or use `about:config` to set `browser.newtab.url` (may not work in newer Firefox)

### File path issues
The script automatically adjusts paths. If manual adjustment needed:
```bash
# Find your Firefox profile
find ~/.var/app/org.mozilla.firefox/.mozilla/firefox -name "*.default*"

# Edit user.js in that profile, change the path:
user_pref("browser.startup.homepage", "file:///YOUR/ACTUAL/PATH/clock.html");
```

### Dark/Light mode
The clock respects system theme by default. To force dark:
- Remove the `@media (prefers-color-scheme: light)` section from clock.html
