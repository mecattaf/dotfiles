# DEFERRED

What a captured ruling bars this repository's units from doing, and who does it
instead. A row leaves when the act has been taken, not when it has been argued
about.

| id | deferred | why it is barred here | who takes it, and when |
|---|---|---|---|
| DF-U-D16-1 | Removing the two hand-written mirror units: `systemctl --user disable --now claude-transcript-mirror.timer`, then `rm ~/.config/systemd/user/claude-transcript-mirror.service` and `rm ~/.config/systemd/user/claude-transcript-mirror.timer` | `~/sept7/scopes/clean-dotfiles.md:171` §6 — "Tom's shell acts that no executor performs" — names this removal explicitly, alongside `git push origin main`, `gh pr create` and `sudo nixos-rebuild switch`. It is also barred by its own mechanism: until the switch that installs the declared units, the hand-written pair is the ONLY working mirror, so deleting it early stops the mirror and stops it silently | Tom, on the coordinator, as step 4 of the P05 walkthrough (`receipts/L8-FLASH/PR-BODY.md`) — after `/home/tom/mecattaf/dotfiles` carries the branch (done: `e549ba91` is an ancestor of `main`) and before `nixos-rebuild switch`. Sequenced inside U-D19. MEASURED still present 2026-09-06, both files 2026-09-04 18:13 |
| DF-U-D16-2 | `sudo nixos-rebuild switch --flake /home/tom/mecattaf/dotfiles#coordinator`, and the worker's switch | U-D16's non-goals: "no switch here; no llama-swap restart". The coordinator's switch is U-D19's own unit (`~/research-methods/DECISIONS.md` D-B15); the worker box's switch is a TOM LINE by the same ruling | U-D19 for the coordinator; Tom for the worker |
| DF-U-D12-1 | Switching the coordinator generation or starting/stopping any `tally-seat-feeder-*` unit | U-D12's non-goal is "no switch here"; D-B15 assigns the coordinator switch to U-D19. A declaration is the deliverable in this unit, never a hand-installed unit (Rule 9) | U-D19 switches the coordinator in the P05 order; Home Manager then enables the three timers through `timers.target` |
| DF-U-D12-2 | Giving `pi-qwencloud` a measured allowance/window or releasing an item onto it | D-B17 keeps TL-17 unset: the row stays UNKNOWN, is never proposed onto, and items naming it remain `unclaimed` carrying this deferral | Tom supplies one of TL-17's named settling artefacts; the later row writer may then replace UNKNOWN with that measured statement |
| DF-U-D12-3 | Refreshing the expired `cc3` OAuth token | D-B5 records this as the TOM LINE "run `claude` once on cc3". This feeder may read the credential through `stamp-receipt.py window`; it may not perform an interactive login | Tom runs `claude` once with the cc3 seat configuration. Until then the enabled feeder writes a fresh UNKNOWN row with the reader's reason |
| DF-U-D12-4 | Releasing work onto the `codex` row | D-B6 says the login is third-party and the row is never proposed onto. Reading `rate_limits` from its rollout is not a spend and does not change ownership | A later explicit ownership ruling (TL-6); this unit preserves `owner: third-party` in every write |
| DF-U-D17-1 | Turning `l8-flash-probe`'s two new `[E]` rows green: `util-sampler.timer` on BOTH boxes and `util-row.timer` on the coordinator. They ship FAIL | Only a switch installs a declared unit, and this unit switches nothing. `~/research-methods/DECISIONS.md` D-B15 splits the two switches: the coordinator's is U-D19's own unit, the worker box's is a TOM LINE. U-D17's non-goals bar changing which box runs which timer, so nothing here can shorten the wait | U-D19 for the coordinator; Tom for the worker. Discharged when `bash tools/u-d17-util-01-oracle.sh` and `l8-flash-probe` both read green for the two rows on both boxes — then delete this row. MEASURED 2026-09-06: neither unit exists on the coordinator, `FragmentPath` empty for both |
| DF-U-D17-2 | Starting any serve on this estate with `--metrics`, so UTIL-01's `tokens_in` / `tokens_out` stop being `UNKNOWN` | U-D17's non-goal is "no change to the sampler's semantics", and R-04 forbids reading an unresolved value as zero — so the sampler reports `UNKNOWN` loudly rather than `0`, and the fix is a serve-side change in another issue, not a sampler-side one here. 0 hits for `--metrics` in `lib/local-models.nix` and `modules/llama-swap.nix` | [dotfiles#312](https://github.com/mecattaf/dotfiles/issues/312). Until then "how many tokens per week" stays a question, and `tokens_grade` stays `UNKNOWN` |

**How DF-U-D16-1 is discharged.** `bash tools/u-d16-l8-flash-oracle.sh` prints
its state as a `NOTE` row (`5e`), and
`home/dot_local/bin/l8-flash-probe` prints it as `[E] hand-written pair gone`.
When both read green on the coordinator, delete the row. DF-U-D17-1 is the same
shape one lane later: `l8-flash-probe` prints it as the two
`[E] util-*.timer declared` rows, and `bash tools/u-d17-util-01-oracle.sh`
gates the repository half around them. A row leaves when the switch has been
taken and the rows read green on the box, not when the merge landed.
The U-D12 rows likewise leave only when the actor and condition in their last
column have actually occurred; a fresh UNKNOWN observation does not discharge
its underlying deferral.
