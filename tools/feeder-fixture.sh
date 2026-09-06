#!/usr/bin/env bash
# U-D12 DF-SEAT-FEEDER — the 60-tick fixture named by the DOMINANT oracle.
#
# The fixture evaluates the coordinator and worker Home Manager declarations,
# builds U-B10's real tally-admit binary offline into a temporary target, then
# replays the three declared clocks. Nothing under ~/.local/state is written:
# both the feeder outputs and tally-admit's receipt ledger live under $work.
#
# Overrides:
#   TALLY_KERNEL_REPO   merged mecattaf/tally checkout (default below)
#   TALLY_RUST_BIN      U-B1's recorded cargo/rustc directory
#   TALLY_CC_BIN        U-B1's recorded C compiler directory
#   TALLY_FIXTURE_TICKS replay length (default 60; the oracle leaves it unset)

set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/tally-seat-feeder.XXXXXX")
trap 'rm -rf -- "$work"' EXIT

kernel_repo=${TALLY_KERNEL_REPO:-/home/tom/mecattaf/tally}
rust_bin=${TALLY_RUST_BIN:-/nix/store/w5fr51mim5idqycr8krd005w5lxhmyd4-rust-default-1.93.0/bin}
cc_bin=${TALLY_CC_BIN:-/nix/store/adcz0m6qq2flmshdf0zz2xwjr5zbq1gr-gcc-wrapper-15.3.0/bin}
ticks=${TALLY_FIXTURE_TICKS:-60}
u_b10_merge=5cf6fa926680b53dfc31598dff8a4cab5e58fc6b

die_dependency() {
  printf 'tools/feeder-fixture.sh: U-B10 dependency absent: %s\n' "$1" >&2
  exit 3
}

[[ -f "$kernel_repo/Cargo.toml" ]] || die_dependency "$kernel_repo/Cargo.toml is missing"
[[ -f "$kernel_repo/crates/tally-kernel/src/admission.rs" ]] || \
  die_dependency "$kernel_repo has no tally-kernel admission source"
[[ -f "$kernel_repo/crates/tally-admit/Cargo.toml" ]] || \
  die_dependency "$kernel_repo has no tally-admit crate"
git -C "$kernel_repo" cat-file -e "$u_b10_merge^{commit}" 2>/dev/null || \
  die_dependency "merged U-B10 commit $u_b10_merge is not in $kernel_repo"
git -C "$kernel_repo" merge-base --is-ancestor "$u_b10_merge" HEAD || \
  die_dependency "$kernel_repo HEAD does not contain merged U-B10 commit $u_b10_merge"

[[ -x "$rust_bin/cargo" ]] || die_dependency "recorded cargo is missing at $rust_bin/cargo"
[[ -x "$rust_bin/rustc" ]] || die_dependency "recorded rustc is missing at $rust_bin/rustc"
[[ -x "$cc_bin/cc" ]] || die_dependency "recorded compiler is missing at $cc_bin/cc"

flake="$repo#nixosConfigurations.coordinator"
python_store=$(nix eval --offline --raw "$flake.pkgs.python3.outPath")
python="$python_store/bin/python3"
[[ -x "$python" ]] || die_dependency "evaluated python is missing at $python"

projection='home: {
  timers = home.systemd.user.timers;
  services = home.systemd.user.services;
  tmpfiles = home.systemd.user.tmpfiles.rules;
}'
nix eval --offline --json \
  "$repo#nixosConfigurations.coordinator.config.home-manager.users.tom" \
  --apply "$projection" >"$work/coordinator.json"
nix eval --offline --json \
  "$repo#nixosConfigurations.worker.config.home-manager.users.tom" \
  --apply "$projection" >"$work/worker.json"

export PATH="$rust_bin:$cc_bin:${PATH:-/usr/bin:/bin}"
export CARGO_TARGET_DIR="$work/kernel-target"
cargo build --offline --locked --manifest-path "$kernel_repo/Cargo.toml" -p tally-admit
admit="$CARGO_TARGET_DIR/debug/tally-admit"
[[ -x "$admit" ]] || die_dependency "cargo did not produce $admit"

log="$work/feeder-fixture.jsonl"
"$python" "$repo/tests/seat-feeder/replay.py" \
  --repo "$repo" \
  --workdir "$work/run" \
  --admit "$admit" \
  --coordinator-config "$work/coordinator.json" \
  --worker-config "$work/worker.json" \
  --ticks "$ticks" \
  --log "$log"

printf 'tools/feeder-fixture.sh: log sha256 %s\n' "$(sha256sum "$log" | cut -d' ' -f1)"
printf 'tools/feeder-fixture.sh: PASS\n'
