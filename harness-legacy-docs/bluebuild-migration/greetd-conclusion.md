  Remove (3 pieces):
  - SDDM service + sddm system user creation script                                     
  - Autologin script that patches /etc/sddm.conf.d/scroll.conf at boot
  - Polkit rule for autologin.service
  - The .desktop file in /usr/share/wayland-sessions/ (optional, harmless to leave)

  Add (2 pieces):
  - greetd package + systemctl enable greetd
  - /etc/greetd/config.toml:
  [terminal]
  vt = 1

  [default_session]
  command = "niri-session"
  user = "yourusername"

  The default_session doubles as your autologin since there's no initial_session —
  greetd just runs it directly. On logout it re-runs the same command (auto-login loop),
   which is fine for single-user.
 
