# Pomodoro Advanced Plugin for DankMaterialShell

An advanced Pomodoro Technique timer plugin for DankMaterialShell (DMS) that helps you manage your focus time and breaks effectively.

## Features

- **Visual Timer Display**: Large, easy-to-read countdown timer with emoji indicators
- **Work/Break Cycles**: Automatic cycling between work periods (25 min) and breaks (5 min)
- **Pause & Resume**: Pause your timer and resume where you left off
- **Progress Tracking**: Visual progress bar showing completion percentage
- **DankBar Integration**: Shows current timer status in the bar with real-time updates
- **Control Center Integration**: Quick start/stop from the control center
- **Desktop Notifications**: Get notified when work/break periods start and end
- **Popout Interface**: Comprehensive timer management with controls and tips
- **Customizable Durations**: Configure work and break times via environment variables

## The Pomodoro Technique

The Pomodoro Technique is a time management method that uses a timer to break work into intervals:

1. **Focus Period** (25 min): Work on a single task with full focus
2. **Short Break** (5 min): Rest, stretch, or grab a drink
3. **Repeat**: After 4 pomodoros, take a longer break (15-30 min)

This plugin implements the core work/break cycle to help you stay productive and avoid burnout.

## Requirements

- DankMaterialShell 0.1.0 or higher
- Bash shell
- `notify-send` for desktop notifications (usually pre-installed)
- `date` and `stat` commands (standard on Linux)

## Installation

1. Copy the plugin folder to your DMS plugins directory:
   ```bash
   cp -r plugins/pomodoro-advanced ~/.config/DankMaterialShell/plugins/
   ```

2. Ensure the pomo script is executable:
   ```bash
   chmod +x ~/.config/DankMaterialShell/plugins/pomodoro-advanced/pomo
   ```

3. Open DMS Settings

4. Navigate to the Plugins tab

5. Click "Scan for Plugins" if the plugin doesn't appear

6. Enable the Pomodoro Advanced plugin with the toggle switch

7. Add the plugin to your DankBar configuration:
   - Go to Settings → Appearance → DankBar Layout
   - Add "pomodoro-advanced" to your desired section (left, center, or right)

## Configuration

### Timer Durations

You can customize the work and break durations using environment variables. Add these to your shell configuration file (e.g., `~/.bashrc`, `~/.zshrc`):

```bash
# Pomodoro work period in minutes (default: 25)
export POMO_WORK_TIME=25

# Pomodoro break period in minutes (default: 5)
export POMO_BREAK_TIME=5

# Optional: Custom location for timer state file
export POMO_FILE="$HOME/.local/share/pomo"
```

After changing these values, restart DMS for the changes to take effect.

### Recommended Settings

**Standard Pomodoro:**
- Work: 25 minutes
- Break: 5 minutes

**Short Sessions:**
- Work: 15 minutes
- Break: 3 minutes

**Extended Focus:**
- Work: 45 minutes
- Break: 10 minutes

## Usage

### DankBar Widget

The widget displays in your DankBar with:
- Timer emoji indicator (🍅 work, 🏖️ break, ⏸️ paused, ⏱️ stopped)
- Current time remaining (MM:SS format)
- Visual progress bar showing completion percentage

Click the widget to open the full control popout.

### Control Center

- Quick toggle to start/stop the timer
- Shows current phase and time remaining
- Active indicator when timer is running

### Popout Interface

The popout provides comprehensive timer management:

#### Timer Display
- Large countdown timer with minutes and seconds
- Phase indicator (Focus Time, Break Time, Paused, or Not running)
- Progress bar with percentage
- Color-coded display:
  - Blue: Work/Focus period
  - Green: Break period
  - Orange: Paused
  - Gray: Stopped

#### Control Buttons

**Start/Stop Button:**
- Green "Start" button when stopped
- Red "Stop" button when running
- Stops the current timer and resets

**Pause/Resume Button:**
- Visible only when timer is running
- Pause to interrupt your session
- Resume to continue where you left off
- Time is preserved when paused

**Restart Button:**
- Quick restart of the current timer
- Resets to a fresh work period
- Useful when you need to start over

#### Timer Settings

Displays your current configuration:
- Work time duration
- Break time duration
- Instructions for customization

#### Tips Section

Helpful reminders about the Pomodoro Technique:
- Focus on one task per work period
- Use breaks to rest and recharge
- Take longer breaks after 4 pomodoros

### Desktop Notifications

The timer sends notifications at key moments:
- **Timer Started**: "🍅 Pomodoro Started - Focus: 25m"
- **Work Complete**: "🏖️ Break Time! - Great work! Time for a break!"
- **Break Complete**: "🍅 Focus Time! - Break's over! Time to focus!"
- **Timer Paused**: "⏸️ Pomodoro Paused"
- **Timer Resumed**: "▶️ Pomodoro Resumed"
- **Timer Stopped**: "🛑 Pomodoro Stopped"

## How It Works

### Architecture

The plugin consists of several components:

1. **pomo (bash script)**: Core timer logic that manages state
   - File-based state storage in `~/.local/share/pomo`
   - Timestamp-based tracking for accuracy
   - JSON output for integration

2. **PomodoroService.qml**: Service layer for DMS
   - Communicates with the pomo script
   - Updates every second
   - Manages timer state and events

