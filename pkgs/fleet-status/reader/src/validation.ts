import schemaValid from '../.generated/validate-snapshot.js';
import contract from '../contracts/public-contract.json';
import type { Snapshot, Subject, Primitive } from './types';

const sources: Record<string, readonly string[]> = contract.sources;
const providers: Record<string, string> = contract.providers;
const domains: Record<string, readonly string[]> = contract.stringDomains;
const summaries: Record<string, string> = contract.eventSummaries;
const scopes = new Set<string>(contract.scopes);
const errors = new Set<string>(contract.errorCodes);
const modes = new Set(['continuous', 'demand-loaded', 'socket-activated', 'manual', 'dormant', 'retired', 'unknown']);
const hostLabels: Record<string, string> = { nas: 'NAS', 'strix-coordinator': 'Strix coordinator', client: 'Zenbook', 'strix-worker': 'Strix worker' };
const hash = /^[a-f0-9]{7,64}$/;
const utc = /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,9})?Z$/;
const time = (value: string) => Date.parse(value);
const errorValid = (value: string | null) => value === null || errors.has(value);
const timestamp = (value: string) => utc.test(value) && Number.isFinite(time(value));
const numericKeys = new Set(Object.values(sources).flat().filter(key => /(?:Bytes|NSec|Count|Percent|Watts|Celsius|Ms|Tokens|PerSecond)$/.test(key)));
for (const key of ['host.load1', 'host.load5', 'host.load15', 'host.failures', 'instance.tasksCurrent',
  'provider.calls', 'provider.successes', 'provider.refusals', 'provider.errors', 'quota.limit', 'quota.remaining',
  'inference.requests', 'inference.errors', 'cloud.requests', 'cloud.errors', 'cloud.cpuTime',
  'dns.queries', 'dns.blocked', 'dns.blockedFraction', 'tailnet.peersOnline', 'backup.bytes']) numericKeys.add(key);
const booleanKeys = new Set(Object.values(sources).flat().filter(key => /(?:Configured|Ready|Reachable|Response|Reboot|Available)$/.test(key)
  || /\.(?:configured|loaded|enabled|releaseCurrent|releaseBooted|mounted|onDemand|maintenance)$/.test(key)));


function subjectAllowed(subject: Subject): boolean {
  if (subject.publicUrl !== undefined) return false; // No public destinations enrolled yet.
  if (subject.declaredMode !== undefined && !modes.has(subject.declaredMode)) return false;
  if (subject.kind === 'fleet') return subject.id === 'fleet' && subject.label === 'Fleet';
  if (subject.kind === 'host') return subject.id.startsWith('host-') && hostLabels[subject.id.slice(5)] === subject.label;
  if (subject.kind === 'provider') return subject.id.startsWith('provider-') && providers[subject.id.slice(9)] === subject.label;
  if (subject.kind === 'account') {
    const match = /^account-([a-z]+)-([1-9][0-9]?)$/.exec(subject.id);
    return Boolean(match && Object.hasOwn(providers, match[1]) && subject.label === `${providers[match[1]]} account ${match[2]}`);
  }
  if (subject.kind === 'quota-bucket') {
    const match = /^quota-([a-z]+)-([1-9][0-9]?)-([a-z0-9-]{1,64})$/.exec(subject.id);
    return Boolean(match && Object.hasOwn(providers, match[1]) && subject.label === `${providers[match[1]]} quota`);
  }
  const dynamic: Record<string, string> = { instance: 'DSH instance', session: 'DSH session', invocation: 'Supervised run' };
  return Boolean(dynamic[subject.kind] && subject.label === dynamic[subject.kind]
    && new RegExp(`^${subject.kind}-[a-f0-9]{24}$`).test(subject.id));
}

function primitiveAllowed(key: string, value: Primitive, ids: Set<string>): boolean {
  if (value === null) return true;
  if (typeof value === 'boolean') return booleanKeys.has(key);
  if (typeof value === 'number') return numericKeys.has(key) && Number.isFinite(value)
    && (key.endsWith('Celsius') || value >= 0);
  if (typeof value !== 'string') return false;
  if (key.endsWith('At')) return timestamp(value);
  if (Object.hasOwn(domains, key)) return domains[key].includes(value);
  if (key === 'quota.bucketId') return ids.has(value) && value.startsWith('quota-');
  // Additional source keys remain explicitly unknown until their public
  // domains are enrolled. A bounded string is not a public projection policy.
  return false;
}

