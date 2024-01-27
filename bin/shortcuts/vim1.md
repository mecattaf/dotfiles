## Cursor Movement

| Command       | Action                                                                |
|---------------|-----------------------------------------------------------------------|
| `h`           | Move cursor left                                                      |
|               |                                                                       |
| `j`           | Move cursor down                                                      |
|               |                                                                       |
| `k`           | Move cursor up                                                        |
|               |                                                                       |
| `l`           | Move cursor right                                                     |
|               |                                                                       |
| `gj`          | Move cursor down (multi-line text)                                    |
|               |                                                                       |
| `gk`          | Move cursor up (multi-line text)                                      |
|               |                                                                       |
| `H`           | Move to top of screen                                                  |
|               |                                                                       |
| `M`           | Move to middle of screen                                               |
|               |                                                                       |
| `L`           | Move to bottom of screen                                               |
|               |                                                                       |
| `w`           | Jump forwards to the start of a word                                  |
|               |                                                                       |
| `W`           | Jump forwards to the start of a word (words can contain punctuation)  |
|               |                                                                       |
| `e`           | Jump forwards to the end of a word                                    |
|               |                                                                       |
| `E`           | Jump forwards to the end of a word (words can contain punctuation)    |
|               |                                                                       |
| `b`           | Jump backwards to the start of a word                                 |
|               |                                                                       |
| `B`           | Jump backwards to the start of a word (words can contain punctuation) |
|               |                                                                       |
| `ge`          | Jump backwards to the end of a word                                   |
|               |                                                                       |
| `gE`          | Jump backwards to the end of a word (words can contain punctuation)   |
|               |                                                                       |
| `%`           | Move cursor to matching character                                     |
|               |                                                                       |
| `0`           | Jump to the start of the line                                         |
|               |                                                                       |
| `^`           | Jump to the first non-blank character of the line                     |
|               |                                                                       |
| `$`           | Jump to the end of the line                                           |
|               |                                                                       |
| `g_`          | Jump to the last non-blank character of the line                      |
|               |                                                                       |
| `gg`          | Go to the first line of the document                                  |
|               |                                                                       |
| `G`           | Go to the last line of the document                                   |
|               |                                                                       |
| `5gg` or `5G` | Go to line 5                                                          |
|               |                                                                       |
| `gd`          | Move to local declaration                                             |
|               |                                                                       |
| `gD`          | Move to global declaration                                            |
|               |                                                                       |
| `fx`          | Jump to next occurrence of character x                                |
|               |                                                                       |
| `tx`          | Jump to before next occurrence of character x                         |
|               |                                                                       |
| `Fx`          | Jump to the previous occurrence of character x                        |
|               |                                                                       |
| `Tx`          | Jump to after previous occurrence of character x                     |
|               |                                                                       |
| `;`           | Repeat previous f, t, F or T movement                                 |
|               |                                                                       |
| `,`           | Repeat previous f, t, F or T movement, backwards                      |
|               |                                                                       |
| `}`           | Jump to next paragraph (or function/block, when editing code)         |
|               |                                                                       |
| `{`           | Jump to previous paragraph (or function/block, when editing code)     |
|               |                                                                       |
| `zz`          | Center cursor on screen                                               |
|               |                                                                       |
| `zt`          | Position cursor on top of the screen                                  |
|               |                                                                       |
| `zb`          | Position cursor on bottom of the screen                               |
|               |                                                                       |
| `Ctrl + e`    | Move screen down one line (without moving cursor)                     |
|               |                                                                       |
| `Ctrl + y`    | Move screen up one line (without moving cursor)                       |
|               |                                                                       |
| `Ctrl + b`    | Move screen up one page (cursor to last line)                         |
|               |                                                                       |
| `Ctrl + f`    | Move screen down one page (cursor to first line)                      |
|               |                                                                       |
| `Ctrl + d`    | Move cursor and screen down 1/2 page                                  |
|               |                                                                       |
| `Ctrl + u`    | Move cursor and screen up 1/2 page                                    |

## Insert Mode - inserting/appending text

| Command            | Action                                                                         |
|--------------------|--------------------------------------------------------------------------------|
| `i`                | Insert before the cursor                                                       |
|                    |                                                                                |
| `I`                | Insert at the beginning of the line                                            |
|                    |                                                                                |
| `a`                | Insert (append) after the cursor                                               |
|                    |                                                                                |
| `A`                | Insert (append) at the end of the line                                         |
|                    |                                                                                |
| `o`                | Append (open) a new line below the current line                                |
|                    |                                                                                |
| `O`                | Append (open) a new line above the current line                                |
|                    |                                                                                |
| `ea`               | Insert (append) at the end of the word                                         |
|                    |                                                                                |
| `Ctrl + h`         | Delete the character before the cursor during insert mode                      |
|                    |                                                                                |
| `Ctrl + w`         | Delete word before the cursor during insert mode                               |
|                    |                                                                                |
| `Ctrl + j`         | Add a line break at the cursor position during insert mode                     |
|                    |                                                                                |
| `Ctrl + t`         | Indent (move right) line one shiftwidth during insert mode                     |
|                    |                                                                                |
| `Ctrl + d`         | De-indent (move left) line one shiftwidth during insert mode                   |
|                    |                                                                                |
| `Ctrl + n`         | Insert (auto-complete) next match before the cursor during insert mode         |
|                    |                                                                                |
| `Ctrl + p`         | Insert (auto-complete) previous match before the cursor during insert mode     |
|                    |                                                                                |
| `Ctrl + rx`        | Insert the contents of register x                                              |
|                    |                                                                                |
| `Ctrl + ox`        | Temporarily enter normal mode to issue one normal-mode command x               |
|                    |                                                                                |
| `Esc` or `Ctrl + c`| Exit insert mode                                                               |

## Editing


| Command         | Action                                                          |
|-----------------|-----------------------------------------------------------------|
| `r`             | Replace a single character                                      |
|                 |                                                                 |
| `R`             | Replace more than one character, until ESC is pressed           |
|                 |                                                                 |
| `J`             | Join line below to the current one with one space in between    |
|                 |                                                                 |
| `gJ`            | Join line below to the current one without space in between     |
|                 |                                                                 |
| `gwip`          | Reflow paragraph                                                |
|                 |                                                                 |
| `g~`            | Switch case up to motion                                        |
|                 |                                                                 |
| `gu`            | Change to lowercase up to motion                                |
|                 |                                                                 |
| `gU`            | Change to uppercase up to motion                                |
|                 |                                                                 |
| `cc`            | Change (replace) entire line                                    |
|                 |                                                                 |
| `c$` or `C`     | Change (replace) to the end of the line                          |
|                 |                                                                 |
| `ciw`           | Change (replace) entire word                                    |
|                 |                                                                 |
| `cw` or `ce`    | Change (replace) to the end of the word                         |
|                 |                                                                 |
| `s`             | Delete character and substitute text                            |
|                 |                                                                 |
| `S`             | Delete line and substitute text (same as cc)                    |
|                 |                                                                 |
| `xp`            | Transpose two letters (delete and paste)                        |
|                 |                                                                 |
| `u`             | Undo                                                            |
|                 |                                                                 |
| `U`             | Restore (undo) last changed line                                |
|                 |                                                                 |
| `Ctrl + r`      | Redo                                                            |
|                 |                                                                 |
| `.`             | Repeat last command                                             |
