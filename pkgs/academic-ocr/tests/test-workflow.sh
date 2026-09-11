set -euo pipefail

work=$(mktemp -d)
cleanup() {
  if [[ -d $work ]]; then
    rm -r -- "$work"
  fi
}
trap cleanup EXIT

fixtures=${ACADEMIC_OCR_FIXTURES:?ACADEMIC_OCR_FIXTURES is not set}
fake_curl=${ACADEMIC_OCR_FAKE_CURL:?ACADEMIC_OCR_FAKE_CURL is not set}
paper_catalog=${ACADEMIC_OCR_PAPER_CATALOG:?ACADEMIC_OCR_PAPER_CATALOG is not set}
sqlite_vec=${ACADEMIC_OCR_SQLITE_VEC:?ACADEMIC_OCR_SQLITE_VEC is not set}
state="$work/state"
mkdir -p "$state"

fail() {
  printf 'academic-ocr-tests: %s\n' "$*" >&2
  exit 1
}

summary_from_output() {
  local output=$1
  [[ $(wc -l < "$output") -eq 1 ]] || fail "driver emitted more than one stdout line: $output"
  grep -q '^TALLY_FINAL_MESSAGE=' "$output" || fail "driver emitted no final message: $output"
  sed 's/^TALLY_FINAL_MESSAGE=//' "$output" | jq -c .
}

run_action() {
  local action=$1 brief=$2 output=$3
  TALLY_BRIEF="$brief" \
    ACADEMIC_OCR_CURL="$fake_curl" \
    ACADEMIC_OCR_STATE_ROOT="$state" \
    academic-ocr-driver "$action" > "$output"
  summary_from_output "$output" >/dev/null
}

signature_disagreement() {
  local left=$1 right=$2
  jq -n \
    --argjson left "$left" \
    --argjson right "$right" '
      ([range(0; ([($left | length), ($right | length)] | max))
        | select($left[.] != $right[.])]
       | length * 1000
       / ([($left | length), ($right | length)] | max)
       | floor)
    '
}

ps2pdf "$fixtures/text-page.ps" "$work/text-page.pdf"
ps2pdf "$fixtures/scan-page.ps" "$work/scan-page.pdf"
fixture_sha=$(sha256sum "$work/text-page.pdf" | awk '{print $1}')
jq -e '
  .turner.paperId == "fa3c575a-3089-4d27-957f-ba7d697b8737"
  and .turner.sourceSha256 == "aa9db49df2216d7455fe0e81af561e05682e8fb68fe72a7e0de00a45b3af6265"
  and .turner.expectedPages == 5
  and .fosfuri.paperId == "96b65260-610c-4404-a08f-98b0e3ebc6d9"
  and .fosfuri.sourceSha256 == "909a82261bc9e0c3b2feaf9b9e93bcefc969919d935fd96734e215d002fdeb2b"
  and .fosfuri.expectedPages == 18
  and (.fosfuri.sourceUrl | contains("491cfaeb-197d-4b1f-a510-261c480a7d22"))
' "$paper_catalog" >/dev/null || fail 'fixed-paper catalog does not match the ruled identities'

ocr_args=$(academic-ocr-prepare \
  --source-file "$work/text-page.pdf" \
  --url 'https://example.invalid/fixture.pdf' \
  --sha256 "$fixture_sha" \
  --paper-id fixture-paper \
  --title 'Fixture Paper for Academic OCR' \
  --expected-pages 1 \
  --state-root "$state")
[[ -f $ocr_args ]] || fail 'prepare did not emit an OCR args manifest'
jq -e '
  (.pages | length == 1)
  and (.protocols | map(.id) == [
    "poppler-text",
    "mupdf-text",
    "halogen-qwen3.8-flash-next"
  ])
  and .rasterDpi == 400
  and .maxMutationIterations == 3
  and .maxDisagreementPermille == 375
' "$ocr_args" >/dev/null
source_path=$(jq -r '.pages[0].sourcePath' "$ocr_args")
[[ -f ${source_path%.pdf}.pages/200dpi/page-0001.png ]] || fail 'prepare did not render the fixture page'

