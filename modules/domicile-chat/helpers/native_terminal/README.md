# Kitty as a view of a DSH terminal

This optional Host plugin carries the existing DSH `terminal` gateway over a
same-user UNIX socket. DSH owns the shell, terminal ID, screen and input lease.
Kitty renders it. A chat is identified by its real DSH session ID; no Herdr
process or state is involved.

It is qualified in a private DSH 0.2.1-rc.2 Host and the current g7 Domicile
engine on strix-coordinator. It is **not mounted in the live Agency Web Host**.
The live Mod+Enter path remains a genuinely fresh independent NAS SSH shell.

## Mount explicitly

The qualified npm archive is `agency-kitty-dsh-0.1.0-qualified.tgz`, with a
bundled Cordis patch. Its trusted default socket is the NAS path below and
its Host identity is `agency-web`. The release owner adds the frozen package
to the profile dependencies and `@agency/kitty-dsh` to `dsh.profile.bundles`.
The exact Host's `dsh-client-connection` peer must be resolvable alongside it.
Nix also declares `dsh-plugins.kitty-native`; no default profile selects it.
An explicit mount instead of the bundle has this equivalent configuration:

```json
{
  "id": "native-kitty",
  "name": "/nix/store/…-dsh-kitty-native-0.1.0",
  "config": {
    "socketPath": "/home/tom/.local/state/agency-web/native-terminal/pty.sock",
    "serverId": "agency-web"
  }
}
```

The socket parent must be owned by the Host user and mode 0700; the socket
is 0600. There is no TCP listener, browser cookie, copied provider credential
or desktop opener. The mounted plugin creates an owner Peer with
`interactions: none`, so it cannot claim approval or question requests. Mount
changes must be coordinated with the live Host's profile owner; restarting
the Host destroys its retained terminals.

## Explicit operations on NAS

Use a real chat session ID from that Host. `create` is the only allocating
operation. It prints a route containing Host ID, Host epoch, session ID,
terminal ID, stable Kitty window class and the existing DSH sidebar params.

```sh
dsh-terminal --socket /home/tom/.local/state/agency-web/native-terminal/pty.sock \
  --server agency-web --session session-… create

dsh-terminal --socket /home/tom/.local/state/agency-web/native-terminal/pty.sock \
  --server agency-web --session session-… inventory

dsh-terminal --socket /home/tom/.local/state/agency-web/native-terminal/pty.sock \
  --server agency-web --session session-… view --epoch EPOCH --terminal TERMINAL
```

Run `view` inside Kitty's NAS SSH PTY. Ctrl+] detaches the viewer, preserving
the DSH terminal. Reopen the exact same route to recover the same process and
serialized screen. `close --epoch EPOCH --terminal TERMINAL` explicitly ends
that one terminal. Unknown terminals and stale Host epochs fail without
allocating or attaching to a replacement.

The controller's stock unattended timeout is two hours. The proof keeps that
default. A browser sidebar retention or active native viewer also retains the
terminal. This survives viewer/SSH connection loss within the Host's retention
policy; it does not survive Host restart or an explicit terminal close. There
is no automatic input replay or automatic creation on reconnect.

## Chat, sidebar and Domicile integration

The carrier obtains status and title from the same authenticated
`/api/chat-attention` route as the chat-attention lane, matching `sessionId`.
It forwards that row without reinterpreting status. Missing feed or session
is shown as unavailable. The viewer updates its title on that feed and sets
Kitty user variables `dsh_server`, `dsh_epoch`, `dsh_session`, `dsh_terminal`.
The route's deterministic `windowClass` is a join key for a native window and
the same chat/terminal. Native app/window IDs remain separate observations.

For dsh-web's existing terminal sidebar, a client plugin with the admitted
route can use the public service:

```js
ctx.sidebarRight.openTabIn(route.session, 'terminal', {
  params: { terminalId: route.terminal }
})
```

This associates the existing retained terminal instead of creating a second
one. Layout membership is client-owned; the Host plugin does not silently add
a tab in another browser. This call and a user-facing action are integration
points, not a mounted sidebar implementation. For the Imagine/dsh-domicile
rail, join the same session ID to the attention row and `windowClass` to the
observed native window. No dsh-domicile source was modified.

The chat-window lane's `#agency-chat=SESSION_ID` handoff selects the chat. This
terminal route contains no URL credential. Chrome routing and permission to
open/focus a Zenbook window remain the respective lanes' decisions. This
package registers no agent tool and sends no desktop launch request.

## Evidence and reproduction

`test/qualify.py` boots a credential-free private Host, uses the public RPC to
create one chat, and checks two terminal IDs, exact process/screen recovery,
resize and input sequencing, stale/unknown refusal, explicit scoped close,
the shared attention row, real Kitty close/reopen, live chat rename, stable
window identity and explicit CLI operations. It makes no model request.

Stage this source, the exact installed DSH package and a read-only copy of the
chat-attention plugin on compute. Run via the **target** `runtime-test` and a
private D-Bus session; `prepare.py` refuses an existing fixture directory.
The receipt and screenshots are retained under `evidence/`. Software-rendered
private proof is separate from physical Zenbook acceptance. Private compositor
teardown returned 1 with portal/Crashpad diagnostics, which are retained;
both Kitty viewers exited 0 and the private desktop stayed alive during use.
