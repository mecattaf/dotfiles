#!/usr/bin/env bash
# Substituted and wrapped by writeShellApplication. No service control, mounts,
# formatting or deletion. Dry-run never creates escrow files or destination dirs.
set -euo pipefail

expected_disk=@expectedDisk@
expected_serial=@expectedSerial@
expected_label=@expectedLabel@
hdd_uuid=@hddUuid@
excludes=@excludes@

die() { printf 'nas-home-migrate: %s\n' "$*" >&2; exit 1; }
usage() {
    cat <<'USAGE'
nas-home-migrate escrow [--dry-run | --apply]
nas-home-migrate home [--dry-run | --apply] [--final] [--bench]
    [--source root@strix:/home/tom/] [--target /mnt/newhome]

Default: dry-run. Escrow runs on the NAS and verifies its mounted HDD before
root-only backups. Home verifies the SSD serial, both p2 labels and the exact
writable btrfs @home mount before rsync. --bench allows home copying as root
on the worker's installer before the SSD moves to the NAS; identity checks
are unchanged. Escrow cannot use --bench.
--target names the @home MOUNTPOINT; its tom/ directory must already exist.
--final adds --checksum to the itemized rsync (still dry-run without --apply).
No --delete, partitioning, formatting, mounting or service control is performed.
Before a final copy, arrange consistent source databases and session handover
separately. Excluded data must be preserved in the sealed full-home HDD copy.
USAGE
}
print_command() { printf '  '; printf '%q ' "$@"; printf '\n'; }
mount_field() { findmnt --noheadings --raw --mountpoint "$1" --output "$2"; }

action=${1:---help}
case "$action" in
    -h|--help) usage; exit 0 ;;
    escrow|home) shift ;;
    *) usage >&2; exit 2 ;;
