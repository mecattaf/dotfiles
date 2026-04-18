if [ "$(hostname)" != "harness-desktop" ]; then
    alias desk='kitten ssh harness-desktop -t shpool attach main'
fi
