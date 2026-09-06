# The `herdr-kitten` input: what it pins, how it is fetched, and what checks it

Written for U-D15 (`mecattaf/dotfiles#318`). It records the state of the
`herdr-kitten` flake input after the round-2 re-pin — both halves of it, the rev
and the URL form — the measurement that admitted the `github:` fetcher, and the
one thing that is still not this repository's to do.

## What the input is

`herdr-kitten` is the repo where herdr IS the kitty kitten: one stdlib-Python
kitten (four gestures on kitty's GUI thread) plus the `hk` CLI. It is consumed
as an input and never vendored (ruling B3), and only through
`packages.<sys>.herdr-kitten` — no overlay of its own reaches this repo's `pkgs`
fixpoint (F.3). It is deliberately out of `rollingInputOverrides` (F.4) for the
same reason `herdr` is: it fronts live PTYs, so its version moves when Tom says
so and never on a nightly resolve.

`home/herdr.nix` is the whole consumption:

- `home.packages` gets the package on **every** interactive host, so `hk` is on
  PATH beside the `herdr` client. The niri terminal binds, the kitty gestures
  and the dictation route all shell out to it.
- `xdg.configFile."kitty-herdr-nix.conf"` emits one `action_alias` carrying the
  **store path** of the kitten's entry point, because kitty resolves a bare
  `kitten foo.py` against `~/.config/kitty` — which here is a whole-dir
  out-of-store symlink into the git tree, so no generated file can nest inside
  it. `kitty.conf` then spends the alias as `map <chord> hk <gesture>`, and the
  chords stay re-cuttable without a rebuild.

The topology is untouched by any of this and is not this document's to move:
**one** herdr server, on the coordinator (ruling B5). `#309` is the open TOM
LINE on that question, and `DEFERRED.md` DF-U-D15-2 is the row.

## What the pin is

    url = "github:mecattaf/herdr-kitten/ccc16393cc35e2cce2b8cd9a55718b3c84849a8f";

**The rev.** `ccc1639` is the merged head of `mecattaf/herdr-kitten` `main` past
the round-2 merges — U-C2…U-C5 (`97e4b9c`, `5e857f0`, `ccc1639`) and
herdr-kitten #26's `homeManagerModules.default`.

The rev it replaced, `41a6de5`, predates all of them. `RULING-kitten.md` §0
rules that tree **"must not ship"**: it is the pre-round2 install layout, so a
switch on it installs a kitten kitty's loader cannot load, and the failure lands
inside kitty with nothing in this repo going red. That is the hazard the bump
removes, and it is the reason the checks below exist.

**The URL form.** `github:` — the URL the repo's own README documents, and the
shape the `tally` input already uses for exactly the stated reason: *"fleet
auto-upgrades need no GitHub credential helper or access token."* What it
replaces, `git+file:///home/tom/mecattaf/herdr-kitten`, resolved **only on the
coordinator**; every other box in the fleet failed to evaluate this flake at
all. Pinned **by rev**, never by branch, for the F.4 reason above.

That form is admissible because its one precondition — fetchable without a
credential — is measured present, not assumed. MEASURED 2026-09-06 on the
coordinator:

| measurement | result |
|---|---|
| `gh repo view mecattaf/herdr-kitten --json isPrivate,visibility` | `{"isPrivate":false,"visibility":"PUBLIC"}` |
| `nix flake metadata github:mecattaf/herdr-kitten/ccc16393cc35e2cce2b8cd9a55718b3c84849a8f` | resolves and unpacks; narHash `sha256-X5b1Fi6ObCI5xHPpEXTL8k1FbWO5JZeBnqMYAfG6jVU=` |
| the narHash the local checkout had locked | `sha256-X5b1Fi6ObCI5xHPpEXTL8k1FbWO5JZeBnqMYAfG6jVU=` — identical |

The two narHashes matching is the point: the fetcher changed and **the object
did not**. The herdr-kitten survey's **Q-7** (*"the repo is PRIVATE by standing
wall. No executor flips visibility."*) is honoured rather than overridden — it
bars an executor from flipping visibility, and no executor did; the repo was
already public when this was measured. See `DECISIONS.md`, the 2026-09-06 U-D15
entry, for why the form was taken rather than deferred.

The lock node changed shape with it: `"type": "git"` + `"url":
"file:///home/tom/mecattaf/herdr-kitten"` is now a `github` node with
`owner`/`repo`/`rev`. Nothing else in the input block moved —
`inputs.nixpkgs.follows` and `inputs.herdr.follows` are exactly as they were, so
one herdr and one nixpkgs still serve the whole closure, and the `herdr` input
itself did not move: herdr owns live PTYs and its version is Tom's.

## What checks it

`nix flake check` carries two, both eval-time except where noted.

- `checks.<sys>.home-profiles` — `hk` is in the coordinator's `home.packages`
  **and** the worker's (one server, two clients), and the generated
  `kitty-herdr-nix.conf` names a `/nix/store` path ending in the kitten's entry
  point. Drop `herdr-kitten` from `home.packages` and the check fails by
  assertion, named.
- `checks.<sys>.herdr-kitten-input` — the `action_alias` line is parsed back out
  of the coordinator's own generation, asserted to be a path *under this input's
  own package*, and then, under a full `nix flake check` (no `--no-build`), the
  file is **read in the store** along with `bin/hk`. `--offline --no-build`
  reduces this to the eval half.

## The oracle

U-D15's DOMINANT, mechanized as one argv:

```sh
bash tests/herdr/test-herdr-kitten-input.sh
```

It prints every clause with its measured value and exits non-zero on the first
red one:

| clause | what it measures | value |
|---|---|---|
| A0 | `nix flake lock --update-input herdr-kitten` (falls back to `--offline`) | rc 0, and `flake.lock` **unchanged** — re-applying reports zero changes. Restored again on exit, because clause A rewrites the lock a second time when `flake.nix` and the lock disagree (measured under the mutation) |
| A | `nix flake check --offline --no-build` | rc 0 |
| B | `grep -c 'git+file' flake.lock` | 0 |
| B2 | `grep -c 'git+file' flake.nix` | 0 |
| B3 | `grep -c 'file:///home/tom'` over `flake.lock` / `flake.nix` | 0 / 0 |
| B4 | the URL is `github:mecattaf/herdr-kitten/<40 hex>`, and the lock node agrees (`type github`, `owner`/`repo`/`rev`) | both |
| C | `hk` in the coordinator's `home.packages` | `["herdr-kitten"]` |
| C2 | `hk` in the worker's too, and the `action_alias` store path | both |

**Why B is not the clause that goes red.** The card's mutation hint is
*"reintroduce the file:// URL → the grep count is 1"*. Executed literally —
`flake.nix` back to `git+file:///home/tom/mecattaf/herdr-kitten?rev=…`, then
`nix flake lock --update-input herdr-kitten` — the measured counts are
`flake.nix` **1** (the card's "1"), `file:///home/tom` in `flake.lock` **2**,
and `git+file` in `flake.lock` **0**: Nix never spells a local git tree
`git+file` *in the lock*, it writes `"type": "git"` plus a bare `file://` URL.
So clause B reads 0 on both sides of the fault and cannot see it. B2/B3/B4 are
where the mutation lands, whichever of the two files it is reintroduced in, and
they are part of the acceptance for that reason rather than as tidiness.

## What is still not done here

Declaring an input is not installing it. Neither box runs this pin until a
`nixos-rebuild switch`, which this unit does not perform: the coordinator's
switch is U-D19's own unit and the worker's is a TOM LINE (`D-B15`). Tracked as
`DEFERRED.md` **DF-U-D15-1**, discharged when `readlink -f "$(command -v hk)"`
on each box resolves under the same store path clause C2 prints. MEASURED
2026-09-06 on the coordinator it does not: `hk` resolves under
`/nix/store/caj91n9…-herdr-kitten-0.1.0-dev`, the running generation, while this
lock's package is `/nix/store/wjbbi7n…-herdr-kitten-0.1.0-dev`.
