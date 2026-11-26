# Claude pasted-image preview: recovered project and Nix route

The 7 October notes identify **claude-image-view**, the Claude Code mod for
pasted-image thumbnails. The recovered reference is
`~/notes/references/continuity/2026-10-23-strix-home/sources/today/HERDR-VICINAE-LEADS-2026-10-07.md:369`.
The 14 October convergence report also records its research checkout. This
is separate from image.nvim (Neovim buffer images), the old Kitty harness's
own image editor, and hc-paste-image (clipboard transport).

The matching upstream is [jarrodwatts/claude-image-view](https://github.com/jarrodwatts/claude-image-view),
plugin name `image-view`, currently version 0.2.0 at
`370b8e7bc0708bebe9762e63534f7ca18bc3e802` (checked 26 November).
It watches `[Image #n]` in the draft and draws matching thumbnails above the
prompt using Claude's native mod UI. It makes no model calls. It requires
Claude Code 2.1.287 or newer; the installed 2.1.331 satisfies this.

Other projects now implement similar behavior, including
[rkueny/claude-code-image-preview](https://github.com/rkueny/claude-code-image-preview)
(thumbnails and a session gallery). That is an alternative, not a second
plugin identified in the recovered October note. Do not enable overlapping
preview mods together.

## Declarative installation shape

Use Claude's documented `--plugin-dir` flag with a pinned Nix source. This
avoids marketplace installation and hand-edited Claude settings. For example,
a non-flake input in flake.nix:

```nix
inputs.claude-image-view = {
  url = "github:jarrodwatts/claude-image-view/370b8e7bc0708bebe9762e63534f7ca18bc3e802";
  flake = false;
};
```

Pass that source to the Home Manager agent module, and replace its selected
`claude-code` member with a wrapper (do not install a second competing
`claude` binary):

```nix
claudeWithPreview = pkgs.symlinkJoin {
  name = "claude-code-with-image-view";
  paths = [ pkgs.llm-agents.claude-code ];
  nativeBuildInputs = [ pkgs.makeWrapper ];
  postBuild = ''
    wrapProgram "$out/bin/claude" \
      --add-flags "--plugin-dir ${inputs.claude-image-view}"
  '';
};
```

Both `cc` and `cc2` already call `claude`, so a package wrapper reaches both
while preserving their separate credentials and shared mutable preferences.
The Nix lock owns updates. There is no `claude plugin install`, activation
script mutating installed_plugins.json, or forced replacement of writable
Claude settings. This is an installation recipe, not an enabled plugin in the
current fleet configuration. Validate its module loading from the read-only
store and its actual hc rendering before enabling it.

## Limits relevant to this fleet

The plugin reads Claude's NAS-side pasted-image cache. It does not transfer
the Zenbook clipboard; hc-paste-image supplies that independent step.
On Linux this upstream previews PNG; its non-PNG conversion uses macOS sips,
so JPEG/WebP/GIF can show “no preview”. Do not promise all accepted attachment
formats will get a thumbnail with this plugin.

Claude decides whether its native Image element can render Kitty graphics.
Upstream documents terminal-name detection trouble in Herdr and the
`CLAUDE_CODE_FORCE_TERMINAL_IMAGES=1` override, but that override cannot supply
missing transport or graphics replay. hc 0.1.22 forwards live image sequences
but does not reconstruct them on fresh attach; prompt placeholders also need
their corresponding image data. Qualify PNG paste, draft clear, resizing and
fresh reattach in the real Kitty/hc topology before choosing an override.
Keep notifications and the current Kitty clipboard-read policy unchanged.
