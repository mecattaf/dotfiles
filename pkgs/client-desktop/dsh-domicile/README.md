# dsh-domicile 0.1 — read-only Imagine snapshots

This first implementation queries **Imagine's actual workspace tree**, including all enclosed tiled and floating native/browser windows, rather than pretending the SDK's flat list is a workspace model. It is attached to the live Imagine desktop through a reviewed read-only NAS→Zenbook route, qualified on 2026-11-05. It is **not registered in the production DSH profile**; full i3ipc-equivalent actions and events remain separate work.

## Ownership and capabilities

Imagine owns the reducer and final rendered Stage geometry. Its privileged adapter is in the adjacent Imagine repository at `src/imagine/ipc/`. This server repository owns transport validation, explicit desktop selection and read-only queries. DSH and native Claude sessions/credentials stay on the server; the desktop runs only Imagine/Domicile and a small Python helper. There is no desktop HTTP listener, client DSH Host, general execution tool, generated-card privilege or second layout model.

Implemented: full snapshot, workspace membership query, typed identities, focus, outputs/scales, final placements, nested tiling containers, floating groups, fullscreen references, hidden scratchpad queue, managed background apps and native popup parentage. `background` identifies managed background apps and can include currently visible windows; hidden scratchpad entries are absent from workspace trees until shown as scratchpad floats.

Not implemented: replayable events, window focus/layout mutations, opening/closing viewers, DSH-session termination, layout persistence across shell refresh, full i3ipc parity or an installed DSH plugin. These capabilities are explicitly false in responses. Current server `query()` is directly usable by a narrow native DSH adapter later; no production tool registration was made here.

Default output omits all window titles, full URLs, page/document contents, descriptions, storage partitions, process environments, native video/frame counters and credentials. Browser app IDs and native desktop-app IDs are typed identities, not DSH session IDs.

## Transport

1. NAS selects a required registry desktop ID; no default focused machine. Strict SSH uses the configured Tailscale IP, existing known HostKeyAlias, BatchMode and StrictHostKeyChecking. ControlMaster/ControlPath reuse and agent forwarding are disabled; no LAN/public fallback.
2. The desktop helper reads its local identity/config and verifies that the requested desktop matches. It discovers exactly one live `domicile-ipc.*.sock` in the explicitly configured private runtime directory. Directory/socket owner, permissions and native socket peer UID are checked. Zero or multiple live peers fail; a stale refused socket is skipped. Discovery survives launcher PID changes without selecting an ambient SSH desktop. `socketPath` is an explicit private-fixture override, not the proposed production setting.
3. It creates a random 128-bit nonce directory under its mode-0700, owner-checked reply root. It invokes only `domicile send-shell imagine snapshot-v1 NONCE DESKTOP EPOCH|- REVISION|-`, using argv and the selected socket. Native delivery acknowledgment alone is not query success.
4. Imagine's **existing command owner** calls the returned snapshot handler. The hook has no second shell-command listener. Only that exact verb is consumed; unrelated/unknown commands retain their existing handling. It projects current reducer state and final Stage placements and uses public `files.write(...,{atomic:true})` to the fixed nonce path. No path comes from the query.
5. The helper waits at most three seconds including delivery, opens only its own nonce response with O_NOFOLLOW, bounds it to 2 MiB, validates request/desktop identity and schema, then removes only its own file/directory. SSH has a separate ten-second bound. No cache of previous desktop results is served when the shell is absent/locked. A late asynchronous atomic write can race timeout cleanup: its parent may already be gone (bounded write failure), or an in-progress temporary file may prevent rmdir. There is no broad janitor, no recursive deletion, and no claim that every timeout leaves no file. Preserve/report that cleanup error; an orphan nonce can never satisfy a new request.

SDK files are refused while locked, and native `send-shell` is itself refused while locked. The adapter also treats unknown/true lock status as unavailable. Unexpected config read/write/rejection errors use bounded diagnostic operation/kind codes; only NotFound for optional config is quiet. Lock status is sampled again when handling a request. If the desktop locks after a successful capture, that already-completed read is not retroactively revoked.

## Snapshot identity and reconciliation

Every successful envelope carries protocol `agency.domicile.snapshot`, version1, exact request/desktop ID, UUIDv4 **mount epoch**, semantic revision, capture time and source identities. A new hook mount creates a new epoch. A changed semantic projection increments revision; window title/content repaint and synced video frames do not. Lock/unlock changes revision too. No claim of lossless action/event history is made.

Workspace IDs name the reducer's actual workspace names. Window IDs retain its `app:`/`browser:` namespace and separately identify underlying native/browser window IDs. Container identities are **epoch + revision + workspace + tiling/float layer + float index + path**; paths cannot be reused across revisions. A request may require an exact epoch/revision. Mismatch returns `epoch-changed` or `stale-revision` without a snapshot; explicitly request a fresh snapshot to reconcile. Viewer/focus IDs never replace DSH session ownership.

The live adapter currently uses stock SDK `67c29a9906905bd5e1679803232c2f510b3fed9e`. The maintained follow-up now requires `sdkSource` as an explicit full40hex commit in client config and reports it without a default; this source/config change is staged, not deployed. Its current67 config and protocol must be pinned together. A future SDK/package update must review layout mappings and supply the matched source identity at a safe engine/session transition. `imagineSource` identifies the reviewed deployed immutable source. Configured identity is deployment provenance, not native engine attestation. See the separate SDK identity receipt.

## Source/API evidence

