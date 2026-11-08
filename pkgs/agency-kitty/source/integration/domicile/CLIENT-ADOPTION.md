# Client adoption must preserve the current desktop

This is a composition plan, not a deployment source or activation receipt.
The native terminal, editor and actual three-chord proofs are ready. The live
client has not adopted them. Deploying the canonical dotfiles client profile
would currently restore a different desktop configuration.

## Source boundaries checked on 2026-11-08

Read-only Git and public configuration inspection at 04:00–04:05 UTC found:

- Canonical `~/dotfiles` resolves to `/home/tom/mecattaf/dotfiles`, branch
  `main`, commit `5c03a0c6aeff50fc55a3afa0b1b7498f4e4d2593`.
- Our package/editor integration is commit
  `48307adde7b12745041e668e0b2015a8879bac6f`, branch
  `feat/kitty-consolidation-20261107`, in
  `/home/tom/.wt/kitty-consolidation/dotfiles-integration`.
- The Domicile owner's separate worktree is
  `/home/tom/.wt/dotfiles/domicile-first-pass-20261105`, detached at
  `87491201700acc5051cb3edfb55f5551a4eb9fbe`, with substantial tracked and
  untracked changes. Its committed HEAD remains a starter/trial configuration;
  its current Imagine, default-login and Agency Web composition is partly dirty.
- The common ancestor is `9cefeea0afbb3503e36849a8b97f7ce1b38ecf07`.
  Integration and owner HEAD have 25 and 30 exclusive commits respectively.
  Only `flake.nix` and `flake.lock` overlap among their committed changed paths.
  Read-only legacy `git merge-tree BASE OWNER INTEGRATION` reports no conflict
  markers. That says nothing about including or qualifying the dirty desktop.

Neither canonical main nor our integration contains `modules/domicile.nix`,
`modules/domicile-apps.nix`, the client TSX entry, or its terminal dispatcher.
Their client host imports no Domicile module, and their flake checks explicitly
require greetd's `sway-physical-session`. A whole `#client` activation from
either source would omit the Domicile package/configuration/helper ownership
and restore Sway login policy. It must not be recommended as this rollout.

The dirty owner source instead imports `modules/domicile.nix` and
`modules/agency-web-client.nix`, selects Domicile for greetd's initial login,
returns to a shell after exit, and sets greetd `restartIfChanged = false`.
Its Domicile module owns the checked TSX and companion Imagine links, snapshot
configuration staged before Home Manager link replacement, console recovery,
and the physical login environment. These are a single desktop composition.

An owner worktree is also not proof of the installed profile. Its lock still
names Domicile `67c29a9906905bd5e1679803232c2f510b3fed9e`, whereas the separate
read-only live-client Rust-source audit matched all 424 checked files to
`75708d7638002e1bba421cf83f6927298dbc1c3a`, with zero differences. That receipt
is `/home/tom/.wt/kitty-consolidation/client-live-dnd-base.json`, described in
[the native drag proof](../../docs/NATIVE_FILE_DND.md). Do not call the owner
HEAD, its dirty lock, or a canonical closure the exact current client profile.

## Compose in an isolated descendant, after the owner boundary is explicit

Use a future `/home/tom/.wt/kitty-consolidation/client-composition` worktree.
Start from the desktop owner's reviewed commit containing the current public
composition. Until that owner lands it, keep its dirty state as external review
context; do not sweep it into our commits, stash it, overwrite it, or copy a
whole home/source tree. No such composition worktree was created by this audit.

Apply the following order to that isolated descendant:

1. Preserve the desktop composition first: physical-login/recovery modules,
   exact TSX and bundled relative production dependencies, snapshot helper,
   Agency Web launchers, and their explicit public Python/helper imports.
   Current dirty dependencies include `modules/domicile-snapshot.nix`,
   `modules/agency-web-client.nix`, its launcher, `chat-window/*.py`,
   `chat-window/native_terminal`, and the three `agent-windows` client files.
   Review additions and removals individually. The old staged
   `home/dot_config/domicile/agency` tree is not imported by the current entry;
   it is not a reason to absorb that unrelated copy. The whole-directory
   `~/.local/bin` link must retain the owner's selected baseline dispatchers.
