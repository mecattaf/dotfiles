`client-native-catalogue.patch.in` is a second, separately optional adoption
artifact. Applied after `client-entry.patch`, it adds only the existing public
`sessionCatalogue.nativeTerminalLauncher` field. It preserves the existing
relay, server and legacy `terminalLauncher`; it adds no Desktop, AgencyKeys,
Nix module, engine or window-reducer change.

The input must match the first patch's exact result:
`61d031227c1e7f731f72046a148f224a20be2ed4b57a01b6c8a3426a5bd9d72d`.
The template patch hash is
`cf6ec9aff6a4d14609baca86a2b4f573136ff869e41e71558667007138484c05`.
Its single `@AGENCY_KITTY_COMMAND@` placeholder must be rendered to the chosen
installed **seat** package's absolute `bin/agency-kitty` path before applying
and compiling. An unresolved placeholder is intentionally not valid runtime
configuration. No historical store path is embedded in this asset.

Render in the existing owner-reviewed composition, using its selected package
derivation, rather than whichever helper happens to be on PATH. For example,
inside that composition's existing Nix build phase:

```sh
substitute "$template_patch" "$rendered_patch" \
  --replace-fail '@AGENCY_KITTY_COMMAND@' "${agencyKittyPackage}/bin/agency-kitty"
```

Here `agencyKittyPackage` is the selected seat derivation in that composition;
the template and output patch paths are private build inputs/outputs. Check
the exact input entry SHA before application, then run `git apply --check` and
`git apply` with the rendered patch in an isolated copy. The patch has the same
`home/dot_config/domicile/domicile.tsx` path as the first artifact. Feed that
reviewed copy through the existing public `programs.domicilePhysical.configSource`
pipeline and its builder/check-config gates. This document changes no owner
checkout or composition. If the captured dirty entry drifted, regenerate the
artifact against its new reviewed bytes instead of relying on patch context.

The fixed helper receives only Imagine's typed `desktop-resume-request` payload.
Native rows exist through explicit NAS session/chat links, for example the
existing `open --chat-id` or `link UUID --chat-id` actions. This field creates no
links, guesses no current chat and changes none of the three chord defaults.
It does not make terminal screen/input authority available to a DSH tool.

Placement remains Imagine's existing policy: use the chat viewer's workspace
when present, otherwise an available empty chat slot, otherwise the current
workspace, including an occupied one. The optional patch does not alter that
policy or the fixed global ten-workspace inventory. Saved native PTYs remain
separate catalogue entries.

The combined private qualification is retained at
[`docs/evidence/native-imagine-public-catalogue/receipt.json`](../../docs/evidence/native-imagine-public-catalogue/receipt.json).
It renders this template to the exact installed seat helper, compiles the
resulting real entry through the installed SDK/full Imagine bundle, exercises
all three engine chords, fills the ten configured workspaces, and clicks one
actual explicitly linked native row through trusted pointer routing. The exact
NAS fish PID/start survives, the new native window joins the current occupied
workspace, existing windows stay put and no holder is allocated. The actual
helper receipt completes; no fixture launcher wrapper supplies that field.

This is entry/configuration qualification, not a full client deployment. The
original startup exports are present but unactivated in the private shell-only
fixture. No live client, baseline startup command or legacy desktop entry was
changed. The proof uses private runtime/network/home state and no real provider
or credential request. Source/rendered/compiled hashes are recorded separately
because the rendered entry correctly depends on the selected package path.
