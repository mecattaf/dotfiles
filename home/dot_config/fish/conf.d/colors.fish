# Color Palette (Claude-inspired, mapped from catppuccin mocha nvim overrides)
set -l normal eaecf0
set -l command 70b8ff
set -l param 9be963
set -l keyword f47b85
set -l quote 9be963
#set -l redirection f5c2e7 # catppuccin pink — no nvim override
set -l end fbad60
set -l comment 818898
set -l error f47b85
#set -l gray 6c7086 # catppuccin overlay0 — no nvim override
#set -l selection 313244 # catppuccin surface0 — no nvim override
#set -l search_match 313244 # catppuccin surface0 — no nvim override
set -l option 9be963
#set -l operator f5c2e7 # catppuccin pink — no nvim override
#set -l escape eba0ac # catppuccin maroon — no nvim override
#set -l autosuggestion 6c7086 # catppuccin overlay0 — no nvim override
set -l cancel f47b85
set -l cwd f9e2af
set -l user 5eeded
set -l host 70b8ff
set -l host_remote 9be963
#set -l status f38ba8
#set -l pager_progress 6c7086 # catppuccin overlay0 — no nvim override
#set -l pager_prefix f5c2e7 # catppuccin pink — no nvim override
set -l pager_completion eaecf0
#set -l pager_description 6c7086 # catppuccin overlay0 — no nvim override

# Syntax Highlighting Colors
set -g fish_color_normal $normal
set -g fish_color_command $command
set -g fish_color_param $param
set -g fish_color_keyword $keyword
set -g fish_color_quote $quote
#set -g fish_color_redirection $redirection # no nvim override
set -g fish_color_end $end
set -g fish_color_comment $comment
set -g fish_color_error $error
#set -g fish_color_gray $gray # no nvim override
#set -g fish_color_selection --background=$selection # no nvim override
#set -g fish_color_search_match --background=$search_match # no nvim override
set -g fish_color_option $option
#set -g fish_color_operator $operator # no nvim override
#set -g fish_color_escape $escape # no nvim override
#set -g fish_color_autosuggestion $autosuggestion # no nvim override
set -g fish_color_cancel $cancel
set -g fish_color_cwd $cwd
set -g fish_color_user $user
set -g fish_color_host $host
set -g fish_color_host_remote $host_remote
set -g fish_color_cwd_root red
set -g fish_color_history_current --bold
set -g fish_color_match --background=brblue
set -g fish_color_valid_path --underline

set -g fish_color_status f47b85

# Completion Pager Colors
#set -g fish_pager_color_progress $pager_progress # no nvim override
#set -g fish_pager_color_prefix $pager_prefix # no nvim override
set -g fish_pager_color_completion $pager_completion
#set -g fish_pager_color_description $pager_description # no nvim override
set -g fish_pager_color_selected_background -r
