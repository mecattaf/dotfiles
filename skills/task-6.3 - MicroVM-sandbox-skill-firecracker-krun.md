---
id: TASK-6.3
title: MicroVM sandbox skill (firecracker/krun)
status: To Do
assignee: []
created_date: '2026-03-09 13:03'
updated_date: '2026-03-09 13:44'
labels: []
dependencies:
  - TASK-1.6
parent_task_id: TASK-6
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Claude Code skill for running agent-written code in local microVMs using microsandbox (msb CLI). CLI-first approach — skill teaches Claude to invoke msb commands directly via bash. Depends on msb binary being installed (TASK-1.6). Ref: INTEL.md §2 (microsandbox decision), §4.7 (Quadlet).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Skill launches code in isolated microVM
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
[Ingested from: microsandbox/]

### Decisions
- CLI-first approach chosen over MCP-first. Skill teaches Claude Code to call `msb` directly via bash, not through MCP server registration. Works immediately in any session without MCP config. MCP is available at :5555/mcp but not the primary interface.
- Use microsandbox as-is (Apache 2.0), do NOT reimplement. Package for Fedora via COPR.
- Bubblewrap and microsandbox are complementary, not alternatives. Bubblewrap sandboxes the agent (file/network restrictions). Microsandbox sandboxes the workload (disposable runtime with own kernel). Both needed.
- Skill structure: SKILL.md (main, ~344 lines) + 3 reference files (cli.md, api.md, sandboxfile.md). Progressive disclosure pattern.

### Architecture
- Server/client model: `msb server start --dev` runs a daemon on 127.0.0.1:5555
- Server exposes: JSON-RPC at /api/v1/rpc, MCP at /mcp, health at /api/v1/health
- Three sandbox modes:
  1. Temporary (`msb exe <image> -- <cmd>`) — auto-destroyed on exit, for one-off tasks
  2. Project (`msb init` + Sandboxfile YAML + `msb up/down`) — persistent, reproducible
  3. Server-managed (JSON-RPC API) — programmatic control via HTTP
- Underlying tech: libkrun (KVM-based microVMs), each sandbox gets own Linux kernel + memory space + network stack
- Boot time: <200ms. On stop, VM + all contents destroyed (no residue).
- OCI images supported: microsandbox/python, microsandbox/node, plus any standard OCI image (python:3.11, node:18, ubuntu:22.04)
- Port forwarding: `--port host:guest` maps sandbox ports to host. Combine with `tailscale serve` for remote access.
- Volume mounts: `--volume host_path:guest_path` for mounting worktree code into sandbox.
- Worktree integration pattern: each git worktree gets its own Sandboxfile + sandbox set. Different ports per worktree to avoid collisions.

### CLI Requirements
- Primary binary: `msb` (installed via `curl -sSL https://get.microsandbox.dev | sh` or future RPM)
- Workspace builds 3 binaries: `msb`, `msbrun`, `msbserver`
- Key commands the skill invokes:
  - `msb server start --dev` / `msb server stop` / `msb server status`
  - `msb exe <image> [--port] [--volume] [--memory] [--cpus] [--env] [--exec] -- <args>`
  - `msb init` / `msb add <name> --image <img> [opts]` / `msb up` / `msb down`
  - `msb run <name>` (alias: `msr <name>`) / `msb shell <name>`
  - `msb status` / `msb log <name> --follow`
  - `msb clean [--all --force]`
  - `msb install <image> <alias>` / `msb uninstall <alias>`
- API key management: `msb server keygen [--expire] [--namespace]`, env var MSB_API_KEY

### Constraints
- KVM required: `lsmod | grep kvm` must show kvm_intel or kvm_amd. No KVM = no microsandbox.
- SELinux: Fedora enforcing by default. msb process needs KVM device access — SELinux policy module required for RPM packaging.
- Rootless: microsandbox uses libkrun which handles rootless KVM. No root required for sandbox operations.
- Resource limits enforced at hypervisor level (not cgroups): memory (default 512 MiB), CPUs (default 1), PIDs.
- Server must be running before any sandbox ops. Skill should check `msb server status` and auto-start if needed.
- Sandboxes consume resources until explicitly stopped. Skill must always clean up.
- Network scope options: local, public, any, none. Default should be `none` for untrusted code.

### Open Questions
1. Should the skill auto-start `msb server` if not running, or require user to start it? (Affects systemd integration — if msb is a systemd service, it could be socket-activated.)
2. The MCP endpoint at :5555/mcp is available — should a future iteration register it as an MCP server alongside the CLI skill, or keep CLI-only?
3. `msb build` and `msb push` are listed as "coming soon" — custom image building not yet available via CLI. For now, must use pre-built OCI images only.
4. `msb server ssh` listed as "not yet implemented" — no SSH into sandboxes yet.
5. REPL languages limited to python and nodejs for `sandbox.repl.run`. Shell commands (`sandbox.command.run`) work for any language but lack REPL state persistence.
<!-- SECTION:NOTES:END -->
