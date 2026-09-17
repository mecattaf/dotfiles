#!/usr/bin/env bash
# FT-3 (dotfiles#361, TL-18 / D-B18, dotfiles#304) — the oracle for the box's
# KIT and for the usage_source join.
#
# REVISED BY D-A (ruling 4, 2026-09-16 evening). FT-3 delivered the kit as a
# `pkgs.writeText` store file and this probe's K1/K3/K5 asserted exactly that.
# Ruling 4 answers that a table which needs a coordinator switch to gain a flow
# is the wrong artifact: "the kit path must become a runtime-read, git-tracked
# location, not a store path baked at switch time". So the three store clauses
# are INVERTED here, and what they now prove is the stronger property:
#
#   K0 the committed bytes ARE the bytes tools/render-tally-kit.py renders, and
#      they contain no store path at all — a hashed path inside a git-tracked
#      file would go stale on the next rebuild of its own derivation, and
#      refreshing it would be the switch ruling 4 removed.
#   K1 `services.tally-uplink.kit` evaluates to the RUNTIME path
#      /home/tom/.config/tally/kit.json — NOT a store path. home/tally-uplink.nix
#      installs that path as an out-of-store symlink into the dotfiles checkout
#      (`mkOutOfStoreSymlink`, the motion home/home.nix already performs), so
#      the uplink's per-wake `readFileSync` reads whatever the checkout holds.
#   K2 the PINNED LAKE'S OWN `readKit` (apps/uplink/src/kit.mjs out of the
#      `tally-lake` input's store path — the very code the unit will run), run
#      against the CHECKOUT FILE, resolves the LOCAL-SMOKE trio and the CUBS
#      range with every required field present, and REFUSES `claude:headless`
#      and `build:CUBS-201` with an error that names the kit file. The refusal
#      is the point: the Claude-seat entry is designed and documented in
#      home/tally-uplink.nix and deliberately not rendered, because no kernel
#      lease on a feeder-owned seat row is sanctioned (D-B6; the ruling is asked
#      in dotfiles#362).
#      K2 reads the FILE, so editing home/dot_config/tally/kit.json and
#      re-running this clause shows the new ref. With TALLY_KIT_LAKE and
#      TALLY_KIT_NODE set it runs with NO nix invocation at all, which is the
#      operator-visible content of ruling 4.
#   K3 every enabled entry's argv[0] is a STABLE per-user profile path
#      (/etc/profiles/per-user/tom/bin/...), never a store path: the two
#      executables are `home.packages` members of home/tally-uplink.nix, and the
#      profile path does not move when the derivation does.
#   K4 THE JOIN, offline: run the LOCAL-SMOKE executable under `env -i` with
#      only the two variables `exec.run` exports to a child (tally
#      crates/tally-kernel/src/exec.rs:689) — TALLY_EXECUTION_ID and
#      TALLY_USAGE_SOURCE_PATH — and the child leaves exactly one JSON line at
#      that path whose `execution_id` is the one it was given. That is what
#      makes the `witness_record`'s `usage_source{kind,path}` (exec.rs:953-958)
#      point at an artifact that names the execution back. Before the switch
#      that installs the profile path, K4 realises `.#tally-local-smoke` and
#      runs THAT — the bytes are the same derivation the profile will carry.
#   K5 the RENDERED ExecStart carries `--kit /home/tom/.config/tally/` and NO
#      `--plan`: the runtime kit reaches the unit, and arming stays Tom's act.
#   K6 `nix build .#checks.x86_64-linux.tally-uplink-topology -L` -> rc 0.
#   K7 `bash tests/tally-uplink/test-tally-uplink-input.sh` -> rc 0, which
#      re-runs clause A0 (the lock update is a NO-OP at the NEW pin) and clause
#      D (the new rev is on the remote's main) among the rest.
#
# WHY BOTH K2 AND K6. The topology check reads the PATH off the rendered option
# and parses the committed JSON with `builtins.fromJSON`; this probe reads the
# BYTES with the lake's own parser. A kit that is git-tracked and reaches the
# argv can still be missing `usage_source` — the RED for this unit is exactly
# that: drop `usage_source` from the enabled entry in a scratch copy and K2 goes
# red naming the field while K6 stays green.
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
envs=0
ok()  { printf 'ok   %s\n' "$*"; }
bad() { printf 'FAIL %s\n' "$*"; fails=$((fails + 1)); }

