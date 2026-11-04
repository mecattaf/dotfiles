# Reproducible assembled candidate

`build.nix` consumes two exact Git commits and the finished checked native
engine tarball. Before evaluation, `build.py` verifies its SHA256 and embedded
PROVENANCE against upstream's series identity script from both exact source
commits. The native package also requires the per-panel white-point ABI symbol.
It builds the Domicile binaries and shell from that source,
packages the tarball with upstream's Nix runtime dependencies, and replaces the
package's default engine link. The client module receives this matched package
and the two native input switches. Only this recipe selects the native display profile: it appends the reviewed
`native-output.ts` export to the regular starter source and builds one standalone
checked TSX. The normal locked dotfiles build retains its compatible config and
is not a claim that native panel warmth/input are ready.

The ordinary Sway greetd command remains the
base; Domicile remains a trial specialisation. Source paths are command inputs,
not committed machine defaults. The helper does not activate either system.

Run `build.py` on Strix through `fleet-exec` from NAS. Supply full source hashes,
actual tarball SHA256 and an unused evidence output directory. It first checks
input identities and evaluates all NixOS assertions. Immediately before the one
system build it records `df -h /` and refuses less than 25 GiB free. Its `system`
link is a Nix GC root. Exact source inputs, commands, metadata, build log and
success/failure receipt remain in the output directory. `--evaluate-only`
produces an evaluation receipt with `built:false`; it is never a build proof.

```sh
fleet-exec strix-coordinator --cwd /absolute/integrated-dotfiles -- \
  python3 tests/domicile-candidate/build.py \
  --dotfiles-checkout /absolute/integrated-dotfiles \
  --dotfiles-revision FULL_DOTFILES_COMMIT \
  --domicile-checkout /absolute/combined-domicile \
  --domicile-revision FULL_DOMICILE_COMMIT \
  --engine-tarball /absolute/finished.tar.zst \
  --engine-sha256 ACTUAL_TARBALL_SHA256 \
  --out /absolute/new-candidate-evidence
```

Final handoff supplies the concrete invocation and immutable outputs. The
source commits must be available in the named local repositories; preserve the
reviewed Git bundles and native artifact beside the receipts for resumption.
No release pin or upstream hash is replaced by a speculative one. Native
headless practice does not prove DRM input policy, panel ramps or physical
login. Actual activation and the physical check use the separately prepared
known-booted-kernel rescue entry; a newer-kernel base is not itself proof of a
working fallback.
