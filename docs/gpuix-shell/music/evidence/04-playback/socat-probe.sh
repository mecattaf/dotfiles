#!/usr/bin/env bash
# The brief's required measurement: mpv idle with --input-ipc-server for 5 s, queried with socat.
set -u
S=${1:?scratch dir}; SOCAT=/nix/store/5fzpsj7yyzmyh3pgdnh6q7qxgdaah354-socat-1.8.1.3/bin/socat; MPV=/etc/profiles/per-user/tom/bin/mpv
( timeout 5 $MPV --no-config --no-video --idle=yes --ao=null --input-ipc-server=$S/mpv.sock --msg-level=all=warn >/dev/null 2>&1 & )
for i in $(seq 1 20); do [ -S $S/mpv.sock ] && break; sleep 0.1; done
q() { echo "> $1"; echo "$1" | $SOCAT - UNIX-CONNECT:$S/mpv.sock; }
t0=$(date +%s%N); q '{"command":["get_property","mpv-version"],"request_id":1}'; t1=$(date +%s%N); echo "roundtrip_ms=$(( (t1-t0)/1000000 )) (includes socat startup)"
q '{"command":["get_property","idle-active"]}'
q '{"command":["get_property","current-ao"]}'
q '{"command":["set_property","user-data/gpuix/owner","gpuix-shell-music"]}'
q '{"command":["get_property","user-data/gpuix/owner"]}'
sleep 5.5; echo "after timeout(SIGTERM): socket file exists=$([ -S $S/mpv.sock ] && echo yes || echo no)"; echo "connect after exit:"; echo '{}' | $SOCAT - UNIX-CONNECT:$S/mpv.sock 2>&1 | sed -E 's/^[0-9/ :]+socat\[[0-9]+\] //'
rm -f -- "$S/mpv.sock"
