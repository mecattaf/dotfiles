# fish layer

This folder is the fish configuration of every host. `home/home.nix` links it whole, out of store, as `~/.config/fish` (the `configDirs` list, REPORTED). The 2026-10-22 consolidation (branch `dryrun/shell-consolidation-2026-10-22`) split the old `config.fish` by concern. No line of behaviour changed: every moved line is byte identical, and the only new lines are comments, three interactive guards and one `##` doc line in `remote.fish`.

## Load order

Fish reads `conf.d/*.fish` in name order first, then `config.fish` last. It does so for non interactive shells too (ssh commands, scripts), which is why every new fragment repeats the guard of the 2026-07-13 ruling.

| order | file | concern | interactive only |
|---|---|---|---|
| 1 | `conf.d/10-aliases.fish` | `vi`, the eza family, `cd` to `z`, `mscan` | yes, own guard |
| 2 | `conf.d/20-tools.fish` | `STARSHIP_CONFIG`, starship, zoxide, atuin with the Ctrl+E rebind and the up arrow restore | yes, own guard; atuin block ends the file early when atuin is missing |
| 3 | `conf.d/30-shell-verbs.fish` | agent seat launchers `cc`, `cac`, `cc2`, `cac2`, `cx`, `cax` and `CLAUDE_ENVELOPE` | yes, own guard |
| 4 | `conf.d/colors.fish` | theme colours, reload on theme pointer move | no (unchanged) |
| 5 | `conf.d/herdr-term.fish` | `KITTY_WINDOW_ID=0` inside herdr panes (#334) | no (unchanged) |
| 6 | `conf.d/remote.fish` | `desk`, the herdr projector, on hosts other than strix | no (unchanged apart from one `##` line) |
| 7 | `config.fish` | greeting off, default key bindings, `SSH_ASKPASS` erase, the interactive guard with its #236 and 2026-07-13 ruling comments, the keypad escape | guard is here |
| lazy | `functions/navidrome-scan.fish` | `navidrome-scan`, autoloaded on first call | n/a |
| lazy | `completions/copilot.fish` | generated completions for `copilot` | n/a |

`fish_variables` is tracked and holds only `__fish_initialized`; no fragment uses `set -U` (REPORTED, `conf.d/colors.fish` header).

## What moved from where

Line numbers are those of `config.fish` at commit `032cc87d` (the clone base, MEASURED with `git log`).

| old `config.fish` lines | new home |
|---|---|
| 1 through 19 (flags, ruling comments, guard, keypad escape) | `config.fish`, verbatim, below a new header |
| 21 (`alias vi`) | `conf.d/10-aliases.fish` |
| 23 through 25 (starship, zoxide) | `conf.d/20-tools.fish` |
| 27 through 43 (eza aliases, `cd` to `z`) | `conf.d/10-aliases.fish` |
| 45 through 94 (Claude seats comment, `CLAUDE_ENVELOPE`, `__claude_seat`, `cc`, `cac`, `cc2`, `cac2`, Codex comment, `cx`, `cax`) | `conf.d/30-shell-verbs.fish`, with a `## group, verb, doc` line above each verb |
| 96 through 100 (Music comment, `mscan`) | `conf.d/10-aliases.fish` |
| 102 through 108 (atuin init, Ctrl+E, up arrow) | `conf.d/20-tools.fish`, still last in its file |

MEASURED: a Python check confirmed that every non blank line of the old `config.fish` appears verbatim in exactly one of the four new files.

## Verb doc lines

`30-shell-verbs.fish` and `remote.fish` carry one comment per verb in the form `## group | verb | doc`. A keymap or palette generator can collect shell verbs with `grep -h '^ *## ' conf.d/*.fish` and not have to parse fish. Nothing reads these lines yet. Exposing these verbs as Vicinae commands is proposed, not built (INFERRED).

## Alias and function names, before and after

MEASURED 2026-10-22 with this scratch script, run on the source tree (`/home/tom/mecattaf/dotfiles/home/dot_config/fish`) and on this folder: `grep -rhoE '^[[:space:]]*(alias|function) [^ =;]+' --include='*.fish' | sort -u`. `diff` of the two outputs was empty: the 23 names are identical.

```
alias cax
alias cd
alias cx
alias l
alias l.
alias la
alias ll
alias llm
alias ls
alias lS
alias lt
alias lx
alias mscan
alias vi
function cac
function cac2
function cc
function cc2
function __claude_seat
function desk
function navidrome-scan
function __theme_load
function __theme_on_prompt
```

## Syntax check

MEASURED 2026-10-22, fish 4.8.1, `fish --no-execute <file>` on each file (parses, runs nothing): `config.fish`, the six `conf.d` fragments, `functions/navidrome-scan.fish` and `completions/copilot.fish` all returned exit 0. No fragment was sourced.

## Order changes worth knowing

1. The atuin `bind \ce` now runs before `config.fish` sets `fish_key_bindings`. MEASURED: on fish 4.8.1 the reload handler `__fish_reload_key_bindings` is defined inside `__fish_config_interactive`, which fish runs at the first prompt, after all config files, so the bind is not erased. INFERRED that the result is the same as before.
2. starship and zoxide now init before the keypad escape in `config.fish`. INFERRED harmless: neither writes to the terminal at init.
3. `desk` stays defined in non interactive shells on thin clients, exactly as before, because `remote.fish` was not given a guard.

## References outside this folder now stale (owned by other lanes, not edited)

1. `home/home.nix` line 285 says the atuin init and Ctrl+E rebind "stay in dot_config/fish/config.fish"; they are now in `conf.d/20-tools.fish`.
2. `AGENTS.md` line 5 and `home/dot_claude/skills/update-check/SKILL.md` line 79 place the `cc` and `cc2` launchers in `config.fish`; they are now in `conf.d/30-shell-verbs.fish`.
3. `herdr-projector`, `home/herdr.nix` and `hosts/client/default.nix` name `remote.fish` for `desk`; that still holds.

## Not verified

1. No interactive fish was started with this config, on any host; startup order and the surviving Ctrl+E bind are reasoned, not observed.
2. The repeated guard `status is-interactive || exit` in a conf.d fragment ends only that fragment (fish documents `exit` in a sourced file this way); not observed here.
3. shellcheck does not apply to fish, and shellcheck is not on PATH here anyway.
4. Comments moved verbatim keep their original dashes; only the new prose follows the no dash rule.

No second reader (Tom's light verification rule, 2026-10-20).
