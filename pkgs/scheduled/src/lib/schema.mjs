/**
 * schema.mjs - JSONC parsing, validation, normalization and revision of scheduled items (schema v1).
 * Exports: parseItem, normalize, revision, formatProblems, jsonSchema, PROMPT_MAX_BYTES
 *
 * A scheduled item is `<agency>/.agency/scheduled/<item>.jsonc`: a clock (`on.schedule`), the
 * work (`job.prompt` or `job.prompt-file`) and, optionally, the compute pair it runs on (`pair`, one
 * of the floor's pairs; absent, the floor's default pair). Conditions, retries, models, priority and
 * permissions are not item keys: the superagent judges an occurrence when it arrives.
 */

import { createHash } from 'node:crypto';
import * as jsonc from 'jsonc-parser';

/** The largest prompt, in UTF-8 bytes; the occurrence record caps `text` at 32 768 units, so every prompt fits. */
export const PROMPT_MAX_BYTES = 32 * 1024;

/** A pair name, as the occurrence record's `pair` field takes it. */
export const PAIR_RE = /^[a-z0-9]([a-z0-9-]{0,38}[a-z0-9])?$/;

// ─── Known keys at each level ────────────────────────────────────────────────

const TOP_KEYS = new Set(['$schema', 'name', 'enabled', 'pair', 'on', 'job']);
const ON_KEYS = new Set(['schedule']);
const SCHEDULE_ENTRY_KEYS = new Set(['cron', 'timezone']);
const JOB_KEYS = new Set(['prompt', 'prompt-file']);

const IN_PROMPT = 'write the condition into job.prompt; the superagent judges it when the occurrence arrives.';

/** Keys of the withdrawn workflow schema, each with where its intent goes now (code removed-key). */
const REMOVED = {
  top: {
    if: IN_PROMPT,
    outcome: IN_PROMPT,
    hold: IN_PROMPT,
    window: IN_PROMPT,
    context: IN_PROMPT,
    concurrency: 'the floor\'s executor.maxWorkers is the only cap.',
    permissions: 'workers run with the floor\'s full permissions.',
  },
  on: {
    workflow_dispatch: 'any item can be run now with "scheduled run <agency>:<item>".',
  },
  job: {
    cwd: 'the agency folder is always the working directory.',
    timeout: 'a worker ends when its work is done.',
  },
};

/** Keys that are not item keys on purpose, with the reason (code unknown-key). */
const REFUSED = {
  workflow: '"workflow" is not a scheduled-item key: a workflow script starts on a request to the superagent that names the script and the agency, never from a scheduled item.',
};
const COMPUTE = ['model', 'profile', 'priority', 'env', 'secrets'];
for (const key of COMPUTE) {
  REFUSED[key] = `"${key}" is not a scheduled-item key: name one of the floor's compute pairs with "pair", or leave it out for the floor's default pair; priority is the superagent's judgement.`;
}

// ─── Did-you-mean ────────────────────────────────────────────────────────────

function levenshtein(a, b) {
  const m = a.length, n = b.length;
  const dp = Array.from({ length: m + 1 }, (_, i) => [i, ...Array(n).fill(0)]);
  for (let j = 0; j <= n; j++) dp[0][j] = j;
  for (let i = 1; i <= m; i++) {
    for (let j = 1; j <= n; j++) {
      dp[i][j] = a[i - 1] === b[j - 1]
        ? dp[i - 1][j - 1]
        : 1 + Math.min(dp[i - 1][j], dp[i][j - 1], dp[i - 1][j - 1]);
    }
  }
  return dp[m][n];
}

function didYouMean(key, knownKeys) {
  let best = null, bestDist = Infinity;
  for (const k of knownKeys) {
    const d = levenshtein(key, k);
    if (d < bestDist && d <= 2) { bestDist = d; best = k; }
  }
  return best;
}

// ─── Problems and positions ──────────────────────────────────────────────────

function err(code, pos, message) {
  return { severity: 'error', code, line: pos?.line ?? 0, col: pos?.col ?? 0, message };
}

function offsetPosition(text, offset) {
  const lines = text.slice(0, offset).split('\n');
  return { line: lines.length, col: lines[lines.length - 1].length + 1 };
}

function nodePosition(text, node) {
  return node ? offsetPosition(text, node.offset) : { line: 0, col: 0 };
}

function propertyOf(parent, key) {
  if (!parent || parent.type !== 'object') return null;
  return (parent.children || []).find((c) => c.children?.[0]?.value === key) ?? null;
}

const keyNode = (parent, key) => propertyOf(parent, key)?.children[0] ?? null;
const valueNode = (parent, key) => propertyOf(parent, key)?.children[1] ?? null;
const keyPos = (text, parent, key) => nodePosition(text, keyNode(parent, key));
const valuePos = (text, parent, key) => nodePosition(text, valueNode(parent, key));

