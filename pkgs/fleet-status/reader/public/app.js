'use strict';
const element = id => document.getElementById(id);
let latest = null;
let busy = false;
let receivedMonotonic = 0;
function when(value) {
  if (!value) return 'Unknown';
  const date = new Date(value);
  return Number.isFinite(date.getTime()) ? date.toLocaleString() : 'Unknown';
}
function display(value, unit) {
  if (value === null || value === undefined) return 'Unknown';
  const result = typeof value === 'number' ? value.toLocaleString(undefined, { maximumFractionDigits: 3 }) : String(value);
  return unit ? result + ' ' + unit : result;
}
function render() {
  const snapshot = latest?.snapshot;
  const rows = snapshot?.observations ?? [];
  const sourceNow = latest ? new Date(latest.serverTime).getTime() + Math.max(0, performance.now() - receivedMonotonic) : 0;
  const labels = new Map((snapshot?.subjects ?? []).map(subject => [subject.id, subject.label]));
  const filter = element('filter').value;
  const selected = rows.filter(row => filter === 'all' || (filter === 'compute' && /^(compute|inference)\./.test(row.sourceId))
    || filter === 'host' && /^(host|fleet)\./.test(row.sourceId) || filter === 'agent' && /^agent\./.test(row.sourceId));
  const fragment = document.createDocumentFragment();
  for (const row of selected.slice(0, 1000)) {
    const tr = document.createElement('tr');
    const expired = row.expiresAt !== null && new Date(row.expiresAt).getTime() <= sourceNow;
    const freshness = row.errorCode ? row.errorCode : expired ? 'Stale' : row.expiresAt ? 'Within source deadline' : 'No freshness claim';
    for (const value of [labels.get(row.subjectId) ?? 'Unregistered subject', row.key, display(row.value, row.unit), row.grade, when(row.observedAt), freshness]) {
      const td = document.createElement('td'); td.textContent = value; tr.append(td);
    }
    fragment.append(tr);
  }
  element('observations').replaceChildren(fragment);
  element('notice').textContent = selected.length > 1000 ? 'Showing the first 1,000 of ' + selected.length + ' observations. The complete dataset is available as JSON.'
    : selected.length === 0 ? 'No observations have been published for this view.' : '';
  const coverage = document.createDocumentFragment();
  for (const row of snapshot?.coverage ?? []) {
    const li = document.createElement('li');
    li.textContent = row.sourceId + ': ' + row.state + '; last success ' + when(row.lastSuccessAt) + (row.errorCode ? '; ' + row.errorCode : '');
    coverage.append(li);
  }
  element('coverage').replaceChildren(coverage);
}
async function refresh() {
  if (busy) return;
  busy = true; element('refresh').disabled = true;
  try {
    const response = await fetch('/api/v1/status.json', { cache: 'no-store', signal: AbortSignal.timeout(10000) });
    if (!response.ok) throw new Error('unavailable');
    const data = await response.json();
    if (data.schemaVersion !== 'fleet-status-response/1') throw new Error('invalid');
    latest = data; receivedMonotonic = performance.now();
    element('connection').textContent = ({ connected: 'Observer connected', disconnected: 'Observer disconnected', uninitialized: 'Awaiting the first observer report' })[data.connection.state] ?? 'Reporting state unknown';
    element('received').textContent = 'Last received: ' + when(data.connection.lastReceivedAt);
    element('checked').textContent = 'Checked ' + when(data.serverTime);
    render();
  } catch {
    element('connection').textContent = 'Status storage is unavailable. Retained observations below may be stale.';
    if (latest) render();
  } finally { busy = false; element('refresh').disabled = false; }
}
element('refresh').addEventListener('click', refresh);
element('filter').addEventListener('change', render);
refresh();
setInterval(refresh, 15000);
