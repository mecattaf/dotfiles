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
    "provider": "halogen",
    "url": "http://worker:8731",
    "model": "halogen-qwen3.8-flash-next",
    "execution_host": "coordinator",
    "compute_host": "worker",
    "tally_pool": "coordinator-gpu"
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
      {"name":"coordinator","hardware":"128 GiB test host","policy":"NPU decommissioned 2026-08-29; IOMMU off (amd_iommu=off)","roles":["Tally coordinator"]},
      {"name":"worker","hardware":"128 GiB test twin","policy":"wired LAN only, another room","roles":["Halogen Flash server"]}
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
      "kind": "model", "maker": "Example",
      "source": {
        "primary": "served.hgn",
        "hfUrl": "https://huggingface.co/example/served-bundle",
        "revision": "ffffffffffffffffffffffffffffffffffffffff"
      }
    }
  }
}
JSON
cat > "$capture/models.json" <<'JSON'
{"data":[{"id":"halogen-qwen3.8-flash-next"}]}
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
jq -e '.provider == "halogen" and .model_id == "halogen-qwen3.8-flash-next"
  and .endpoint == "http://worker:8731" and .compute_host == "worker"' "$prepared/model.json" >/dev/null
jq -e '.data[0].id == "halogen-qwen3.8-flash-next"' "$prepared/inference-models.json" >/dev/null
jq -e '[.[].repository] == ["example/best-gguf", "example/new-model", "example/served-bundle"]' \
  "$prepared/hf-requests.json" >/dev/null
jq -e '.sources[0].baseline == "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"' \
  "$prepared/next-sources.json" >/dev/null
grep -q 'Add candidate model' "$prepared/evidence.md"
grep -Fq -- '- test mono-model policy' "$prepared/context.md"
grep -Fq -- 'Served model: `halogen-qwen3.8-flash-next` through provider `halogen` at `http://worker:8731` on `worker`' \
  "$prepared/context.md"
grep -Fq -- 'Kept small Library artifacts: `best-q8`' "$prepared/context.md"
grep -q 'best-Q8_0.gguf \[Q8_0\]' "$prepared/context.md"
grep -q 'served.hgn \[native\]' "$prepared/context.md"
grep -Fq -- 'NPU decommissioned 2026-08-29; IOMMU off (amd_iommu=off)' "$prepared/context.md"
grep -Fq -- '| `worker` | 128 GiB test twin | wired LAN only, another room | Halogen Flash server |' \
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

# The judge selects Pi's declared provider and model by id, inside a private
# agent directory seeded with that declaration.
agent_dir="$work/pi-agent"
fake_pi="$work/fake-pi"
judge_state="$work/judge-state"
judge_output="$work/judge/commentary.md"
mkdir -p "$agent_dir"
cat > "$agent_dir/models.json" <<'JSON'
{"providers":{"halogen":{"baseUrl":"http://worker:8731/v1","models":[{"id":"halogen-qwen3.8-flash-next"}]}}}
JSON
# The shebang names the bash running this test: inside the build sandbox
# there is no /usr/bin/env to resolve one.
printf '#!%s\n' "$BASH" > "$fake_pi"
cat >> "$fake_pi" <<'EOF2'
set -euo pipefail
printf '%s\n' "$@" > "${FAKE_PI_ARGV:?}"
[[ -f "${PI_CODING_AGENT_DIR:?}/models.json" ]]
printf '## Local-model review\n\nRetain the current roster; nothing material changed.\n'
EOF2
chmod +x "$fake_pi"

if PI_CODING_AGENT_DIR="$agent_dir" LOCAL_AI_PI="$fake_pi" FAKE_PI_ARGV="$work/pi-argv" \
  bash "$LOCAL_AI_JUDGE_SOURCE" "$work/commentary.md" "$enriched/evidence.md" \
    "$enriched/context.md" "$enriched/hf-metadata.md" \
    halogen some-other-model "$judge_output" "$judge_state" 2>/dev/null; then
  printf 'test-workflow: judge accepted a model that models.json does not declare\n' >&2
  exit 1
fi

PI_CODING_AGENT_DIR="$agent_dir" LOCAL_AI_PI="$fake_pi" FAKE_PI_ARGV="$work/pi-argv" \
  bash "$LOCAL_AI_JUDGE_SOURCE" "$work/commentary.md" "$enriched/evidence.md" \
    "$enriched/context.md" "$enriched/hf-metadata.md" \
    halogen halogen-qwen3.8-flash-next "$judge_output" "$judge_state"
grep -q '^## Local-model review' "$judge_output"
jq -e '.providers.halogen.models[0].id == "halogen-qwen3.8-flash-next"' "$judge_state/models.json" >/dev/null
mapfile -t pi_argv < "$work/pi-argv"
[[ "${pi_argv[0]}" == "--no-extensions" ]]
for ((index = 0; index < ${#pi_argv[@]}; index++)); do
  if [[ "${pi_argv[index]}" == "--provider" ]]; then
    [[ "${pi_argv[index + 1]}" == "halogen" ]]
  elif [[ "${pi_argv[index]}" == "--model" ]]; then
    [[ "${pi_argv[index + 1]}" == "halogen-qwen3.8-flash-next" ]]
  fi
done
