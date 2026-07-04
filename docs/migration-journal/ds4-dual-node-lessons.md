# Dual-node ds4 on two Strix Halo boxes — build report & lessons

_Setup completed 2026-06-17. This doc is the "do it faster next time" runbook + postmortem._

## What we built

A pipeline-parallel **ds4** (antirez's DeepSeek V4 Flash engine) cluster across **two identical AMD Strix Halo desktops**, serving an OpenAI/Anthropic-compatible API that a local `pi` coding-agent session talks to.

| | Coordinator | Worker |
|---|---|---|
| Box | primary (user `tom`, hostname `harness`) | `sodimo` (headless, hostname **also** `harness`) |
| GPU / RAM | Radeon 8060S (gfx1151) / 125 GB | same |
| Thunderbolt IP | `169.254.200.164` | `169.254.53.173` |
| ds4 role | `coordinator`, layers `0:21+output` | `worker`, layers `22:output` |
| Ports | HTTP `:8000`, coord `:8081` | connects out to coord `:8081` |
| Extras | `--mtp`, `--kv-disk-dir /kv`, ctx 131072 | ctx 131072 |

- **Link:** direct Thunderbolt host-to-host cable, `thunderbolt0`, ~0.4 ms RTT, NM-assigned IPv4 link-local.
- **Model:** `DeepSeek-V4-Flash-Q4KExperts-F16HC-F16Compressor-F16Indexer-Q8Attn-Q8Shared-Q8Out-chat-v2-imatrix.gguf` (154 GB) + `DeepSeek-V4-Flash-MTP-Q4K-Q8_0-F32.gguf` (3.6 GB), in `~/ds4` on **both** nodes.
- **Image:** `docker.io/kyuz0/strix-halo-ds4-toolbox:multi-node-rocm-7.2.4`.
- **Throughput:** ~11 tok/s generation (quality > speed; the TB hop is pure overhead vs single-node).

---

## The hard part: getting into the headless worker

This ate ~80% of the effort. The model download and cluster launch were straightforward; **access was the saga.**

What was wrong / discovered:
- **Tailscale was offline** (`sodimo` last seen hours ago) and its tailnet DNS was down — no path that way.
- **No password exists.** The box was provisioned (kickstart/flasher) with `rootpw --lock` and `user --name=core --lock`. Password auth is impossible by design.
- **No shared keys.** None of the primary's keys (`flasher`, `kharness_loopback`, `ds4-cluster`) nor the laptop's `tom@harness-xps` key were trusted by `sodimo`, for any username (`sodimo`/`tom`/`core`/`mecattaf`/…). The flasher key is for user **`core`**, but the live desktop user is **`sodimo`** — different `authorized_keys`.
- **The only live path was the Thunderbolt cable** (its sshd answered; everything else was dead).

How we got in (the move that worked):
1. Generated a dedicated key on the primary: `ssh-keygen -t ed25519 -f ~/.ssh/ds4_worker`.
2. Uploaded a tiny key-install script to a public paste (`paste.rs`) — installing a serverless fetch was needed because the sandbox kept killing local listeners and the box had no inbound IPv4 on the TB link.
3. On the worker's **autologin console** (mod+enter → kitty), typed a short one-liner blind: `curl -s https://paste.rs/<id> | sh`. That appended `ds4_worker.pub` to `sodimo`'s `~/.ssh/authorized_keys`.
4. From then on: `ssh -i ~/.ssh/ds4_worker sodimo@'fe80::…%thunderbolt0'` — done, survives reboots.

**Lesson:** for a locked-down headless box, don't hand-type the key (a 68-char base64 string typed blind *will* corrupt). Type a short `curl … | sh` that *fetches* the key. And remember the only assumption you can't skip: **someone has to run one command at the console once.** There is no pure-software way into a box that trusts a key you don't hold and has passwords locked.

---

## Lessons learned / things that bit us

1. **SSH config + IPv6 zone index.** A `HostName` with `%thunderbolt0` makes ssh try to expand `%t` as a token → `unknown key %t`. **Escape it as `%%thunderbolt0`** in `~/.ssh/config`. (Bare command-line `user@fe80::…%thunderbolt0` is fine; only the config file needs the escape.)

2. **rsync + link-local IPv6.** `rsync … sodimo@fe80::…%thunderbolt0:path` mis-parses the colons (`Could not resolve hostname fe80`). Fix: use the **SSH alias** (`ds4-worker`) so rsync sees no colons, or bracket the address.

3. **HF Xet downloads stall** on these boxes (both nodes, ~0–5 MB/s then frozen, many open conns, no progress). Don't fight it — use **`aria2c -x16 -s16`** against the direct CDN URL (`…/resolve/main/<file>?download=true`) with `--header="Authorization: Bearer $(cat ~/.cache/huggingface/token)"`. An **HF token lifts the unauthenticated rate cap** (matters a lot).

4. **Download where it's fastest, copy over Thunderbolt.** The primary's wifi did ~34 MB/s; the worker's only ~6 MB/s. So we downloaded the 154 GB on the primary and shipped it to the worker over the 10 Gbps TB link with **`rsync -a --append-verify`** (~4 GB/s for the matching prefix, only the tail crosses the wire). `--append-verify` is the right flag when the destination already has a partial from the same source.

5. **Firewall was the final blocker.** The coordinator's `thunderbolt0` was in firewalld's **`public`** zone, which **rejected the worker's connection to `:8081`** ("No route to host" — that's a firewalld REJECT, not a missing listener). Symptom in ds4: `distributed route incomplete: missing layer 22`.
   - **Fix:** `sudo firewall-cmd --zone=trusted --change-interface=thunderbolt0` (+ `--permanent`).
   - The **worker connects outbound**, so the worker's own active firewalld (where we had no sudo) **does not matter** — its inbound `data_listen` port being blocked is harmless. Good to know: you only need to open the **coordinator's** TB interface.

