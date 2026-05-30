export const meta = {
  name: 'microvm-stage4-scrutiny',
  description: 'Adversarially scrutinize the merged draft against the cloned references, then verify + consolidate findings',
  phases: [
    { title: 'Review', detail: 'reviewers each verify the draft against specific references through one lens' },
    { title: 'Verify', detail: 'each finding adversarially re-checked against source before it survives' },
    { title: 'Consolidate', detail: 'prioritized findings list for the orchestrator' },
  ],
}

const ROOT = '/var/home/tom/mecattaf/dotfiles/skills/microvm'
const DRAFT = `${ROOT}/findings/build/sandbox.draft.sh`

const COMMON = `
You are scrutinizing a FIRST-DRAFT bash script. Nothing is final; your job is to find what is wrong or weak.
THE DRAFT: ${DRAFT} (1566 lines). Read it.
CANONICAL SPEC: ${ROOT}/findings/BUILD-BRIEF.md
REFERENCE LEARNINGS: ${ROOT}/findings/STAGE2_5-condensed.md and ${ROOT}/findings/STAGE2-per-repo-findings.md
GROUND TRUTH SOURCE (cloned, read-only): ${ROOT}/references/ — VERIFY claims against actual source here, do NOT rely on memory. e.g. crun's krun handler is references/documentation/crun/src/libcrun/handlers/krun.c and references/documentation/crun/krun.1.md; podman docs under references/documentation/podman/docs/; real bash prior art at references/inspiration/gh-runner-krunvm/.

ALREADY-CONFIRMED BUG (do not re-spend on it, build beyond it): the draft emits \`--annotation run.oci.krun.cpus=...\` / \`run.oci.krun.ram_mib=...\`, but crun's find_annotation does an EXACT-match lookup of the literal keys \`krun.cpus\`/\`krun.ram_mib\` (krun.c:262,272; krun.1.md:45). So the resource caps SILENTLY NO-OP — the ERA fail-open. HIGH severity, fix = use \`krun.cpus\`/\`krun.ram_mib\`.

For each finding give: severity (critical/high/medium/low), exact location (function + line range), the issue, EVIDENCE (cite the reference file:line or the man page that proves it), and the concrete fix. Prefer a few high-confidence, source-backed findings over many speculative ones. Be concrete and verifiable.
`.trim()

const FINDINGS_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['lens', 'findings'],
  properties: {
    lens: { type: 'string' },
    findings: {
      type: 'array',
      items: {
        type: 'object', additionalProperties: false,
        required: ['severity', 'location', 'issue', 'evidence', 'fix', 'confidence'],
        properties: {
          severity: { type: 'string', enum: ['critical', 'high', 'medium', 'low'] },
          location: { type: 'string' },
          issue: { type: 'string' },
          evidence: { type: 'string', description: 'reference file:line / man page / source that proves it' },
          fix: { type: 'string' },
          confidence: { type: 'string', enum: ['confirmed-against-source', 'likely', 'speculative'] },
        },
      },
    },
  },
}

const LENSES = [
  { key: 'isolation', desc:
    'ISOLATION ENFORCEMENT — for EVERY isolation flag the draft sets, verify it reaches a REAL enforced engine arg (not metadata-only). Check: krun annotation namespace (beyond the known cpus/ram_mib bug — also use_passt/nested_virt/variant if used), --network none actually means no NIC under krun, the read-only rootfs + the worktree being the only rw :Z mount, --security-opt no-new-privileges, --cap-drop, --ulimit/rlimits, --publish behavior under --network none (does podman reject or silently drop?), and the --network loopback->pasta/passt localhost-publish assumption. Verify against crun/handlers/krun.c, krun.1.md, podman-run docs.' },
  { key: 'lifecycle', desc:
    'LIFECYCLE / ORPHAN / REAP — verify the three-layer teardown is actually airtight: trap-disarm-first correctness, that --rm covers the clean path, that the trap only tears down the just-born ephemeral (never a kept sandbox), that reap selects EXCLUSIVELY by label (never name substring) and its age cut works, the worktree create/branch contract, and whether has_unpushed_commits is too aggressive (A flagged a fresh branch-off-HEAD always looks unpushed). Check the no-lock reap race on worktree removal. Ground against gh-runner-krunvm and the smolvm/is_safe_cache_path lessons.' },
  { key: 'bash', desc:
    'BASH CORRECTNESS & FOOTGUNS — set -euo pipefail pitfalls (e in if/subshell/pipeline, unset under -u), quoting, array/nameref handling, command-substitution swallowing exit codes, the base64 command-transport decode correctness in-guest (does the decode+dispatch actually run the workload? is bash present in a fedora-minimal base?), and whether --timeout is correctly wired (and the keep/exec cases where it is parsed but not applied). Run bash -n yourself; reason about runtime logic shellcheck cannot see.' },
  { key: 'fidelity', desc:
    'FIDELITY TO REFERENCE LEARNINGS & DISCIPLINE CHECKLIST — go through BUILD-BRIEF §"Non-negotiable disciplines" (1-13) and the STAGE2_5 consensus, and check each is honored: one centralized birth function (no second create path), label-exclusive selection everywhere, machine-readable-by-default output, stable distinct exit codes (no 255 collapse), self-documenting usage with no drift, no host-global mutation (arrakis anti-pattern), no scope creep (no egress DSL/daemon/secret-broker leaking in). Flag any discipline silently violated.' },
  { key: 'doctor', desc:
    'DOCTOR CORRECTNESS — verify each doctor probe actually proves what it claims: detecting crun built +LIBKRUN (is grepping `crun --version` correct? what is the real feature string?), that the crun-krun handler/runtime is registered for podman (the crun-vs-krun runtime-name relationship), /dev/kvm accessibility incl. group membership with the actionable usermod fix, the libkrun/libkrunfw soname/ABI acceptance, and the --rm --network none smoke test. Also: does precheck gate the right verbs (B flagged reap requiring krun precheck even for pure cleanup)? Verify against crun source + libkrun.' },
]

