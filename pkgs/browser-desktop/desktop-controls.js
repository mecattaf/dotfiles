// Small takeover control added to stock noVNC. Its rendering and input stay upstream.
import UI from './app/ui.js';
window.faraRfb = () => UI.rfb;
UI.updateDesktopName = (event) => {
    UI.desktopName = event.detail.name;
    document.title = 'Browser desktop';
};
if (!new URLSearchParams(location.search).has('agent')) {
    // Fail closed on first connect/reconnect and when control status is unavailable.
    // Route the stock setting through the same ownership decision, including its
    // keyboard/clipboard controls, so it cannot accidentally end spectator mode.
    let viewOnly = true;
    const originalViewOnly = UI.updateViewOnly.bind(UI);
    UI.updateViewOnly = () => {
        UI.forceSetting('view_only', viewOnly);
        originalViewOnly();
    };
    const controls = document.createElement('div');
    controls.style.cssText = 'position:fixed;right:12px;top:12px;z-index:10000;display:flex;align-items:center;gap:8px;background:#313131;color:white;padding:8px 12px;font:14px sans-serif';
    const label = document.createElement('span');
    label.id = 'desktop-ownership'; label.textContent = 'Connecting…';
    const button = document.createElement('button'); button.id = 'desktop-take-control';
    button.textContent = 'Take control'; button.disabled = true;
    button.title = 'Pause FARA and disconnect its input before using the desktop';
    controls.append(label, button); document.body.append(controls);
    button.onclick = async () => {
        button.disabled = true;
        label.textContent = 'Stopping FARA…';
        try {
            const r = await fetch('/control/pause', {method:'POST', headers:{'X-Fara-Control':'1'}});
            if (!r.ok) throw Error('Unable to confirm');
            await update();
        } catch { label.textContent = 'Ask your agent to stop FARA'; }
    };
    async function update() {
        try {
            const response = await fetch('/control/state', {cache:'no-store'});
            if (!response.ok) throw Error('Control state unavailable');
            const state = await response.json();
            const human = state.owner === 'human' && state.phase !== 'pausing';
            viewOnly = !human;
            UI.updateViewOnly();
            const profile = state.profile_at_start;
            const identity = profile ? ` · ${profile.name} (${profile.directory}) · ${profile.google_account || 'No Google account recorded'}` : '';
            label.textContent = state.phase === 'pausing' ? 'Stopping FARA…' : human ? 'You have control' : `Spectating · ${state.task_id}${identity}`;
            button.hidden = human; button.disabled = human || state.phase === 'pausing';
        } catch {
            viewOnly = true; UI.updateViewOnly();
            label.textContent = 'Spectating · control status unavailable';
            button.hidden = false; button.disabled = true;
        }
    }
    setInterval(update, 750);
    update();
}

// Reuse noVNC's existing toolbar and panel styling.
if (!new URLSearchParams(location.search).has('agent')) {
    const bar = document.querySelector('#noVNC_control_bar .noVNC_scroll');
    const chrome = document.createElement('input');
    chrome.type = 'image'; chrome.src = './chrome.png'; chrome.alt = 'Chrome';
    chrome.title = 'Open a Google Chrome window'; chrome.id = 'chrome-menu-button';
    chrome.className = 'noVNC_button'; chrome.setAttribute('aria-expanded', 'false');
    const wrapper = document.createElement('div'); wrapper.className = 'noVNC_vcenter';
    const panel = document.createElement('div'); panel.className = 'noVNC_panel';
    panel.id = 'chrome-menu';
    panel.style.cssText = 'width:min(360px,calc(100vw - 80px));box-sizing:border-box';
    panel.innerHTML = `<div class="noVNC_heading">Google Chrome</div>
        <p><label for="chrome-profile">Profile and Google account</label></p>
        <select id="chrome-profile" style="width:100%"><option value="">Choose a profile…</option></select>
        <p><button id="chrome-open" disabled>Open window</button>
        <button id="chrome-unlock" hidden>Unlock keyring</button></p>
        <p id="chrome-status" role="status" style="white-space:normal;overflow-wrap:anywhere;margin-bottom:0"></p>`;
    wrapper.append(panel);
    bar.querySelector('hr').after(chrome, wrapper);
    const select = panel.querySelector('select');
    const open = panel.querySelector('#chrome-open');
    const unlock = panel.querySelector('#chrome-unlock');
    const status = panel.querySelector('#chrome-status');
    let snapshot = null, pending = false, stateMessage = false;
    function buttons() {
        open.disabled = pending || !snapshot || snapshot.busy || snapshot.keyring !== 'unlocked' || !select.value;
        unlock.hidden = snapshot?.keyring !== 'locked';
        unlock.disabled = pending || snapshot?.busy;
    }
    async function refresh() {
        try {
            const r = await fetch('/desktop/profiles', {cache:'no-store'});
            if (!r.ok) throw Error('Chrome menu is unavailable. Try again shortly.');
            snapshot = await r.json();
            const selected = select.value;
            select.replaceChildren(new Option('Choose a profile…', ''));
            for (const p of snapshot.profiles.filter(p=>p.exists)) {
                select.add(new Option(`${p.name} · ${p.google_account || 'No Google account recorded'} · ${p.directory}`, p.directory));
            }
            select.value = selected;
            if (stateMessage) status.textContent = '';
            stateMessage = snapshot.unlocking || snapshot.busy || snapshot.keyring !== 'unlocked';
            if (snapshot.unlocking) status.textContent = 'Enter the keyring password in the desktop dialog.';
            else if (snapshot.busy) status.textContent = 'Finish or cancel the current FARA task before opening another window.';
            else if (snapshot.keyring === 'locked') status.textContent = 'Unlock the desktop keyring once before opening Chrome.';
            else if (snapshot.keyring !== 'unlocked') status.textContent = 'The desktop keyring is unavailable.';
        } catch (error) { snapshot = null; status.textContent = error.message; }
        buttons();
    }
    const originalClose = UI.closeAllPanels.bind(UI);
    UI.closeAllPanels = () => {
        originalClose(); panel.classList.remove('noVNC_open');
        chrome.classList.remove('noVNC_selected'); chrome.setAttribute('aria-expanded', 'false');
    };
    chrome.onclick = () => {
        const wasOpen = panel.classList.contains('noVNC_open');
        UI.closeAllPanels();
        if (!wasOpen) {
            UI.openControlbar(); panel.classList.add('noVNC_open');
            chrome.classList.add('noVNC_selected'); chrome.setAttribute('aria-expanded', 'true');
            status.textContent = ''; refresh();
        }
    };
    select.onchange = buttons;
    async function submit(action) {
        pending = true; buttons();
        stateMessage = false;
        status.textContent = action === 'open' ? 'Opening Chrome…' : 'Requesting keyring unlock…';
        try {
            const response = await fetch('/desktop/' + action, {method:'POST',
                headers:{'Content-Type':'application/json','X-Fara-Control':'1'},
                body:JSON.stringify({profile:select.value})});
            const result = await response.json();
            if (!response.ok) throw Error(result.error || 'The request could not be completed.');
            status.textContent = action === 'open' ? `Opened ${result.profile.name} (${result.profile.directory}).` : 'Enter the keyring password in the desktop dialog.';
        } catch (error) { status.textContent = error.message; }
        finally { pending = false; await refresh(); }
    }
    open.onclick = () => submit('open'); unlock.onclick = () => submit('unlock');
    setInterval(() => { if (panel.classList.contains('noVNC_open') && !pending) refresh(); }, 3000);
}
