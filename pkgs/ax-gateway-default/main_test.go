package main

import (
	"testing"

	"github.com/google/ax/pkg/apis/v1alpha1"
)

func TestHostIsOpen(t *testing.T) {
	for host, want := range map[string]bool{
		"10.42.0.5/32": false, "*": true, "": true, " * ": true,
		"0.0.0.0/1": true, "128.0.0.0/1": true, "0.0.0.0/0": true, "::/0": true,
		"10.0.0.0/8": true, "10.0.0.0/9": false, "fd00::/48": false, "fd00::/16": true,
		"api.example.com": false, "10.1.2.3/abc": true, "a/b/c": true, "worker.lan/32": true,
	} {
		if got := hostIsOpen(host); got != want {
			t.Errorf("hostIsOpen(%q) = %v, want %v", host, got, want)
		}
	}
}

func gw(al *v1alpha1.EgressAllowlist) *v1alpha1.Gateway {
	return &v1alpha1.Gateway{Spec: &v1alpha1.GatewaySpec{Egress: &v1alpha1.EgressConfig{Allowlist: al}}}
}

func TestUnsafeReason(t *testing.T) {
	halogen := &v1alpha1.HostRule{Host: "10.42.0.5/32", Port: 8731}
	cases := []struct {
		name string
		g    *v1alpha1.Gateway
		safe bool
	}{
		{"no spec", &v1alpha1.Gateway{}, false},
		{"no allowlist", gw(nil), false},
		{"empty hosts", gw(&v1alpha1.EgressAllowlist{}), false},
		{"halogen", gw(&v1alpha1.EgressAllowlist{Hosts: []*v1alpha1.HostRule{halogen}}), true},
		{"halogen plus star", gw(&v1alpha1.EgressAllowlist{Hosts: []*v1alpha1.HostRule{halogen, {Host: "*", Port: 443}}}), false},
		{"two halves", gw(&v1alpha1.EgressAllowlist{Hosts: []*v1alpha1.HostRule{{Host: "0.0.0.0/1"}, {Host: "128.0.0.0/1"}}}), false},
	}
	for _, c := range cases {
		if got := unsafeReason(c.g) == ""; got != c.safe {
			t.Errorf("%s: safe = %v, want %v (%q)", c.name, got, c.safe, unsafeReason(c.g))
		}
	}
}
