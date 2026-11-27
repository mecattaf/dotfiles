#!/bin/sh
# SYNTHETIC generic-PC VM proof. No PS4 GPU, Orbis firmware or boot payload.
# This file is appended under the initramfs's amdgpu directory ONLY to exercise
# the unmodified stage-1 firmware-directory preservation and /sbin/init bridge.
set -eu
PATH=/run/current-system/sw/bin:/usr/bin:/bin
export PATH
exec >/dev/ttyS0 2>&1
echo 'SYNTHETIC PS4 ROOT-CONTRACT TEST: generic PC, no PS4 GPU/firmware/payload'

test "$(cat /proc/1/comm)" = systemd
test "$(hostname)" = ps4-dummy
test -e /etc/NIXOS
test -x /sbin/init
test -x /nix/var/nix/profiles/system/init
test "$(readlink -f /run/current-system)" = "$(readlink -f /nix/var/nix/profiles/system)"
test "$(stat -c %u /)" = 0
test "$(stat -c %u /nix/store)" = 0
test "$(stat -Lc %u /sbin/init)" = 0
test ! -e /nix-path-registration
test -s /nix/var/nix/db/db.sqlite
nix-store --query --requisites /run/current-system >/dev/null
test "$(systemctl show --property=Result --value register-nix-paths.service)" = success
! grep -qw avx2 /proc/cpuinfo

printf 'PS4_VM_RELEASE=%s\n' "$(uname -r)"
printf 'PS4_VM_SYSTEM=%s\n' "$(readlink -f /run/current-system)"
printf 'PS4_VM_ROOT=%s\n' "$(findmnt -n -o SOURCE,FSTYPE /)"
printf 'PS4_VM_ROOT_CONTRACT_PASS\n'
