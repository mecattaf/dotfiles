import { timingSafeEqual } from 'node:crypto';

const token = process.env.CHROME_STREAM_TOKEN;
if (!token) throw new Error('Missing viewer token');
const port = Number(process.env.CHROME_STREAM_PORT || 4780);
const cdp = new WebSocket(process.env.CHROME_STREAM_CDP);
await new Promise((resolve, reject) => { cdp.onopen = resolve; cdp.onerror = reject; });
let serial = 0;
const pending = new Map();
const viewers = new Set();
function call(method, params = {}, sessionId) {
  return new Promise((resolve, reject) => {
    const id = ++serial;
    const timer = setTimeout(() => { pending.delete(id); reject(new Error(`${method} timed out`)); }, 10000);
    pending.set(id, { resolve, reject, timer });
    cdp.send(JSON.stringify({ id, method, params, sessionId }));
  });
}
function send(ws, value) { if (ws.readyState === 1) ws.send(JSON.stringify(value)); }
async function tabs(ws) {
  const { targetInfos } = await call('Target.getTargets');
  send(ws, { type: 'tabs', tabs: targetInfos.filter(t => t.type === 'page') });
}
cdp.onmessage = ({ data }) => {
  const m = JSON.parse(data);
  if (m.id) {
    const p = pending.get(m.id);
    if (!p) return;
    clearTimeout(p.timer); pending.delete(m.id);
    if (m.error) p.reject(new Error(m.error.message)); else p.resolve(m.result);
    return;
  }
  for (const ws of viewers) {
    if (m.sessionId !== ws.data.session) continue;
    if (m.method === 'Page.screencastFrame') {
      // The client acknowledges after decoding, so slow links cannot queue frames forever.
      send(ws, { type: 'frame', ...m.params, session: m.sessionId });
    } else if (m.method === 'Page.javascriptDialogOpening') {
      send(ws, { ...m.params, dialogType: m.params.type, type: 'dialog' });
    }
  }
};
cdp.onclose = () => { for (const ws of viewers) ws.close(1011, 'Chrome disconnected'); process.exit(1); };
async function attach(ws, targetId) {
  if (ws.data.session) {
    await call('Page.stopScreencast', {}, ws.data.session).catch(() => {});
    await call('Target.detachFromTarget', { sessionId: ws.data.session }).catch(() => {});
  }
  const { sessionId } = await call('Target.attachToTarget', { targetId, flatten: true });
  ws.data.session = sessionId;
  ws.data.target = targetId;
  await call('Page.enable', {}, sessionId);
  await call('Emulation.setDeviceMetricsOverride', { width: 1440, height: 900, deviceScaleFactor: 1, mobile: false }, sessionId);
  await call('Page.bringToFront', {}, sessionId);
  send(ws, { type: 'active', targetId });
  await call('Page.startScreencast', { format: 'jpeg', quality: 85, maxWidth: 1440, maxHeight: 900, everyNthFrame: 1 }, sessionId);
  await tabs(ws);
}
async function command(ws, m) {
  const session = ws.data.session;
  switch (m.type) {
    case 'tabs': return tabs(ws);
    case 'attach': return attach(ws, m.targetId);
    case 'new': {
      const { targetId } = await call('Target.createTarget', { url: 'about:blank' });
      return attach(ws, targetId);
    }
    case 'navigate': {
      const url = new URL(m.url);
      if (!['http:', 'https:', 'about:'].includes(url.protocol)) throw new Error('Use an http or https URL');
      const result = await call('Page.navigate', { url: url.href }, session);
      if (result.errorText) throw new Error(result.errorText);
      return;
    }
    case 'reload': return call('Page.reload', {}, session);
    case 'back': case 'forward': {
      const h = await call('Page.getNavigationHistory', {}, session);
      const entry = h.entries[h.currentIndex + (m.type === 'back' ? -1 : 1)];
      if (entry) await call('Page.navigateToHistoryEntry', { entryId: entry.id }, session);
      return;
    }
    case 'ack':
      if (m.session === session) return call('Page.screencastFrameAck', { sessionId: m.sessionId }, session);
      return;
    case 'mouse': return call('Input.dispatchMouseEvent', m.params, session);
    case 'key': return call('Input.dispatchKeyEvent', m.params, session);
    case 'text': return call('Input.insertText', { text: m.text }, session);
    case 'dialog': return call('Page.handleJavaScriptDialog', { accept: !!m.accept, promptText: m.text || '' }, session);
    default: throw new Error('Unknown command');
  }
}
function authorized(value) {
  const a = Buffer.from(value || ''); const b = Buffer.from(token);
  return a.length === b.length && timingSafeEqual(a, b);
}
const server = Bun.serve({
  hostname: '127.0.0.1', port,
  fetch(req, server) {
    const url = new URL(req.url);
    if (!['127.0.0.1', 'localhost'].includes(url.hostname)) return new Response('Forbidden', { status: 403 });
    if (url.pathname === '/health') return new Response('ok');
    if (url.pathname === '/ws') {
      if (req.headers.get('origin') !== url.origin || !authorized(url.searchParams.get('token')))
        return new Response('Forbidden', { status: 403 });
      if (viewers.size) return new Response('Viewer already connected', { status: 409 });
      if (server.upgrade(req, { data: { session: null, queue: Promise.resolve() } })) return;
      return new Response('Upgrade required', { status: 426 });
    }
    const file = { '/': 'index.html', '/viewer.js': 'viewer.js', '/style.css': 'style.css' }[url.pathname];
    if (!file) return new Response('Not found', { status: 404 });
    return new Response(Bun.file(new URL(file, import.meta.url)), { headers: {
      'Cache-Control': 'no-store', 'Referrer-Policy': 'no-referrer',
      'Content-Security-Policy': "default-src 'self'; img-src 'self' blob: data:; connect-src 'self'; frame-ancestors 'none'",
    } });
  },
  websocket: {
    maxPayloadLength: 1024 * 1024,
    async open(ws) {
      viewers.add(ws);
      ws.data.queue = (async () => {
        const { targetInfos } = await call('Target.getTargets');
        let target = targetInfos.find(t => t.type === 'page' && /^https?:/.test(t.url))
          || targetInfos.find(t => t.type === 'page');
        if (!target) target = await call('Target.createTarget', { url: 'about:blank' });
        await attach(ws, target.targetId);
      })().catch(e => send(ws, { type: 'error', message: e.message }));
    },
    message(ws, data) {
      // Preserve ordering of mouse/key events and tab attachment.
      ws.data.queue = ws.data.queue.then(() => command(ws, JSON.parse(data)))
        .catch(e => send(ws, { type: 'error', message: e.message }));
    },
    close(ws) {
      viewers.delete(ws);
      ws.data.queue.finally(async () => {
        if (ws.data.session) {
          await call('Page.stopScreencast', {}, ws.data.session).catch(() => {});
          await call('Target.detachFromTarget', { sessionId: ws.data.session }).catch(() => {});
        }
      });
    },
  },
});
console.log(`Chrome viewer listening on 127.0.0.1:${server.port}`);
