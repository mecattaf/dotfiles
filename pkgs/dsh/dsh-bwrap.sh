# dsh-bwrap: the sandbox runner the dsh policy pins (sandbox.runnerCommand).
# Built by ./default.nix with writeShellApplication (strict mode, shellcheck,
# bubblewrap and coreutils on PATH).
#
# dsh calls `dsh-bwrap <its bwrap profile args> -- <argv>`. Its profile is
# `--ro-bind / / --dev /dev --unshare-pid --proc /proc --die-with-parent`,
# plus `--tmpfs /tmp --bind <ws> <ws>` in workspace-write. The fleet masks go
# after dsh's own args and before the `--`, so they land on top of its mounts.
#
# What the masks close: the model's bash reaching the live Herdr server or the
# user manager through /run/user, reading agenix secrets or another harness's
# login, and planting git hooks or config that a later host-side git (Tom's,
# outside any sandbox) would run. What they do NOT close: the network stays
# shared (git push, gh and web work from bash), ~/.ssh and ~/.config/gh stay
# visible on purpose, and dsh's in-process `read` tool runs outside this
# runner, so it still reads whatever tom can. The masks block actions, not
# reads by the harness itself.
#
# Any failure here prints a `dsh-bwrap: ` line, which the policy lists as a
# runner-failure signature, so dsh reports a sandbox failure instead of
# running the command some other way.

pre=()
ws=""
while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do
  if [ "$1" = "--bind" ] && [ "$#" -ge 3 ]; then
    ws="$2"
  fi
  pre+=("$1")
  shift
done
if [ "${1-}" != "--" ] || [ "$#" -lt 2 ]; then
  echo "dsh-bwrap: expected <bwrap args> -- <command>" >&2
  exit 125
fi
shift

uid="$(id -u)"
masks=(/run/agenix.d "/run/user/$uid")
# /run/agenix is a symlink into /run/agenix.d, so masking the target covers it.
if [ -d /run/agenix ] && [ ! -L /run/agenix ]; then
  masks+=(/run/agenix)
fi
for d in .config/herdr .claude .claude-work .claude-3 .codex .pi .dsh; do
  masks+=("$HOME/$d")
done
# The wrapper passes the resolved DSH_HOME under a name dsh's child-env scrub
# keeps (it drops every DSH_* name).
if [ -n "${DSHWRAP_HOME-}" ]; then
  masks+=("$DSHWRAP_HOME")
fi

extra=(--unshare-ipc --new-session)
for m in "${masks[@]}"; do
  [ -d "$m" ] || continue
  # A tmpfs over the workspace or one of its parents would hide the workspace.
  # Fail closed rather than drop the mask.
  if [ -n "$ws" ]; then
    case "$ws/" in
      "$m"/*)
        echo "dsh-bwrap: workspace $ws is inside masked $m" >&2
        exit 125
        ;;
    esac
  fi
  extra+=(--tmpfs "$m")
done

# Read-only git control files in a writable workspace. A `.git` FILE (a linked
# worktree) is bound read-only whole, so it cannot be repointed at a gitdir the
# model controls. A missing hooks dir is created first (git init creates it
# anyway), so the model cannot create it under the read-only config.
if [ -n "$ws" ]; then
  if [ -f "$ws/.git" ]; then
    extra+=(--ro-bind "$ws/.git" "$ws/.git")
  elif [ -d "$ws/.git" ]; then
    mkdir -p "$ws/.git/hooks"
    extra+=(--ro-bind "$ws/.git/hooks" "$ws/.git/hooks")
    for f in config config.worktree; do
      if [ -f "$ws/.git/$f" ]; then
        extra+=(--ro-bind "$ws/.git/$f" "$ws/.git/$f")
      fi
    done
  fi
fi

exec bwrap "${pre[@]}" "${extra[@]}" -- "$@"
