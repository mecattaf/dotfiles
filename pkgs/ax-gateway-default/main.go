// ax-gateway-default: stock ax v0.3.0 gives a Task with no gateway, or one
// naming a Gateway its atespace lacks, an allow-all EgressPolicy
// (internal/controller/reconciler.go, "Default to allow all egress"). This
// fleet does not patch ax (Tom, 2026-09-23), so the default lives outside it:
// every declared atespace carries a default Gateway (the bootstrap applies
// it), and this loop points any Task in those atespaces that has no usable
// gateway at that default through ax's own UpdateTask. The controller then
// reconciles the Task again and replaces the actor's egress policy with the
// default Gateway's allowlist.
//
// It is a client of ax's public gRPC API, built from the same module tree;
// it changes nothing inside ax.
package main

import (
	"context"
	"flag"
	"fmt"
	"log/slog"
	"net/netip"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/google/ax/pkg/apis/v1alpha1"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/grpc/status"
)

func main() {
	server := flag.String("server", os.Getenv("AX_SERVER"), "ax-server address, host:port or http://host:port")
	spaces := flag.String("atespaces", "", "comma-separated atespace=defaultGateway pairs")
	every := flag.Duration("interval", 2*time.Second, "poll interval")
	once := flag.Bool("once", false, "one pass, then exit (tests)")
	flag.Parse()

	defaults := map[string]string{}
	for _, kv := range strings.Split(*spaces, ",") {
		if kv == "" {
			continue
		}
		ns, gw, ok := strings.Cut(kv, "=")
		if !ok || ns == "" || gw == "" {
			fmt.Fprintf(os.Stderr, "bad -atespaces entry %q (want atespace=gateway)\n", kv)
			os.Exit(64)
		}
		defaults[ns] = gw
	}
	if len(defaults) == 0 {
		fmt.Fprintln(os.Stderr, "no atespaces declared")
		os.Exit(64)
	}
	target := strings.TrimPrefix(strings.TrimPrefix(*server, "http://"), "https://")
	conn, err := grpc.NewClient(target, grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		slog.Error("connect", "target", target, "error", err)
		os.Exit(1)
	}
	defer conn.Close()
	client := v1alpha1.NewAXClient(conn)

	for {
		for ns, gw := range defaults {
			if err := pass(client, ns, gw); err != nil {
				slog.Warn("pass failed", "atespace", ns, "error", err)
			}
		}
		if *once {
			return
		}
		time.Sleep(*every)
	}
}

// pageSize bounds one ListTasks call. ax-server defaults to 50 and returns
// newest first, so an unpaginated pass never saw an older gateway-less Task
// once 50 newer ones existed (codex review 1, E2).
const pageSize = 200

// hostIsOpen mirrors the link's B10 rule (pkgs/substrate-link/src/apps/link/src/ax.ts
// cidrIsOpen) and the default-Gateway assertion in modules/ax-fleet/gateways.nix:
// "*" or empty is open, and ax sends every host containing "/" to Substrate as a
// CIDR, so one that does not parse or is /8 or wider (IPv4), /16 or wider (IPv6)
// counts as open.
func hostIsOpen(host string) bool {
	h := strings.ToLower(strings.TrimSpace(host))
	if h == "" || h == "*" {
		return true
	}
	if !strings.Contains(h, "/") {
		return false
	}
	addr, bits, ok := strings.Cut(h, "/")
	n, err := strconv.Atoi(bits)
	if !ok || err != nil || strings.Contains(bits, "/") || len(bits) > 3 {
		return true
	}
	a, err := netip.ParseAddr(addr)
	if err != nil {
		return true
	}
	if a.Is4() {
		return n > 32 || n <= 8
	}
	return n > 128 || n <= 16
}

// safe reports why a Gateway would not restrict egress, or "" when it does.
// Stock ax applies "*" when a Gateway has no egress allowlist
// (reconciler.go "Default to allow all egress"), and an empty host list writes
// no policy, so an existing actor keeps whatever it had (codex review 1, E3).
func unsafeReason(g *v1alpha1.Gateway) string {
	al := g.GetSpec().GetEgress().GetAllowlist()
	if al == nil {
		return "no egress allowlist (ax applies allow-all)"
	}
	if len(al.GetHosts()) == 0 {
		return "empty allowlist (ax writes no policy)"
	}
	for _, r := range al.GetHosts() {
		if hostIsOpen(r.GetHost()) {
			return fmt.Sprintf("open host %q", r.GetHost())
		}
	}
	return ""
}

