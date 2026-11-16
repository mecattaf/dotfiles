# Official Zen workers, including DSH

`opencode` is already installed by `home/agent-tools.nix` (qualified version
1.19.5). `zen` is the fixed-key launcher for its official `run` and `acp`
commands. It does not impersonate the native client or rotate keys on refusal.
The older `dsh zen` fingerprint plugin is not this supported path.

## DSH owns the work

Mount the existing native-agent ACP adapter a second time. The same package
supports both Antigravity and Zen; there is no new factory or LLM tool loop.
Use the current built `@mecattaf/dsh-gemini-cli` package from the owning profile,
with this module configuration (JSON shown to preserve exact names):

```json
{
  "id": "llm-zen-cli",
  "name": "@mecattaf/dsh-gemini-cli",
  "config": {
    "providerPrefix": "zen-cli",
    "runtimeName": "OpenCode Zen",
    "registerCommands": false,
    "allowDirectProvider": true,
    "accounts": [{
      "id": "1",
      "name": "Zen fixed slot 1",
      "executablePath": "zen",
      "cliArgs": ["--acp", "--timeout", "3600"]
    }],
    "defaultMode": "zen-worker",
    "allowedModels": [
      "opencode/beam-free",
      "opencode/big-pickle",
      "opencode/deepseek-v4.1-flash-free",
      "opencode/flint-40b-free",
      "opencode/glm-5.3-flash-free"
    ],
    "turnTimeoutMs": 600000
  }
}
```

Select provider `zen-cli-1` and an exact native model, for example
`opencode/deepseek-v4.1-flash-free`. The example deliberately allows a subset.
The earlier apparent five-model limit came from truncated native stdout, not
provider removal or account entitlement. The corrected launcher refreshed and
listed these twelve zero-price metadata selectors on all four fixed slots on
15 November 2026 at 22:02–22:03 UTC:

```text
beam-free
big-pickle
deepseek-v4.1-flash-free
flint-40b-free
glm-5.3-flash-free
iceman-free
inkling-2-small-free
longcat-2.5-free
mimo-v2.6-flash-free
minimax-m3.1-flash-free
nemotron-3.5-lightning-free
nemotron-3.5-super-vl-free
```

These come from the official client's model metadata, not a per-account
allowance endpoint. Inkling's documented EU restriction excludes it from the
eleven region-eligible choices here. Four matching lists do not establish four
independent quota pools. Refresh before admission; model names do not prove
remaining capacity. [Official free-model rules](https://opencode.ai/docs/console/models/#free-models).

For a workspace-editing account, use explicit launch arguments
`["--acp", "--edit", "--cwd", ".", "--timeout", "3600"]`. The supervisor's
bound cwd supplies the workspace; `.` is resolved there. The native client
executes its own tools. Its process lifetime is bounded by the launch timeout;
the adapter also bounds individual turns and owns cancellation, permissions,
native session binding and DSH presentation. ACP native data persists privately
under `~/.local/state/seats/zen/acp/slot-N/` so a new process can load a bound
native session. A second route/key does not imply independent quota.

The Master floor's Zen pairs also pass `--model <selector>` (without the
`opencode/` prefix), so the launcher admits, pins as small model and records
the pair's own model rather than its DeepSeek default. A floor worker's cwd is
its workflow run's directory. When that is home or the filesystem root, the
ACP launcher serves the session read-only and says so on stderr and in its
receipt (`edit_requested`, `edit_refused`), instead of exiting before ACP
starts. Edits are never granted across home or root; a hand-run `zen --edit`
in home is still refused. Before this, every floor Zen worker of a run started
in home exited at once and DSH reported only "ACP connection closed before the
operation completed"; the adapter now appends the client's exit status and
redacted stderr tail to that error.

OpenCode 1.19.5 returns ACP `configOptions`: `model` uses full
`opencode/<selector>` values, `mode` includes `zen-worker`, and the effort
option has ID `effort`, category `thought_level`, values `low/high/max/default`
for DeepSeek. The adapter must resolve categories to the advertised exact ID.
OpenCode does not advertise Antigravity's system-prompt append extension;
include any task constraints in the work itself.

## Bounded command interface

```sh
zen --models
zen --cwd /tmp/public-source -m glm-5.3-flash-free --timeout 180 \
  --task-id shutdown-review 'Read state-query.ts and trace shutdown ownership.'
zen --cwd /tmp/public-worktree --edit -m deepseek-v4.1-flash-free \
  --task-id narrow-code-draft 'Implement the scoped change and explain it.'
```

Read-only is the default. Shell, delegation, external directories, web and
unknown tools are denied. `--edit` requires an explicit workspace and enables
only edits inside it; root and home are refused (an `--acp` session there is
served read-only instead, as described above). These native permissions are
not an OS filesystem sandbox. Supply public/nonsecret workspaces and source
packets. In v1.19.5 the edit permission patterns are relative to the Git worktree
(or filesystem root outside Git), which is why absolute allow patterns fail.