function unitAllowed(key: string, unit: string | undefined, value: Primitive): boolean {
  if (unit === undefined) return typeof value !== 'number' || /^host\.load(?:1|5|15)$/.test(key);
  if (unit === 'percent' && typeof value === 'number' && (value < 0 || value > 100)) return false;
  if (key.endsWith('Percent')) return unit === 'percent' && (typeof value !== 'number' || value >= 0 && value <= 100);
  if (key.endsWith('Bytes')) return unit === 'bytes';
  if (key.endsWith('Tokens')) return unit === 'tokens';
  if (key.endsWith('NSec')) return unit === 'nanoseconds';
  if (key.endsWith('Ms')) return unit === 'milliseconds';
  if (key.endsWith('Watts')) return unit === 'watts';
  if (key.endsWith('Celsius')) return unit === 'celsius';
  if (key.endsWith('PerSecond')) return ['tokens-per-second', 'bytes-per-second', 'requests-per-second'].includes(unit);
  if (key === 'quota.limit' || key === 'quota.remaining') return ['requests', 'tokens', 'neurons', 'usd', 'percent'].includes(unit);
  return unit === 'count';
}

/** Shape and per-source public-domain validation; never return raw errors. */
export function validateSnapshot(data: unknown, now = Date.now()): data is Snapshot {
  if (!schemaValid(data)) return false;
  const snapshot = data as Snapshot;
  if (snapshot.synthetic !== false || snapshot.publisher.id !== 'nas-observer'
    || !Number.isSafeInteger(snapshot.publisher.sequence)
    || snapshot.snapshotId !== 'snapshot-' + snapshot.publisher.sequence || !/^[a-f0-9]{64}$/.test(snapshot.catalogRevision)
    || !timestamp(snapshot.generatedAt) || time(snapshot.generatedAt) > now + 300_000
    || snapshot.publisher.sourceRevision != null && !hash.test(snapshot.publisher.sourceRevision)) return false;
  const ids = new Set(snapshot.subjects.map(row => row.id));
  const eventIds = new Set(snapshot.events.map(row => row.id));
  if (ids.size !== snapshot.subjects.length || eventIds.size !== snapshot.events.length) return false;
  for (const subject of snapshot.subjects) {
    if (!subjectAllowed(subject) || subject.relations.some(relation => !ids.has(relation.targetId))) return false;
  }
  const coverage = new Set<string>();
  for (const row of snapshot.coverage) {
    if (!Object.hasOwn(sources, row.sourceId) || coverage.has(row.sourceId) || !errorValid(row.errorCode)) return false;
    coverage.add(row.sourceId);
    if (row.lastSuccessAt !== null && row.lastAttemptAt !== null && time(row.lastSuccessAt) > time(row.lastAttemptAt)) return false;
    if ([row.lastAttemptAt, row.lastSuccessAt, row.gapFrom].some(value => value != null && time(value) > time(snapshot.generatedAt) + 5000)) return false;
  }
  const observed = new Set<string>();
  for (const row of snapshot.observations) {
    const identity = `${row.sourceId}:${row.subjectId}:${row.key}`;
    if (!ids.has(row.subjectId) || !Object.hasOwn(sources, row.sourceId) || !sources[row.sourceId]?.includes(row.key) || !coverage.has(row.sourceId)
      || observed.has(identity) || !errorValid(row.errorCode) || row.scope !== undefined && !scopes.has(row.scope)
      || !primitiveAllowed(row.key, row.value, ids) || !unitAllowed(row.key, row.unit, row.value)) return false;
    observed.add(identity);
    if (row.observedAt !== null && row.lastAttemptAt !== null && time(row.observedAt) > time(row.lastAttemptAt)) return false;
    if (row.observedAt !== null && row.expiresAt !== null && time(row.expiresAt) < time(row.observedAt)) return false;
    if ([row.observedAt, row.lastAttemptAt, row.lastGood?.observedAt].some(value => value != null && time(value) > time(snapshot.generatedAt) + 5000)) return false;
    if (row.lastGood && (!primitiveAllowed(row.key, row.lastGood.value, ids) || !unitAllowed(row.key, row.unit, row.lastGood.value)
      || row.lastAttemptAt !== null && time(row.lastGood.observedAt) > time(row.lastAttemptAt))) return false;
  }
  for (const event of snapshot.events) {
    if (!/^event-[a-f0-9]{24}$/.test(event.id) || !ids.has(event.subjectId) || !Object.hasOwn(sources, event.sourceId) || !coverage.has(event.sourceId)
      || summaries[event.type] !== event.summary || time(event.at) > time(snapshot.generatedAt) + 5000
      || event.endedAt !== undefined && (time(event.endedAt) < time(event.at) || time(event.endedAt) > time(snapshot.generatedAt) + 5000)
      || event.durationMs !== undefined && !Number.isFinite(event.durationMs)) return false;
    if (event.invocationId && !ids.has(event.invocationId) || event.sessionId && !ids.has(event.sessionId)
      || event.workItemId && !ids.has(event.workItemId) || event.parentEventId && !eventIds.has(event.parentEventId)) return false;
    for (const metric of event.metrics ?? []) {
      if (!sources[event.sourceId]?.includes(metric.key) || metric.value !== null && !Number.isFinite(metric.value)
        || !unitAllowed(metric.key, metric.unit, metric.value)) return false;
    }
  }
  return true;
}
