set -euo pipefail

# Query live device properties rather than a dispatcher event's old profile.
# A missing/disconnected device, or any failed query, leaves the gate closed.
profile=$(nmcli -g GENERAL.CONNECTION device show wlo1 2>/dev/null || true)
gateway=$(nmcli -g IP4.GATEWAY device show wlo1 2>/dev/null || true)
address=$(nmcli -g IP4.ADDRESS device show wlo1 2>/dev/null || true)
dns=$(nmcli -g IP4.DNS device show wlo1 2>/dev/null || true)
ssid=$(nmcli -g 802-11-wireless.ssid connection show id thomas-6ghz 2>/dev/null || true)

# Submit one atomic nftables transaction: an old permission never survives a
# transition to another Wi-Fi, the direct fallback, or a Tailscale-only path.
{
  echo 'flush set inet home_printing wifi_interfaces'
  if [[ "$profile" == thomas-6ghz && "$ssid" == thomas-6ghz \
    && "$gateway" == 10.42.0.1 && "$address" == 10.42.0.16/24 \
    && "$dns" == 10.42.0.1 ]]; then
    echo 'add element inet home_printing wifi_interfaces { "wlo1" }'
  fi
} | nft -f -
