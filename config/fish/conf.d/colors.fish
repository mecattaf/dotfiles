# Color Palette
set -l normal cdd6f4
set -l command 89b4fa
set -l param f2cdcd
set -l keyword f38ba8
set -l quote a6e3a1
set -l redirection f5c2e7
set -l end fab387
set -l comment 7f849c
set -l error f38ba8
set -l gray 6c7086
set -l selection 313244
set -l search_match 313244
set -l option a6e3a1
set -l operator f5c2e7
set -l escape eba0ac
set -l autosuggestion 6c7086
set -l cancel f38ba8
set -l cwd f9e2af
set -l user 94e2d5
set -l host 89b4fa
set -l host_remote a6e3a1
#set -l status f38ba8
set -l pager_progress 6c7086
set -l pager_prefix f5c2e7
set -l pager_completion cdd6f4
set -l pager_description 6c7086

# Syntax Highlighting Colors
set -g fish_color_normal $normal
set -g fish_color_command $command
set -g fish_color_param $param
set -g fish_color_keyword $keyword
set -g fish_color_quote $quote
set -g fish_color_redirection $redirection
set -g fish_color_end $end
set -g fish_color_comment $comment
set -g fish_color_error $error
set -g fish_color_gray $gray
set -g fish_color_selection --background=$selection
set -g fish_color_search_match --background=$search_match
set -g fish_color_option $option
set -g fish_color_operator $operator
set -g fish_color_escape $escape
set -g fish_color_autosuggestion $autosuggestion
set -g fish_color_cancel $cancel
set -g fish_color_cwd $cwd
set -g fish_color_user $user
set -g fish_color_host $host
set -g fish_color_host_remote $host_remote

set -g fish_color_status f38ba8

# Completion Pager Colors
set -g fish_pager_color_progress $pager_progress
set -g fish_pager_color_prefix $pager_prefix
set -g fish_pager_color_completion $pager_completion
set -g fish_pager_color_description $pager_description