esac
apply=false
final=false
bench=false
mode_seen=false
source='root@strix:/home/tom/'
target='/mnt/newhome'
while (($#)); do
    case "$1" in
        --apply|--dry-run)
            "$mode_seen" && die 'choose only one of --apply and --dry-run'
            mode_seen=true
            [[ $1 != --apply ]] || apply=true
            shift ;;
        --final) [[ $action == home ]] || die '--final is only for home'; final=true; shift ;;
        --bench) [[ $action == home ]] || die '--bench is only for home'; bench=true; shift ;;
        --source|--target)
            [[ $action == home && $# -ge 2 && -n $2 ]] || die "invalid $1"
            if [[ $1 == --source ]]; then source=$2; else target=$2; fi
            shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown argument: $1" ;;
    esac
done

if "$apply"; then
    [[ $EUID == 0 ]] || die '--apply requires root'
    if ! "$bench"; then
        [[ $(uname -n) == nas ]] || die 'run on the NAS, or use home --bench on the installer'
    fi
else
    printf 'DRY RUN: no backups or home files will be written.\n'
fi

if [[ $action == home ]]; then
    # Verify both the whole disk and the mounted partition's ancestry. Never
    # trust enumeration order, a directory named /mnt/newhome, or a label alone.
    [[ $expected_disk == /dev/disk/by-id/nvme-* && $expected_disk == *_"$expected_serial" ]] \
        || die 'invalid configured disk identity'
    serial=$(lsblk --nodeps --noheadings --raw --output SERIAL "$expected_disk")
    [[ ${serial//[[:space:]]/} == "$expected_serial" ]] || die 'target SSD serial does not match'
    partition="$expected_disk-part2"
    ancestry_serial=$(lsblk --inverse --noheadings --raw --output SERIAL "$partition")
    [[ ${ancestry_serial//[[:space:]]/} == "$expected_serial" ]] || die 'p2 is not on the expected SSD'
    label=$(lsblk --nodeps --noheadings --raw --output PARTLABEL "$partition")
    [[ $label == disk-primary-home ]] || die 'p2 must be labelled disk-primary-home'
    filesystem_label=$(lsblk --nodeps --noheadings --raw --output LABEL "$partition")
    [[ $filesystem_label == "$expected_label" ]] || die "p2 filesystem must be labelled $expected_label"
    [[ $target == /* && -d $target && ! -L $target ]] || die 'target must be an existing absolute mountpoint'
    target=$(realpath -e -- "$target")
    [[ $(mount_field "$target" FSTYPE) == btrfs ]] || die 'target must be an exact btrfs mountpoint'
    [[ $(mount_field "$target" FSROOT) == /@home ]] || die 'target must mount subvolume @home itself'
    device_number=$(lsblk --nodeps --noheadings --raw --output MAJ:MIN "$partition")
    [[ $(mount_field "$target" MAJ:MIN) == "$device_number" ]] || die 'target mount is not the expected SSD p2'
    case ",$(mount_field "$target" OPTIONS)," in
        *,rw,*) ;;
        *) die 'target mount is not writable' ;;
    esac
    [[ -d $target/tom && ! -L $target/tom ]] || die 'prepare the tom/ directory inside @home first'
    [[ $source != -* && $source == */ ]] || die 'source must end in / and cannot be an option'
    [[ -f $excludes ]] || die 'packaged exclusion list is missing'
    printf 'Verified SSD serial %s, disk-primary-home p2, filesystem %s, mounted @home at %s\n' "$expected_serial" "$expected_label" "$target"
    if "$bench"; then
        printf 'Bench mode: home copy on the installer; all disk identity checks remain enabled.\n'
    fi
    args=(-aHAXS --numeric-ids --protect-args --itemize-changes --stats --exclude-from="$excludes")
    "$apply" || args+=(--dry-run)
    "$final" && args+=(--checksum)
    print_command rsync "${args[@]}" -- "$source" "$target/tom/"
    exec rsync "${args[@]}" -- "$source" "$target/tom/"
fi

# Escrow is intentionally independent of the incoming SSD: stage 0 precedes
# its arrival. Refuse the eMMC fallback when the HDD is absent or wrong.
[[ $(mount_field /mnt/nas FSTYPE) == btrfs ]] || die '/mnt/nas must be mounted btrfs'
[[ $(mount_field /mnt/nas UUID) == "$hdd_uuid" ]] || die 'escrow HDD UUID does not match'
case ",$(mount_field /mnt/nas OPTIONS)," in
    *,rw,*) ;;
    *) die 'escrow HDD is not writable' ;;
esac
escrow_root=/mnt/nas/services/migration-escrow
printf 'Escrow on verified HDD: %s (root:root 0700; files 0600)\n' "$escrow_root"
if ! "$apply"; then
    printf '%s\n' \
        '  runuser -u postgres -- pg_dumpall > ESCROW/postgresql.sql' \
        '  sqlite3 /var/lib/private/atticd/server.db ".backup ESCROW/server.db"' \
        '  tar --acls --xattrs: /etc/ssh/ssh_host_*, /var/lib/tailscale-personal,' \
        '      /var/lib/atticd-secrets, /var/lib/AdGuardHome -> ESCROW/identity.tar' \
        '  Each command writes diagnostics inside ESCROW; contents are never printed.'
    exit 0
fi

umask 077
[[ $(realpath -m -- "$escrow_root") == "$escrow_root" ]] || die 'escrow path contains a symlink'
[[ -d /mnt/nas/services ]] || die 'HDD services directory is missing'
[[ $(findmnt --noheadings --raw --target /mnt/nas/services --output UUID) == "$hdd_uuid" ]] \
    || die 'escrow services directory is not on the verified HDD'
if [[ -e $escrow_root ]]; then
    [[ -d $escrow_root && $(stat -c %u:%g:%a "$escrow_root") == 0:0:700 ]] \
        || die 'existing escrow directory must be root:root 0700'
else
    install -d -m 0700 -o root -g root -- "$escrow_root"
fi
shopt -s nullglob
host_keys=(/etc/ssh/ssh_host_*)
((${#host_keys[@]})) || die 'SSH host keys are missing'
for path in /var/lib/private/atticd/server.db /var/lib/tailscale-personal /var/lib/atticd-secrets /var/lib/AdGuardHome; do
    [[ -e $path ]] || die "required escrow source missing: $path"
done
escrow_dir=$(mktemp -d "$escrow_root/escrow-$(date -u +%Y%m%dT%H%M%SZ)-XXXXXX")
# The outer directory is root-only; postgres writes through stdout opened here
# as root. Matching the server's PostgreSQL package is handled by the module.
runuser -u postgres -- pg_dumpall >"$escrow_dir/postgresql.sql" 2>"$escrow_dir/postgresql.log" \
    || die "PostgreSQL escrow failed; private diagnostics: $escrow_dir/postgresql.log"
sqlite3 /var/lib/private/atticd/server.db ".backup '$escrow_dir/server.db'" \
    >"$escrow_dir/sqlite.log" 2>&1 || die "Attic escrow failed; private diagnostics: $escrow_dir/sqlite.log"
relative_keys=("${host_keys[@]/#\//}")
tar --acls --xattrs --directory / -cpf "$escrow_dir/identity.tar" -- \
    "${relative_keys[@]}" var/lib/tailscale-personal var/lib/atticd-secrets var/lib/AdGuardHome \
    >"$escrow_dir/tar.log" 2>&1 || die "Identity escrow failed; private diagnostics: $escrow_dir/tar.log"
for name in postgresql.sql server.db identity.tar; do
    [[ -s $escrow_dir/$name ]] || die "empty escrow output: $name"
done
chmod 0600 "$escrow_dir"/*
touch "$escrow_dir/COMPLETE"
printf 'Escrow complete: %s (contents not printed)\n' "$escrow_dir"
stat -c '%n: %s bytes, mode %a, owner %U:%G' "$escrow_dir"/{postgresql.sql,server.db,identity.tar,COMPLETE}
