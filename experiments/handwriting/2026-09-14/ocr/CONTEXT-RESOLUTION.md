# Context hints for Qwen's hardest handwriting

The useful analogy from [the voice-mode investigation](/home/tom/Downloads/claude-voice-learnings.md)
is a compact vocabulary hint list. That investigation reports that the voice client
sends keyterms, **not the chat transcript**, and leaves the server-side mechanism
unconfirmed. This OCR proposal deliberately adds explicit, local conversation
context; it is not a claim about Claude's undisclosed speech server.

## Proposed resolution heuristic

Keep the fast, unassisted page pass. Have it report the location, raw reading,
alternatives and difficulty of ambiguous spans. Only `hard` and `unreadable` enter
context resolution. The existing benchmark prompt reports uncertainty but **does
not report severity**; that schema still needs a measured first-pass experiment.
Self-reported severity is an uncalibrated routing signal, not a certainty percentage.

For an eligible span:

1. Retrieve similar spellings from a small, explicitly selected context scope:
   recent user messages, project glossary terms and writer-confirmed notebook words.
   Keep provenance and a context cutoff. Assistant output and unconfirmed OCR labels
   must not become evidence for their own correction.
2. Rank a shortlist using spelling similarity to the raw word and Qwen's alternatives,
   with small contributions from recency and occurrence in separate messages. For
   now the prototype uses 85% similarity, 10% recency, 5% frequency and at most five
   hints. These weights and the 0.65 similarity cutoff are starting heuristics,
   **not learned values or confidence probabilities**.
3. Give Qwen the original crop with line context, original alternatives, selected
   context words and relevant confirmed handwriting examples if available. Ask it
   to compare visible letter shapes, including the option that none fits.
4. Return `keep`, `interpret`, or `unresolved`. Preserve `raw_visible_text` separately
   from an `interpreted_term`, so recognizing a familiar name does not silently
   rewrite literal handwriting. Record what context contributed and retain the
   first-pass output.

Example: the image may visibly say `Huyon`, while the notebook/project context
suggests the intended device is `Huion`. It is useful to identify that relationship
without declaring the extra context to be proof of an i on the page.

A page budget of two local retries bounds the initial prototype. Further hard
spans are explicitly deferred, not discarded or marked resolved. Unreadable spans
are queued first; this policy can change with measurements. If the crop is unreadable,
a context word cannot supply missing visual evidence. A human/frontier review can
remain available after local retries, but nothing is automatically sent externally.

## Concrete prototype and demonstration

[context_hints.py](context_hints.py) builds candidate packets. It does not call a
model, crop images, patch transcripts, or deploy an inbox consumer. It reads only
explicitly supplied Codex JSONL files and confirmed-term JSON lists. Session input
is restricted to user messages; it skips injected AGENTS/environment blocks and
fenced or blockquoted content. Ordinary user messages can still contain typos or
pasted text, so their words remain weak vocabulary evidence, not confirmed labels.

The [demo packet](runs/context-hints-demo/candidates.json) takes Qwen's reported
`Huyon` / `Hygon` uncertainty and retrieves only **huion**, found in two earlier
user messages. Its context cutoff is 2026-09-14 07:27 UTC, before the first Halogen
OCR run. Assistant transcriptions and later discussion were excluded. The ordinary
`stuff` / `styff` uncertainty is left at the first pass.

The demo's difficulty labels were manually assigned to exercise the routing rule;
the original Qwen response did not rank them. This demonstrates candidate retrieval
and provenance, **not successful visual resolution or improved OCR accuracy**.

```bash
python3 context_hints.py \
  --session /path/to/explicit-codex-session.jsonl \
  --spans /path/to/reported-spans.json \
  --as-of 2026-09-14T07:27:00Z
```

Optional `--reviewed-terms terms.json` accepts a list like:

```json
[
  {
    "term": "Huion",
    "status": "confirmed",
    "kind": "project_glossary",
    "source": "writer-selected project glossary entry",
    "observed_at": "2026-09-13T12:00:00Z"
  }
]
```

Unlike the inspected voice client's transport restrictions, this tool keeps Unicode,
accents and short two-letter identifiers such as `ui` and `db`. Halogen receives
hints as ordinary text content; there is no claim that it supports the voice
service's `x-config-keyterms` header. The current importer handles the observed
Codex JSONL schema; Claude JSONL and automatic notebook indexing are not implemented.

## Evaluation before adopting it

Compare crop-only retries with the same crops plus shortlisted context. On
writer-corrected held-out pages, count correct resolutions, incorrect contextual
substitutions, unresolved cases and latency per hard span. Include unfamiliar names
and distractor vocabulary to test whether familiar terms overpower the ink. Test
ordinary narrative as well as technical vocabulary; character similarity alone
will not reliably recover an entirely misread phrase.

Context scope matters more than an ever-larger word list. Use the relevant notebook,
project or explicitly selected recent conversations, and freeze source timestamps
before the evaluation's permitted cutoff. Do not let the target page's correction
enter its own hints. Frequency should count distinct sources, not repeated model
guesses or repeated mentions in one message. The intended stable system rules can
be cached; the crop and small dynamic shortlist belong in the changing user input.

The next step is a measured local visual retry on the forthcoming journal samples,
after confirming literal labels. No extra model, embeddings service or training
is needed for this prototype.