6. **podman details.**
   - `--rm -it` fails when detached ("not a TTY"). Use **`-d --name … --replace`** instead.
   - KV-disk needs a **writable** mount: `/models` is `:ro`, so mount a separate `-v ~/.cache/ds4-kv:/kv` and pass `--kv-disk-dir /kv`.
   - Containers are **`--rm` → not persistent across reboot.** (TODO: systemd units.)

7. **Shell/automation footguns (cost us real time).**
   - `pkill -f "hf download"` **matches its own command line** and kills the launching shell. Use `pkill -x <procname>` (exact name) or run the kill from a context whose cmdline doesn't contain the pattern (e.g. remote `bash -s` over ssh, whose argv is just `bash -s`).
   - The agent sandbox **SIGTERMs background listeners** (a local `http.server` died with exit 144). Use the harness's managed background, or avoid inbound listeners entirely (we switched to an outbound paste).
   - Foreground `sleep` is blocked — wait with `until <cond>; do sleep N; done` or a backgrounded watcher.

8. **The model thinks in Chinese** by default (visible reasoning trace); the final answer follows your prompt language. Use a no-think mode if you don't want the trace.

---

## Exact system changes made (so you can reproduce or revert)

**On the coordinator (primary, `tom`):**
- Created keypair `~/.ssh/ds4_worker{,.pub}`.
- Added to `~/.ssh/config`:
  ```
  Host ds4-worker
      HostName fe80::6d1d:f33d:36f6:4129%%thunderbolt0   # note the %% escape
      User sodimo
      IdentityFile /home/tom/.ssh/ds4_worker
      IdentitiesOnly yes
      StrictHostKeyChecking accept-new
  ```
- Firewall: `thunderbolt0` → `trusted` zone (runtime + `--permanent`).
- `pipx install` the cockpit (`ds4-cockpit`).
- Added `pi` provider `ds4` to `~/.pi/agent/models.json` → `http://127.0.0.1:8000/v1`, model `deepseek-v4-flash`, 131072 ctx.
- Created `~/ds4` (models, 154 GB + MTP) and `~/.cache/ds4-kv`.
- Running container `ds4-coordinator`.

**On the worker (`sodimo`):**
- Installed `ds4_worker.pub` into `~/.ssh/authorized_keys`.
- `pipx install "huggingface_hub[cli]"` (for `hf`) and the cockpit (`ds4-cockpit`).
- Copied the HF token to `~/.cache/huggingface/token`.
- Created `~/ds4` (154 GB model copy).
- Running container `ds4-worker`.

---

## Fast-path runbook for next time

