{
  config,
  lib,
  osConfig,
  pkgs,
  ...
}:
# Agent binaries and writable seat initialization belong to the brain and
# physical seat. Compute retains the shell and browser plumbing only.
let
  link = config.lib.rawDotfiles.link;
  # The brain links retained fleet skills separately so portable tools can
  # supply their own skills. Thin seats keep their existing whole-root links.
  skillRoots = [
    ".claude/skills"
    ".claude-work/skills"
    ".agents/skills"
  ];
  fleetSkills = lib.filter (name: name != "synced") (
    builtins.attrNames (builtins.readDir ./dot_claude/skills)
  );
  skillFiles =
    if !(osConfig.myFleet.has "brain") then
      lib.genAttrs skillRoots (_: {
        source = link "dot_claude/skills";
      })
    else
      lib.listToAttrs (
        lib.concatMap (
          root:
          map (
            name:
            lib.nameValuePair "${root}/${name}" {
              source = link "dot_claude/skills/${name}";
            }
          ) fleetSkills
          ++ lib.optionals (!config.rawDotfiles.inStore) [
            (lib.nameValuePair "${root}/synced" {
              source = link "dot_claude/skills/synced";
            })
          ]
          ++ lib.optionals (osConfig.myFleet.has "brain") [
            (lib.nameValuePair "${root}/publish-artifact" {
              source = config.lib.file.mkOutOfStoreSymlink "${config.xdg.dataHome}/artifact-publish/current/skills/publish-artifact";
            })
          ]
        ) skillRoots
      );
  # Curated llm-agents.nix install. `pkgs.llm-agents` (from the flake input's
  # overlay) is the entire ~139-agent catalog, prebuilt against upstream's own
  # nixpkgs. The maximalist "install every buildable member" sweep (write-up
  # retired to Git history; see docs/old/README.md) surfaced a lot we neither want nor need on the
  # desktop, so we've pruned to an explicit ALLOWLIST — only these names are
  # pulled from the catalog. Adding an agent is now a deliberate edit here, and
  # agents upstream adds no longer land automatically on `nix flake update`.
  #
  # `meta.available` filtering (wrapped in tryEval, since evaluating meta can
  # itself throw) skips any keeper that's broken / wrong-platform on this host.
  # claude-code comes FROM this set, so it has no standalone home.packages entry.
  keepFromLlmAgents = [
    "claude-code"
    "ccusage"
    "ck"
    "claude-agent-acp"
    "claude-code-router" # bin: `ccr` — routes Claude Code requests to other model backends/providers
    "codex"
    "spec-kit" # bin: `specify` — GitHub Spec-Kit, spec-driven development bootstrapper
    "cc-switch-cli" # bin: `cc-switch` — switches Claude Code/Codex/Gemini CLI provider configs
    "opencode" # bin: `opencode` — headless client for OpenCode Zen's free models behind the `zen` wrapper (dot_local/bin); NOT a harness
  ];
  llmAgentsSelected = pkgs.buildEnv {
    name = "llm-agents-selected";
    # Curated set is small, but a couple of members still share share/ paths;
    # keep ignoreCollisions so the profile merges deterministically (first wins).
    ignoreCollisions = true;
    paths = lib.pipe pkgs.llm-agents [
      (lib.filterAttrs (n: _: builtins.elem n keepFromLlmAgents))
      (lib.filterAttrs (
        _: v: (builtins.tryEval (lib.isDerivation v && (v.meta.available or true))).value
      ))
      builtins.attrValues
    ];
  };

in
lib.mkIf (osConfig.myFleet.has "brain" || osConfig.myFleet.has "seat") {
  home.packages = [ llmAgentsSelected ];
  # Claude Code skills + settings in the standard user config directory.
  # Deployed as individual out-of-store symlinks — NOT a whole-dir link — so
  # ~/.claude stays a real, writable directory that modules/secrets.nix can seed
  # .credentials.json into (a whole-dir symlink would push the credential into the
  # PUBLIC repo tree). Without this, a fresh box has zero skills/settings.
  home.file = skillFiles // {
    ".claude/rules/runtime-tests.md".source = link "agent-runtime-rules.md";
    ".claude/rules/ultracode-workflows.md".source = link "agent-workflow-rules.md";
    ".codex/AGENTS.md".source = link "agent-runtime-rules.md";
    ".claude-work/rules/runtime-tests.md".source = link "agent-runtime-rules.md";
    ".claude-work/rules/ultracode-workflows.md".source = link "agent-workflow-rules.md";
  };

  # NO hook is delivered here any more. The SessionEnd harvest hook (MEM-2,
  # dotfiles#339) was removed 2026-09-23: it blocked session exit for up to 57 s
  # on the runs that actually harvested, and Claude Code reported the abort as
  # "SessionEnd hook [...] failed: Hook cancelled" on every close. Of its last
  # 101 logged runs, 54 were skips. The harvest verb itself is unchanged and
  # still reachable on demand through the `drain` skill.
  #
  # ~/.claude/hooks is deliberately left as a real, writable directory owned by
  # nobody: a hook that is not delivered from this repository can still live
  # there (the dead SessionStart hook that once named herdr-agent-state.sh was
  # removed the same way, 2026-09-13).

  # Second Claude account (work): `cc2`/`cac2` in fish set CLAUDE_CONFIG_DIR to
  # ~/.claude-work. Same skills + settings, separate .credentials.json/.claude.json.

  # Claude owns mutable preferences. One direct symlink hop reaches writable
  # shared state, never the Nix store or Git checkout. Activation seeds only
  # once and preserves /model and /effort changes on every later switch.
  home.activation.claudeSettings = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run ${pkgs.python3}/bin/python3 ${./claude-settings.py} \
      --home "$HOME" --template ${./dot_claude/settings.json}
  '';

  # Same canonical skill tree, exposed to Codex and dsh (home/dsh.nix) through
  # the vendor-neutral, always-trusted Agent-Skills directory (~/.agents/skills).
  # Both read the same agentskills.io SKILL.md format (name/description
  # frontmatter, symlinks followed), so ONE tree feeds every harness.

  # OpenCode CLI config for the Zen free lane (docs/free-lanes.md, last
  # section): default and small model, sharing off, only the `opencode`
  # provider, and a permission block that denies edit/bash/web so an unattended
  # `opencode run` can only read inside its cwd. ONE file, not a whole-dir
  # link: ~/.config/opencode is a real directory Tom made in July 2026
  # (package.json, package-lock.json, .gitignore, opencode.jsonc) and it stays
  # his. Measured on 1.19.3: opencode.jsonc is loaded AFTER opencode.json and
  # wins on conflicting keys, but his .jsonc holds only "$schema", so this
  # file's keys all survive the merge. Delivering as opencode.jsonc would have
  # collided with his file at activation.
  xdg.configFile."opencode/opencode.json".source = link "dot_config/opencode/opencode.json";
}
