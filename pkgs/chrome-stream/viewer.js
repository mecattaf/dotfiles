const $ = id => document.getElementById(id);
const canvas = $('screen');
const context = canvas.getContext('2d');
const token = location.hash.slice(1) || sessionStorage.getItem('chrome-stream-token');
if (token) sessionStorage.setItem('chrome-stream-token', token);
history.replaceState(null, '', '/');
let ws, active;
const status = text => { $('status').textContent = text; };
function send(value) { if (ws?.readyState === WebSocket.OPEN) ws.send(JSON.stringify(value)); }
function connect() {
  if (!token) return status('Open the viewer link from the coordinator to connect.');
  if (ws && ws.readyState < 2) ws.close();
  ws = new WebSocket(`ws://${location.host}/ws?token=${encodeURIComponent(token)}`);
  ws.onopen = () => status('Connected · Click the page to type · Paste with Ctrl+V');
  ws.onclose = () => status('Disconnected. Use Reconnect; only one viewer can control Chrome at a time.');
  ws.onerror = () => status('Connection failed. Check the SSH tunnel and viewer link.');
  ws.onmessage = async ({ data }) => {
    const m = JSON.parse(data);
    if (m.type === 'frame') {
      try {
        const picture = new Image();
        picture.src = 'data:image/jpeg;base64,' + m.data;
        await picture.decode();
        canvas.width = picture.naturalWidth; canvas.height = picture.naturalHeight;
        context.drawImage(picture, 0, 0);
      } finally { send({ type: 'ack', sessionId: m.sessionId, session: m.session }); }
    } else if (m.type === 'active') active = m.targetId;
    else if (m.type === 'tabs') {
      $('tabs').replaceChildren(...m.tabs.map(t => new Option(t.title || t.url, t.targetId, false, t.targetId === active)));
      const tab = m.tabs.find(t => t.targetId === active);
      if (tab && document.activeElement !== $('address')) $('address').value = tab.url;
    } else if (m.type === 'error') status(m.message);
    else if (m.type === 'dialog') {
      let accept = true, text = '';
      if (m.dialogType === 'alert') alert(m.message);
      else if (m.dialogType === 'prompt') {
        text = prompt(m.message, m.defaultPrompt); accept = text !== null;
      } else accept = confirm(m.message);
      send({ type: 'dialog', accept, text });
    }
  };
}
$('reconnect').onclick = connect;
for (const type of ['back', 'forward', 'reload', 'new']) $(type).onclick = () => send({ type });
$('tabs').onchange = () => send({ type: 'attach', targetId: $('tabs').value });
$('navigation').onsubmit = e => {
  e.preventDefault(); let url = $('address').value.trim();
  if (!/^[a-z]+:/i.test(url)) url = 'https://' + url;
  send({ type: 'navigate', url }); canvas.focus();
};
function modifiers(e) { return (e.altKey ? 1 : 0) | (e.ctrlKey ? 2 : 0) | (e.metaKey ? 4 : 0) | (e.shiftKey ? 8 : 0); }
function position(e) {
  const r = canvas.getBoundingClientRect();
  return { x: (e.clientX - r.left) * 1440 / r.width, y: (e.clientY - r.top) * 900 / r.height };
}
const button = e => ['left', 'middle', 'right'][e.button] || 'none';
for (const [event, type] of [['pointerdown', 'mousePressed'], ['pointerup', 'mouseReleased'], ['pointermove', 'mouseMoved']]) {
  canvas.addEventListener(event, e => {
    if (event === 'pointerdown') { canvas.focus(); canvas.setPointerCapture(e.pointerId); }
    e.preventDefault();
    send({ type: 'mouse', params: { type, ...position(e), button: event === 'pointermove' && !e.buttons ? 'none' : button(e), buttons: e.buttons, clickCount: type === 'mouseMoved' ? 0 : e.detail || 1, modifiers: modifiers(e) } });
  });
}
canvas.oncontextmenu = e => e.preventDefault();
canvas.addEventListener('wheel', e => {
  e.preventDefault(); const scale = e.deltaMode === 1 ? 16 : e.deltaMode === 2 ? 900 : 1;
  send({ type: 'mouse', params: { type: 'mouseWheel', ...position(e), deltaX: e.deltaX * scale, deltaY: e.deltaY * scale, modifiers: modifiers(e) } });
}, { passive: false });
for (const event of ['keydown', 'keyup']) canvas.addEventListener(event, e => {
  if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'v') return;
  e.preventDefault();
  const text = event === 'keydown' && !e.ctrlKey && !e.metaKey && !e.altKey ? (e.key.length === 1 ? e.key : e.key === 'Enter' ? '\r' : '') : '';
  send({ type: 'key', params: { type: event === 'keyup' ? 'keyUp' : text ? 'keyDown' : 'rawKeyDown', key: e.key, code: e.code, windowsVirtualKeyCode: e.keyCode, nativeVirtualKeyCode: e.keyCode, modifiers: modifiers(e), text, unmodifiedText: text, autoRepeat: e.repeat } });
});
canvas.addEventListener('paste', e => { e.preventDefault(); send({ type: 'text', text: e.clipboardData.getData('text/plain') }); });
setInterval(() => send({ type: 'tabs' }), 2000);
connect();
