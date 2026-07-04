#!/usr/bin/env bash
# Standalone kargs injector — extracted from BlueBuild kargs module.
# Writes kernel arguments to /usr/lib/bootc/kargs.d/ for bootc to apply on boot.
# Usage: /ctx/build/kargs/set-kargs.sh
# Docs: https://bootc-dev.github.io/bootc/building/kernel-arguments.html
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$(cat "${SCRIPT_DIR}/kargs.json")"

KARGS_D="/usr/lib/bootc/kargs.d"
TOML_FILE="${KARGS_D}/custom-kargs.toml"

if ! command -v bootc &> /dev/null; then
  echo "ERROR: 'bootc' is not installed — required for kargs.d injection."
  exit 1
fi

readarray -t KARGS < <(echo "${CONFIG}" | jq -r '.kargs[]')
ARCH=$(echo "${CONFIG}" | jq -r '.arch // empty')

if [[ ${#KARGS[@]} -eq 0 ]]; then
  echo "ERROR: No kernel arguments found in kargs.json."
  exit 1
fi

mkdir -p "${KARGS_D}"

# If file already exists, append with a numeric suffix
if [[ -f "${TOML_FILE}" ]]; then
  counter=1
  while [[ -f "${KARGS_D}/custom-kargs-${counter}.toml" ]]; do
    counter=$((counter + 1))
  done
  TOML_FILE="${KARGS_D}/custom-kargs-${counter}.toml"
fi

formatted_kargs=$(printf '"%s", ' "${KARGS[@]}")
formatted_kargs=${formatted_kargs%, }

echo "Writing kernel arguments to ${TOML_FILE}: ${formatted_kargs}"
echo "kargs = [${formatted_kargs}]" > "${TOML_FILE}"

if [[ -n "${ARCH}" ]]; then
  formatted_arch=$(echo "${ARCH}" | sed 's/[^, ]\+/"&"/g')
  echo "Architecture filter: ${formatted_arch}"
  echo "match-architectures = [${formatted_arch}]" >> "${TOML_FILE}"
fi

echo "==> Kernel arguments injected."
