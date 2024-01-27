
## Shared Bindings

| Key               | Action                                                       |
|-------------------|--------------------------------------------------------------|
| `Tab`             | Completes the current token.                                 |
|                   |                                                              |
| `Shift+Tab`       | Completes the current token and starts the pager’s search mode. |
|                   |                                                              |
| `Left` / `Right`  | Move the cursor left or right by one character. Accepts the autosuggestion if available. |
|                   |                                                              |
| `Enter`           | Executes the current command line or inserts a newline if it’s not complete. |
|                   |                                                              |
| `Alt+Enter`       | Inserts a newline at the cursor position.                    |
|                   |                                                              |
| `Alt+Left` / `Alt+Right` | Move the cursor one word left or right, or moves in the directory history. Accepts the first word of the autosuggestion if available. |
|                   |                                                              |
| `Ctrl+Left` / `Ctrl+Right` | Move the cursor one word left or right, accepting one word of the autosuggestion. |
|                   |                                                              |
| `Shift+Left` / `Shift+Right` | Move the cursor one word left or right, without stopping on punctuation. Accepts one big word of the autosuggestion. |
|                   |                                                              |
| `Up` / `Down`     | Search the command history for the previous/next command.     |
|                   |                                                              |
| `Alt+Up` / `Alt+Down` | Search the command history for the previous/next token.    |
|                   |                                                              |
| `Ctrl+C`       | Interrupt/kill whatever is running (SIGINT).                 |
|                   |                                                              |
| `Ctrl+D`       | Delete one character right of the cursor or exit fish if command line is empty. |
|                   |                                                              |
| `Ctrl+U`       | Removes contents from the beginning of line to the cursor.    |
|                   |                                                              |
| `Ctrl+L`       | Clears and repaints the screen.                              |
|                   |                                                              |
| `Ctrl+W`       | Removes the previous path component.                          |
|                   |                                                              |
| `Ctrl+X`       | Copies the current buffer to the system’s clipboard.          |
|                   |                                                              |
| `Ctrl+V`       | Inserts the clipboard contents.                              |
|                   |                                                              |
| `Alt+D`           | Moves the next word to the Copy and paste (Kill Ring).        |
|                   |                                                              |
| `Alt+H` / `F1`    | Shows the manual page for the current command.                |
|                   |                                                              |
| `Alt+L`           | Lists the contents of the current or specified directory.     |
|                   |                                                              |
| `Alt+O`           | Opens the file at the cursor in a pager.                      |
|                   |                                                              |
| `Alt+P`           | Adds `&| less;` to the end of the job under the cursor.        |
|                   |                                                              |
| `Alt+W`           | Prints a short description of the command under the cursor.   |
|                   |                                                              |
| `Alt+E` / `Alt+V` | Edit the current command line in an external editor.          |
|                   |                                                              |
| `Alt+S`           | Prepends `sudo` to the current command line.                  |
|                   |                                                              |
| `Ctrl+Space`   | Inserts a space without expanding an abbreviation.            |

## Emacs Mode Commands

| Key               | Action                                                       |
|-------------------|--------------------------------------------------------------|
|                   |                                                              |
| `Home` / `Ctrl+A` | Moves the cursor to the beginning of the line.            |
|                   |                                                              |
| `End` / `Ctrl+E` | Moves to the end of line. Accepts autosuggestion if available. |
|                   |                                                              |
| `Ctrl+B` / `Ctrl+F` | Move the cursor one character left or right.            |
|                   |                                                              |
| `Ctrl+N` / `Ctrl+P` | Move the cursor up/down or through history.             |
|                   |                                                              |
| `Delete` / `Backspace` | Removes one character forwards or backwards.              |
|                   |                                                              |
| `Alt+Backspace`   | Removes one word backwards.                                  |
|                   |                                                              |
| `Alt+<` / `Alt+>` | Moves to the beginning/end of the command line.              |
|                   |                                                              |
| `Ctrl+K`       | Deletes from the cursor to the end of line.                  |
|                   |                                                              |
| `Escape` / `Ctrl+G` | Cancels the current operation. Undoes unambiguous completion. |
|                   |                                                              |
| `Alt+C`           | Capitalizes the current word.                                |
|                   |                                                              |
| `Alt+U`           | Makes the current word uppercase.                            |
|                   |                                                              |
| `Ctrl+T`       | Transposes the last two characters.                          |
|                   |                                                              |
| `Alt+T`           | Transposes the last two words.                               |
|                   |                                                              |
| `Ctrl+Z` / `Ctrl+_` | Undo the most recent edit of the line.                |
|                   |                                                              |
| `Alt+/`           | Reverts the most recent undo.                                |
|                   |                                                              |
| `Ctrl+R`       | Opens the history in a pager.                                |

## Additional Shortcuts

| Key           | Action                                        |
|---------------|-----------------------------------------------|
| `Alt+Up` / `Alt+Down` | Switch to the previous/next arguments. |
|               |                                           |
| `Alt+.`       | Repeat last argument.                         |
