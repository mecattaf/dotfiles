#!/bin/sh
# SYNTHETIC generic-PC VM proof. No PS4 GPU, Orbis firmware or boot payload.
# This file is appended under the initramfs's amdgpu directory ONLY to exercise
# the unmodified stage-1 firmware-directory preservation and /sbin/init bridge.
set -eu
PATH=/run/current-system/sw/bin:/usr/bin:/bin
export PATH
exec >/dev/ttyS0 2>&1
echo 'SYNTHETIC PS4 ROOT-CONTRACT TEST: generic PC, no PS4 GPU/firmware/payload'
phase=root-contract
trap 'result=$?; if [ "$result" -ne 0 ]; then echo "PS4_VM_PROOF_FAILED=$phase status=$result"; systemctl --failed --no-pager --plain; fi' 0

test "$(cat /proc/1/comm)" = systemd
test "$(hostname)" = ps4-dummy
test -e /etc/NIXOS
test -x /sbin/init
test -x /nix/var/nix/profiles/system/init
test "$(readlink -f /run/current-system)" = "$(readlink -f /nix/var/nix/profiles/system)"
test "$(stat -c %u /)" = 0
test "$(stat -c %u /nix/store)" = 0
test "$(stat -Lc %u /sbin/init)" = 0
# Stage 2 repairs /nix/store's top-level owner. Check immutable imported
# store files too, so that repair cannot hide a broken mkfs ownership map.
test "$(stat -Lc %u /run/current-system/init)" = 0
test "$(stat -Lc %u /run/current-system/activate)" = 0
test ! -e /nix-path-registration
test -s /nix/var/nix/db/db.sqlite
nix-store --query --requisites /run/current-system >/dev/null
test "$(systemctl show --property=Result --value register-nix-paths.service)" = success
test -d "/run/current-system/kernel-modules/lib/modules/$(uname -r)"
! grep -qw avx2 /proc/cpuinfo
! grep -Eq '(^|[[:space:]])avx512' /proc/cpuinfo

phase=multi-user-startup
# The generated proof unit depends on basic.target, not multi-user.target.
# Start the ordinary fleet boot transaction, then inspect its real results.
systemctl start multi-user.target
for unit in sshd.service NetworkManager.service nftables.service tailscaled.service home-manager-tom.service; do
  phase=$unit
  systemctl is-active --quiet "$unit"
  printf 'PS4_VM_ACTIVE=%s\n' "$unit"
done
phase=firewall
nft list table inet nixos-fw >/dev/null
phase=fresh-ssh-identity
test -s /etc/ssh/ssh_host_ed25519_key
test -s /etc/ssh/ssh_host_ed25519_key.pub
phase=tailscale-needs-login
if tailscale status --json --peers=false >/run/ps4-vm-tailscale-status.json; then
  tailscale_status=0
else
  tailscale_status=$?
fi
test "$tailscale_status" -eq 0 || test "$tailscale_status" -eq 1
jq -e '.BackendState == "NeedsLogin"' /run/ps4-vm-tailscale-status.json >/dev/null
echo 'PS4_VM_TAILSCALE=NeedsLogin'
phase=unprivileged-runtime-isolation
runuser -u tom -- env PATH=/etc/profiles/per-user/tom/bin:/run/current-system/sw/bin \
  /home/tom/.local/bin/runtime-test -- /run/current-system/sw/bin/true
echo 'PS4_VM_USER_RUNTIME_ISOLATION_PASS'
phase=failed-unit-check
systemctl --failed --no-pager --plain
test "$(systemctl --failed --no-legend --plain | wc -l)" -eq 0
grep -E '^(MemTotal|MemAvailable):' /proc/meminfo
echo 'PS4_VM_FLEET_STARTUP_PASS'

printf 'PS4_VM_RELEASE=%s\n' "$(uname -r)"
printf 'PS4_VM_SYSTEM=%s\n' "$(readlink -f /run/current-system)"
printf 'PS4_VM_ROOT=%s\n' "$(findmnt -n -o SOURCE,FSTYPE /)"
printf 'PS4_VM_ROOT_CONTRACT_PASS\n'