```bash
# 0. Reach the worker (key already installed; if not, repeat the paste-fetch console step)
ssh ds4-worker 'hostname'                      # via ~/.ssh/config alias (with %% escape)

# 1. Coordinator firewall (one-time per boot if not permanent)
sudo firewall-cmd --zone=trusted --change-interface=thunderbolt0

# 2. Model present on both nodes? If not: aria2c on the fast box + rsync over TB
#    aria2c -c -x16 -s16 -k1M --header="Authorization: Bearer $(cat ~/.cache/huggingface/token)" \
#      -d ~/ds4 -o <Q4>.gguf "https://huggingface.co/antirez/deepseek-v4-gguf/resolve/main/<Q4>.gguf?download=true"
#    rsync -a --append-verify ~/ds4/<Q4>.gguf ds4-worker:/home/sodimo/ds4/<Q4>.gguf

# 3. Launch worker FIRST (it waits for the coordinator)
IMG=docker.io/kyuz0/strix-halo-ds4-toolbox:multi-node-rocm-7.2.4
Q4=DeepSeek-V4-Flash-Q4KExperts-F16HC-F16Compressor-F16Indexer-Q8Attn-Q8Shared-Q8Out-chat-v2-imatrix.gguf
ssh ds4-worker "podman run -d --name ds4-worker --replace --network=host --ipc=host --cap-add=SYS_PTRACE \
  --device /dev/kfd --device /dev/dri --group-add video --group-add render \
  --security-opt seccomp=unconfined --security-opt label=disable -v /home/sodimo/ds4:/models:ro \
  $IMG ds4-server -m /models/$Q4 --ctx 131072 --role worker --layers 22:output --coordinator 169.254.200.164 8081"

# 4. Launch coordinator
mkdir -p ~/.cache/ds4-kv
podman run -d --name ds4-coordinator --replace --network=host --ipc=host --cap-add=SYS_PTRACE \
  --device /dev/kfd --device /dev/dri --group-add video --group-add render \
  --security-opt seccomp=unconfined --security-opt label=disable \
  -v ~/ds4:/models:ro -v ~/.cache/ds4-kv:/kv \
  $IMG ds4-server -m /models/$Q4 --ctx 131072 --host 0.0.0.0 --port 8000 \
  --mtp /models/DeepSeek-V4-Flash-MTP-Q4K-Q8_0-F32.gguf --mtp-draft 1 \
  --kv-disk-dir /kv --kv-disk-space-mb 16384 --role coordinator --layers 0:21 --listen 169.254.200.164 8081

# 5. Verify + launch agent
curl -s 127.0.0.1:8000/v1/models | grep deepseek-v4-flash
kitty @ launch --type=os-window --title "ds4 dual-node — pi agent" pi --provider ds4 --model deepseek-v4-flash
```

**If inference returns `distributed route incomplete: missing layer 22`:** the worker can't reach the coordinator's `:8081` → check the coordinator's `thunderbolt0` firewall zone (must be `trusted`) and that both TB link-local IPs are present (`ip -br addr show thunderbolt0`).

## Open follow-ups
- **Persistence:** wrap both servers in systemd units (+ make the firewall change permanent, which it is) so the cluster auto-starts on boot.
- **Worker firewall:** currently irrelevant (worker dials out), but if a future ds4 version needs inbound to the worker, you'll need sudo on `sodimo` to trust `thunderbolt0`. **← This bit us. See Appendix A.**
- **Speed:** if ~11 tok/s is too slow, single-node IQ2_XXS on the primary is ~2–3× faster.

---

# Appendix A — `--kv-disk-dir` wedges the coordinator (the worker-firewall follow-up, realized)

_Added 2026-06-17, ~hours after the original build. The "if a future ds4 version needs inbound to the worker" follow-up above came true — it wasn't a future version, it was the `--kv-disk-dir` flag we already had on the coordinator._

## Symptom
The local LLM went **completely unresponsive**. `GET /v1/models` still answered instantly (coordinator-only), but **any actual chat completion hung forever**. It had been wedged for ~2 hours with zero new log lines. A red herring made it look session-related: the previous Claude Code session, on shutdown, warned "still one running program" — but that was incidental. **Both containers (`ds4-coordinator`, `ds4-worker`) were up the entire time.** The hang was self-inflicted by the cluster, not by killing any process.

## Root cause
`--kv-disk-dir /kv` on the coordinator enables KV-cache offload to disk. In **dual-node** mode the KV is split across both nodes (coordinator holds layers `0:21`, worker holds `22:output`), so to stage/evict a sequence's KV to disk **the coordinator must reach into the worker** and pull the worker's half. It does this by **dialing the worker on an ephemeral port (observed: `41265`)** — i.e. an **inbound** connection to the worker.

But the worker's `thunderbolt0` is in firewalld's **`public`** zone, which **rejects** that connect:

```
kv cache skipped tokens=6729 reason=evict because KV payload staging failed:
  unable to connect to 169.254.53.173:41265: No route to host
```

