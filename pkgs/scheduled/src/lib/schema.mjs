/**
 * schema.mjs - JSONC parsing, validation, normalization, and revision for workflow files.
 * Exports: parseWorkflow, normalize, revision, formatProblems, jsonSchema
 */

import { createHash } from 'node:crypto';
import * as jsonc from 'jsonc-parser';

// ─── Duration parsing ──────────────────────────────────────────────────────────

const DURATION_RE = /^([1-9][0-9]*)(s|m|h|d)$/;
function parseDuration(s) {
  if (typeof s !== 'string') return null;
  const m = DURATION_RE.exec(s);
  if (!m) return null;
  const n = parseInt(m[1], 10);
  const unit = m[2];
  const ms = { s: 1000, m: 60000, h: 3600000, d: 86400000 }[unit];
  return n * ms;
}

// ─── Known keys at each path level ───────────────────────────────────────────

const TOP_KEYS = new Set([
  '$schema', 'name', 'enabled', 'on', 'if', 'window', 'concurrency',
  'permissions', 'hold', 'outcome', 'context', 'job',
]);
const ON_KEYS = new Set(['schedule', 'workflow_dispatch']);
const SCHEDULE_ENTRY_KEYS = new Set(['cron', 'timezone']);
const DISPATCH_KEYS = new Set(['inputs']);
const DISPATCH_INPUT_KEYS = new Set(['description', 'type', 'options', 'required', 'default']);
const IF_KEYS = new Set(['idle', 'command']);
const CONCURRENCY_KEYS = new Set(['group', 'queue']);
const PERMISSIONS_KEYS = new Set(['mode', 'add-dirs']);
const OUTCOME_KEYS = new Set(['goal', 'check', 'attempts']);
const CONTEXT_KEYS = new Set(['previous', 'diff']);
const JOB_KEYS = new Set(['prompt', 'prompt-file', 'cwd', 'timeout']);

// Keys that are banned (the spec says these are "absent on purpose")
const BANNED_KEYS = new Set(['model', 'profile', 'priority', 'env', 'secrets']);

// ─── Levenshtein for did-you-mean ─────────────────────────────────────────────

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

// ─── Problem builder ──────────────────────────────────────────────────────────

function problem(severity, code, line, col, message) {
  return { severity, code, line: line ?? 0, col: col ?? 0, message };
}
function err(code, line, col, message) { return problem('error', code, line, col, message); }
function warn(code, line, col, message) { return problem('warning', code, line, col, message); }

// ─── Position helpers using jsonc-parser tree ─────────────────────────────────

function nodePosition(text, node) {
  if (!node) return { line: 0, col: 0 };
  // Convert offset to 1-based line/col
  const before = text.slice(0, node.offset);
  const lines = before.split('\n');
  const line = lines.length;
  const col = lines[lines.length - 1].length + 1;
  return { line, col };
}

function findKeyNode(text, parentNode, key) {
  if (!parentNode || parentNode.type !== 'object') return null;
  for (const child of (parentNode.children || [])) {
    // child is a property node with children[0] = key, children[1] = value
    if (child.children && child.children[0] && child.children[0].value === key) {
      return child.children[0]; // the key node
    }
  }
  return null;
}

function getValueNode(parentNode, key) {
  if (!parentNode || parentNode.type !== 'object') return null;
  for (const child of (parentNode.children || [])) {
    if (child.children && child.children[0] && child.children[0].value === key) {
      return child.children[1];
    }
  }
  return null;
}

function getArrayItemNode(parentNode, index) {
  if (!parentNode || parentNode.type !== 'array') return null;
  return (parentNode.children || [])[index] || null;
}

// ─── Command type validation ──────────────────────────────────────────────────

function isLines(v) {
  return typeof v === 'string' || (Array.isArray(v) && v.every(x => typeof x === 'string'));
}

function isCommand(v) {
  if (Array.isArray(v) && v.length > 0 && v.every(x => typeof x === 'string' && x.length > 0)) return true;
  if (v && typeof v === 'object' && !Array.isArray(v)) {
    const keys = Object.keys(v);
    if (keys.length === 1 && keys[0] === 'sh' && isLines(v.sh)) return true;
  }
  return false;
}

// ─── Main parser ──────────────────────────────────────────────────────────────

/**
 * Parse a JSONC workflow file text.
 * @param {string} text - File text
 * @param {object} opts - { proposal: boolean }
 * @returns {{ value: object|null, problems: Problem[] }}
 */
