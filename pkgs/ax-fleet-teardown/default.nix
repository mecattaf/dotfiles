{
  writeShellApplication,
  k3s,
  iptables,
  nftables,
  iproute2,
  procps,
  coreutils,
  gnugrep,
  systemd,
}:
# ax-fleet-teardown: the second half of the kill switch (DESIGN.md section 13).
#
# The k3s unit runs with KillMode=process, so pods and containerd shims outlive
# it; switching `myAxFleet.enable = false` alone leaves them, plus cni0,
# flannel.1, the KUBE-/FLANNEL-/CNI- rules and ip_forward=1. This wraps the
# pinned package's own k3s-killall.sh, removes the guard chains only when the
# running generation does not declare them (a pre-ax generation), then
# restores the sysctls recorded before k3s first ran on this host
# (/var/lib/ax-fleet/sysctl-before.conf, written by the activation snippet in
# modules/ax-fleet/k3s.nix).
#
# PATH is pinned (inheritPath = false). The upstream killall's
# remove_interfaces runs `tailscale set --advertise-routes=` whenever a
# `tailscale` binary is on PATH; on the NAS that would withdraw the
# 10.42.0.0/24 subnet route (hosts/nas/headscale.nix). With the caller's PATH
# cut off, `command -v tailscale` fails and the call is skipped; the killall
# wrapper still prefixes its own dependencies. The explicit check below makes
# the teardown refuse to run if tailscale ever becomes reachable anyway.
#
# Left on disk on purpose: /mnt/fast/k3s, the data-pool directories and
# /var/lib/ax-fleet. Deleting them is Tom's call.
writeShellApplication {
  name = "ax-fleet-teardown";
  inheritPath = false;
  runtimeInputs = [
    k3s
    iptables
    nftables
    iproute2
    procps
    coreutils
    gnugrep
    systemd
  ];
  text = ''
    if [ "$(id -u)" -ne 0 ]; then
      echo "ax-fleet-teardown: run as root (sudo)" >&2
      exit 1
    fi

    if command -v tailscale >/dev/null 2>&1; then
      echo "ax-fleet-teardown: tailscale is on PATH; k3s-killall.sh would clear the advertised routes. Refusing." >&2
      exit 1
    fi

    if systemctl is-enabled --quiet k3s.service 2>/dev/null; then
      echo "ax-fleet-teardown: note: k3s.service is still part of this generation;" >&2
      echo "  k3s-killall.sh stops it now, and it starts again at the next boot or switch." >&2
    fi

    echo "== k3s-killall.sh (${k3s.version})"
    ${k3s}/bin/k3s-killall.sh || echo "k3s-killall.sh exited $?; continuing" >&2

    # Fix round 3: a harness or control generation declares the guards
    # whatever `enable` says (the kill switch leaves pods running until this
    # script), so they stay; a generation from before ax never had them, and
    # then they go.
    if [ -e /etc/ax-fleet/guard-declared ]; then
      echo "== guards: declared by this generation ($(cat /etc/ax-fleet/guard-declared)); left in place"
    else
      echo "== guard chains"
      while iptables -w -t mangle -D FORWARD -j ax-fleet-guard 2>/dev/null; do :; done
      iptables -w -t mangle -F ax-fleet-guard 2>/dev/null || true
      iptables -w -t mangle -X ax-fleet-guard 2>/dev/null || true
      while iptables -w -D OUTPUT -j ax-fleet-api 2>/dev/null; do :; done
      iptables -w -F ax-fleet-api 2>/dev/null || true
      iptables -w -X ax-fleet-api 2>/dev/null || true

      echo "== NAS guard table"
      nft delete table inet ax-fleet-guard 2>/dev/null || true
    fi

    snap=/var/lib/ax-fleet/sysctl-before.conf
    if [ -s "$snap" ]; then
      echo "== sysctl restore from $snap"
      # -e: a conntrack key recorded while nf_conntrack was loaded may be
      # absent now; skip it rather than abort the restore.
      sysctl -e -p "$snap"
    else
      echo "ax-fleet-teardown: no $snap; sysctls left as they are" >&2
    fi

    echo "== left behind (should be empty)"
    ip -br link show 2>/dev/null | grep -E '^(cni0|flannel\.1|veth)' || true
    iptables-save 2>/dev/null | grep -cE 'KUBE-|FLANNEL|CNI-' || true
    pgrep -a containerd-shim || true
    echo "ax-fleet-teardown: done"
  '';
}
