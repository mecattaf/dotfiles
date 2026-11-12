// The midnight sequence (Tom, 2026-09-20 R6/R7): "a midnight sequence full archival followed by a dedicated
// dotfiles operation: check if open gh issues that were filed today are closed otherwise cc opus works on them
// (culminating in a clean tree); then does the atomic fleet update so that the morning is fresh".
//
// The order between the three halves is a workflow's job, so the sequence is one workflow script,
// .agency/workflows/fleet-nightly.js, and the master item fleet-nightly.jsonc is only its start nudge: a
// request to the superagent that names the script and the agency (no `workflow` key, ANSWERS 10). Both ship
// in the staged master agency the integrator copies; the item stays "enabled": false.
//
// The script body is run here the way the workflow interpreter runs it (meta cut out, body wrapped in an async
// function of agent, parallel, pipeline, phase, log, budget, workflow and the args JSON), against a stub agent().
import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { lstatSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import * as jsonc from 'jsonc-parser';
import { validateFile } from '../src/lib/validate.mjs';

const AGENCY = fileURLToPath(new URL('./fixtures/master', import.meta.url));
const ITEM = join(AGENCY, '.agency/scheduled/fleet-nightly.jsonc');
const SCRIPT_REL = '.agency/workflows/fleet-nightly.js';
const SCRIPT = join(AGENCY, SCRIPT_REL);
const NIGHT = '2026-11-12';

/** Split `export const meta = {...};` off the source; the body keeps its line count. */
function split(src) {
  const start = src.indexOf('export const meta = ');
  assert.ok(start >= 0, 'the script declares export const meta');
  const end = src.indexOf('\n};', start);
  assert.ok(end > start, 'the meta literal ends with a line "};"');
  const header = src.slice(start + 'export const meta = '.length, end + 2);
  const errors = [];
  const meta = jsonc.parse(header, errors, { allowTrailingComma: true });
  assert.deepEqual(errors, [], 'meta is a pure literal');
  const cut = src.slice(start, end + 3);
  const body = src.slice(0, start) + '\n'.repeat(cut.split('\n').length - 1) + src.slice(end + 3);
  return { meta, body };
}

/** Run the body with a stub agent(); `answer(call)` returns what agent() resolves to (null = a failed node). */
async function runScript(args, answer) {
  const { body } = split(readFileSync(SCRIPT, 'utf8'));
  const calls = [];
  const phases = [];
  const logs = [];
  const agent = async (prompt, opts = {}) => {
    const call = { prompt, opts, phase: phases.at(-1) };
    calls.push(call);
    return answer(call);
  };
  const phase = (t) => { phases.push(String(t)); };
  const log = (m) => { logs.push(String(m)); };
  const parallel = async (thunks) => Promise.all(thunks.map((t) => t()));
  const ctx = vm.createContext(Object.create(null));
  const fn = new vm.Script(
    '(async function (agent, parallel, pipeline, phase, log, budget, workflow, __argsJson) {\n'
    + '"use strict"; const args = __argsJson === undefined ? undefined : JSON.parse(__argsJson);\n'
    + body + '\n})', { filename: SCRIPT_REL }).runInContext(ctx);
  let result;
  let error;
  try {
    result = await fn(agent, parallel, undefined, phase, log, () => ({}), undefined,
      args === undefined ? undefined : JSON.stringify(args));
  } catch (e) { error = e; }
  // The interpreter hands the result back as JSON (sandbox toJson); so does this harness, which also drops the
  // script realm's prototypes.
  if (result !== undefined) result = JSON.parse(JSON.stringify(result));
  return { calls, phases, logs, result, error };
}

const ISSUES = [{ number: 801, title: 'one' }, { number: 802, title: 'two' }];
const answers = ({ issues = ISSUES, clean = true } = {}) => ({ opts }) => {
  switch (opts.label) {
    case 'archival': return 'archived';
    case 'issues-open': return issues === null ? null : { issues };
    case 'clean-tree': return { clean, detail: clean ? 'clean, fast-forwarded' : 'M flake.nix' };
    case 'fleet-update': return 'launched';
    default: return `worked on ${opts.label}`;
  }
};

test('N1: fleet-nightly is a disabled start nudge that names the workflow script and the agency', async () => {
  const r = await validateFile(ITEM);
  assert.deepEqual(r.problems, []);
  assert.equal(r.value.enabled, false);
  assert.equal(r.value.workflow, undefined);
  assert.match(r.prompt, /not work for a worker/);
  assert.match(r.prompt, /orchestrator_workflow_start/);
  assert.ok(r.prompt.includes(`script ${SCRIPT_REL}`), r.prompt);
  assert.match(r.prompt, /cwd the agency folder/);
  assert.match(r.prompt, /trigger_id/);
  assert.match(r.prompt, /"night": "<night key>"/);
  assert.match(r.prompt, /ignore this trigger/);
});

test('N2: the script it names is a regular file in the agency whose meta lists the four phases in order', () => {
  const st = lstatSync(SCRIPT);
  assert.ok(st.isFile() && !st.isSymbolicLink());
  const { meta } = split(readFileSync(SCRIPT, 'utf8'));
  assert.equal(meta.name, 'fleet-nightly');
  assert.ok(typeof meta.description === 'string' && meta.description.length > 0);
  assert.deepEqual(meta.phases.map((p) => p.title), ['archival', 'issues', 'clean-tree', 'fleet-update']);
});

test('N3: archival, then today\'s open issues one Ticket each, then the clean-tree check, then the fleet update', async () => {
  const { calls, phases, result, error } = await runScript({ night: NIGHT }, answers());
  assert.equal(error, undefined, String(error?.stack));
  assert.deepEqual(calls.map((c) => c.opts.label),
    ['archival', 'issues-open', 'issue-801', 'issue-802', 'clean-tree', 'fleet-update']);
  assert.deepEqual(phases, ['archival', 'issues', 'clean-tree', 'fleet-update']);
  assert.deepEqual(calls.map((c) => c.phase), ['archival', 'issues', 'issues', 'issues', 'clean-tree', 'fleet-update']);
  for (const c of calls) assert.ok(c.prompt.includes(NIGHT), `${c.opts.label} names the night`);
  assert.ok(calls[1].prompt.includes('created:2026-11-12'));
  assert.ok(calls[1].opts.schema && calls[4].opts.schema, 'the list and the clean-tree check answer JSON');
  assert.equal(result.night, NIGHT);
  assert.deepEqual(result.issues.map((i) => i.number), [801, 802]);
  assert.equal(result.clean, true);
  assert.equal(result.fleet, 'launched');
});

test('N4: a tree that is not clean ends the night before the fleet update', async () => {
  const { calls, result, error } = await runScript({ night: NIGHT }, answers({ clean: false }));
  assert.equal(error, undefined, String(error?.stack));
  assert.ok(!calls.some((c) => c.opts.label === 'fleet-update'));
  assert.equal(result.clean, false);
  assert.match(result.fleet, /^skipped: /);
});

test('N5: a failed clean-tree check also skips the fleet update; a failed list runs no issue node', async () => {
  const failedCheck = await runScript({ night: NIGHT }, (c) => (c.opts.label === 'clean-tree' ? null : answers()(c)));
  assert.ok(!failedCheck.calls.some((c) => c.opts.label === 'fleet-update'));
  assert.match(failedCheck.result.fleet, /^skipped: /);
  const failedList = await runScript({ night: NIGHT }, answers({ issues: null }));
  assert.deepEqual(failedList.calls.map((c) => c.opts.label), ['archival', 'issues-open', 'clean-tree', 'fleet-update']);
  assert.deepEqual(failedList.result.issues, []);
});

test('N6: issue nodes are capped by args.maxIssues (default 3); the rest are named, not worked', async () => {
  const many = [1, 2, 3, 4, 5].map((n) => ({ number: n, title: `t${n}` }));
  const dflt = await runScript({ night: NIGHT }, answers({ issues: many }));
  assert.deepEqual(dflt.calls.filter((c) => /^issue-\d/.test(c.opts.label)).map((c) => c.opts.label), ['issue-1', 'issue-2', 'issue-3']);
  assert.deepEqual(dflt.result.deferred, [4, 5]);
  const one = await runScript({ night: NIGHT, maxIssues: 1 }, answers({ issues: many }));
  assert.deepEqual(one.calls.filter((c) => /^issue-\d/.test(c.opts.label)).map((c) => c.opts.label), ['issue-1']);
});

test('N7: without a night key (YYYY-MM-DD) the script refuses before any node', async () => {
  for (const args of [undefined, {}, { night: 'tonight' }]) {
    const { calls, error } = await runScript(args, answers());
    assert.ok(error instanceof Error || (error && typeof error.message === 'string'), JSON.stringify(args));
    assert.deepEqual(calls, []);
  }
});

test('N8: the worker briefs carry the guardrails: no force-push, no merge, no NAS switch, builds on the strix builder', async () => {
  const { calls } = await runScript({ night: NIGHT }, answers());
  const by = Object.fromEntries(calls.map((c) => [c.opts.label, c.prompt]));
  for (const p of [by['issue-801'], by['clean-tree'], by['fleet-update']]) assert.match(p, /[Nn]ever force-push/);
  assert.match(by['issue-801'], /[Nn]ever merge/);
  assert.match(by['issue-801'], /never push main/);
  assert.match(by['issue-801'], /strix-coordinator/);
  assert.match(by['issue-801'], /25 GB/);
  assert.match(by['clean-tree'], /--ff-only/);
  assert.match(by['clean-tree'], /[Nn]ever stash, reset, clean/);
  assert.match(by['fleet-update'], /df -h \//);
  assert.match(by['fleet-update'], /25 GB/);
  assert.match(by['fleet-update'], /nas is an activation target/);
  for (const c of calls) assert.ok(!/strix-worker/.test(c.prompt) || /[Nn]ever .*strix-worker/.test(c.prompt), c.opts.label);
});
