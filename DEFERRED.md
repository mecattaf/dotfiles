# DEFERRED

What a captured ruling bars this repository's units from doing, and who does it
instead. A row leaves when the act has been taken, not when it has been argued
about.

| id | deferred | why it is barred here | who takes it, and when |
|---|---|---|---|
| DF-U-D16-1 | Removing the two hand-written mirror units: `systemctl --user disable --now claude-transcript-mirror.timer`, then `rm ~/.config/systemd/user/claude-transcript-mirror.service` and `rm ~/.config/systemd/user/claude-transcript-mirror.timer` | `~/sept7/scopes/clean-dotfiles.md:171` §6 — "Tom's shell acts that no executor performs" — names this removal explicitly, alongside `git push origin main`, `gh pr create` and `sudo nixos-rebuild switch`. It is also barred by its own mechanism: until the switch that installs the declared units, the hand-written pair is the ONLY working mirror, so deleting it early stops the mirror and stops it silently | Tom, on the coordinator, as step 4 of the P05 walkthrough (`receipts/L8-FLASH/PR-BODY.md`) — after `/home/tom/mecattaf/dotfiles` carries the branch (done: `e549ba91` is an ancestor of `main`) and before `nixos-rebuild switch`. Sequenced inside U-D19. MEASURED still present 2026-09-06, both files 2026-09-04 18:13 |
| DF-U-D16-2 | `sudo nixos-rebuild switch --flake /home/tom/mecattaf/dotfiles#coordinator`, and the worker's switch | U-D16's non-goals: "no switch here; no llama-swap restart". The coordinator's switch is U-D19's own unit (`~/research-methods/DECISIONS.md` D-B15); the worker box's switch is a TOM LINE by the same ruling | U-D19 for the coordinator; Tom for the worker |

**How a row is discharged.** `bash tools/u-d16-l8-flash-oracle.sh` prints
DF-U-D16-1's state as a `NOTE` row (`5e`), and
`home/dot_local/bin/l8-flash-probe` prints it as `[E] hand-written pair gone`.
When both read green on the coordinator, delete the row.
