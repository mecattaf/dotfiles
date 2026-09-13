# raw-dotfiles-guard (#313). home/raw-dotfiles-guard.nix runs it from
# home.activation before writeBoundary; flake.nix's `raw-dotfiles-guard` check
# runs the same binary against fixture checkouts.
#
#   raw-dotfiles-guard <repoDir> <program>...
#
# Every raw dotfile is an out-of-store link into <repoDir>/home, which is the
# checkout at ~/mecattaf/dotfiles and NOT the flake a switch was taken from.
# A user unit whose ExecStart is %h/.local/bin/<program> therefore renders
# from the flake while <program> comes from that checkout. If the checkout
# lacks it, the switch would half-land: the unit is installed and fails later,
# on its own timer, with nothing pointing back at the switch. This refuses the
# activation instead, before any file is written.
#
# No checkout at all (a fresh machine, before modules/dotfiles-bootstrap.nix
# has cloned it) is a warning, not a failure: the dangling-link behaviour
# home/home.nix documents for that case is unchanged.
{ writeShellApplication }:
writeShellApplication {
  name = "raw-dotfiles-guard";
  text = ''
    if [ "$#" -lt 1 ]; then
      echo "usage: raw-dotfiles-guard <repoDir> <program>..." >&2
      exit 2
    fi
    repo=$1
    shift
    bin="$repo/home/dot_local/bin"

    # .git is a directory in a clone and a file in a worktree; either counts.
    if [ ! -e "$repo/.git" ]; then
      echo "raw-dotfiles-guard: warning: no checkout at $repo; raw dotfiles will dangle until it is cloned" >&2
      exit 0
    fi

    missing=()
    for p in "$@"; do
      if [ ! -x "$bin/$p" ]; then
        missing+=("$p")
      fi
    done

    if [ "''${#missing[@]}" -gt 0 ]; then
      for p in "''${missing[@]}"; do
        echo "raw-dotfiles-guard: this generation's units run %h/.local/bin/$p but $bin/$p does not exist or is not executable" >&2
      done
      echo "raw-dotfiles-guard: the raw half of a switch comes from $repo, not from the flake you switched from; bring that checkout to the branch first (AGENTS.md, raw dotfiles)" >&2
      exit 1
    fi

    echo "raw-dotfiles-guard: ok ($# programs)"
  '';
}
