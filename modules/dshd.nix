{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
{
  imports = [ inputs.dshd.nixosModules.default ];

  config = lib.mkIf (config.myFleet.has "brain") {
    dshd.enable = true;
    # Upstream reserves "default" for the link to the only declared release.
    dshd.releases.nas = {
      dsh = pkgs.llm-agents.dsh;
      # Never recorded in an instance, never passed to dsh. The NAS
      # login shell exports the token. The rest are per-launch values
      # of the shell that creates an instance (a Claude Code session,
      # a DSH tool shell); an instance must not inherit its creator's.
      # agency-kitty strips the first two Claude names for the same
      # reason (pkgs/agency-kitty/source/agency_kitty/cli.py).
      unsetEnvironment = [
        "CLOUDFLARE_API_TOKEN"
        "CLAUDECODE"
        "CLAUDE_CODE_ENTRYPOINT"
        "CLAUDE_CODE_CHILD_SESSION"
        "CLAUDE_CODE_SESSION_ID"
        "CLAUDE_CODE_SESSION_ATTENDED"
        "CLAUDE_CODE_MESSAGING_SOCKET"
        "CLAUDE_CODE_MESSAGING_TOKEN"
        "CLAUDE_CODE_EXECPATH"
        "CLAUDE_PID"
        "CLAUDE_EFFORT"
        "CLAUDE_ENVELOPE"
        "CODEX_THREAD_ID"
        "DSH_SESSION_ID"
        "DSH_SHELL"
        "DSH_PROFILE_DIR"
        "DSH_WEB_URL"
      ];
    };
  };
}
