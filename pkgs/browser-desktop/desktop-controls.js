// Small takeover control added to stock noVNC. Its rendering and input stay upstream.
import UI from './app/ui.js';
window.faraRfb = () => UI.rfb;
if (!new URLSearchParams(location.search).has('agent')) {
    const button = document.createElement('button');
    button.textContent = 'Take control';
    button.title = 'Pause FARA and disconnect its input before using the desktop';
    button.style.cssText = 'position:fixed;right:12px;top:12px;z-index:10000;padding:8px 12px;cursor:pointer';
    document.body.append(button);
    button.onclick = async () => {
        button.textContent = 'Stopping FARA…';
        try {
            const r = await fetch('/control/pause', {method:'POST', headers:{'X-Fara-Control':'1'}});
            if (!r.ok) throw Error('Unable to confirm');
        } catch { button.textContent = 'Ask your agent to stop FARA'; }
    };
    async function update() {
        try {
            const response = await fetch('/control/state', {cache:'no-store'});
            const state = response.ok ? await response.json() : {owner:'human'};
            const human = state.owner === 'human' && state.phase !== 'pausing';
            if (UI.rfb) UI.rfb.viewOnly = !human;
            button.textContent = state.phase === 'pausing' ? 'Stopping FARA…' : human ? 'You have control' : `Take control · ${state.task_id}`;
            button.disabled = human || state.phase === 'pausing';
        } catch { if(UI.rfb) UI.rfb.viewOnly = true; }
    }
    setInterval(update, 750);
    update();
}
