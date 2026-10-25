# wifi-ladder: the client's home Wi-Fi ladder (hosts/client/wifi-ladder.nix).
#
#   wifi-ladder guard     one pass: step down a rung when the NAS (rung 1) or
#                         the BE550 (rung 2) has stopped serving this laptop
#   wifi-ladder return    loop while rung 2 or 3 is active: step back up to
#                         rung 1 once the NAS answers again
#   wifi-ladder status    print the rung and every probe (read-only)
#   wifi-ladder hold      pause automatic returns until reboot; `release` undoes
#
# WIFI_LADDER_DRY_RUN=1 makes guard/return log the nmcli call instead of running it.

IFACE=wlo1
R1=thomas-6ghz        # DHCP from the NAS: NAS gateway, AdGuard DNS (normal life)
R2=thomas-6ghz-direct # same SSID, static 10.42.0.16, BE550 as gateway and DNS
R3=Freebox-AB3ACE     # the ISP box's own Wi-Fi (imperative keyfile, priority 0)
NAS=10.42.0.1
BE550=10.42.0.3
STATE=/run/wifi-ladder
mkdir -p "$STATE"

say() { echo "wifi-ladder: $*" >&2; }

# The profile on the radio, but only once NetworkManager calls it activated.
# Mid-activation (association, DHCP) is NetworkManager's own business: its
# dhcp-timeout and autoconnect-retries walk the ladder down when DHCP never
# answers, so the guard never acts on a half-configured link.
active() {
  local state
  state=$(nmcli -g GENERAL.STATE device show "$IFACE" 2>/dev/null || true)
  case "$state" in
    100*) nmcli -g GENERAL.CONNECTION device show "$IFACE" 2>/dev/null || true ;;
    *) echo "" ;;
  esac
}

# The rcode for a random, uncacheable name, or "timeout". A random name forces
# the resolver to ask its upstream, so NOERROR/NXDOMAIN proves the whole
# resolver -> internet path, not a cache hit.
rcode() {
  local out
  out=$(dig +time=3 +tries=1 @"$1" "ladder-$(date +%s%N).example.com" A 2>/dev/null) || {
    echo timeout
    return 0
  }
  grep -oE 'status: [A-Z]+' <<<"$out" | head -n 1 | cut -d' ' -f2 || echo timeout
}
resolves() { case "$(rcode "$1")" in NOERROR | NXDOMAIN) return 0 ;; *) return 1 ;; esac; }
pings() { ping -c 1 -W 2 "$1" >/dev/null 2>&1; }

# Rung 1 works when the NAS answers as gateway AND AdGuard resolves through it.
nas_ok() { pings "$NAS" && resolves "$NAS"; }
# Rung 2 works when the BE550 answers AND its own resolver reaches the internet.
be550_ok() { pings "$BE550" && resolves "$BE550"; }

act() {
  if [ -n "${WIFI_LADDER_DRY_RUN:-}" ]; then
    say "DRY RUN: nmcli $*"
    return 0
  fi
  nmcli "$@"
}

step_to() {
  say "stepping to $1"
  date +%s >"$STATE/stepped-down"
  act --wait 90 connection up "$1" ifname "$IFACE"
}

guard() {
  exec 9>"$STATE/lock"
  flock -w 120 9 || exit 0
  local cur i
  cur=$(active)
  case "$cur" in
    "$R1")
      for i in 1 2 3; do
        [ "$(active)" = "$R1" ] || return 0
        if nas_ok; then
          say "rung 1 ($R1) healthy on probe $i"
          return 0
        fi
        [ "$i" -lt 3 ] && sleep 10
      done
      # The NAS failed three probes in ~30 s. Move only when a lower rung is
      # actually better: an internet outage behind the Freebox fails every
      # rung alike, and then staying home is right.
      if be550_ok; then
        say "NAS failed 3 probes, BE550 resolves: the NAS is the broken piece"
        step_to "$R2" || step_to "$R3" || true
      elif ! pings "$BE550"; then
        say "NAS and BE550 both silent"
        step_to "$R3" || true
      else
        say "NAS failing but BE550 cannot resolve either: uplink outage, staying on $R1"
      fi
      ;;
    "$R2")
      for i in 1 2 3; do
        [ "$(active)" = "$R2" ] || return 0
        if be550_ok; then
          say "rung 2 ($R2) healthy on probe $i"
          return 0
        fi
        [ "$i" -lt 3 ] && sleep 10
      done
      if ! pings "$BE550"; then
        say "BE550 silent for 3 probes"
        step_to "$R3" || true
      else
        say "BE550 answers but cannot resolve: uplink outage, staying on $R2"
      fi
      ;;
    *) return 0 ;; # rung 3, away from home, or mid-activation
  esac
}

