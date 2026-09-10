#!/usr/bin/env bash
# FT-3 (dotfiles#361, TL-18 / D-B18, dotfiles#304) — the oracle for the box's
# KIT and for the usage_source join.
#
# WHAT IT PROVES. Until this unit, `services.tally-uplink.kit` was null: no file
# on this box mapped an `argv_ref` to a command, so every proposal the lake
# could make was a legible throw and nothing could ever run under a lease. This
# probe asserts, out of the TREE only and with no network, no socket, no lake
# and no switch, that the box now carries an argv table — and that the one entry
# it ENABLES actually closes the seam the kernel has never been given.
#
#   K1 `services.tally-uplink.kit` evaluates to a `/nix/store/…-tally-uplink-
#      kit.json` path: the argv table is a reviewed store artifact, never a file
#      hand-edited on the box (Rule 9, dotfiles#293).
#   K2 the PINNED LAKE'S OWN `readKit` (apps/uplink/src/kit.mjs out of the
#      `tally-lake` input's store path — the very code the unit will run)
#      resolves all three enabled refs with every required field present, and
#      REFUSES `claude:headless` with an error that names the kit file. The
#      refusal is the point: the Claude-seat entry is designed and documented
#      in home/tally-uplink.nix and deliberately not in `entries`, because no
#      kernel lease on a feeder-owned seat row is sanctioned (D-B6; the ruling
#      is asked in dotfiles#362).
#   K3 the enabled entry's argv[0] is an executable store path.
#   K4 THE JOIN, offline: run that argv[0] under `env -i` with only the two
#      variables `exec.run` exports to a child (tally crates/tally-kernel/src/
#      exec.rs:689) — TALLY_EXECUTION_ID and TALLY_USAGE_SOURCE_PATH — and the
#      child leaves exactly one JSON line at that path whose `execution_id` is
#      the one it was given. That is what makes the `witness_record`'s
#      `usage_source{kind,path}` (exec.rs:953-958) point at an artifact that
#      names the execution back.
#   K5 the RENDERED ExecStart carries `--kit /nix/store/…` and NO `--plan`:
#      the kit reaches the unit, and arming stays Tom's act.
#   K6 `nix build .#checks.x86_64-linux.tally-uplink-topology -L` -> rc 0.
#   K7 `bash tests/tally-uplink/test-tally-uplink-input.sh` -> rc 0, which
#      re-runs clause A0 (the lock update is a NO-OP at the NEW pin) and clause
#      D (the new rev is on the remote's main) among the rest.
#
# WHY BOTH K2 AND K6. The topology check reads the PATH off the rendered option;
# this probe reads the BYTES at that path with the lake's own parser. A kit that
# is in the store and reaches the argv can still be missing `usage_source` — the
# RED for this unit is exactly that: drop `usage_source` from the enabled entry
# in a scratch copy and K2 goes red naming the field while K6 stays green.
#
# NOTHING IS SWITCHED, STARTED OR ARMED. No unit is touched, no lake is
# contacted, no credential is read, nothing under ~/.local/state is written —
# K4 writes only into a scratch directory of its own, removed on exit.
#
# Usage: bash tests/tally-uplink/probe-FT-3-kit.sh [repo-path]
# rc 0 = every clause passed. rc 1 = a clause failed. rc 2 = the probe could not run.
set -uo pipefail

repo="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
cd "$repo" || { echo "FAIL: cannot cd $repo"; exit 2; }
command -v nix >/dev/null || { echo "FAIL: no nix on PATH"; exit 2; }

fails=0
ok()  { printf 'ok   %s\n' "$*"; }
bad() { printf 'FAIL %s\n' "$*"; fails=$((fails + 1)); }

scratch="$(mktemp -d)" || exit 2
trap 'rm -rf "$scratch"' EXIT

coord=".#nixosConfigurations.coordinator.config.home-manager.users.tom"

