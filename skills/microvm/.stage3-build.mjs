export const meta = {
  name: 'microvm-stage3-build',
  description: 'Build the sandbox bash script: A one-shots the whole thing, B/C/D refine expert sections, integrator merges',
  phases: [
    { title: 'Spine', detail: 'Agent A one-shots the complete script' },
    { title: 'Experts', detail: 'B/C/D refine lifecycle, isolation/krun, and CLI/UX sections against A' },
    { title: 'Integrate', detail: 'merge A spine + B/C/D expert sections into one coherent draft' },
  ],
}

const ROOT = '/var/home/tom/mecattaf/dotfiles/skills/microvm'
const BUILD = `${ROOT}/findings/build`

const COMMON = `
You are building ONE part of a single bash script. NOTHING here is final — it is a first draft to be scrutinized later.

CANONICAL SPEC (read it fully first): ${ROOT}/findings/BUILD-BRIEF.md
SUPPORTING DETAIL (read what is relevant):
- ${ROOT}/findings/STAGE2-verb-deliberation.md   (the 11 verbs with full provenance + signatures)
- ${ROOT}/findings/STAGE2_5-condensed.md          (consensus patterns, per-repo unique tricks, contested calls)
- ${ROOT}/findings/STAGE2-per-repo-findings.md    (raw per-repo detail, incl. exact krun annotation semantics)
SHELL-CRAFT REFERENCE (real prior-art bash to study): ${ROOT}/references/inspiration/gh-runner-krunvm/ (orchestrator.sh, runner.sh, lib/) — trap-disarm-first, self-documenting usage(), leveled logging.

HARD RULES:
- Target install path is ~/.local/bin/sandbox, but in this stage WRITE DRAFTS ONLY to ${BUILD}/ — do NOT install, do NOT touch ~/.local/bin.
- Pure bash, single-file, must pass \`bash -n\` (syntax) and ideally \`shellcheck\`. set -euo pipefail.
- Engine is \`podman run --runtime=krun\`. Do NOT actually run podman/krun (the host may lack the krun handler) — write code, do not execute sandboxes. You MAY run \`bash -n\` / \`shellcheck\` on your output.
- Discipline checklist in BUILD-BRIEF.md §"Non-negotiable disciplines" is binding.
- Selection EXCLUSIVELY by \`--filter label=sandbox.managed-by=<us>\`, never name substring.
- Every isolation flag must reach a real podman/krun arg and be assertable by doctor. No metadata-only no-ops.
`.trim()

// ---------- Phase 1: A one-shots the complete script ----------
phase('Spine')
const A = await agent(
  `${COMMON}\n\n` +
  `YOU ARE AGENT A. One-shot the COMPLETE \`sandbox\` script: all 11 verbs (doctor, run, keep, start, exec, logs, ls, inspect, stop, rm, reap), the centralized birth function, the 3-layer teardown, arg parsing + dispatch, doctor probes, ssh-agent forwarding, krun annotations, machine-readable output, exit-code scheme, self-documenting usage().\n` +
  `Produce a coherent, complete, internally-consistent script — this is the SPINE the experts will refine, so its function decomposition and interfaces matter as much as correctness. Favor small, single-purpose functions with clear names so sections can be swapped.\n\n` +
  `Write the full script to ${BUILD}/A-full.sh and run \`bash -n\` on it (and shellcheck if available); fix what you can. Return the structured summary.`,
  { label: 'A:spine', phase: 'Spine', schema: {
    type: 'object', additionalProperties: false,
    required: ['file_written', 'verbs_implemented', 'functions', 'line_count', 'bash_n_passed', 'summary', 'self_review_notes'],
    properties: {
      file_written: { type: 'string' },
      verbs_implemented: { type: 'array', items: { type: 'string' } },
      functions: { type: 'array', items: { type: 'object', additionalProperties: false, required: ['name', 'purpose'], properties: { name: { type: 'string' }, purpose: { type: 'string' } } } },
      line_count: { type: 'integer' },
      bash_n_passed: { type: 'boolean' },
      summary: { type: 'string' },
      self_review_notes: { type: 'array', items: { type: 'string' }, description: 'weak spots / things the experts should harden' },
    },
  } }
)

const aFunctions = A.functions.map(f => `${f.name} — ${f.purpose}`).join('\n')

