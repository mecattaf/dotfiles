set -euo pipefail

publish=false
prepare_only=false
dotfiles_url="https://github.com/mecattaf/dotfiles.git"
base_branch=main
period="$(TZ=Europe/Paris date +%Y-%m)"
cutoff="$(TZ=Europe/Paris date +%F)"
runtime_base="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/local-ai-monthly"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/local-ai-monthly"
tally_program=tally

usage() {
  cat <<'EOF'
usage: local-ai-monthly [options]

  --publish                 push/update the period branch and GitHub PR
  --prepare-only            stop after deterministic Git/HF/Nix preparation
  --period YYYY-MM          override the review period
  --dotfiles-url URL        publication repository
  --base-branch BRANCH      accepted-state branch (default: main)
  --runtime-base PATH       transient run parent
  --state-dir PATH          fixed Tally receipt directory
  --tally PATH              exact tally executable for the nested GPU job
EOF
}

while (($#)); do
  case "$1" in
    --publish)
      publish=true
      shift
      ;;
    --prepare-only)
      prepare_only=true
      shift
      ;;
    --period)
      period="${2:?--period requires YYYY-MM}"
      shift 2
      ;;
    --dotfiles-url)
      dotfiles_url="${2:?--dotfiles-url requires a URL}"
      shift 2
      ;;
    --base-branch)
      base_branch="${2:?--base-branch requires a branch}"
      shift 2
      ;;
    --runtime-base)
      runtime_base="${2:?--runtime-base requires a path}"
      shift 2
      ;;
    --state-dir)
      state_dir="${2:?--state-dir requires a path}"
      shift 2
      ;;
    --tally)
      tally_program="${2:?--tally requires a path}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      printf 'local-ai-monthly: unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

[[ "$period" =~ ^[0-9]{4}-[0-9]{2}$ ]]
[[ "$base_branch" =~ ^[A-Za-z0-9._/-]+$ ]]
[[ "$base_branch" != -* && "$base_branch" != *..* ]]
if [[ "$publish" == true && "$prepare_only" == true ]]; then
  printf 'local-ai-monthly: --publish and --prepare-only are mutually exclusive\n' >&2
  exit 2
fi
github_repo="${dotfiles_url#https://github.com/}"
github_repo="${github_repo%.git}"
if [[ "$publish" == true ]]; then
  [[ "$github_repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]
fi
export GIT_TERMINAL_PROMPT=0
export LC_ALL=C
umask 077

mkdir -p "$runtime_base" "$state_dir"
run_dir="$(mktemp -d "$runtime_base/$period.XXXXXX")"
receipt="$state_dir/last-run.json"
started_at="$(date -u +%FT%TZ)"
status=running
error=''
dotfiles_commit=''
prepared=''
enriched=''
finalized=''
commentary=''
pr_url=''
model_id=''
manifest_path=''

digest_or_empty() {
  if [[ -f "$1" ]]; then
    sha256sum "$1" | cut -d' ' -f1
  else
    printf ''
  fi
}

write_receipt() {
  local completed_at sources_json receipt_tmp
  completed_at="$(date -u +%FT%TZ)"
  sources_json='[]'
  if [[ -n "$manifest_path" && -f "$manifest_path" ]]; then
    sources_json="$(jq '[.sources[] | {
      slug, baseline, observed_head: .head, status, commit_count,
      relevant_path_count: (.relevant_paths | length)
    }]' "$manifest_path")"
  fi
  receipt_tmp="$receipt.tmp"
  jq -n \
    --arg period "$period" \
    --arg run_dir "$run_dir" \
    --arg started_at "$started_at" \
    --arg completed_at "$completed_at" \
    --arg status "$status" \
    --arg error "$error" \
    --arg dotfiles_commit "$dotfiles_commit" \
    --arg prepared "$prepared" \
    --arg enriched "$enriched" \
    --arg finalized "$finalized" \
    --arg model_id "$model_id" \
    --arg commentary_sha256 "$(digest_or_empty "$commentary")" \
    --arg pr_url "$pr_url" \
    --argjson sources "$sources_json" \
    '{
      schema_version: 2,
      period: $period,
      run_dir: $run_dir,
      started_at: $started_at,
      completed_at: $completed_at,
      status: $status,
      error: (if $error == "" then null else $error end),
      dotfiles_commit: (if $dotfiles_commit == "" then null else $dotfiles_commit end),
      model_id: (if $model_id == "" then null else $model_id end),
      prepared_store_path: (if $prepared == "" then null else $prepared end),
      enriched_store_path: (if $enriched == "" then null else $enriched end),
      finalized_store_path: (if $finalized == "" then null else $finalized end),
      commentary_sha256: (if $commentary_sha256 == "" then null else $commentary_sha256 end),
      sources: $sources,
      pr_url: (if $pr_url == "" then null else $pr_url end),
      no_model_blobs: true
    }' > "$receipt_tmp"
  mv "$receipt_tmp" "$receipt"
}

