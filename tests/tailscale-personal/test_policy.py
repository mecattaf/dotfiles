"""Inspect evaluated NixOS variants, not merely comments in module source."""
import json
import re
import sys
import unittest

with open(sys.argv.pop(1), encoding="utf-8") as stream:
    FIXTURES = json.load(stream)


class PersonalTailnetPolicy(unittest.TestCase):
    def test_default_off_has_no_container_or_network_changes(self):
        c = FIXTURES["disabled"]
        self.assertFalse(c["enabled"])
        self.assertIsNone(c["container"])
        self.assertEqual(c["input"], "")
        self.assertNotIn("personal_isolation", c["tables"])

    def test_host_headscale_and_dns_unchanged_in_every_variant(self):
        baseline = FIXTURES["disabled"]
        for name, c in FIXTURES.items():
            with self.subTest(name=name):
                if name == "unapproved":
                    self.assertEqual(c["failedAssertions"], [
                        "Approve node-scoped SaaS Funnel policy before enabling the public Headscale endpoint."])
                else:
                    self.assertEqual(c["failedAssertions"], [])
                self.assertEqual(c["hostTailscale"], baseline["hostTailscale"])
                self.assertEqual(c["hostDns"], ["100.64.0.1"])
                self.assertNotIn("ve-nas-saas", c["trusted"])
                if c["container"]:
                    self.assertEqual(c["container"]["failedAssertions"], [])

    def test_kernel_mode_independent_persistent_identity_and_resolver(self):
        n = FIXTURES["enabled"]["container"]
        self.assertTrue(n["privateNetwork"])
        self.assertTrue(n["enableTun"])
        self.assertFalse(n["ephemeral"])
        self.assertEqual(n["bindMounts"]["/var/lib/tailscale"]["hostPath"], "/var/lib/tailscale-personal")
        self.assertEqual(n["forwardPorts"], [])
        self.assertFalse(n["useHostResolvConf"])
        self.assertEqual(n["nameservers"], ["10.42.0.1"])
        self.assertEqual(n["tailscale"]["interfaceName"], "tailscale0")
        self.assertEqual(n["tailscale"]["useRoutingFeatures"], "server")
        self.assertIsNone(n["tailscale"]["authKeyFile"])

    def test_no_automatic_login_route_consumption_or_ssh(self):
        prefs = FIXTURES["enabled"]["container"]["tailscale"]["extraSetFlags"]
        self.assertEqual(prefs, ["--accept-dns=false", "--accept-routes=false", "--ssh=false",
                                 "--advertise-routes=", "--advertise-exit-node=true"])
        self.assertFalse(any("login-server" in x or x.startswith("--exit-node=") for x in prefs))
        self.assertIn("--advertise-exit-node=false", FIXTURES["minimal"]["container"]["tailscale"]["extraSetFlags"])

    def test_host_admissions_only_exact_interface_source_destination_ports(self):
        for variant, allowed in [("enabled", {53, 4533, 32400}),
                                 ("minimal", {53}), ("public", {53, 4533, 32400, 8090}),
                                 ("tls", {53, 443, 4533, 32400, 8443})]:
            text = FIXTURES[variant]["input"]
            for line in text.splitlines():
                if not line.strip():
                    continue
                self.assertIn('iifname "ve-nas-saas" ip saddr 172.31.255.2 ip daddr ', line)
                self.assertRegex(line, r'ip daddr (10\.42\.0\.1|172\.31\.255\.1) ')
                match = re.search(r'dport (.*) accept', line)
                self.assertIsNotNone(match)
                self.assertLessEqual(set(map(int, re.findall(r'\d+', match[1]))), allowed)
            for forbidden in (22, 2283, 8080, 8091):
                self.assertNotRegex(text, rf'dport (?:\{{[^}}]*\b)?{forbidden}\b')

    def test_early_guards_clear_marks_deny_spoofing_and_cross_tailnet_routing(self):
        text = FIXTURES["enabled"]["tables"]["personal_isolation"]
        self.assertIn('iifname "ve-nas-saas" meta mark set 0', text)
        self.assertIn('priority -155', text)
        self.assertIn('ip saddr != 172.31.255.2 counter drop', text)
        self.assertIn('ip daddr @non_internet_v4 counter drop', text)
        self.assertIn('100.64.0.0/10', text)
        self.assertIn('10.0.0.0/8', text)
        self.assertIn('oifname != "enp1s0" counter drop', text)
        self.assertIn('meta nfproto != ipv4 counter drop', text)
        self.assertIn('oifname "ve-nas-saas" counter drop', text)
        nat = FIXTURES["enabled"]["tables"]["personal_nat"]
        self.assertIn('iifname "ve-nas-saas" oifname "enp1s0" ip saddr 172.31.255.2 snat to 10.42.0.1', nat)

    def test_media_proxies_are_private_and_keep_existing_wake_endpoints(self):
        n = FIXTURES["enabled"]["container"]
        self.assertTrue(n["proxies"]["personal-music"].endswith("172.31.255.1:4533"))
        self.assertTrue(n["proxies"]["personal-plex"].endswith("172.31.255.1:32400"))
        self.assertNotIn("personal-headscale-funnel", n["proxies"])
        self.assertIn('iifname "eth0" drop', n["tables"]["personal_ingress"])
        self.assertIn('iifname "tailscale0" drop', n["tables"]["personal_ingress"])

    def test_funnel_is_opt_in_single_headscale_backend_not_media(self):
        n = FIXTURES["public"]["container"]
        self.assertEqual(n["sockets"]["personal-headscale"], "127.0.0.1:18090")
        self.assertTrue(n["proxies"]["personal-headscale"].endswith("10.42.0.1:8090"))
        funnel = n["proxies"]["personal-headscale-funnel"]
        self.assertIn("funnel --https=8443 http://127.0.0.1:18090", funnel)
        self.assertNotIn("--bg", funnel)
        for forbidden in ("4533", "32400", "--https=443 ", "8080", "8091"):
            self.assertNotIn(forbidden, funnel)
        self.assertNotIn("8090 accept", FIXTURES["enabled"]["input"])

    def test_custom_https_reuses_host_certificate_without_sharing_keys(self):
        c = FIXTURES["tls"]
        self.assertEqual(set(c["certificates"]), {
            "https://music.mecattaf.dev:8443", "https://plex.mecattaf.dev:8443"})
        for v in c["certificates"].values():
            self.assertEqual(v["listenAddresses"], ["172.31.255.1"])
            self.assertEqual(v["useACMEHost"], "mecattaf.dev")
        self.assertEqual(list(c["container"]["bindMounts"]), ["/var/lib/tailscale"])
        self.assertEqual(c["container"]["sockets"]["personal-media-tls"], "0.0.0.0:443")

    def test_firewall_and_tls_lifecycle_have_recovery_and_one_way_ordering(self):
        lifecycle = FIXTURES["tls"]["lifecycle"]
        for child, parent in [("container@nas-saas", "nftables"), ("caddy", "container@nas-saas")]:
            for dependency in ("after", "requires", "bindsTo", "partOf", "wantedBy"):
                self.assertIn(parent + ".service", lifecycle[child][dependency])
            self.assertNotIn(child + ".service", lifecycle[parent]["after"])
        self.assertNotIn("caddy", FIXTURES["enabled"]["lifecycle"])


if __name__ == "__main__":
    unittest.main()