export function parseWorkflow(text, { proposal = false } = {}) {
  const problems = [];

  // 1. Parse with jsonc-parser
  const parseErrors = [];
  const tree = jsonc.parseTree(text, parseErrors, {
    allowTrailingComma: true,
    allowEmptyContent: false,
    disallowComments: false,
  });

  // Also parse to get a value object
  const parseErrors2 = [];
  const rawValue = jsonc.parse(text, parseErrors2, {
    allowTrailingComma: true,
  });

  // Report parse errors
  for (const e of parseErrors) {
    // Convert offset to line/col
    const before = text.slice(0, e.offset);
    const lines = before.split('\n');
    const line = lines.length;
    const col = lines[lines.length - 1].length + 1;
    problems.push(err('parse', line, col, `JSON parse error (code ${e.error}): unexpected token.`));
  }

  if (parseErrors.length > 0 || rawValue === undefined) {
    return { value: null, problems };
  }

  if (typeof rawValue !== 'object' || rawValue === null || Array.isArray(rawValue)) {
    problems.push(err('parse', 1, 1, 'Workflow file must be a JSON object.'));
    return { value: null, problems };
  }

  // 2. Check for duplicate keys using the tree
  checkDuplicateKeys(text, tree, [], problems);

  // 3. Validate the object
  const value = validateObject(text, tree, rawValue, { proposal }, problems);

  if (problems.some(p => p.severity === 'error')) {
    return { value: null, problems };
  }

  return { value, problems };
}

/** Recursively check for duplicate keys in object nodes */
function checkDuplicateKeys(text, node, path, problems) {
  if (!node) return;
  if (node.type === 'object') {
    const seen = new Map();
    for (const child of (node.children || [])) {
      if (!child.children || child.children.length < 1) continue;
      const keyNode = child.children[0];
      const key = keyNode.value;
      if (seen.has(key)) {
        const pos = nodePosition(text, keyNode);
        problems.push(err('duplicate-key', pos.line, pos.col,
          `Key "${key}" is defined more than once in this object.`));
      } else {
        seen.set(key, child);
      }
      // Recurse into value
      if (child.children[1]) checkDuplicateKeys(text, child.children[1], [...path, key], problems);
    }
  } else if (node.type === 'array') {
    for (let i = 0; i < (node.children || []).length; i++) {
      checkDuplicateKeys(text, node.children[i], [...path, i], problems);
    }
  }
}

/** Check for unknown keys at the top level and known sub-objects */
function checkKeys(text, objNode, rawObj, allowedKeys, path, problems) {
  for (const key of Object.keys(rawObj)) {
    if (key.startsWith('x-')) continue; // x-* are free
    if (!allowedKeys.has(key)) {
      const keyNode = findKeyNode(text, objNode, key);
      const pos = keyNode ? nodePosition(text, keyNode) : { line: 0, col: 0 };

      // Check if it's a banned key (model/profile/priority/env/secrets)
      if (BANNED_KEYS.has(key)) {
        problems.push(err('unknown-key', pos.line, pos.col,
          `"${key}" is not a valid workflow key (compute scheduling is the floor's responsibility).`));
        continue;
      }

      // Try to suggest a known key
      const suggestion = didYouMean(key, allowedKeys);
      const msg = suggestion
        ? `"${key}" is not a key here; did you mean "${suggestion}"?`
        : `"${key}" is not a key here.`;
      problems.push(err('unknown-key', pos.line, pos.col, msg));
    }
  }
}

