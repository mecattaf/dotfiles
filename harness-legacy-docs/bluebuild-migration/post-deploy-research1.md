




---




from niri arch linux docs

Starting
Niri comes with a desktop entry that can be sourced by display managers; selecting it will run niri-session which handles exporting environment variables to systemd.

Additionally you can start Niri from a getty by executing:

niri-session -l
This can be paired with auto login to have a seamless boot experience.


---

getty

Page
Discussion
Read
View source
View history

Tools
Appearance hide
Text

Small

Standard

Large
Width

Standard

Wide
Color (beta)

Automatic

Light

Dark

Related articles

Display manager
A getty is the generic name for a program which manages a terminal line and its connected terminal. Its purpose is to protect the system from unauthorized access. Generally, each getty process is started by systemd and manages a single terminal line.

Installation
agetty is the default getty in Arch Linux, as part of the util-linux package.

An alternative is mingettyAUR.

Tips and tricks
Staircase effect
agetty modifies the TTY settings while waiting for a login so that the newlines are not translated to CR-LFs. This tends to cause a "staircase effect" for messages printed to the console.

It is entirely harmless, but in the event it persists once logged, you can fix this behavior with:

$ stty onlcr
See this forums discussion on the subject.

Add additional virtual consoles
Agetty manages virtual consoles and six of these virtual consoles are provided by default in Arch Linux. They are usually accessible by pressing Ctrl+Alt+F1 through Ctrl+Alt+F6.

Open the file /etc/systemd/logind.conf and set the option NAutoVTs=6 to the number of virtual terminals that you want at boot.

If needed, it is possible to temporarily start a getty@ttyN.service service directly.

Automatic login to virtual console
Configuration relies on systemd unit drop-in files to override the default parameters passed to agetty.

Configuration differs for virtual versus serial consoles. In most cases, you want to set up automatic login on a virtual console, (whose device name is ttyN, where N is a number). The configuration of automatic login for serial consoles will be slightly different. Device names of the serial consoles look like ttySN, where N is a number.

Tip
Consider using greetd's auto-login feature. It will not auto-login a second time if the initial session exits, but will show a login screen instead.
Virtual console
Create a drop-in file for getty@tty1.service with the following contents:

/etc/systemd/system/getty@tty1.service.d/autologin.conf
[Service]
ExecStart=
ExecStart=-/sbin/agetty --noreset --noclear --autologin username - ${TERM}
Tip
The option Type=idle found in the default getty@.service will delay the service startup until all jobs (state change requests to units) are completed in order to avoid polluting the login prompt with boot-up messages. When starting X automatically, it may be useful to start getty@tty1.service immediately by adding Type=simple into the drop-in file. Both the init system and startx can be silenced to avoid the interleaving of their messages during boot-up.
See Silent boot#agetty for an example virtual console drop-in file which hides the login prompt completely.
The above snippet will cause the loginctl session type to be set to tty. If desirable (for example if starting X automatically), it is possible to manually set the session type to wayland or x11 by adding Environment=XDG_SESSION_TYPE=x11 or Environment=XDG_SESSION_TYPE=wayland into this file.
If you do not want full automatic login, but also do not want to type your username, see #Prompt only the password for a default user in virtual console login.

If you want to use a tty other than tty1, see systemd/FAQ#How do I change the default number of gettys?.

Serial console
Create a drop-in file:

/etc/systemd/system/serial-getty@ttyS0.service.d/autologin.conf
[Service]
ExecStart=
ExecStart=-/sbin/agetty --noreset --noclear --autologin username --keep-baud 115200,57600,38400,9600 - ${TERM}
Nspawn console
To configure auto-login for a systemd-nspawn container, override console-getty.service by creating a drop-in file:

/etc/systemd/system/console-getty.service.d/autologin.conf
[Service]
ExecStart=
ExecStart=-/sbin/agetty --noreset --noclear --autologin username --keep-baud 115200,57600,38400,9600 - ${TERM}
If machinectl login my-container method is used to access the container, also adjust the container-getty@.service template that manages pts/[0-9] pseudo ttys:

/etc/systemd/system/container-getty@.service.d/autologin.conf
[Service]
ExecStart=
ExecStart=-/sbin/agetty --noreset --noclear --autologin username - ${TERM}
Prompt only the password for a default user in virtual console login
Getty can be used to login from a virtual console with a default user, typing the password but without needing to insert the username. For instance, to prompt the password for username on tty1:

/etc/systemd/system/getty@tty1.service.d/skip-username.conf
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -- username' --noclear --skip-login - $TERM
Have boot messages stay on tty1
By default, Arch has the getty@tty1 service enabled. The service file already passes --noclear, which stops agetty from clearing the screen. However systemd clears the screen before starting it. To disable this behavior, create a drop-in file:

