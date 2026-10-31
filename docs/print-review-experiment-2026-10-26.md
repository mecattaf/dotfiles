# Manual chat review experiment: printing, 26 October 2026

A real review of recent AI conversations recovered repeated print failures and
tested the repaired Markdown path through the physical printer. The principal
finding is an incomplete repair loop: the main crash had already reached project
memory **and an open GitHub issue**. Better extraction alone would not have fixed
it. Review must also reconcile unresolved work, deployment and outcome receipts.

This was a manual experiment using Codex `gpt-6.1-sol`, effort `xhigh`, with
parallel reviewers. Both settings were read from this run's `turn_context`
metadata, rather than inferred from the available model catalog. It installed no review schedule and wrote no extracted
candidate directly to project memory. The private ledger retains exact sources;
this public report contains no private transcript passages or document contents.

## Scope and actual coverage

The logical window is 21 October 00:00 Europe/Paris through the first prompt of
this experiment on 26 October, exclusive: `2026-10-20T22:00:00Z` to
`2026-10-26T18:12:39.603Z`. The experiment's own dialogue and workers are excluded
from findings; its earlier history-display copy is explicitly excluded too.

The reader inventoried both live Claude seats, Codex sessions and archived
sessions, the retired pi store, Substrate transcripts, known loose harness logs,
and the canonical `~/archives/ai-chats` object catalog. It also checked the old
Claude seat and dsh locations rather than assuming they existed. The old seats
and live dsh session directory were absent; historical dsh records remain in the
canonical archive. The catalog supplied a bounded allowlist of previously found
loose transcripts. This was not a new search of every file in home or an audit of
other machines and uncaptured transcripts.

| Layer | Measured coverage |
| --- | --- |
| Transcript capture | 9,880 live paths and 486 additional archived byte versions; 13,983,986,489 bytes streamed |
| History cross-check | 14 live/archived history versions; 13,395,160 bytes streamed |
| Human candidate triage | 784 distinct text groups, with replay aliases retained |
| Delivered mid-turn messages | 98 additional human attachment texts, reviewed in full |
| Semantic principal review | 585 distinct texts across all six dates |
| Separate dispositions | 10 harness controls reviewed; 287 generated/delegated candidate texts excluded by provenance |
| Outcome detection | 90,556 tool records and 119,808 assistant records scanned in 1,647 date-overlapping versions |

The 585 semantic reviews comprise 148, 155, 139, 68, 12 and 63 texts on
21–26 October respectively. Exact duplicates were read once; their paths,
timestamps and identities remain available. Recurring similar requests were not
silently merged into one event.

Outcome detection produced 17,986 signals, including repeated byte versions and
quoted failures. These are **not** 17,986 incidents. Reviewers followed print
signals through surrounding dialogue, source and receipts; they did not
semantically review every tool output or every assistant sentence in the corpus.
Broader principal requests were read regardless of whether they mentioned print.

The manifest hashes the exact bounded bytes read, with byte offsets, line numbers
and before/after file metadata. It is not a claim that an active transcript's
whole-file hash will remain stable. No file changed during its individual read.
The archive catalog was copied through SQLite's read-only backup interface.
Raw transcript prefixes were not committed or copied to compute.

There were 51 malformed/partial records. Thirty-four were outside files with
dated records in the window, including one old incomplete tail. Of the other 17,
12 are child-workflow telemetry/reasoning/tool results and five are Codex
reasoning/tool-output/command-completion records. None is a principal message or
delivered human attachment. They remain recorded as gaps in outcome context;
the originals were not repaired or discarded.

## What the review established