/** Full object validation, returns normalized value */
function validateObject(text, tree, raw, { proposal }, problems) {
  const result = {};

  // Check top-level keys
  checkKeys(text, tree, raw, TOP_KEYS, [], problems);

  // $schema: ignored
  // name
  if ('name' in raw) {
    if (typeof raw.name !== 'string' || raw.name.length < 1 || raw.name.length > 80) {
      const n = getValueNode(tree, 'name');
      const pos = n ? nodePosition(text, n) : { line: 0, col: 0 };
      problems.push(err('type', pos.line, pos.col, '"name" must be a string of 1-80 characters.'));
    } else {
      result.name = raw.name;
    }
  }

  // enabled
  if ('enabled' in raw) {
    if (typeof raw.enabled !== 'boolean') {
      const n = getValueNode(tree, 'enabled');
      const pos = n ? nodePosition(text, n) : { line: 0, col: 0 };
      problems.push(err('type', pos.line, pos.col, '"enabled" must be a boolean.'));
    } else {
      result.enabled = raw.enabled;
    }
  } else {
    result.enabled = true;
  }

  // on (required)
  if (!('on' in raw)) {
    problems.push(err('type', 1, 1, '"on" is required.'));
  } else if (typeof raw.on !== 'object' || raw.on === null || Array.isArray(raw.on)) {
    const n = getValueNode(tree, 'on');
    const pos = n ? nodePosition(text, n) : { line: 0, col: 0 };
    problems.push(err('type', pos.line, pos.col, '"on" must be an object.'));
  } else {
    result.on = validateOn(text, getValueNode(tree, 'on'), raw.on, problems);
  }

  // if
  if ('if' in raw) {
    if (typeof raw.if !== 'object' || raw.if === null || Array.isArray(raw.if)) {
      const n = getValueNode(tree, 'if');
      const pos = n ? nodePosition(text, n) : { line: 0, col: 0 };
      problems.push(err('type', pos.line, pos.col, '"if" must be an object.'));
    } else {
      result.if = validateIf(text, getValueNode(tree, 'if'), raw.if, problems);
    }
  } else {
    result.if = {};
  }

  // window
  if ('window' in raw) {
    const ms = parseDuration(raw.window);
    const minMs = 60 * 60 * 1000; // 1h
    const maxMs = 30 * 24 * 60 * 60 * 1000; // 30d
    if (ms === null || ms < minMs || ms > maxMs) {
      const n = getValueNode(tree, 'window');
      const pos = n ? nodePosition(text, n) : { line: 0, col: 0 };
      problems.push(err('type', pos.line, pos.col, '"window" must be a duration between 1h and 30d (e.g. "1h", "7d").'));
    } else {
      result.window_ms = ms;
    }
  } else {
    result.window_ms = null;
  }

  // concurrency
  if ('concurrency' in raw) {
    result.concurrency = validateConcurrency(text, getValueNode(tree, 'concurrency'), raw.concurrency, problems);
  }
  // (default set during normalize)

  // permissions
  if ('permissions' in raw) {
    result.permissions = validatePermissions(text, getValueNode(tree, 'permissions'), raw.permissions, problems);
  } else {
    result.permissions = { mode: 'workspace-write', 'add-dirs': [] };
  }

  // hold
  if ('hold' in raw) {
    result.hold = validateHold(text, getValueNode(tree, 'hold'), raw.hold, problems);
  } else {
    result.hold = [];
  }

  // outcome
  if ('outcome' in raw) {
    result.outcome = validateOutcome(text, getValueNode(tree, 'outcome'), raw.outcome, problems);
  } else {
    result.outcome = { attempts: 1 };
  }

  // context
  if ('context' in raw) {
    result.context = validateContext(text, getValueNode(tree, 'context'), raw.context, problems);
  } else {
    result.context = { previous: 1, diff: true };
  }

  // job (required)
  if (!('job' in raw)) {
    problems.push(err('job', 1, 1, '"job" is required.'));
  } else if (typeof raw.job !== 'object' || raw.job === null || Array.isArray(raw.job)) {
    const n = getValueNode(tree, 'job');
    const pos = n ? nodePosition(text, n) : { line: 0, col: 0 };
    problems.push(err('type', pos.line, pos.col, '"job" must be an object.'));
  } else {
    result.job = validateJob(text, getValueNode(tree, 'job'), raw.job, problems);
  }

  // proposal checks
  if (proposal) {
    if (!raw['x-proposal']) {
      problems.push(err('proposal', 1, 1, 'Files in proposed/ must have an "x-proposal" key with {by, at, why}.'));
    }
    if (raw.enabled !== false) {
      problems.push(err('proposal', 1, 1, 'Files in proposed/ must have "enabled": false.'));
    }
  }

  // Copy x- keys
  for (const key of Object.keys(raw)) {
    if (key.startsWith('x-')) result[key] = raw[key];
  }

  return result;
}

function validateOn(text, onNode, raw, problems) {
  const result = {};

  checkKeys(text, onNode, raw, ON_KEYS, ['on'], problems);

  // Check for unknown on.* keys (not schedule or workflow_dispatch)
  for (const key of Object.keys(raw)) {
    if (key !== 'schedule' && key !== 'workflow_dispatch') {
      const keyNode = findKeyNode(text, onNode, key);
      const pos = keyNode ? nodePosition(text, keyNode) : { line: 0, col: 0 };
      problems.push(err('event', pos.line, pos.col,
        `"on.${key}" is not supported; other events are superagent Sources.`));
    }
  }

  if (!('schedule' in raw) && !('workflow_dispatch' in raw)) {
    const pos = onNode ? nodePosition(text, onNode) : { line: 0, col: 0 };
    problems.push(err('no-trigger', pos.line, pos.col,
      '"on" must have at least one of "schedule" or "workflow_dispatch".'));
    return result;
  }

  if ('schedule' in raw) {
    result.schedule = validateSchedule(text, getValueNode(onNode, 'schedule'), raw.schedule, problems);
  }

  if ('workflow_dispatch' in raw) {
    result.dispatch = validateDispatch(text, getValueNode(onNode, 'workflow_dispatch'), raw.workflow_dispatch, problems);
  } else {
    result.dispatch = { inputs: {} };
  }

  return result;
}

