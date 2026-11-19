{ lib }:
# The kitty-persist harness definition of one hand-run dsh profile, as data.
# home/kitty-persist-agents.nix writes one per selecting profile to
# ~/.config/kitty-persist/harness/dsh-<profile>.json on the session host; the
# plugin's tests and checks.kitty-persist-dsh-hooks replay events through it.
#
# Shape: kitty-persist's published harness definition schema
# (schema/harness-definition.schema.json in the kitty-persist repository): the
# four parts recognize/fields/events, resume and install, plus the optional
# conversation part. checks.kitty-persist-dsh-hooks runs `kitty-persist
# harness check` on every generated file when it is given the program.
#
# One definition per profile, because the resume must name the same profile:
# dsh refuses to adopt a session whose recorded preset the profile does not
# compose, and the profile is neither an environment variable nor hook data.
let
  # The wrapper accepts DSH_ROUTE only for these (pkgs/dsh/default.nix).
  routeProfiles = [
    "headless"
    "sdk"
    "acp"
    "zen"
    "native"
  ];
in
rec {
  harnessName = profile: "dsh-${profile}";

  # Event words of ./index.js (EVENTS) -> a state (S22.1) or the agent's end
  # (S9.8). The plugin already sends a distinct word per case (and nothing
  # for a subagent); only session-start needs a condition, as in the shipped
  # Claude Code and Codex definitions: a start after a compaction happens
  # inside a turn, so it is working, every other start is idle.
  events = {
    session-start = [
      {
        when.source = "compact";
        state = "working";
      }
      { state = "idle"; }
    ];
    turn-start.state = "working";
    tool-result.state = "working";
    approval-asked.state = "waiting";
    approval-decided.state = "working";
    question-asked.state = "waiting";
    question-answered.state = "working";
    stop.state = "done";
    stop-failure.state = "done";
    turn-aborted.state = "idle";
    session-end.ended = true;
  };

  definition = profile: {
    # The dsh process is node started as `exec -a dsh`: argv0 is `dsh`, the
    # kernel's comm is the thread name `MainThread`. kitty-persist matches the
    # base name of argv[0] as well as comm, so `dsh` finds it.
    recognize.commands = [ "dsh" ];
    # The payload fields ./index.js sends.
    fields = {
      session = "session_id";
      transcript = "transcript_path";
      cwd = "cwd";
    };
    inherit events;
    # dsh adopts the session only with the same profile and the same
    # directory. `-` reads the next instruction from the terminal (ended by
    # ctrl+D): nothing is typed for the user. The carried variables pick the
    # same DSH_HOME, the same account slot and, where allowed, the same route.
    resume = {
      command = [
        "dsh"
        profile
        "--session-id"
        "{id}"
        "-"
      ];
      env = [
        "DSH_HOME"
        "DSH_KEY_SLOT"
      ]
      ++ lib.optional (builtins.elem profile routeProfiles) "DSH_ROUTE";
    };
    # dsh has no hook settings file: the plugin is the installation.
    install.manual = "dsh reports through the kitty-persist-hooks plugin, which the dotfiles select per hand-run profile (pkgs/dsh profilePlugins); there is no settings file to change.";
    # Session logs are plain JSONL (pkgs/dsh/sessions.patch.yml, compression
    # none): a header line `{"type":"session","id":...}`, then one line per
    # event with a `type` and nested `data`. Text is an array of parts, which
    # the program renders like Claude's; `time` is epoch milliseconds, not a
    # text stamp, so it is not named.
    conversation = {
      format = "jsonl";
      session = {
        field = "id";
        when.type = "session";
      };
      entries = [
        {
          when.type = "user/message";
          speaker = "data.role";
          role = "user";
          text = "data.content";
          id = "data.id";
        }
        {
          when.type = "assistant/message";
          speaker = "data.message.role";
          role = "assistant";
          text = "data.message.content";
          id = "data.message.id";
        }
        {
          when.type = "tool/call";
          tool_name = "data.name";
          tool_input = "data.arguments";
        }
        {
          when.type = "tool/result";
          tool_result = "data.message.content";
        }
      ];
    };
  };
}
