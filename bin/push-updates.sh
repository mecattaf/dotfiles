#!/bin/bash

commit_message="Update dotfiles"
notify() {
    if [ $? -eq 0 ]; then
        notify-send "Success" "$1 successfully pushed."
    else
        notify-send "Error" "$1 failed to push."
    fi
}

echo "Committing and pushing dotfiles..."
git -C ~/dotfiles add .
git -C ~/dotfiles commit -m "$commit_message"
git -C ~/dotfiles push origin master
notify "Dotfiles"

echo "Committing and pushing Neovim configuration..."
git -C ~/dotfiles/nvim add .
git -C ~/dotfiles/nvim commit -m "$commit_message"
git -C ~/dotfiles/nvim push origin master
notify "Neovim Configuration"

notify-send "Push Operation" "Push operation completed."