function validateSchedule(text, schedNode, raw, problems) {
  if (!Array.isArray(raw)) {
    const pos = schedNode ? nodePosition(text, schedNode) : { line: 0, col: 0 };
    problems.push(err('type', pos.line, pos.col, '"on.schedule" must be an array.'));
    return [];
  }
  if (raw.length < 1 || raw.length > 8) {
    const pos = schedNode ? nodePosition(text, schedNode) : { line: 0, col: 0 };
    problems.push(err('type', pos.line, pos.col, '"on.schedule" must have 1-8 entries.'));
    return raw.slice(0, 8);
  }

  const result = [];
  for (let i = 0; i < raw.length; i++) {
    const entry = raw[i];
    const entryNode = getArrayItemNode(schedNode, i);
    if (typeof entry !== 'object' || entry === null || Array.isArray(entry)) {
      const pos = entryNode ? nodePosition(text, entryNode) : { line: 0, col: 0 };
      problems.push(err('type', pos.line, pos.col, `Schedule entry ${i} must be an object.`));
      continue;
    }

    checkKeys(text, entryNode, entry, SCHEDULE_ENTRY_KEYS, ['on', 'schedule', i], problems);

    if (!('cron' in entry) || typeof entry.cron !== 'string') {
      const pos = entryNode ? nodePosition(text, entryNode) : { line: 0, col: 0 };
      problems.push(err('type', pos.line, pos.col, `Schedule entry ${i} must have a "cron" string.`));
    }
    if (!('timezone' in entry) || typeof entry.timezone !== 'string') {
      const pos = entryNode ? nodePosition(text, entryNode) : { line: 0, col: 0 };
      problems.push(err('timezone', pos.line, pos.col, `Schedule entry ${i} must have a "timezone" string.`));
    }

    if (typeof entry.cron === 'string' && typeof entry.timezone === 'string') {
      result.push({ cron: entry.cron, timezone: entry.timezone });
    }
  }

  return result;
}

function validateDispatch(text, dispNode, raw, problems) {
  if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) {
    const pos = dispNode ? nodePosition(text, dispNode) : { line: 0, col: 0 };
    problems.push(err('type', pos.line, pos.col, '"on.workflow_dispatch" must be an object.'));
    return { inputs: {} };
  }
  checkKeys(text, dispNode, raw, DISPATCH_KEYS, ['on', 'workflow_dispatch'], problems);
  const inputs = {};
  if ('inputs' in raw) {
    if (typeof raw.inputs !== 'object' || raw.inputs === null || Array.isArray(raw.inputs)) {
      const n = getValueNode(dispNode, 'inputs');
      const pos = n ? nodePosition(text, n) : { line: 0, col: 0 };
      problems.push(err('type', pos.line, pos.col, '"on.workflow_dispatch.inputs" must be an object.'));
    } else {
      const inputEntries = Object.entries(raw.inputs);
      if (inputEntries.length > 8) {
        const n = getValueNode(dispNode, 'inputs');
        const pos = n ? nodePosition(text, n) : { line: 0, col: 0 };
        problems.push(err('type', pos.line, pos.col, '"on.workflow_dispatch.inputs" may have at most 8 entries.'));
      }
      const nameRe = /^[a-z][a-z0-9_-]{0,31}$/;
      for (const [name, def] of inputEntries) {
        if (!nameRe.test(name)) {
          problems.push(err('type', 0, 0, `Input name "${name}" must match ^[a-z][a-z0-9_-]{0,31}$.`));
        }
        inputs[name] = def;
      }
    }
  }
  return { inputs };
}

function validateIf(text, ifNode, raw, problems) {
  checkKeys(text, ifNode, raw, IF_KEYS, ['if'], problems);
  const result = {};
  if ('idle' in raw) {
    if (typeof raw.idle !== 'boolean') {
      const n = getValueNode(ifNode, 'idle');
      const pos = n ? nodePosition(text, n) : { line: 0, col: 0 };
      problems.push(err('type', pos.line, pos.col, '"if.idle" must be a boolean.'));
    } else {
      result.idle = raw.idle;
    }
  }
  if ('command' in raw) {
    if (!isCommand(raw.command)) {
      const n = getValueNode(ifNode, 'command');
      const pos = n ? nodePosition(text, n) : { line: 0, col: 0 };
      problems.push(err('type', pos.line, pos.col, '"if.command" must be a Command (argv array or {sh: lines}).'));
    } else {
      result.command = raw.command;
    }
  }
  return result;
}

