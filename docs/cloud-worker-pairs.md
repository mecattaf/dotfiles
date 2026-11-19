# Cloud workers in the existing Master floor

Master has named native DSH worker pairs for Groq Qwen, Google Flash-Lite,
Cohere extraction, official Antigravity Gemini, and official OpenCode Zen.
They use the same dshd worker lifecycle, workflow journal and JSONL sessions
as the existing Opus and Gufo pairs. There is no second scheduler or router.

| Pair | Provider / exact model | Effort | Per-pair workers |
|---|---|---|---:|
| `groq` | `groq` / `qwen/qwen3.8-27b` | low | 1 |
| `gemini-lite` | `google` / `gemini-3.5-flash-lite` | low | 1 |
| `cohere-extract` | `cohere` / `command-r-plus-08-2024` | omitted | 1 |
| `openrouter-free` | `openrouter-free` / `nvidia/nemotron-3.5-lightning:free` | low | 1 |
| `nvidia` | `nvidia` / `nvidia/nemotron-3.5-lightning-30b-a3b` | omitted; native chat-template thinking off | 1 |
| `antigravity` | `antigravity-cli-1` / `gemini-3.8-flash` | low | 1 |
| `antigravity-2` | `antigravity-cli-2` / `gemini-3.8-flash` | low | 1 |
| `antigravity-3` | `antigravity-cli-3` / `gemini-3.8-flash` | low | 1 |
| `zen-deepseek` | `zen-cli-1` / `opencode/deepseek-v4.1-flash-free` | omitted | 1 |
| `zen-glm` | `zen-cli-1` / `opencode/glm-5.3-flash-free` | omitted | 1 |
| `zen-mimo` | `zen-cli-1` / `opencode/mimo-v2.6-flash-free` | omitted | 1 |
| `zen-minimax` | `zen-cli-2` / `opencode/minimax-m3.1-flash-free` | omitted | 1 |

The DeepSeek, GLM and MiMo Zen rows share fixed slot 1; MiniMax uses explicit slot 2.
Whether those slots have independent quota remains unknown. Model selectors
and key counts never multiply an account's allowance. These conservative worker
caps are initial allocations, not measured provider concurrency ceilings.
The existing executor settings seed sets eight total workers for this floor; the Opus pair
retains a cap of three and Gufo a cap of one. This permits cloud work alongside
the existing lanes without turning eight into a claimed provider ceiling.
Every pair row declares `provider`, `model` and, when non-null, `effort`, so
the workflow executor can resolve a requested route without falling back to
the default Claude pair. The default pair itself remains `opus`.

Use coherent, bounded source packets. Groq's observed input window is 7,000
tokens/minute; its normal DSH tool request is already several thousand tokens
before source is added. The native Groq provider retains bounded normal
recovery but waits 60 seconds between transient retries. A request larger
than the input cap must be reduced; retries cannot make it fit. Quota and
authentication failures do not select another account or paid model.

## Native credentials for dshd workers

The hand-run wrapper exports API keys, but dshd starts the raw DSH binary.
Cloud pairs therefore use DSH's supported `credentials-local` service,
enabled only for the pair's profile. `credentialFiles` maps a credential
reference to its existing runtime agenix file, for example:

```nix
credentialFiles.GROQ_API_KEY = osConfig.age.secrets.groq-api-key-1.path;
```

`dsh-master credentials sync [PROFILE...]` reads those sources and atomically
publishes `$DSH_HOME/master-credentials/<profile>.yaml`, a native version-1
credential document. The directory is mode 0700 and files are 0600. It first
reads every selected source and validates every destination; missing, empty,
oversized or multiline sources and symlinked/readable destinations fail
visibly. Values are absent from Nix outputs, profile YAML, manifests, argv,
pair environment, dshd recipes and stdout. Only source paths are recorded.
The user's global `$DSH_HOME/.credentials.yaml` is untouched. The generated
directory is exclusively owned by this command; do not put hand-maintained
records there.