const isObject = (v) => typeof v === 'object' && v !== null && !Array.isArray(v);
const isLines = (v) => typeof v === 'string' || (Array.isArray(v) && v.every((x) => typeof x === 'string'));

// ─── Parser ──────────────────────────────────────────────────────────────────

/**
 * Parse and validate the text of one scheduled item.
 * @param {string} text - File text (JSONC)
 * @param {{ pairs?: string[]|null }} [opts] - The floor's pair names; an item may name only one of these
 * @returns {{ value: object|null, problems: object[] }} value is null when any error was found
 */
export function parseItem(text, { pairs = null } = {}) {
  const problems = [];
  const parseErrors = [];
  const tree = jsonc.parseTree(text, parseErrors, { allowTrailingComma: true, allowEmptyContent: false, disallowComments: false });
  const raw = jsonc.parse(text, [], { allowTrailingComma: true });

  for (const e of parseErrors) {
    problems.push(err('parse', offsetPosition(text, e.offset), `JSON parse error (code ${e.error}): unexpected token.`));
  }
  if (parseErrors.length > 0 || raw === undefined) return { value: null, problems };
  if (!isObject(raw)) {
    problems.push(err('parse', { line: 1, col: 1 }, 'A scheduled item must be a JSON object.'));
    return { value: null, problems };
  }

  checkDuplicateKeys(text, tree, problems);
  const value = validateItem(text, tree, raw, problems, pairs);
  return problems.some((p) => p.severity === 'error') ? { value: null, problems } : { value, problems };
}

function checkDuplicateKeys(text, node, problems) {
  if (!node) return;
  if (node.type === 'object') {
    const seen = new Set();
    for (const child of node.children || []) {
      const k = child.children?.[0];
      if (!k) continue;
      if (seen.has(k.value)) {
        problems.push(err('duplicate-key', nodePosition(text, k), `Key "${k.value}" is defined more than once in this object.`));
      }
      seen.add(k.value);
      checkDuplicateKeys(text, child.children[1], problems);
    }
  } else if (node.type === 'array') {
    for (const child of node.children || []) checkDuplicateKeys(text, child, problems);
  }
}

/** Unknown, removed and refused keys of one object; `x-*` keys are free. */
function checkKeys(text, node, raw, allowed, { removed = {}, prefix = '' }, problems) {
  for (const key of Object.keys(raw)) {
    if (key.startsWith('x-') || allowed.has(key)) continue;
    const pos = keyPos(text, node, key);
    const label = `${prefix}${key}`;
    if (Object.hasOwn(removed, key)) {
      problems.push(err('removed-key', pos, `"${label}" was removed: ${removed[key]}`));
    } else if (!prefix && Object.hasOwn(REFUSED, key)) {
      problems.push(err('unknown-key', pos, REFUSED[key]));
    } else {
      const suggestion = didYouMean(key, allowed);
      problems.push(err('unknown-key', pos, suggestion
        ? `"${label}" is not a key here; did you mean "${suggestion}"?`
        : `"${label}" is not a key here.`));
    }
  }
}

function validateItem(text, tree, raw, problems, pairs) {
  const result = {};
  checkKeys(text, tree, raw, TOP_KEYS, { removed: REMOVED.top }, problems);

  if ('name' in raw) {
    if (typeof raw.name !== 'string' || raw.name.length < 1 || raw.name.length > 80) {
      problems.push(err('type', valuePos(text, tree, 'name'), '"name" must be a string of 1-80 characters.'));
    } else {
      result.name = raw.name;
    }
  }

  if (!('enabled' in raw)) {
    problems.push(err('enabled-required', { line: 1, col: 1 },
      '"enabled" is required: an item is never armed by omission. Write "enabled": false until it should fire.'));
  } else if (typeof raw.enabled !== 'boolean') {
    problems.push(err('type', valuePos(text, tree, 'enabled'), '"enabled" must be a boolean.'));
  } else {
    result.enabled = raw.enabled;
  }

  if ('pair' in raw) {
    const pair = validatePair(raw.pair, pairs, valuePos(text, tree, 'pair'), problems);
    if (pair) result.pair = pair;
  }

  if (!('on' in raw)) {
    problems.push(err('type', { line: 1, col: 1 }, '"on" is required.'));
  } else if (!isObject(raw.on)) {
    problems.push(err('type', valuePos(text, tree, 'on'), '"on" must be an object.'));
  } else {
    result.on = validateOn(text, valueNode(tree, 'on'), raw.on, problems);
  }

  if (!('job' in raw)) {
    problems.push(err('job', { line: 1, col: 1 }, '"job" is required.'));
  } else if (!isObject(raw.job)) {
    problems.push(err('type', valuePos(text, tree, 'job'), '"job" must be an object.'));
  } else {
    result.job = validateJob(text, valueNode(tree, 'job'), raw.job, problems);
  }

  for (const key of Object.keys(raw)) {
    if (key.startsWith('x-')) result[key] = raw[key];
  }
  return result;
}

