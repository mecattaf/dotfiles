# Vendored: qwen3-embedding Gufo extension

A snapshot of the community Gufo extension that serves Qwen3-Embedding-8B
(Q8_0 GGUF) through `gufo serve embedding`. It is compiled into Gufo v0.33.0
by `modules/gufo-embedding.nix`
(`inputs.gufo-embedding.packages.<system>.default.override { extensions = [ ./. ]; }`).

- Source: the extension's local git repository `qwen3-embedding-gufo-extension`
  (MIT, copyright holder `mecattaf`). It has no public remote yet.
- Commit: `4eb92c68288f158e2eee80a717dde06da3f90ed1` (tag `wp2-done`).
- Built against: Gufo v0.33.0 = `77dff828be02a498e9951694f31b024e7ac87119`.
- Copied with `git archive wp2-done`, then
  `rsync -a --delete --exclude .git --exclude tests/fixtures --exclude docs --exclude functional --exclude tools`.
  Gufo's Nix package configures with `BUILD_TESTING=OFF`, so the test sources
  kept here are not built and the excluded fixtures are not needed.
- Licences: `LICENSE` (MIT) and `THIRD_PARTY_NOTICES.md` (MIT code adapted from
  Gufo, the lfm3 Gufo extension and llama.cpp's Unicode tables and BPE).

Do not edit files here. Change the extension in its own repository, then
re-vendor with the same command and update the commit above. When the
extension has a public repository, replace this directory with a flake input
that pins the same commit.
