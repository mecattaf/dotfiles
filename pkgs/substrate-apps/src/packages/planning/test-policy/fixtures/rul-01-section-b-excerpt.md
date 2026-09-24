<!--
VERBATIM EXCERPT — do not edit.
Source: /home/tom/research-methods/cards/RUL-01.md lines 444-481 (Section B, B-Q3/B-Q4/B-Q5),
card sha256 bb812861c95bf40a98d9ba8a1e919c3b4c77fb6a17142c8c92b8e6808067d94b, MEASURED 2026-09-06.
The trailing "### B-Q6" heading is added so the last block has a terminator; nothing else is added.
Copied by U-A9 LAKE-POLICY with `sed -n 444,481p`. The card itself is read-only to this repository.
-->
### B-Q3 — CONSOLIDATED Q3: routing preference order

**Question.** Is the per-item preference order over members adopted as the ReleasePolicy default, or set explicitly? The sheet's recommendation is to adopt the default and let a loaded batch supply the values.

**Default (PROPOSED).** Adopt the ReleasePolicy default preference order and let a loaded batch supply the values; do not set it explicitly now.

**Retires.** nothing (the `>` line at CONSOLIDATED.md section 3 question 3, lines 195-197, is empty).

**Newest source.** /home/tom/research-methods/PROMPTS.md amendment §2 step 9 (2026-09-06), which binds Q3 to P17  
**Blocks.** P17

>

### B-Q4 — CONSOLIDATED Q4: congestion policy

**Question.** When the preferred member is congested, does the item wait or escalate? The sheet's recommendation is wait, with escalation on capability floor, deadline, or a failed verdict only.

**Default (PROPOSED).** Wait when the preferred member is congested, with escalation on capability floor, deadline, or a failed verdict only — a closed list of three triggers.

**Retires.** nothing (the `>` line at CONSOLIDATED.md section 3 question 4, lines 199-201, is empty).

**Newest source.** /home/tom/research-methods/PROMPTS.md amendment §2 step 9 (2026-09-06)  
**Blocks.** P17

>

### B-Q5 — CONSOLIDATED Q5: the length exponent

**Question.** What exponent sits on the unattended length term in the attended/unattended flip? The sheet's recommendation is 1.0 until measurement, so the flip is a sign change and nothing more.

**Default (PROPOSED).** 1.0 until measurement, so the attended/unattended flip is a sign change and nothing more.

**Retires.** nothing (the `>` line at CONSOLIDATED.md section 3 question 5, lines 203-205, is empty).

**Newest source.** /home/tom/research-methods/PROMPTS.md amendment §2 step 9 (2026-09-06)  
**Blocks.** P17

>

### B-Q6 — CONSOLIDATED Q6: the Rust CLI's surviving verbs