jq -n \
  --arg sourcePath "$source_path" \
  --arg artifactPath "$work/outside-state.json" '{
    action: "recognize",
    page: {paperId: "fixture-paper", pageNumber: 1, sourcePath: $sourcePath},
    protocol: {id: "poppler-text", tier: "cheap"},
    input: {id: "original", mutation: {kind: "none"}},
    artifactPath: $artifactPath
  }' > "$work/outside-state-brief.json"
if TALLY_BRIEF="$work/outside-state-brief.json" ACADEMIC_OCR_STATE_ROOT="$state" \
  academic-ocr-driver recognize > "$work/outside-state.out" 2> "$work/outside-state.err"; then
  fail 'driver accepted an artifact path outside the academic OCR data root'
fi
grep -q 'escapes the academic OCR data root' "$work/outside-state.err" \
  || fail 'driver did not explain its data-root boundary rejection'

args_digest=$(sha256sum "$ocr_args" | awk '{print $1}')
ocr_args_again=$(academic-ocr-prepare \
  --source-file "$work/text-page.pdf" \
  --url 'https://example.invalid/fixture.pdf' \
  --sha256 "$fixture_sha" \
  --paper-id fixture-paper \
  --title 'Fixture Paper for Academic OCR' \
  --expected-pages 1 \
  --state-root "$state")
[[ $ocr_args_again == "$ocr_args" ]] || fail 'prepare changed the manifest path on replay'
[[ $(sha256sum "$ocr_args" | awk '{print $1}') == "$args_digest" ]] || fail 'prepare output is not deterministic'

fosfuri_args=$(academic-ocr-prepare \
  --paper fosfuri \
  --source-file "$work/text-page.pdf" \
  --sha256 "$fixture_sha" \
  --expected-pages 1 \
  --state-root "$work/fosfuri-state")
fosfuri_run=$(dirname "$fosfuri_args")
jq -e '
  .paperId == "96b65260-610c-4404-a08f-98b0e3ebc6d9"
  and .title == "The Licensing Dilemma: Understanding the Determinants of the Rate of Technology Licensing"
  and (.sourceUrl | contains("491cfaeb-197d-4b1f-a510-261c480a7d22"))
  and .pageCount == 1
' "$fosfuri_run/source.json" >/dev/null \
  || fail 'Fosfuri profile did not preserve db_id identity independently of the URL UUID'

run_dir=$(dirname "$ocr_args")
poppler_artifact="$run_dir/ocr/fixture-paper/page-1/poppler-text/original.json"
mupdf_artifact="$run_dir/ocr/fixture-paper/page-1/mupdf-text/original.json"

for protocol in poppler-text mupdf-text; do
  artifact="$run_dir/ocr/fixture-paper/page-1/$protocol/original.json"
  brief="$work/$protocol-brief.json"
  jq -n \
    --arg protocol "$protocol" \
    --arg sourcePath "$source_path" \
    --arg artifactPath "$artifact" '{
      action: "recognize",
      page: {paperId: "fixture-paper", pageNumber: 1, sourcePath: $sourcePath},
      protocol: {id: $protocol, tier: "cheap"},
      input: {id: "original", mutation: {kind: "none"}},
      artifactPath: $artifactPath
    }' > "$brief"
  run_action recognize "$brief" "$work/$protocol.out"
  jq -e '
    .paperId == "fixture-paper"
    and .pageNumber == 1
    and .protocolId == $protocol
    and .inputVariant == "original"
    and (.textDigest | test("^sha256:[0-9a-f]{64}$"))
    and (.signature | length == 32)
    and .confidencePermille == 1000
    and .hotZones == []
    and .skewMilliDegrees == 0
  ' --arg protocol "$protocol" "$artifact" >/dev/null
done

poppler_signature=$(jq -c '.signature' "$poppler_artifact")
mupdf_signature=$(jq -c '.signature' "$mupdf_artifact")
mechanical_disagreement=$(signature_disagreement "$poppler_signature" "$mupdf_signature")
(( mechanical_disagreement <= 375 )) || fail "mechanical fixture signatures disagree at $mechanical_disagreement permille"

