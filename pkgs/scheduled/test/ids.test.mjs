// ids.test.mjs — tests for src/lib/ids.mjs
// Run: node --test test/ids.test.mjs

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';

import {
  STEM_RE,
  agencyId,
  parseId,
  spoolStamp,
  occurrenceName,
  runName,
  ulid,
} from '../src/lib/ids.mjs';

// ---------------------------------------------------------------------------
// STEM_RE
// ---------------------------------------------------------------------------

describe('STEM_RE', () => {
  it('accepts single lowercase letter', () => {
    assert.ok(STEM_RE.test('a'));
  });
  it('accepts single digit', () => {
    assert.ok(STEM_RE.test('0'));
  });
  it('accepts example-daily', () => {
    assert.ok(STEM_RE.test('example-daily'));
  });
  it('accepts update-check', () => {
    assert.ok(STEM_RE.test('update-check'));
  });
  it('rejects leading hyphen', () => {
    assert.ok(!STEM_RE.test('-bad'));
  });
  it('rejects trailing hyphen', () => {
    assert.ok(!STEM_RE.test('bad-'));
  });
  it('rejects uppercase', () => {
    assert.ok(!STEM_RE.test('Bad'));
  });
  it('rejects empty string', () => {
    assert.ok(!STEM_RE.test(''));
  });
  it('rejects stem that is too long (33 chars)', () => {
    // 33 chars: 1 start + 31 middle + 1 end = 33 chars; middle limit is 30
    assert.ok(!STEM_RE.test('a' + '-'.repeat(31) + 'b'));
  });
  it('accepts stem at max length (32 chars: 1+30+1)', () => {
    assert.ok(STEM_RE.test('a' + 'b'.repeat(30) + 'c'));
  });
});

// ---------------------------------------------------------------------------
// agencyId
// ---------------------------------------------------------------------------

describe('agencyId', () => {
  it('returns master for home directory', () => {
    assert.equal(agencyId('/home/tom', '/home/tom'), 'master');
  });
  it('returns relative path for sub-agency', () => {
    assert.equal(agencyId('/home/me/work/widgets', '/home/me'), 'work/widgets');
  });
  it('returns single-segment relative path', () => {
    assert.equal(agencyId('/home/tom/work', '/home/tom'), 'work');
  });
});

// ---------------------------------------------------------------------------
// parseId
// ---------------------------------------------------------------------------

describe('parseId', () => {
  it('splits master:example-daily correctly', () => {
    assert.deepEqual(parseId('master:example-daily'), {
      agency: 'master',
      stem: 'example-daily',
    });
  });
  it('splits sub-agency id correctly', () => {
    assert.deepEqual(parseId('work/widgets:sync-contacts'), {
      agency: 'work/widgets',
      stem: 'sync-contacts',
    });
  });
  it('throws for id without colon', () => {
    assert.throws(() => parseId('noseparator'), /colon/i);
  });
});

// ---------------------------------------------------------------------------
// spoolStamp
// ---------------------------------------------------------------------------

describe('spoolStamp', () => {
  it('formats 2026-11-12T00:00:00.000Z correctly', () => {
    const d = new Date('2026-11-12T00:00:00.000Z');
    assert.equal(spoolStamp(d), '20261112T0000Z');
  });
  it('formats 2026-11-12T14:35:00.000Z correctly', () => {
    const d = new Date('2026-11-12T14:35:00.000Z');
    assert.equal(spoolStamp(d), '20261112T1435Z');
  });
});

// ---------------------------------------------------------------------------
// occurrenceName and runName (inbox record names)
// ---------------------------------------------------------------------------

describe('occurrenceName', () => {
  it('builds a schedule record name', () => {
    const due = new Date('2026-11-12T00:00:00.000Z');
    assert.equal(occurrenceName({ namespace: 'master', item: 'example-daily', due }), 'master~example-daily@20261112T0000Z.json');
  });
  it('replaces / in a namespace with +', () => {
    const due = new Date('2026-11-12T00:00:00.000Z');
    assert.equal(occurrenceName({ namespace: 'team/widgets', item: 'sync', due }), 'team+widgets~sync@20261112T0000Z.json');
  });
});

describe('runName', () => {
  it('builds a manual run record name', () => {
    assert.equal(runName({ namespace: 'master', item: 'example-daily', run: '01JABCD1234567890ABCDEFGHJ' }), 'master~example-daily@run~01JABCD1234567890ABCDEFGHJ.json');
  });
  it('replaces / in a namespace with +', () => {
    assert.equal(runName({ namespace: 'team/widgets', item: 'sync', run: 'X' }), 'team+widgets~sync@run~X.json');
  });
});

// ---------------------------------------------------------------------------
// ulid
// ---------------------------------------------------------------------------

describe('ulid', () => {
  it('returns a 26-character string', () => {
    const id = ulid(new Date());
    assert.equal(id.length, 26);
  });
  it('contains only Crockford base32 characters', () => {
    const CROCKFORD_RE = /^[0-9A-HJKMNP-TV-Z]{26}$/;
    for (let i = 0; i < 20; i++) {
      assert.ok(CROCKFORD_RE.test(ulid(new Date())), `ulid() produced non-Crockford chars`);
    }
  });
  it('two ULIDs for the same millisecond have the same 10-char prefix', () => {
    const d = new Date('2026-11-12T00:00:00.000Z');
    const a = ulid(d);
    const b = ulid(d);
    assert.equal(a.slice(0, 10), b.slice(0, 10));
  });
  it('ULIDs are monotonically sortable across time', () => {
    const d1 = new Date('2026-11-12T00:00:00.000Z');
    const d2 = new Date('2026-11-12T00:01:00.000Z');
    assert.ok(ulid(d1) < ulid(d2));
  });
  it('throws for invalid date', () => {
    assert.throws(() => ulid(new Date('not a date')), /RangeError|Invalid/i);
  });
});
