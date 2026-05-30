export const meta = {
  name: 'microvm-stage2_5-condense',
  description: 'Condense the per-repo scour findings into cross-cutting similarities + per-repo uniqueness',
  phases: [
    { title: 'Cluster', detail: 'one agent per dimension finds shared patterns + unique contributions across all repos' },
    { title: 'Condense', detail: 'synthesize consensus, per-repo unique value, and contested points' },
  ],
}

// The 16 scour findings live in this JSON file (array of objects). Cluster agents Read it
// directly (it is ~188k chars — too large to thread through `args`).
const FINDINGS_PATH = '/var/home/tom/mecattaf/dotfiles/skills/microvm/.stage2-findings.json'
const FINDINGS_INSTRUCTION = `The 16 per-repo scour findings are a JSON array at ${FINDINGS_PATH}. READ that file first (it has fields: repo, tier, language, purpose, verb_surface, lifecycle_model, isolation_and_flags, standout_features, gotchas, fedora_fit, lessons_for_our_tool). Base your analysis ONLY on what is in that file.`

const PROJECT = `
OUR PROJECT: single-user, Fedora-canon, disposable-microVM code-execution tool = ONE disciplined bash script (~/.local/bin) + a thin Claude SKILL.md, engine = podman run --runtime=krun over official Fedora packages, no daemon, ephemeral-by-default, accident (not adversary) threat model, sandboxing the WORKLOAD not the agent. Tailscale-orthogonal.
`.trim()

const CLUSTER_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['dimension', 'shared_patterns', 'unique_contributions', 'recommendation_for_us'],
  properties: {
    dimension: { type: 'string' },
    shared_patterns: {
      type: 'array',
      description: 'patterns multiple tools independently exhibit — the load-bearing ones',
      items: {
        type: 'object', additionalProperties: false,
        required: ['pattern', 'repos_exhibiting', 'why_it_recurs', 'adopt_for_us'],
        properties: {
          pattern: { type: 'string' },
          repos_exhibiting: { type: 'array', items: { type: 'string' } },
          why_it_recurs: { type: 'string' },
          adopt_for_us: { type: 'string', description: 'yes/no/partial + how it applies to our bash tool' },
        },
      },
    },
    unique_contributions: {
      type: 'array',
      description: 'something only ONE (or very few) repos do in this dimension',
      items: {
        type: 'object', additionalProperties: false,
        required: ['repo', 'what', 'worth_stealing'],
        properties: { repo: { type: 'string' }, what: { type: 'string' }, worth_stealing: { type: 'string' } },
      },
    },
    recommendation_for_us: { type: 'string' },
  },
}

const CONDENSE_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['consensus', 'per_repo_unique', 'contested', 'condensed_narrative'],
  properties: {
    consensus: {
      type: 'array',
      description: 'cross-dimension patterns the field broadly agrees on — treat as defaults for our tool',
      items: {
        type: 'object', additionalProperties: false,
        required: ['pattern', 'strength', 'implication_for_us'],
        properties: {
          pattern: { type: 'string' },
          strength: { type: 'string', description: 'how widely shared (e.g. "near-universal", "common", "a few")' },
          implication_for_us: { type: 'string' },
        },
      },
    },
    per_repo_unique: {
      type: 'array',
      description: 'ONE line per reference repo: the single most distinctive thing it contributes that the others do not',
      items: {
        type: 'object', additionalProperties: false,
        required: ['repo', 'unique_value', 'use_or_ignore'],
        properties: { repo: { type: 'string' }, unique_value: { type: 'string' }, use_or_ignore: { type: 'string' } },
      },
    },
    contested: {
      type: 'array',
      description: 'points where the references genuinely disagree (and what we should pick)',
      items: {
        type: 'object', additionalProperties: false,
        required: ['question', 'positions', 'our_call'],
        properties: { question: { type: 'string' }, positions: { type: 'string' }, our_call: { type: 'string' } },
      },
    },
    condensed_narrative: { type: 'string', description: '3-5 tight paragraphs: what the whole reference set teaches us, similarities first then the few uniquenesses worth lifting' },
  },
}

// ---------- Phase 1: cluster by dimension ----------
phase('Cluster')
const DIMENSIONS = [
  { key: 'verbs', desc: 'VERB SURFACE & CLI SHAPE — which verb names/structures recur across tools, which are idiosyncratic.' },
  { key: 'lifecycle', desc: 'LIFECYCLE & CLEANUP — ephemeral vs persistent defaults, teardown, reapers, orphan prevention, naming/identity.' },
  { key: 'isolation', desc: 'ISOLATION, NETWORK & RESOURCES — mount posture, network defaults, resource caps/annotations, egress policy, the security model.' },
  { key: 'gotchas', desc: 'GOTCHAS & ANTI-PATTERNS — recurring pitfalls (worktree/.git, KVM/SELinux, --rm-vs-crash) and the platform-creep warning.' },
  { key: 'llm_ux', desc: 'LLM/SKILL INTEGRATION & UX — how tools expose themselves to coding agents (skills, doctor checks, parseable output, config files).' },
]
const clusters = (await parallel(DIMENSIONS.map(d => () =>
  agent(
    `Condense the reference set along ONE dimension: ${d.desc}\n\n` +
    `${PROJECT}\n\n` +
    `${FINDINGS_INSTRUCTION}\n\n` +
    `For this dimension only: identify the SHARED patterns (which multiple repos independently exhibit — name the repos), explain why each recurs, and say whether we should adopt it. Then identify the UNIQUE contributions (something only one/few repos do) and whether it is worth stealing. End with a recommendation for our tool. Return ONLY the structured object.`,
    { label: `cluster:${d.key}`, phase: 'Cluster', schema: CLUSTER_SCHEMA }
  ).catch(() => null)
))).filter(Boolean)

const clusterDigest = clusters.map(c =>
  `## ${c.dimension}\nSHARED:\n${c.shared_patterns.map(p => `- ${p.pattern} [${p.repos_exhibiting.join(', ')}] → ${p.adopt_for_us}`).join('\n')}\nUNIQUE:\n${c.unique_contributions.map(u => `- ${u.repo}: ${u.what} → ${u.worth_stealing}`).join('\n')}\nRECO: ${c.recommendation_for_us}`
).join('\n\n')

// ---------- Phase 2: condense ----------
phase('Condense')
const condensed = await agent(
  `Reconcile the per-dimension clustering into ONE condensed cross-reference.\n\n` +
  `${PROJECT}\n\n` +
  `PER-DIMENSION CLUSTERS:\n${clusterDigest}\n\n` +
  `Produce: (1) the consensus patterns the field broadly agrees on (with how widely shared + implication for us), (2) a per-repo table with ONE line of unique value each (cover every repo named in the clusters), (3) genuinely contested points and our call, (4) a 3-5 paragraph condensed narrative — similarities first, then the few uniquenesses worth lifting. Return ONLY the structured object.`,
  { label: 'condense', phase: 'Condense', schema: CONDENSE_SCHEMA }
)

return { clusters, condensed }