2. Merge our reviewed package/editor history through `48307add` (or its next
   explicit source-export successor), preserving the owner's desktop paths.
   Our paths otherwise do not overlap the dirty owner changes. Our three
   `flake.nix` hunks also match unique exact contexts in the inspected dirty
   owner text; this was checked in memory, without changing either checkout.
3. Update only the intended agent catalogue graph, as below. Do not replace
   `flake.lock` wholesale or run an unrelated full input update.
4. Retire the owner's 0.48-only Kitty Wayland backport overlay when selecting
   our qualified 0.50 recipe. Keep its patch and crash fixtures as history.
   The newer source already contains the fix, as verified below.
5. Select the explicit qualified Domicile Rust/SDK, official engine and Imagine
   production-source combination. Pin the maintained source immutably; stale
   path-input NARs do not select the newly qualified source. Preserve the
   owner's relative-dependency bundling, entry stamp, checked config, recovery
   paths and staged snapshot identity. A source pin alone does not select an
   engine, and placing binaries on disk does not replace the loaded engine.
6. Admit the NAS role before changing client launch routes. A package built on
   Strix is not automatically installed or on PATH on NAS. The default remote
   command is bare `agency-kitty`; make the reviewed matching NAS helper and
   holder available there first, or explicitly pin
   `AGENCY_KITTY_REMOTE_PROGRAM` to its already-present NAS-role executable.
   That override alone does not install the editor: `editor-local-attach`
   separately calls `dsh-editor`. Admit matching NAS terminfo/fish integration,
   `dsh-editor`, the full Neovim configuration and the new-shell
   `DSH_EDITOR_VI`/`DSH_EDITOR_ROLE` environment as one reviewed role. Preserve
   live Herdr, harness and existing editor processes; inspect activation deltas
   rather than assuming a whole NAS switch is harmless. Existing retained
   shells do not retroactively gain new session variables. Qualify fresh
   managed direct and retained shells separately, including primary `vi`.
7. Apply [client-entry.patch](client-entry.patch) only after checking the exact
   original entry hash in [its provenance](client-entry-provenance.json).
   It changes Mod+Enter, Mod+Ctrl+Shift+Enter and Mod+Shift+Enter through the
   public `ImagineOptions.keybindings` seam. It changes no Imagine Desktop,
   AgencyKeys, internal reducer, window class convention or other key.
8. If adopting the native chat catalogue too, compose its separately reviewed
   NAS catalogue companion and Imagine change, then set the existing public
   `sessionCatalogue.nativeTerminalLauncher` to the absolute installed helper.
   The original entry lacks that optional field. The separately optional
   [exact-entry template](NATIVE-CATALOGUE.md) supplies it without hard-coding a
   historical helper path. The combined rendered entry passed installed-SDK
   compilation, all three trusted chords and a real linked-row resume with
   every configured workspace occupied. Installing three launch chords alone
   does not enable that UI or infer a chat/workspace relationship.

The owner's deletion of its old `pkgs/dsh-plugins/kitty-native` directory does
not remove our new plugin: the reviewed integration's plugin map points to
`pkgs/agency-kitty/source/integration/dsh`. Preserve that exact map and the
explicit `native` profile; keep the headless profile free of the plugin.

## Preserve graph identity and base-system pins

The inspected owner lock's host `nixpkgs` is
`f36469d0b0e4633696a109f3867195c0464d1353`; integration's is
`dce1caf58d1a943af38b376e824a0d036ec3eea7`. These are source-tree facts, not
an attestation of the currently running client's Mesa/base closure. Establish
the intended client base from its actual profile and the desktop owner's
receipt before composing. Do not silently substitute canonical base packages.
Both trees use `nixpkgs-fresh` `3a32588c117116d2bf0edc33915981398fab2b00`.

Our bounded catalogue update changes these locked revisions:

- `llm-agents`: `9749aedff46456aa55451a7a01f103224af40451`.
- Its `flake-parts`: `ea2630b7470978622c7689a1ff75d2b389175399`.
- Its own `nixpkgs`: `6dadaf4375be35033e1c84395adbd53ff5fded96`.

