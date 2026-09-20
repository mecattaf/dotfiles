# lib/paths.nix (2026-09-20 corrections), the two home-relative trees this
# estate names from more than one module, written once.
#
# WHY THIS FILE EXISTS. Until 2026-09-20 the notes vault and the dotfiles
# checkout were spelled as literals or as `${config.home.homeDirectory}/mecattaf/
# ...` in five separate .nix files, which meant the 2026-09-20 home migration
# would have had to find and flip five strings that must agree with each other or
# a flake check goes red (flake.nix's `expectedJournal` is asserted against what
# home/ai-memory.nix renders, so a half-done edit is a build failure, not a
# silent drift). One definition point makes that flip one edit.
#
# THE VALUES ARE UNCHANGED TODAY. `~/mecattaf/notes` and `~/mecattaf/dotfiles`
# are exactly where they were this morning. Wave 0 of the migration left
# `~/notes` and `~/dotfiles` as SYMLINKS to them; the after-switch step replaces
# those symlinks with the real move and flips the two strings below to
# "/home/tom/notes" and "/home/tom/dotfiles" in the same commit. Nothing in this
# file anticipates that: it is a seam, not a schedule.
#
# WHY LITERALS AND NOT `${config.home.homeDirectory}`. This file is imported by
# flake.nix (for a check) and by NixOS modules (modules/dotfiles-bootstrap.nix
# runs before any user session exists) as well as by home-manager modules, and
# only the last of those has a `config.home.homeDirectory` to read. The estate
# has exactly one user on exactly one home, and flake.nix already asserted the
# literal, so the literal is what every consumer can agree on. Home-manager
# modules that want the option's own default still get it from here.
#
# HOW TO USE IT. `let paths = import ../lib/paths.nix; in paths.notesDir`, the
# same shape lib/local-models.nix and lib/model-store.nix are consumed with
# (imported where they are used, not projected through the flake's outputs).
{
  # The notes vault: the journal the memory drain writes, the CRM database, the
  # backlog, the continuity packets.
  notesDir = "/home/tom/mecattaf/notes";

  # The RAW dotfiles checkout every out-of-store symlink in home/home.nix points
  # into, and the one a switch must be taken from (#313, DECISIONS.md line 28).
  # NOT the same thing as `github:mecattaf/dotfiles`, which is a remote and is
  # deliberately left spelled out wherever it appears.
  dotfilesDir = "/home/tom/mecattaf/dotfiles";
}
