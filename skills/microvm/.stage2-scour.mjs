export const meta = {
  name: 'microvm-stage2-scour',
  description: 'Scour every reference repo for verb surface + lessons, then deliberate a converged verb surface',
  phases: [
    { title: 'Scour', detail: 'one Opus agent per repo extracts verb surface, lifecycle, isolation, gotchas' },
    { title: 'Propose', detail: '3 diverse lenses each propose a verb surface for our tool' },
    { title: 'Critique', detail: 'each lens sees the others and revises (deliberation round)' },
    { title: 'Synthesize', detail: 'reconcile into one recommended verb surface with provenance' },
  ],
}

const BASE = '/var/home/tom/mecattaf/dotfiles/skills/microvm/references'

// Project constraints every deliberation agent must respect (from may30-latest-thread.md).
const CONSTRAINTS = `
PROJECT: a single-user, Fedora-canon, disposable-microVM code-execution tool.
ENGINE (fixed): podman run --runtime=krun over official Fedora packages (podman + crun-krun + libkrun + libkrunfw). No daemon, no third-party runtime, no login.
FORM: ONE disciplined bash script in ~/.local/bin (flag-preceded, scriptable) + a thin Claude SKILL.md. podman is the only source of truth (labels), so NO state file / NO daemon.
THREAT MODEL: accident, not adversary (a coding agent's clumsy code must not damage the host). Blast-radius containment, not anti-exfiltration.
WHAT WE SANDBOX: the WORKLOAD (e.g. a webapp the agent wrote/runs), NOT the agent harness itself.
LOCKED DECISIONS:
- ephemeral-by-default (--rm); persistence is an explicit opt-in verb/flag that stamps a label.
- three cleanup layers: --rm (clean exit) + trap on INT/TERM/EXIT (interactive crash) + a label-driven reap backstop (hard kill).
- every sandbox born through ONE centralized function that stamps a MANDATORY label set (sandbox.managed-by, .created, .id, .worktree) and SAFE-BY-DEFAULT isolation flags (--network none default, read-only mounts where possible, conservative --memory/--cpus via krun.cpus/krun.ram_mib annotations).
- a 'doctor'-style precondition check is verb zero (KVM access, crun +LIBKRUN, crun-krun present).
- SSH-agent forwarding so keys never enter the guest (idea lifted from smolvm).
- worktree-per-sandbox: the tool should CREATE the worktree (not accept a pre-made one, which orphans the agent from .git); guard destructive git inside.
- ORTHOGONAL to Tailscale: the tool knows nothing about the network/remote hosts; it publishes predictably to localhost and emits parseable output so ssh/Caddy compose around it. NO --host flag.
- machine-readable output (a --json/stable-columns mode), stable exit codes.
GRADUATION SIGNAL (when to stop growing bash and adopt microsandbox/rewrite in Rust): painful arg-parsing, need for concurrency-safe allocation, need for tested isolation guarantees, or the script outgrows single-file auditability.
`.trim()