`No route to host` is a firewalld **REJECT** (same tell as the original `:8081` blocker in Lesson #5), **not** a dead host — `ping` to the worker succeeds at 0.9 ms and the worker's `ds4-server` is `LISTEN`ing on `0.0.0.0:41265`. The coordinator then sits in a `SYN-SENT` retry loop (source port cycling) and blocks the whole request path. It does **not** self-recover.

**Why it never showed up during the build:** the main pipeline is **worker→coordinator outbound** (Lesson #5/#57: "you only need to open the coordinator's TB interface"). That conclusion is correct *only without* `--kv-disk-dir`. The very first **KV eviction** (long context grew, then a fresh prompt caused a `token-mismatch` cache miss) was the first time anything dialed *into* the worker — and it instantly hit the wall the follow-up predicted.

## Diagnosis trail (fast next time)
```bash
ss -tnp | grep 169.254.53.173
#   ESTAB ...:8081 <-> ...:54918   → main pipeline UP (worker dials out, fine)
#   SYN-SENT ...:<eph> -> :41265   → coordinator stuck dialing INTO the worker  ← the smoking gun
podman logs --tail 20 ds4-coordinator | grep -i 'kv .*staging\|No route to host'
ssh ds4-worker 'ss -tlnp | grep 41265; firewall-cmd --get-zone-of-interface=thunderbolt0'
#   LISTEN 0.0.0.0:41265 (ds4-server)   +   zone = public   → worker firewall rejects inbound
```

## Why we can't "just open the worker firewall"
Per the saga in the body: `sodimo` has **no password and no sudo**, and `rootpw` is locked. There is **no root on the worker** without re-provisioning, so `firewall-cmd --zone=trusted --change-interface=thunderbolt0` on the worker is **not available**. (An SSH local-forward doesn't help either: ds4 dials the worker's *TB IP* `169.254.53.173:41265` directly, not a redirectable localhost.)

## The fix (applied, reversible)
**Relaunch the coordinator without `--kv-disk-dir` / `--kv-disk-space-mb`.** With no disk offload, the coordinator never stages KV to the worker → never dials inbound → never wedges. KV stays in RAM, which is fine here: 125 GB/node, the model is split across both nodes, and DeepSeek V4's MLA cache is tiny (context buffers for full 131072 ctx ≈ 4.5 GiB). For a single `pi` agent this is more than enough; the only thing lost is cross-request KV *persistence to disk* and the ability to spill beyond RAM.

```bash
IMG=docker.io/kyuz0/strix-halo-ds4-toolbox:multi-node-rocm-7.2.4
Q4=DeepSeek-V4-Flash-Q4KExperts-F16HC-F16Compressor-F16Indexer-Q8Attn-Q8Shared-Q8Out-chat-v2-imatrix.gguf
podman run -d --name ds4-coordinator --replace --network=host --ipc=host --cap-add=SYS_PTRACE \
  --device /dev/kfd --device /dev/dri --group-add video --group-add render \
  --security-opt seccomp=unconfined --security-opt label=disable \
  -v /home/tom/ds4:/models:ro -v /home/tom/.cache/ds4-kv:/kv \
  "$IMG" ds4-server -m /models/$Q4 --ctx 131072 --host 0.0.0.0 --port 8000 \
  --mtp /models/DeepSeek-V4-Flash-MTP-Q4K-Q8_0-F32.gguf --mtp-draft 1 \
  --role coordinator --layers 0:21 --listen 169.254.200.164 8081
#   ^ identical to runbook step 4, MINUS  --kv-disk-dir /kv --kv-disk-space-mb 16384
```

- **Worker needs no touch.** Restarting the coordinator drops the worker's pipeline socket; the worker **auto-redials** `:8081` within seconds (it "waits for the coordinator"). Confirmed: new `ESTAB` reappeared on its own, no `ds4-worker` restart.
- Coordinator reload was **~20 s** (model still in page cache) → `listening on http://0.0.0.0:8000`.
- Verify: `curl -s -m 60 127.0.0.1:8000/v1/chat/completions -d '{"model":"deepseek-v4-flash","messages":[{"role":"user","content":"say PIPELINE OK"}],"max_tokens":24}'` → real tokens in ~3 s through both nodes. (Mind Lesson #8: the model emits its reasoning trace first, so a tiny `max_tokens` returns mid-think — that's expected, not a fault.)

## Takeaways
- **Correct the body's Lesson #5/#57 mental model:** "you only need the *coordinator's* TB interface trusted" holds **only without `--kv-disk-dir`**. Disk-KV offload in dual-node is **bidirectional** and needs the **worker's** `thunderbolt0` trusted too.
- **Runbook step 4 is a trap as written** — it still carries `--kv-disk-dir /kv --kv-disk-space-mb 16384`. Either drop those flags, or first get root on `sodimo` and `firewall-cmd --zone=trusted --change-interface=thunderbolt0 [--permanent]` there. Don't enable disk-KV until the worker firewall is open.
- **`No route to host` on a box that pings = firewalld REJECT**, every time on this cluster. Check zones before you suspect the process.
- To re-enable disk-KV later: get a one-time console session on `sodimo` (the paste-fetch trick), but note root is *locked* — you'd need to re-provision with an unlocked privileged user, or add a `firewalld` rule via a mechanism that has `CAP_NET_ADMIN` on the host (rootless podman does **not**).