Lock node names differ. Our graph calls the last two `flake-parts` and
`nixpkgs_4`; the dirty owner graph calls them `flake-parts_2` and `nixpkgs_5`.
Follow `nodes.llm-agents.inputs`, verify each prior locked identity, and update
only the corresponding `locked` objects, preserving their inputs/follows.
A read-only in-memory composition changed exactly those three owner nodes and
preserved its host nixpkgs, Domicile, Imagine and dsh-domicile nodes byte for
byte as JSON values. A literal canonical lock patch failed exact-context
application; copying nodes by their numeric suffix is not a safe merge method.
Changing Imagine/Domicile later in the sequence is a separate explicit update.

## The seat's Wayland crash fix is retained upstream

The dirty owner's `pkgs/kitty/wayland-output-leave.patch` identifies upstream
[commit 2dbe5df2](https://github.com/kovidgoyal/kitty/commit/2dbe5df2d8a7590213d76aa4ce112024602eb57d)
and backports it to 0.48. The exact cloned `v0.50.0` source is commit
`bb1aca6f279f1a5cfa3edd765a71650fe91b6472`, matching the release tag selected
by our source-hashed recipe. Its
[Wayland enter/leave implementation](https://github.com/kovidgoyal/kitty/blob/bb1aca6f279f1a5cfa3edd765a71650fe91b6472/glfw/wl_window.c#L582-L622)
already rejects a null removed output and null monitor, and removes only a
matching monitor through the bounded reverse loop. It cannot unconditionally
decrement an empty monitor array as the old code did. This source comparison
independently establishes the required behavior; the shallow clone did not
contain the older commit object, so no ancestry claim is made from that clone.

Remove that old backport's *overlay application* in the isolated composition.
Leaving the outer overlay in place feeds the old patch into the later 0.50
recipe's inherited `old.patches`, even if an earlier overlay still reports
0.48. A condition on only that earlier package version does not fix the
inheritance. Our 0.50 source retains the actual guard without reapplying the
0.48 patch. Retain its historical evidence files; this is not an evidence purge.

## Gates before client adoption

The [actual key proof](../../docs/IMAGINE-CLIENT-KEYS-PROOF.md) passed the exact
patched entry through the installed builder and real engine shortcut route.
It used full Imagine source `8954bbe22e7bad338206322576838f6c20b2043a`, compiled
production bundle SHA256
`191547be9ec4c56a2108c4d82eda5b2f99a501492e0727e9db980cd5f5db1f37`, the
source-built native-drag-aware Domicile CLI/compositor/helper, and official
engine `63db244`. Its loaded engine library SHA256 is
`43f0dc75132f7ab3ae7042a75d7c19b88e89a9e10a4850a656a06bcda623c02f`.
The receipt records all Rust hashes separately. The original startup exports
were present but intentionally inactive in the private shell-only fixture.
This is functional evidence, not a qualified composed client NixOS closure or
a physical PAM/login/monitor transition.

Before adoption, evaluate the isolated complete client configuration and build
on compute only, with a fresh free-space check of at least 25 GiB. Review the
whole closure delta against the actual current client profile. Assert Domicile
greetd/recovery ownership, unchanged intended kernel/Mesa/base inputs, checked
TSX and companion source links, exact CLI/SDK/engine source identity, helper and
Kitty package identity, NAS terminfo/fish assets, native profile isolation,
client credential exclusion and preserved baseline/rescue routes. Repeat the
private exact-entry keys, native catalogue resume/identity, editor and graphics
gates against those composed package paths, under `runtime-test` on each host.

Use the desktop owner's established physical adoption route. An engine change
requires a genuine PAM/logind session transition, recovery aligned with the
new pair, and actual loaded-library/CLI/SDK attestation after the old engine,
escaped scopes and listeners have gone. Preserve live work until that deliberate
transition; do not restart greetd, Herdr or the user manager to simulate it.
A source-only watched-link refresh still requires its own semantic refresh and
native/guest retention checks. Neither transition was performed by this audit.
