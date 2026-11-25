# Prune a persisted home to the paths it declares, keeping nothing else.
#
#   home-prune ROOT KEEP...
#
# ROOT is the home on its own disk (on strix-coordinator /persist/home/tom),
# pruned before it is mounted at /home. Each KEEP is a path relative to ROOT,
# for example .ssh or .local/share/keyrings. A kept path is left exactly as
# it is. Its parent directories are kept but pruned in turn, and every other
# entry is removed, so the home starts each boot holding only what is kept.
#
# Set HOME_PRUNE_DRY_RUN=1 to print what would be removed and change nothing.
# rm never crosses a mount point. Nothing is mounted inside ROOT at boot,
# but --one-file-system keeps that from mattering.
set -eu
shopt -s dotglob nullglob

root=${1:?usage: home-prune ROOT KEEP...}
shift
keep=("$@")
dry=${HOME_PRUNE_DRY_RUN:-0}

if [ ! -d "$root" ] || [ -L "$root" ]; then
  echo "home-prune: $root is not a directory; nothing to do" >&2
  exit 0
fi
if [ "${#keep[@]}" -eq 0 ]; then
  echo "home-prune: no KEEP paths given; refusing to empty $root" >&2
  exit 2
fi
for k in "${keep[@]}"; do
  case "$k" in
  "" | /* | *..* | ./* | */)
    echo "home-prune: KEEP path '$k' must be relative, without '..' or a trailing slash" >&2
    exit 2
    ;;
  esac
done

is_kept() {
  local k
  for k in "${keep[@]}"; do [ "$1" = "$k" ] && return 0; done
  return 1
}

is_parent() {
  local k
  for k in "${keep[@]}"; do
    case "$k" in "$1"/*) return 0 ;; esac
  done
  return 1
}

removed=0
prune() {
  local rel=$1 entry name r
  for entry in "$root${rel:+/$rel}"/*; do
    name=${entry##*/}
    r=${rel:+$rel/}$name
    if is_kept "$r"; then
      continue
    fi
    if is_parent "$r" && [ -d "$entry" ] && [ ! -L "$entry" ]; then
      prune "$r"
      continue
    fi
    removed=$((removed + 1))
    if [ "$dry" = 1 ]; then
      echo "would remove $r"
    else
      rm -rf --one-file-system -- "$entry"
    fi
  done
}

prune ""
verb=removed
if [ "$dry" = 1 ]; then verb='would be removed'; fi
echo "home-prune: $root: $removed entries $verb; kept: ${keep[*]}"
