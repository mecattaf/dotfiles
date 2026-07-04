this project called howcoe has lots of cool functionality. they have for instance a bespoke frontend that demonstrates how the best products already use pi sdk. see the series of tweets:

```
https://x.com/Howaboua/status/2064780144686805457
```

I did say Howcode 0.1.67 will be special. What I did not expect is Mario dropping an update to the SDK enabling extensions to be rendered in GUI apps.

- Added native Smart BTW extension, and subsequently removed it, because...
- Howcode now uses new Pi SDK to render dialogs, widgets, statuslines and notifications. (see https://x.com/Howaboua/status/2064713302878363692?s=20 for a video demo)
- Extensions pass through shortcuts.
- Fancy react-rendered extensions not supported yet. Only normal-ish widgets.
- /tree - also 2x esc when agent is idle.
- Split Pi TUI takeover and the terminal drawer properly.
- Shortcut handling improved when Pi TUI is on.
- Resolved an annoying bug that didn't allow typing into Pi TUI.
- Added Pi project trust prompts in desktop, backed by Pi's trust store.
- Updated Pi SDK/runtime packages to 0.79.1.
- Bumped app/build dependencies

For now, on bunx howcode@dev

Also coming to stable .67, hopefully:

- bugfixes, send me some. I have a couple I need to sort out.
- WSL, I have a PR opened for it, so hopefully a nice merge.
- ability to just open it in your browser. Right now it's bound to localhost... 
- hopefully, ability to run headless and use the browser to operate it.

Don't think I need to tell you what this will enable.

Happy Clanking!
