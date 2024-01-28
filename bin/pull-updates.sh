#!/bin/bash

notify() {
    if [ $? -eq 0 ]; then
        notify-send "Success" "Dotfiles successfully updated."
    else
        notify-send "Error" "Dotfiles update failed."
    fi
}

echo "Updating dotfiles..."
git -C ~/dotfiles pull origin master
notify