ssid_of() { nmcli -g 802-11-wireless.ssid connection show "$1" 2>/dev/null || true; }
visible() {
  local ssid
  ssid=$(ssid_of "$1")
  [ -n "$ssid" ] || return 1
  # --rescan auto: 6 GHz BSSes drop out of the cached list between
  # NetworkManager's own background scans (measured 2026-10-25).
  nmcli -t -f SSID device wifi list ifname "$IFACE" --rescan auto 2>/dev/null | grep -Fqx "$ssid"
}

return_loop() {
  local cur now last backoff earliest passes=0
  now=$(date +%s)
  last=$(cat "$STATE/returned" 2>/dev/null || echo 0)
  backoff=$(cat "$STATE/backoff" 2>/dev/null || echo 60)
  # A step-down within 15 min of the last return means that return failed:
  # double the wait (cap 1 h). Otherwise start fresh at 1 min.
  if [ $((now - last)) -lt 900 ]; then
    backoff=$((backoff * 2))
    [ "$backoff" -gt 3600 ] && backoff=3600
  else
    backoff=60
  fi
  echo "$backoff" >"$STATE/backoff"
  earliest=$((now + backoff))
  say "on a lower rung; probing the NAS every 60 s, first return no sooner than ${backoff}s from now"
  while :; do
    cur=$(active)
    case "$cur" in
      "$R2" | "$R3") ;;
      "")
        sleep 60 # between profiles; NetworkManager is still deciding
        continue
        ;;
      *)
        say "now on '$cur'; return loop done"
        return 0
        ;;
    esac
    if [ -e "$STATE/hold" ]; then
      passes=0
      sleep 60
      continue
    fi
    # From rung 3 the NAS is probed over the tailnet subnet route (the NAS
    # advertises 10.42.0.0/24); from rung 2 directly on the LAN.
    if nas_ok && { [ "$cur" = "$R2" ] || visible "$R1"; }; then
      passes=$((passes + 1))
    else
      passes=0
    fi
    if [ "$passes" -ge 3 ] && [ "$(date +%s)" -ge "$earliest" ]; then
      exec 9>"$STATE/lock"
      if flock -w 120 9; then
        say "NAS healthy for 3 probes: stepping up to $R1"
        date +%s >"$STATE/returned"
        if ! act --wait 60 connection up "$R1" ifname "$IFACE"; then
          say "$R1 did not activate; back to $cur"
          act --wait 90 connection up "$cur" ifname "$IFACE" || true
          backoff=$((backoff * 2))
          [ "$backoff" -gt 3600 ] && backoff=3600
          echo "$backoff" >"$STATE/backoff"
          earliest=$(($(date +%s) + backoff))
        fi
        flock -u 9
      fi
      passes=0
    fi
    sleep 60
  done
}

ping_word() { if pings "$1"; then echo ok; else echo FAIL; fi; }

status() {
  local cur f hold=no
  cur=$(active)
  if [ -e "$STATE/hold" ]; then hold=yes; fi
  echo "rung:         ${cur:-<none or activating>}"
  echo "connectivity: $(nmcli -g CONNECTIVITY general status 2>/dev/null || echo '?')"
  echo "NAS $NAS:     ping $(ping_word "$NAS"), dns $(rcode "$NAS")"
  echo "BE550 $BE550:  ping $(ping_word "$BE550"), dns $(rcode "$BE550")"
  echo "hold:         $hold"
  for f in stepped-down returned backoff; do
    if [ -e "$STATE/$f" ]; then echo "$f: $(cat "$STATE/$f")"; fi
  done
}

case "${1:-status}" in
  guard) guard ;;
  return) return_loop ;;
  status) status ;;
  hold) touch "$STATE/hold" ;;
  release) rm -f "$STATE/hold" ;;
  *)
    echo "usage: wifi-ladder guard|return|status|hold|release" >&2
    exit 2
    ;;
esac
