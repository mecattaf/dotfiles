# Upgrade the idle floor while other Masters stay live

Several dshd instances can share the native `master` profile. Its package
directories are ordinary hoisted directories, and DSH watches profile patches
live. Do not install into that profile or rewrite its patch while another
instance uses it. `dsh-master render` defers changed active profiles; the install
guard remains in force.

`dsh-master runtime snapshot` is an explicit packaging step in the existing
Master CLI. It copies an already installed graph and generates one floor
overlay. It never installs packages, builds, edits a profile, or starts/stops a
process.

```sh
DSH_HOME="$HOME/.dsh" dsh-master runtime snapshot \
  --from /absolute/path/to/new-dsh-master-build \
  --installed-profile /absolute/path/to/checked/dsh/profiles/master-groq
```

The installed source's package digest and both pnpm lockfiles must match the
new manifest. Use a profile that already passed install/check and useful worker
qualification. The source graph must contain the complete built v7 backend.
The output is JSON containing `generation`, `contentHash`, `overlay`, `pins`,
`storeRoots`, and whether an identical generation was reused.

Snapshots live at `$DSH_HOME/master-runtimes/<sha256>`. Regular files are copied
into distinct inodes; no hardlinks remain to the source. Internal symlinks are
made relative, mutable external links are refused, and immutable external links
are canonicalized to verified local Nix store paths. VCS files, caches and local
environment/configuration files are omitted. The complete backend `lib` tree,
ordinary installed dependencies, package/lock files, source manifest and
provenance remain in the generation. Ordinary dependencies and native backend
peers must resolve within the graph or the exact native DSH installation.

Available DSH peers link to that installation so Cordis/service identities stay
the same. Browser peers belong to DSH's client graph and need not exist as Node
packages. Bundled SDKs can declare additional type peers absent from the already
qualified installation; `snapshot.json` records these as
`unprovidedDeclaredPeers`. No replacement dependencies are downloaded.

Before publication, `nix-store --check-validity` checks every referenced store
root. The helper retains those already valid paths using indirect GC roots in
`master-runtimes/.nix-gcroots/`; substitution and all builders are disabled for
this operation. Package bytes and metadata determine the hash. Publication is
an atomic directory rename followed by a read-only generation. Repeating the
command verifies the existing bytes before reusing them. Concurrent runs cannot
replace a published generation.

The overlay disables the old `dsh-superagent`, `dsh-superagent-scheduled` and
`dsh-superagent-workflow` rows, then inserts their three replacements by absolute
module path. Each replacement takes the corresponding enabled configuration
from the new manifest, including the persistent main state directory and exact
provider/model/effort pairs. DSH's `name` field on an existing row is an
assertion, so changing a module requires disabling the old row and inserting a
new ID. Existing bundle declarations, presets and client assets remain intact.

Only after the isolated smoke passes, the operator captures the idle floor's
recipe/environment, release, labels, enablement, persistent Store/main Session,
and confirms zero active workers. dshd recipes are immutable: adding this patch
requires stopping/removing/recreating **the same `floor` name**, with the
snapshotted overlay passed to `dshd run --patch FILE` before `--`. Restore its
original cwd/release/labels/enablement and use native `master`. Do not recreate
an academic instance. The helper deliberately performs none of these lifecycle
steps. The original Master graph and patch remain available for rollback.

There is no automatic pruning. Retired generations and their GC roots may be
removed explicitly once no instance recipe or running process references them.

## Qualification

The ordinary Nix `dsh-master` check includes eight packaging tests: independent
copied bytes, read-only publication/reuse, correct overlay configurations,
missing dependency/backend/lock rejection, mutable external link rejection,
concurrent publication, and tampered or writable generation rejection.

The opt-in native smoke uses actual old and v7 packages, two concurrent native
Master processes on one private profile, the actual web Runtime/API, and an
in-process trap model. It copies the old package graph into that private profile
and loads v7 through the generated overlay. The main Store/inbox/session root
are private; Claude and network provider adapters are disabled. It sends no
task, checks the actual scheduled/workflow registration, sets eval off and
pause, reads the native state/settings/models endpoints, validates all manifest
pairs, imports the workflow module later, and checks zero prompt calls
and unchanged old profile/package bytes.

Run on compute after staging the nonsecret graphs/build/tests there:

```sh
runtime-test -- node --expose-internals tests/dsh-master/runtime-smoke.mjs \
  /absolute/new-dsh-master-build /absolute/frozen-generation \
  /absolute/old-node_modules /absolute/new-private-proof-directory
```

`DSH_SMOKE_INSTALL` can name the exact installed native DSH package directory
when the staged build's NAS release alias does not exist on compute. Keep the
same Nix store installation/peer identities. The proof writes a bounded
`result.json` and redacts temporary web token URLs from diagnostics. It is not
a production floor replacement.