function validateConcurrency(text, conNode, raw, problems) {
  if (typeof raw === 'string') {
    return { group: raw, queue: 'single' };
  }
  if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) {
    const pos = conNode ? nodePosition(text, conNode) : { line: 0, col: 0 };
    problems.push(err('type', pos.line, pos.col, '"concurrency" must be a string or {group, queue} object.'));
    return null;
  }

  checkKeys(text, conNode, raw, CONCURRENCY_KEYS, ['concurrency'], problems);

  if ('cancel-in-progress' in raw) {
    const keyNode = findKeyNode(text, conNode, 'cancel-in-progress');
    const pos = keyNode ? nodePosition(text, keyNode) : { line: 0, col: 0 };
    problems.push(err('cancel', pos.line, pos.col,
      '"concurrency.cancel-in-progress" is not supported.'));
  }

  const result = {};
  if ('group' in raw) {
    if (typeof raw.group !== 'string') {
      const n = getValueNode(conNode, 'group');
      const pos = n ? nodePosition(text, n) : { line: 0, col: 0 };
      problems.push(err('type', pos.line, pos.col, '"concurrency.group" must be a string.'));
    } else {
      result.group = raw.group;
    }
  }
  if ('queue' in raw) {
    if (raw.queue !== 'single' && raw.queue !== 'max') {
      const n = getValueNode(conNode, 'queue');
      const pos = n ? nodePosition(text, n) : { line: 0, col: 0 };
      problems.push(err('type', pos.line, pos.col, '"concurrency.queue" must be "single" or "max".'));
    } else {
      result.queue = raw.queue;
    }
  } else {
    result.queue = 'single';
  }
  return result;
}

function validatePermissions(text, permNode, raw, problems) {
  if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) {
    const pos = permNode ? nodePosition(text, permNode) : { line: 0, col: 0 };
    problems.push(err('type', pos.line, pos.col, '"permissions" must be an object.'));
    return { mode: 'workspace-write', 'add-dirs': [] };
  }
  checkKeys(text, permNode, raw, PERMISSIONS_KEYS, ['permissions'], problems);
  const result = { mode: 'workspace-write', 'add-dirs': [] };

  if ('mode' in raw) {
    if (raw.mode !== 'workspace-write' && raw.mode !== 'danger-full-access') {
      const n = getValueNode(permNode, 'mode');
      const pos = n ? nodePosition(text, n) : { line: 0, col: 0 };
      problems.push(err('type', pos.line, pos.col,
        '"permissions.mode" must be "workspace-write" or "danger-full-access".'));
    } else {
      result.mode = raw.mode;
    }
  }

  if ('add-dirs' in raw) {
    if (!Array.isArray(raw['add-dirs'])) {
      const n = getValueNode(permNode, 'add-dirs');
      const pos = n ? nodePosition(text, n) : { line: 0, col: 0 };
      problems.push(err('type', pos.line, pos.col, '"permissions.add-dirs" must be an array.'));
    } else if (raw['add-dirs'].length > 8) {
      const n = getValueNode(permNode, 'add-dirs');
      const pos = n ? nodePosition(text, n) : { line: 0, col: 0 };
      problems.push(err('type', pos.line, pos.col, '"permissions.add-dirs" may have at most 8 entries.'));
    } else {
      const dirs = [];
      for (const d of raw['add-dirs']) {
        if (typeof d !== 'string' || (!d.startsWith('/') && !d.startsWith('~/'))) {
          problems.push(err('type', 0, 0,
            `"permissions.add-dirs" entries must be absolute paths or start with "~/".`));
        } else {
          dirs.push(d);
        }
      }
      result['add-dirs'] = dirs;
    }
  }

  return result;
}

function validateHold(text, holdNode, raw, problems) {
  if (!Array.isArray(raw)) {
    const pos = holdNode ? nodePosition(text, holdNode) : { line: 0, col: 0 };
    problems.push(err('type', pos.line, pos.col, '"hold" must be an array of strings.'));
    return [];
  }
  if (raw.length > 8) {
    const pos = holdNode ? nodePosition(text, holdNode) : { line: 0, col: 0 };
    problems.push(err('type', pos.line, pos.col, '"hold" may have at most 8 entries.'));
  }
  const result = [];
  for (let i = 0; i < Math.min(raw.length, 8); i++) {
    const s = raw[i];
    if (typeof s !== 'string' || s.length < 1 || s.length > 160) {
      problems.push(err('type', 0, 0, `"hold[${i}]" must be a string of 1-160 characters.`));
    } else {
      result.push(s);
    }
  }
  return result;
}

