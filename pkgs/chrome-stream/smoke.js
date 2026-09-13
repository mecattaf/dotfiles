// Integration test: two real Chrome processes, one viewing the other's pixels.
// Run: bun smoke.js (google-chrome-stable, python3 and bun must be in PATH).
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import assert from 'node:assert/strict';

const root = mkdtempSync(join(tmpdir(), 'chrome-stream-test-'));
const processes = [], sockets = [];
async function until(fn) {
  for (let i = 0; i < 150; i++) {
    try { const result = await fn(); if (result) return result; } catch {}
    await Bun.sleep(100);
  }
  throw new Error('Timed out waiting for test condition');
}
async function connection(udd) {
  const port = await until(() => Number(readFileSync(join(udd, 'DevToolsActivePort'), 'utf8').split('\n')[0]));
  const version = await (await fetch(`http://127.0.0.1:${port}/json/version`)).json();
  const socket = new WebSocket(version.webSocketDebuggerUrl);
  sockets.push(socket);
  await new Promise((resolve, reject) => { socket.onopen = resolve; socket.onerror = reject; });
  let id = 0;
  const waiting = new Map();
  socket.onmessage = e => {
    const m = JSON.parse(e.data), p = waiting.get(m.id);
    if (p) { waiting.delete(m.id); m.error ? p.reject(Error(m.error.message)) : p.resolve(m.result); }
  };
  return (method, params = {}, sessionId) => new Promise((resolve, reject) => {
    waiting.set(++id, { resolve, reject });
    socket.send(JSON.stringify({ id, method, params, sessionId }));
  });
}
const fixture = Bun.serve({ hostname: '127.0.0.1', port: 0, fetch() {
  return new Response('<!doctype html><title>Input fixture</title><style>body{margin:0;height:2400px}input{position:absolute;left:40px;top:40px;width:300px;height:40px}button{position:absolute;left:40px;top:120px;width:300px;height:40px}</style><input id="text"><button onclick="this.textContent=\'Clicked\'">Click me</button>', { headers: { 'Content-Type': 'text/html' } });
} });
try {
  const source = join(root, 'source'); mkdirSync(join(source, 'Default'), { recursive: true });
  writeFileSync(join(source, 'Local State'), '{}');
  // Reserve a free port, then release it immediately before launching.
  const reservation = Bun.serve({ hostname: '127.0.0.1', port: 0, fetch: () => new Response('') });
  const viewerPort = reservation.port; reservation.stop(true);
  processes.push(Bun.spawn(['python3', join(import.meta.dir, 'launch.py'), '--source', source, '--state', join(root, 'remote'), '--port', String(viewerPort), '--url', `http://127.0.0.1:${fixture.port}`], { stdout: 'ignore', stderr: 'inherit' }));
  const link = await until(() => readFileSync(join(root, 'remote', 'viewer-url'), 'utf8').trim());
  const origin = `http://127.0.0.1:${viewerPort}`;
  assert.equal((await fetch(origin + '/ws?token=wrong', { headers: { Origin: origin } })).status, 403);
  assert.equal((await fetch(origin + '/ws?token=' + new URL(link).hash.slice(1), { headers: { Origin: 'http://evil.example' } })).status, 403);
  processes.push(Bun.spawn(['google-chrome-stable', '--headless=new', '--remote-debugging-port=0', `--user-data-dir=${root}/local`, '--no-first-run', '--window-size=1440,1100', 'about:blank'], { stdout: 'ignore', stderr: 'ignore' }));
  const local = await connection(join(root, 'local'));
  const remote = await connection(join(root, 'remote', 'chrome'));
  async function page(cdp) {
    const { targetInfos } = await cdp('Target.getTargets');
    return (await cdp('Target.attachToTarget', { targetId: targetInfos.find(t => t.type === 'page').targetId, flatten: true })).sessionId;
  }
  const localSession = await page(local), remoteSession = await page(remote);
  const evaluate = async (cdp, session, expression) => (await cdp('Runtime.evaluate', { expression, returnByValue: true }, session)).result.value;
  const here = expression => evaluate(local, localSession, expression);
  const there = expression => evaluate(remote, remoteSession, expression);
  await local('Page.navigate', { url: link }, localSession);
  await until(() => here("document.querySelector('#status')?.textContent.startsWith('Connected')"));
  await until(() => here("document.querySelector('#screen').getContext('2d').getImageData(0,0,1,1).data[3] === 255"));
  const bounds = await here("JSON.stringify(document.querySelector('#screen').getBoundingClientRect().toJSON())");
  const r = JSON.parse(bounds);
  const click = async (x, y) => {
    const position = { x: r.x + x * r.width / 1440, y: r.y + y * r.height / 900, button: 'left', clickCount: 1 };
    await local('Input.dispatchMouseEvent', { type: 'mousePressed', ...position }, localSession);
    await local('Input.dispatchMouseEvent', { type: 'mouseReleased', ...position }, localSession);
  };
  await click(100, 60);
  for (const char of 'Hello') {
    await local('Input.dispatchKeyEvent', { type: 'keyDown', key: char, text: char, windowsVirtualKeyCode: char.toUpperCase().charCodeAt(0) }, localSession);
    await local('Input.dispatchKeyEvent', { type: 'keyUp', key: char }, localSession);
  }
  await until(async () => await there("document.querySelector('input').value") === 'Hello');
  await click(100, 140);
  await until(async () => await there("document.querySelector('button').textContent") === 'Clicked');
  await local('Input.dispatchMouseEvent', { type: 'mouseWheel', x: r.x + 400, y: r.y + 400, deltaX: 0, deltaY: 500 }, localSession);
  await until(async () => await there('scrollY') > 0);
  await here("document.querySelector('#new').click()");
  await until(async () => (await remote('Target.getTargets')).targetInfos.filter(t => t.type === 'page').length === 2);
  const reserveAttach = Bun.serve({ hostname: '127.0.0.1', port: 0, fetch: () => new Response('') });
  const attachPort = reserveAttach.port; reserveAttach.stop(true);
  const attached = Bun.spawn(['python3', join(import.meta.dir, 'launch.py'), '--attach', join(root, 'remote', 'chrome'), '--state', join(root, 'attached'), '--port', String(attachPort)], { stdout: 'ignore', stderr: 'inherit' });
  processes.push(attached);
  await until(() => readFileSync(join(root, 'attached', 'viewer-url'), 'utf8').trim());
  attached.kill('SIGTERM'); await attached.exited;
  assert.ok((await remote('Browser.getVersion')).product.includes('Chrome'));
  processes.pop();
  console.log('PASS: authenticated viewer, origin rejection, decoded frames, mouse, typing, scrolling, new tabs, and attach/detach leaves Chrome running');
} finally {
  for (const socket of sockets) socket.close();
  for (const p of processes.reverse()) { p.kill('SIGTERM'); await p.exited; }
  fixture.stop(true);
  rmSync(root, { recursive: true, force: true });
}
