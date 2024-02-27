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


## Marking Text

| Command         | Action                                                          |
|-----------------|-----------------------------------------------------------------|
| `v`             | Start visual mode, mark lines, then do a command (like y-yank)  |
|                 |                                                                 |
| `V`             | Start linewise visual mode                                     |
|                 |                                                                 |
| `o`             | Move to other end of marked area                               |
|                 |                                                                 |
| `Ctrl + v`      | Start visual block mode                                        |
|                 |                                                                 |
| `O`             | Move to other corner of block                                  |
|                 |                                                                 |
| `aw`            | Mark a word                                                     |
|                 |                                                                 |
| `ab`            | A block with ()                                                 |
|                 |                                                                 |
| `aB`            | A block with {}                                                 |
|                 |                                                                 |
| `at`            | A block with <> tags                                            |
|                 |                                                                 |
| `ib`            | Inner block with ()                                             |
|                 |                                                                 |
| `iB`            | Inner block with {}                                             |
|                 |                                                                 |
| `it`            | Inner block with <> tags                                        |
|                 |                                                                 |
| `Esc` or `Ctrl + c` | Exit visual mode                                               |

## Visual Commands

| Command | Action                                  |
|---------|-----------------------------------------|
| `>`     | Shift text right                        |
|         |                                         |
| `<`     | Shift text left                         |
|         |                                         |
| `y`     | Yank (copy) marked text                 |
|         |                                         |
| `d`     | Delete marked text                      |
|         |                                         |
| `~`     | Switch case                             |
|         |                                         |
| `u`     | Change marked text to lowercase         |
|         |                                         |
| `U`     | Change marked text to uppercase         |

## Marks and Positions


