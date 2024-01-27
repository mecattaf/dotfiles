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