/etc/systemd/system/getty@tty1.service.d/noclear.conf
[Service]
TTYVTDisallocate=no
Note
Make sure to remove quiet from the kernel parameters.
Late KMS starting may cause the first few boot messages to clear. See Kernel mode setting#Early KMS start.
Turn off display after timeout
This article or section is a candidate for merging with Display Power Management Signaling#Linux console.

Notes: This tip is essentially about the console blanking, and we have dedicated section on it. (Discuss in Talk:Getty)
When the system is used as a server but has a display connected, the display will be turned on forever. To turn off display after 5 minutes create a drop-in file. On any key press, display will turn back on.

/etc/systemd/system/getty@tty1.service.d/blankscreen.conf
[Service]
ExecStartPost=-/usr/bin/setterm --blank 5
See also
systemd#Change default target to boot into
The TTY demystified
---

greetd

Page
Discussion
Read
View source
View history

Tools
Appearance hide
Text

Small

Standard

Large
Width

Standard

Wide
Color (beta)

Automatic

Light

Dark

Related articles

Display manager
Wayland
Sway
greetd is a minimal, agnostic and flexible login manager daemon which does not make assumptions about what the user wants to launch, should it be console-based or graphical. Any script or program which can be started from the console may be launched by greetd, which makes it particularly suitable for Wayland compositors. It can also launch a greeter to start user sessions, like any other display manager.

Installation
Install the greetd or greetd-gitAUR packages.

The default greetd configuration file is located at /etc/greetd/config.toml. PAM-specific configuration is set in /etc/pam.d/greetd.

Greeters
Greetd has greetd-agreety as its built-in greeter, however this is a minimal implementation. You should consider using one of the several available greeters:

greetd-agreety — The default, a text-based greeter similar to agetty.
https://git.sr.ht/~kennylevinsen/greetd || greetd-agreety
cosmic-greeter — A libcosmic greeter.
https://github.com/pop-os/cosmic-greeter || cosmic-greeter
dlm — An fbdev greeter.
https://git.sr.ht/~kennylevinsen/dlm || greetd-dlm-gitAUR
ddlm — An fbdev greeter. Enhanced/extended version of dlm.
https://github.com/deathowl/ddlm || greetd-ddlm-gitAUR
gtkgreet — A GTK greeter.
https://git.sr.ht/~kennylevinsen/gtkgreet || greetd-gtkgreet, greetd-gtkgreet-gitAUR
ReGreet — A GTK greeter. Supports various customization options. Wayland only.
https://github.com/rharish101/ReGreet || greetd-regreet, greetd-regreet-gitAUR
wlgreet — A Wayland greeter.
https://git.sr.ht/~kennylevinsen/wlgreet || greetd-wlgreetAUR, greetd-wlgreet-gitAUR
tuigreet — A console UI greeter.
https://github.com/apognu/tuigreet || greetd-tuigreet
qtgreet — A Qt greeter.
https://gitlab.com/marcusbritanicus/QtGreet || greetd-qtgreetAUR
nwg-hello — GTK3-based greeter for greetd written in python.
https://github.com/nwg-piotr/nwg-hello || nwg-hello
sysc-greet — A TUI ASCII greeter written in Go.
https://github.com/Nomadcxx/sysc-greet || sysc-greetAUR
Starting greetd
Enable greetd.service so greetd will be started at boot.

See also Display manager#Loading the display manager.

Greeter configuration
Configuring the greeter run by greetd is done using the command option in the default_session section in /etc/greetd/config.toml. The included agreety greeter will be used if no changes are made. Also see #agreety.

By default, greeters are run as the greeter user. This can be changed by editing the user option in the default_session section of the configuration file and replacing another_user with the chosen user:

...
[default_session]
user = "another_user"
...
Make sure the ownership of the /etc/greetd directory is set accordingly.

agreety
This is the default greeter. It is launched by greetd with the configuration file set as follows:

...
[default_session]
command = "agreety --cmd $SHELL"
...
agreety can launch any arbitrary command once a user logs in. For example, in order to start Sway, replace $SHELL in the example above with sway.

gtkgreet
In order to run, gtkgreet needs a compositor. For the full experience, a compositor with wlr-layer-shell-unstable support is required but others can work. As such, it is recommended to use sway, but something like cage can also be used. Examples for both cage and sway are provided below.

In order to specify which login environments can be started by gtkgreet, list them in /etc/greetd/environments. For example:

sway
bash
You can also invoke gtkgreet with the -c mycommand parameter, replacing mycommand with the desired program (for example, gtkgreet -c bash or gtkgreet -c sway). Do so in the below compositor examples as desired.

