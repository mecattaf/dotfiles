#!/usr/bin/env bash
#
# Install Claude Code CLI system-wide for BlueBuild (x86_64 only)

set -euo pipefail

GCS_BUCKET="https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases"

# Use 'stable' NOT 'latest'
VERSION=$(curl -fsSL "$GCS_BUCKET/stable")

echo "Claude Code version: $VERSION"

# Download to /tmp first (always writable), then install
curl -fsSL -o /tmp/claude "$GCS_BUCKET/$VERSION/linux-x64/claude"
chmod +x /tmp/claude

# Install to /usr/local/bin
install -m 755 /tmp/claude /usr/local/bin/claude

# Cleanup
rm -f /tmp/claude

echo "Claude Code $VERSION installed to /usr/local/bin/claude"
