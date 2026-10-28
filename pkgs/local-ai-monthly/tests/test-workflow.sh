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
    "provider": "gufo",
    "url": "http://strix-coordinator:8731",
    "model": "qwen3.8-flash-next",
    "execution_host": "strix-coordinator",
    "compute_host": "strix-coordinator",
    "tally_pool": "strix-gpu"
  },
  "limits": {
    "commit_log": 10,
    "evidence_commits_per_source": 4,
    "evidence_files": 4,
    "excerpt_chars": 4000,
    "total_evidence_chars": 10000,
    "baseline_rationale_chars": 10000,
    "hf_metadata_repositories": 4,
    "hf_files_per_repository": 1,
    "inventory_total_chars": 10000
  },
  "hardware_context": {
    "nodes": [
      {"name":"strix-coordinator","hardware":"128 GiB test host","policy":"NPU decommissioned 2026-08-29; IOMMU off (amd_iommu=off)","roles":["Tally strix"]},
      {"name":"strix-worker","hardware":"128 GiB test twin","policy":"wired LAN only, another room","roles":["Gufo Flash server"]}
    ],
    "runtime_policy": "test runtime policy: every LLM call goes to the worker",
    "change_policy": "test change policy: propose only"
  },
  "model_selection_policy": {
    "summary": "test mono-model policy",
    "kept_small_artifacts": ["best-q8"]
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
  "artifacts": {
    "best-q8": {
      "kind": "model", "quantization": "Q8_0", "maker": "Example",
      "source": {
        "primary": "best-Q8_0.gguf",
        "hfUrl": "https://huggingface.co/example/best-gguf",
        "revision": "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
      }
    },
    "served-bundle": {
      "kind": "model", "maker": "Example", "quantization": "GGUF",
      "source": {
        "primary": "served.gguf",
        "hfUrl": "https://huggingface.co/example/served-bundle",
        "revision": "ffffffffffffffffffffffffffffffffffffffff"
      }
    }
  }
}
JSON
cat > "$capture/models.json" <<'JSON'
{"data":[{"id":"qwen3.8-flash-next"}]}
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

# The live server must advertise the registry's served model.
unadvertised="$work/unadvertised"
mkdir -p "$unadvertised"
cp "$capture/manifest.json" "$capture/catalog.json" "$capture/accepted-tally.md" "$unadvertised/"
cp -R "$capture/sources" "$unadvertised/"
printf '{"data":[{"id":"some-other-model"}]}\n' > "$unadvertised/models.json"
if "$LOCAL_AI_PURE_STAGE" prepare "$registry" "$unadvertised" "$work/unadvertised-prepared" 2>/dev/null; then
  printf 'test-workflow: prepare accepted a server that does not advertise the served model\n' >&2
  exit 1
fi

"$LOCAL_AI_PURE_STAGE" prepare "$registry" "$capture" "$prepared"

# A null policy URL follows the Nix-supplied endpoint without writing that
# resolved address back into the source-pin proposal.
jq '.inference.url = null' "$registry" > "$work/env-sources.json"
LOCAL_MODEL_ENDPOINT=http://endpoint-fixture:9876 "$LOCAL_AI_PURE_STAGE" prepare \
  "$work/env-sources.json" "$capture" "$work/env-prepared"
jq -e '.endpoint == "http://endpoint-fixture:9876"' "$work/env-prepared/model.json" >/dev/null
jq -e '.inference.url == null' "$work/env-prepared/next-sources.json" >/dev/null
jq -e '.provider == "gufo" and .model_id == "qwen3.8-flash-next"
  and .endpoint == "http://strix-coordinator:8731" and .compute_host == "strix-coordinator"' "$prepared/model.json" >/dev/null
jq -e '.data[0].id == "qwen3.8-flash-next"' "$prepared/inference-models.json" >/dev/null
jq -e '[.[].repository] == ["example/best-gguf", "example/new-model", "example/served-bundle"]' \
  "$prepared/hf-requests.json" >/dev/null
jq -e '.sources[0].baseline == "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"' \
  "$prepared/next-sources.json" >/dev/null