# ---- K1: the kit is a store .json, named by the module that builds it.
kit="$(nix eval --raw "${coord}.services.tally-uplink.kit" 2>/dev/null)"
case "$kit" in
  /nix/store/*-tally-uplink-kit.json) ok "K1 kit = $kit" ;;
  "") bad "K1 services.tally-uplink.kit did not evaluate (still null?)"; kit="" ;;
  *)  bad "K1 kit is not a store -tally-uplink-kit.json: '$kit'"; kit="" ;;
esac
# realise it, so the bytes exist for K2 even on a store that only has the .drv.
if [ -n "$kit" ] && [ ! -e "$kit" ]; then
  nix build --no-link "${coord}.services.tally-uplink.kit" >/dev/null 2>&1
fi

# ---- K2: the PINNED LAKE's own readKit resolves the enabled refs and refuses
#          the designed-but-disabled one, naming this kit file.
lake="$(nix eval --raw --impure --expr "(builtins.getFlake \"path:${repo}\").inputs.tally-lake.outPath" 2>/dev/null)"
if [ -z "$lake" ] || [ ! -r "$lake/apps/uplink/src/kit.mjs" ]; then
  bad "K2 cannot resolve the tally-lake input's apps/uplink/src/kit.mjs (got '$lake')"
elif [ -z "$kit" ]; then
  bad "K2 skipped: K1 produced no kit path"
else
  # the unit's OWN interpreter, so the parser under test runs on the runtime the
  # service will use. The option holds the package's root, not the binary.
  node="$(nix eval --raw "${coord}.services.tally-uplink.node" 2>/dev/null)"
  if [ -n "$node" ] && [ -x "$node/bin/node" ]; then
    node="$node/bin/node"
  elif [ ! -x "${node:-}" ]; then
    node="$(command -v node || true)"
  fi
  if [ -z "$node" ] || [ ! -x "$node" ]; then
    bad "K2 no node: neither the unit's interpreter nor one on PATH"
  else
    out="$("$node" --input-type=module -e "
      import { readKit } from '${lake}/apps/uplink/src/kit.mjs'
      const kit = readKit(process.argv[1])
      const want = ['build:LOCAL-SMOKE', 'scope(build:LOCAL-SMOKE)', 'eval(build:LOCAL-SMOKE)']
      for (const ref of want) {
        const e = kit.resolve(ref)
        for (const f of ['argv', 'cwd', 'env_allowlist', 'usage_source', 'stdin']) {
          if (e[f] === undefined) throw new Error(\`\${ref} is missing \${f}\`)
        }
        if (typeof e.usage_source.kind !== 'string' || typeof e.usage_source.path_glob !== 'string') {
          throw new Error(\`\${ref} usage_source lacks kind/path_glob\`)
        }
        if (!e.usage_source.path_glob.includes('*')) {
          throw new Error(\`\${ref} usage_source.path_glob has no * for the execution digest\`)
        }
      }
      let refused = ''
      try { kit.resolve('claude:headless'); } catch (error) { refused = error.message }
      if (!refused) throw new Error('claude:headless RESOLVED — the seat entry is enabled')
      if (!refused.includes(process.argv[1])) throw new Error('the refusal does not name the kit file: ' + refused)
      console.log('ARGV0=' + kit.resolve('build:LOCAL-SMOKE').argv[0])
      console.log('REFS=' + kit.refs().join(','))
      console.log('REFUSED=' + refused)
    " "$kit" 2>&1)"
    if [ $? -eq 0 ]; then
      ok "K2 readKit(pinned lake) resolves the three refs and refuses claude:headless"
      printf '     %s\n' "$out"
    else
      bad "K2 readKit: $out"
    fi
  fi
fi

# ---- K3: the enabled argv[0] is an executable store path.
argv0="$(printf '%s\n' "${out:-}" | sed -n 's/^ARGV0=//p')"
if [ -n "$argv0" ] && [ -x "$argv0" ]; then
  case "$argv0" in
    /nix/store/*) ok "K3 argv[0] = $argv0 (store, executable)" ;;
    *) bad "K3 argv[0] is executable but not a store path: '$argv0'" ;;
  esac
else
  bad "K3 argv[0] is absent or not executable: '${argv0:-}'"
fi

# ---- K4: THE JOIN. Only the two variables exec.run exports; nothing else.
usage="$scratch/local-smoke-probe.jsonl"
if [ -n "$argv0" ] && [ -x "$argv0" ]; then
  if env -i TALLY_EXECUTION_ID=exec-probe TALLY_USAGE_SOURCE_PATH="$usage" "$argv0"; then
    lines=$(wc -l < "$usage" 2>/dev/null || echo 0)
    got=$(sed -n '1p' "$usage" 2>/dev/null | sed -n 's/.*"execution_id":"\([^"]*\)".*/\1/p')
    if [ "$lines" = "1" ] && [ "$got" = "exec-probe" ]; then
      ok "K4 one usage line, execution_id = exec-probe: $(cat "$usage")"
    else
      bad "K4 expected one line with execution_id exec-probe; lines=$lines id='$got'"
    fi
  else
    bad "K4 the enabled argv exited non-zero under env -i"
  fi
else
  bad "K4 skipped: no runnable argv[0]"
fi

# ---- K5: the rendered ExecStart carries --kit and no --plan.
exec_start="$(nix eval --raw "${coord}.systemd.user.services.tally-uplink.Service.ExecStart" \
  --apply 'e: if builtins.isList e then builtins.concatStringsSep " " e else e' 2>/dev/null)"
case "$exec_start" in
  *"--kit /nix/store/"*) ok "K5 ExecStart carries --kit /nix/store/…" ;;
  *) bad "K5 ExecStart carries no '--kit /nix/store/': '$exec_start'" ;;
esac
case "$exec_start" in
  *--plan*) bad "K5 ExecStart carries --plan; arming is Tom's act, plan must stay null" ;;
  *) ok "K5 ExecStart carries no --plan" ;;
esac

# ---- K6: the topology check builds (it asserts the kit over the rendered unit).
if nix build .#checks.x86_64-linux.tally-uplink-topology -L; then
  ok "K6 nix build .#checks.x86_64-linux.tally-uplink-topology"
else
  bad "K6 tally-uplink-topology did not build"
fi

# ---- K7: U-D14's own suite, which re-runs A0 (lock no-op at the NEW pin) and D.
if bash tests/tally-uplink/test-tally-uplink-input.sh "$repo"; then
  ok "K7 tests/tally-uplink/test-tally-uplink-input.sh"
else
  bad "K7 test-tally-uplink-input.sh is not green"
fi

if [ "$fails" -eq 0 ]; then
  echo "PROBE FT-3: PASS"
  exit 0
fi
echo "PROBE FT-3: FAIL ($fails clause(s))"
exit 1