arbiter_artifact="$run_dir/ocr/fixture-paper/page-1/arbiter/final.json"
jq -n \
  --arg sourcePath "$source_path" \
  --arg popplerPath "$poppler_artifact" \
  --arg popplerDigest "$(jq -r '.textDigest' "$poppler_artifact")" \
  --arg mupdfPath "$mupdf_artifact" \
  --arg mupdfDigest "$(jq -r '.textDigest' "$mupdf_artifact")" \
  --arg artifactPath "$arbiter_artifact" '{
    action: "arbitrate",
    page: {paperId: "fixture-paper", pageNumber: 1, sourcePath: $sourcePath},
    attempts: [{
      taskUuid: "00000000-0000-4000-8000-000000000121",
      witnessSeq: 1,
      verdict: "pass",
      protocolId: "poppler-text",
      inputVariant: "original",
      artifactPath: $popplerPath,
      textDigest: $popplerDigest
    }, {
      taskUuid: "00000000-0000-4000-8000-000000000122",
      witnessSeq: 2,
      verdict: "pass",
      protocolId: "mupdf-text",
      inputVariant: "original",
      artifactPath: $mupdfPath,
      textDigest: $mupdfDigest
    }],
    artifactPath: $artifactPath
  }' > "$work/arbiter-brief.json"
run_action arbitrate "$work/arbiter-brief.json" "$work/arbiter.out"
jq -e '
  .paperId == "fixture-paper"
  and .pageNumber == 1
  and (.basis | length == 2)
  and (.textDigest | test("^sha256:[0-9a-f]{64}$"))
' "$arbiter_artifact" >/dev/null

jitter_a=$(academic-ocr-signature "$fixtures/jitter-a.txt")
jitter_b=$(academic-ocr-signature "$fixtures/jitter-b.txt")
different=$(academic-ocr-signature "$fixtures/different.txt")
jitter_disagreement=$(signature_disagreement "$jitter_a" "$jitter_b")
different_disagreement=$(signature_disagreement "$jitter_a" "$different")
(( jitter_disagreement <= 375 )) || fail "minor OCR jitter exceeds threshold: $jitter_disagreement"
(( different_disagreement > 375 )) || fail "different content falls below threshold: $different_disagreement"
if printf '   \n' | academic-ocr-signature - >/dev/null 2>&1; then
  fail 'empty text unexpectedly produced a signature'
fi

scan_sha=$(sha256sum "$work/scan-page.pdf" | awk '{print $1}')
scan_artifact="$work/scan-recognition.json"
jq -n \
  --arg sourcePath "$work/scan-page.pdf" \
  --arg artifactPath "$scan_artifact" '{
    action: "recognize",
    page: {paperId: "scan-fixture", pageNumber: 1, sourcePath: $sourcePath},
    protocol: {id: "poppler-text", tier: "cheap"},
    input: {id: "original", mutation: {kind: "none"}},
    artifactPath: $artifactPath
  }' > "$work/scan-brief.json"
if TALLY_BRIEF="$work/scan-brief.json" ACADEMIC_OCR_STATE_ROOT="$work" \
  academic-ocr-driver recognize > "$work/scan.out" 2> "$work/scan.err"; then
  fail 'empty mechanical extraction unexpectedly passed'
fi
[[ ! -e $scan_artifact ]] || fail 'failed mechanical extraction wrote a passing artifact'
grep -q 'empty or near-empty' "$work/scan.err" || fail 'mechanical failure did not explain the fail-closed gate'
[[ $scan_sha =~ ^[0-9a-f]{64}$ ]] || fail 'scan fixture hash failed'

vlm_protocol=halogen-qwen3.8-flash-next
vlm_artifact="$run_dir/ocr/fixture-paper/page-1/$vlm_protocol/original.json"
jq -n \
  --arg sourcePath "$source_path" \
  --arg protocol "$vlm_protocol" \
  --arg artifactPath "$vlm_artifact" '{
    action: "recognize",
    page: {paperId: "fixture-paper", pageNumber: 1, sourcePath: $sourcePath},
    protocol: {id: $protocol, tier: "standard"},
    input: {id: "original", mutation: {kind: "none"}},
    artifactPath: $artifactPath
  }' > "$work/vlm-brief.json"
