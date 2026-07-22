set -euo pipefail

registry="${1:?usage: local-ai-monthly-capture <registry.json> <period> <cutoff> <dotfiles-commit> <capture-dir> <clone-dir>}"
period="${2:?}"
cutoff="${3:?}"
dotfiles_commit="${4:?}"
capture_dir="${5:?}"
clone_dir="${6:?}"

export GIT_TERMINAL_PROMPT=0
export LC_ALL=C
umask 077

[[ "$period" =~ ^[0-9]{4}-[0-9]{2}$ ]]
[[ "$cutoff" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]
[[ "$dotfiles_commit" =~ ^[0-9a-f]{40}$ ]]
jq -e '
  .schema_version == 1
  and (.sources | type == "array" and length > 0)
  and all(.sources[];
    (.slug | type == "string" and length > 0)
    and (.url | type == "string" and startswith("https://github.com/"))
    and (.baseline | test("^[0-9a-f]{40}$")))
' "$registry" >/dev/null

mkdir -p "$capture_dir/sources" "$clone_dir"

manifest_tmp="$capture_dir/manifest.json.tmp"
jq -n \
  --arg period "$period" \
  --arg cutoff "$cutoff" \
  --arg dotfiles_commit "$dotfiles_commit" \
  '{
    schema_version: 1,
    period: $period,
    cutoff: $cutoff,
    dotfiles_commit: $dotfiles_commit,
    sources: []
  }' > "$manifest_tmp"
mv "$manifest_tmp" "$capture_dir/manifest.json"

matches_any() {
  local candidate="$1"
  shift
  local pattern
  for pattern in "$@"; do
    # Registry entries are reviewed Git path globs; expansion is intentional.
    # shellcheck disable=SC2053
    if [[ "$candidate" == $pattern ]]; then
      return 0
    fi
  done
  return 1
}

json_lines() {
  jq -Rsc 'split("\n") | map(select(length > 0))' "$1"
}

resolve_head() {
  local repository="$1"
  local ref sha
  for ref in refs/remotes/origin/HEAD origin/main origin/master HEAD; do
    sha="$(git -C "$repository" rev-parse "$ref" 2>/dev/null || true)"
    if [[ "$sha" =~ ^[0-9a-f]{40}$ ]]; then
      printf '%s\n' "$sha"
      return 0
    fi
  done
  return 1
}

