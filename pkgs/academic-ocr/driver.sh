set -euo pipefail

ocr_prompt='Transcribe this scanned academic page to clean GitHub-flavored Markdown. Preserve heading levels, paragraphs, footnotes, and tables (as markdown tables). Use $...$ / $$...$$ for math. Do not add commentary. If part is illegible write [illegible].'
llama_swap_url=${ACADEMIC_OCR_LLAMA_SWAP_URL:-http://localhost:9292}

# A visual transcription that hits the cap comes back as a plausible prefix, so
# its signature still agrees with the mechanical extraction well enough for the
# flow to converge on a page that has silently lost its tail. Fail closed below
# 600 permille of the longest mechanical extraction of the same page, and only
# where that extraction is long enough to vouch for the page at all. Lengths are
# counted in the whitespace words the rest of the pipeline counts.
vlm_max_tokens=4096
voucher_min_words=200
voucher_min_permille=600
curl_cmd=${ACADEMIC_OCR_CURL:-curl}
chunk_awk=${ACADEMIC_OCR_CHUNK_AWK:?ACADEMIC_OCR_CHUNK_AWK is not set}
sqlite_vec=${ACADEMIC_OCR_SQLITE_VEC:?ACADEMIC_OCR_SQLITE_VEC is not set}
state_base=${XDG_STATE_HOME:-${HOME:?HOME is not set}/.local/state}
state_root=${ACADEMIC_OCR_STATE_ROOT:-$state_base/academic-ocr}

usage() {
  printf 'usage: academic-ocr-driver <recognize|arbitrate|assemble|chunk|embed|index|receipt|failure>\n' >&2
  exit 2
}

[[ $# -eq 1 ]] || usage
action=$1
case $action in
  recognize|arbitrate|assemble|chunk|embed|index|receipt|failure) ;;
  *) usage ;;
esac

die() {
  printf 'academic-ocr-driver: %s\n' "$*" >&2
  exit 1
}

die_code() {
  local code=$1
  shift
  printf 'academic-ocr-driver: %s\n' "$*" >&2
  exit "$code"
}

[[ $state_root = /* && $state_root != / ]] || die 'data root must be an absolute non-root path'
state_root=$(realpath -m -- "$state_root")
notes_root=$(realpath -m -- "${HOME:?HOME is not set}/mecattaf/notes")
case $state_root in
  "$notes_root"|"$notes_root"/*) die 'data root must not be inside ~/mecattaf/notes' ;;
esac

brief_path=${TALLY_BRIEF:-}
[[ -n $brief_path && -f $brief_path ]] || die 'TALLY_BRIEF must name a readable JSON file'
jq -e 'type == "object"' "$brief_path" >/dev/null || die 'TALLY_BRIEF is not a JSON object'
brief_action=$(jq -er '.action' "$brief_path") || die 'brief has no action'
[[ $brief_action == "$action" ]] || die "brief action $brief_action does not match argv action $action"

work_dir=$(mktemp -d)
cleanup() {
  if [[ -d $work_dir ]]; then
    rm -r -- "$work_dir"
  fi
}
trap cleanup EXIT

is_absolute_path() {
  [[ $1 = /* && $1 != *$'\n'* && $1 != *$'\r'* ]]
}

require_absolute_path() {
  local label=$1 path=$2
  is_absolute_path "$path" || die "$label must be an absolute single-line path"
}

require_state_path() {
  local label=$1 path=$2 resolved
  require_absolute_path "$label" "$path"
  resolved=$(realpath -m -- "$path")
  case $resolved in
    "$state_root"/*) ;;
    *) die "$label escapes the academic OCR data root" ;;
  esac
}

require_paper_id() {
  [[ $1 =~ ^[A-Za-z0-9._-]+$ ]] || die 'paperId contains unsafe characters'
}

sha_prefixed() {
  printf 'sha256:%s\n' "$(sha256sum "$1" | awk '{print $1}')"
}

atomic_move() {
  local source=$1 destination=$2
  chmod 0644 "$source"
  mv -f -- "$source" "$destination"
}

emit_artifact_fields() {
  local artifact=$1 filter=$2
  printf 'TALLY_FINAL_MESSAGE='
  jq -c "$filter" "$artifact"
}

normalize_text() {
  local source=$1 destination=$2
  tr -d '\f' < "$source" \
    | sed 's/[[:space:]]\+$//' \
    | gawk '
        /^[[:space:]]*$/ {
          blanks++
          if (blanks <= 1) print ""
          next
        }
        {
          blanks = 0
          print
        }
      ' > "$destination"
  if [[ -s $destination ]] && [[ $(tail -c 1 "$destination" | wc -l) -eq 0 ]]; then
    printf '\n' >> "$destination"
  fi
}

require_substantive_text() {
  local text_file=$1 protocol=$2
  local alnum_count word_count
  alnum_count=$(tr -cd '[:alnum:]' < "$text_file" | wc -c)
  word_count=$(wc -w < "$text_file")
  if (( alnum_count < 32 || word_count < 6 )); then
    die_code 20 "$protocol extraction is empty or near-empty ($alnum_count alphanumeric characters, $word_count words)"
  fi
}

require_pdf() {
  local source=$1 magic
  [[ -f $source ]] || die "source PDF is missing: $source"
  magic=$(head -c 5 "$source" || true)
  [[ $magic == '%PDF-' ]] || die "source does not have PDF magic bytes: $source"
}

render_page() {
  local source=$1 page=$2 dpi=$3 destination=$4 prefix
  prefix="$work_dir/render-$RANDOM"
  pdftoppm \
    -f "$page" \
    -l "$page" \
    -r "$dpi" \
    -png \
    -singlefile \
    "$source" \
    "$prefix" >/dev/null 2>&1 || die "failed to render page $page at $dpi DPI"
  [[ -f $prefix.png ]] || die "page renderer produced no PNG for page $page"
  mv -- "$prefix.png" "$destination"
}

prepare_raster() {
  local source=$1 page=$2 artifact=$3
  local input_id mutation_kind destination base cached dpi zones_count
  input_id=$(jq -er '.input.id' "$brief_path")
  mutation_kind=$(jq -er '.input.mutation.kind' "$brief_path")
  destination=${artifact%.json}.png
  mkdir -p "$(dirname "$destination")"
  base="$work_dir/base.png"

  case $mutation_kind in
    none)
      cached="${source%.pdf}.pages/200dpi/$(printf 'page-%04d.png' "$page")"
      if [[ -f $cached ]]; then
        cp --reflink=auto -- "$cached" "$base"
      else
        render_page "$source" "$page" 200 "$base"
      fi
      ;;
    rerasterize)
      dpi=$(jq -er '.input.mutation.dpi | select(type == "number" and . >= 200 and . <= 1200)' "$brief_path") \
        || die 'rerasterize mutation has an invalid DPI'
      render_page "$source" "$page" "$dpi" "$base"
      ;;
    crop-hot-zones)
      render_page "$source" "$page" 200 "$base"
      zones_count=$(jq -er '.input.mutation.zones | length' "$brief_path") \
        || die 'crop-hot-zones mutation has no zones array'
      if (( zones_count == 0 )); then
        magick "$base" -fuzz 3% -trim +repage "$work_dir/mutated.png" \
          || die 'ImageMagick whitespace crop failed'
      else
        read -r image_width image_height < <(magick identify -format '%w %h' "$base")
        read -r min_x min_y max_x max_y < <(
          jq -r '
            [
              ([.input.mutation.zones[].x] | min),
              ([.input.mutation.zones[].y] | min),
              ([.input.mutation.zones[] | .x + .width] | max),
              ([.input.mutation.zones[] | .y + .height] | max)
            ] | @tsv
          ' "$brief_path"
        )
        crop_x=$(( min_x * image_width / 10000 ))
        crop_y=$(( min_y * image_height / 10000 ))
        crop_right=$(( (max_x * image_width + 9999) / 10000 ))
        crop_bottom=$(( (max_y * image_height + 9999) / 10000 ))
        (( crop_x < 0 )) && crop_x=0
        (( crop_y < 0 )) && crop_y=0
        (( crop_right > image_width )) && crop_right=$image_width
        (( crop_bottom > image_height )) && crop_bottom=$image_height
        crop_width=$(( crop_right - crop_x ))
        crop_height=$(( crop_bottom - crop_y ))
        (( crop_width > 0 && crop_height > 0 )) || die 'hot-zone crop is empty'
        magick "$base" -crop "${crop_width}x${crop_height}+${crop_x}+${crop_y}" +repage "$work_dir/mutated.png" \
          || die 'ImageMagick hot-zone crop failed'
      fi
      base="$work_dir/mutated.png"
      ;;
    deskew)
      render_page "$source" "$page" 200 "$base"
      correction=$(jq -er '.input.mutation.correctionMilliDegrees | select(type == "number" and . >= -45000 and . <= 45000)' "$brief_path") \
        || die 'deskew mutation has an invalid correction'
      degrees=$(gawk -v milli="$correction" 'BEGIN { printf "%.3f", milli / 1000 }')
      magick "$base" -background white -rotate "$degrees" "$work_dir/mutated.png" \
        || die 'ImageMagick deskew rotation failed'
      base="$work_dir/mutated.png"
      ;;
    *)
      die "unsupported input mutation: $mutation_kind"
      ;;
  esac

  [[ -s $base ]] || die "mutation $input_id produced an empty raster"
  raster_tmp="$work_dir/final-raster.png"
  cp --reflink=auto -- "$base" "$raster_tmp"
  atomic_move "$raster_tmp" "$destination"
  printf '%s\n' "$destination"
}

strip_markdown_fence() {
  local source=$1 destination=$2
  sed \
    -e '1{/^```\(markdown\)\{0,1\}[[:space:]]*$/d;}' \
    -e '${/^```[[:space:]]*$/d;}' \
    "$source" > "$destination"
}

require_local_llama_swap() {
  local endpoint=$1
  case $endpoint in
    http://localhost:9292) ;;
    *) die "inference endpoint must be llama-swap on localhost:9292, got $endpoint" ;;
  esac
}

count_words() {
  local words
  words=$(wc -w < "$1")
  printf '%s\n' "$words"
}

# The longest mechanical extraction of this page, or 0 when none is on hand.
# Both ruled mechanical engines refuse raster mutations, so a voucher can only
# ever be the original input, and a scanned page has no voucher at all.
mechanical_voucher_words() {
  local page_dir=$1 paper_id=$2 page_number=$3
  local protocol voucher_path words best=0
  for protocol in poppler-text mupdf-text; do
    voucher_path="$page_dir/$protocol/original.json"
    [[ -f $voucher_path ]] || continue
    jq -e \
      --arg paper "$paper_id" \
      --argjson page "$page_number" \
      --arg protocol "$protocol" \
      '.action == "recognize"
        and .paperId == $paper
        and .pageNumber == $page
        and .protocolId == $protocol
        and .inputVariant == "original"
        and (.text | type == "string" and length > 0)' \
      "$voucher_path" >/dev/null || continue
    jq -jr '.text' "$voucher_path" > "$work_dir/voucher-$protocol.md"
    words=$(count_words "$work_dir/voucher-$protocol.md")
    if (( words > best )); then
      best=$words
    fi
  done
  printf '%s\n' "$best"
}

require_untruncated_vlm() {
  local text_file=$1 protocol=$2 artifact_path=$3 paper_id=$4 page_number=$5
  local page_dir voucher_words candidate_words floor_words
  page_dir=$(dirname "$(dirname "$artifact_path")")
  voucher_words=$(mechanical_voucher_words "$page_dir" "$paper_id" "$page_number")
  (( voucher_words >= voucher_min_words )) || return 0
  candidate_words=$(count_words "$text_file")
  floor_words=$(( voucher_words * voucher_min_permille / 1000 ))
  if (( candidate_words < floor_words )); then
    die_code 20 "$protocol transcribed $candidate_words words against a $voucher_words-word mechanical voucher, under the $floor_words-word floor: the page is truncated"
  fi
}

run_vlm() {
  local raster=$1 model=$2 output=$3
  local b64_file payload response content
  require_local_llama_swap "$llama_swap_url"
  b64_file="$work_dir/page.b64"
  payload="$work_dir/chat-request.json"
  response="$work_dir/chat-response.json"
  base64 -w 0 "$raster" > "$b64_file"
  jq -Rs \
    --arg model "$model" \
    --arg prompt "$ocr_prompt" \
    --argjson maxTokens "$vlm_max_tokens" \
    '{
      model: $model,
      temperature: 0,
      max_tokens: $maxTokens,
      messages: [{
        role: "user",
        content: [
          {type: "text", text: $prompt},
          {type: "image_url", image_url: {url: ("data:image/png;base64," + .)}}
        ]
      }]
    }' "$b64_file" > "$payload"
  "$curl_cmd" \
    --fail \
    --retry 1 \
    --retry-all-errors \
    --show-error \
    --silent \
    --max-time 900 \
    --header 'Content-Type: application/json' \
    --data-binary "@$payload" \
    "$llama_swap_url/v1/chat/completions" > "$response" \
    || die "llama-swap request failed for $model"
  jq -e '.choices[0].message.content | type == "string" and length > 0' "$response" >/dev/null \
    || die "llama-swap returned no text content for $model"
  vlm_finish_reason=$(jq -r '.choices[0].finish_reason // ""' "$response")
  # The cap is the one truncation the server reports outright. It is the only
  # signal available for a scanned page, which has no mechanical voucher.
  [[ $vlm_finish_reason != length ]] \
    || die_code 20 "$model stopped at the $vlm_max_tokens-token cap (finish_reason=length): the page is truncated"
  content="$work_dir/vlm-content.md"
  jq -jr '.choices[0].message.content' "$response" > "$content"
  strip_markdown_fence "$content" "$work_dir/vlm-unfenced.md"
  normalize_text "$work_dir/vlm-unfenced.md" "$output"
}

recognize() {
  local paper_id page_number source_path protocol_id protocol_tier input_id artifact_path
  local text_raw text_file raster_path engine_input engine_page confidence engine_version
  paper_id=$(jq -er '.page.paperId' "$brief_path")
  page_number=$(jq -er '.page.pageNumber | select(type == "number" and . >= 1)' "$brief_path")
  source_path=$(jq -er '.page.sourcePath' "$brief_path")
  protocol_id=$(jq -er '.protocol.id' "$brief_path")
  protocol_tier=$(jq -er '.protocol.tier' "$brief_path")
  input_id=$(jq -er '.input.id' "$brief_path")
  artifact_path=$(jq -er '.artifactPath' "$brief_path")
  require_state_path sourcePath "$source_path"
  require_state_path artifactPath "$artifact_path"
  require_paper_id "$paper_id"
  [[ $protocol_id =~ ^[A-Za-z0-9._-]+$ ]] || die 'protocolId contains unsafe characters'
  require_pdf "$source_path"
  mkdir -p "$(dirname "$artifact_path")"

  case $protocol_id:$protocol_tier in
    poppler-text:cheap|mupdf-text:cheap|qwen3-vl-8b-ocr:standard|qwen3-vl-32b-ocr:specialist) ;;
    *) die "unsupported protocol/tier pair: $protocol_id/$protocol_tier" ;;
  esac

  text_raw="$work_dir/raw.txt"
  text_file="$work_dir/text.md"
  raster_path=''
  engine_input=$source_path
  engine_page=$page_number
  vlm_finish_reason=''

  if [[ $protocol_id == qwen3-vl-* || $input_id != original ]]; then
    raster_path=$(prepare_raster "$source_path" "$page_number" "$artifact_path")
  fi
  if [[ $protocol_id == poppler-text || $protocol_id == mupdf-text ]]; then
    if [[ $input_id != original ]]; then
      # The ladder's transformed input is intentionally a raster. Neither
      # ruled mechanical engine performs OCR, so treating it as text evidence
      # would be false convergence. Fail this protocol/input pair closed.
      die_code 20 "$protocol_id cannot extract a text layer from raster mutation $input_id"
    fi
    if [[ $protocol_id == poppler-text ]]; then
      pdftotext -f "$engine_page" -l "$engine_page" -layout "$engine_input" - > "$text_raw" 2> "$work_dir/engine.err" \
        || die 'pdftotext failed'
      engine_version=$(pdftotext -v 2>&1 | head -n 1)
    else
      mutool draw -q -F txt -o "$text_raw" "$engine_input" "$engine_page" 2> "$work_dir/engine.err" \
        || die 'mutool text extraction failed'
      engine_version=$(mutool -v 2>&1 | head -n 1)
    fi
    normalize_text "$text_raw" "$text_file"
    require_substantive_text "$text_file" "$protocol_id"
    confidence=1000
  else
    run_vlm "$raster_path" "$protocol_id" "$text_file"
    require_substantive_text "$text_file" "$protocol_id"
    require_untruncated_vlm "$text_file" "$protocol_id" "$artifact_path" "$paper_id" "$page_number"
    engine_version=$protocol_id
    if [[ $protocol_id == qwen3-vl-8b-ocr ]]; then
      confidence=900
    else
      confidence=850
    fi
  fi

  signature=$(academic-ocr-signature "$text_file")
  text_digest=$(sha_prefixed "$text_file")
  source_digest=$(sha_prefixed "$source_path")
  if [[ -n $raster_path ]]; then
    input_path=$raster_path
  else
    input_path=$source_path
  fi
  input_digest=$(sha_prefixed "$input_path")
  prompt_digest=$(printf '%s' "$ocr_prompt" | sha256sum | awk '{print "sha256:" $1}')
  artifact_tmp=$(mktemp "$(dirname "$artifact_path")/.recognition.XXXXXX")
  jq -n \
    --arg paperId "$paper_id" \
    --argjson pageNumber "$page_number" \
    --arg protocolId "$protocol_id" \
    --arg protocolTier "$protocol_tier" \
    --arg inputVariant "$input_id" \
    --arg artifactPath "$artifact_path" \
    --arg sourcePath "$source_path" \
    --arg sourceDigest "$source_digest" \
    --arg inputPath "$input_path" \
    --arg inputDigest "$input_digest" \
    --arg textDigest "$text_digest" \
    --arg engineVersion "$engine_version" \
    --arg endpoint "$llama_swap_url" \
    --arg promptDigest "$prompt_digest" \
    --arg finishReason "$vlm_finish_reason" \
    --argjson wordCount "$(count_words "$text_file")" \
    --argjson signature "$signature" \
    --argjson confidencePermille "$confidence" \
    --argjson input "$(jq -c '.input' "$brief_path")" \
    --rawfile text "$text_file" \
    '{
      schemaVersion: 1,
      action: "recognize",
      paperId: $paperId,
      pageNumber: $pageNumber,
      protocolId: $protocolId,
      protocolTier: $protocolTier,
      inputVariant: $inputVariant,
      input: $input,
      artifactPath: $artifactPath,
      sourcePath: $sourcePath,
      inputPath: $inputPath,
      text: $text,
      textDigest: $textDigest,
      signature: $signature,
      wordCount: $wordCount,
      confidencePermille: $confidencePermille,
      hotZones: [],
      skewMilliDegrees: 0,
      provenance: {
        sourceDigest: $sourceDigest,
        inputDigest: $inputDigest,
        engine: $engineVersion,
        endpoint: (if ($protocolId | startswith("qwen3-vl-")) then $endpoint else null end),
        promptDigest: (if ($protocolId | startswith("qwen3-vl-")) then $promptDigest else null end),
        finishReason: (if ($finishReason | length > 0) then $finishReason else null end)
      }
    }' > "$artifact_tmp"
  atomic_move "$artifact_tmp" "$artifact_path"
  emit_artifact_fields "$artifact_path" '{
    paperId,
    pageNumber,
    protocolId,
    inputVariant,
    artifactPath,
    textDigest,
    signature,
    wordCount,
    confidencePermille,
    hotZones,
    skewMilliDegrees
  }'
}

arbitrate() {
  local paper_id page_number artifact_path selected_path text_digest artifact_tmp
  paper_id=$(jq -er '.page.paperId' "$brief_path")
  page_number=$(jq -er '.page.pageNumber | select(type == "number" and . >= 1)' "$brief_path")
  artifact_path=$(jq -er '.artifactPath' "$brief_path")
  require_state_path artifactPath "$artifact_path"
  require_paper_id "$paper_id"
  mkdir -p "$(dirname "$artifact_path")"

  mapfile -t candidate_paths < <(
    jq -r '.attempts[] | select(.verdict == "pass") | .artifactPath // empty' "$brief_path" | sort -u
  )
  basis_paths=()
  for candidate in "${candidate_paths[@]}"; do
    require_state_path candidateArtifactPath "$candidate"
    [[ -f $candidate ]] || continue
    mapfile -t expected_digests < <(
      jq -r --arg path "$candidate" '
        .attempts[]
        | select(.verdict == "pass" and .artifactPath == $path)
        | .textDigest
      ' "$brief_path" | sort -u
    )
    (( ${#expected_digests[@]} == 1 )) || die "candidate has ambiguous evidence: $candidate"
    jq -e \
      --arg paper "$paper_id" \
      --argjson page "$page_number" \
      --arg digest "${expected_digests[0]}" \
      '.paperId == $paper
        and .pageNumber == $page
        and .textDigest == $digest
        and (.text | type == "string" and length > 0)' \
      "$candidate" >/dev/null || die "candidate artifact has the wrong identity: $candidate"
    basis_paths+=("$candidate")
  done
  (( ${#basis_paths[@]} > 0 )) || die 'arbiter has no successful artifact basis'

  # The ladder can still hand the arbiter a truncated visual candidate when the
  # mechanical voucher was not yet on disk at recognition time. Such a candidate
  # outranks every mechanical extraction and, being a prefix, reads as the
  # longest plausible transcription, so drop it before ranking rather than
  # after. A page whose whole basis is truncated is disputed, not resolved.
  voucher_words=0
  for candidate in "${basis_paths[@]}"; do
    jq -e '.protocolId == "poppler-text" or .protocolId == "mupdf-text"' "$candidate" >/dev/null || continue
    jq -jr '.text' "$candidate" > "$work_dir/basis-text.md"
    candidate_words=$(count_words "$work_dir/basis-text.md")
    if (( candidate_words > voucher_words )); then
      voucher_words=$candidate_words
    fi
  done
  floor_words=$(( voucher_words * voucher_min_permille / 1000 ))
  ranked_paths=()
  truncated_paths=()
  for candidate in "${basis_paths[@]}"; do
    if (( voucher_words >= voucher_min_words )) \
      && jq -e '.protocolId | startswith("qwen3-vl-")' "$candidate" >/dev/null; then
      jq -jr '.text' "$candidate" > "$work_dir/basis-text.md"
      candidate_words=$(count_words "$work_dir/basis-text.md")
      if (( candidate_words < floor_words )); then
        truncated_paths+=("$candidate")
        continue
      fi
    fi
    ranked_paths+=("$candidate")
  done
  (( ${#ranked_paths[@]} > 0 )) \
    || die_code 20 "every arbiter candidate falls under the $floor_words-word floor of a $voucher_words-word mechanical voucher: the page is truncated"

  selected_path=$(jq -sr '
    def rank:
      if .protocolId == "qwen3-vl-32b-ocr" then 0
      elif .protocolId == "qwen3-vl-8b-ocr" then 1
      elif .protocolId == "poppler-text" then 2
      elif .protocolId == "mupdf-text" then 3
      else 4 end;
    sort_by([rank, -(.text | length), .artifactPath]) | .[0].artifactPath
  ' "${ranked_paths[@]}")
  [[ -f $selected_path ]] || die 'arbiter selection did not resolve to an artifact'
  jq -jr '.text' "$selected_path" > "$work_dir/arbitrated.md"
  require_substantive_text "$work_dir/arbitrated.md" arbiter
  text_digest=$(sha_prefixed "$work_dir/arbitrated.md")
  selected_digest=$(jq -er '.textDigest' "$selected_path")
  [[ $text_digest == "$selected_digest" ]] || die 'selected artifact text digest does not verify'
  basis_json=$(printf '%s\n' "${ranked_paths[@]}" | jq -Rsc 'split("\n")[:-1]')
  if (( ${#truncated_paths[@]} > 0 )); then
    truncated_json=$(printf '%s\n' "${truncated_paths[@]}" | jq -Rsc 'split("\n")[:-1]')
  else
    truncated_json='[]'
  fi

  artifact_tmp=$(mktemp "$(dirname "$artifact_path")/.arbiter.XXXXXX")
  jq -n \
    --arg paperId "$paper_id" \
    --argjson pageNumber "$page_number" \
    --arg artifactPath "$artifact_path" \
    --arg selectedArtifactPath "$selected_path" \
    --arg textDigest "$text_digest" \
    --argjson basis "$basis_json" \
    --argjson truncated "$truncated_json" \
    --argjson voucherWords "$voucher_words" \
    --rawfile text "$work_dir/arbitrated.md" \
    '{
      schemaVersion: 1,
      action: "arbitrate",
      paperId: $paperId,
      pageNumber: $pageNumber,
      artifactPath: $artifactPath,
      text: $text,
      textDigest: $textDigest,
      basis: $basis,
      truncatedArtifactPaths: $truncated,
      selectedArtifactPath: $selectedArtifactPath,
      provenance: {
        strategy: "specialist-first-then-longest",
        voucherWords: $voucherWords
      }
    }' > "$artifact_tmp"
  atomic_move "$artifact_tmp" "$artifact_path"
  emit_artifact_fields "$artifact_path" \
    '{paperId, pageNumber, artifactPath, textDigest, basis, truncatedArtifactPaths}'
}

assemble() {
  local paper_id title source_url source_sha output_dir artifact_path canonical_dir pages_dir
  paper_id=$(jq -er '.paper.paperId' "$brief_path")
  title=$(jq -er '.paper.title' "$brief_path")
  source_url=$(jq -er '.paper.sourceUrl' "$brief_path")
  source_sha=$(jq -er '.paper.sourceSha256 | select(test("^[0-9a-f]{64}$"))' "$brief_path")
  output_dir=$(jq -er '.outputDir' "$brief_path")
  artifact_path=$(jq -er '.artifactPath' "$brief_path")
  require_state_path outputDir "$output_dir"
  require_state_path artifactPath "$artifact_path"
  require_paper_id "$paper_id"
  [[ $artifact_path == "$output_dir/canonical/manifest.json" ]] || die 'assemble artifactPath is not the canonical manifest path'
  canonical_dir="$output_dir/canonical"
  pages_dir="$canonical_dir/pages"
  mkdir -p "$pages_dir"

  page_manifest="$work_dir/page-manifest.json"
  printf '{"pages":[]}\n' > "$page_manifest"
  paper_tmp="$work_dir/paper.md"
  title_yaml=$(jq -nr --arg value "$title" '$value | tojson')
  url_yaml=$(jq -nr --arg value "$source_url" '$value | tojson')
  {
    printf '%s\n' '---'
    printf 'uuid: %s\n' "$paper_id"
    printf 'title: %s\n' "$title_yaml"
    printf 'sha256: %s\n' "$source_sha"
    printf 'source_url: %s\n' "$url_yaml"
    printf '%s\n\n' '---'
  } > "$paper_tmp"

  expected_page=1
  while IFS= read -r selection; do
    page_number=$(jq -er '.pageNumber' <<< "$selection")
    selected_paper=$(jq -er '.paperId' <<< "$selection")
    chosen_path=$(jq -er '.chosenArtifactPath' <<< "$selection")
    chosen_digest=$(jq -er '.textDigest' <<< "$selection")
    [[ $selected_paper == "$paper_id" ]] || die "page $page_number belongs to the wrong paper"
    (( page_number == expected_page )) || die "page selection is not contiguous at page $page_number"
    require_state_path chosenArtifactPath "$chosen_path"
    [[ -f $chosen_path ]] || die "chosen page artifact is missing: $chosen_path"
    jq -e \
      --arg paper "$paper_id" \
      --argjson page "$page_number" \
      '.paperId == $paper and .pageNumber == $page and (.text | type == "string")' \
      "$chosen_path" >/dev/null || die "chosen artifact identity mismatch: $chosen_path"
    jq -jr '.text' "$chosen_path" > "$work_dir/page.md"
    actual_digest=$(sha_prefixed "$work_dir/page.md")
    [[ $actual_digest == "$chosen_digest" ]] || die "page $page_number digest does not verify"

    page_md=$(printf '%s/%03d.md' "$pages_dir" "$page_number")
    page_json=$(printf '%s/%03d.json' "$pages_dir" "$page_number")
    page_tmp=$(mktemp "$pages_dir/.page-md.XXXXXX")
    cp -- "$work_dir/page.md" "$page_tmp"
    atomic_move "$page_tmp" "$page_md"
    artifact_sha=$(sha256sum "$chosen_path" | awk '{print $1}')
    meta_tmp=$(mktemp "$pages_dir/.page-meta.XXXXXX")
    jq -n \
      --argjson selection "$selection" \
      --arg artifactSha256 "$artifact_sha" \
      --arg canonicalPath "$page_md" \
      '{
        schemaVersion: 1,
        pageNumber: $selection.pageNumber,
        canonicalPath: $canonicalPath,
        chosenArtifactPath: $selection.chosenArtifactPath,
        chosenArtifactSha256: $artifactSha256,
        textDigest: $selection.textDigest,
        resolution: $selection.resolution,
        inputVariant: $selection.inputVariant,
        disagreementPermille: $selection.disagreementPermille,
        agreementProtocols: $selection.agreementProtocols,
        attemptCount: $selection.attemptCount,
        proof: $selection.proof
      }' > "$meta_tmp"
    atomic_move "$meta_tmp" "$page_json"
    page_md_digest=$(sha_prefixed "$page_md")
    page_meta_digest=$(sha_prefixed "$page_json")
    jq \
      --argjson pageNumber "$page_number" \
      --arg markdownPath "$page_md" \
      --arg markdownDigest "$page_md_digest" \
      --arg metadataPath "$page_json" \
      --arg metadataDigest "$page_meta_digest" \
      '.pages += [{
        pageNumber: $pageNumber,
        markdownPath: $markdownPath,
        markdownDigest: $markdownDigest,
        metadataPath: $metadataPath,
        metadataDigest: $metadataDigest
      }]' "$page_manifest" > "$work_dir/page-manifest.next"
    mv -f -- "$work_dir/page-manifest.next" "$page_manifest"

    {
      printf '<!-- page:%03d -->\n' "$page_number"
      cat "$work_dir/page.md"
      printf '\n'
    } >> "$paper_tmp"
    expected_page=$((expected_page + 1))
  done < <(jq -c '.pages | sort_by(.pageNumber)[]' "$brief_path")
  page_count=$((expected_page - 1))
  (( page_count > 0 )) || die 'assemble received no page selections'

  paper_path="$canonical_dir/paper.md"
  paper_atomic=$(mktemp "$canonical_dir/.paper.XXXXXX")
  cp -- "$paper_tmp" "$paper_atomic"
  atomic_move "$paper_atomic" "$paper_path"
  paper_digest=$(sha_prefixed "$paper_path")
  source_path="$output_dir/source.json"
  source_tmp=$(mktemp "$output_dir/.source.XXXXXX")
  jq -n \
    --arg paperId "$paper_id" \
    --arg title "$title" \
    --arg sourceUrl "$source_url" \
    --arg sourceSha256 "$source_sha" \
    --argjson pageCount "$page_count" \
    '{
      schemaVersion: 1,
      uuid: $paperId,
      title: $title,
      sourceUrl: $sourceUrl,
      sha256: $sourceSha256,
      pageCount: $pageCount
    }' > "$source_tmp"
  atomic_move "$source_tmp" "$source_path"
  source_digest=$(sha_prefixed "$source_path")

  manifest_tmp=$(mktemp "$canonical_dir/.manifest.XXXXXX")
  jq -n \
    --slurpfile pageManifest "$page_manifest" \
    --arg paperId "$paper_id" \
    --arg paperPath "$paper_path" \
    --arg paperDigest "$paper_digest" \
    --arg sourcePath "$source_path" \
    --arg sourceDigest "$source_digest" \
    '{
      schemaVersion: 1,
      paperId: $paperId,
      paperPath: $paperPath,
      paperDigest: $paperDigest,
      sourcePath: $sourcePath,
      sourceDigest: $sourceDigest,
      pages: $pageManifest[0].pages
    }' > "$manifest_tmp"
  atomic_move "$manifest_tmp" "$artifact_path"
  artifact_digest=$(sha_prefixed "$artifact_path")
  printf 'TALLY_FINAL_MESSAGE='
  jq -cn \
    --arg paperId "$paper_id" \
    --arg artifactPath "$artifact_path" \
    --arg artifactDigest "$artifact_digest" \
    --arg paperPath "$paper_path" \
    --arg paperDigest "$paper_digest" \
    --argjson pageCount "$page_count" \
    '{paperId: $paperId, artifactPath: $artifactPath, artifactDigest: $artifactDigest, paperPath: $paperPath, paperDigest: $paperDigest, pageCount: $pageCount}'
}

chunk() {
  local paper_id paper_path artifact_path target_words embedding_model
  paper_id=$(jq -er '.paperId' "$brief_path")
  paper_path=$(jq -er '.paperPath' "$brief_path")
  artifact_path=$(jq -er '.artifactPath' "$brief_path")
  target_words=$(jq -er '.chunkWords | select(type == "number" and . >= 64 and . <= 2048)' "$brief_path")
  embedding_model=$(jq -er '.embeddingModel' "$brief_path")
  require_state_path paperPath "$paper_path"
  require_state_path artifactPath "$artifact_path"
  require_paper_id "$paper_id"
  [[ -f $paper_path ]] || die "canonical paper is missing: $paper_path"
  mkdir -p "$(dirname "$artifact_path")"
  chunks_dir="$work_dir/chunks"
  mkdir -p "$chunks_dir"
  gawk \
    -v out_dir="$chunks_dir" \
    -v target_words="$target_words" \
    -f "$chunk_awk" \
    "$paper_path"
  [[ -s $chunks_dir/manifest.tsv ]] || die 'chunker produced no chunks'

  title_literal=$(sed -n 's/^title: //p' "$paper_path" | head -n 1)
  title=$(jq -er '.' <<< "$title_literal" 2>/dev/null || printf 'Untitled')
  chunks_json="$work_dir/chunks.json"
  jq -n \
    --arg paperUuid "$paper_id" \
    --arg sourceMd "$paper_path" \
    --arg chunker "academic-ocr.awk-word-chunker(chunk_size=$target_words)" \
    --arg embeddingModel "$embedding_model" \
    '{
      schema_version: 1,
      paper_uuid: $paperUuid,
      source_md: $sourceMd,
      chunker: $chunker,
      embed_model_version: $embeddingModel,
      chunks: []
    }' > "$chunks_json"

  chunk_count=0
  while IFS=$'\t' read -r index start end page_start page_end word_count section; do
    chunk_file=$(printf '%s/chunk-%04d.txt' "$chunks_dir" "$index")
    [[ -s $chunk_file ]] || die "chunk body is missing: $chunk_file"
    content_hash=$(sha256sum "$chunk_file" | awk '{print substr($1, 1, 12)}')
    chunk_id=$(printf '%s\0%s\0%s\0%s' "$paper_id" "$index" "$content_hash" "$embedding_model" \
      | sha256sum | awk '{print substr($1, 1, 16)}')
    if [[ -n $section ]]; then
      prefix="[$title] | [$section]"
    else
      prefix="[$title]"
    fi
    chunk_object=$(jq -n \
      --arg id "$chunk_id" \
      --rawfile text "$chunk_file" \
      --arg prefix "$prefix" \
      --arg section "$section" \
      --arg modelVersion "$embedding_model" \
      --argjson pageStart "$page_start" \
      --argjson pageEnd "$page_end" \
      --argjson start "$start" \
      --argjson end "$end" \
      --argjson tokenCount "$word_count" \
      '{
        id: $id,
        text: $text,
        prefix: $prefix,
        embed_text: ($prefix + "\n" + $text),
        section: $section,
        page_start: $pageStart,
        page_end: $pageEnd,
        start: $start,
        end: $end,
        token_count: $tokenCount,
        model_version: $modelVersion
      }')
    jq --argjson chunk "$chunk_object" '.chunks += [$chunk]' "$chunks_json" > "$work_dir/chunks.next"
    mv -f -- "$work_dir/chunks.next" "$chunks_json"
    chunk_count=$((chunk_count + 1))
  done < "$chunks_dir/manifest.tsv"
  (( chunk_count > 0 )) || die 'chunk manifest was empty'

  artifact_tmp=$(mktemp "$(dirname "$artifact_path")/.chunks.XXXXXX")
  cp -- "$chunks_json" "$artifact_tmp"
  atomic_move "$artifact_tmp" "$artifact_path"
  artifact_digest=$(sha_prefixed "$artifact_path")
  printf 'TALLY_FINAL_MESSAGE='
  jq -cn \
    --arg paperId "$paper_id" \
    --arg artifactPath "$artifact_path" \
    --arg artifactDigest "$artifact_digest" \
    --arg embeddingModel "$embedding_model" \
    --argjson chunkCount "$chunk_count" \
    '{paperId: $paperId, artifactPath: $artifactPath, artifactDigest: $artifactDigest, chunkCount: $chunkCount, embeddingModel: $embeddingModel}'
}

embed() {
  local paper_id chunks_path artifact_path endpoint model batch_size dimensions chunk_count
  paper_id=$(jq -er '.paperId' "$brief_path")
  chunks_path=$(jq -er '.chunksPath' "$brief_path")
  artifact_path=$(jq -er '.artifactPath' "$brief_path")
  endpoint=$(jq -er '.embedding.endpoint' "$brief_path")
  model=$(jq -er '.embedding.model' "$brief_path")
  batch_size=$(jq -er '.embedding.batchSize | select(type == "number" and . >= 1 and . <= 64)' "$brief_path")
  dimensions=$(jq -er '.embedding.dimensions | select(. == 4096)' "$brief_path")
  require_state_path chunksPath "$chunks_path"
  require_state_path artifactPath "$artifact_path"
  require_paper_id "$paper_id"
  require_local_llama_swap "$endpoint"
  [[ $model == qwen3-embedding-8b ]] || die "unsupported embedding model: $model"
  [[ -f $chunks_path ]] || die "chunks are missing: $chunks_path"
  chunk_count=$(jq -er '.chunks | length | select(. > 0)' "$chunks_path") || die 'chunks file has no chunks'
  mkdir -p "$(dirname "$artifact_path")"

  embeddings_json="$work_dir/embeddings.json"
  chunks_digest=$(sha_prefixed "$chunks_path")
  jq -n \
    --arg paperId "$paper_id" \
    --arg chunksPath "$chunks_path" \
    --arg chunksDigest "$chunks_digest" \
    --arg model "$model" \
    --arg endpoint "$endpoint" \
    --argjson dimensions "$dimensions" \
    '{
      schema_version: 1,
      paper_uuid: $paperId,
      chunks_path: $chunksPath,
      chunks_digest: $chunksDigest,
      model: $model,
      endpoint: $endpoint,
      dimensions: $dimensions,
      vectors: []
    }' > "$embeddings_json"

  for ((start = 0; start < chunk_count; start += batch_size)); do
    end=$((start + batch_size))
    (( end > chunk_count )) && end=$chunk_count
    request="$work_dir/embed-request-$start.json"
    response="$work_dir/embed-response-$start.json"
    jq \
      --arg model "$model" \
      --argjson start "$start" \
      --argjson end "$end" \
      '{model: $model, input: [.chunks[$start:$end][] | .embed_text]}' \
      "$chunks_path" > "$request"
    "$curl_cmd" \
      --fail \
      --retry 1 \
      --retry-all-errors \
      --show-error \
      --silent \
      --max-time 900 \
      --header 'Content-Type: application/json' \
      --data-binary "@$request" \
      "$endpoint/v1/embeddings" > "$response" \
      || die "llama-swap embedding request failed for chunks $start through $((end - 1))"
    expected_batch=$((end - start))
    jq -e \
      --argjson count "$expected_batch" \
      --argjson dimensions "$dimensions" '
        (.data | length) == $count
        and ([.data[].index] | sort == [range(0; $count)])
        and all(.data[]; (.embedding | type == "array" and length == $dimensions))
      ' "$response" >/dev/null || die "embedding response for batch $start has the wrong shape"
    jq -n \
      --slurpfile response "$response" \
      --slurpfile chunks "$chunks_path" \
      --argjson start "$start" '
        [$response[0].data[]
          | {id: $chunks[0].chunks[$start + .index].id, embedding: .embedding}
        ]
      ' > "$work_dir/embed-batch.json"
    jq --slurpfile batch "$work_dir/embed-batch.json" '.vectors += $batch[0]' "$embeddings_json" > "$work_dir/embeddings.next"
    mv -f -- "$work_dir/embeddings.next" "$embeddings_json"
  done
  jq -e --argjson count "$chunk_count" '.vectors | length == $count' "$embeddings_json" >/dev/null \
    || die 'embedding artifact is incomplete'

  artifact_tmp=$(mktemp "$(dirname "$artifact_path")/.embeddings.XXXXXX")
  cp -- "$embeddings_json" "$artifact_tmp"
  atomic_move "$artifact_tmp" "$artifact_path"
  artifact_digest=$(sha_prefixed "$artifact_path")
  printf 'TALLY_FINAL_MESSAGE='
  jq -cn \
    --arg paperId "$paper_id" \
    --arg artifactPath "$artifact_path" \
    --arg artifactDigest "$artifact_digest" \
    --arg model "$model" \
    --argjson vectorCount "$chunk_count" \
    --argjson dimensions "$dimensions" \
    '{paperId: $paperId, artifactPath: $artifactPath, artifactDigest: $artifactDigest, vectorCount: $vectorCount, dimensions: $dimensions, model: $model}'
}

index_artifacts() {
  local paper_id chunks_path embeddings_path artifact_path chunk_count vector_count
  paper_id=$(jq -er '.paperId' "$brief_path")
  chunks_path=$(jq -er '.chunksPath' "$brief_path")
  embeddings_path=$(jq -er '.embeddingsPath' "$brief_path")
  artifact_path=$(jq -er '.artifactPath' "$brief_path")
  require_state_path chunksPath "$chunks_path"
  require_state_path embeddingsPath "$embeddings_path"
  require_state_path artifactPath "$artifact_path"
  require_paper_id "$paper_id"
  [[ -f $chunks_path ]] || die "chunks are missing: $chunks_path"
  [[ -f $embeddings_path ]] || die "embeddings are missing: $embeddings_path"
  case $chunks_path:$embeddings_path in
    *[!A-Za-z0-9_./:-]*) die 'index input paths contain unsupported characters' ;;
  esac
  chunk_count=$(jq -er '.chunks | length | select(. > 0)' "$chunks_path") || die 'chunks file has no chunks'
  vector_count=$(jq -er '.vectors | length | select(. > 0)' "$embeddings_path") || die 'embeddings file has no vectors'
  (( chunk_count == vector_count )) || die 'chunk/vector count mismatch'
  mkdir -p "$(dirname "$artifact_path")"
  database_tmp=$(mktemp "$(dirname "$artifact_path")/.papers.XXXXXX.db")

  sqlite3 -cmd ".load $sqlite_vec" "$database_tmp" >/dev/null <<SQL
.bail on
PRAGMA journal_mode = DELETE;
PRAGMA synchronous = FULL;
CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE chunks (
  rowid INTEGER PRIMARY KEY,
  id TEXT NOT NULL UNIQUE,
  uuid TEXT NOT NULL,
  page_start INTEGER NOT NULL,
  page_end INTEGER NOT NULL,
  section TEXT NOT NULL,
  text TEXT NOT NULL,
  embed_text TEXT NOT NULL
);
CREATE VIRTUAL TABLE chunks_fts USING fts5(id UNINDEXED, text, tokenize = 'unicode61');
CREATE VIRTUAL TABLE chunks_vec USING vec0(embedding float[4096]);
WITH
  chunk_rows AS (
    SELECT key, value FROM json_each(CAST(readfile('$chunks_path') AS TEXT), '$.chunks')
  )
INSERT INTO chunks (rowid, id, uuid, page_start, page_end, section, text, embed_text)
SELECT
  CAST(c.key AS INTEGER) + 1,
  json_extract(c.value, '$.id'),
  '$paper_id',
  json_extract(c.value, '$.page_start'),
  json_extract(c.value, '$.page_end'),
  json_extract(c.value, '$.section'),
  json_extract(c.value, '$.text'),
  json_extract(c.value, '$.embed_text')
FROM chunk_rows AS c
ORDER BY CAST(c.key AS INTEGER);
WITH vector_rows AS (
  SELECT value FROM json_each(CAST(readfile('$embeddings_path') AS TEXT), '$.vectors')
)
INSERT INTO chunks_vec (rowid, embedding)
SELECT
  c.rowid,
  json_extract(v.value, '$.embedding')
FROM chunks AS c
JOIN vector_rows AS v ON json_extract(v.value, '$.id') = c.id
ORDER BY c.rowid;
INSERT INTO chunks_fts (rowid, id, text) SELECT rowid, id, text FROM chunks ORDER BY rowid;
INSERT INTO metadata VALUES ('schema_version', '1');
INSERT INTO metadata VALUES ('paper_uuid', '$paper_id');
INSERT INTO metadata VALUES ('chunks_sha256', '$(sha256sum "$chunks_path" | awk '{print $1}')');
INSERT INTO metadata VALUES ('embeddings_sha256', '$(sha256sum "$embeddings_path" | awk '{print $1}')');
VACUUM;
SQL
  integrity=$(sqlite3 -cmd ".load $sqlite_vec" "$database_tmp" 'PRAGMA integrity_check;')
  [[ $integrity == ok ]] || die "SQLite integrity check failed: $integrity"
  indexed_count=$(sqlite3 -cmd ".load $sqlite_vec" "$database_tmp" 'SELECT count(*) FROM chunks;')
  fts_count=$(sqlite3 -cmd ".load $sqlite_vec" "$database_tmp" 'SELECT count(*) FROM chunks_fts;')
  vector_indexed_count=$(sqlite3 -cmd ".load $sqlite_vec" "$database_tmp" 'SELECT count(*) FROM chunks_vec;')
  (( indexed_count == chunk_count && fts_count == chunk_count && vector_indexed_count == chunk_count )) \
    || die 'SQLite indexes are incomplete'
  atomic_move "$database_tmp" "$artifact_path"
  artifact_digest=$(sha_prefixed "$artifact_path")
  printf 'TALLY_FINAL_MESSAGE='
  jq -cn \
    --arg paperId "$paper_id" \
    --arg artifactPath "$artifact_path" \
    --arg artifactDigest "$artifact_digest" \
    --argjson chunkCount "$chunk_count" \
    '{paperId: $paperId, artifactPath: $artifactPath, artifactDigest: $artifactDigest, chunkCount: $chunkCount, indexKind: "sqlite-vec+fts5"}'
}

receipt() {
  local paper_id artifact_path output_dir
  paper_id=$(jq -er '.paper.paperId' "$brief_path")
  artifact_path=$(jq -er '.artifactPath' "$brief_path")
  output_dir=$(jq -er '.outputDir' "$brief_path")
  require_state_path artifactPath "$artifact_path"
  require_state_path outputDir "$output_dir"
  require_paper_id "$paper_id"
  [[ $artifact_path == "$(dirname "$output_dir")/receipt.json" || $artifact_path == "$output_dir/receipt.json" ]] \
    || die 'receipt path is outside the run/package boundary'
  mkdir -p "$(dirname "$artifact_path")"
  generated_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  converged_count=$(jq '[.pages[] | select(.status == "converged")] | length' "$brief_path")
  arbitrated_count=$(jq '[.pages[] | select(.status == "arbitrated")] | length' "$brief_path")
  page_count=$(jq '.pages | length' "$brief_path")
  receipt_tmp=$(mktemp "$(dirname "$artifact_path")/.receipt.XXXXXX")
  jq -n \
    --slurpfile brief "$brief_path" \
    --arg generatedAt "$generated_at" \
    --argjson pageCount "$page_count" \
    --argjson convergedCount "$converged_count" \
    --argjson arbitratedCount "$arbitrated_count" '
      {
        schema_version: 1,
        status: "complete",
        generated_at: $generatedAt,
        paper: $brief[0].paper,
        protocols: $brief[0].protocols,
        ocr: {
          page_count: $pageCount,
          converged_count: $convergedCount,
          arbitrated_count: $arbitratedCount,
          pages: $brief[0].pages
        },
        stages: $brief[0].stages,
        artifacts: {
          canonical_manifest: {
            path: $brief[0].stages.assemble.result.artifactPath,
            digest: $brief[0].stages.assemble.result.artifactDigest
          },
          paper_markdown: {
            path: $brief[0].stages.assemble.result.paperPath,
            digest: $brief[0].stages.assemble.result.paperDigest
          },
          chunks: {
            path: $brief[0].stages.chunk.result.artifactPath,
            digest: $brief[0].stages.chunk.result.artifactDigest
          },
          embeddings: {
            path: $brief[0].stages.embed.result.artifactPath,
            digest: $brief[0].stages.embed.result.artifactDigest,
            model: $brief[0].stages.embed.result.model
          },
          disposable_index: {
            path: $brief[0].stages.index.result.artifactPath,
            digest: $brief[0].stages.index.result.artifactDigest,
            kind: $brief[0].stages.index.result.indexKind
          }
        },
        rebuild: {
          durable_inputs: [
            $brief[0].stages.assemble.result.paperPath,
            $brief[0].stages.chunk.result.artifactPath
          ],
          embedding_model: $brief[0].stages.embed.result.model,
          index_is_disposable: true
        }
      }
    ' > "$receipt_tmp"
  atomic_move "$receipt_tmp" "$artifact_path"
  artifact_digest=$(sha_prefixed "$artifact_path")
  printf 'TALLY_FINAL_MESSAGE='
  jq -cn \
    --arg paperId "$paper_id" \
    --arg artifactPath "$artifact_path" \
    --arg artifactDigest "$artifact_digest" \
    '{status: "complete", paperId: $paperId, artifactPath: $artifactPath, artifactDigest: $artifactDigest}'
}

failure() {
  local paper_id artifact_path generated_at receipt_tmp
  paper_id=$(jq -er '.paper.paperId' "$brief_path")
  artifact_path=$(jq -er '.artifactPath' "$brief_path")
  require_state_path artifactPath "$artifact_path"
  require_paper_id "$paper_id"
  mkdir -p "$(dirname "$artifact_path")"
  generated_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  receipt_tmp=$(mktemp "$(dirname "$artifact_path")/.receipt-failure.XXXXXX")
  jq -n \
    --slurpfile brief "$brief_path" \
    --arg generatedAt "$generated_at" '{
      schema_version: 1,
      status: "failed",
      generated_at: $generatedAt,
      paper: $brief[0].paper,
      error: $brief[0].error
    }' > "$receipt_tmp"
  atomic_move "$receipt_tmp" "$artifact_path"
  artifact_digest=$(sha_prefixed "$artifact_path")
  printf 'TALLY_FINAL_MESSAGE='
  jq -cn \
    --arg paperId "$paper_id" \
    --arg artifactPath "$artifact_path" \
    --arg artifactDigest "$artifact_digest" \
    '{status: "failed", paperId: $paperId, artifactPath: $artifactPath, artifactDigest: $artifactDigest}'
}

case $action in
  recognize) recognize ;;
  arbitrate) arbitrate ;;
  assemble) assemble ;;
  chunk) chunk ;;
  embed) embed ;;
  index) index_artifacts ;;
  receipt) receipt ;;
  failure) failure ;;
esac