The native profile resolves the generated file's real path before mounting
the credential service. A missing store fails startup; it cannot silently
fall back to a project's `.env` or an inherited API key. The native service
then validates the file's owner-only permissions and document layout.
These profiles also require the `credentials` service in `llm-pi-ai`'s
injection list. DSH otherwise treats a failed optional credential plugin as
a warning and can continue through ambient authentication; the required
service prevents that fallback when the store is unreadable or invalid.

Home activation renders profiles and syncs these stores. After rotating a
source key, run the sync command before starting another worker. An existing
worker reads its native store at startup; sync neither restarts nor rewrites
the live floor. A failed rotation leaves the previous file intact and returns
failure rather than claiming it has installed the replacement.

For a scratch home, render, sync and install there explicitly:

```sh
export DSH_HOME=/tmp/my-cloud-worker-home
mkdir -p "$DSH_HOME"
dsh-master render master-groq master-gemini-lite master-cohere-extract
dsh-master credentials sync master-groq master-gemini-lite master-cohere-extract
dsh-master install master-groq master-gemini-lite master-cohere-extract
dsh-master check master-groq master-gemini-lite master-cohere-extract
```

This selects slot 1 explicitly, without automatic account rotation. Adding a
second intentional slot is a separate declared pair, after establishing which
account/project/organization quota it uses.
Selective rendering, ported from the existing 6bcd16fc implementation, leaves
unselected live Master/Claude profile files, state and installation records
byte-for-byte unchanged. Do not render the live `master` merely to install a
new worker profile.
Default rendering also skips every changed profile used by an active dshd
instance in this `DSH_HOME`, preserving all its files and render state. It
reports the pending profile and instance names while rendering inactive
workers. If dshd inventory is unavailable, it fails before writing any
profile. There is no render force bypass: HMR watches these profile files.

## Native CLI workers

The Antigravity and Zen profiles install a pinned, built native-client plugin
as a per-pair dependency. Its worker row mounts the package through DSH's
normal plugin resolver. Other profiles acquire neither that dependency nor
its provider. `workerRows` permits pair-specific modules; `dependencies`
supplies their immutable package pins. The NAS's ordinary plugin installation
uses its existing Git authentication; no private repository contents or login
tokens are embedded in public Nix source.

Antigravity invokes the official fixed-account launcher with
`useG1Credits=false`; no credit fallback or account rotation is requested.
All three existing account launchers have explicit pairs. Select their pair
or provider-qualified model; a bare Gemini model is ambiguous. Their quota
percentages remain separate observations and are never added.
The fixed native thought level is selected only after ACP advertises its
actual configuration controls. `nativeEffort` reports that verified setting
to pair selection without sending an unsupported outer DSH reasoning option
before discovery. It is distinct from `reasoningEffort` on a direct API pair.
Zen invokes the official OpenCode ACP client through the fixed-slot `zen`
launcher. The code worker explicitly enables editing in its actual workspace;
the same native account stays selected. An API client gate is not a quota
reading and is never worked around by forging a fingerprint.
Each pair passes its fixed `--slot` explicitly, so an inherited `ZEN_SLOT`
cannot change its declared account. The corrected launcher captures complete
native catalogue output, verifies a real cache refresh and admits exact
zero-price models. An earlier five-model list was truncated stdout, not a
provider withdrawal. All four configured slots exposed the same twelve
metadata-free selectors; Inkling's EU restriction leaves eleven eligible here.
The MiniMax and MiMo pairs each passed a native DSH source-edit task and all
sixteen independent boolean acceptance cases. These are route checks, not measured
remaining quota or model-quality rankings.

Both native-client rows set `narration = "reasoning"`. Tool activity, plans,
adapter notices and context occupancy then go to reasoning blocks, and the
final answer text holds only the native agent's message. A workflow node that
asks for one JSON value parses that text strictly; without this setting a Zen
answer carried a system-prompt notice and an occupancy line, and an
Antigravity answer carried its tool narration, so neither parsed.

