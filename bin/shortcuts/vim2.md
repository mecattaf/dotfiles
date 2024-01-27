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

