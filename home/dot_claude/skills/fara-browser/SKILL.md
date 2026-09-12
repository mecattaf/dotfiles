---
name: fara-browser
description: Delegate a bounded task requiring a live, logged-in Google Chrome browser to local FARA through the coordinator's shared Sway/noVNC desktop. Use for browser-only actions such as filling forms or entering an explicitly specified message, with human takeover and recorded trajectories.
---

# FARA browser tasks

Run `fara-browser` on **coordinator**, through the existing SSH/Herdr terminal.
The human opens **http://browser.internal** on the BE550 network. One task runs
at a time. This uses Microsoft's pinned Fara15Agent with its normal prompt,
action vocabulary and trajectory writer; the environment is stock noVNC.

## Before delegating

1. Run `fara-browser status` and `fara-browser profiles`. Choose the existing
   Chrome profile explicitly from its directory, display name and recorded Google
   account mapping. Listings include the active FARA task per profile. `status`
   identifies the running profile, its account at launch, and current Chrome
   metadata. These are Chrome identities, not proof of a website's signed-in
   account: verify the requested website identity in the live page before acting.
2. If another task is active, inspect it rather than launching a second one.
3. `fara-browser keyring` checks the default GNOME keyring without reading any
   secrets. If locked, run `fara-browser unlock` and tell the human to enter the
   keyring password in the shared desktop. Rerun after it reports unlocked.
   Never request the password in chat, a prompt file, or a command argument.
   Unlock is normally needed once after reboot, or after the keyring relocks.
4. If Chrome is running on another display, the tool refuses to redirect or kill
   it. Explain the concrete conflict; preserve open work before moving Chrome.

## Task contract

Write a UTF-8 prompt file containing the exact goal, selected website identity,
recipient/record identifiers, supplied text or values, permitted final action,
and observable success condition. Keep drafting/research outside the visual loop
when available tools can do it. FARA operates the live browser.

Preserve the user's existing authorization: an authorized send does not require
a second generic confirmation. A draft request does not authorize sending.
Do not broaden recipients, invent missing values, or repeatedly retry a send
whose result is uncertain. Ask the user or inspect the recorded evidence.

```bash
fara-browser run --profile 'Profile 2' --task-file /path/to/task.txt --max-steps 30
```

The CLI opens that profile automatically and includes its recorded profile/account
metadata in FARA's task context. Use `profiles` and `status` as the operator;
FARA does not need to operate the Chrome launcher menu itself.

Run this as a foreground tool process (or a managed process you continue to
monitor). Do not fire and forget. It prints a task ID and status; inference stays
on coordinator, starting the on-demand model service when needed.

The adapter supports the Fara 1.5 4B, 9B and 27B family through the same upstream
agent. `--model MODEL_ID --endpoint http://127.0.0.1:PORT/v1` selects an existing
local server; its `/models` response must advertise that ID. Status and replay
record the selection. Only the default 9B endpoint starts automatically; choosing
another size does not download weights or reconfigure the fleet.

## Takeover, completion and inspection

The human can open `http://browser.internal` at any time to silently spectate.
During FARA control, the viewer shows the task/profile/account and disables mouse,
keyboard and clipboard input. Opening or closing it does not interrupt the run.
The sidebar's Chrome menu opens existing profiles when no FARA task is active;
those manual windows persist until closed by the human.

The human's **Take control** button pauses the run and disconnects FARA's viewer.
The equivalent CLI is `fara-browser pause`. When the human finishes:

```bash
fara-browser resume --message-file /path/to/correction.txt
```

The correction and a fresh screenshot enter the existing FARA conversation.
`fara-browser cancel` ends the task and cleans up. Closing the human viewer alone
does not cancel a task. A model question leaves the task paused for the human.

Runs live under `~/.local/state/fara-browser/runs/<task-id>/`. Microsoft FARA
writes `task.json`, `solver_log/events.jsonl`, `data_point.json` and per-step
screenshots. `lifecycle.jsonl` adds takeover/interruption/cleanup events.
`replay.html` is a local inspector of those existing records, not a second log.
Treat this folder as private browser data; do not publish it automatically.

Check the recorded final action and outcome before reporting success. Step-limit,
error and cancellation outcomes are not success. If an external action's outcome
is uncertain, inspect rather than replaying the whole task blindly.

Completion closes only task-owned Chrome windows/tabs and FARA's helper browser.
Existing profiles and the desktop keyring persist. Report any cleanup failure.

## Other visual controllers

Codex or another approved visual controller can use the same stock noVNC page.
First inspect `fara-browser status` and pause any FARA run; wait for `paused` and
the viewer's **You have control** state. Drive that viewer's canvas and keyboard.
Its `window.faraRfb().toDataURL()` exposes the full desktop image; account-bearing
Chrome does not need remote debugging. Map screenshot coordinates to the canvas
bounds if the human viewer is scaled. Do not run two controllers concurrently.
Direct viewer actions outside a FARA run are not automatically trajectory-logged.
