# Reviewable native client composition

This isolated candidate preserves the current Domicile desktop composition and
adds native Kitty transport, the primary local Neovim UI, and the public native
catalogue launcher. It changes no live client or NAS generation. A complete
Nix evaluation is separate from realizing and qualifying its Domicile package.

The worktree is `/home/tom/.wt/kitty-consolidation/client-composition`, branch
`feat/client-composition-20261108`. It starts at canonical `e629eeda`, merges
owner `87491201`, and copies 37 named reviewed owner dependencies unchanged.
The named copy manifest and source/entry chain are under the task's
`artifacts/client-composition`. The unused staged `home/dot_config/domicile/agency`
shell is excluded. The owner worktree, Imagine Desktop/AgencyKeys, and their
Nix internals remain unchanged.

## Sources and package identities

Resolve host inputs from `nodes.root.inputs`, not numeric lock-node names.
Both original trees and this composition select root nixpkgs
`e2587caef70cea85dd97d7daab492899902dbf5d`. The literal node named `nixpkgs`
in each lock belongs to another input graph. The copied owner graph retains
its follows; only the reviewed llm-agents/catalogue dependency nodes and the
explicit desktop-source inputs change.

The client kernel derivation is `/nix/store/wjng0666yjjchqkf4dhhksaahhmr0dzz-linux-7.3`
and Mesa is `/nix/store/phi22s7027ilx17453zjxskja9slvbd4-mesa-26.1.5`.
These exactly match the current client profile. The booted kernel remains
7.2.10; this work requests no reboot.

Domicile is pinned to the clean reviewed native-drag snapshot
`ec4852dc02c6da2376dc6a81bea845980db47669`, based on upstream `75708d7`.
Imagine is the clean qualified snapshot
`8954bbe22e7bad338206322576838f6c20b2043a`. Immutable local Git inputs retain
honest revision metadata without changing either source repository. The
compute evaluation uses explicit shallow mirrors at those same private input
paths. This is a local-source construction boundary, not publication or a
promise that a different builder can find those paths. Its locked Git/NAR
identities must be provided before evaluating elsewhere; target machines need
only the realized closure. The small read-only dsh-domicile helper is a named
relative source snapshot, not the owner's mutable external path.

Kitty is the already qualified rs4 0.50.0 package. The old 0.48 Wayland
output-leave overlay is not reapplied: 0.50 contains the guarded removal
implementation. Its original patch/crash evidence is preserved in the owner.
The exact final role helpers remain the previously built ph974 seat/l4xq NAS
packages, with their matching final source-built holder and role-specific Kitty
assets. Primary `vi` remains enabled for seat and brain.

The engine selection is the published official `63db244` series. Its existing
PROVENANCE states `is_official_build = true` and `dcheck_always_on = false`.
The engine library SHA-256 is
`43f0dc75132f7ab3ae7042a75d7c19b88e89a9e10a4850a656a06bcda623c02f`;
its Chromium executable SHA-256 is
`2ff2309ac1235b215393b25572ba95b49a531258416bc6f75c9228c91c391a27`.
Candidate input agreement and an existing engine file are not loaded-runtime
attestation of the new Rust/SDK package. The complete source admission receipt
records which paths exist and which remain unrealized.

## Public entry and workflow

The captured owner entry remains 6,250 bytes with SHA-256
`b6cf824a58a96efe6ec8f7d4d674e9a2cf9dff771524a81e4ef96033c0ad4fb9`.
The exact first patch produces `61d03122`; the optional public native catalogue
patch produces template `216de886`. New `modules/agency-kitty-client.nix`
renders its one helper placeholder using the selected seat derivation and
passes the result through the unchanged public
`programs.domicilePhysical.configSource` pipeline. That pipeline checks the
entry and bundles/stamps all Imagine production dependencies.

Mod+Enter selects managed ordinary SSH without a holder. The session menu can
create or resume an explicit retained UUID. Mod+Shift+Enter remains local
rescue. Existing baseline startup commands/dispatchers remain available.
The native catalogue field creates no chat/workspace links: those remain
explicit `open --chat-id` or `link` assignments. It does not change the global
workspace inventory or install a DSH Host/provider on the client.

## NAS admission without automatic service replacement

`tests/client-composition/nas-admission.nix` defines a separate Home Manager
admission package and a structured read-only admission value. It supplies the
matching NAS helper, full generated Neovim/plugin configuration and fresh-shell
primary-vi environment. It also freezes the reviewed catalogue producer's
complete Python import graph, applies the existing native metadata patch, and
renders its fixed helper path. Only two catalogue entry links are managed;
the existing release directories are retained.

This admission forces Home Manager's public `systemd.user.startServices` option
to `suggest`. Inspection of the pinned Home Manager source shows that this
mode reloads user unit definitions and prints suggested lifecycle commands;
it does not start, stop or restart those units. Herdr additionally retains
`X-SwitchMethod=keep-old`. Do not run any printed restart suggestion as part of
this workflow admission. This is a candidate source plan, not an activation
receipt or authorization to deploy NAS.

Before a later authorized activation, review the complete generated activation
script and preserve existing unmanaged catalogue links using Home Manager's
explicit backup mechanism. Do not force-overwrite files or replace the whole
`.local/lib/agency-chat-window` directory. Existing retained NAS shells do not
gain new environment variables retroactively. Qualify fresh managed direct
and retained shells separately after admission, including their primary `vi`.

Current NAS inspection finds raw `dsh-editor` scripts already available through
the canonical checkout, but no `agency-kitty` executable on PATH and neither
final role helper present in the NAS store. Pinning a helper path that exists
only on Strix does not fix that. Copying/admitting the NAS closure and the full
editor/configuration payload must precede changing client routes. The
catalogue companion is a separate required payload for the optional native UI.

## Qualification and next action

The first bounded compute evaluation passes all effective client and NAS
assertions: primary vi, exact root base/kernel/Mesa, final role helpers,
Domicile/Imagine pins, manual Sway fallback, client greetd
`restartIfChanged=false`, and NAS Herdr keep-old. No build, activation, model
request, desktop restart or live synthetic input was performed.

The complete composition still needs realization and private exact-package
entry/catalogue/editor/graphics qualification. The newly derived Domicile
Rust/SDK path is not the live d0pn package and is not admitted merely by the
older manual binaries' proofs. Before every build, enforce the normal fresh
25 GiB root-space guard on Strix. The current guard is below threshold; no
build was attempted. Do not substitute the earlier canonical Sway closure for
this candidate.

After that qualification, review the whole activation delta. A future live
engine/SDK change follows the owner's deliberate physical PAM/logind
transition and loaded-library attestation. Keep the current desktop and all
NAS sessions running until that separately authorized transition.
