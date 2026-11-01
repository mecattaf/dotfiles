# Mnemon on the NAS agent host

Issue: [#676](https://github.com/mecattaf/dotfiles/issues/676).

`mnemon` is the pinned native Go/SQLite CLI (v0.2.13). `dsh mnemon` is a
separate hand-run profile using the pinned dsh-mnemon bundle (v0.5.38) and
Gufo's `qwen3.8-flash-next` route. The existing `headless` and `herdr` profiles
do not load Mnemon. Nothing installs hooks into Claude or Codex.

The native CLI stores facts, links and recall indexes; the DSH plugin adds
runtime memory, managed project documents and memory-space tools. The host
model makes the judgment calls. Neither component needs another model server
to provide lexical/graph recall. Embeddings are disabled: Gufo has no
embedding API. This setup does not configure D3-Ultra as a Mnemon judge.

## Nix ownership

`home/dsh.nix` exposes `programs.dsh.plugins`, an explicit selected-plugin
table. The defaults are:

```nix
programs.dsh.plugins = {
  herdr = [ "stderr-log" "herdr-guard" "dsh-herdr" "jevcore" ];
  mnemon = [ "stderr-log" "mnemon" ];
};
```

As with Neovim, Nix pins and delivers each package. The DSH wrapper renders
the selected bundle manifest and links the packages from the store when the
profile boots. It removes obsolete store links and leaves DSH's writable
profile settings alone. Add later utilities to `pkgs/dsh-plugins`, then
select them here; no runtime npm/pnpm install is needed. `dsh plugin` stays
disabled. The Mnemon native provider uses an absolute store path.

Activation downloads nothing and initializes no database. Native memory,
documents and plugin state live under `~/.mnemon`, or `MNEMON_DATA_DIR` when
explicitly supplied. Keep these files on NAS with the harness and its
credentials. The compute host only serves Gufo inference.

## Manual and overnight work

From the project directory, initialize a separate batch store once:

```sh
export MNEMON_DATA_DIR="$HOME/.local/share/mnemon/overnight"
export MNEMON_STORE=overnight
mnemon store create overnight
mnemon --store overnight status
dsh mnemon 'Work on the requested project task. Use Mnemon only for facts and documents relevant to this task, cite the original sources, and report the write receipts.'
```

Use the same environment to inspect that store later:

```sh
mnemon --readonly recall 'search words' --basic
mnemon --readonly recall 'why was this decision made?'
```

The first command uses literal keyword matching; the second uses Mnemon's
intent/graph ranking without embeddings. DSH's document tools can create a
managed Markdown document, retain workspace-relative `sourcePaths`, and
search/read it on demand. Original source files remain the authority.

The profile allows intended memory tool writes while idle review, automatic
capture, skill creation/editing/backtests and Git sync remain off. A long
foreground DSH run can stay in a Herdr pane on NAS. There is no timer or new
scheduler. Automated overnight dispatch still depends on a working Substrate
NAS executor; installing this package does not establish that executor.

Do not run `mnemon setup`, `mnemon update`, or a plugin installer. Setup
would imperatively alter other harnesses; updates belong to the Nix pins.
QMD is being removed separately in #672. It was unused; there is no QMD
ingestion, corpus import or index migration in this work.

## Validation and activation

`checks.dsh-mnemon` covers native store isolation, remember/recall and rejected
read-only writes; a synthetic document's creation/search/provenance; the DSH
profile composition; selection/removal of store links without deleting data;
a plugin boot that stops before inference; and an actual DSH turn against a
loopback mock OpenAI server, checking that memory tools reach the request.
The package's check phase runs upstream deterministic store,
search, graph and import-draft tests. No live credentials or user memory
are used.

Builds and runtime-isolated smoke checks ran on strix-coordinator. A passing
build is installation readiness, not NAS activation or a successful Gufo
turn. Normal reviewed fleet deployment installs the binaries; no Herdr or
user-manager restart is needed for this profile.