on_exit() {
  local code=$?
  trap - EXIT
  if ((code != 0)); then
    status=failed
    error="workflow exited with status $code"
  fi
  write_receipt
  if ((code == 0)); then
    printf 'receipt: %s\n' "$receipt"
  else
    printf 'local-ai-monthly: failed; receipt: %s\n' "$receipt" >&2
  fi
  exit "$code"
}
trap on_exit EXIT
write_receipt

dotfiles="$run_dir/dotfiles"
capture="$run_dir/capture"
clones="$run_dir/sources"
hf_capture="$run_dir/hf-capture"
mkdir -p "$capture" "$hf_capture"

git clone --filter=blob:none --single-branch --branch "$base_branch" \
  "$dotfiles_url" "$dotfiles" >/dev/null
dotfiles_commit="$(git -C "$dotfiles" rev-parse HEAD)"
[[ "$dotfiles_commit" =~ ^[0-9a-f]{40}$ ]]
registry="$dotfiles/pkgs/local-ai-monthly/sources.json"
jq -e '.schema_version == 1' "$registry" >/dev/null

"$LOCAL_AI_CAPTURE" "$registry" "$period" "$cutoff" "$dotfiles_commit" \
  "$capture" "$clones"
manifest_path="$capture/manifest.json"

changed_count="$(jq '[.sources[] | select(.head != .baseline)] | length' "$manifest_path")"
if ((changed_count == 0)); then
  status=no-delta
  printf 'local-ai-monthly: every source is already at its accepted pin\n'
  exit 0
fi

nix eval --json --no-write-lock-file "path:$dotfiles#lib.localModelCatalog" \
  > "$capture/catalog.json"
endpoint="$(jq -r '.inference.url' "$registry")"
models_url="${endpoint%/}"
if [[ "$models_url" != */v1 ]]; then
  models_url="$models_url/v1"
fi
curl --silent --show-error --fail --connect-timeout 10 --max-time 30 \
  --header 'Accept: application/json' \
  "$models_url/models" > "$capture/models.json"
jq -e '.data | type == "array" and length > 0' "$capture/models.json" >/dev/null

