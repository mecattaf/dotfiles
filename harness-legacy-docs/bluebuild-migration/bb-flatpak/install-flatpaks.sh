#!/usr/bin/env bash
# Build-time script: installs user-scope flatpak runtime components into the image.
# Reads flatpaks.json, copies config + systemd units + runtime scripts.
# Usage: /ctx/build/flatpak/install-flatpaks.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${SCRIPT_DIR}/flatpaks.json"

SHARE_DIR="/usr/share/flatpak-manager"
LIBEXEC_DIR="/usr/libexec/flatpak-manager"

# Validate config
CONFIGS=$(jq -r '.configurations | length' "${CONFIG}")
if [[ "${CONFIGS}" -eq 0 ]]; then
  echo "ERROR: No flatpak configurations found in flatpaks.json."
  exit 1
fi

echo "Found ${CONFIGS} flatpak configuration(s)"

for i in $(seq 0 $((CONFIGS - 1))); do
  REPO_TITLE=$(jq -r ".configurations[${i}].repo.title" "${CONFIG}")
  COUNT=$(jq -r ".configurations[${i}].install | length" "${CONFIG}")
  echo "  - ${COUNT} user flatpak(s) from ${REPO_TITLE}"
done

# Copy config into image
mkdir -p "${SHARE_DIR}"
cp "${CONFIG}" "${SHARE_DIR}/flatpaks.json"

# Copy runtime scripts
mkdir -p "${LIBEXEC_DIR}"
cp "${SCRIPT_DIR}/runtime/user-flatpak-setup" "${LIBEXEC_DIR}/"
chmod +x "${LIBEXEC_DIR}/user-flatpak-setup"

# Copy CLI tool
cp "${SCRIPT_DIR}/runtime/flatpak-manager" /usr/bin/flatpak-manager
chmod +x /usr/bin/flatpak-manager

# Install systemd units
mkdir -p /usr/lib/systemd/user
cp "${SCRIPT_DIR}/runtime/user-flatpak-setup.service" /usr/lib/systemd/user/
cp "${SCRIPT_DIR}/runtime/user-flatpak-setup.timer" /usr/lib/systemd/user/

# Enable user timer globally
systemctl enable --force --global user-flatpak-setup.timer

echo "==> Flatpak management installed. User flatpaks will be installed on first boot."