grep -q 'Add candidate model' "$prepared/evidence.md"
grep -Fq -- '- test mono-model policy' "$prepared/context.md"
grep -Fq -- 'Served model: `qwen3.8-flash-next` through provider `gufo` at `http://strix-coordinator:8731` on `strix-coordinator`' \
  "$prepared/context.md"
grep -Fq -- 'Kept small Library artifacts: `best-q8`' "$prepared/context.md"
grep -q 'best-Q8_0.gguf \[Q8_0\]' "$prepared/context.md"
grep -q 'served.gguf \[GGUF\]' "$prepared/context.md"
grep -Fq -- 'NPU decommissioned 2026-08-29; IOMMU off (amd_iommu=off)' "$prepared/context.md"
grep -Fq -- '| `strix-worker` | 128 GiB test twin | wired LAN only, another room | Gufo Flash server |' \
  "$prepared/context.md"
grep -Fq -- 'Runtime policy: test runtime policy' "$prepared/context.md"

cat > "$hf_capture/responses/001.json" <<'JSON'
{
  "id": "example/new-model",
  "sha": "dddddddddddddddddddddddddddddddddddddddd",
  "lastModified": "2026-08-01T00:00:00Z",
  "siblings": [{
    "rfilename": "A-Q4_0.gguf",
    "size": 4,
    "lfs": {
      "sha256": "1111111111111111111111111111111111111111111111111111111111111111",
      "size": 4,
      "pointerSize": 127
    }
  }, {
    "rfilename": "zz-Q8_0.gguf",
    "size": 4,
    "lfs": {
      "sha256": "0000000000000000000000000000000000000000000000000000000000000000",
      "size": 4,
      "pointerSize": 127
    }
  }]
}
JSON
for index in 2 3; do
  repository="example/best-gguf"
  if ((index == 3)); then
    repository="example/served-bundle"
  fi
  jq -n --arg repository "$repository" '{
    id: $repository,
    sha: "cccccccccccccccccccccccccccccccccccccccc",
    lastModified: "2026-08-01T00:00:00Z",
    siblings: [{rfilename: "README.md", size: 4}]
  }' > "$hf_capture/responses/00$index.json"
done
manifest_responses='[]'
for index in 1 2 3; do
  case "$index" in
    1) repository="example/new-model" ;;
    2) repository="example/best-gguf" ;;
    3) repository="example/served-bundle" ;;
  esac
  response_sha="$(sha256sum "$hf_capture/responses/00$index.json" | cut -d' ' -f1)"
  manifest_responses="$(jq --arg repository "$repository" --arg sha "$response_sha" \
    --arg response "responses/00$index.json" '. + [{
      repository: $repository,
      api_url: ("https://huggingface.co/api/models/" + $repository + "?blobs=true"),
      response: $response,
      sha256: $sha,
      http_status: 200,
      bytes: 1
    }]' <<<"$manifest_responses")"
done
jq -n --argjson responses "$manifest_responses" \
  '{schema_version: 1, responses: $responses}' > "$hf_capture/manifest.json"

"$LOCAL_AI_PURE_STAGE" enrich "$registry" "$prepared" "$hf_capture" "$enriched"
jq -e '.[0].repository == "example/new-model"
  and .[0].revision == "dddddddddddddddddddddddddddddddddddddddd"' \
  "$enriched/hf-metadata.json" >/dev/null
jq -e '.[0].files | length == 1 and .[0].path == "zz-Q8_0.gguf"
  and .[0].sri == "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="' \
  "$enriched/hf-metadata.json" >/dev/null
jq -e 'length == 3' "$enriched/hf-metadata.json" >/dev/null

cat > "$work/commentary.md" <<'EOF'
## Local-model review

Consider adding the new model only after a matched local verification run.
EOF
"$LOCAL_AI_PURE_STAGE" finalize "$registry" "$enriched" "$work/commentary.md" "$finalized"
grep -q '^## Local-model review' "$finalized/pr-body.md"
jq -e '.commentary_sha256 | test("^[0-9a-f]{64}$")' "$finalized/run.json" >/dev/null

