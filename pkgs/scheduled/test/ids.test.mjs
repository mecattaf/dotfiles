// ids.test.mjs — tests for src/lib/ids.mjs
// Run: node --test test/ids.test.mjs

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';

import {
  STEM_RE,
  agencyId,
  parseId,
  spoolStamp,
  censusStamp,
  spoolName,
  manualSpoolName,
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
  it('accepts fleet-nightly', () => {
    assert.ok(STEM_RE.test('fleet-nightly'));
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
    assert.equal(agencyId('/home/tom/mecattaf/crm', '/home/tom'), 'mecattaf/crm');
  });
  it('returns single-segment relative path', () => {
    assert.equal(agencyId('/home/tom/work', '/home/tom'), 'work');
  });
});

// ---------------------------------------------------------------------------
// parseId
// ---------------------------------------------------------------------------

describe('parseId', () => {
  it('splits master:fleet-nightly correctly', () => {
    assert.deepEqual(parseId('master:fleet-nightly'), {
      agency: 'master',
      stem: 'fleet-nightly',
    });
  });
  it('splits sub-agency id correctly', () => {
    assert.deepEqual(parseId('mecattaf/crm:sync-contacts'), {
      agency: 'mecattaf/crm',
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
// censusStamp
// ---------------------------------------------------------------------------

describe('censusStamp', () => {
  it('formats 2026-11-12T00:00:41.000Z correctly', () => {
    const d = new Date('2026-11-12T00:00:41.000Z');
    assert.equal(censusStamp(d), '20261112T000041Z');
  });
  it('includes seconds', () => {
    const d = new Date('2026-11-12T14:35:07.000Z');
    assert.equal(censusStamp(d), '20261112T143507Z');
  });
});

// ---------------------------------------------------------------------------
// spoolName
// ---------------------------------------------------------------------------

describe('spoolName', () => {
  it('builds scheduled occurrence name', () => {
    const d = new Date('2026-11-12T00:00:00.000Z');
    const name = spoolName({ agency: 'master', stem: 'fleet-nightly', instant: d });
    assert.equal(name, 'master~fleet-nightly@20261112T0000Z.json');
  });
  it('replaces / in agency with - in spool name', () => {
    const d = new Date('2026-11-12T00:00:00.000Z');
    const name = spoolName({ agency: 'mecattaf/crm', stem: 'sync', instant: d });
    assert.equal(name, 'mecattaf-crm~sync@20261112T0000Z.json');
  });
});

// ---------------------------------------------------------------------------
// manualSpoolName
// ---------------------------------------------------------------------------

describe('manualSpoolName', () => {
  it('builds manual occurrence name', () => {
    const name = manualSpoolName({ agency: 'master', stem: 'fleet-nightly', ulid: '01JABCD1234567890ABCDE' });
    assert.equal(name, 'master~fleet-nightly@manual~01JABCD1234567890ABCDE.json');
  });
  it('replaces / in agency with - in spool name', () => {
    const name = manualSpoolName({ agency: 'mecattaf/crm', stem: 'sync', ulid: 'TESTULIDVALUE123456789' });
    assert.equal(name, 'mecattaf-crm~sync@manual~TESTULIDVALUE123456789.json');
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
