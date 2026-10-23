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
# Known limits:
# - dsh's in-process `write` and `edit` tools also run outside this runner.
#   In workspace-write their fence is the workspace, /tmp and os.tmpdir()
#   (dsh packages/sandbox/sandbox/src/roots.ts), so they can write the host's
#   /tmp and $TMPDIR. The wrapper refuses a DSH_HOME there, because a
#   `cordis.patch.yml` with `!!js` under DSH_HOME runs unsandboxed on the
#   next boot.
# - Only the workspace's own top-level `.git` is protected. A nested repo
#   under the workspace keeps a writable `.git`, and so does a workspace that
#   had no `.git` when dsh started (the model can `git init` one), so hooks
#   or config planted there run when tom uses git in it outside dsh.
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

# A read-only gitdir in a writable workspace. The whole `.git` is bound
# read-only, FILE (a linked worktree) or DIRECTORY alike, so it is a mount
# point: renaming or removing it fails (EBUSY), and nothing under it can be
# created or changed, `commondir`, `config`, `hooks/` and `objects/`
# included. Per-file binds were not enough: `mv .git` and a planted
# `.git/commondir` both redirected a later host-side git to a config and
# hooks dir the model wrote. The cost: dsh's bash cannot stage or commit, so
# tom commits outside dsh.
if [ -n "$ws" ] && [ -e "$ws/.git" ]; then
  extra+=(--ro-bind "$ws/.git" "$ws/.git")
fi

exec bwrap "${pre[@]}" "${extra[@]}" -- "$@"
