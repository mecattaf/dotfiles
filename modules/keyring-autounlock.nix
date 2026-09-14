{ config, lib, pkgs, ... }:
# Automatic gnome-keyring unlock on the headless coordinator (Tom, 2026-09-14:
# "prefer NOT having to type pwd at all").
#
# The coordinator boots with no login, so nothing unlocks Default_Keyring and
# the browser desktop's Chrome waits on a prompt. Instead the keyring password
# is sealed ONCE to this board's TPM2 with systemd-creds, bound to PCR 7
# (firmware / Secure Boot state — stable across kernel and NixOS updates on
# systemd-boot), and a boot oneshot decrypts it and feeds it to keyring-unlock.
#
# Threat model: the sealed file is useless off this board (a stolen or imaged
# disk cannot unseal it) and the secret never enters the Nix store. Anyone
# with root, or physical access to boot the box, gets the keyring unlocked —
# the same boundary the unencrypted root already sets. A firmware or Secure
# Boot change breaks the seal: the keyring then stays LOCKED (fail safe), and
# `keyring-seal` once more re-arms it. Manual fallback, always:
#   ssh -t coordinator keyring-unlock
#
# Setup / re-seal (verifies itself end to end; restores on failure):
#   sudo keyring-seal            # reads the password silently from the tty
#   sudo keyring-seal FILE       # or from a 0600 file
let
  cred = "/etc/credstore.encrypted/keyring-password.cred";
  user = "tom";
  unlockAsUser = ''
    uid="$(id -u ${user})"
    runuser -u ${user} -- env DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" ${pkgs.keyring-unlock}/bin/keyring-unlock "$@"
  '';
  keyring-seal = pkgs.writeShellApplication {
    name = "keyring-seal";
    runtimeInputs = [ pkgs.coreutils pkgs.diffutils pkgs.util-linux config.systemd.package ];
    text = ''
      [ "$(id -u)" = 0 ] || { echo "keyring-seal: run as root (sudo keyring-seal)" >&2; exit 2; }
      u() { ${unlockAsUser} }
      tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
      umask 077
      if [ $# -ge 1 ]; then
        input="$1"
      else
        read -rsp "keyring password: " pw; echo
        printf '%s' "$pw" > "$tmp/pw"; unset pw
        input="$tmp/pw"
      fi
      install -d -m 0700 /etc/credstore.encrypted
      systemd-creds encrypt --with-key=tpm2 --tpm2-pcrs=7 --name=keyring-password "$input" "$tmp/new.cred"
      if ! systemd-creds decrypt --name=keyring-password "$tmp/new.cred" - | cmp -s - "$input"; then
        echo "keyring-seal: TPM round trip did not reproduce the input; nothing changed" >&2; exit 2
      fi
      [ -e ${cred} ] && cp -p ${cred} "$tmp/old.cred"
      install -m 0600 "$tmp/new.cred" ${cred}
      # Prove the real boot path: lock the keyring, run the boot unit, check.
      if ! u --lock >/dev/null; then
        echo "keyring-seal: could not lock the keyring to verify; sealed file kept, NOT verified" >&2; exit 2
      fi
      systemctl reset-failed keyring-unlock-boot.service 2>/dev/null || true
      if systemctl restart keyring-unlock-boot.service && u --status >/dev/null; then
        echo "keyring-seal: sealed to this TPM (PCR 7); the boot unit unlocked the keyring. Nothing to type at boot."
        exit 0
      fi
      if [ -e "$tmp/old.cred" ]; then install -m 0600 "$tmp/old.cred" ${cred}; else rm -f ${cred}; fi
      echo "keyring-seal: that password did not unlock the keyring; previous state restored and the keyring is LOCKED." >&2
      echo "keyring-seal: unlock by hand with: keyring-unlock" >&2
      exit 1
    '';
  };
in
{
  environment.systemPackages = [ keyring-seal ];

  systemd.services.keyring-unlock-boot = {
    description = "Unlock tom's gnome-keyring from the TPM-sealed password";
    wantedBy = [ "multi-user.target" ];
    wants = [ "user@1000.service" ];
    after = [ "user@1000.service" ];
    unitConfig.ConditionPathExists = cred;
    path = [ pkgs.coreutils pkgs.util-linux ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = "180s";
      LoadCredentialEncrypted = "keyring-password:${cred}";
    };
    # The keyring daemon is D-Bus activated inside tom's lingering user
    # session; retry until that bus answers. rc 1 = the sealed password was
    # rejected (stop, stay locked); rc 2 = bus or service not up yet (retry).
    script = ''
      u() { ${unlockAsUser} }
      for _ in $(seq 60); do
        rc=0; u < "$CREDENTIALS_DIRECTORY/keyring-password" || rc=$?
        case "$rc" in
          0) exit 0 ;;
          1) echo "keyring-unlock-boot: the sealed password was rejected; keyring stays locked (re-run keyring-seal)"; exit 1 ;;
        esac
        sleep 2
      done
      echo "keyring-unlock-boot: the keyring service never answered; keyring stays locked"
      exit 2
    '';
  };
}
