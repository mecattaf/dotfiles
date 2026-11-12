# Durable DSH sessions on NAS

`modules/dshd.nix` enables the upstream `dshd` NixOS module on the brain
only. The `nas` release runs plain `pkgs.llm-agents.dsh`. The hand-run fleet
wrapper remains a separate entrypoint. DSH owns its live profiles, plugins,
credentials and conversations under its own home; dshd neither copies nor
rewrites those profiles. The release excludes the NAS login shell's exported
`CLOUDFLARE_API_TOKEN` from saved instance environments.

The input is `github:mecattaf/dshd.nix`, pinned by revision in `flake.lock`,
with nixpkgs following dotfiles. Update it with `nix flake update dshd` and
check that unrelated lock nodes did not move. The finished initial revision is
`a75495b29e1c003810f67899959922a81337a607`; its producer reported all twelve
package/check outputs passing, including four NixOS VM checks, in
[issue 703](https://github.com/mecattaf/dotfiles/issues/703#issuecomment-6775166427).

Nix installs the static `dshd@.service` template, `dshd.target`, the CLI and
`/etc/dshd/releases/nas` (also the default release). Instances, labels and boot
enablement are runtime data. Linger is already enabled for Tom. No instance
starts merely because the module is installed. Running instances keep their
DSH build and runner across switches and garbage collection; changing a release
does not move a running instance to it.

## Deploy without interrupting existing sessions

Build `checks.x86_64-linux.dshd-nas` and the NAS system closure on
strix-coordinator, after checking that its root filesystem has at least 25 GiB
free. NAS evaluates when needed but has zero local build jobs. Runtime-sensitive
tests use the target's `~/.local/bin/runtime-test -- ...`; tests must never
share the live user's runtime tree.

Before activation, check NAS root, store and boot space, inspect the candidate's
`dry-activate`, and keep its complete output. The permitted D-Bus action is a
reload of `dbus-broker.service`. A stop or restart of D-Bus, logind, `user@`, or
Tom's existing user units stops deployment. Review other system-service actions
for the same session-preservation requirement; do not restart Herdr or the user
manager to make an update work. Do not run GC, remove generations or reboot.

`tests/dshd-deploy/gates.py` provides read-only admission, user-unit tree and
protected process snapshots. `idle` checks load, Nix builders and commands,
and Herdr agent panes (its `busy_reasons()`, formerly update-check's); only the
actual deploying Herdr pane may be excluded, when there is one. Wait for idle rather than forcing it. Take `snapshot` immediately
before and after the switch, and `compare` them: user@1000, Herdr, its web UI,
Agency Web and every existing DSH must retain PIDs and InvocationIDs. Keep the
previous system closure available. Roll back only if a protected service is
down, and only to that previous generation.

The identity and user-tree gates are stricter diagnostics for a deployment that
adds only dshd; they report existing drift rather than proving an arbitrary
full-system update safe. Inspect every difference and the activation plan.
Update the canonical NAS checkout before switching because its raw helper links
read that checkout. Preserve unrelated working files.

## First use

Use a project directory rather than the home directory. Web and ACP starts
need no model request. Keep authenticated web URLs out of logs and receipts:
`attach` shows the origin; `attach --print-url` includes the login token.

```sh
dshd run --name work -- web
dshd get work
dshd attach work
# Disconnect SSH, reconnect, then confirm the same invocation:
dshd get work
dshd enable work
```

`enable` opts this instance into starting with the user manager, including at
boot with linger. For an ACP frontend, create with `dshd run --name editor -- acp`
and use `dshd attach editor` as its agent command. Detaching does not cancel
the running session. One controller is active at a time; `--takeover` transfers
control explicitly. A foreground or background headless run executes its prompt
once; read and wait on the same instance instead of submitting the prompt again.

```sh
dshd run --bg --name task -- headless 'reply ok'
dshd wait task
dshd read task
dshd ls
```

The first real-DSH acceptance must cover web readiness and a stable port across
restart, SSH disconnect/reconnect, ACP resume, the headless exit code, terminal
profile refusal, and stop/remove of temporary instances. The producer's stub
tests alone do not establish those real-package edges. Keep failures visible
and fix interoperability upstream before claiming persistence is qualified.

`dshd update NAME` selects the latest declared release for the next start;
`dshd update -R NAME` also restarts a running web/ACP instance deliberately.
`dshd stop NAME` stops it, and `dshd rm NAME` removes a stopped instance without
deleting DSH's conversations. `dshd --skill` describes the JSON control plane.

Imagine can associate one foreground DSH conversation with a Domicile workspace
and restore its layout. dshd supplies the NAS process lifetime underneath that
association. Background runs share the inventory without consuming desktop
workspaces. Installing dshd does not adopt existing ordinary Kitty SSH sessions,
and the workspace/thread navigation integration is a separate change.