run_action recognize "$work/vlm-brief.json" "$work/vlm.out"
jq -e --arg protocol "$vlm_protocol" '
  .protocolId == $protocol
  and .confidencePermille == 900
  and .provenance.endpoint == "http://worker:8731"
  and (.provenance.promptDigest | test("^sha256:[0-9a-f]{64}$"))
  and .provenance.finishReason == "stop"
  and (.wordCount | type == "number" and . > 0)
' "$vlm_artifact" >/dev/null

# The fixture page is deliberately shorter than the voucher floor, so the
# length ratio never applies to it and the transcription above is judged on
# substance alone. Fattening the fixture would silently change that.
poppler_words=$(jq -r '.wordCount' "$poppler_artifact")
(( poppler_words < 200 )) || fail "fixture voucher assumption broke at $poppler_words words"

# A page that stops at the token cap fails on the server's own signal, with no
# mechanical voucher anywhere in reach.
capped_artifact="$run_dir/ocr/capped-fixture/page-1/$vlm_protocol/original.json"
jq -n \
  --arg sourcePath "$source_path" \
  --arg protocol "$vlm_protocol" \
  --arg artifactPath "$capped_artifact" '{
    action: "recognize",
    page: {paperId: "capped-fixture", pageNumber: 1, sourcePath: $sourcePath},
    protocol: {id: $protocol, tier: "standard"},
    input: {id: "original", mutation: {kind: "none"}},
    artifactPath: $artifactPath
  }' > "$work/capped-brief.json"
if TALLY_BRIEF="$work/capped-brief.json" \
  ACADEMIC_OCR_CURL="$fake_curl" \
  ACADEMIC_OCR_STATE_ROOT="$state" \
  ACADEMIC_OCR_FAKE_FINISH_REASON=length \
  academic-ocr-driver recognize > "$work/capped.out" 2> "$work/capped.err"; then
  fail 'a transcription stopped at the token cap unexpectedly passed'
fi
[[ ! -e $capped_artifact ]] || fail 'a capped transcription wrote a passing artifact'
grep -q 'finish_reason=length' "$work/capped.err" \
  || fail 'the cap rejection did not name the signal it acted on'

# A page whose mechanical extraction is long enough to vouch for it rejects a
# visual transcription that returns only a fraction of that length, even when
# the server claims it stopped cleanly.
voucher_page_dir="$run_dir/ocr/voucher-fixture/page-1"
voucher_text=$(seq -f 'mechanical%g' 1 240 | tr '\n' ' ')
short_content=$(seq -f 'transcribed%g' 1 20 | tr '\n' ' ')

# Hand-built recognitions stand in for attempts the ladder would have produced.
# The digest is over the exact text the arbiter re-derives, with no trailing
# newline, which is what `jq -jr` yields.
write_recognition() {
  local protocol=$1 text=$2 destination="$voucher_page_dir/$3/original.json"
  mkdir -p "$(dirname "$destination")"
  jq -n \
    --arg protocol "$protocol" \
    --arg text "$text" \
    --arg artifactPath "$destination" \
    --arg digest "$(printf '%s' "$text" | sha256sum | awk '{print "sha256:" $1}')" '{
      schemaVersion: 1,
      action: "recognize",
      paperId: "voucher-fixture",
      pageNumber: 1,
      protocolId: $protocol,
      inputVariant: "original",
      artifactPath: $artifactPath,
      text: $text,
      textDigest: $digest
    }' > "$destination"
}

write_recognition poppler-text "$voucher_text" poppler-text

voucher_artifact="$voucher_page_dir/$vlm_protocol/original.json"
jq -n \
  --arg sourcePath "$source_path" \
  --arg protocol "$vlm_protocol" \
  --arg artifactPath "$voucher_artifact" '{
    action: "recognize",
    page: {paperId: "voucher-fixture", pageNumber: 1, sourcePath: $sourcePath},
    protocol: {id: $protocol, tier: "standard"},
    input: {id: "original", mutation: {kind: "none"}},
    artifactPath: $artifactPath
  }' > "$work/voucher-brief.json"