const REPOS = [
  // documentation tier — what we build on
  { name: 'crun',                  path: 'documentation/crun',                 tier: 'documentation', focus: 'krun.1.md / krun.1 — the krun HANDLER and its ANNOTATION surface (krun.cpus, krun.ram_mib, run.oci.handler=krun, .krun_vm.json). This is the most important doc repo. Read docs/, krun.1.md, design-docs/.' },
  { name: 'libkrun',               path: 'documentation/libkrun',              tier: 'documentation', focus: 'VMM-as-library: virtio-fs host passthrough (the security soft spot), TSI networking, resource limits. Read README, docs/, include/, examples/.' },
  { name: 'libkrunfw',             path: 'documentation/libkrunfw',            tier: 'documentation', focus: 'guest kernel bundled as a .so; what the microVM actually boots; SEV/TDX variants. README + Makefile + configs.' },
  { name: 'krunvm',                path: 'documentation/krunvm',               tier: 'documentation', focus: 'standalone CLI verb surface — read src/commands/ (create/start/exec/delete/list/changevm/config) and README. NOTE: COPR-only on Fedora, we do NOT use it, but its verb shape is prime reference.' },
  { name: 'crun-vm',               path: 'documentation/crun-vm',              tier: 'documentation', focus: 'a DIFFERENT runtime (run.oci.handler) that boots full VM/QEMU images — contrast with the krun microVM path. README + docs/.' },
  { name: 'podman',                path: 'documentation/podman',               tier: 'documentation', focus: 'DOCS ONLY — do NOT read all the Go source. Read docs/source/markdown/podman-run.1.md, the Quadlet (.container) docs, and the --runtime / --annotation / --rm / --label / ps --filter / --network / -v mount-flag surfaces. This is the actual CLI our script wraps.' },
  // inspiration tier — sister projects
  { name: 'microsandbox',          path: 'inspiration/microsandbox',           tier: 'inspiration', focus: 'EXACT verb surface (msb exe/init/add/up/down/run/shell/status/log/clean/install/server). Read its skills/ (Agent Skills — how they teach an LLM), sdk/, and crates/ CLI def. It is a full SDK — note the platform surface we deliberately DON\'T want.' },
  { name: 'smolvm',                path: 'inspiration/smolvm',                 tier: 'inspiration', focus: 'EXACT verb surface (machine create/start/exec/stop/delete, cp, run, flags --net/--volume/--ssh-agent). Extract HOW the ssh-agent forwarding works (keys never in guest) in detail. NOTE: it vendors a FORKED libkrun/libkrunfw — flag that, do not recommend adopting it.' },
  { name: 'agent-sandbox',         path: 'inspiration/agent-sandbox',          tier: 'inspiration', focus: 'EXACT verb surface incl. doctor / update / update-agents. Read CLAUDE.md, docs/, crates/. The dcg policy dependency. The git-worktree-prune gotcha. NOTE: it is podman CONTAINER tier (not microVM) — weaker isolation than us.' },
  { name: 'ERA',                   path: 'inspiration/ERA',                    tier: 'inspiration', focus: 'closest prior art (krunvm microVMs). Read skill-layer/, recipes/, scripts/, docs/. Extract verb surface + setup/doctor checks + how the skill layer is structured.' },
  { name: 'arrakis',               path: 'inspiration/arrakis',                tier: 'inspiration', focus: 'THE PLATFORM-CREEP ANTI-PATTERN. Document its 3-daemon architecture, REST API, SDK, MCP, snapshot/restore — i.e. everything our bash script must NOT become. Also note any verb names. Read README, api/, cmd/, docs/.' },
  { name: 'gh-runner-krunvm',      path: 'inspiration/gh-runner-krunvm',       tier: 'inspiration', focus: 'MOST RELEVANT FOR BASH DISCIPLINE: real-world bash orchestration of krunvm microVMs. Read orchestrator.sh, runner.sh, lib/ in detail. Extract trap/cleanup patterns, set -euo pipefail usage, labelling/naming, error handling, KVM checks. This is our shell-craft reference.' },
  { name: 'claude-code-sandbox',   path: 'inspiration/claude-code-sandbox',    tier: 'inspiration', focus: 'sandboxes the AGENT in Docker (different layer). Read claude-sandbox.config.example.json schema, src/, docs/. Extract config/lifecycle UX patterns worth mirroring.' },
  { name: 'sbx-releases',          path: 'inspiration/sbx-releases',           tier: 'inspiration', focus: 'docs-only release repo (no source). Read README + SECURITY.md for the EGRESS POLICY model (open/balanced/locked-down, denied-domain lists) we may emulate at the firewalld tier. Also note the mandatory-login fact.' },
  // lists tier
  { name: 'awesome-agent-sandboxes', path: 'lists/awesome-agent-sandboxes',    tier: 'lists', focus: 'skim README; surface any tool/pattern NOT already in our reference set that is relevant to a Fedora-local microVM tool.' },
  { name: 'wincent-gist',          path: 'lists/wincent-gist',                 tier: 'lists', focus: 'read agent-sandboxen.md; surface practitioner conventions/verbs/gotchas worth noting.' },
]

const SCOUR_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['repo', 'tier', 'language', 'purpose', 'verb_surface', 'lifecycle_model', 'isolation_and_flags', 'standout_features', 'gotchas', 'fedora_fit', 'lessons_for_our_tool'],
  properties: {
    repo: { type: 'string' },
    tier: { type: 'string' },
    language: { type: 'string' },
    purpose: { type: 'string', description: '1-2 sentences' },
    verb_surface: {
      type: 'array',
      description: 'EXACT command/subcommand names this tool exposes, with args and what each does. Empty if a pure library/doc repo.',
      items: {
        type: 'object', additionalProperties: false,
        required: ['verb', 'args', 'does'],
        properties: { verb: { type: 'string' }, args: { type: 'string' }, does: { type: 'string' } },
      },
    },
    lifecycle_model: { type: 'string', description: 'ephemeral vs persistent, how cleanup/teardown works, any reaper/age logic' },
    isolation_and_flags: { type: 'array', items: { type: 'string' }, description: 'mount/network/resource flags, annotations, defaults relevant to isolation' },
    standout_features: { type: 'array', items: { type: 'string' } },
    gotchas: { type: 'array', items: { type: 'string' } },
    fedora_fit: { type: 'string', description: 'how Fedora-canon / officially-packaged this is' },
    lessons_for_our_tool: { type: 'array', items: { type: 'string' }, description: 'concrete, actionable takeaways for OUR bash script + skill' },
  },
}

