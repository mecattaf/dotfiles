set -euo pipefail

if [[ -n "${XDG_STATE_HOME:-}" ]]; then
  call_diarize_state="${XDG_STATE_HOME}/call-diarize"
else
  : "${HOME:?HOME is required when XDG_STATE_HOME is unset}"
  call_diarize_state="${HOME}/.local/state/call-diarize"
fi

call_diarize_venv="${call_diarize_state}/venv"
call_diarize_marker="${call_diarize_state}/venv.lock-id"
mkdir -p "${call_diarize_state}"

call_diarize_current_marker=""
if [[ -f "${call_diarize_marker}" ]]; then
  call_diarize_current_marker="$(<"${call_diarize_marker}")"
fi

if [[ ! -x "${call_diarize_venv}/bin/python" ]] ||
   [[ "${call_diarize_current_marker}" != "${CALL_DIARIZE_LOCK_ID}" ]]; then
  echo "call-diarize: materializing pinned Python environment in ${call_diarize_venv}" >&2
  UV_NO_PROGRESS=1 \
    UV_PROJECT_ENVIRONMENT="${call_diarize_venv}" \
    UV_PYTHON="${CALL_DIARIZE_PYTHON}" \
    uv sync \
      --project "${CALL_DIARIZE_PROJECT}" \
      --frozen \
      --offline \
      --no-install-project \
      --python "${CALL_DIARIZE_PYTHON}"
  printf '%s\n' "${CALL_DIARIZE_LOCK_ID}" >"${call_diarize_marker}"
fi

# nix-strix-halo's ROCm wheel bundle carries an exact loader search path in
# this setup hook. It is immutable and part of the package closure.
source "${CALL_DIARIZE_TORCH_ROOT}/nix-support/setup-hook"
export CALL_DIARIZE_STATE_ROOT="${call_diarize_state}"
# Bound cold-cache host staging to one shard read at a time before the complete
# model moves into Strix Halo's unified GTT allocation.
export HF_DEACTIVATE_ASYNC_LOAD=1
export HF_DATASETS_OFFLINE=1
export HF_HUB_OFFLINE=1
export PYTHONNOUSERSITE=1
export PYTHONPATH="${CALL_DIARIZE_PYTHONPATH}${PYTHONPATH:+:${PYTHONPATH}}"
export TOKENIZERS_PARALLELISM=false
export TRANSFORMERS_OFFLINE=1

exec "${call_diarize_venv}/bin/python" -m call_diarize.cli "$@"