- Public `WindowState` supplies real screens/homes/workspaces/floats/scratchpad/background/popups and window identities; `src/imagine/useAgencyWindows.ts` is the owned state bridge.
- Final `screens` after `agencyScreens` and `presentChrome` supplies actual window surface/frame/bar geometry, including zero gaps, rail and chrome policy. `displays` supplies scale. No layout is recomputed by the adapter.
- `@domicile-desktop/sdk/desktop/shell` exposes command words and delivery, not query responses. `desktop/system-calls.ts:68` documents atomic writes; file/process calls are refused while locked.
- `tree/node` is **not** a public package export. The adapter derives its tree type through public WindowState and maps the four pinned numeric layout tags; it does not import a private module. An initial failing test caught that import and is retained in the proof history.
- The public browser list supplies stable app IDs that WindowState does not retain. Only those IDs are joined into window metadata, not the browser URL/title/partition.

## Reviewed live integration

Launch owner controls Imagine Desktop/AgencyKeys/Nix. The deployed integration uses:

```tsx
import { useImagineSnapshot } from "./ipc/useImagineSnapshot";
// After final chrome.screens; displays and windows are already owned here.
const snapshotCommand = useImagineSnapshot({ domicile, state: windows, screens, displays });
// First recognized branch in existing onAgency (which receives words without prefix):
if (snapshotCommand(args)) return;
```

Install the helper plus sibling `protocol.py` into one reviewed client directory, with a known Python interpreter; preserve executable mode. Stage owner-only `.config/dsh-domicile/client.json` based on `client.example.json`, real user runtime directory and exact Domicile/source identities. The helper creates its private reply root; no always-on daemon/service is needed. Optional config absence leaves the hook disabled. The deployed Nix module installs the reviewed owner-only config atomically before Home Manager linkGeneration triggers the watched shell refresh. The hook reads config once at mount (retrying on unlock); identity-config-only updates require lifecycle coordination. The checked TSX, relative production modules, immutable source stamp and companion user link ship together.

On NAS, fill a reviewed `desktops.json` from `desktops.example.json` using the **actual existing trusted SSH identity**, then:

```sh
python3 query.py --registry desktops.json --desktop zenbook
python3 query.py --registry desktops.json --desktop zenbook --workspace 4
python3 query.py --registry desktops.json --desktop zenbook --workspace 4 \
  --expect-epoch UUID --expect-revision 7
```

`query(registry, desktop, workspace=None, expected=None)` is the importable server surface. It provides no caller-supplied command/path/environment and no mutating operation. A production DSH wrapper should advertise only snapshot/workspace query with a configured desktop allowlist, preserve the exact envelope, and keep generated cards outside that authority. Root review preceded the current read-only live attachment; any production DSH capability/profile integration still needs its own concrete review.

## Proof and limits

Evidence checkpoint: `/home/tom/wednesday/agency-overnight-20261105/dsh-domicile/`.

- Eight new TS projection/protocol tests; existing Imagine suite and bundle pass against exact installed stock dependencies. Seven Python schema/transport/private-directory/socket tests cover schema mutations, privacy and cross-references through compute runtime-test.
- Final real private stock Domicile run5: eleven native command/file queries; native/native/browser workspace membership, workspace move, scratchpad hide/show, repaint-stable revisions, stale-revision refusal, page reload with new mount epoch, retained native/browser identities, actual socket discovery/peer verification, actual lock refusal and zero captured JS exceptions. Both native process and PTY identities stayed unchanged before owned teardown.
- Tests ran only on strix-coordinator through strict tailnet and target runtime-test. Private D-Bus and private PAM fixture use existing supported launch seams; no engine/source patch or host PAM change. The public top-level launcher does not accept compositor `--pam-confdir`; a tiny private argv wrapper adds it to the unchanged compositor.
- Preserved initial missing private D-Bus environment, private-PAM flag placement failure, initial private-tree import failure and first lock test's explicit native refusal to lock without PAM. Expected private portal/systemd availability errors and the pre-existing Chrome allocator teardown dump remain retained. Passing query behavior does not mean teardown is clean.
- The production NAS→Zenbook route is now qualified: four bounded native read-only queries validate the real two-output homes/membership and stable agency-web host window identity. Owner1001/modes0700+0600, immutable Imagine source and actual command hookup pass. Both original DSH/native Claude bindings, eight tracked core/broker identities and the exact liked whitepoint survive automatic refresh. No live lock test, content screenshot, mutation or DSH tool registration was performed.
- Live authority: `~/wednesday/agency-overnight-20261105/dsh-domicile-integration/RECEIPT.md`, `CANDIDATE.json` and `LIVE-RETENTION.json`. Exact current profile is `qxw1v5385jzkmhd30pnjgz1nlf7v0whd`, stock SDK67c29a9 / engine62a671f. The NAS registry uses existing strict Tailnet client authority with masters disabled; no client DSH/listener/provider credentials. No claim of full i3ipc parity or persistent layout restore.
- These learning updates are newer than the deployed locked local NAR; source publication is not authorized and future packaging must deliberately repin it. The separate matched touchpad SDK/engine must be qualified together before changing the watched source under a loaded engine.

## First-party DSH capability follow-up (staged)

`plugin/` registers exactly `domicile_snapshot` and `domicile_workspace` using
the installed rc.2 public registry, a fixed copied Python runner and explicit
desktop allowlist. A private actual NAS Host passed snapshot/WS1/stale queries;
no production profile or native adapter was changed. The separate native bridge
proposal passes actual rc.2 cold-history lifecycle validation with controlled
SDK calls and no provider request. Final copied pack3 adds tested owned-process
cancellation. See `~/wednesday/agency-overnight-20261105/dsh-domicile-capability/`.

The trusted registry may optionally name `sshConfig`, an absolute regular
owner0600 file used with `ssh -F`; strict tailnet/key/master options remain
explicit. This handles Nix-store-root SSH config ownership inside runtime-test
without weakening SSH checks, forwarding an agent or copying private keys.
Model arguments cannot provide this option.