3. **PomodoroWidget.qml**: UI component
   - DankBar integration (horizontal and vertical)
   - Control Center quick toggle
   - Comprehensive popout interface

4. **plugin.json**: Plugin manifest with metadata

### State Management

The timer uses a file-based approach for persistence:
- Timer state stored in `~/.local/share/pomo`
- File modification time tracks when timer started
- File content stores pause state (seconds remaining)
- Survives DMS restarts and system reboots

### Timer Phases

The timer cycles through these phases:
1. **Work Phase**: Focus time (default 25 minutes)
2. **Break Phase**: Rest time (default 5 minutes)
3. **Cycle Repeat**: Automatically starts new work phase after break

The timer automatically transitions between phases and sends notifications.

## Command Line Usage

You can also control the timer from the command line:

```bash
# Get current status (JSON output)
~/.config/DankMaterialShell/plugins/pomodoro-advanced/pomo json

# Start a new pomodoro
~/.config/DankMaterialShell/plugins/pomodoro-advanced/pomo start

# Stop the timer
~/.config/DankMaterialShell/plugins/pomodoro-advanced/pomo stop

# Pause/Resume the timer
~/.config/DankMaterialShell/plugins/pomodoro-advanced/pomo pause

# Restart the timer
~/.config/DankMaterialShell/plugins/pomodoro-advanced/pomo restart
```

## Troubleshooting

### Plugin doesn't appear

- Ensure files are in: `~/.config/DankMaterialShell/plugins/pomodoro-advanced/`
- Check the pomo script is executable: `ls -l ~/.config/DankMaterialShell/plugins/pomodoro-advanced/pomo`
- Click "Scan for Plugins" in Settings → Plugins
- Check DMS console for errors

### Timer doesn't update

- Check if the pomo script runs: `~/.config/DankMaterialShell/plugins/pomodoro-advanced/pomo json`
- Verify bash is available: `which bash`
- Check file permissions on `~/.local/share/pomo`
- Restart DMS

### Notifications don't appear

- Verify notify-send is installed: `which notify-send`
- Test notifications: `notify-send "Test" "Message"`
- Check notification daemon is running
- On some systems, install `libnotify`: `sudo apt install libnotify-bin`

### Timer resets unexpectedly

- Don't manually edit or delete `~/.local/share/pomo` while timer is running
- Avoid changing `POMO_WORK_TIME` or `POMO_BREAK_TIME` while timer is active
- System time changes can affect the timer (NTP sync, timezone changes)

### Custom durations don't apply

- Environment variables must be set before starting DMS
- Add exports to your shell configuration file
- Restart DMS after changing variables
- Verify variables are set: `echo $POMO_WORK_TIME`

## Tips for Effective Use

### Getting Started

1. **Plan Your Task**: Before starting, decide what you'll work on
2. **Eliminate Distractions**: Close unnecessary apps, silence notifications
3. **Start the Timer**: Click the widget and press Start
4. **Focus**: Work on your task until the timer completes
5. **Take the Break**: When break time arrives, step away from your desk

### Best Practices

- **One Task Per Pomodoro**: Focus on a single task during work periods
- **Honor the Breaks**: Don't skip breaks, they're essential for productivity
- **Track Your Pomodoros**: Note how many pomodoros tasks take
- **Adjust as Needed**: If 25 minutes doesn't work, try different durations
- **Long Break Every 4**: After 4 work periods, take a 15-30 minute break

### Integration Ideas

- Use with your task management system
- Track completed pomodoros in a journal
- Set DMS to Do Not Disturb mode during work periods
- Pair with focus music or ambient sounds

## Development

### File Structure

```
pomodoro-advanced/
├── plugin.json           # Plugin manifest
├── pomo                  # Bash script (core timer logic)
├── PomodoroService.qml   # Service layer
├── PomodoroWidget.qml    # Widget UI component
└── README.md            # This file
```

### Extending the Plugin

The plugin is designed to be extensible. Potential enhancements:

- **Statistics Tracking**: Count completed pomodoros
- **Task Integration**: Link to task management apps
- **Custom Sounds**: Audio alerts for phase transitions
- **Focus Mode**: Auto-enable Do Not Disturb
- **Multiple Timers**: Support for different timer presets
- **History**: Track pomodoro completion over time
- **Goals**: Set daily pomodoro targets

## Contributing

This plugin is part of the DankMaterialShell ecosystem. Contributions, bug reports, and feature requests are welcome!

## License

Same as DankMaterialShell

## Credits

Based on the Pomodoro Technique developed by Francesco Cirillo.

Adapted from the rofi/waybar pomodoro implementation for DankMaterialShell integration.

## Related Resources

- [Pomodoro Technique Official Site](https://francescocirillo.com/pages/pomodoro-technique)
- [DankMaterialShell Documentation](https://github.com/DankMaterialShell/dms)
- [Time Management Resources](https://en.wikipedia.org/wiki/Pomodoro_Technique)

## Version History

### 1.0.0 (2025-01-11)
- Initial release
- Work/break cycle management
- Pause and resume functionality
- DankBar and Control Center integration
- Desktop notifications
- Customizable durations
- Progress tracking
- Comprehensive popout interface
