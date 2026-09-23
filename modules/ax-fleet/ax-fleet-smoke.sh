# ax-fleet-smoke: run one proof case as a real ax Task and print a JSON receipt.
# (Wrapped by writeShellApplication in ./ax.nix: strict mode, pinned PATH, and
# AX_FLEET_{ATESPACE,HALOGEN,HALOGEN_CIDR,API} from the module.)
#
#   ax-fleet-smoke halogen     [--hold N]  one chat completion against Halogen
#   ax-fleet-smoke pi          [--hold N]  pi against Halogen, schema-valid result
#   ax-fleet-smoke exit N      [--hold N]  the command exits N (Failed ExitCode=N)
#   ax-fleet-smoke egress-deny [URL]       GET a non-allowlisted URL (default the
#                                          coordinator's LAN address); must be refused
#   ax-fleet-smoke floor N                 N Tasks in a row; none ResourceExhausted
#   ax-fleet-smoke probe       [--hold N]  `claude --version` and a GET of Halogen's
#                                          /v1/models, sandboxClass gvisor; needs an
#                                          --image that carries claude-code (the
#                                          fleet image does not, DESIGN.md 11)
#
# Options: --hold N (re-read the phase after N seconds), --timeout N (per Task,
# default 900), --keep (do not delete the Tasks), --image REF (default: the
# fleet image, ax-fleet-image-ref), --sandbox-class C (spec.sandboxClass; empty
# means gVisor), --gateway NAME (spec.gateway.name, default halogen; `none`
# omits the gateway; ax-fleet-gateway-default then points the Task at the
# atespace's default Gateway, since stock ax would give it allow-all).
# Exit 0 only when the case passes. The receipt carries no secret: Tasks carry none (DESIGN.md 11).

export AX_SERVER="${AX_SERVER:-$AX_FLEET_API}"
ns="$AX_FLEET_ATESPACE"
hold=0
timeout=900
keep=0
image=""
sandbox_class=""
gateway=halogen
args=()
while [ $# -gt 0 ]; do
  case "$1" in
  --hold) hold="$2"; shift 2 ;;
  --timeout) timeout="$2"; shift 2 ;;
  --keep) keep=1; shift ;;
  --image) image="$2"; shift 2 ;;
  --sandbox-class) sandbox_class="$2"; shift 2 ;;
  --gateway) gateway="$2"; shift 2 ;;
  *) args+=("$1"); shift ;;
  esac
done
[ "${#args[@]}" -ge 1 ] || { sed -n '2,21p' "$0" >&2; exit 64; }
case_="${args[0]}"
[ -n "$image" ] || image="$(ax-fleet-image-ref)"
# Stock ax has no spec.sandboxClass and rejects the unknown field, so the
# probe sends none (ax v0.3.0 hardcodes gVisor).
run_id="$(date +%s)-$$"