const PROPOSAL_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['lens', 'verbs', 'rationale'],
  properties: {
    lens: { type: 'string' },
    verbs: {
      type: 'array',
      items: {
        type: 'object', additionalProperties: false,
        required: ['verb', 'signature', 'behavior', 'safe_default', 'provenance'],
        properties: {
          verb: { type: 'string' },
          signature: { type: 'string', description: 'e.g. "sandbox run [--mem M] [--cpus N] <image> -- <cmd...>"' },
          behavior: { type: 'string' },
          safe_default: { type: 'string', description: 'what the safe-by-default posture is for this verb' },
          provenance: { type: 'string', description: 'which prior-art tool(s) this verb name/shape is taken from' },
        },
      },
    },
    rationale: { type: 'string' },
  },
}

const REVISION_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['lens', 'critique_of_others', 'revised_verbs', 'points_of_agreement', 'remaining_disagreements'],
  properties: {
    lens: { type: 'string' },
    critique_of_others: { type: 'string' },
    revised_verbs: PROPOSAL_SCHEMA.properties.verbs,
    points_of_agreement: { type: 'array', items: { type: 'string' } },
    remaining_disagreements: { type: 'array', items: { type: 'string' } },
  },
}

const SYNTH_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['recommended_verbs', 'rejected_verbs', 'global_flags', 'open_questions', 'summary'],
  properties: {
    recommended_verbs: {
      type: 'array',
      items: {
        type: 'object', additionalProperties: false,
        required: ['verb', 'signature', 'behavior', 'safe_default', 'provenance'],
        properties: {
          verb: { type: 'string' },
          signature: { type: 'string' },
          behavior: { type: 'string' },
          safe_default: { type: 'string' },
          provenance: { type: 'string' },
        },
      },
    },
    rejected_verbs: { type: 'array', items: { type: 'object', additionalProperties: false, required: ['verb', 'why'], properties: { verb: { type: 'string' }, why: { type: 'string' } } } },
    global_flags: { type: 'array', items: { type: 'string' }, description: 'cross-cutting flags (e.g. --json, --persist, --mem, --cpus, --net, --mount, --ssh-agent)' },
    open_questions: { type: 'array', items: { type: 'string' } },
    summary: { type: 'string', description: 'the recommended verb surface in one tight paragraph, with the deliberation reasoning' },
  },
}

// ---------- Phase 1: Scour (one agent per repo) ----------
phase('Scour')
const findings = (await parallel(REPOS.map(r => () =>
  agent(
    `You are scouring a LOCAL READ-ONLY clone of the repo "${r.name}" (tier: ${r.tier}) at ${BASE}/${r.path}.\n` +
    `This is reference material for a project — do NOT modify anything under ${BASE}.\n\n` +
    `FOCUS: ${r.focus}\n\n` +
    `Your single most important job is to extract the EXACT VERB SURFACE (the command/subcommand names the tool exposes and what each does), because our project will choose its own verb names by learning from prior art. Be precise — read the actual CLI definition / arg parser / docs, do not guess.\n\n` +
    `Also extract: the lifecycle model (ephemeral vs persistent, cleanup/teardown/reaper), the isolation-relevant flags & defaults (mounts, network, resource caps, annotations), standout features, gotchas, how Fedora-canon it is, and concrete lessons for OUR tool.\n\n` +
    `OUR PROJECT CONTEXT (so your lessons are relevant):\n${CONSTRAINTS}\n\n` +
    `Use ripgrep/find/cat liberally. For large repos read only what the FOCUS points to. Return ONLY the structured object.`,
    { label: `scour:${r.name}`, phase: 'Scour', schema: SCOUR_SCHEMA }
  ).catch(() => null)
))).filter(Boolean)

log(`Scour complete: ${findings.length}/${REPOS.length} repos digested`)

// Compact verb-surface digest to feed the deliberation.
const verbDigest = findings.map(f =>
  `### ${f.repo} (${f.tier}, ${f.language})\n${f.purpose}\nVERBS: ${f.verb_surface.map(v => `${v.verb}[${v.args}]=${v.does}`).join(' | ') || '(none — library/doc)'}\nLIFECYCLE: ${f.lifecycle_model}\nKEY LESSONS: ${f.lessons_for_our_tool.join('; ')}`
).join('\n\n')

