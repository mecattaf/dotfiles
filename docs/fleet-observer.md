# Passive fleet observer

`fleet-observer` extends the existing `fleet-status` package and module. One
long-lived NAS user service observes existing owners and atomically retains
`~/.local/state/fleet-status/public/status.json`. It serves no HTTP endpoint,
starts no agents or models, and declares no timer. The public Cloudflare reader
consumes a separately committed copy; a browser never triggers fleet work.

The snapshot is `fleet-observations/1`, from the reviewed Valet investigation.
The schema and explicit public field/string contract ship beside the program
under `share/fleet-status/schema/` and `public-contract.json`. Missing adapters
are listed in coverage; their absent values remain unknown.

## Backend access

The collector, retained observation contract and CLI are the backend. A webpage
is a separate consumer; neither collection nor local inspection depends on a
web server or cloud publication.

```
fleet-status --json
fleet-status observations
fleet-status observations --json
fleet-status observations --snapshot /path/to/status.json --json
```

The first command retains the existing bounded fleet-health collection. The
`observations` command reads the observer's committed `public/status.json` and
exposes every subject, observation, event and source-coverage record. JSON uses
the existing `fleet-observations/1` contract, including units, measurement scope,
acquisition timestamps, errors and last-good values. Expired observations become
unknown on read without changing their original timestamps or the stored file.
`--state-dir` selects an existing observer directory. A missing snapshot returns
`snapshot-missing` and exit 1, rather than collecting implicitly or showing zeros.

The CLI starts no observer, network request, model or publisher. The optional
HTTPS publisher and any future webpage consume this same versioned contract.
This adds no hardware-history recorder and makes no claim of coverage before
the existing observer enrolled each source.

| Owner | Acquisition | Normal cadence |
|---|---|---|
| Existing fleet collector | One bounded fleet fanout; selected public reachability/load/memory fields | 300 seconds |
| Fixed host counters | `/proc` memory/load; qualified Strix APU busy and GTT/VRAM counters | 60 seconds |
| dshd | Batched `ls`, then one native accounting-property batch; no ACP probe | 60 seconds |
| User journal | One cursor-owned lifecycle subscription | Events, bounded reconnect backoff |
| DSH | Incremental selected metadata from recent session journals | 10 seconds |
| Seats | `--no-spend`, normal 1800-second native cache TTL, one shared acquisition | 600 seconds |
| Cloudflare | Read-only account Neurons analytics; declared included allocation kept separate | 3600 seconds |
| Vercel | Read-only credits balance | 3600 seconds |
| Free-provider headers | Existing lane meter, recorded during ordinary calls | Incremental; no inference/catalogue probes |
| Local/public commit | Independent of slow reads | 60 seconds |

The dormant Strix worker is declared dormant and never contacted. The Strix APU
counter map is a fixed qualified PCI device. The metrics helper first checks
runtime PM and skips device reads while suspended. It does not run SMART,
discover sensors repeatedly, change power settings, or wake an inference route.
GTT plus VRAM allocation is labelled shared APU memory, not private device RAM.

Each source has one in-flight acquisition, a deadline and bounded exponential
failure backoff. A failed source retains dated `lastGood`; heartbeat publication
never refreshes its observation time. Unknown counters are not zero. Independent
sources and the outbound sender cannot block the main publication heartbeat.

For persisted DSH journals, `assistant/message.data.usage` supplies only numeric
metadata and is joined to its matching `step/end`. The completion sequence is
counted once, including when stdout repeats usage or a source is resumed.
Prompts, reasoning, code and tool output are never copied into observer state.
No missing cache/reasoning counter is inferred from a total. The initial counts
cover observed DSH model-step attempts since enrollment; successes require an
actual non-interrupted response, while failed/cancelled turns stay distinct.
Observed partial-response token usage is retained on cancellation. These are
not all HTTP retries, all clients,
or all prior history. Old transcripts are enrolled at their end. Truncation and
cursor gaps are explicit coverage limitations.

The private state directory is mode 0700; state files are 0600. Public records
are constructed from fixed fields and finite value domains. Account slots are
anonymous. Instance, invocation and session identities are salted opaque hashes
with generic labels. The public projection excludes raw journals, local paths,
titles, arguments, environment, provider account identities and credentials.

`services.fleet-status.observer.enable` defaults on for the brain role only.
Set `publishUrl` and `publishTokenFile` to enable the separate bounded HTTPS
sender. The token remains in its NAS-only credential file. The sender performs
conditional replacement of the one validated snapshot object and reconciles
uncertain writes. Its remote sequence participates in the next local sequence,
so restoring old local state cannot overwrite a newer publication. Worker
receipt time determines connected/disconnected; source observation times remain
separate. Local collection continues if public publication is unavailable.

Inspect the new service with `systemctl --user status fleet-observer`; inspect
the committed public JSON and source coverage before treating it as evidence.
This service never restarts Herdr, DSH instances, the compositor or the user
manager. A process being active is distinct from a model generating, a source
being fresh, or a returned artifact being accepted.
