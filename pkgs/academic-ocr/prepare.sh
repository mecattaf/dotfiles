set -euo pipefail

paper_catalog=${ACADEMIC_OCR_PAPER_CATALOG:?ACADEMIC_OCR_PAPER_CATALOG is not set}
paper_profile=turner
url_override=''
sha_override=''
paper_id_override=''
title_override=''
expected_pages_override=''
source_file=''
state_base=${XDG_STATE_HOME:-${HOME:?HOME is not set}/.local/state}
state_root="$state_base/academic-ocr"
runtime_max_sec=1800

usage() {
  cat >&2 <<'EOF'
usage: academic-ocr-prepare [options]

Options:
  --paper NAME             fixed paper profile: turner or fosfuri (default: turner)
  --url URL                override the profile's public PDF URL
  --sha256 HEX             expected PDF sha256
  --paper-id ID            safe paper/database identifier
  --title TITLE            canonical title
  --expected-pages N       expected page count; 0 disables the exact check
  --state-root PATH        data root (default: $XDG_STATE_HOME/academic-ocr)
  --source-file PATH       offline/local source instead of HTTP fetch
  --runtime-max-sec N      per OCR child deadline written to flow args
EOF
  exit 2
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --paper)
      [[ $# -ge 2 ]] || usage
      paper_profile=$2
      shift 2
      ;;
    --url)
      [[ $# -ge 2 ]] || usage
      url_override=$2
      shift 2
      ;;
    --sha256)
      [[ $# -ge 2 ]] || usage
      sha_override=$2
      shift 2
      ;;
    --paper-id)
      [[ $# -ge 2 ]] || usage
      paper_id_override=$2
      shift 2
      ;;
    --title)
      [[ $# -ge 2 ]] || usage
      title_override=$2
      shift 2
      ;;
    --expected-pages)
      [[ $# -ge 2 ]] || usage
      expected_pages_override=$2
      shift 2
      ;;
    --state-root)
      [[ $# -ge 2 ]] || usage
      state_root=$2
      shift 2
      ;;
    --source-file)
      [[ $# -ge 2 ]] || usage
      source_file=$2
      shift 2
      ;;
    --runtime-max-sec)
      [[ $# -ge 2 ]] || usage
      runtime_max_sec=$2
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      printf 'academic-ocr-prepare: unknown option: %s\n' "$1" >&2
      usage
      ;;
  esac
done

die() {
  printf 'academic-ocr-prepare: %s\n' "$*" >&2
  exit 1
}

[[ -f $paper_catalog ]] || die "fixed-paper catalog is missing: $paper_catalog"
profile_json=$(jq -cer --arg profile "$paper_profile" '
  .[$profile]
  | select(type == "object")
  | select(.paperId | type == "string")
  | select(.title | type == "string")
  | select(.sourceUrl | type == "string")
  | select(.sourceSha256 | type == "string")
  | select(.expectedPages | type == "number")
' "$paper_catalog") || die "unknown or invalid fixed-paper profile: $paper_profile"

url=${url_override:-$(jq -r '.sourceUrl' <<< "$profile_json")}
expected_sha=${sha_override:-$(jq -r '.sourceSha256' <<< "$profile_json")}
paper_id=${paper_id_override:-$(jq -r '.paperId' <<< "$profile_json")}
title=${title_override:-$(jq -r '.title' <<< "$profile_json")}
expected_pages=${expected_pages_override:-$(jq -r '.expectedPages' <<< "$profile_json")}

[[ $expected_sha =~ ^[0-9a-f]{64}$ ]] || die 'sha256 must be 64 lowercase hexadecimal characters'
[[ $paper_id =~ ^[A-Za-z0-9._-]+$ ]] || die 'paper-id contains unsafe characters'
[[ -n $title ]] || die 'title must not be empty'
[[ $expected_pages =~ ^[0-9]+$ ]] || die 'expected-pages must be a non-negative integer'
[[ $runtime_max_sec =~ ^[1-9][0-9]*$ ]] || die 'runtime-max-sec must be positive'
[[ $state_root = /* && $state_root != / ]] || die 'state-root must be an absolute non-root path'
state_root=$(realpath -m -- "$state_root")
notes_root=$(realpath -m -- "${HOME:?HOME is not set}/mecattaf/notes")
case $state_root in
  "$notes_root"|"$notes_root"/*) die 'state-root must not be inside ~/mecattaf/notes' ;;
esac
[[ $url == https://* ]] || die 'source URL must use https'
if [[ -n $source_file ]]; then
  [[ -f $source_file ]] || die "source-file is not a regular file: $source_file"
fi

curl_cmd=${ACADEMIC_OCR_CURL:-curl}
driver_path=${ACADEMIC_OCR_DRIVER_PATH:?ACADEMIC_OCR_DRIVER_PATH is not set}
blob_dir="$state_root/blobs/sha256"
blob_path="$blob_dir/$expected_sha.pdf"
render_dir="$blob_dir/$expected_sha.pages/200dpi"
run_dir="$state_root/runs/$paper_id-${expected_sha:0:12}"
source_manifest="$run_dir/source.json"
ocr_args="$run_dir/ocr-args.json"
mkdir -p "$blob_dir" "$render_dir" "$run_dir"

tmp_download=''
cleanup() {
  if [[ -n $tmp_download && -e $tmp_download ]]; then
    rm -f -- "$tmp_download"
  fi
}
trap cleanup EXIT

verify_pdf() {
  local candidate=$1
  local actual_sha magic
  actual_sha=$(sha256sum "$candidate" | awk '{print $1}')
  [[ $actual_sha == "$expected_sha" ]] || die "sha256 mismatch: expected $expected_sha, got $actual_sha"
  magic=$(head -c 5 "$candidate" || true)
  [[ $magic == '%PDF-' ]] || die 'source does not have PDF magic bytes'
}

if [[ -e $blob_path ]]; then
  [[ -f $blob_path ]] || die "content-addressed blob path is not a regular file: $blob_path"
  verify_pdf "$blob_path"
else
  tmp_download=$(mktemp "$blob_dir/.academic-ocr-download.XXXXXX")
  if [[ -n $source_file ]]; then
    cp --reflink=auto -- "$source_file" "$tmp_download"
  else
    "$curl_cmd" \
      --fail \
      --location \
      --proto '=https' \
      --retry 2 \
      --retry-all-errors \
      --show-error \
      --silent \
      --output "$tmp_download" \
      "$url"
  fi
  verify_pdf "$tmp_download"
  chmod 0444 "$tmp_download"
  mv -n -- "$tmp_download" "$blob_path"
  tmp_download=''
  verify_pdf "$blob_path"
fi

page_count=$(pdfinfo "$blob_path" | awk '$1 == "Pages:" { print $2; exit }')
[[ $page_count =~ ^[1-9][0-9]*$ ]] || die 'pdfinfo did not return a positive page count'
(( page_count <= 100 )) || die "page count $page_count exceeds the OCR flow bound of 100"
if (( expected_pages > 0 && page_count != expected_pages )); then
  die "page-count mismatch: expected $expected_pages, got $page_count"
fi

png_magic='89504e470d0a1a0a'
for ((page = 1; page <= page_count; page++)); do
  page_path=$(printf '%s/page-%04d.png' "$render_dir" "$page")
  if [[ -f $page_path ]]; then
    actual_magic=$(head -c 8 "$page_path" | od -An -tx1 | tr -d ' \n')
    [[ $actual_magic == "$png_magic" ]] || die "cached render has invalid PNG magic: $page_path"
    continue
  fi
  render_tmp_dir=$(mktemp -d "$render_dir/.page-${page}.XXXXXX")
  render_prefix="$render_tmp_dir/render"
  if ! pdftoppm \
    -f "$page" \
    -l "$page" \
    -r 200 \
    -png \
    -singlefile \
    "$blob_path" \
    "$render_prefix" >/dev/null 2>&1; then
    rm -r -- "$render_tmp_dir"
    die "pdftoppm failed to render page $page"
  fi
  render_tmp="$render_prefix.png"
  if [[ ! -f $render_tmp ]]; then
    rm -r -- "$render_tmp_dir"
    die "pdftoppm did not render page $page"
  fi
  actual_magic=$(head -c 8 "$render_tmp" | od -An -tx1 | tr -d ' \n')
  [[ $actual_magic == "$png_magic" ]] || die "rendered page $page is not PNG"
  chmod 0444 "$render_tmp"
  mv -n -- "$render_tmp" "$page_path"
  rm -r -- "$render_tmp_dir"
done

source_tmp=$(mktemp "$run_dir/.source.XXXXXX")
jq -n \
  --arg paperId "$paper_id" \
  --arg title "$title" \
  --arg sourceUrl "$url" \
  --arg sourceSha256 "$expected_sha" \
  --arg blobPath "$blob_path" \
  --arg renderDir "$render_dir" \
  --argjson pageCount "$page_count" \
  '{
    schemaVersion: 1,
    paperId: $paperId,
    title: $title,
    sourceUrl: $sourceUrl,
    sourceSha256: $sourceSha256,
    blobPath: $blobPath,
    renderDpi: 200,
    renderDir: $renderDir,
    pageCount: $pageCount
  }' > "$source_tmp"
chmod 0444 "$source_tmp"
mv -f -- "$source_tmp" "$source_manifest"

pages=$(jq -cn \
  --arg paperId "$paper_id" \
  --arg sourcePath "$blob_path" \
  --argjson count "$page_count" \
  '[range(1; $count + 1) | {
    paperId: $paperId,
    pageNumber: .,
    sourcePath: $sourcePath
  }]')

args_tmp=$(mktemp "$run_dir/.ocr-args.XXXXXX")
jq -n \
  --argjson pages "$pages" \
  --arg program "$driver_path" \
  --arg outputDir "$run_dir/ocr" \
  --argjson runtimeMaxSec "$runtime_max_sec" \
  '{
    pages: $pages,
    protocols: [
      {id: "poppler-text", tier: "cheap"},
      {id: "mupdf-text", tier: "cheap"},
      {id: "qwen3-vl-8b-ocr", tier: "standard"},
      {id: "qwen3-vl-32b-ocr", tier: "specialist"}
    ],
    driver: {
      adapter: "ocr-driver",
      program: $program,
      runtimeMaxSec: $runtimeMaxSec
    },
    outputDir: $outputDir,
    rasterDpi: 400,
    maxMutationIterations: 3,
    maxDisagreementPermille: 375
  }' > "$args_tmp"
chmod 0444 "$args_tmp"
mv -f -- "$args_tmp" "$ocr_args"

printf '%s\n' "$ocr_args"
