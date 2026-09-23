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
	"os"
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

func pass(client v1alpha1.AXClient, ns, def string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	if _, err := client.GetGateway(ctx, &v1alpha1.GetGatewayRequest{Atespace: ns, Name: def}); err != nil {
		// Without the default there is nothing safe to point at; the
		// bootstrap re-applies it. Log loudly, change nothing.
		return fmt.Errorf("default gateway %s/%s: %w", ns, def, err)
	}
	resp, err := client.ListTasks(ctx, &v1alpha1.ListTasksRequest{Atespace: ns})
	if err != nil {
		return fmt.Errorf("list tasks: %w", err)
	}
	for _, t := range resp.Tasks {
		if t.Spec == nil || t.Metadata == nil {
			continue
		}
		name := ""
		if t.Spec.Gateway != nil {
			name = t.Spec.Gateway.Name
		}
		if name != "" {
			_, gerr := client.GetGateway(ctx, &v1alpha1.GetGatewayRequest{Atespace: ns, Name: name})
			if gerr == nil {
				continue
			}
			if status.Code(gerr) != codes.NotFound {
				slog.Warn("gateway lookup", "task", t.Metadata.Name, "gateway", name, "error", gerr)
				continue
			}
		}
		t.Spec.Gateway = &v1alpha1.GatewayRef{Name: def}
		if _, err := client.UpdateTask(ctx, &v1alpha1.UpdateTaskRequest{Task: t}); err != nil {
			slog.Warn("repoint", "task", t.Metadata.Name, "error", err)
			continue
		}
		slog.Info("pointed at the default gateway", "atespace", ns, "task", t.Metadata.Name, "was", name, "now", def)
	}
	return nil
}
