set -euo pipefail

ocr_args=''
flow_log=''
output=''

usage() {
  printf 'usage: academic-ocr-plan-assemble --ocr-args PATH --flow-log PATH [--output PATH]\n' >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --ocr-args)
      [[ $# -ge 2 ]] || usage
      ocr_args=$2
      shift 2
      ;;
    --flow-log)
      [[ $# -ge 2 ]] || usage
      flow_log=$2
      shift 2
      ;;
    --output)
      [[ $# -ge 2 ]] || usage
      output=$2
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      usage
      ;;
  esac
done

die() {
  printf 'academic-ocr-plan-assemble: %s\n' "$*" >&2
  exit 1
}

[[ -f $ocr_args ]] || die "OCR args are not a file: $ocr_args"
[[ -f $flow_log ]] || die "flow log is not a file: $flow_log"
run_dir=$(dirname "$ocr_args")
source_manifest="$run_dir/source.json"
[[ -f $source_manifest ]] || die "source manifest is missing: $source_manifest"
if [[ -z $output ]]; then
  output="$run_dir/assemble-args.json"
fi
[[ $output = /* ]] || die 'output must be an absolute path'

ocr_result_tmp=$(mktemp "$run_dir/.ocr-result.XXXXXX")
cleanup() {
  if [[ -e $ocr_result_tmp ]]; then
    rm -f -- "$ocr_result_tmp"
  fi
}
trap cleanup EXIT

jq -sc '
  [ .[]
    | select(.type == "flow-report")
    | select(.report.flowName == "academic-ocr")
    | .report.finalValue
  ]
  | last // error("no completed academic-ocr flow-report in log")
  | select(.schemaVersion == 1)
  | select(.pageCount == (.pages | length))
' "$flow_log" > "$ocr_result_tmp"
jq -e '.pages | length > 0' "$ocr_result_tmp" >/dev/null \
  || die 'OCR result has no pages'
jq -e --slurpfile source "$source_manifest" '
  . as $result
  | $source[0] as $paper
  | $result.pageCount == $paper.pageCount
    and ([ $result.pages[].paperId ] | all(. == $paper.paperId))
    and ([ $result.pages[].pageNumber ] | sort == [range(1; $paper.pageCount + 1)])
' "$ocr_result_tmp" >/dev/null \
  || die 'OCR result does not match the prepared paper identity and page census'

ocr_result="$run_dir/ocr-result.json"
chmod 0444 "$ocr_result_tmp"
mv -f -- "$ocr_result_tmp" "$ocr_result"

driver_path=${ACADEMIC_OCR_DRIVER_PATH:?ACADEMIC_OCR_DRIVER_PATH is not set}
output_dir="$run_dir/package"
receipt_path="$run_dir/receipt.json"
output_tmp=$(mktemp "$run_dir/.assemble-args.XXXXXX")
jq -n \
  --slurpfile source "$source_manifest" \
  --slurpfile ocr "$ocr_result" \
  --slurpfile ocrArgs "$ocr_args" \
  --arg program "$driver_path" \
  --arg outputDir "$output_dir" \
  --arg receiptPath "$receipt_path" \
  '{
    paper: {
      paperId: $source[0].paperId,
      title: $source[0].title,
      sourceUrl: $source[0].sourceUrl,
      sourceSha256: $source[0].sourceSha256
    },
    pages: $ocr[0].pages,
    protocols: $ocrArgs[0].protocols,
    driver: {
      adapter: "ocr-driver",
      program: $program,
      runtimeMaxSec: 1800
    },
    outputDir: $outputDir,
    receiptPath: $receiptPath,
    chunkWords: 512,
    embedding: {
      endpoint: "http://localhost:9292",
      model: "qwen3-embedding-8b",
      batchSize: 16,
      dimensions: 4096
    }
  }' > "$output_tmp"

jq -e '
  .paper.paperId != ""
  and (.paper.sourceSha256 | test("^[0-9a-f]{64}$"))
  and (.pages | length > 0)
' "$output_tmp" >/dev/null || die 'generated assemble args are invalid'
chmod 0444 "$output_tmp"
mv -f -- "$output_tmp" "$output"
printf '%s\n' "$output"
