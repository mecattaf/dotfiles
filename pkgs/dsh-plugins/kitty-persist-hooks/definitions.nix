{ lib }:
# The kitty-persist harness definition of one hand-run dsh profile, as data.
# home/kitty-persist-agents.nix writes one per selecting profile to
# ~/.config/kitty-persist/harness/dsh-<profile>.json on the session host; the
# plugin's tests and checks.kitty-persist-dsh-hooks replay events through it.
#
# DRAFT FIELD NAMES. The definition schema is not published yet; this follows
# the four parts and the optional fifth that the kitty-persist specification
# fixes (recognition, event to state, resume, install, conversation file).
# When the program ships its schema, rename the keys here and run
# `kitty-persist harness check` on every generated file.
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

  # Event words of ./index.js (EVENTS) -> state, or the agent's end.
  events = {
    session-start.state = "idle";
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
    # kernel's comm is the thread name `MainThread`. Recognition must match
    # the argv0 basename.
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
    # none). A line's `type` says what it is; content sits in nested fields.
    conversation = {
      format = "jsonl";
      kind = "type";
      user = {
        kind = "user/message";
        text = "data.content[].text";
      };
      assistant = {
        kind = "assistant/message";
        text = "data.message.content[].text";
      };
      toolCall = {
        kind = "tool/call";
        name = "data.name";
        input = "data.arguments";
      };
      toolResult = {
        kind = "tool/result";
        text = "data.message.content[].text";
        error = "data.message.isError";
      };
    };
  };
}