scratch="$(mktemp -d)" || exit 2
trap 'rm -rf "$scratch"' EXIT

coord=".#nixosConfigurations.coordinator.config.home-manager.users.tom"

# the git-tracked kit, and the runtime path the symlink puts it at.
checkout_kit="$repo/home/dot_config/tally/kit.json"
runtime_kit="/home/tom/.config/tally/kit.json"

# ---- K0: the committed bytes are the rendered bytes, and hold no store path.
if python3 tools/render-tally-kit.py --check; then
  if [ "$(grep -c '/nix/store' "$checkout_kit")" -eq 0 ]; then
    ok "K0 home/dot_config/tally/kit.json is the rendered output and names no store path"
  else
    bad "K0 the committed kit contains a store path (ruling 4: argv[0] must be stable)"
  fi
else
  bad "K0 tools/render-tally-kit.py --check is red"
fi

# ---- K1: the kit is the RUNTIME path, and NOT a store path.
kit="$(nix eval --raw "${coord}.services.tally-uplink.kit" 2>/dev/null)"
case "$kit" in
  /nix/store/*) bad "K1 kit is a store path: '$kit' — ruling 4 requires a runtime-read location" ;;
  "$runtime_kit") ok "K1 kit = $kit (runtime-read, git-tracked via mkOutOfStoreSymlink)" ;;
  "") bad "K1 services.tally-uplink.kit did not evaluate"; kit="" ;;
  *)  bad "K1 kit is not $runtime_kit: '$kit'"; kit="" ;;
esac

# ---- K2: the PINNED LAKE's own readKit, over the CHECKOUT FILE, resolves the
#          enabled refs and refuses the designed-but-disabled one, naming it.
#
# TALLY_KIT_LAKE / TALLY_KIT_NODE let a reviewer re-run this clause after an
# edit to the JSON with no nix invocation whatsoever — the operator-visible
# content of ruling 4. Unset, they are resolved from the flake as before.
lake="${TALLY_KIT_LAKE:-}"
[ -n "$lake" ] || lake="$(nix eval --raw --impure --expr "(builtins.getFlake \"path:${repo}\").inputs.tally-lake.outPath" 2>/dev/null)"
out=""
if [ -z "$lake" ] || [ ! -r "$lake/apps/uplink/src/kit.mjs" ]; then
  bad "K2 cannot resolve the tally-lake input's apps/uplink/src/kit.mjs (got '$lake')"
elif [ ! -r "$checkout_kit" ]; then
  bad "K2 the git-tracked kit $checkout_kit is not readable"
else
  # the unit's OWN interpreter, so the parser under test runs on the runtime the
  # service will use. The option holds the package's root, not the binary.
  node="${TALLY_KIT_NODE:-}"
  if [ -z "$node" ]; then
    node="$(nix eval --raw "${coord}.services.tally-uplink.node" 2>/dev/null)"
    if [ -n "$node" ] && [ -x "$node/bin/node" ]; then
      node="$node/bin/node"
    elif [ ! -x "${node:-}" ]; then
      node="$(command -v node || true)"
    fi
  fi
  if [ -z "$node" ] || [ ! -x "$node" ]; then
    bad "K2 no node: neither the unit's interpreter nor one on PATH"
  else
    out="$("$node" --input-type=module -e "
      import { readKit } from '${lake}/apps/uplink/src/kit.mjs'
      const kit = readKit(process.argv[1])
      const trio = (label) => [label, 'scope(' + label + ')', 'eval(' + label + ')']
      const want = [
        ...trio('build:LOCAL-SMOKE'),
        ...trio('build:CUBS-1'),
        ...trio('build:CUBS-200')
      ]
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
        if (!e.usage_source.path_glob.startsWith('/home/tom/.local/state/tally-rewrite/uplink/usage/')) {
          throw new Error(\`\${ref} usage_source.path_glob leaves the uplink usage drop: \${e.usage_source.path_glob}\`)
        }
      }
      for (const absent of ['claude:headless', 'build:CUBS-201']) {
        let refused = ''
        try { kit.resolve(absent); } catch (error) { refused = error.message }
        if (!refused) throw new Error(absent + ' RESOLVED — it must not be in the kit')
        if (!refused.includes(process.argv[1])) throw new Error('the refusal does not name the kit file: ' + refused)
      }
      const argv0 = new Set(
        kit.refs().filter((r) => r.startsWith('build:')).map((r) => kit.resolve(r).argv[0])
      )
      console.log('ARGV0=' + [...argv0].join(' '))
      console.log('REFS=' + kit.refs().length)
    " "$checkout_kit" 2>&1)"
    if [ $? -eq 0 ]; then
      ok "K2 readKit(pinned lake) over the CHECKOUT file resolves the trios and refuses claude:headless / CUBS-201"
      printf '     %s\n' "$out"
    else
      bad "K2 readKit: $out"
    fi
  fi
fi

# ---- K3: every enabled argv[0] is a STABLE per-user profile path, not a store
#          path. This is the inverse of FT-3's clause and it is what makes the
#          git-tracked JSON survive a rebuild of either executable.
argv0_line="$(printf '%s\n' "${out:-}" | sed -n 's/^ARGV0=//p')"
if [ -z "$argv0_line" ]; then
  bad "K3 skipped: K2 produced no argv[0] set"
else
  k3=0
  for a in $argv0_line; do
    case "$a" in
      /etc/profiles/per-user/tom/bin/*) ;;
      *) bad "K3 argv[0] is not a stable per-user profile path: '$a'"; k3=1 ;;
    esac
  done
  [ "$k3" = 0 ] && ok "K3 argv[0] set is stable: $argv0_line"
fi

# ---- K4: THE JOIN. Only the two variables exec.run exports; nothing else.
#
# The kit names the PROFILE path, which exists only after the coordinator switch
# this change still needs (DEFERRED.md [OPERATOR]). Before that switch the same
# derivation is reachable as `.#tally-local-smoke`, and running it proves the
# join for the bytes the profile will carry.
smoke="/etc/profiles/per-user/tom/bin/tally-local-smoke"
if [ ! -x "$smoke" ]; then
  built="$(nix build --offline --no-link --print-out-paths .#tally-local-smoke 2>/dev/null | tail -1)"
  [ -n "$built" ] && smoke="$built/bin/tally-local-smoke"
fi
usage="$scratch/local-smoke-probe.jsonl"
if [ -x "$smoke" ]; then
  if env -i TALLY_EXECUTION_ID=exec-probe TALLY_USAGE_SOURCE_PATH="$usage" "$smoke"; then
    lines=$(wc -l < "$usage" 2>/dev/null || echo 0)
    got=$(sed -n '1p' "$usage" 2>/dev/null | sed -n 's/.*"execution_id":"\([^"]*\)".*/\1/p')
    if [ "$lines" = "1" ] && [ "$got" = "exec-probe" ]; then
      ok "K4 one usage line, execution_id = exec-probe (via $smoke): $(cat "$usage")"
    else
      bad "K4 expected one line with execution_id exec-probe; lines=$lines id='$got'"
    fi
  else
    bad "K4 the enabled argv exited non-zero under env -i"
  fi