function validateOutcome(text, outNode, raw, problems) {
  if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) {
    const pos = outNode ? nodePosition(text, outNode) : { line: 0, col: 0 };
    problems.push(err('type', pos.line, pos.col, '"outcome" must be an object.'));
    return { attempts: 1 };
  }
  checkKeys(text, outNode, raw, OUTCOME_KEYS, ['outcome'], problems);
  const result = {};

  if ('goal' in raw) {
    if (typeof raw.goal !== 'string' || raw.goal.length < 1 || raw.goal.length > 160) {
      const n = getValueNode(outNode, 'goal');
      const pos = n ? nodePosition(text, n) : { line: 0, col: 0 };
      problems.push(err('type', pos.line, pos.col, '"outcome.goal" must be a string of 1-160 characters.'));
    } else {
      result.goal = raw.goal;
    }
  }

  if ('check' in raw) {
    if (!isCommand(raw.check)) {
      const n = getValueNode(outNode, 'check');
      const pos = n ? nodePosition(text, n) : { line: 0, col: 0 };
      problems.push(err('type', pos.line, pos.col,
        '"outcome.check" must be a Command (argv array or {sh: lines}).'));
    } else {
      result.check = raw.check;
    }
  }

  if ('attempts' in raw) {
    const a = raw.attempts;
    if (!Number.isInteger(a) || a < 1 || a > 3) {
      const n = getValueNode(outNode, 'attempts');
      const pos = n ? nodePosition(text, n) : { line: 0, col: 0 };
      problems.push(err('type', pos.line, pos.col, '"outcome.attempts" must be an integer 1-3.'));
    } else {
      result.attempts = a;
      if (a > 1 && !('check' in raw)) {
        const n = getValueNode(outNode, 'attempts');
        const pos = n ? nodePosition(text, n) : { line: 0, col: 0 };
        problems.push(err('attempts', pos.line, pos.col,
          '"outcome.attempts" above 1 requires "outcome.check".'));
      }
    }
  } else {
    result.attempts = 1;
  }

  return result;
}

function validateContext(text, ctxNode, raw, problems) {
  if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) {
    const pos = ctxNode ? nodePosition(text, ctxNode) : { line: 0, col: 0 };
    problems.push(err('type', pos.line, pos.col, '"context" must be an object.'));
    return { previous: 1, diff: true };
  }
  checkKeys(text, ctxNode, raw, CONTEXT_KEYS, ['context'], problems);
  const result = { previous: 1, diff: true };

  if ('previous' in raw) {
    const p = raw.previous;
    if (!Number.isInteger(p) || p < 0 || p > 5) {
      const n = getValueNode(ctxNode, 'previous');
      const pos = n ? nodePosition(text, n) : { line: 0, col: 0 };
      problems.push(err('type', pos.line, pos.col, '"context.previous" must be an integer 0-5.'));
    } else {
      result.previous = p;
    }
  }

  if ('diff' in raw) {
    if (typeof raw.diff !== 'boolean') {
      const n = getValueNode(ctxNode, 'diff');
      const pos = n ? nodePosition(text, n) : { line: 0, col: 0 };
      problems.push(err('type', pos.line, pos.col, '"context.diff" must be a boolean.'));
    } else {
      result.diff = raw.diff;
    }
  }

  return result;
}

function validateJob(text, jobNode, raw, problems) {
  checkKeys(text, jobNode, raw, JOB_KEYS, ['job'], problems);
  const result = {};

  const hasPrompt = 'prompt' in raw;
  const hasPromptFile = 'prompt-file' in raw;

  if (!hasPrompt && !hasPromptFile) {
    const pos = jobNode ? nodePosition(text, jobNode) : { line: 0, col: 0 };
    problems.push(err('job', pos.line, pos.col,
      '"job" must have exactly one of "prompt" or "prompt-file".'));
  } else if (hasPrompt && hasPromptFile) {
    const pos = jobNode ? nodePosition(text, jobNode) : { line: 0, col: 0 };
    problems.push(err('job', pos.line, pos.col,
      '"job" must have exactly one of "prompt" or "prompt-file", not both.'));
  } else if (hasPrompt) {
    if (!isLines(raw.prompt)) {
      const n = getValueNode(jobNode, 'prompt');
      const pos = n ? nodePosition(text, n) : { line: 0, col: 0 };
      problems.push(err('job', pos.line, pos.col,
        '"job.prompt" must be a string or array of strings.'));
    } else {
      const promptText = Array.isArray(raw.prompt) ? raw.prompt.join('\n') : raw.prompt;
      if (promptText.length === 0) {
        const n = getValueNode(jobNode, 'prompt');
        const pos = n ? nodePosition(text, n) : { line: 0, col: 0 };
        problems.push(err('job', pos.line, pos.col, '"job.prompt" must not be empty.'));
      } else if (Buffer.byteLength(promptText, 'utf8') > 32 * 1024) {
        const n = getValueNode(jobNode, 'prompt');
        const pos = n ? nodePosition(text, n) : { line: 0, col: 0 };
        problems.push(err('job', pos.line, pos.col, '"job.prompt" must not exceed 32 KiB.'));
      } else {
        result.prompt = promptText;
      }
    }
  } else if (hasPromptFile) {
    if (typeof raw['prompt-file'] !== 'string') {
      const n = getValueNode(jobNode, 'prompt-file');
      const pos = n ? nodePosition(text, n) : { line: 0, col: 0 };
      problems.push(err('job', pos.line, pos.col, '"job.prompt-file" must be a string path.'));
    } else {
      result['prompt-file'] = raw['prompt-file'];
    }
  }

  if ('cwd' in raw) {
    if (typeof raw.cwd !== 'string') {
      const n = getValueNode(jobNode, 'cwd');
      const pos = n ? nodePosition(text, n) : { line: 0, col: 0 };
      problems.push(err('type', pos.line, pos.col, '"job.cwd" must be a string.'));
    } else {
      result.cwd = raw.cwd;
    }
  }

  if ('timeout' in raw) {
    const ms = parseDuration(raw.timeout);
    const minMs = 5 * 60 * 1000; // 5m
    const maxMs = 24 * 60 * 60 * 1000; // 24h
    if (ms === null || ms < minMs || ms > maxMs) {
      const n = getValueNode(jobNode, 'timeout');
      const pos = n ? nodePosition(text, n) : { line: 0, col: 0 };
      problems.push(err('type', pos.line, pos.col,
        '"job.timeout" must be a duration between 5m and 24h.'));
    } else {
      result.timeout_ms = ms;
    }
  } else {
    result.timeout_ms = 3 * 60 * 60 * 1000; // 3h default
  }

  return result;
}