: > "$capture/accepted-tally.md"
shopt -s nullglob
tallies=("$dotfiles"/docs/local-ai/tallies/[0-9][0-9][0-9][0-9]-[0-9][0-9]*.md)
if ((${#tallies[@]} > 0)); then
  cp "${tallies[-1]}" "$capture/accepted-tally.md"
fi
shopt -u nullglob

prepared="$(nix build --offline --no-link --print-out-paths \
  --file "$LOCAL_AI_STAGES" \
  --argstr system "$LOCAL_AI_STAGE_SYSTEM" \
  --argstr bashPath "$LOCAL_AI_STAGE_BASH" \
  --argstr pureStagePath "$LOCAL_AI_PURE_STAGE" \
  --argstr phase prepare \
  --arg registry "$registry" \
  --arg capture "$capture")"
[[ -d "$prepared" ]]

hf_response_limit="$(jq -r '.limits.hf_metadata_response_bytes // 5000000' "$registry")"
"$LOCAL_AI_HF_CAPTURE" "$prepared/hf-requests.json" "$hf_capture" "$hf_response_limit"
enriched="$(nix build --offline --no-link --print-out-paths \
  --file "$LOCAL_AI_STAGES" \
  --argstr system "$LOCAL_AI_STAGE_SYSTEM" \
  --argstr bashPath "$LOCAL_AI_STAGE_BASH" \
  --argstr pureStagePath "$LOCAL_AI_PURE_STAGE" \
  --argstr phase enrich \
  --arg registry "$registry" \
  --arg capture "$prepared" \
  --arg hfCapture "$hf_capture")"
[[ -d "$enriched" ]]

if [[ "$prepare_only" == true ]]; then
  status=prepared
  printf 'prepared evidence: %s\n' "$enriched"
  exit 0
fi

provider="$(jq -r '.provider' "$enriched/model.json")"
model_id="$(jq -r '.model_id' "$enriched/model.json")"
endpoint="$(jq -r '.endpoint' "$enriched/model.json")"
model_timeout="$(jq -r '.limits.model_timeout_seconds' "$registry")"
commentary="$run_dir/pr-commentary.md"
pi_state="$run_dir/pi-state"
evidence_digest="$(sha256sum "$enriched/evidence.md" "$enriched/context.md" "$enriched/hf-metadata.md" \
  | sha256sum | cut -d' ' -f1)"

if [[ -z "${TALLY_SOCKET:-}" || -z "${TALLY_JOB_ID:-}" ]]; then
  printf 'local-ai-monthly: the Pi step requires a parent Tally job with child enqueue capability\n' >&2
  exit 1
fi
"$tally_program" --socket "$TALLY_SOCKET" enqueue \
  --source orchestrator \
  --pool worker-gpu \
  --priority low \
  --dedup-key "local-ai-judge-$period-${evidence_digest:0:20}" \
  --runtime-max-sec "$model_timeout" \
  --no-enqueue \
  --wait \
  --evidence exit:0 \
  --evidence "artifact:$commentary" \
  --evidence hash:sha256 \
  -- "$LOCAL_AI_JUDGE" \
    "$LOCAL_AI_PROMPT" \
    "$enriched/evidence.md" \
    "$enriched/context.md" \
    "$enriched/hf-metadata.md" \
    "$provider" "$model_id" "$endpoint" "$commentary" "$pi_state"

finalized="$(nix build --offline --no-link --print-out-paths \
  --file "$LOCAL_AI_STAGES" \
  --argstr system "$LOCAL_AI_STAGE_SYSTEM" \
  --argstr bashPath "$LOCAL_AI_STAGE_BASH" \
  --argstr pureStagePath "$LOCAL_AI_PURE_STAGE" \
  --argstr phase finalize \
  --arg registry "$registry" \
  --arg capture "$enriched" \
  --arg commentary "$commentary")"
[[ -d "$finalized" ]]

if [[ "$publish" != true ]]; then
  status=preview
  printf 'commentary: %s\n' "$commentary"
  printf 'final candidate: %s\n' "$finalized"
  exit 0
fi

branch="automation/local-ai-review-$period"
pr_tree="$run_dir/pr-tree"
git -C "$dotfiles" worktree add -b "$branch" "$pr_tree" "origin/$base_branch" >/dev/null
cp "$finalized/next-sources.json" "$pr_tree/pkgs/local-ai-monthly/sources.json"
git -C "$pr_tree" add -- pkgs/local-ai-monthly/sources.json
mapfile -t staged < <(git -C "$pr_tree" diff --cached --name-only)
if ((${#staged[@]} != 1)) || [[ "${staged[0]}" != pkgs/local-ai-monthly/sources.json ]]; then
  printf 'local-ai-monthly: publication scope violation\n' >&2
  exit 1
fi
git -C "$pr_tree" diff --cached --check
jq -e '.schema_version == 1' "$pr_tree/pkgs/local-ai-monthly/sources.json" >/dev/null
nix build --no-link --no-write-lock-file "path:$pr_tree#local-ai-monthly"

git -C "$pr_tree" commit -m "chore(local-ai): advance $period review pins"
remote_sha="$(git -C "$pr_tree" ls-remote --heads origin "refs/heads/$branch" | cut -f1)"
if [[ -n "$remote_sha" ]]; then
  [[ "$remote_sha" =~ ^[0-9a-f]{40}$ ]]
  git -C "$pr_tree" push \
    "--force-with-lease=refs/heads/$branch:$remote_sha" \
    origin "HEAD:refs/heads/$branch"
else
  git -C "$pr_tree" push --set-upstream origin "$branch"
fi

title="chore(local-ai): $period source review"
existing="$(gh pr list --repo "$github_repo" --head "$branch" --state open --limit 1 \
  --json number,url 2>/dev/null || printf '[]')"
existing_number="$(jq -r '.[0].number // empty' <<<"$existing")"
if [[ -n "$existing_number" ]]; then
  gh pr edit --repo "$github_repo" "$existing_number" --title "$title" \
    --body-file "$finalized/pr-body.md" >/dev/null
  pr_url="$(jq -r '.[0].url' <<<"$existing")"
else
  pr_url="$(gh pr create --repo "$github_repo" \
    --base "$base_branch" \
    --head "$branch" \
    --title "$title" \
    --body-file "$finalized/pr-body.md")"
fi

status=published
printf 'pull request: %s\n' "$pr_url"