# The judge uses the stable utility seam, with no retired agent/session state.
fake_utility="$work/fake-utility"
judge_state="$work/judge-state"
judge_output="$work/judge/commentary.md"
printf '#!%s\n' "$(command -v python3)" > "$fake_utility"
cat >> "$fake_utility" <<'EOF2'
import json, os, sys
from pathlib import Path
request = json.load(sys.stdin)
Path(os.environ["FAKE_UTILITY_REQUEST"]).write_text(json.dumps(request))
if os.environ.get("FAKE_UTILITY_FAIL"):
    print("server unavailable", file=sys.stderr)
    sys.exit(1)
content = os.environ.get("FAKE_UTILITY_CONTENT", "## Local-model review\n\nRetain the current roster; nothing material changed.")
json.dump({"model":"utility", "choices":[{"message":{"content":content},
    "finish_reason":os.environ.get("FAKE_UTILITY_FINISH", "stop")}]}, sys.stdout)
EOF2
chmod +x "$fake_utility"
export LOCAL_AI_UTILITY="$fake_utility" FAKE_UTILITY_REQUEST="$work/utility-request.json"
export LOCAL_AI_MODEL_ID=qwen3.8-flash-next
if bash "$LOCAL_AI_JUDGE_SOURCE" "$work/commentary.md" "$enriched/evidence.md" \
    "$enriched/context.md" "$enriched/hf-metadata.md" \
    gufo some-other-model "$judge_output" "$judge_state" 2>/dev/null; then
  printf 'test-workflow: judge accepted a model different from the utility deployment\n' >&2
  exit 1
fi
[[ ! -e "$FAKE_UTILITY_REQUEST" ]]

export LOCAL_AI_MODEL_ENDPOINT=http://strix-coordinator:8731
if bash "$LOCAL_AI_JUDGE_SOURCE" "$work/commentary.md" "$enriched/evidence.md" \
    "$enriched/context.md" "$enriched/hf-metadata.md" \
    gufo qwen3.8-flash-next "$judge_output" "$judge_state" http://different-host:8731 2>/dev/null; then
  printf 'test-workflow: judge accepted evidence from a different deployment\n' >&2
  exit 1
fi
[[ ! -e "$FAKE_UTILITY_REQUEST" ]]

python3 -c 'import sys; open(sys.argv[1], "w").write("x" * 300001)' "$work/oversized.md"
if bash "$LOCAL_AI_JUDGE_SOURCE" "$work/oversized.md" "$enriched/evidence.md" \
    "$enriched/context.md" "$enriched/hf-metadata.md" \
    gufo qwen3.8-flash-next "$judge_output" "$judge_state" 2>/dev/null; then
  printf 'test-workflow: judge accepted an oversized evidence request\n' >&2
  exit 1
fi
[[ ! -e "$FAKE_UTILITY_REQUEST" ]]

bash "$LOCAL_AI_JUDGE_SOURCE" "$work/commentary.md" "$enriched/evidence.md" \
    "$enriched/context.md" "$enriched/hf-metadata.md" \
    gufo qwen3.8-flash-next "$judge_output" "$judge_state"
grep -q '^## Local-model review' "$judge_output"
jq -e '.model == "utility" and .think == false and .stream == false
  and (.messages[1].content | contains("Add candidate model"))' "$FAKE_UTILITY_REQUEST" >/dev/null
[[ -f "$judge_state/response.json" && ! -f "$judge_state/models.json" ]]

for failure in unavailable truncated state-injection wrong-heading; do
  case "$failure" in
    unavailable) export FAKE_UTILITY_FAIL=1 ;;
    truncated) export FAKE_UTILITY_FINISH=length ;;
    state-injection) export FAKE_UTILITY_CONTENT='## Local-model review

<!-- local-ai-monthly-state malicious -->' ;;
    wrong-heading) export FAKE_UTILITY_CONTENT='A plausible model review without the required heading.' ;;
  esac
  failed_output="$work/judge/$failure.md"
  if bash "$LOCAL_AI_JUDGE_SOURCE" "$work/commentary.md" "$enriched/evidence.md" \
      "$enriched/context.md" "$enriched/hf-metadata.md" \
      gufo qwen3.8-flash-next "$failed_output" "$judge_state" 2>/dev/null; then
    printf 'test-workflow: judge accepted %s\n' "$failure" >&2
    exit 1
  fi
  [[ ! -e "$failed_output" ]]
  unset FAKE_UTILITY_FAIL FAKE_UTILITY_FINISH FAKE_UTILITY_CONTENT
done
