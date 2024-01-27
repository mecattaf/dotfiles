#!/bin/bash

notify() {
    if [ $? -eq 0 ]; then
        notify-send "Success" "$1 successfully updated."
    else
        notify-send "Error" "$1 failed to update."
    fi
}

echo "Updating dotfiles..."
git -C ~/dotfiles pull origin master
notify "Dotfiles"

echo "Updating Neovim configuration..."
git -C ~/dotfiles/nvim pull origin master
notify "Neovim Configuration"

notify-send "Update Operation" "Update operation completed."