func pass(client v1alpha1.AXClient, ns, def string) error {
	call := func() (context.Context, context.CancelFunc) {
		return context.WithTimeout(context.Background(), 10*time.Second)
	}
	ctx, cancel := call()
	dg, err := client.GetGateway(ctx, &v1alpha1.GetGatewayRequest{Atespace: ns, Name: def})
	cancel()
	if err != nil {
		// Without the default there is nothing safe to point at; the
		// bootstrap re-applies it. Log loudly, change nothing.
		return fmt.Errorf("default gateway %s/%s: %w", ns, def, err)
	}
	if why := unsafeReason(dg); why != "" {
		// Pointing Tasks at an edited, permissive default would widen them.
		return fmt.Errorf("default gateway %s/%s is not safe (%s); repointing nothing", ns, def, why)
	}

	// Gateway verdicts are cached for one pass only.
	usable := map[string]bool{def: true}
	for offset := int64(0); ; offset += pageSize {
		ctx, cancel := call()
		resp, err := client.ListTasks(ctx, &v1alpha1.ListTasksRequest{Atespace: ns, Limit: pageSize, Offset: offset})
		cancel()
		if err != nil {
			return fmt.Errorf("list tasks (offset %d): %w", offset, err)
		}
		for _, t := range resp.Tasks {
			if t.Spec == nil || t.Metadata == nil {
				continue
			}
			name := ""
			if t.Spec.Gateway != nil {
				name = t.Spec.Gateway.Name
			}
			if ok, seen := usable[name]; name != "" && seen && ok {
				continue
			}
			if name != "" {
				if _, seen := usable[name]; !seen {
					ctx, cancel := call()
					g, gerr := client.GetGateway(ctx, &v1alpha1.GetGatewayRequest{Atespace: ns, Name: name})
					cancel()
					switch {
					case gerr == nil && unsafeReason(g) == "":
						usable[name] = true
						continue
					case gerr == nil:
						slog.Warn("gateway does not restrict egress", "atespace", ns, "gateway", name, "why", unsafeReason(g))
						usable[name] = false
					case status.Code(gerr) == codes.NotFound:
						usable[name] = false
					default:
						slog.Warn("gateway lookup", "task", t.Metadata.Name, "gateway", name, "error", gerr)
						continue
					}
				}
			}
			repoint(client, call, ns, def, t.Metadata.Name, name)
		}
		if int64(len(resp.Tasks)) < pageSize {
			return nil
		}
	}
}

// repoint re-reads the Task immediately before the blind upsert (ax's
// UpdateTask is an upsert with no version check) and leaves it alone when it
// is gone, Terminating, or no longer names the gateway the list showed. A
// stale snapshot written after a delete would recreate the Task and start a
// second attempt beside its successor (codex review 1, D3). The re-read
// narrows that window to one RPC; it does not close it.
func repoint(client v1alpha1.AXClient, call func() (context.Context, context.CancelFunc), ns, def, task, was string) {
	ctx, cancel := call()
	defer cancel()
	t, err := client.GetTask(ctx, &v1alpha1.GetTaskRequest{Atespace: ns, Name: task})
	if err != nil {
		if status.Code(err) != codes.NotFound {
			slog.Warn("re-read before repoint", "task", task, "error", err)
		}
		return
	}
	if t.Spec == nil || t.Metadata == nil {
		return
	}
	if t.GetStatus().GetPhase() == "Terminating" {
		slog.Info("not repointing a Terminating task", "atespace", ns, "task", task)
		return
	}
	now := ""
	if t.Spec.Gateway != nil {
		now = t.Spec.Gateway.Name
	}
	if now != was {
		return // changed since the list; the next pass decides
	}
	t.Spec.Gateway = &v1alpha1.GatewayRef{Name: def}
	if _, err := client.UpdateTask(ctx, &v1alpha1.UpdateTaskRequest{Task: t}); err != nil {
		slog.Warn("repoint", "task", task, "error", err)
		return
	}
	slog.Info("pointed at the default gateway", "atespace", ns, "task", task, "was", was, "now", def)
}