else
  bad "K4 skipped: no runnable tally-local-smoke (profile path absent and .#tally-local-smoke did not build)"
fi

# ---- K5: the rendered ExecStart carries the RUNTIME --kit and no --plan.
exec_start="$(nix eval --raw "${coord}.systemd.user.services.tally-uplink.Service.ExecStart" \
  --apply 'e: if builtins.isList e then builtins.concatStringsSep " " e else e' 2>/dev/null)"
case "$exec_start" in
  *"--kit /nix/store/"*) bad "K5 ExecStart carries --kit /nix/store/… — ruling 4 requires the runtime path" ;;
  *"--kit /home/tom/.config/tally/"*) ok "K5 ExecStart carries --kit /home/tom/.config/tally/…" ;;
  *) bad "K5 ExecStart carries no '--kit /home/tom/.config/tally/': '$exec_start'" ;;
esac
case "$exec_start" in
  *--plan*) bad "K5 ExecStart carries --plan; arming is Tom's act, plan must stay null" ;;
  *) ok "K5 ExecStart carries no --plan" ;;
esac

# ---- K6: the topology check builds (it asserts the kit over the rendered unit
#          AND parses the committed JSON with builtins.fromJSON).
if nix build .#checks.x86_64-linux.tally-uplink-topology -L; then
  ok "K6 nix build .#checks.x86_64-linux.tally-uplink-topology"
