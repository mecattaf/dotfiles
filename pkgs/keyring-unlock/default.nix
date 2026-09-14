{ writers, python3Packages }:
# keyring-unlock — unlock the headless coordinator's gnome-keyring without a
# GUI prompt. The coordinator boots with no login (the 2026-09-11 headless
# decision), so nothing unlocks Default_Keyring; the browser desktop's Chrome
# then waits on a keyring prompt over noVNC. From the client:
#   ssh -t coordinator keyring-unlock
# The password is read from the tty (or stdin), never argv, and passed to
# gnome-keyring's UnlockWithMasterPassword on the session bus. Exit 0 only when
# the collection reports Locked=false. throwaway_test.py proves wrong/right/
# idempotent on a disposable collection without touching the real keyring
# (run 2026-09-14: wrong -> rc 1 still locked; right -> rc 0 unlocked).
writers.writePython3Bin "keyring-unlock" {
  libraries = [ python3Packages.jeepney ];
  flakeIgnore = [ "E501" "E401" "E701" "E702" "E731" ];
} (builtins.readFile ./keyring_unlock.py)
