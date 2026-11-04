# Local Qwen chat in DSH

The stock DSH Web UI runs on the NAS. Inference runs on Strix through the
existing llama-swap endpoint at `http://strix-coordinator:8731/v1`.

The current private tailnet address is
<https://nas.tail8dd1.ts.net:8444/>. Its hand-run Tailscale Serve listener
forwards to `127.0.0.1:3080` on the NAS. Port 443 remains Herdr's listener;
port 80 retains the artifact configuration.

| DSH route | API model ID | Declared context |
|---|---|---:|
| `qwen-ara` | `qwen3.8-27b-ara` | 102,400 |
| `qwen-flash-abliterated` | `qwen3.8-flash-next-abliterated` | 32,768 |

Both are text-only models in the stock model picker. Requests select the
backend through llama-swap. The route leaves request-level reasoning effort
unset; the backend's thinking settings apply. A picker entry establishes the
route, while a successful inference receipt establishes runtime readiness.

## Hand-run launcher

The current launcher is the transient user unit `dsh-qwen-chat.service`,
started by hand on the NAS, with cwd `/home/tom/mecattaf/dotfiles` and
`DSH_ROUTE=qwen-ara`. It has no boot target, timer or restart policy.

The executable used for the 2026-11-04 conversation is
`/nix/store/9xzwfgw6j2lc0vdzc7p6y2wash4bjcck-dsh/bin/dsh`. This built wrapper
includes the new routes and Web policy before a full NAS activation. The
ordinary `dsh` on PATH gains them when that package is activated.

After stopping the hand-run unit, the equivalent foreground invocation is:

```sh
DSH_ROUTE=qwen-ara /nix/store/9xzwfgw6j2lc0vdzc7p6y2wash4bjcck-dsh/bin/dsh web \
  --no-open --port 3080 \
  --public-url https://nas.tail8dd1.ts.net:8444/ \
  --trusted-host nas.tail8dd1.ts.net:8444 nas.tail8dd1.ts.net 10.42.0.1 dsh.internal
```

The unit directs stdout and stderr to private files under
`~/.local/state/dsh-qwen-chat/`. Its private `launch-url` file contains the
current authenticated URL. Restarting Web requires refreshing that file from
the new startup announcement before opening it on the client. Do not reuse
the old process's launch URL.

DSH's standard authentication flow exchanges the startup URL for a signed,
authority-bound browser cookie, then redirects to the clean address. The
startup credential remains reusable for that Web process; the cookie lasts
30 days by default. Transfer the launch URL privately to the intended browser.
Once authenticated, use the clean HTTPS address above. Session selection is
browser-local; choose **Qwen ARA** in the sidebar to resume the prepared chat.

## Tailnet listener

Create only this listener on the NAS:

```sh
sudo tailscale serve --bg --https=8444 http://127.0.0.1:3080
```

Remove only this listener, retaining Herdr and artifacts:

```sh
sudo tailscale serve --https=8444 off
```

Stop only this Web process with
`systemctl --user stop dsh-qwen-chat.service`. Its sessions remain in
`~/.dsh/sessions/`. Herdr and the user manager do not need a restart.

## Verification

`checks.x86_64-linux.dsh-config` verifies the new routes, the stock Web
profile, and the fleet tool policy in every shipped Web preset. Preset rows
are generated from the pinned upstream bundle; they retain fetch-only Web
tools, the three-child workflow limit, and disabled runtime plugin installs
and scheduling. NAS harness state and credentials stay local.

The live **Qwen ARA** conversation is
`session-03af97a5-c6c3-4fd3-860c-7663886c8051`, using the `standard` preset.
Two prompts submitted through the stock Web Session API completed:

1. A greeting returned `Hello Tom, ARA is ready.` with a separate reasoning
   block.
2. The same session answered `Tom` when asked for the speaker's name.

The first cold request loaded in 19.84 seconds and spent 93.66 seconds in
inference: 16,284 harness prompt tokens, 392 generated tokens, about 7
generated tokens per second. These are a connectivity and conversation
check, not a coding benchmark.

Non-secret receipts are under `~/.local/state/dsh-qwen-chat/`:
`conversation.json`, `model-picker.json` and `tailscale-receipt.json`. The
tailnet receipt records verified TLS, the startup-cookie exchange, HTTP 200
for the frontend and model-catalog RPC, and the two completed conversation
turns. The `launch-url` and stdout log are private credentials and must not be
copied into reports.