// ─── Normalize ────────────────────────────────────────────────────────────────

/**
 * Normalize a valid parsed workflow value into the show --json shape.
 * @param {object} value - From parseWorkflow (errors-free)
 * @param {object} opts - { file, agencyRoot, agencyId, stem, promptText, home }
 * @returns The normalized shape
 */
export function normalize(value, { file, agencyRoot, agencyId, stem, promptText, home } = {}) {
  const id = `${agencyId}:${stem}`;

  // Resolve cwd: relative paths are relative to agencyRoot
  let cwd = value.job?.cwd ?? agencyRoot ?? '/';
  if (cwd && !cwd.startsWith('/') && !cwd.startsWith('~/') && agencyRoot) {
    cwd = `${agencyRoot}/${cwd}`;
  }

  // Resolve concurrency group default
  const concurrency = value.concurrency
    ? { ...value.concurrency, group: value.concurrency.group ?? id }
    : { group: id, queue: 'single' };

  // Normalize permissions
  const perms = value.permissions ?? { mode: 'workspace-write', 'add-dirs': [] };
  const addDirs = (perms['add-dirs'] ?? []).map(d => {
    if (d.startsWith('~/') && home) return `${home}/${d.slice(2)}`;
    return d;
  });

  // Inline prompt-file if provided
  let jobPrompt = value.job?.prompt ?? promptText ?? '';

  return {
    v: 1,
    id,
    stem,
    agency: { id: agencyId, root: agencyRoot ?? '' },
    path: file ?? '',
    kind: 'workflow',
    state: 'valid',
    revision: null, // caller fills in
    problems: [],
    spec: {
      name: value.name ?? stem,
      enabled: value.enabled ?? true,
      on: {
        schedule: (value.on?.schedule ?? []),
        dispatch: value.on?.dispatch ?? { inputs: {} },
      },
      if: value.if ?? {},
      window_ms: value.window_ms ?? null,
      concurrency,
      permissions: {
        mode: perms.mode ?? 'workspace-write',
        add_dirs: addDirs,
      },
      hold: value.hold ?? [],
      outcome: {
        goal: value.outcome?.goal ?? undefined,
        check: value.outcome?.check ?? undefined,
        attempts: value.outcome?.attempts ?? 1,
      },
      context: {
        previous: value.context?.previous ?? 1,
        diff: value.context?.diff ?? true,
      },
      job: {
        prompt: jobPrompt,
        cwd: cwd,
        timeout_ms: value.job?.timeout_ms ?? 3 * 60 * 60 * 1000,
      },
    },
  };
}

// ─── Revision ─────────────────────────────────────────────────────────────────

/**
 * Compute the revision: first 12 hex of sha256(sha256(fileBytes) + '\n' + sha256(promptBytes) or '').
 * @param {Buffer} fileBytes
 * @param {Buffer|null} promptBytes
 * @returns {string} 12 hex chars
 */
export function revision(fileBytes, promptBytes) {
  const fileHash = createHash('sha256').update(fileBytes).digest('hex');
  const promptHash = promptBytes ? createHash('sha256').update(promptBytes).digest('hex') : '';
  const combined = fileHash + '\n' + promptHash;
  return createHash('sha256').update(combined, 'utf8').digest('hex').slice(0, 12);
}

// ─── Format problems (compiler-style) ────────────────────────────────────────

/**
 * Format problems as compiler-style lines.
 * @param {string} file - file path to prefix
 * @param {Problem[]} problems
 * @returns {string[]} Lines (no trailing newline per line)
 */