if TALLY_BRIEF="$work/voucher-brief.json" \
  ACADEMIC_OCR_CURL="$fake_curl" \
  ACADEMIC_OCR_STATE_ROOT="$state" \
  ACADEMIC_OCR_FAKE_VLM_CONTENT="$short_content" \
  academic-ocr-driver recognize > "$work/voucher.out" 2> "$work/voucher.err"; then
  fail 'a transcription far under its mechanical voucher unexpectedly passed'
fi
[[ ! -e $voucher_artifact ]] || fail 'a truncated transcription wrote a passing artifact'
grep -q 'mechanical voucher' "$work/voucher.err" \
  || fail 'the voucher rejection did not explain the length it compared'

# The same voucher accepts a transcription that clears the floor, so the guard
# is a length ratio and not a blanket refusal of visual protocols.
full_content=$(seq -f 'transcribed%g' 1 200 | tr '\n' ' ')
TALLY_BRIEF="$work/voucher-brief.json" \
  ACADEMIC_OCR_CURL="$fake_curl" \
  ACADEMIC_OCR_STATE_ROOT="$state" \
  ACADEMIC_OCR_FAKE_VLM_CONTENT="$full_content" \
  academic-ocr-driver recognize > "$work/voucher-pass.out"
summary_from_output "$work/voucher-pass.out" >/dev/null
jq -e '.wordCount == 200 and .provenance.finishReason == "stop"' "$voucher_artifact" >/dev/null \
  || fail 'a transcription clearing the voucher floor did not record its length'

# The arbiter drops a truncated visual candidate rather than ranking it first,
# which it otherwise would: the visual tier outranks every mechanical
# extraction before length is even considered. The candidate is written under
# a sibling variant so the passing transcription above stays on disk.
write_recognition "$vlm_protocol" "$short_content" "$vlm_protocol-truncated"
truncated_path="$voucher_page_dir/$vlm_protocol-truncated/original.json"
truncated_digest=$(jq -r '.textDigest' "$truncated_path")
voucher_poppler="$voucher_page_dir/poppler-text/original.json"
voucher_poppler_digest=$(jq -r '.textDigest' "$voucher_poppler")
voucher_arbiter="$voucher_page_dir/arbiter/final.json"
jq -n \
  --arg sourcePath "$source_path" \
  --arg protocol "$vlm_protocol" \
  --arg truncatedPath "$truncated_path" \
  --arg truncatedDigest "$truncated_digest" \
  --arg voucherPath "$voucher_poppler" \
  --arg voucherDigest "$voucher_poppler_digest" \
  --arg artifactPath "$voucher_arbiter" '{
    action: "arbitrate",
    page: {paperId: "voucher-fixture", pageNumber: 1, sourcePath: $sourcePath},
    attempts: [{
      taskUuid: "00000000-0000-4000-8000-000000000131",
      witnessSeq: 1,
      verdict: "pass",
      protocolId: $protocol,
      inputVariant: "original",
      artifactPath: $truncatedPath,
      textDigest: $truncatedDigest
    }, {
      taskUuid: "00000000-0000-4000-8000-000000000132",
      witnessSeq: 2,
      verdict: "pass",
      protocolId: "poppler-text",
      inputVariant: "original",
      artifactPath: $voucherPath,
      textDigest: $voucherDigest
    }],
    artifactPath: $artifactPath
  }' > "$work/voucher-arbiter-brief.json"
run_action arbitrate "$work/voucher-arbiter-brief.json" "$work/voucher-arbiter.out"
jq -e \
  --arg truncatedPath "$truncated_path" \
  --arg voucherPath "$voucher_poppler" '
  .selectedArtifactPath == $voucherPath
  and (.basis == [$voucherPath])
  and (.truncatedArtifactPaths == [$truncatedPath])
  and .provenance.voucherWords == 240
