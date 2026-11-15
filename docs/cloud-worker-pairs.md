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
| `antigravity` | `antigravity-cli-1` / `gemini-3.8-flash` | low | 1 |
| `zen-deepseek` | `zen-cli-1` / `opencode/deepseek-v4.1-flash-free` | omitted | 1 |
| `zen-glm` | `zen-cli-1` / `opencode/glm-5.3-flash-free` | omitted | 1 |

The Zen rows share the same fixed slot and quota pool. Model selectors and
key counts never multiply an account's allowance. These conservative worker
caps are initial allocations, not measured provider concurrency ceilings.
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

Home activation renders profiles and syncs these stores. After rotating a
source key, run the sync command before starting another worker. An existing
worker reads its native store at startup; sync neither restarts nor rewrites
the live floor. A failed rotation leaves the previous file intact and returns
failure rather than claiming it has installed the replacement.

For a scratch home, render, sync and install there explicitly:

```sh
export DSH_HOME=/tmp/my-cloud-worker-home
mkdir -p "$DSH_HOME"
dsh-master render
dsh-master credentials sync master-groq master-gemini-lite master-cohere-extract
dsh-master install master-groq master-gemini-lite master-cohere-extract
dsh-master check master-groq master-gemini-lite master-cohere-extract
```

This selects slot 1 explicitly, without automatic account rotation. Adding a
second intentional slot is a separate declared pair, after establishing which
account/project/organization quota it uses.

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
Zen invokes the official OpenCode ACP client through the fixed-slot `zen`
launcher. The code worker explicitly enables editing in its actual workspace;
the same native account stays selected. An API client gate is not a quota
reading and is never worked around by forging a fingerprint.

## Coverage and admission are different facts

All existing API adapters remain declared in `pkgs/dsh/config.nix` and the
hand-run `DSH_ROUTE` interface. No funded or unqualified route is silently
promoted into the automatic free worker pool:

| Route | Adapter status | Admission status at 2026-11-15 qualification |
|---|---|---|
| Cloudflare Workers AI Qwen | Supported native pi-ai adapter; stronger code task returned correctly | Paid account can incur overage. Included allocation requires a current shared budget before broader factory admission. |
| NVIDIA NIM | Supported native pi-ai adapter | Fresh bounded generation timed out; a model list does not prove usable inference. |
| Mistral | Supported native pi-ai adapter | Generation still refused with inactive-plan/zero request-rate evidence. |
| Cerebras | Supported native pi-ai adapter | Generation still returned payment-required. Historical large rate headers are not credit. |
| Hugging Face | Supported native pi-ai adapter | No demonstrated included routed-inference allowance on this account. |
| Vercel AI Gateway | Supported native pi-ai adapter | No demonstrated funded or included generation allowance. |
| OpenRouter free | Separate measured direct API runner; exact free selectors and zero-price caps | No native pi-ai Master pair until the same no-paid-fallback contract is represented and checked. |
| xAI | Stored credential only | No established API entitlement or working adapter configuration. |

These are qualification observations, not permanent provider outages or a
promise about today's remaining balance. Exact receipts and account readings
remain private. Requalification must record its timestamp and actual quota
owner. Private inputs stay on authorized providers such as Gufo.

Ordinary DSH JSONL sessions retain model selections, model-request outcomes,
usage where the provider supplies it, and retry events. Pair metadata joins
those sessions to workflow nodes and dshd invocations. Missing token counters
stay unknown; a transport success is separate from a verified usable patch.
Do not manufacture one aggregate remaining-token figure from requests,
percentages, USD and Neurons.
