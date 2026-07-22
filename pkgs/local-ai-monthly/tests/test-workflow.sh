set -euo pipefail

work="$(mktemp -d)"
registry="$work/sources.json"
capture="$work/capture"
prepared="$work/prepared"
hf_capture="$work/hf-capture"
enriched="$work/enriched"
finalized="$work/finalized"
mkdir -p "$capture/sources/001-example" "$hf_capture/responses"

for script in \
  "$LOCAL_AI_SUPERVISOR_SOURCE" \
  "$LOCAL_AI_CAPTURE_SOURCE" \
  "$LOCAL_AI_HF_CAPTURE_SOURCE" \
  "$LOCAL_AI_JUDGE_SOURCE" \
  "$LOCAL_AI_PURE_STAGE_SOURCE"; do
  grep -q '^set -euo pipefail$' "$script"
done

grep -Fq -- '--argstr bashPath "$LOCAL_AI_STAGE_BASH"' "$LOCAL_AI_SUPERVISOR_SOURCE"
grep -Fq -- '--argstr pureStagePath "$LOCAL_AI_PURE_STAGE"' "$LOCAL_AI_SUPERVISOR_SOURCE"

cat > "$registry" <<'JSON'
{
  "schema_version": 1,
  "accepted_through": "2026-07-01",
  "inference": {
    "provider": "llama-swap",
    "url": "http://worker:9292",
    "model_class": "strongest",
    "fallback_classes": [],
    "classes": {
      "strongest": {"role_order": ["quality", "general"], "ram_order": "descending"}
    }
  },
  "limits": {
    "commit_log": 10,
    "evidence_commits_per_source": 4,
    "evidence_files": 4,
    "excerpt_chars": 4000,
    "total_evidence_chars": 10000,
    "baseline_rationale_chars": 10000,
    "hf_metadata_repositories": 4,
    "hf_files_per_repository": 20
  },
  "sources": [{
    "slug": "example/repo",
    "url": "https://github.com/example/repo.git",
    "baseline": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "enabled": true,
    "cadence": "monthly",
    "watched_paths": ["README.md"]
  }]
}
JSON

cat > "$capture/manifest.json" <<'JSON'
{
  "schema_version": 1,
  "period": "2026-08",
  "cutoff": "2026-08-01",
  "dotfiles_commit": "cccccccccccccccccccccccccccccccccccccccc",
  "sources": [{
    "slug": "example/repo",
    "url": "https://github.com/example/repo.git",
    "baseline": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "head": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "observed_at": "2026-08-01T00:00:00Z",
    "status": "relevant",
    "processor": "generic",
    "dir": "sources/001-example",
    "commit_count": 1,
    "changed_paths": ["README.md"],
    "relevant_paths": ["README.md"]
  }]
}
JSON
cat > "$capture/catalog.json" <<'JSON'
{
  "deployments": {
    "best": {
      "status": "canonical", "role": "quality", "ramTierGb": 64,
      "model": "best-model", "backend": "vulkan", "evidence": "matched-local"
    },
    "fallback": {
      "status": "canonical", "role": "general", "ramTierGb": 16,
      "model": "fallback-model", "backend": "vulkan", "evidence": "unverified"
    }
  }
}
JSON
cat > "$capture/models.json" <<'JSON'
{"data":[{"id":"fallback-model"},{"id":"best-model"}]}
JSON
cat > "$capture/accepted-tally.md" <<'EOF'
# Previous accepted review

Keep the proven baseline unless new evidence is stronger.
EOF
cat > "$capture/sources/001-example/commits.tsv" <<'EOF'
bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb2026-08-01T00:00:00ZAdd candidate model
EOF
cat > "$capture/sources/001-example/diff.patch" <<'EOF'
diff --git a/README.md b/README.md
+++ b/README.md
@@ -0,0 +1 @@
+See https://huggingface.co/example/new-model for the artifact.
EOF
printf 'example/new-model\n' > "$capture/sources/001-example/hf-repositories.txt"
: > "$capture/sources/001-example/pickaxe.tsv"
: > "$capture/sources/001-example/packages-before.txt"
: > "$capture/sources/001-example/packages-after.txt"

"$LOCAL_AI_PURE_STAGE" prepare "$registry" "$capture" "$prepared"
jq -e '.model_id == "best-model" and .class == "strongest"' "$prepared/model.json" >/dev/null
jq -e 'length == 1 and .[0].repository == "example/new-model"' "$prepared/hf-requests.json" >/dev/null
jq -e '.sources[0].baseline == "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"' \
  "$prepared/next-sources.json" >/dev/null
grep -q 'Add candidate model' "$prepared/evidence.md"

cat > "$hf_capture/responses/001.json" <<'JSON'
{
  "id": "example/new-model",
  "sha": "dddddddddddddddddddddddddddddddddddddddd",
  "lastModified": "2026-08-01T00:00:00Z",
  "siblings": [{
    "rfilename": "model.gguf",
    "size": 4,
    "lfs": {
      "sha256": "0000000000000000000000000000000000000000000000000000000000000000",
      "size": 4,
      "pointerSize": 127
    }
  }]
}
JSON
response_sha="$(sha256sum "$hf_capture/responses/001.json" | cut -d' ' -f1)"
jq -n --arg sha "$response_sha" '{
  schema_version: 1,
  responses: [{
    repository: "example/new-model",
    api_url: "https://huggingface.co/api/models/example/new-model?blobs=true",
    response: "responses/001.json",
    sha256: $sha,
    http_status: 200,
    bytes: 1
  }]
}' > "$hf_capture/manifest.json"

"$LOCAL_AI_PURE_STAGE" enrich "$registry" "$prepared" "$hf_capture" "$enriched"
jq -e '.[0].revision == "dddddddddddddddddddddddddddddddddddddddd"' \
  "$enriched/hf-metadata.json" >/dev/null
jq -e '.[0].files[0].sri == "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="' \
  "$enriched/hf-metadata.json" >/dev/null

cat > "$work/commentary.md" <<'EOF'
## Local-model review

Consider adding the new model only after a matched local verification run.
EOF
"$LOCAL_AI_PURE_STAGE" finalize "$registry" "$enriched" "$work/commentary.md" "$finalized"
grep -q '^## Local-model review' "$finalized/pr-body.md"
jq -e '.commentary_sha256 | test("^[0-9a-f]{64}$")' "$finalized/run.json" >/dev/null
