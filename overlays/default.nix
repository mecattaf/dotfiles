final: prev: {
  # Add-only overlay + a single scoped upstream override (niri, below).
  # Everything else from the old COPR is already in nixpkgs (referenced directly).
  # NB: sfmono-liga (pkgs/sfmono-liga.nix) is wired in flake.nix, not here —
  # it needs the sfmono-liga flake input as src, and this file has no inputs.

  # Silence the upstream niri-session deprecation warning that prints (orange) at
  # every session start: "Calling 'import-environment' without a list of variable
  # names is deprecated". It comes from the ONE bare `systemctl --user
  # import-environment` in niri's resources/niri-session; the upstream fix is still
  # unmerged as of jul5 (niri #254/#3572). Redirect just that call's stderr — zero
  # behaviour change, only the deprecation text is dropped. --replace-fail makes a
  # future upstream rename fail the build loudly instead of silently no-op'ing.
  # Flows fleet-wide via programs.niri.package. NB: makes niri a from-source rebuild.
  niri = prev.niri.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      substituteInPlace resources/niri-session \
        --replace-fail \
          'systemctl --user import-environment' \
          'systemctl --user import-environment 2>/dev/null'
    '';
  });

  # mactahoe — the PROVEN source-build + OLED postPatch (NOT nix-test's prebuilt
  # tarball). Built/verified in a nixos/nix container 2026-06-19. Originated in
  # the mactahoe-oled staging repo (since deleted 2026-07-04); pkgs/ is the home.
  # Icons: stock default (blue folders); GTK: light+dark grey, dark OLED-patched.
  mactahoe-gtk-theme = final.callPackage ../pkgs/mactahoe-gtk-theme.nix { };
  mactahoe-icon-theme = final.callPackage ../pkgs/mactahoe-icon-theme.nix { };

  # Backlog.md — markdown-native task manager CLI (`backlog`). Not in nixpkgs;
  # packaged from the upstream release binary (Bun compile). See pkgs/backlog-md.nix.
  backlog-md = final.callPackage ../pkgs/backlog-md.nix { };

  # DEFERRED bespoke pkgs: asr-rs (v2 not in first push), cliamp, gws, fgp-browser.
}
