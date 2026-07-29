{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.ai-memory;
  qmd = pkgs.llm-agents.qmd;
in
{
  options.programs.ai-memory.journalDir = lib.mkOption {
    type = lib.types.str;
    default = "${config.home.homeDirectory}/mecattaf/notes/journal";
    description = ''
      Sole routing destination for manually drained AI-session journal notes.
    '';
  };

  config = {
    xdg.configFile."ai-memory/config.json".text = builtins.toJSON {
      schema = 1;
      journal_dir = cfg.journalDir;
    };

    # qmd owns only its read/index database.  The drain remains the sole writer
    # of journal Markdown, and `qmd update` is never configured to pull or mutate
    # the notes Git checkout.
    home.activation.aiMemoryJournal = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      journal_dir=${lib.escapeShellArg cfg.journalDir}
      run ${pkgs.coreutils}/bin/mkdir -p "$journal_dir"

      if current="$(${qmd}/bin/qmd collection show journal 2>/dev/null)"; then
        current_path="$(
          printf '%s\n' "$current" \
            | ${pkgs.gnused}/bin/sed -n 's/^  Path:     //p'
        )"
        if [ "$current_path" != "$journal_dir" ]; then
          echo "ai-memory: qmd collection 'journal' points at '$current_path', expected '$journal_dir'" >&2
          exit 1
        fi
      else
        run ${qmd}/bin/qmd collection add "$journal_dir" --name journal
      fi
    '';
  };
}
