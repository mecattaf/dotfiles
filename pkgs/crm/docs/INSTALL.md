# Install and graduate `crm`

This repository proves the package that will move into the owner's dotfiles.
It does not perform that move and does not install or modify CRM data.

## Verify the package

From the repository root:

```console
nix build .#crm
test "$(./result/bin/crm --version)" = "$(nix eval --raw .#crm.version)"
```

The derivation builds one static, CGO-disabled binary. Its install check runs
`crm --version` and requires the output to equal the derivation's version
exactly.

## Graduate it into dotfiles

Keep the tracked source tree together under `pkgs/crm/`, including
`nix/package.nix`; that preserves the package's `../.` source path. Wire it
into the dotfiles package set with:

```nix
crm = final.callPackage ../pkgs/crm/nix/package.nix { };
```

Then add `crm` to the user's `home.packages`. The dotfiles flake supplies
`nixpkgs`, so the repository's standalone `flake.nix` is only the local proof
harness and does not need to be imported into the distribution flake.

Install the agent skill by keeping the entire `skills/crm/` directory at
`~/.agents/skills/crm/`. In the owner's dotfiles, the canonical source is
`home/dot_claude/skills/crm/`; Home Manager exposes that same skill tree at
both `~/.agents/skills/` and `~/.claude/skills/`. Keep `SKILL.md`, `flags.md`,
and `agents/openai.yaml` together.

## Configure the data path and hook

Without configuration, `crm` uses
`~/mecattaf/notes/crm/crm.db`. To select another database, set `CRM_DB` before
running any command:

```sh
export CRM_DB="$HOME/path/to/crm/crm.db"
```

The optional `CRM_POST_WRITE_HOOK` value is a shell command. After each
successful mutation, `crm` starts that command with a JSON post-write payload
on stdin. Hook stderr passes through, the hook has a 30-second timeout, and
its result never changes the CRM command's result. Read commands do not run
the hook. Set it only to a command already installed in the user's
environment:

```sh
export CRM_POST_WRITE_HOOK='<installed shell command>'
```

The same values can be declared with Home Manager's
`home.sessionVariables` instead of shell exports.

## Bootstrap the database

After the binary and environment are in place, initialize the resolved data
path once:

```console
crm init
crm status
```

`crm init` is idempotent. It creates the database, the current year's
`transcripts/YYYY/` directory, and the orientation `README.md` beside the
database. The binary never runs git; repository automation belongs in the
optional post-write hook.