# The Gateway's `port` is carried for the record only: ax v0.3.0 copies only
# the host into a CIDR rule and Substrate's evaluator never compares ports
# (REPORTED ax client.go:457-490, egresspolicy.go:133-158; MEASURED by the
# round-3 review: worker:2222 answered through this Gateway). The port is
# enforced on the NAS instead: its pods reach ${AX_FLEET_HALOGEN} and no other
# private address (modules/ax-fleet/control.nix, podEgress).
ensure_gateway() {
  ax -a "$ns" apply -f - >/dev/null <<YAML
apiVersion: ax.io/v1alpha1
kind: Gateway
metadata:
  name: halogen
  atespace: $ns
spec:
  egress:
    allowlist:
      hosts:
        - host: "$AX_FLEET_HALOGEN_CIDR"
          port: ${AX_FLEET_HALOGEN##*:}
YAML
}

# task_json NAME: the Task as JSON (empty object when absent). The status is
# protobuf JSON, which omits zero values: an exited command with exit code 0
# carries `exited: true` and no `exitCode` (MEASURED in the VM test).
task_json() {
  ax -a "$ns" get task "$1" 2>/dev/null | yq -o json '.' 2>/dev/null || echo '{}'
}

# run_task NAME CMD...: apply, wait for a terminal phase, hold, print a receipt.
run_task() {
  local name="$1"
  shift
  local cmd_json
  cmd_json="$(jq -cn '$ARGS.positional' --args -- "$@")"
  local class_line=""
  [ -z "$sandbox_class" ] || class_line="  sandboxClass: \"$sandbox_class\""
  local gateway_lines=""
  [ "$gateway" = none ] || gateway_lines="  gateway:
    name: \"$gateway\""
  ax -a "$ns" apply -f - >/dev/null <<YAML
apiVersion: ax.io/v1alpha1
kind: Task
metadata:
  name: $name
  atespace: $ns
spec:
  image: "$image"
$class_line
  command: $cmd_json
  env:
    - name: HALOGEN_URL
      value: "http://$AX_FLEET_HALOGEN"
$gateway_lines
YAML
  local t0 t phase="" deadline
  t0="$(date +%s)"
  deadline=$((t0 + timeout))
  while :; do
    t="$(task_json "$name")"
    phase="$(jq -r '.status.phase // ""' <<<"$t")"
    case "$phase" in Completed | Failed) break ;; esac
    if [ "$(date +%s)" -ge "$deadline" ]; then break; fi
    sleep 2
  done
  local settled
  settled="$(date +%s)"
  local after="$phase"
  if [ "$hold" -gt 0 ]; then
    sleep "$hold"
    after="$(task_json "$name" | jq -r '.status.phase // ""')"
    t="$(task_json "$name")"
  fi
  local result='null'
  if [ "$(jq -r '.status.command.exited // false' <<<"$t")" = true ]; then
    result="$(ax -a "$ns" result task "$name" 2>/dev/null | jq -c '.' 2>/dev/null || echo null)"
  fi
  jq -cn --arg name "$name" --arg phase "$phase" --arg after "$after" \
    --argjson t "$t" --argjson result "$result" --argjson secs "$((settled - t0))" --argjson hold "$hold" \
    '{task:$name, phase:$phase, phase_after_hold:$after, hold_seconds:$hold, settle_seconds:$secs,
      ready:(($t.status.conditions // []) | map(select(.type=="Ready")) | .[0] // null | if . then {reason, message} else null end),
      gateway_ready:(($t.status.conditions // []) | map(select(.type=="GatewayReady")) | .[0] // null | if . then {status, reason} else null end),
      exit_code:(if ($t.status.command.exited // false) then ($t.status.command.exitCode // 0) else null end), result_bytes:($t.status.command.resultBytes // null),
      result_sha256:($t.status.command.resultSha256 // null), result:$result}'
  if [ "$keep" -eq 0 ]; then ax -a "$ns" delete task "$name" >/dev/null 2>&1 || true; fi
}

run_case() {
case "$case_" in
halogen)
  r="$(run_task "smoke-halogen-$run_id" ax-agent halogen-smoke)"
  jq -c --arg case "$case_" '. + {case:$case, pass:(.phase=="Completed" and .phase_after_hold=="Completed" and .exit_code==0)}' <<<"$r"
  ;;
pi)
  r="$(run_task "smoke-pi-$run_id" ax-agent pi)"
  jq -c --arg case "$case_" '. + {case:$case, pass:(.phase=="Completed" and .phase_after_hold=="Completed" and (.result.valid == true))}' <<<"$r"
  ;;
exit)
  n="${args[1]:?usage: ax-fleet-smoke exit N}"
  r="$(run_task "smoke-exit-$run_id" ax-agent exit "$n")"
  if [ "$n" -eq 0 ]; then want=Completed; else want=Failed; fi
  jq -c --arg case "exit $n" --arg want "$want" --argjson n "$n" \
    '. + {case:$case, pass:(.phase==$want and .phase_after_hold==$want and .exit_code==$n and .ready.reason=="CommandExited")}' <<<"$r"
  ;;
egress-deny)
  url="${args[1]:-http://10.42.0.2/}"
  r="$(run_task "smoke-egress-$run_id" ax-agent fetch "$url")"
  # Refused either at the Gateway (the connection fails: curl rc != 0) or,
  # for an allowlisted host on a port the NAS drops (fix round 3), by the
  # egress gateway's own upstream error (502/503/504, the target never
  # answered), or by Substrate's egress router refusing the actor outright
  # (403 "egress denied": no policy, or a policy with no rules). Any other
  # HTTP status
  # is the target answering: fail. The deny targets in the VM answer 200.
  jq -c --arg case "$case_" --arg url "$url" --arg gw "$gateway" \
    '. + {case:$case, url:$url, gateway:$gw,
          refused_by:(if (.result.curl_rc // 0) != 0 then "gateway-connection"
                      elif ((.result.http_code // "") | test("^50[234]$")) then "egress-upstream"
                      elif (.result.http_code // "") == "403" then "egress-policy"
                      else null end)}
       | . + {pass:(.refused_by != null and .ready.reason=="CommandExited")}' <<<"$r"
  ;;
floor)
  n="${args[1]:?usage: ax-fleet-smoke floor N}"
  all='[]'
  for i in $(seq 1 "$n"); do
    r="$(run_task "smoke-floor-$run_id-$i" ax-agent exit 0)"
    all="$(jq -c --argjson r "$r" '. + [$r]' <<<"$all")"
  done
  jq -c --arg case "floor $n" --argjson n "$n" \
    '{case:$case, tasks:., pass:((length == $n) and all(.[]; .phase=="Completed" and ((.ready.message // "") | test("ResourceExhausted") | not)))}' <<<"$all"
  ;;
probe)
  r="$(run_task "smoke-probe-$run_id" ax-agent probe)"
  jq -c --arg case "$case_" --arg class "$sandbox_class" --arg image "$image" \
    '. + {case:$case, sandbox_class:$class, image:$image,
          pass:(.phase=="Completed" and .phase_after_hold=="Completed" and .exit_code==0
                and .result.claude_rc==0 and .result.http_code=="200")}' <<<"$r"
  ;;
*)
  echo "unknown case: $case_" >&2
  exit 64
  ;;
esac
}

ensure_gateway
receipt="$(run_case)"
printf '%s\n' "$receipt"
jq -e '.pass' <<<"$receipt" >/dev/null