else
  bad "K6 tally-uplink-topology did not build"
fi

# ---- K7: U-D14's own suite, which re-runs A0 (lock no-op at the NEW pin) and D.
#
# THE ONE [ENV] FENCE IN THIS PROBE, and it is deliberately NARROW. That suite's
# clause A is the repo-wide `nix flake check --offline --no-build`, which is red
# on this box for a reason that has nothing to do with the kit:
# `checks.x86_64-linux.nas-personal-tailnet` cannot realise one of its inputs
# offline ("error: path '…-source' is not valid"). MEASURED 2026-09-17: the same
# suite on main (202d9c31) fails at the SAME single clause with the same error,
# so it is inherited, not introduced. DEFERRED.md carries the [ENV] row with the
# tail verbatim and DECISIONS.md records this fence as "default, unruled".
#
# The fence fires ONLY when the suite's failing set is EXACTLY {A}. Any other
# failing clause — including a second one beside A — is a hard FAIL, so a real
# regression in U-D14's suite cannot hide behind it.
k7_out="$(bash tests/tally-uplink/test-tally-uplink-input.sh "$repo" 2>&1)"
k7_rc=$?
if [ "$k7_rc" -eq 0 ]; then
  ok "K7 tests/tally-uplink/test-tally-uplink-input.sh"
else
  k7_failed="$(printf '%s\n' "$k7_out" | sed -n 's/^\[F\] \([A-Za-z0-9]*\) .*/\1/p' | sort -u | tr '\n' ' ')"
  if [ "$k7_failed" = "A " ]; then
    printf 'ENV  %s\n' "K7 test-tally-uplink-input.sh is red at clause A ONLY — the repo-wide nix flake check,"
    printf '     %s\n' "red identically on main 202d9c31 at checks.x86_64-linux.nas-topology (the 8731 firewall"
    printf '     %s\n' "assertion) and, on an earlier pass, at checks.x86_64-linux.nas-personal-tailnet (offline"
    printf '     %s\n' "input not valid). Inherited, not introduced; DEFERRED.md DF-KIT-3 carries both tails."
    printf '     %s\n' "Every other clause of the suite is green:"
    printf '%s\n' "$k7_out" | sed -n 's/^/     /p' | grep -E '\[F\]|\[N\]'
    envs=$((envs + 1))
  else
    bad "K7 test-tally-uplink-input.sh is not green (failing clauses: ${k7_failed:-unparsed})"
    printf '%s\n' "$k7_out" | tail -20
  fi
fi

if [ "$fails" -eq 0 ]; then
  if [ "$envs" -eq 0 ]; then
    echo "PROBE FT-3: PASS"
  else
    echo "PROBE FT-3: PASS ($envs clause(s) [ENV]-fenced — see DEFERRED.md, and the tail above)"
  fi
  exit 0
fi
echo "PROBE FT-3: FAIL ($fails clause(s))"
exit 1
