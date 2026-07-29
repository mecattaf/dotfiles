# Academic OCR

This package implements the bounded coordinator-only slice in dotfiles issue
`#124`. It keeps all source blobs, renders, protocol artifacts, canonical files,
chunks, embeddings, the disposable SQLite index, and receipts below:

```text
~/.local/state/academic-ocr/
```

It never writes to `~/mecattaf/notes`. Promotion into notes is a later,
supervised operator decision. The fixed `turner` and `fosfuri` profiles carry
the two ruled db IDs, source URLs, hashes, and page counts. In particular, the
Fosfuri profile keeps db ID `96b65260-610c-4404-a08f-98b0e3ebc6d9` even though
its source filename contains the unrelated UUID `491cfaeb-…`.

## Programs

- `academic-paper-archive` creates an index-preserving LaCie mirror of the
  Cloudflare paper corpus. Its `init` command imports an untouched D1 SQL
  export, frozen sidecars, prior purge records, and OCR provenance into a
  local SQLite catalog keyed by the original `db_id`; `mirror` copies genuine
  PDFs and recovers PDFs linked by mislabeled HTML landing pages;
  `recover-history` indexes LaCie candidates and restores prior purges with
  hash/path provenance; `reconstruct-facsimiles` creates explicitly labeled
  image PDFs only where the OCR corpus retained every rendered page;
  `recover-web` uses landing-page DOIs, Crossref, and Unpaywall to locate
  title-checked open copies; `recover-live-library` retries exact-title links
  from the live Effectuation catalog; `recover-url` attaches a manually found
  public-repository PDF to its existing D1 ID. PDF identity is checked against
  the first three pages, with OCR fallback for scanned or corrupt text layers;
  `verify` checks the catalog/file invariants. It never deletes from D1 or R2.
- `academic-ocr-prepare` fetches and verifies the PDF, performs the page
  census, renders the immutable 200 DPI page inputs, and prints the absolute
  path of the OCR flow-args manifest.
- `academic-ocr-driver` is the direct tally adapter program. Its `recognize`
  and `arbitrate` actions implement the upstream mutation-ladder contract; the
  other actions implement the second flow's bounded stages.
- `academic-ocr-plan-assemble` extracts the final value from a completed OCR
  flow JSONL log, retains it as `ocr-result.json`, and prints the second flow's
  args path.
- `academic-ocr-signature` exposes the deterministic 32-component text
  signature used by recognition artifacts.

## Supervised two-flow sequence

These commands describe the operator phase for both fixed papers. Do not run
them merely to validate the package or generation.

```bash
run_paper() {
  local profile=$1 ocr_args run_dir config ocr_flow assemble_args assemble_flow
  ocr_args=$(academic-ocr-prepare --paper "$profile")
  run_dir=$(dirname "$ocr_args")
  config=${XDG_CONFIG_HOME:-$HOME/.config}/tally/config.json
  ocr_flow=$(jq -r '.flows["academic-ocr"].script' "$config")

  tally flow check "$ocr_flow" --args "$(<"$ocr_args")"
  tally flow run "$ocr_flow" \
    --flow-run-id "$(</proc/sys/kernel/random/uuid)" \
    --args "$(<"$ocr_args")" \
    --max-nodes 1700 \
    | tee "$run_dir/ocr-flow.jsonl"

  assemble_args=$(
    academic-ocr-plan-assemble \
      --ocr-args "$ocr_args" \
      --flow-log "$run_dir/ocr-flow.jsonl"
  )
  assemble_flow=$(jq -r '.flows["academic-assemble"].script' "$config")

  tally flow check "$assemble_flow" --args "$(<"$assemble_args")"
  tally flow run "$assemble_flow" \
    --flow-run-id "$(</proc/sys/kernel/random/uuid)" \
    --args "$(<"$assemble_args")" \
    --max-nodes 6 \
    | tee "$run_dir/assemble-flow.jsonl"
}

run_paper turner
run_paper fosfuri
```

The success receipt lands at:

```text
<run-dir>/receipt.json
```

For the fixed Turner input, `<run-dir>` is
`~/.local/state/academic-ocr/runs/fa3c575a-3089-4d27-957f-ba7d697b8737-aa9db49df221`;
for Fosfuri it is
`~/.local/state/academic-ocr/runs/96b65260-610c-4404-a08f-98b0e3ebc6d9-909a82261bc9`.
The durable rebuild inputs named in the receipt are `canonical/paper.md` and
`chunks.json`. `embeddings.json` and the SQLite `sqlite-vec` + FTS5 index at
`index/papers.db` are disposable; rerun the embedding and index nodes from the
retained chunks when rebuilding them.

## Protocol and inference boundary

The cheap tier is `pdftotext` plus `mutool`, both of which exit nonzero for
empty or near-empty extraction. The standard and specialist tiers are
`qwen3-vl-8b-ocr` and `qwen3-vl-32b-ocr`. The embedding node uses
`qwen3-embedding-8b`. Every model request goes through the OpenAI-compatible
llama-swap endpoint at `http://localhost:9292`, with temperature zero for OCR.

Package builds run ShellCheck and generated fixture tests entirely offline.
The tests cover both mechanical engines, fail-closed scan handling, signature
agreement/disagreement, a stubbed VLM/embedding boundary, canonical assembly,
chunking, SQLite index construction, receipt emission, and args planning.
