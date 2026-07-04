#!/usr/bin/env bash
# Standalone font installer — extracted from BlueBuild fonts module.
# Reads fonts.json from the same directory and dispatches to source scripts.
# Usage: /ctx/build/fonts/install-fonts.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FONTS_JSON="$(cat "${SCRIPT_DIR}/fonts.json")"

for SOURCE in "${SCRIPT_DIR}"/sources/*.sh; do
    chmod +x "${SOURCE}"

    FILENAME=$(basename -- "${SOURCE}")
    ARRAY_NAME="${FILENAME%.*}"

    if [ "${ARRAY_NAME}" = "url-fonts" ]; then
        FONTS_SUBSET=$(echo "${FONTS_JSON}" | jq -c --arg k "${ARRAY_NAME}" 'try .[$k]')
        if [ "${FONTS_SUBSET}" != "null" ] && [ "${FONTS_SUBSET}" != "[]" ]; then
            echo "==> Installing ${ARRAY_NAME}..."
            bash "${SOURCE}" "${FONTS_SUBSET}"
        fi
    else
        readarray -t FONTS < <(echo "${FONTS_JSON}" | jq -c -r --arg k "${ARRAY_NAME}" 'try .[$k][]')
        if [ ${#FONTS[@]} -gt 0 ]; then
            echo "==> Installing ${ARRAY_NAME}..."
            bash "${SOURCE}" "${FONTS[@]}"
        fi
    fi
done

echo "==> All fonts installed."