clone_repository() {
  local url="$1"
  local prefix="$2"
  local log_dir="$3"
  local attempt candidate
  for attempt in 1 2; do
    candidate="${prefix}-attempt${attempt}"
    if git clone --filter=blob:none --no-checkout --no-tags "$url" "$candidate" \
      > "$log_dir/clone-attempt${attempt}.log" 2>&1; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

source_index=0
while IFS= read -r encoded; do
  source_json="$(printf '%s' "$encoded" | base64 --decode)"
  enabled="$(jq -r '.enabled // false' <<<"$source_json")"
  cadence="$(jq -r '.cadence // "never"' <<<"$source_json")"
  if [[ "$enabled" != true || "$cadence" == "never" || "$cadence" == "on-demand" ]]; then
    continue
  fi

  source_index=$((source_index + 1))
  slug="$(jq -r '.slug' <<<"$source_json")"
  url="$(jq -r '.url' <<<"$source_json")"
  baseline="$(jq -r '.baseline' <<<"$source_json")"
  processor="$(jq -r '.processor // "generic"' <<<"$source_json")"
  safe_slug="${slug//\//--}"
  [[ "$safe_slug" =~ ^[A-Za-z0-9._-]+$ ]]

  source_dir_rel="sources/$(printf '%03d' "$source_index")-$safe_slug"
  source_dir="$capture_dir/$source_dir_rel"
  mkdir -p "$source_dir"

  if ! repository="$(clone_repository "$url" "$clone_dir/$safe_slug" "$source_dir")"; then
    printf 'local-ai-monthly: clone failed twice: %s\n' "$slug" >&2
    exit 1
  fi
  head="$(resolve_head "$repository")"
  observed_at="$(date -u +%FT%TZ)"
  [[ "$head" =~ ^[0-9a-f]{40}$ ]]

  if ! git -C "$repository" cat-file -e "$baseline^{commit}" 2>/dev/null; then
    git -C "$repository" fetch --filter=blob:none --no-tags origin "$baseline" >/dev/null
  fi
  git -C "$repository" cat-file -e "$baseline^{commit}"
  if ! git -C "$repository" merge-base --is-ancestor "$baseline" "$head"; then
    printf 'local-ai-monthly: accepted pin is not an ancestor: %s %s..%s\n' \
      "$slug" "$baseline" "$head" >&2
    exit 1
  fi

  git -C "$repository" diff --name-only -z "$baseline" "$head" > "$source_dir/changed.zlist"
  : > "$source_dir/changed.txt"
  : > "$source_dir/relevant.txt"
  mapfile -d '' -t changed_paths < "$source_dir/changed.zlist"
  mapfile -t watched_paths < <(jq -r '.watched_paths[]? // empty' <<<"$source_json")
  mapfile -t ignored_paths < <(jq -r '.ignore_paths[]? // empty' <<<"$source_json")
  mapfile -t evidence_paths < <(jq -r '.evidence_paths[]? // empty' <<<"$source_json")

  for path in "${changed_paths[@]}"; do
    if [[ "$path" == *$'\n'* || "$path" == *$'\r'* ]]; then
      printf 'local-ai-monthly: unsupported newline in Git path for %s\n' "$slug" >&2
      exit 1
    fi
    printf '%s\n' "$path" >> "$source_dir/changed.txt"
    if ! matches_any "$path" "${watched_paths[@]}"; then
      continue
    fi
    if ((${#ignored_paths[@]} > 0)) && matches_any "$path" "${ignored_paths[@]}"; then
      continue
    fi
    if ((${#evidence_paths[@]} > 0)) && ! matches_any "$path" "${evidence_paths[@]}"; then
      continue
    fi
    printf '%s\n' "$path" >> "$source_dir/relevant.txt"
  done

  mapfile -t relevant_paths < "$source_dir/relevant.txt"
  commit_count="$(git -C "$repository" rev-list --count "$baseline..$head")"
  [[ "$commit_count" =~ ^[0-9]+$ ]]
  status=irrelevant
  if [[ "$head" == "$baseline" ]]; then
    status=no-delta
  elif ((${#relevant_paths[@]} > 0)); then
    status=relevant
  fi

  commit_limit="$(jq -r '.limits.commit_log' "$registry")"
  [[ "$commit_limit" =~ ^[1-9][0-9]*$ ]]
  git -C "$repository" log \
    "--max-count=$commit_limit" \
    '--format=%H%x1f%cI%x1f%s' \
    "$baseline..$head" > "$source_dir/commits.tsv"
  git -C "$repository" log \
    "--max-count=$commit_limit" \
    --numstat '--format=commit%x1f%H%x1f%cI%x1f%s' \
    "$baseline..$head" -- "${relevant_paths[@]}" > "$source_dir/numstat.txt"

  : > "$source_dir/diff.patch"
  : > "$source_dir/pickaxe.tsv"
  if [[ "$status" == relevant ]]; then
    max_blob_bytes="$(jq -r '.limits.max_diff_blob_bytes // 2000000' "$registry")"
    max_raw_bytes="$(jq -r '.limits.max_raw_diff_bytes // 8000000' "$registry")"
    [[ "$max_blob_bytes" =~ ^[1-9][0-9]*$ ]]
    [[ "$max_raw_bytes" =~ ^[1-9][0-9]*$ ]]
    oversized=false
    for path in "${relevant_paths[@]}"; do
      for revision in "$baseline" "$head"; do
        size="$(git -C "$repository" cat-file -s "$revision:$path" 2>/dev/null || printf '0')"
        [[ "$size" =~ ^[0-9]+$ ]]
        if ((size > max_blob_bytes)); then
          oversized=true
        fi
      done
    done
    if [[ "$oversized" == true ]]; then
      status=needs-split
      printf 'Evidence omitted: at least one changed blob exceeds %s bytes.\n' \
        "$max_blob_bytes" > "$source_dir/diff.patch"
    else
      raw_diff="$repository/local-ai-monthly-diff.patch"
      git -C "$repository" diff --no-ext-diff --unified=8 \
        "$baseline" "$head" -- "${relevant_paths[@]}" > "$raw_diff"
      raw_bytes="$(wc -c < "$raw_diff")"
      if ((raw_bytes > max_raw_bytes)); then
        status=needs-split
        head -c "$max_raw_bytes" "$raw_diff" > "$source_dir/diff.patch"
      else
        cp "$raw_diff" "$source_dir/diff.patch"
      fi
    fi

    {
      rg -o 'https://huggingface\.co/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+' \
        "$source_dir/diff.patch" 2>/dev/null || true
    } | sed -E 's#^https://huggingface\.co/##; s#\.git$##' | sort -u \
      > "$source_dir/hf-repositories.txt"
    while IFS= read -r hf_repository; do
      [[ -n "$hf_repository" ]] || continue
      while IFS= read -r commit_row; do
        printf '%s\x1f%s\n' "$hf_repository" "$commit_row"
      done < <(
        git -C "$repository" log \
          "--max-count=$commit_limit" \
          "-S$hf_repository" \
          '--format=%H%x1f%cI%x1f%s' \
          "$baseline..$head" -- "${relevant_paths[@]}"
      )
    done < "$source_dir/hf-repositories.txt" > "$source_dir/pickaxe.tsv"
  fi

  : > "$source_dir/packages-before.txt"
  : > "$source_dir/packages-after.txt"
  if [[ "$processor" == llm-agents-nix ]]; then
    git -C "$repository" ls-tree -d --name-only "$baseline" packages/ \
      | sed 's#^packages/##' | sort -u > "$source_dir/packages-before.txt"
    git -C "$repository" ls-tree -d --name-only "$head" packages/ \
      | sed 's#^packages/##' | sort -u > "$source_dir/packages-after.txt"
  fi

  row="$(jq -n \
    --arg slug "$slug" \
    --arg url "$url" \
    --arg baseline "$baseline" \
    --arg head "$head" \
    --arg status "$status" \
    --arg observed_at "$observed_at" \
    --arg processor "$processor" \
    --arg dir "$source_dir_rel" \
    --argjson commit_count "$commit_count" \
    --argjson changed_paths "$(json_lines "$source_dir/changed.txt")" \
    --argjson relevant_paths "$(json_lines "$source_dir/relevant.txt")" \
    '{
      slug: $slug,
      url: $url,
      baseline: $baseline,
      head: $head,
      observed_at: $observed_at,
      status: $status,
      processor: $processor,
      dir: $dir,
      commit_count: $commit_count,
      changed_paths: $changed_paths,
      relevant_paths: $relevant_paths
    }')"
  jq --argjson row "$row" '.sources += [$row]' "$capture_dir/manifest.json" \
    > "$manifest_tmp"
  mv "$manifest_tmp" "$capture_dir/manifest.json"
done < <(jq -r '.sources[] | @base64' "$registry")

jq -e '.sources | length > 0' "$capture_dir/manifest.json" >/dev/null