`-k N` selects `/run/agenix/opencode-zen-key-N` (default `ZEN_SLOT`, then 1).
Only this selected key is read, into the official child environment. Every
invocation refreshes the official verbose catalogue and requires the selected
exact model to have explicit zero input/output and zero other reported prices.
The selected model is also the native small model. ACP additionally filters its
advertised models to the refreshed zero-price list. There is no paid fallback.
Catalogue stdout is captured through an anonymous regular file, then redacted
into its receipt. OpenCode 1.19.5 can exit before pending pipe writes drain;
line-by-line capture previously retained only an arbitrary prefix of its JSON
metadata. Incomplete model JSON now fails visibly. The launcher also verifies
that refresh replaced the actual private native cache, records its SHA-256,
and lists that cache in a second native process. The native refresh command
can otherwise return zero after a fetch failure. Ambient model-source
overrides are cleared rather than accepted as authoritative price metadata.
`--burndown` now refuses with an explanation instead of automatically rotating
accounts after a limit. Existing `-k`, `-m`, prompt arguments,
`-- --pure --format json`, and explicit `ZEN_STDIN=1` piping remain supported.
No pipeline input is read unless `ZEN_STDIN=1` is set; ACP reserves stdin for
its protocol.

The command deadline includes catalogue refresh and inherited child pipes.
Timeout returns 124; cancellation returns 130; provider error events, missing
final text/usage/stop, nonzero native exit and nonzero reported costs fail even
when the client returned zero. Unknown catalogue metadata fails closed. Native
success means completion, not reviewed engineering acceptance.

## Receipts and existing meters

Each UUID invocation gets new, private files under
`~/.local/state/seats/zen/invocations/`: `invocation.json`, refreshed catalogue,
redacted raw stdout/stderr, and `result.json`. Files are created exclusively;
retries receive new IDs, with optional `--retry-of` and shared `--task-id`.
The prompt is identified by SHA-256 in the wrapper receipt. Native state may
contain the submitted public prompt. Exact selected-key values and bearer
strings are redacted from captured output. Keep these private raw records out
of public repositories.

One terminal record is appended under a file lock to the existing
`~/.local/state/seats/lane-usage.jsonl` meter, including receipt pointer and
exact per-step usage. Input, output, reasoning, cache and total are preserved
separately; they are not added twice or called account quota. A catalogue-only
record has status `catalogue` and made no inference; an ACP process record
reports its lifecycle, while per-turn ACP outcomes live in the DSH adapter's
journal. `accepted` stays null until an external reviewer checks the output.

Normal command native state is isolated per invocation, preserving live
OpenCode config/sessions. Tests can explicitly relocate state, ledger and dummy
keys with `ZEN_STATE_DIR`, `ZEN_LEDGER` and `ZEN_KEY_DIR`; the normal key root
remains `/run/agenix`.

## Qualification, 15 November 2026

Eighteen offline checks cover paid/absent admission, vendor exit-zero
error events, incomplete output, timeout including descendant pipe holders,
SIGTERM cleanup, fixed slots/no rotation, concurrent immutable records, and
explicit edit scope, and ACP protocol passthrough/persistent native state. Run:

```sh
runtime-test -- python3 tests/zen-worker/test_zen.py
```

Real official-client calls read the public v1.19.5 `run.ts`. GLM identified the
actual event shapes and error paths. Its argument that current source permits
zero-exit errors was not established: this version explicitly assigns exit 1
in the cited paths. Fault injection retains the zero-exit/error defense for
other vendor paths and versions.

DeepSeek generated a 68-line standalone JSONL result reader through the actual
write tool after the edit-pattern fix. It passed six independent command cases:
completed output, error after text, partial output, tool-only output, malformed
lines, and unreadable input; exact token dictionaries were preserved. The first
edit attempt was retained as a permission failure, not claimed as accepted code.
This demonstrates useful source/tool/code work and the acceptance boundary;
it does not establish sustainable provider capacity or arbitrary coding quality.
Public source: <https://github.com/anomalyco/opencode/blob/v1.19.5/packages/opencode/src/cli/cmd/run.ts>.

A complete installed DSH 0.2.2-rc.1 headless turn also completed through the
reused ACP adapter, provider `zen-cli-1`, model
`opencode/glm-5.3-flash-free`, mode `zen-worker`, with actual native `glob` and
`read` calls and a final source analysis. It ran under `runtime-test` with a
private DSH profile and the public source packet, preserving live profiles.
The adapter's turn journal recorded the native session/model binding and
completion. This proof is separate from the standalone command tests.

After fixing catalogue capture, a further DSH native ACP turn used fixed
slot 2 and `opencode/minimax-m3.1-flash-free`. It read and edited a public
permission helper through native tools, completed, and its patch passed all
sixteen boolean input combinations independently on compute. To expose this
model in another profile, set the account id to `2`, explicitly include
`--slot 2` in its CLI arguments, allow that exact native model and select
provider `zen-cli-2`. Existing DeepSeek/GLM pairs need only the corrected
launcher; no experimental flag or different OpenCode package is required.
The added tests cover large native output lost on a pipe, incomplete JSON,
silent refresh failure, a changed price and the shared absolute deadline.
