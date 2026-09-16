// Session start and a Chrome menu added to stock noVNC. Its rendering and input stay upstream.
import UI from './app/ui.js';
UI.updateDesktopName = (event) => {
    UI.desktopName = event.detail.name;
    document.title = 'Browser desktop';
};
{
    // Only initial entry or an explicit Connect starts a manual session.
    // Transport reconnects after End session must not restart the desktop.
    let mayStartDesktop = true;
    const connect = UI.connect.bind(UI);
    UI.connect = async (...args) => {
        try {
            const response = await fetch('/desktop/profiles', {cache:'no-store'});
            if (!response.ok) throw Error('Desktop status unavailable');
            const state = await response.json();
            if (!state.desktop_running) {
                if (!mayStartDesktop) {
                    UI.cancelReconnect();
                    UI.showStatus('Session ended. Choose Start desktop to begin again.', 'normal');
                    UI.openControlbar(); return;
                }
                const start = await fetch('/desktop/start', {method:'POST', headers:{'X-Desktop-Control':'1'}});
                if (!start.ok) throw Error('Unable to start desktop');
            }
            mayStartDesktop = false;
            connect(...args);
        } catch (error) { UI.showStatus(error.message, 'error'); }
    };
    const connectButton = document.getElementById('noVNC_connect_button');
    if (connectButton.tagName === 'INPUT') connectButton.value = 'Start desktop';
    else connectButton.textContent = 'Start desktop';
    connectButton.addEventListener('click', () => { mayStartDesktop = true; }, {capture:true});
}

// Reuse noVNC's existing toolbar and panel styling.
{
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
        <p><button id="desktop-end">End session</button></p>
        <p style="white-space:normal">Closes five minutes after the last viewer disconnects.</p>
        <p id="chrome-status" role="status" style="white-space:normal;overflow-wrap:anywhere;margin-bottom:0"></p>`;
    wrapper.append(panel);
    bar.querySelector('hr').after(chrome, wrapper);
    const select = panel.querySelector('select');
    const open = panel.querySelector('#chrome-open');
    const unlock = panel.querySelector('#chrome-unlock');
    const end = panel.querySelector('#desktop-end');
    const status = panel.querySelector('#chrome-status');
    let snapshot = null, pending = false, stateMessage = false;
    function buttons() {
        open.disabled = pending || !snapshot || snapshot.busy || snapshot.keyring !== 'unlocked' || !select.value;
        unlock.hidden = snapshot?.keyring !== 'locked';
        unlock.disabled = pending || snapshot?.busy;
        end.disabled = pending || !snapshot?.desktop_running || snapshot?.busy;
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
            else if (snapshot.busy) status.textContent = 'Another desktop action is in progress.';
            else if (snapshot.keyring === 'locked') status.textContent = 'Unlock the desktop keyring once before opening Chrome.';
            else if (snapshot.keyring !== 'unlocked') status.textContent = 'The coordinator’s keyring cannot be reached. Its desktop session needs repair before Chrome can open.';
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
        status.textContent = action === 'end' ? 'Closing session…' : action === 'open' ? 'Opening Chrome…' : 'Requesting keyring unlock…';
        try {
            const response = await fetch('/desktop/' + action, {method:'POST',
                headers:{'Content-Type':'application/json','X-Desktop-Control':'1'},
                body:JSON.stringify({profile:select.value})});
            const result = await response.json();
            if (!response.ok) throw Error(result.error || 'The request could not be completed.');
            if (action === 'end') {
                UI.inhibitReconnect = true;
                if (UI.rfb) UI.disconnect();
                UI.cancelReconnect();
            }
            else if (!UI.connected) UI.connect();
            status.textContent = action === 'end' ? 'Session ended.' : action === 'open' ? `Opened ${result.profile.name} (${result.profile.directory}).` : 'Enter the keyring password in the desktop dialog.';
        } catch (error) { status.textContent = error.message; }
        finally { pending = false; await refresh(); }
    }
    end.onclick = () => submit('end');
    open.onclick = () => submit('open'); unlock.onclick = () => submit('unlock');
    setInterval(() => { if (panel.classList.contains('noVNC_open') && !pending) refresh(); }, 3000);
}