' "$voucher_arbiter" >/dev/null \
  || fail 'the arbiter ranked a truncated visual candidate over its mechanical voucher'

vlm_digest=$(jq -r '.textDigest' "$vlm_artifact")
selection=$(jq -n \
  --arg digest "$vlm_digest" \
  --arg protocol "$vlm_protocol" \
  --arg path "$vlm_artifact" '{
    paperId: "fixture-paper",
    pageNumber: 1,
    status: "converged",
    resolution: "tier",
    inputVariant: "original",
    chosenArtifactPath: $path,
    textDigest: $digest,
    disagreementPermille: 0,
    agreementProtocols: ["poppler-text", $protocol],
    attemptCount: 3,
    proof: {taskUuid: "00000000-0000-4000-8000-000000000124", witnessSeq: 1}
  }')
package_dir="$run_dir/package"
canonical_manifest="$package_dir/canonical/manifest.json"
jq -n \
  --argjson selection "$selection" \
  --arg outputDir "$package_dir" \
  --arg artifactPath "$canonical_manifest" '{
    action: "assemble",
    paper: {
      paperId: "fixture-paper",
      title: "Fixture Paper for Academic OCR",
      sourceUrl: "https://example.invalid/fixture.pdf",
      sourceSha256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    },
    pages: [$selection],
    outputDir: $outputDir,
    artifactPath: $artifactPath
  }' > "$work/assemble-brief.json"
run_action assemble "$work/assemble-brief.json" "$work/assemble.out"
assemble_summary=$(summary_from_output "$work/assemble.out")
jq -e '.pages | length == 1' "$canonical_manifest" >/dev/null
grep -q '<!-- page:001 -->' "$package_dir/canonical/paper.md"

chunks_path="$package_dir/chunks.json"
jq -n \
  --arg paperPath "$package_dir/canonical/paper.md" \
  --arg artifactPath "$chunks_path" '{
    action: "chunk",
    paperId: "fixture-paper",
    paperPath: $paperPath,
    chunkWords: 512,
    embeddingModel: "qwen3-embedding-8b",
    artifactPath: $artifactPath
  }' > "$work/chunk-brief.json"
run_action chunk "$work/chunk-brief.json" "$work/chunk.out"
chunk_summary=$(summary_from_output "$work/chunk.out")
jq -e '
  .paper_uuid == "fixture-paper"
  and .embed_model_version == "qwen3-embedding-8b"
  and (.chunks | length > 0)
  and all(.chunks[]; has("page_start") and has("page_end") and has("embed_text"))
' "$chunks_path" >/dev/null
chunks_digest=$(sha256sum "$chunks_path" | awk '{print $1}')
run_action chunk "$work/chunk-brief.json" "$work/chunk-replay.out"
[[ $(sha256sum "$chunks_path" | awk '{print $1}') == "$chunks_digest" ]] || fail 'chunk output changed on replay'

# No fleet server offers /v1/embeddings: a null endpoint is the planner saying
# ACADEMIC_OCR_EMBEDDINGS_URL was unset, and the driver refuses it outright
# rather than fabricating vectors.
embeddings_path="$package_dir/embeddings.json"
embeddings_url='http://embed-fixture.invalid:8080'
jq -n \
  --arg chunksPath "$chunks_path" \
  --arg artifactPath "$embeddings_path" '{
    action: "embed",
    paperId: "fixture-paper",
    chunksPath: $chunksPath,
    embedding: {
      endpoint: null,
      model: "qwen3-embedding-8b",
      batchSize: 16,
      dimensions: 4096
    },
    artifactPath: $artifactPath
  }' > "$work/embed-null-brief.json"
if TALLY_BRIEF="$work/embed-null-brief.json" \
  ACADEMIC_OCR_CURL="$fake_curl" \
  ACADEMIC_OCR_STATE_ROOT="$state" \
  academic-ocr-driver embed > "$work/embed-null.out" 2> "$work/embed-null.err"; then
  fail 'embed accepted a null endpoint'