// ---------- Phase 1+2: review then adversarially verify, pipelined ----------
phase('Review')
const reviewed = await pipeline(
  LENSES,
  l => agent(
    `${COMMON}\n\nYOUR LENS — ${l.desc}\n\nReturn ONLY the structured object with your findings.`,
    { label: `review:${l.key}`, phase: 'Review', schema: FINDINGS_SCHEMA }
  ),
  (rev, l) => parallel((rev.findings || []).map(f => () =>
    agent(
      `Adversarially VERIFY this scrutiny finding about ${DRAFT}. Default to refuted if you cannot prove it against source.\n\n` +
      `FINDING (${f.severity}, ${f.confidence}) @ ${f.location}:\n${f.issue}\nClaimed evidence: ${f.evidence}\nProposed fix: ${f.fix}\n\n` +
      `Open the draft AND the cited reference/source under ${ROOT}/references/ and confirm or refute. Is the location/line right? Does the cited evidence actually say what is claimed? Is the fix correct and complete? Return ONLY the structured object.`,
      { label: `verify:${l.key}:${(f.location||'').split(' ')[0].slice(0,18)}`, phase: 'Verify', schema: {
        type: 'object', additionalProperties: false,
        required: ['verdict', 'severity_adjusted', 'note', 'fix_confirmed'],
        properties: {
          verdict: { type: 'string', enum: ['confirmed', 'refuted', 'partial'] },
          severity_adjusted: { type: 'string', enum: ['critical', 'high', 'medium', 'low', 'none'] },
          note: { type: 'string' },
          fix_confirmed: { type: 'boolean' },
        },
      } }
    ).then(v => ({ ...f, lens: l.key, verification: v })).catch(() => ({ ...f, lens: l.key, verification: { verdict: 'unverified', severity_adjusted: f.severity, note: 'verification agent errored', fix_confirmed: false } }))
  ))
)

const survivors = reviewed.flat().filter(Boolean).filter(f => f.verification && f.verification.verdict !== 'refuted')

// ---------- Phase 3: consolidate ----------
phase('Consolidate')
const digest = survivors.map(f =>
  `- [${f.verification.severity_adjusted}|${f.verification.verdict}] (${f.lens}) ${f.location}: ${f.issue}\n    evidence: ${f.evidence}\n    fix: ${f.fix}\n    verify-note: ${f.verification.note}`
).join('\n')

const consolidation = await agent(
  `You are consolidating the verified scrutiny findings on the draft ${DRAFT} for the orchestrator.\n\n` +
  `SURVIVING (non-refuted) FINDINGS:\n${digest}\n\n` +
  `Produce a single prioritized punch-list: dedupe overlaps, order by severity then blast-radius, and for each give a one-line title, severity, the fix, and whether it is a blocker for a first real-world test. Then give an overall verdict on the draft's readiness and the top themes. Return ONLY the structured object.`,
  { label: 'consolidate', phase: 'Consolidate', schema: {
    type: 'object', additionalProperties: false,
    required: ['punch_list', 'overall_verdict', 'top_themes', 'blocker_count'],
    properties: {
      punch_list: { type: 'array', items: { type: 'object', additionalProperties: false, required: ['title', 'severity', 'fix', 'blocker'], properties: { title: { type: 'string' }, severity: { type: 'string' }, fix: { type: 'string' }, blocker: { type: 'boolean' } } } },
      overall_verdict: { type: 'string' },
      top_themes: { type: 'array', items: { type: 'string' } },
      blocker_count: { type: 'integer' },
    },
  } }
)

return { reviewed: survivors, consolidation }