### Worker directory and approvals

A floor worker runs in its workflow run's directory (`dshd.cwd`, here home, is
only the fallback). Two failures follow from a run started in home:

- Zen: `--edit --cwd .` named home, which the launcher refused, so the client
  exited before ACP started. The launcher now serves such a session read-only.
  Start runs that need Zen edits in a project directory.
- Antigravity: the floor passes `--approval-policy never`, so DSH rejects
  every native permission request at once. `accept-edits` asks permission
  for shell commands; the rejected command ends the native turn with no
  answer. Reads and edits do not ask and work. A task that needs shell output
  belongs on a DSH-tool pair, or needs a deliberate native mode decision; the
  launcher does not widen it silently.

## Coverage and admission are different facts

All existing API adapters remain declared in `pkgs/dsh/config.nix` and the
hand-run `DSH_ROUTE` interface. No funded or unqualified route is silently
promoted into the automatic free worker pool:

| Route | Adapter status | Admission status at 2026-11-15 qualification |
|---|---|---|
| Cloudflare Workers AI Qwen | Supported native pi-ai adapter; stronger code task returned correctly | Paid account can incur overage. Included allocation requires a current shared budget before broader factory admission. |
| NVIDIA NIM | Supported native pi-ai adapter; exact Lightning model qualified with thinking off | GPT-OSS/GLM timeouts were model/parameter observations, not a provider outage. Remaining account allowance is unknown. |
| Mistral | Supported native pi-ai adapter | Generation still refused with inactive-plan/zero request-rate evidence. |
| Cerebras | Supported native pi-ai adapter | Generation still returned payment-required. Historical large rate headers are not credit. |
| Hugging Face | Supported native pi-ai adapter | No demonstrated included routed-inference allowance on this account. |
| Vercel AI Gateway | Supported native pi-ai adapter | No demonstrated funded or included generation allowance. |
| OpenRouter free | Native DSH PiAiAdapter with a final native SDK payload guard | Exact allowlisted `:free` model, no fallback array, provider fallback disabled and all documented price dimensions capped at zero. Shared-pool refusals stay failures. |
| xAI | Stored credential only | No established API entitlement or working adapter configuration. |

These are qualification observations, not permanent provider outages or a
promise about today's remaining balance. Exact receipts and account readings
remain private. Requalification must record its timestamp and actual quota
owner. Private inputs stay on authorized providers such as Gufo.

The OpenRouter adapter is owned under `pkgs/dsh-plugins/openrouter-free`.
It wraps the native completion API's `onPayload` hook; DSH retains the agent
loop and tool/usage/session behavior. The guard runs after earlier payload
hooks, so they cannot add a paid model fallback or loosen price caps. The
supported field names and units are checked against [OpenRouter routing](https://openrouter.ai/docs/guides/routing/provider-selection#max-price).

NVIDIA Lightning uses the native `chat-template` compatibility format with
`chatTemplateKwargs.enable_thinking=false`, matching [NVIDIA's model guide](https://docs.nvidia.com/nim/large-language-models/2.0.10/get-started/advanced/get-started-nemotron-3.5-lightning.html).
The underlying catalog model stays reasoning-capable: marking it non-reasoning
would skip the SDK branch that serializes this required thinking-off field.
A local HTTP fixture checks the actual native request body, and a genuine
DSH source-edit task checks the resulting patch independently.

Ordinary DSH JSONL sessions retain model selections, model-request outcomes,
usage where the provider supplies it, and retry events. Pair metadata joins
those sessions to workflow nodes and dshd invocations. Missing token counters
stay unknown; a transport success is separate from a verified usable patch.
Do not manufacture one aggregate remaining-token figure from requests,
percentages, USD and Neurons.