fi
[[ ! -e $embeddings_path ]] || fail 'embed wrote an artifact without a backend'
grep -q 'ACADEMIC_OCR_EMBEDDINGS_URL was unset' "$work/embed-null.err" \
  || fail 'the null-endpoint refusal did not name the variable to set'

jq -n \
  --arg chunksPath "$chunks_path" \
  --arg endpoint "$embeddings_url" \
  --arg artifactPath "$embeddings_path" '{
    action: "embed",
    paperId: "fixture-paper",
    chunksPath: $chunksPath,
    embedding: {
      endpoint: $endpoint,
      model: "qwen3-embedding-8b",
      batchSize: 16,
      dimensions: 4096
    },
    artifactPath: $artifactPath
  }' > "$work/embed-brief.json"
run_action embed "$work/embed-brief.json" "$work/embed.out"
embed_summary=$(summary_from_output "$work/embed.out")
jq -e --arg endpoint "$embeddings_url" '
  .model == "qwen3-embedding-8b"
  and .endpoint == $endpoint
  and .dimensions == 4096
  and (.vectors | length > 0)
  and all(.vectors[]; .embedding | length == 4096)
' "$embeddings_path" >/dev/null

index_path="$package_dir/index/papers.db"
jq -n \
  --arg chunksPath "$chunks_path" \
  --arg embeddingsPath "$embeddings_path" \
  --arg artifactPath "$index_path" '{
    action: "index",
    paperId: "fixture-paper",
    chunksPath: $chunksPath,
    embeddingsPath: $embeddingsPath,
    artifactPath: $artifactPath
  }' > "$work/index-brief.json"
run_action index "$work/index-brief.json" "$work/index.out"
index_summary=$(summary_from_output "$work/index.out")
[[ $(sqlite3 -cmd ".load $sqlite_vec" "$index_path" 'PRAGMA integrity_check;') == ok ]] \
  || fail 'built index is not integral'
[[ $(sqlite3 -cmd ".load $sqlite_vec" "$index_path" 'SELECT count(*) FROM chunks;') -gt 0 ]] \
  || fail 'built index has no chunks'
[[ $(sqlite3 -cmd ".load $sqlite_vec" "$index_path" 'SELECT count(*) FROM chunks_vec;') -gt 0 ]] \
  || fail 'built index has no vectors'
nearest_distance=$(sqlite3 -cmd ".load $sqlite_vec" "$index_path" '
  SELECT distance
  FROM chunks_vec
  WHERE embedding MATCH (SELECT embedding FROM chunks_vec WHERE rowid = 1)
  ORDER BY distance
  LIMIT 1;
')
[[ $nearest_distance == 0.0 ]] || fail 'built vector index did not return an exact nearest neighbor'

receipt_path="$run_dir/receipt.json"
jq -n \
  --argjson selection "$selection" \
  --argjson assemble "$assemble_summary" \
  --argjson chunk "$chunk_summary" \
  --argjson embed "$embed_summary" \
  --argjson index "$index_summary" \
  --arg protocol "$vlm_protocol" \
  --arg outputDir "$package_dir" \
  --arg artifactPath "$receipt_path" '{
    action: "receipt",
    paper: {
      paperId: "fixture-paper",
      title: "Fixture Paper for Academic OCR",
      sourceUrl: "https://example.invalid/fixture.pdf",
      sourceSha256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    },
    pages: [$selection],
    protocols: [
      {id: "poppler-text", tier: "cheap"},
      {id: "mupdf-text", tier: "cheap"},
      {id: $protocol, tier: "standard"}
    ],
    outputDir: $outputDir,
    stages: {
      assemble: {result: $assemble, proof: {taskUuid: "a", witnessSeq: 1}},
      chunk: {result: $chunk, proof: {taskUuid: "b", witnessSeq: 2}},
      embed: {result: $embed, proof: {taskUuid: "c", witnessSeq: 3}},
      index: {result: $index, proof: {taskUuid: "d", witnessSeq: 4}}
    },
    artifactPath: $artifactPath
  }' > "$work/receipt-brief.json"