export function formatProblems(file, problems) {
  const lines = [];
  for (const p of problems) {
    const loc = `${p.line}:${p.col}`;
    lines.push(`${file}:${loc}: ${p.severity}[${p.code}]:`);
    lines.push(`  ${p.message}`);
  }
  const errors = problems.filter(p => p.severity === 'error').length;
  const warnings = problems.filter(p => p.severity === 'warning').length;
  lines.push(`${file}: ${errors} error${errors === 1 ? '' : 's'}, ${warnings} warning${warnings === 1 ? '' : 's'}`);
  return lines;
}

// ─── JSON Schema ──────────────────────────────────────────────────────────────

/**
 * Return a JSON Schema object describing valid workflow files.
 */
export function jsonSchema() {
  return {
    $schema: 'http://json-schema.org/draft-07/schema#',
    title: 'Scheduled workflow',
    description: 'A scheduled workflow file for the scheduled CLI.',
    type: 'object',
    required: ['on', 'job'],
    additionalProperties: false,
    patternProperties: {
      '^x-': {},
    },
    properties: {
      $schema: { type: 'string', description: 'Editor support: load this schema.' },
      name: { type: 'string', minLength: 1, maxLength: 80, description: 'Display name (default: stem).' },
      enabled: { type: 'boolean', default: true, description: 'False pauses the schedule.' },
      on: {
        type: 'object',
        description: 'At least one of schedule or workflow_dispatch.',
        minProperties: 1,
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
                cron: { type: 'string', description: 'Five numeric cron fields.' },
                timezone: { type: 'string', description: 'UTC or IANA Area/Location zone.' },
              },
            },
          },
          workflow_dispatch: {
            type: 'object',
            additionalProperties: false,
            properties: {
              inputs: {
                type: 'object',
                maxProperties: 8,
                additionalProperties: {
                  type: 'object',
                  properties: {
                    description: { type: 'string' },
                    type: { type: 'string', enum: ['string', 'boolean', 'choice'] },
                    options: { type: 'array', items: { type: 'string' } },
                    required: { type: 'boolean' },
                    default: {},
                  },
                },
              },
            },
          },
        },
      },
      if: {
        type: 'object',
        additionalProperties: false,
        properties: {
          idle: { type: 'boolean' },
          command: {
            oneOf: [
              { type: 'array', items: { type: 'string', minLength: 1 }, minItems: 1 },
              { type: 'object', required: ['sh'], additionalProperties: false,
                properties: { sh: { oneOf: [{ type: 'string' }, { type: 'array', items: { type: 'string' } }] } } },
            ],
          },
        },
      },
      window: { type: 'string', pattern: '^[1-9][0-9]*(s|m|h|d)$', description: 'Duration 1h-30d.' },
      concurrency: {
        oneOf: [
          { type: 'string' },
          {
            type: 'object',
            additionalProperties: false,
            properties: {
              group: { type: 'string' },
              queue: { type: 'string', enum: ['single', 'max'], default: 'single' },
            },
          },
        ],
      },
      permissions: {
        type: 'object',
        additionalProperties: false,
        properties: {
          mode: { type: 'string', enum: ['workspace-write', 'danger-full-access'], default: 'workspace-write' },
          'add-dirs': { type: 'array', maxItems: 8, items: { type: 'string' } },
        },
      },
      hold: { type: 'array', maxItems: 8, items: { type: 'string', minLength: 1, maxLength: 160 } },
      outcome: {
        type: 'object',
        additionalProperties: false,
        properties: {
          goal: { type: 'string', minLength: 1, maxLength: 160 },
          check: {
            oneOf: [
              { type: 'array', items: { type: 'string', minLength: 1 }, minItems: 1 },
              { type: 'object', required: ['sh'], additionalProperties: false,
                properties: { sh: { oneOf: [{ type: 'string' }, { type: 'array', items: { type: 'string' } }] } } },
            ],
          },
          attempts: { type: 'integer', minimum: 1, maximum: 3, default: 1 },
        },
      },
      context: {
        type: 'object',
        additionalProperties: false,
        properties: {
          previous: { type: 'integer', minimum: 0, maximum: 5, default: 1 },
          diff: { type: 'boolean', default: true },
        },
      },
      job: {
        type: 'object',
        additionalProperties: false,
        properties: {
          prompt: {
            oneOf: [
              { type: 'string' },
              { type: 'array', items: { type: 'string' } },
            ],
            description: 'The agent prompt (mutually exclusive with prompt-file).',
          },
          'prompt-file': { type: 'string', description: 'Path under .agency/ to a prompt file.' },
          cwd: { type: 'string', description: 'Working directory (default: agency root).' },
          timeout: { type: 'string', pattern: '^[1-9][0-9]*(s|m|h|d)$', description: 'Duration 5m-24h (default 3h).' },
        },
      },
    },
  };
}
