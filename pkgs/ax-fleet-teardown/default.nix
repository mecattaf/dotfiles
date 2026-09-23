{
  writeShellApplication,
  k3s,
  iptables,
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
# pinned package's own k3s-killall.sh, removes the coordinator guard chain
# (the firewall reload of the disabled generation does not know it), then
# restores the sysctls recorded before k3s first ran on this host
# (/var/lib/ax-fleet/sysctl-before.conf, written by the activation snippet in
# modules/ax-fleet/k3s.nix).
#
# Left on disk on purpose: /mnt/fast/k3s, the data-pool directories and
# /var/lib/ax-fleet. Deleting them is Tom's call.
writeShellApplication {
  name = "ax-fleet-teardown";
  runtimeInputs = [
    k3s
    iptables
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

    if systemctl is-enabled --quiet k3s.service 2>/dev/null; then
      echo "ax-fleet-teardown: note: k3s.service is still part of this generation;" >&2
      echo "  k3s-killall.sh stops it now, and it starts again at the next boot or switch." >&2
    fi

    echo "== k3s-killall.sh (${k3s.version})"
    ${k3s}/bin/k3s-killall.sh || echo "k3s-killall.sh exited $?; continuing" >&2

    echo "== guard chain"
    while iptables -w -t mangle -D FORWARD -j ax-fleet-guard 2>/dev/null; do :; done
    iptables -w -t mangle -F ax-fleet-guard 2>/dev/null || true
    iptables -w -t mangle -X ax-fleet-guard 2>/dev/null || true

    snap=/var/lib/ax-fleet/sysctl-before.conf
    if [ -s "$snap" ]; then
      echo "== sysctl restore from $snap"
      sysctl -p "$snap"
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