/**
 * The item's pair when it is one of `pairs`, else null with the problem pushed. With no pairs configured
 * every pair is refused: a record never names a pair the executor would refuse as unknown.
 */
function validatePair(pair, pairs, pos, problems) {
  if (typeof pair !== 'string' || !PAIR_RE.test(pair)) {
    problems.push(err('type', pos, '"pair" must be a pair name: lowercase letters and digits, inner hyphens, at most 40 characters.'));
    return null;
  }
  const known = [...new Set(pairs ?? [])].sort();
  if (known.length === 0) {
    problems.push(err('unknown-pair', pos,
      `"pair" "${pair}" cannot be checked: no pairs are configured (SCHEDULED_PAIRS); leave "pair" out to run on the floor's default pair.`));
    return null;
  }
  if (!known.includes(pair)) {
    const suggestion = didYouMean(pair, known);
    problems.push(err('unknown-pair', pos, `"pair" "${pair}" is not one of the floor's pairs (${known.join(', ')}); ${suggestion
      ? `did you mean "${suggestion}"?`
      : 'leave "pair" out to run on the floor\'s default pair.'}`));
    return null;
  }
  return pair;
}

function validateOn(text, node, raw, problems) {
  checkKeys(text, node, raw, ON_KEYS, { removed: REMOVED.on, prefix: 'on.' }, problems);
  if (!('schedule' in raw)) {
    problems.push(err('no-trigger', nodePosition(text, node), '"on.schedule" is required: an item fires only on its schedule.'));
    return { schedule: [] };
  }
  return { schedule: validateSchedule(text, valueNode(node, 'schedule'), raw.schedule, problems) };
}

function validateSchedule(text, node, raw, problems) {
  if (!Array.isArray(raw)) {
    problems.push(err('type', nodePosition(text, node), '"on.schedule" must be an array.'));
    return [];
  }
  if (raw.length < 1 || raw.length > 8) {
    problems.push(err('type', nodePosition(text, node), '"on.schedule" must have 1-8 entries.'));
    return [];
  }
  const result = [];
  raw.forEach((entry, i) => {
    const entryNode = node?.children?.[i] ?? null;
    const pos = nodePosition(text, entryNode);
    if (!isObject(entry)) {
      problems.push(err('type', pos, `Schedule entry ${i} must be an object.`));
      return;
    }
    checkKeys(text, entryNode, entry, SCHEDULE_ENTRY_KEYS, { prefix: `on.schedule[${i}].` }, problems);
    if (typeof entry.cron !== 'string') problems.push(err('type', pos, `Schedule entry ${i} must have a "cron" string.`));
    if (typeof entry.timezone !== 'string') problems.push(err('timezone', pos, `Schedule entry ${i} must have a "timezone" string.`));
    if (typeof entry.cron === 'string' && typeof entry.timezone === 'string') {
      result.push({ cron: entry.cron, timezone: entry.timezone });
    }
  });
  return result;
}

function validateJob(text, node, raw, problems) {
  checkKeys(text, node, raw, JOB_KEYS, { removed: REMOVED.job, prefix: 'job.' }, problems);
  const result = {};
  const hasPrompt = 'prompt' in raw;
  const hasPromptFile = 'prompt-file' in raw;
  if (hasPrompt === hasPromptFile) {
    problems.push(err('job', nodePosition(text, node), hasPrompt
      ? '"job" must have exactly one of "prompt" or "prompt-file", not both.'
      : '"job" must have exactly one of "prompt" or "prompt-file".'));
  } else if (hasPrompt) {
    const pos = valuePos(text, node, 'prompt');
    if (!isLines(raw.prompt)) {
      problems.push(err('job', pos, '"job.prompt" must be a string or array of strings.'));
    } else {
      const prompt = Array.isArray(raw.prompt) ? raw.prompt.join('\n') : raw.prompt;
      const bytes = Buffer.byteLength(prompt, 'utf8');
      if (bytes === 0) problems.push(err('job', pos, '"job.prompt" must not be empty.'));
      else if (bytes > PROMPT_MAX_BYTES) problems.push(err('job', pos, '"job.prompt" must not exceed 32 KiB.'));
      else result.prompt = prompt;
    }
  } else if (typeof raw['prompt-file'] !== 'string' || raw['prompt-file'].length === 0) {
    problems.push(err('job', valuePos(text, node, 'prompt-file'), '"job.prompt-file" must be a path relative to the agency folder.'));
  } else {
    result['prompt-file'] = raw['prompt-file'];
  }
  return result;
}

