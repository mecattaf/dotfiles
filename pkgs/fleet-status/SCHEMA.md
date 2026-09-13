# fleet-status snapshot schema, version 1

Issue: mecattaf/dotfiles#356. The JSON is the contract. The terminal view is
just one reader of it. `validate_node_report` and `validate_snapshot` in
`fleet_status.py` enforce the rules below, and `checks.fleet-status` runs them.

## Facts

Every leaf the collector reports is a **fact**:

```json
{"value": <any>, "source": "<command, file or endpoint>", "observed_at": "<RFC 3339 UTC>",
 "grade": "measured" | "unknown" | "missing-by-design", "reason": "<why, when not measured>"}
```

- `measured`: the source answered, and `value` is what it said. An empty list
  counts as measured ("zero failed units").
- `unknown`: the collector tried and could not tell (timeout, missing tool,
  refused socket, crashed section). `value` is `null` and `reason` is
  required. A reader must never turn this into a zero.
- `missing-by-design`: this host's profile says the thing does not exist here,
  such as the NAS's user manager or Herdr on the worker. `value` is `null` and
  `reason` is required.

## Node report (`fleet-status-collect --json`)

```json
{"schema": 1, "kind": "node", "observed_at": "...", "hostname": "...", "profile": "...",
 "collect_ms": 1234, "sections": {"<section>": {"<fact name>": <fact>}}}
```

All thirteen sections are always present and non-empty. The collector has a
6 s internal budget. A section that has not finished by then is
`{"section": <unknown fact>}`.

| section | facts | source |
|---|---|---|
| identity | hostname, profile, boot_id, uptime_s | /proc, /etc/fleet-status/profile.json |
| nix | current, booted, generation{number,link,is_current}, version, revision, pending_reboot{pending,differs} | /run/{current,booted}-system, /nix/var/nix/profiles/system, nixos-version --json |
| updates | status (verbatim `update-adopt status --json`) | #354; unknown until that verb is enrolled on the host |
| systemd | system_state, failed_units[] | systemctl |
| user_manager | state, failed_units[] | `systemctl --user` as tom; missing-by-design on profiles without Home Manager |
| failure_markers | markers[{name, summary, mtime}] | /var/lib/failure-markers (modules/failure-surfacing.nix) |
| pressure | memory{total,available,swap_total,swap_used}, psi{memory_some,…}, load[3], top_cgroups[5] | /proc/meminfo, /proc/pressure, cgroupfs |
| storage | mounts[{mountpoint, mounted, on_demand, fstype, size, avail, use_pct}] | findmnt, checked against the host's declared `fileSystems` |
| timers | system, user: {timers, non_success[{unit,result,active}]} | list-timers joined with each triggered unit's Result |
| events | coredumps, unit_failures, oom_kills, update_adopt: [{at, message, …}] ≤ 50 each, last 6 h | journalctl field matches only |
| inference | worker: halogen_units, health, cache. coordinator: fara_browser_model. Otherwise server is missing-by-design | systemd, Halogen `/health` and `/cache` on loopback |
| runs | coordinator: kernel_unit, kernel_leases{open_lease_ids, ledger, last_seq}, daemon_unit, daemon_running_jobs{job_ids}, daemon_pools | tally-kernel (system unit plus its ledger), tally-daemon (user unit plus `tally query`) |
| attention | coordinator: agents{by_status, agents[]}, server{main_pid, server_rss, cgroup_memory_current, cgroup_anon}, panes{count, panes[{pane_id, agent, status, age_s, tree_rss, tree_procs}]} | `herdr agent list`, `herdr pane list`, `herdr pane process-info`, /proc |

Only IDs, states and counts cross the Tally and Herdr seams. No lake rows,
transcripts or pane contents appear here. `server_rss` is the Herdr server
process alone. `cgroup_memory_current` is herdr.service's cgroup, which also
holds every pane's descendants and their page cache. The two numbers are never
added together or swapped for each other (#357).

## Fleet snapshot (`fleet-status --json`)

```json
{"schema": 1, "kind": "fleet", "observed_at": "...",
 "nodes": [{"name", "profile", "target", "reachability", "latency_ms", "error"?, "report"}],
 "updates": [{"node", "status", "current", "booted", "revision", "pending_reboot"}],
 "failures": [{"node", "kind": "unit"|"user-unit"|"marker"|"node", "id", "grade", "source"|"reason"}],
 "inference": [{"node", <inference facts>}], "runs": [...], "attention": [...]}
```

- `reachability` takes one of four values. `reachable` means the report is
  present and valid. `timeout` means there was no answer within 8 s.
  `unreachable` means ssh exited 255. `error` means the collector failed or
  sent a report that is not valid schema-1 JSON. Every value other than
  `reachable` has `report: null`.
- For a node without a report, the joined arrays contain unknown facts, never
  an omission. `updates` holds unknown facts, `failures` holds a
  `kind: "node"` entry with grade unknown, and `inference` holds an unknown
  entry.
- Hosts come from `/etc/fleet-status/hosts.json`, which is rendered from
  `modules/mesh-registry.nix`. `FLEET_STATUS_HOSTS=a,b,c` narrows or extends
  that list, and any name it does not declare is dialed as `root@<name>`.
  `FLEET_STATUS_SSH` swaps the ssh binary, which the flake check uses.

Bump `schema` for any change that removes or renames a field. Adding a fact
does not require a bump.
