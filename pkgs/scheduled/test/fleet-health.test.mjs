// The two fleet-health items of the master fixture (fleet-health, tmp-ageing). Both are readings:
// the plain box-upkeep timers (tripwires, failure markers, gc-root-reaper, tmpfiles) keep doing the
// work and stay plain (AGENTS.md D41-D49); these items only say what those timers and the hosts
// show. Every guardrail below is a line of the Ticket brief, so a careless edit fails here.
import test from 'node:test';
import assert from 'node:assert/strict';
import { cpSync, mkdtempSync, chmodSync, readdirSync, statSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { validateFile } from '../src/lib/validate.mjs';

const FIXTURE = fileURLToPath(new URL('./fixtures/master', import.meta.url));

async function item(file) {
  const dir = mkdtempSync(join(tmpdir(), 'scheduled-fleet-health-'));
  try {
    cpSync(FIXTURE, dir, { recursive: true });
    const walk = (p) => {
      const st = statSync(p);
      chmodSync(p, st.isDirectory() ? 0o700 : 0o600);
      if (st.isDirectory()) for (const e of readdirSync(p)) walk(join(p, e));
    };
    walk(dir);
    const r = await validateFile(join(dir, '.agency/scheduled', file));
    assert.deepEqual(r.problems, [], file);
    // The schema joins an array prompt with newlines; the brief is read the way the Ticket gets it.
    return { value: r.value, lines: r.prompt.split('\n') };
  } finally { rmSync(dir, { recursive: true, force: true }); }
}

// A command that changes state. The brief may name one only on its "Never" line.
const MUTATING = /git (push|fetch|pull|commit|bundle|gc|branch -[dD]|worktree (remove|prune))|\brm\b|nix-collect-garbage|nix store (gc|delete|optimise)|systemctl (--user )?(start|stop|restart|reset-failed|kill|mask|disable|enable)|tailscale up/;
// What a public repository must not carry (DIRECTIVES 4.3).
const PERSONAL = /\/home\/|~\/notes|~\/today|~\/mecattaf|\bcc2\b|claude-work|\btom\b/i;

function shared(lines, file) {
  const never = lines.filter((l) => l.startsWith('Never'));
  assert.equal(never.length, 1, `${file}: one "Never" line`);
  for (const l of lines) {
    if (!l.startsWith('Never')) assert.doesNotMatch(l, MUTATING, `${file}: a step names a state-changing command: ${l}`);
    assert.doesNotMatch(l, PERSONAL, `${file}: personal path or name: ${l}`);
  }
  const text = lines.join('\n');
  assert.match(text, /^Report only\./m, `${file}: opens as a report`);
  assert.match(text, /ssh -o BatchMode=yes strix-coordinator /, `${file}: reads the build host without a prompt`);
  assert.match(text, /strix-worker is dormant: never contact it\./, `${file}: strix-worker ban`);
  assert.match(text, /Nothing was changed\./, `${file}: the report ends by saying nothing changed`);
  return never[0];
}

test('fleet-health: weekly, disabled, failed units on both hosts and / against the 25 GB build floor', async () => {
  const { value, lines } = await item('fleet-health.jsonc');
  assert.equal(value.enabled, false);
  assert.deepEqual(value.on.schedule, [{ cron: '0 7 * * 0', timezone: 'Europe/Paris' }]);
  const never = shared(lines, 'fleet-health');
  const text = lines.join('\n');
  assert.match(text, /systemctl --failed --no-legend --plain/);
  assert.match(text, /systemctl --user --failed --no-legend --plain/);
  assert.match(text, /strix-coordinator systemctl --failed --no-legend --plain/);
  assert.match(text, /df -BG --output=target,avail,pcent \//);
  assert.match(text, /strix-coordinator df -BG --output=target,avail,pcent \//);
  assert.match(text, /less than 25G available/);
  for (const word of ['start', 'stop', 'restart', 'reset', 'garbage', 'delete', 'Herdr', 'user manager', 're-authenticate'])
    assert.ok(never.includes(word), `Never line names ${word}`);
});

test('tmp-ageing: weekly, disabled, reports /tmp work at risk and touches none of it', async () => {
  const { value, lines } = await item('tmp-ageing.jsonc');
  assert.equal(value.enabled, false);
  assert.deepEqual(value.on.schedule, [{ cron: '0 8 * * 0', timezone: 'Europe/Paris' }]);
  const never = shared(lines, 'tmp-ageing');
  const text = lines.join('\n');
  assert.match(text, /build no sync tool, sweep or schedule for it/, 'carries the push-habit rule');
  assert.match(text, /git -C <dir> log --oneline --branches --not --remotes/, 'unpushed commits without network');
  assert.match(text, /git --no-optional-locks -C <dir> status --porcelain --branch/, 'status must not refresh the index');
  assert.doesNotMatch(text, /(?<!--no-optional-locks )-C <dir> status/, 'every status read skips the index refresh');
  assert.match(text, /do not override safe\.directory/, 'a checkout another user owns is skipped, not trusted');
  assert.match(text, /\/nix\/var\/nix\/gcroots\/auto/);
  assert.match(text, /journalctl -u gc-root-reaper --since -8d/);
  assert.match(text, /\*\.bundle/);
  for (const word of ['push', 'fetch', 'commit', 'bundle', 'worktree', 'branch', 'GC root', 'file', 'index'])
    assert.ok(never.includes(word), `Never line names ${word}`);
});