// ─── Normalize ───────────────────────────────────────────────────────────────

/**
 * The `show --json` shape of a valid item.
 * @param {object} value - From parseItem (error-free)
 * @param {{ file: string, root: string, agency: string, stem: string, prompt: string }} where
 */
export function normalize(value, { file, root, agency, stem, prompt }) {
  return {
    v: 1,
    id: `${agency}:${stem}`,
    item: stem,
    agency: { id: agency, root },
    path: file,
    state: value.enabled ? 'enabled' : 'disabled',
    revision: null,
    problems: [],
    spec: {
      name: value.name ?? stem,
      enabled: value.enabled,
      ...(value.pair ? { pair: value.pair } : {}),
      on: { schedule: value.on?.schedule ?? [] },
      job: {
        ...(value.job?.['prompt-file'] ? { 'prompt-file': value.job['prompt-file'] } : {}),
        prompt,
      },
    },
  };
}

// ─── Revision ────────────────────────────────────────────────────────────────

/**
 * The revision: first 12 hex of sha256(hex(sha256(fileBytes)) + '\n' + (hex(sha256(promptBytes)) or '')).
 * @param {Buffer} fileBytes
 * @param {Buffer|null} promptBytes
 * @returns {string}
 */
export function revision(fileBytes, promptBytes) {
  const fileHash = createHash('sha256').update(fileBytes).digest('hex');
  const promptHash = promptBytes ? createHash('sha256').update(promptBytes).digest('hex') : '';
  return createHash('sha256').update(fileHash + '\n' + promptHash, 'utf8').digest('hex').slice(0, 12);
}

// ─── Compiler-style problems ─────────────────────────────────────────────────

/**
 * @param {string} file
 * @param {object[]} problems
 * @returns {string[]}
 */
export function formatProblems(file, problems) {
  const lines = [];
  for (const p of problems) {
    lines.push(`${file}:${p.line}:${p.col}: ${p.severity}[${p.code}]:`);
    lines.push(`  ${p.message}`);
  }
  const errors = problems.filter((p) => p.severity === 'error').length;
  const warnings = problems.filter((p) => p.severity === 'warning').length;
  lines.push(`${file}: ${errors} error${errors === 1 ? '' : 's'}, ${warnings} warning${warnings === 1 ? '' : 's'}`);
  return lines;
}

// ─── JSON Schema ─────────────────────────────────────────────────────────────

/** The JSON Schema (draft 2020-12) of a scheduled item, for editors; `scheduled validate` is the authority. */
export function jsonSchema() {
  const lines = { oneOf: [{ type: 'string', minLength: 1 }, { type: 'array', items: { type: 'string' } }] };
  return {
    $schema: 'https://json-schema.org/draft/2020-12/schema',
    $id: 'scheduled-item.v1',
    title: 'Scheduled item',
    description: 'One <agency>/.agency/scheduled/<item>.jsonc: when an occurrence is due and the work it hands to the superagent.',
    type: 'object',
    required: ['enabled', 'on', 'job'],
    additionalProperties: false,
    patternProperties: { '^x-': {} },
    properties: {
      $schema: { type: 'string', description: 'Editor support: load this schema.' },
      name: { type: 'string', minLength: 1, maxLength: 80, description: 'Display title (default: the item stem).' },
      enabled: { type: 'boolean', description: 'Required. false: the heartbeat never hands off an occurrence; scheduled run still works.' },
      pair: { type: 'string', pattern: PAIR_RE.source, description: 'One of the floor\'s compute pairs (SCHEDULED_PAIRS); absent: the floor\'s default pair.' },
      on: {
        type: 'object',
        required: ['schedule'],
        additionalProperties: false,
        properties: {
          schedule: {
            type: 'array',
            minItems: 1,
            maxItems: 8,
            items: {
              type: 'object',
              required: ['cron', 'timezone'],
              additionalProperties: false,
              properties: {
                cron: { type: 'string', description: 'Five-field cron; instants at least 60 minutes apart.' },
                timezone: { type: 'string', description: 'IANA zone, for example Europe/Paris.' },
              },
            },
          },
        },
      },
      job: {
        type: 'object',
        additionalProperties: false,
        minProperties: 1,
        maxProperties: 1,
        properties: {
          prompt: { ...lines, description: 'The work, 1 byte to 32 KiB; an array is joined with newlines.' },
          'prompt-file': { type: 'string', minLength: 1, description: 'A file inside the agency folder, read at each tick.' },
        },
      },
    },
  };
}
