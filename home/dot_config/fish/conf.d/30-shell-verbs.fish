# 30-shell-verbs.fish: the verbs Tom types to start work, the agent seat
# launchers. Each one carries a `## group | verb | doc` line so a generator (the
# keymap and palette lanes, tools/) can list shell verbs beside sway bindings
# and Vicinae commands without parsing fish.
# What it replaced: config.fish lines 45 through 94 until 2026-10-22; moved
# verbatim, only the `##` lines and this header are new.
# Deliberately absent: `desk`. It stays in conf.d/remote.fish because
# herdr-projector, home/herdr.nix and hosts/client/default.nix name that file;
# its `##` line lives there.
# Palette exposure of these verbs (Vicinae command entries in home/vicinae.nix)
# is proposed, not built: INFERRED from the lane brief, no Vicinae entry exists today.
# Interactive only, same guard as config.fish (2026-07-13 ruling).
status is-interactive || exit

# Claude Code: two seats, one launcher shape (2026-09-22).
#   cc  / cac   -> ~/.claude       the personal Claude Max login (gmail org)
#   cc2 / cac2  -> ~/.claude-work  the leger.run Claude Max login
# CLAUDE_CONFIG_DIR isolates login, history and state per seat; skills and
# settings are the same dotfiles links for both (home.nix). Claude Code never
# saves workspace trust for $HOME (docs, security: "trust acceptance is held
# for the current session only and is not written to disk"), so a seat started
# in ~ shows "Accessing workspace" on every launch. Both launchers therefore
# move into the desk envelope (~/today) when typed from ~; the shell stays
# there afterwards. Tom, 2026-10-13: cc and cc2 keep starting in ~/today; its
# stale CLAUDE.md brief was moved out that day.
set -q CLAUDE_ENVELOPE; or set -gx CLAUDE_ENVELOPE $HOME/today
## agents | __claude_seat | internal helper: start one Claude seat outside $HOME (not a verb)
function __claude_seat --description 'start one Claude seat outside $HOME'
    set -l seat $argv[1]
    set -l config_dir $argv[2]
    set -l args $argv[3..]
    if test (pwd) = $HOME
        if not test -d $CLAUDE_ENVELOPE
            echo "$seat: \$CLAUDE_ENVELOPE ($CLAUDE_ENVELOPE) does not exist; cd into a project first" >&2
            return 1
        end
        builtin cd $CLAUDE_ENVELOPE
        echo "($seat: started in $CLAUDE_ENVELOPE, not in ~)" >&2
    end
    # Agent view off for both seats (2026-10-12): herdr is the multiplexer, and
    # finished background sessions sat in "Needs input" for weeks. The 2.1.287
    # binary describes the switch as "Disable agent view (`claude agents`,
    # `--bg`, /background, the on-demand daemon)". The env var form needs no
    # edit to the seeded ~/.local/state/claude/settings.json.
    set -lx CLAUDE_CODE_DISABLE_AGENT_VIEW 1
    # A terminal opened from inside a cc2 session already carries
    # CLAUDE_CONFIG_DIR, so `cc` must clear it explicitly or it silently starts
    # cc2 (measured 2026-09-22). Each seat sets its own value or none.
    if test -n "$config_dir"
        env CLAUDE_CONFIG_DIR=$config_dir claude --dangerously-skip-permissions $args
    else
        env -u CLAUDE_CONFIG_DIR claude --dangerously-skip-permissions $args
    end
end
## agents | cc | start the personal Claude seat (~/.claude), in ~/today when typed from ~
function cc;   __claude_seat cc  "" $argv; end
## agents | cac | continue the newest personal Claude seat session
function cac;  __claude_seat cc  "" --continue $argv; end
## agents | cc2 | start the leger.run Claude seat (~/.claude-work), in ~/today when typed from ~
function cc2;  __claude_seat cc2 $HOME/.claude-work $argv; end
## agents | cac2 | continue the newest leger.run Claude seat session
function cac2; __claude_seat cc2 $HOME/.claude-work --continue $argv; end
# Codex, same shape: cx starts, cax resumes the newest session. codex 0.160.0
# auto-starts a shared app-server daemon that copies its install into
# ~/.codex/packages and needs the codex-package.json manifest the Nix build does
# not ship ("this CLI has no complete local package", 2026-10-04), so the
# launchers run the embedded server as before 0.160.
## agents | cx | start Codex with the embedded app server
alias cx='codex --disable daemon_auto_start --dangerously-bypass-approvals-and-sandbox'
## agents | cax | resume the newest Codex session
alias cax='codex resume --last --disable daemon_auto_start --dangerously-bypass-approvals-and-sandbox'

## Not verified
# Not run in a live shell; checked with `fish --no-execute` only. The `##` line
# format has no consumer yet.
# No second reader (Tom's light verification rule, 2026-10-20).
