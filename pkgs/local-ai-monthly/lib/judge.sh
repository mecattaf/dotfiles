set -euo pipefail

exec python3 "${LOCAL_AI_JUDGE_PYTHON:?}" "$@"