Using cage
Install cage and set the command option as follows:

...
[default_session]
command = "cage -s -- gtkgreet"
...
The -s argument enables VT switching in cage (0.1.2 and newer only), which is highly recommended to prevent locking yourself out.

Using sway
Install sway. When using Sway, it must be terminated once the user logs in. For that purpose, a specific configuration file must be created, for example in /etc/greetd/sway-config, with the following content:

# `-l` activates layer-shell mode. Notice that `swaymsg exit` will run after gtkgreet.
exec "gtkgreet -l; swaymsg exit"

bindsym Mod4+shift+e exec swaynag \
-t warning \
-m 'What do you want to do?' \
-b 'Poweroff' 'systemctl poweroff' \
-b 'Reboot' 'systemctl reboot'

include /etc/sway/config.d/*
Then, greetd must be set to start Sway with the configuration file above. Set the command option as follows:

...
[default_session]
command = "sway --config /etc/greetd/sway-config"
...
ReGreet
Similar to gtkgreet, ReGreet needs a compositor. For example, both Cage and Sway can be used just like they are used for gtkgreet, replacing the gtkgreet command with regreet. The config for Sway would thus look like:

# Notice that `swaymsg exit` will run after ReGreet.
exec "regreet; swaymsg exit"

bindsym Mod4+shift+e exec swaynag \
-t warning \
-m 'What do you want to do?' \
-b 'Poweroff' 'systemctl poweroff' \
-b 'Reboot' 'systemctl reboot'

include /etc/sway/config.d/*
ReGreet picks up available sessions from /usr/share/xsession (for X11 sessions) and /usr/share/wayland-sessions (for Wayland sessions). Thus, there is no need to list sessions in /etc/greetd/environments.

ReGreet can be configured through a TOML file in /etc/greetd/regreet.toml. A sample file is provided in /usr/share/doc/greetd-regreet/regreet.sample.toml with all available options. Copy this to /etc/greetd/regreet.toml and make the changes you want, commenting out or deleting the lines you do not need. Any invalid options are ignored.

Using Hyprland
Set the command option as follows:

...
[default_session]
command = "start-hyprland -- -c /etc/greetd/hyprland.conf"
...
Then create /etc/greetd/hyprland.conf as:

/etc/greetd/hyprland.conf
exec-once = regreet; hyprctl dispatch exit
wlgreet
In order to start wlgreet, a compositor with wlr-layer-shell-unstable is required. Follow the steps required to set up gtkgreet with Sway as described above but use the following for /etc/greetd/sway-config instead:

exec "wlgreet --command sway; swaymsg exit"

bindsym Mod4+shift+e exec swaynag \
-t warning \
-m 'What do you want to do?' \
-b 'Poweroff' 'systemctl poweroff' \
-b 'Reboot' 'systemctl reboot'
 
include /etc/sway/config.d/*
tuigreet
tuigreet does not require any special setup. Set the command option as follows, replacing sway if you use a different desktop environment/window manager:

...
[default_session]
command = "tuigreet --cmd sway"
...
tuigreet --help will display customization options.

ddlm
ddlm does not require any special setup, just set the command option as follows, replacing sway if you use a different desktop environment/window manager:

...
[default_session]
command = "ddlm --target sway"
...
qtgreet
In order to use qtgreet, you need a WLR based compositor (e.g. wayfireAUR, sway).

Using Wayfire
Install wayfireAUR and set the command option as follows:

...
[default_session]
command = "wayfire --config /etc/qtgreet/wayfire.ini"
...
The Wayfire configuration file referred to is included with qtgreet.

Using Hyprland
Set the command option as follows:

...
[default_session]
command = "start-hyprland -- -c /etc/greetd/hyprland.conf"
...
Then create /etc/greetd/hyprland.conf as:

/etc/greetd/hyprland.conf
exec-once = qtgreet; hyprctl dispatch exit
nwg-hello
In order to use nwg-hello, you either need sway or hyprland.

Using Sway
Install sway and set the command option as follows:

...
[default_session]
command = "sway -c /etc/nwg-hello/sway-config"
...
The Sway configuration file referred to is included with nwg-hello.

Using Hyprland
Install hyprland and set the command option as follows:

...
[default_session]
command = "start-hyprland -- -c /etc/nwg-hello/hyprland.conf"
...
The Hyprland configuration file referred to is included with nwg-hello.

Tips and tricks
Enabling autologin
If you want a user to be logged in automatically, an initial_session section must be defined in /etc/greetd/config.toml:

...
[initial_session]
command = "sway"
user = "myuser"
...
The command option may contain the name of any executable file. In the example above, Sway will be started by myuser at boot.

If you do not want to use greetd and always want autologin to be enabled, see autologin.

Unlocking keyring on autologin using the cryptsetup password
Autologin is often used on a single-user system with full disk encryption. Both GNOME/Keyring and KDE Wallet can be unlocked using the encryption password entered at boot. In the case of other display managers, this typically requires an entry such as auth optional pam_systemd_loadkey.so, auth optional pam_gdm.so, or similar, in the PAM config.

However, this setup does not work with greetd because it skips the auth stack entirely. Instead, use the pam_fde_boot_pw module (currently not packaged and not in AUR).

After installing the module to /usr/local/lib/security/pam_fde_boot_pw.so, use the following PAM config. Substitute inject_for=gkr (GNOME Keyring) with inject_for=kwallet5 for KDE Wallet.

/etc/pam.d/greetd
#%PAM-1.0
 
auth       required     pam_securetty.so
auth       requisite    pam_nologin.so
auth       include      system-local-login
account    include      system-local-login
session    optional     /usr/local/lib/security/pam_fde_boot_pw.so inject_for=gkr
session    include      system-local-login
session    optional     pam_gnome_keyring.so auto_start
Run local programs
Add the PATH environment variable to ~/.profile, or the desktop environment called by greetd will not be able to run local programs. Greetd will not source shell configuration files and thus not get any modified variables from these files.

~/.profile
export PATH="$HOME/.local/bin:$PATH"
Setting the Environment
By default greetd does not set environment variables such as XDG_SESSION_TYPE and XDG_CURRENT_DESKTOP, unless the greeter sets them based on the session you chose (for example TUI will set the session type based on the location of the session file chosen). One way to solve this is to use a wrapper script that sets any desired environment variables before running the actual command. For example to start sway:

/usr/local/bin/start-sway
#!/bin/sh
export XDG_SESSION_TYPE=wayland
export XDG_SESSION_DESKTOP=sway
export XDG_CURRENT_DESKTOP=sway

# Wayland stuff
export QT_QPA_PLATFORM=wayland
export SDL_VIDEODRIVER=wayland
export _JAVA_AWT_WM_NONREPARENTING=1

exec sway "$@"
then use this wrapper script as the command the greeter runs. For example with gtkgreet you could use

/etc/greetd/config.toml
...
[default_session]
command = "gtkgreet -c /usr/local/bin/start-sway"
...
or put start-sway in /etc/greetd/environments.

See How to Set XDG_SESSION_TYPE=wayland

Setting logind session type
Note
This is necessary for running GNOME on Wayland properly.
The logind session type is set by the XDG_SESSION_TYPE environment variable. However, it must be set before the PAM session is opened. Because of this, setting the variable through ~/.profile or a wrapper script will not work (both happen after session open).

The correct way to achieve this is through the environment variables sent by greeters (these are set before session open). So if your greeter supports it, just make it send the appropriate XDG_SESSION_TYPE=xxx.

If your greeter does not support this, it is also possible to use pam_env under the auth group. The drawback is that all the sessions spawned by greetd will use that session type, which may or may not be problematic depending on your use case.

Here is how one could use the pam_env method to have a Wayland session:

/etc/greetd/config.toml
[general]
service = "greetd-spawn"
/etc/greetd/greetd-spawn.pam_env.conf
XDG_SESSION_TYPE DEFAULT=wayland OVERRIDE=wayland
/etc/pam.d/greetd-spawn
auth       include      greetd
auth       required     pam_env.so conffile=/etc/greetd/greetd-spawn.pam_env.conf
account    include      greetd
session    include      greetd
Missing mouse cursor
If you are using qtgreet with a compositor such as wayfire and generally need to export variables, such as WLR_NO_HARDWARE_CURSORS=1 to get the mouse cursor working, one solution would be to create a separate executable script and then calling that from /etc/greetd/config.toml.

/usr/local/bin/greetd-startup.sh
#!/bin/sh
export WLR_NO_HARDWARE_CURSORS=1
exec wayfire --config /etc/qtgreet/wayfire.ini
/etc/greetd/config.toml
...
[default_session]
command = "/usr/local/bin/greetd-startup.sh"
...
Prevent systemd messages from overwriting console-based greeterd
If you are using console-based greeters such as tuigreet systemd messages can overwrite UI. To prevent this you may use console=quiet kernel parameter as it prevents display of any messages (also during boot).

If you still would like to see messages during boot, you could instead append console=tty1 to kernel parameters. This would redirect all messages from /dev/console (which broadcasts to all ttys) to /dev/tty1, which is utilized during boot. Now you just need to select any other TTY for greeter. Either specify particular tty (other than tty1) or use next option.

/etc/greetd/config.toml
...
vt = "next"
...
See also
greetd project page
greetd source code
greetd wiki
Category: Display managers
