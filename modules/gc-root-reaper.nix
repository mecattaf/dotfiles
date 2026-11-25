{ lib, pkgs, ... }:
# Stale auto-GC-root reaper. Refs #133 ("every accumulating artifact needs a
# retention policy") — this closes the largest gap that doctrine had left.
#
# Agent sessions (Claude Code, Codex) run `nix build` in scratchpads and
# worktrees under /tmp; every such build registers a symlink in
# /nix/var/nix/gcroots/auto pointing at the session's `result`. The sessions
# end; the roots stay; nix can never collect what they pin. Found live on the
# strix 2026-08-20: 322 auto roots, of which 310 were dead sessions or
# dangling — pinning ~80 GB on a root filesystem at 90%. The one-off reap is
# history; this unit is the retention policy that stops the regrowth.
#
# Policy (deliberately narrower than the one-off): delete an auto root when
# its target is dangling, or lives under /tmp and has been unmodified for 7+
# days. A 7-day window cannot bite a live session — nothing agent-shaped runs
# for a week without touching its own scratchpad — and /tmp contents don't
# survive a reboot anyway, so these roots were doomed to dangle; we just stop
# waiting. Roots targeting other real paths are someone's pin, with three
# exceptions found on 2026-11-25, when they pinned about 50 GB on the NAS and
# 63 GB on strix-coordinator:
#   - /var/tmp/*: the same 7 days as /tmp.
#   - /var/lib/microvms/<vm>/*: 14 days, and only while microvm@<vm> is not
#     running. Test VMs are kept by microvm.nix and never torn down.
#   - ~/.local/state/*: 14 days, and only for a whole NixOS system or Home
#     Manager generation (old deploy candidates and cleanup pins), never the
#     live Home Manager root or a nix profile generation.
{
  systemd.services.gc-root-reaper = {
    description = "Reap stale agent-session auto GC roots";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "gc-root-reaper" ''
        set -eu
        export PATH=${
          lib.makeBinPath [
            pkgs.coreutils
            pkgs.systemd
          ]
        }:$PATH
        cd /nix/var/nix/gcroots/auto 2>/dev/null || exit 0
        now=$(date +%s)
        week=604800
        fortnight=1209600
        deleted=0
        for l in *; do
          [ -L "$l" ] || continue
          t=$(readlink "$l")
          if [ ! -e "$t" ]; then
            rm -f -- "$l"; deleted=$((deleted+1)); continue
          fi
          age=$(( now - $(stat -c %Y "$t") ))
          case "$t" in
            /tmp/*|/var/tmp/*)
              if [ "$age" -ge "$week" ]; then
                rm -f -- "$l"; deleted=$((deleted+1))
              fi
              ;;
            /var/lib/microvms/*/*)
              vm=''${t#/var/lib/microvms/}; vm=''${vm%%/*}
              if [ "$age" -ge "$fortnight" ] && ! systemctl -q is-active "microvm@$vm.service"; then
                rm -f -- "$l"; deleted=$((deleted+1))
              fi
              ;;
            /home/*/.local/state/home-manager/gcroots/*|/home/*/.local/state/nix/profiles/*) ;;
            /home/*/.local/state/*)
              case "$(readlink -f "$t")" in
                /nix/store/*-nixos-system-*|/nix/store/*-home-manager-generation)
                  if [ "$age" -ge "$fortnight" ]; then
                    rm -f -- "$l"; deleted=$((deleted+1))
                  fi
                  ;;
              esac
              ;;
          esac
        done
        echo "gc-root-reaper: removed $deleted stale roots"
      '';
    };
  };

  systemd.timers.gc-root-reaper = {
    description = "Daily reap of stale agent-session GC roots";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };
}