| Finding | Evidence and disposition |
| --- | --- |
| Markdown rendered, then crashed before submission | `decision.pdf` was a path string while submission treated it as metadata. This was already described in memory and [issue #588](https://github.com/mecattaf/dotfiles/issues/588), opened 22 October and still open at review. |
| Agents worked around the crash repeatedly | Some submitted existing rendered PDFs; an urgent run sent raw Markdown to CUPS, prompting a formatting complaint and another manual render. Spool acceptance and an empty queue were sometimes described as printed without a device receipt. |
| Gufo cutover had a separate caller defect | Historical classifier calls used a retired Halogen model ID and received 404 responses. Their deterministic fallback did not cause the string/dictionary crash. The active `utility` call now reaches Gufo with its served model ID. |
| The NAS move added a host-boundary failure | The NAS queue lacked Chrome for rendering and local CUPS for submission while the compute printer queue remained available. [Issue #634](https://github.com/mecattaf/dotfiles/issues/634), opened 26 October, already retained this migration problem. Its wider migration checklist is not all closed by this change. |
| Page and formatting requirements were specific | Some requests supplied exact slack, while one urgent request relaxed its page budget. These are document-level instructions. A good review preserves them instead of making every target exact or removing page checks globally. |

The two-host Paper outcome reconciliation found 19 unique standard outcomes in
the window: 13 submission type crashes, one missing-Chrome render failure, two
legitimate page-target rejections and three printer-confirmed PDF successes.
Nine render logs also contain the historical Halogen 404. Direct CUPS workarounds
without a standard Paper receipt remain separate evidence and are not counted
as additional daemon successes.

Broader review recovered concrete corrections about contextual workspace pickup,
offloaded compute, clipboard locality, UI scope, migration preservation and
memory batching. Many were already retained in Projects. The private ledger
records that status rather than manufacturing new backlog items. It also
preserves reversals: a browser-removal idea was immediately withdrawn, an
overbroad feature-parity memory entry was explicitly corrected, and an earlier
reachability problem was later attributed to a VPN and resolved. Historical
permissions and another person's machine settings do not become current blanket
authorization.

## Physical qualification and its boundary

The implementation keeps queue state and receipts on the NAS and moves rendering
to a request-scoped worker on compute. That worker uses Gufo and the configured
fonts, returns a bounded render result, and has no printer-submission authority.
The controller validates PDF readability, page count and A4 geometry before
using the NAS-owned pinned CUPS queue. Submission also accepts the legacy
path-shaped Markdown decision that caused the original crash. Print skills now
describe this host boundary and require outcome evidence.

Validation passed 92 Python `unittest` cases on `strix-coordinator` through
`runtime-test`, the `print-paper`, `print-plane` and `fleet-roles` Nix checks, and
builds of `paper-daemon` and `paper-render` on compute. The suite covers the
original regression, remote render contracts, source preservation, layout/page
limits, failure handling and quiet-hours behavior. The NAS did not compile these
packages.

A frozen Markdown document passed the built daemon and compute renderer through
a real Gufo classification, three layout attempts (`2 → 2 → 1` pages), a target
of one page with zero slack, and the existing compute CUPS queue. The printer's
IPP job **424** reported **completed, one impression** at 19:26:59 local time on
26 October; CUPS job **432** and the standard Paper receipt identify the same job.
The receipt's source hash matches the frozen input and its PDF hash identifies
the rendered artifact.

This proves the repaired package path and physical delivery for that document.
It does not prove production activation on the NAS. The qualification used a
temporary loopback transport to the existing compute CUPS service; that transport
was stopped afterwards. Later isolated guard and quiet-hours edge fixes were
covered by tests rather than another physical print. Live deployment and any
deliberate replay of old failed jobs remain separate actions.

## Repeating the experiment before automation

Keep a private frozen input manifest, reader version, reviewer/model settings,
original instructions and output ledger. The manual helpers and full evidence
for this run are under
`~/monday-oct26/print-review-experiment/`, mode-restricted and outside Git.
`coverage-manifest.jsonl` has SHA-256
`a7f9f1baade7e09c741e41bac01f40114712b1ac7187b346a02baaa02bbc457b`;
`review-register.jsonl` has SHA-256
`18a67a364c36a749f07bb3686775eecedd0f1a25113c80d0f9ba94b22978a5fd`.

The repeat procedure is:

1. Bound the dates, timezone, input versions and self-exclusion before review.
   Include histories as a cross-check, not as a substitute for transcripts.
2. Normalize current schemas. In particular, Claude delivers some real human
   messages as `attachment.queued_command` with a human origin; a reader that
   selects only `type=user` misses them. Separate Codex exec instructions,
   subagent relays, skill bodies, compactions and harness controls from the
   principal. Keep malformed and undated material visible as coverage limits.
3. Read all principal texts. Systematically detect outcome failures, then inspect
   context and receipts before promoting a signal to a finding. Preserve exact
   quotations privately and attach path, line, offset, hash and event date.
4. Classify issue, intent, correction, task-specific exception and agent claim.
   Group recurrence without losing events. Apply later explicit corrections and
   resolved outcomes before proposing work.
5. Compare each candidate to existing memory, threads, GitHub issues, source and
   deployment evidence. Distinguish missing knowledge, retained unresolved work,
   implemented but undeployed changes, and a verified outcome.
6. Have a reviewer validate a bounded candidate ledger before any memory or
   issue mutation. Keep unrelated extracted work as review evidence in this run.

A weaker-agent comparison should receive the same bounded evidence and tools.
Score missed principal messages, false user attribution, duplicate proposals,
lost corrections, incorrect status and unsupported completion claims. Print is a
useful reference case because extraction, existing issue state, deterministic
failure, code repair, deployment and printer receipt are independently testable.
Do not add a recurring job until the one-off method has been evaluated; any later
schedule belongs to Substrate, not a new dotfiles timer.

## Unknowns and proposed defaults

- Production NAS activation is not proved by this package qualification. Keep
  deployment and any old-job replay explicit, preserving live sessions and
  checking receipts instead of automatically replaying the failed backlog.
- The weaker-agent comparison has not run. Use the frozen private ledger and
  equal tools for that experiment before choosing or scheduling an extractor.