// ---------- Phase 2: B/C/D refine their sections against A ----------
phase('Experts')
const EXPERTS = [
  { key: 'B', domain: 'LIFECYCLE & CLEANUP', mandate:
    'the centralized BIRTH function + mandatory label set (sandbox.managed-by/.created/.id/.worktree), the three-layer teardown (--rm + trap-disarm-first on ERR/EXIT/INT/TERM + reap backstop), the unconditionally-ephemeral run vs explicit keep split, the reap verb (label-driven sweep, --until age cut via sandbox.created, --dry-run, reconcile-atop-every-invocation), and worktree creation + is_safe_cache_path guard + unpushed-commit guard. Make orphans structurally impossible.' },
  { key: 'C', domain: 'ISOLATION & KRUN', mandate:
    'the centralized SAFE-FLAGS applied at birth (--network none default, read-only mounts EXCEPT the one tool-created worktree bound :Z rw, --security-opt no-new-privileges, conservative --cap-drop, SELinux stays on), krun.cpus/krun.ram_mib annotations with strict bash INTEGER validation + conservative clamped defaults (~1 vCPU / 512-1024 MiB; remember krun silently ignores ram_mib<=128 and caps cpus at 16), rlimits as a second layer, ssh-agent forwarding (bind $SSH_AUTH_SOCK + env, keys never enter guest, hard-fail if no agent), and the doctor capability probes (/dev/kvm accessible, crun +LIBKRUN feature string, crun-krun handler present, libkrun/libkrunfw loadable+ABI-matched, a --rm --network none smoke test). Every flag must reach a real engine arg.' },
  { key: 'D', domain: 'CLI/UX & DISPATCH', mandate:
    'argument parsing + verb dispatch (flags+env duality with ${VAR:-default}, flags win; the -- separator passing everything after verbatim to the guest), the self-documenting usage() that greps the script\'s own option-comment lines (zero help/parser drift), machine-readable output (--json / stable columns derived from podman ps --format; diagnostics to stderr; stdout pipeable), the stable distinct exit-code scheme (workload code forwarded verbatim; distinct codes for precondition-fail vs not-found vs launch-fail; never collapse to 255), leveled logging to an fd, and the base64 command-transport for arbitrary agent-written code.' },
]
const experts = (await parallel(EXPERTS.map(e => () =>
  agent(
    `${COMMON}\n\n` +
    `YOU ARE EXPERT ${e.key}, owner of: ${e.domain}.\n` +
    `Read Agent A's complete draft at ${BUILD}/A-full.sh. A's functions are:\n${aFunctions}\n\n` +
    `YOUR MANDATE — surgically harden ${e.mandate}\n\n` +
    `Rewrite ONLY the functions/sections in your domain to best-practice quality, calibrated to A's existing interfaces (same function names/signatures where sensible so the integrator can splice cleanly; if you must change an interface, say so explicitly in deviations_from_A). Study the gh-runner-krunvm bash for idioms. Write your improved section (just your functions, as valid bash, with a header comment naming each) to ${BUILD}/${e.key}-section.sh and \`bash -n\` it. Return the structured summary.`,
    { label: `${e.key}:${e.domain.split(' ')[0].toLowerCase()}`, phase: 'Experts', schema: {
      type: 'object', additionalProperties: false,
      required: ['expert', 'file_written', 'functions_provided', 'functions_consumed', 'key_decisions', 'deviations_from_A'],
      properties: {
        expert: { type: 'string' },
        file_written: { type: 'string' },
        functions_provided: { type: 'array', items: { type: 'object', additionalProperties: false, required: ['name', 'signature', 'purpose'], properties: { name: { type: 'string' }, signature: { type: 'string' }, purpose: { type: 'string' } } } },
        functions_consumed: { type: 'array', items: { type: 'string' }, description: 'functions from A or other experts this section calls' },
        key_decisions: { type: 'array', items: { type: 'string' } },
        deviations_from_A: { type: 'array', items: { type: 'string' }, description: 'interface changes the integrator must reconcile' },
      },
    } }
  ).catch(() => null)
))).filter(Boolean)

const expertDigest = experts.map(e =>
  `## Expert ${e.expert} (${e.file_written})\nProvides: ${e.functions_provided.map(f => f.name).join(', ')}\nConsumes: ${e.functions_consumed.join(', ')}\nDecisions: ${e.key_decisions.join('; ')}\nDeviations from A: ${e.deviations_from_A.join('; ') || '(none)'}`
).join('\n\n')

// ---------- Phase 3: Integrate ----------
phase('Integrate')
const integrated = await agent(
  `${COMMON}\n\n` +
  `YOU ARE THE INTEGRATOR. Produce the final single coherent \`sandbox\` script by merging Agent A's spine with the experts' hardened sections.\n\n` +
  `INPUTS:\n- A's spine: ${BUILD}/A-full.sh\n- Expert sections: ${EXPERTS.map(e => `${BUILD}/${e.key}-section.sh`).join(', ')}\n\nEXPERT INTERFACE NOTES:\n${expertDigest}\n\n` +
  `Take A as the structural skeleton; replace each section A owns with the corresponding expert's hardened version; reconcile any interface deviations the experts flagged (rename/adapt call sites so the whole script is consistent); de-duplicate; ensure one and only one centralized birth function and one teardown path. The result must be a SINGLE self-consistent file that passes \`bash -n\` and, where shellcheck is available, is shellcheck-clean (or has justified inline disables).\n\n` +
  `Write the merged script to ${BUILD}/sandbox.draft.sh, \`chmod +x\` it, run \`bash -n\` and \`shellcheck\` (if present), and fix issues. Return the structured summary. Do NOT install it to ~/.local/bin.`,
  { label: 'integrator', phase: 'Integrate', schema: {
    type: 'object', additionalProperties: false,
    required: ['final_path', 'final_line_count', 'bash_n_passed', 'shellcheck_status', 'merge_decisions', 'conflicts_resolved', 'unresolved', 'summary'],
    properties: {
      final_path: { type: 'string' },
      final_line_count: { type: 'integer' },
      bash_n_passed: { type: 'boolean' },
      shellcheck_status: { type: 'string', description: 'clean / not-installed / N warnings (summarize)' },
      merge_decisions: { type: 'array', items: { type: 'string' } },
      conflicts_resolved: { type: 'array', items: { type: 'string' } },
      unresolved: { type: 'array', items: { type: 'string' }, description: 'anything the Stage-4 scrutiny must look at' },
      summary: { type: 'string' },
    },
  } }
)

return { A, experts, integrated }
