# The `herdr-kitten` input: what it pins, and the one thing that is not ours

Written for U-D15 (`mecattaf/dotfiles#318`). It records the state of the
`herdr-kitten` flake input after the round-2 re-pin, the measurement behind the
URL form it still carries, and the exact edit that finishes the job the day
that measurement changes.

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
LINE on that question.

## What the pin is

    url = "git+file:///home/tom/mecattaf/herdr-kitten?rev=ccc16393cc35e2cce2b8cd9a55718b3c84849a8f";

`ccc1639` is the merged head of `mecattaf/herdr-kitten` `main` past the round-2
merges — U-C2…U-C5 (`97e4b9c`, `5e857f0`, `ccc1639`) and herdr-kitten #26's
`homeManagerModules.default`.

The rev it replaced, `41a6de5`, predates all of them. `RULING-kitten.md` §0
rules that tree **"must not ship"**: it is the pre-round2 install layout, so a
switch on it installs a kitten kitty's loader cannot load, and the failure lands
inside kitty with nothing in this repo going red. That is the hazard the bump
removes, and it is the reason the two checks below exist.

## What checks it

`nix flake check` carries two of them; both are eval-time except where noted.

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

## The one thing that is not ours: the URL form

The end state for the URL is `github:mecattaf/herdr-kitten/<rev>` — the URL the
repo's own README documents, and the shape the `tally` input already uses for
exactly the stated reason: *"fleet auto-upgrades need no GitHub credential
helper or access token."* A `git+file://` URL resolves **only on this box**, so
the fleet cannot evaluate this flake from anywhere else.

That flip is not taken here, and it is not an executor's to take. Fetchability
is a precondition, and neither of its two paths holds. MEASURED 2026-09-06 on
the coordinator:

| path | measurement | verdict |
|---|---|---|
| the repo made public | `nix flake metadata github:mecattaf/herdr-kitten/ccc16393cc35e2cce2b8cd9a55718b3c84849a8f` → `HTTP error 404`; `gh repo view mecattaf/herdr-kitten --json isPrivate` → `{"isPrivate":true,"visibility":"PRIVATE"}` | **barred.** The public flip is the herdr-kitten survey's **Q-7**: *"The repo is PRIVATE by standing wall. No executor flips visibility."* Tom's line. |
| a credential path the fleet's other boxes actually have | `/etc/nix/nix.conf` carries no `access-tokens` line; `~/.config/nix/nix.conf` does not exist; `/etc/nix/netrc` and `~/.netrc` do not exist; `ssh -T git@github.com` → `Permission denied (publickey)`; `secrets.nix:166-168` makes `gh-hosts.age` and `wrangler-config.age` `coordinatorOnly` under Tom's ruling *"the coordinator is the fleet's only authenticated operator box — gh + wrangler stay off the laptops"* | **absent.** The fleet SSH user key is a fleet-mutual key, not a GitHub credential, and the one GitHub credential on the estate is a `gh` CLI hosts file the other boxes cannot decrypt. |

There is no third path, and inventing one is out of scope by the issue's own
words. So the URL form stays local and only the rev moved.

## Finishing it, the day Q-7 lands

Two commands, in this order, from a clean worktree:

```sh
sed -i 's|url = "git+file:///home/tom/mecattaf/herdr-kitten?rev=\(.*\)";|url = "github:mecattaf/herdr-kitten/\1";|' flake.nix
nix flake lock --update-input herdr-kitten
```

Then the acceptance, which is U-D15's DOMINANT in full:

```sh
nix flake check --offline --no-build          # 0
grep -c 'git+file' flake.lock                 # 0
grep -c 'git+file' flake.nix                  # 0  (1 until the flip)
grep -c 'file:///home/tom' flake.lock         # 0  (2 until the flip)
nix eval --offline --json \
  .#nixosConfigurations.coordinator.config.home-manager.users.tom.home.packages \
  --apply 'ps: builtins.filter (n: n == "herdr-kitten") (map (p: (builtins.parseDrvName (p.name or "")).name) ps)'
                                              # ["herdr-kitten"]
```

The lock node changes shape at the same time: `"type": "git"` + `"url":
"file:///home/tom/mecattaf/herdr-kitten"` becomes a `github` node with
`owner`/`repo`. Nothing else in the input block moves — `inputs.nixpkgs.follows`
and `inputs.herdr.follows` stay exactly as they are, so one herdr and one
nixpkgs still serve the whole closure, and the `herdr` input itself does not
move: herdr owns live PTYs and its version is Tom's.

The deferral is tracked as **D-1** in `DEFERRED.md`.
