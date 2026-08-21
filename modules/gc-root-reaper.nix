{ lib, pkgs, ... }:
# Stale auto-GC-root reaper. Refs #133 ("every accumulating artifact needs a
# retention policy") — this closes the largest gap that doctrine had left.
#
# Agent sessions (Claude Code, Codex) run `nix build` in scratchpads and
# worktrees under /tmp; every such build registers a symlink in
# /nix/var/nix/gcroots/auto pointing at the session's `result`. The sessions
# end; the roots stay; nix can never collect what they pin. Found live on the
# coordinator 2026-08-20: 322 auto roots, of which 310 were dead sessions or
# dangling — pinning ~80 GB on a root filesystem at 90%. The one-off reap is
# history; this unit is the retention policy that stops the regrowth.
#
# Policy (deliberately narrower than the one-off): delete an auto root when
# its target is dangling, or lives under /tmp and has been unmodified for 7+
# days. A 7-day window cannot bite a live session — nothing agent-shaped runs
# for a week without touching its own scratchpad — and /tmp contents don't
# survive a reboot anyway, so these roots were doomed to dangle; we just stop
# waiting. Roots targeting real (non-/tmp) paths are never touched: a
# deliberate `nix build` result in a project directory is someone's pin.
{
  systemd.services.gc-root-reaper = {
    description = "Reap stale agent-session auto GC roots";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "gc-root-reaper" ''
        set -eu
        export PATH=${lib.makeBinPath [ pkgs.coreutils ]}:$PATH
        cd /nix/var/nix/gcroots/auto 2>/dev/null || exit 0
        now=$(date +%s)
        deleted=0
        for l in *; do
          [ -L "$l" ] || continue
          t=$(readlink "$l")
          if [ ! -e "$t" ]; then
            rm -f -- "$l"; deleted=$((deleted+1)); continue
          fi
          case "$t" in
            /tmp/*)
              age=$(( now - $(stat -c %Y "$t") ))
              if [ "$age" -ge 604800 ]; then
                rm -f -- "$l"; deleted=$((deleted+1))
              fi
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