| Command        | Action                                               |
|----------------|------------------------------------------------------|
| `:marks`       | List of marks                                        |
|                |                                                      |
| `ma`           | Set current position for mark A                      |
|                |                                                      |
| `` `a ``       | Jump to position of mark A                           |
|                |                                                      |
| `y\`a`         | Yank text to position of mark A                      |
|                |                                                      |
| `` `0 ``       | Go to the position where Vim was previously exited   |
|                |                                                      |
| `` `" ``       | Go to the position when last editing this file       |
|                |                                                      |
| `` `. ``       | Go to the position of the last change in this file   |
|                |                                                      |
| `` `` ``       | Go to the position before the last jump              |
|                |                                                      |
| `:ju[mps]`     | List of jumps                                        |
|                |                                                      |
| `Ctrl + i`     | Go to newer position in jump list                    |
|                |                                                      |
| `Ctrl + o`     | Go to older position in jump list                    |
|                |                                                      |
| `:changes`     | List of changes                                      |
|                |                                                      |
| `g,`           | Go to newer position in change list                  |
|                |                                                      |
| `g;`           | Go to older position in change list                  |
|                |                                                      |
| `Ctrl + ]`     | Jump to the tag under cursor                         |

## Cut and Paste

| Command                  | Action                                                                           |
|--------------------------|----------------------------------------------------------------------------------|
| `yy`                     | Yank (copy) a line                                                               |
|                          |                                                                                  |
| `2yy`                    | Yank (copy) 2 lines                                                              |
|                          |                                                                                  |
| `yw`                     | Yank (copy) the characters of the word from the cursor position to the next word |
|                          |                                                                                  |
| `yiw`                    | Yank (copy) word under the cursor                                                |
|                          |                                                                                  |
| `yaw`                    | Yank (copy) word under the cursor and the space after/before it                  |
|                          |                                                                                  |
| `y$` or `Y`              | Yank (copy) to end of line                                                       |
|                          |                                                                                  |
| `p`                      | Put (paste) the clipboard after cursor                                           |
|                          |                                                                                  |
| `P`                      | Put (paste) before cursor                                                        |
|                          |                                                                                  |
| `gp`                     | Put (paste) the clipboard after cursor and leave cursor after the new text       |
|                          |                                                                                  |
| `gP`                     | Put (paste) before cursor and leave cursor after the new text                    |
|                          |                                                                                  |
| `dd`                     | Delete (cut) a line                                                              |
|                          |                                                                                  |
| `2dd`                    | Delete (cut) 2 lines                                                             |
|                          |                                                                                  |
| `dw`                     | Delete (cut) the characters of the word from the cursor position to the next word|
|                          |                                                                                  |
| `diw`                    | Delete (cut) word under the cursor                                               |
|                          |                                                                                  |
| `daw`                    | Delete (cut) word under the cursor and the space after/before it                 |
|                          |                                                                                  |
| `:3,5d`                  | Delete lines starting from 3 to 5                                                |
|                          |                                                                                  |
| `:g/{pattern}/d`         | Delete all lines containing pattern                                              |
|                          |                                                                                  |
| `:g!/{pattern}/d`        | Delete all lines not containing pattern                                          |
|                          |                                                                                  |
| `d$` or `D`              | Delete (cut) to the end of the line                                              |
|                          |                                                                                  |
| `x`                      | Delete (cut) character                                                           |

## Macros

| Command | Action                  |
|---------|-------------------------|
| `qa`    | Record macro a          |
|         |                         |
| `q`     | Stop recording macro    |
|         |                         |
| `@a`    | Run macro a             |
|         |                         |
| `@@`    | Rerun last run macro    |


## Indent Text


| Command    | Action                                                              |
|------------|---------------------------------------------------------------------|
| `>>`       | Indent (move right) line one shiftwidth                             |
|            |                                                                     |
| `<<`       | De-indent (move left) line one shiftwidth                           |
|            |                                                                     |
| `>%`       | Indent a block with () or {} (cursor on brace)                      |
|            |                                                                     |
| `<%`       | De-indent a block with () or {} (cursor on brace)                   |
|            |                                                                     |
| `>ib`      | Indent inner block with ()                                          |
|            |                                                                     |
| `>at`      | Indent a block with <> tags                                         |
|            |                                                                     |
| `3==`      | Re-indent 3 lines                                                   |
|            |                                                                     |
| `=%`       | Re-indent a block with () or {} (cursor on brace)                   |
|            |                                                                     |
| `=iB`      | Re-indent inner block with {}                                       |
|            |                                                                     |
| `gg=G`     | Re-indent entire buffer                                             |
|            |                                                                     |
| `]p`       | Paste and adjust indent to current line                             |



## Search and Replace

| Command             | Action                                                                 |
|---------------------|------------------------------------------------------------------------|
| `:/pattern`         | Search for pattern                                                     |
|                     |                                                                        |
| `?pattern`          | Search backward for pattern                                            |
|                     |                                                                        |
| `pattern`         | 'Very magic' pattern: non-alphanumeric characters as special regex symbols |
|                     |                                                                        |
| `n`                 | Repeat search in same direction                                        |
|                     |                                                                        |
| `N`                 | Repeat search in opposite direction                                    |
|                     |                                                                        |
| `:%s/old/new/g`     | Replace all old with new throughout file                               |
|                     |                                                                        |
| `:%s/old/new/gc`    | Replace all old with new throughout file with confirmations            |
|                     |                                                                        |
| `:noh[lsearch]`     | Remove highlighting of search matches                                  |


## Diff

| Command             | Action                                                  |
|---------------------|---------------------------------------------------------|
| `zf`                | Manually define a fold up to motion                     |
|                     |                                                         |
| `zd`                | Delete fold under the cursor                            |
|                     |                                                         |
| `za`                | Toggle fold under the cursor                            |
|                     |                                                         |
| `zo`                | Open fold under the cursor                              |
|                     |                                                         |
| `zc`                | Close fold under the cursor                             |
|                     |                                                         |
| `zr`                | Reduce (open) all folds by one level                    |
|                     |                                                         |
| `zm`                | Fold more (close) all folds by one level                |
|                     |                                                         |
| `zi`                | Toggle folding functionality                            |
|                     |                                                         |
| `]c`                | Jump to start of next change                            |
|                     |                                                         |
| `[c`                | Jump to start of previous change                        |
|                     |                                                         |
| `do` or `:diffg[et]`| Obtain (get) difference (from other buffer)             |
|                     |                                                         |
| `dp` or `:diffpu[t]`| Put difference (to other buffer)                        |
|                     |                                                         |
| `:diffthis`         | Make current window part of diff                        |
|                     |                                                         |
| `:dif[fupdate]`     | Update differences                                      |
|                     |                                                         |
| `:diffo[ff]`        | Switch off diff mode for current window                 |

## Working with multiple files

| Command                      | Action                                                                       |
|------------------------------|------------------------------------------------------------------------------|
| `:e[dit] file`               | Edit a file in a new buffer                                                  |
|                              |                                                                              |
| `:bn[ext]`                   | Go to the next buffer                                                        |
|                              |                                                                              |
| `:bp[revious]`               | Go to the previous buffer                                                    |
|                              |                                                                              |
| `:bd[elete]`                 | Delete a buffer (close a file)                                               |
|                              |                                                                              |
| `:b[uffer]#`                 | Go to a buffer by index #                                                    |
|                              |                                                                              |
| `:b[uffer] file`             | Go to a buffer by file                                                       |
|                              |                                                                              |
| `:ls` or `:buffers`          | List all open buffers                                                        |
|                              |                                                                              |
| `:sp[lit] file`              | Open a file in a new buffer and split window                                 |
|                              |                                                                              |
| `:vs[plit] file`             | Open a file in a new buffer and vertically split window                      |
|                              |                                                                              |
| `:vert[ical] ba[ll]`         | Edit all buffers as vertical windows                                        |
|                              |                                                                              |
| `:tab ba[ll]`                | Edit all buffers as tabs                                                     |
|                              |                                                                              |
| `Ctrl + ws`                  | Split window                                                                 |
|                              |                                                                              |
| `Ctrl + wv`                  | Split window vertically                                                      |
|                              |                                                                              |
| `Ctrl + ww`                  | Switch windows                                                               |
|                              |                                                                              |
| `Ctrl + wq`                  | Quit a window                                                                |
|                              |                                                                              |
| `Ctrl + wx`                  | Exchange current window with next one                                        |
|                              |                                                                              |
| `Ctrl + w=`                  | Make all windows equal height & width                                       |
|                              |                                                                              |
| `Ctrl + wh`                  | Move cursor to the left window (vertical split)                              |
|                              |                                                                              |
| `Ctrl + wl`                  | Move cursor to the right window (vertical split)                             |
|                              |                                                                              |
| `Ctrl + wj`                  | Move cursor to the window below (horizontal split)                           |
|                              |                                                                              |
| `Ctrl + wk`                  | Move cursor to the window above (horizontal split)                           |
|                              |                                                                              |
| `Ctrl + wH`                  | Make current window full height at far left (leftmost vertical window)       |
|                              |                                                                              |
| `Ctrl + wL`                  | Make current window full height at far right (rightmost vertical window)     |
|                              |                                                                              |
| `Ctrl + wJ`                  | Make current window full width at the very bottom (bottommost horizontal window) |
|                              |                                                                              |
| `Ctrl + wK`                  | Make current window full width at the very top (topmost horizontal window)   |


## Search in multiple files


| Command                       | Action                                                    |
|-------------------------------|-----------------------------------------------------------|
| `:vim[grep] /pattern/ {file}` | Search for pattern in multiple files                      |
|                               |                                                           |
| `:cn[ext]`                    | Jump to the next match                                    |
|                               |                                                           |
| `:cp[revious]`                | Jump to the previous match                                |
|                               |                                                           |
| `:cope[n]`                    | Open a window containing the list of matches              |
|                               |                                                           |
| `:ccl[ose]`                   | Close the quickfix window                                 |

## Tabs


| Command                          | Action                                                                    |
|----------------------------------|---------------------------------------------------------------------------|
| `:tabnew` or `:tabnew {file}`    | Open a file in a new tab                                                  |
|                                  |                                                                           |
| `Ctrl + wT`                      | Move the current split window into its own tab                            |
|                                  |                                                                           |
| `gt` or `:tabn[ext]`             | Move to the next tab                                                      |
|                                  |                                                                           |
| `gT` or `:tabp[revious]`         | Move to the previous tab                                                  |
|                                  |                                                                           |
| `#gt`                            | Move to tab number #                                                      |
|                                  |                                                                           |
| `:tabm[ove] #`                   | Move current tab to the #th position (indexed from 0)                     |
|                                  |                                                                           |
| `:tabc[lose]`                    | Close the current tab and all its windows                                 |
|                                  |                                                                           |
| `:tabo[nly]`                     | Close all tabs except for the current one                                 |
|                                  |                                                                           |
| `:tabdo command`                 | Run the command on all tabs (e.g., `:tabdo q` - closes all opened tabs)   |


## Exiting


| Command           | Action                                               |
|-------------------|------------------------------------------------------|
| `:w`              | Write (save) the file, but don't exit                |
|                   |                                                      |
| `:w !sudo tee %`  | Write out the current file using sudo                |
|                   |                                                      |
| `:wq` or `:x` or `ZZ` | Write (save) and quit                            |
|                   |                                                      |
| `:q`              | Quit (fails if there are unsaved changes)            |
|                   |                                                      |
| `:q!` or `ZQ`     | Quit and throw away unsaved changes                 |
|                   |                                                      |
| `:wqa`            | Write (save) and quit on all tabs                    |