// ---------- Phase 2: Propose (3 diverse lenses) ----------
phase('Propose')
const LENSES = [
  { key: 'mirror', desc: 'MIRROR-PRIOR-ART: name verbs to match microsandbox/smolvm/krunvm as closely as sensible, so the documented escape hatch (adopt microsandbox later) stays low-friction. Favor familiarity to anyone who has used those tools.' },
  { key: 'safety', desc: 'SAFETY-MINIMALIST: the smallest verb set that makes the safe path the only expressible path. Ephemeral-by-default, separate persist verb, reap as a first-class backstop, doctor as verb zero. Fewer verbs, each unambiguous.' },
  { key: 'podman', desc: 'PODMAN-MENTAL-MODEL: name verbs so anyone who knows podman/docker already knows ours (run/exec/ps/rm/logs/stop), minimizing surprise. The tool is a thin disciplined wrapper, so its verbs should echo what it wraps.' },
]
const proposals = await parallel(LENSES.map(l => () =>
  agent(
    `You are designing the VERB SURFACE for our bash microVM-sandbox tool, through ONE specific lens.\n\n` +
    `YOUR LENS — ${l.desc}\n\n` +
    `PROJECT CONSTRAINTS (binding):\n${CONSTRAINTS}\n\n` +
    `PRIOR-ART VERB SURFACES (from scouring the references):\n${verbDigest}\n\n` +
    `Propose the complete verb surface for OUR tool through your lens. For each verb give signature, behavior, the safe-by-default posture, and provenance (which prior-art tool the name/shape comes from). Verbs must be taken/adapted from the prior art above, not invented from scratch. Include doctor, reap, and the ephemeral/persist split. Return ONLY the structured object.`,
    { label: `propose:${l.key}`, phase: 'Propose', schema: PROPOSAL_SCHEMA }
  ).catch(() => null)
)).then(a => a.filter(Boolean))

const proposalDigest = proposals.map(p =>
  `## Lens: ${p.lens}\nRationale: ${p.rationale}\nVerbs:\n${p.verbs.map(v => `- ${v.verb}: ${v.signature} — ${v.behavior} [default: ${v.safe_default}] (from ${v.provenance})`).join('\n')}`
).join('\n\n')

// ---------- Phase 3: Critique / deliberate (each lens sees the others) ----------
phase('Critique')
const revisions = await parallel(LENSES.map((l, i) => () =>
  agent(
    `You previously proposed a verb surface through the ${l.key} lens. Now you see all THREE proposals and must DELIBERATE.\n\n` +
    `PROJECT CONSTRAINTS (binding):\n${CONSTRAINTS}\n\n` +
    `ALL THREE PROPOSALS:\n${proposalDigest}\n\n` +
    `Critique the other two lenses honestly (where are they wrong or risky for THIS project?), then revise YOUR verb set toward what is genuinely best for the project — move toward consensus where the others are right, hold your ground where your lens matters. List explicit points of agreement and any remaining disagreements. Return ONLY the structured object.`,
    { label: `critique:${l.key}`, phase: 'Critique', schema: REVISION_SCHEMA }
  ).catch(() => null)
)).then(a => a.filter(Boolean))

const revisionDigest = revisions.map(r =>
  `## Lens: ${r.lens}\nCritique: ${r.critique_of_others}\nRevised verbs:\n${r.revised_verbs.map(v => `- ${v.verb}: ${v.signature} — ${v.behavior} [default: ${v.safe_default}] (from ${v.provenance})`).join('\n')}\nAgreements: ${r.points_of_agreement.join('; ')}\nDisagreements: ${r.remaining_disagreements.join('; ')}`
).join('\n\n')

// ---------- Phase 4: Synthesize ----------
phase('Synthesize')
const synthesis = await agent(
  `You are the orchestrator's synthesis agent. Reconcile a 3-lens deliberation into ONE recommended verb surface for our bash microVM-sandbox tool.\n\n` +
  `PROJECT CONSTRAINTS (binding):\n${CONSTRAINTS}\n\n` +
  `POST-DELIBERATION REVISIONS:\n${revisionDigest}\n\n` +
  `Produce the single recommended verb surface: each verb with signature, behavior, safe-by-default posture, and provenance (which prior-art tool it descends from). Include rejected verbs with reasons, the cross-cutting global flags, and any open questions the build stage must resolve. The summary must read as a clear recommendation an implementer can act on. Return ONLY the structured object.`,
  { label: 'synthesize', phase: 'Synthesize', schema: SYNTH_SCHEMA }
)

return { findings, proposals, revisions, synthesis }