run_action receipt "$work/receipt-brief.json" "$work/receipt.out"
jq -e '
  .status == "complete"
  and .ocr.page_count == 1
  and .artifacts.embeddings.model == "qwen3-embedding-8b"
  and .artifacts.disposable_index.kind == "sqlite-vec+fts5"
  and .rebuild.embedding_model == "qwen3-embedding-8b"
  and .rebuild.index_is_disposable == true
  and (.rebuild.durable_inputs | length == 2)
' "$receipt_path" >/dev/null

# With no embeddings backend named, the flow hands the receipt null embed and
# index stages, and the receipt says so instead of pointing at nothing.
skipped_receipt_path="$package_dir/receipt.json"
jq '.stages.embed = null | .stages.index = null | .artifactPath = $path' \
  --arg path "$skipped_receipt_path" "$work/receipt-brief.json" > "$work/receipt-skipped-brief.json"
run_action receipt "$work/receipt-skipped-brief.json" "$work/receipt-skipped.out"
jq -e '
  .status == "complete"
  and .artifacts.embeddings.status == "skipped"
  and (.artifacts.embeddings.reason | contains("ACADEMIC_OCR_EMBEDDINGS_URL"))
  and .artifacts.disposable_index.status == "skipped"
  and .rebuild.embedding_model == "qwen3-embedding-8b"
' "$skipped_receipt_path" >/dev/null \
  || fail 'a receipt without embed and index stages did not record the skip'

ocr_flow_log="$run_dir/ocr-flow.jsonl"
jq -cn \
  --argjson selection "$selection" '{
    type: "flow-report",
    report: {
      flowRunId: "00000000-0000-4000-8000-000000000124",
      flowName: "academic-ocr",
      scriptHash: "fixture",
      ordinalKeys: [],
      observationOrder: [],
      finalValue: {
        schemaVersion: 1,
        pageCount: 1,
        convergedCount: 1,
        arbitratedCount: 0,
        configuredNodeUpperBound: 17,
        pages: [$selection]
      }
    }
  }' > "$ocr_flow_log"
assemble_args=$(env -u ACADEMIC_OCR_EMBEDDINGS_URL \
  academic-ocr-plan-assemble --ocr-args "$ocr_args" --flow-log "$ocr_flow_log" 2> "$work/plan.err")
[[ -f $assemble_args && -f $run_dir/ocr-result.json ]] || fail 'assemble planner did not retain its outputs'
jq -e '
  .paper.paperId == "fixture-paper"
  and (.pages | length == 1)
  and (.protocols | map(.id) | index("halogen-qwen3.8-flash-next") != null)
  and .embedding.endpoint == null
  and .embedding.model == "qwen3-embedding-8b"
  and .embedding.dimensions == 4096
' "$assemble_args" >/dev/null
grep -q 'ACADEMIC_OCR_EMBEDDINGS_URL is unset' "$work/plan.err" \
  || fail 'the planner did not announce the skipped embedding stage'
embedded_args=$(ACADEMIC_OCR_EMBEDDINGS_URL="$embeddings_url" \
  academic-ocr-plan-assemble --ocr-args "$ocr_args" --flow-log "$ocr_flow_log" \
    --output "$run_dir/assemble-args-embedded.json")
jq -e --arg endpoint "$embeddings_url" '.embedding.endpoint == $endpoint' "$embedded_args" >/dev/null \
  || fail 'the planner did not carry the named embeddings backend into the args'
if ACADEMIC_OCR_EMBEDDINGS_URL='not-a-url' \
  academic-ocr-plan-assemble --ocr-args "$ocr_args" --flow-log "$ocr_flow_log" \
    --output "$run_dir/assemble-args-bad.json" > /dev/null 2> "$work/plan-bad.err"; then
  fail 'the planner accepted a malformed embeddings URL'
fi
grep -q 'not an http(s) URL' "$work/plan-bad.err" || fail 'the planner did not explain the malformed URL'

printf 'academic-ocr fixture tests passed (jitter=%s, different=%s, mechanical=%s permille)\n' \
  "$jitter_disagreement" "$different_disagreement" "$mechanical_disagreement"
