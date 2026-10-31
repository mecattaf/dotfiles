# BOUNDARY — the personal Sway shell versus the shared utilities

Synthesis for the overnight gpuix-shell build (2026-10-20/21), revision 2 (written after every
wave-1 note, 01–30 and 35–36, was read in full; revision 1 of 23:57 predated the revised notes
15, 18, 19, 21, 23, 24, 26 and the Vicinae notes 35/36). It restates, for this build, the line
between what lives in Tom's private dotfiles as the personal Sway shell and what belongs to the
agency-agency shared utilities (mail, CRM, projects, chat, files) and their three heads (web, macOS
native, Wayland native). Sources are the wave-1 reader notes, cited as `[w1-NN §x]`; the primary
ones are w1-12 (boundary and packets), w1-04 (October 14 transcript, part a), w1-08 (October 20
transcripts) and w1-07 (October 17–20 desktop-ui notes). Sibling syntheses are cited as `SCOPE
S-nnn`, `DESIGN A-nn`, `KEYS`. Tom's words are verbatim, typos kept. **INFERRED** marks a line
where no note or ruling settles the point and I chose; each such choice is also logged as one
`- BOUNDARY:` line in `ASSUMPTIONS.md`. Nothing here asks Tom anything. §8 lists what this pass left
unverified.

---

## 0. The boundary in one paragraph, and the one-line test

The personal shell is everything that only makes sense because a Wayland compositor is underneath
it: layer-shell surfaces (rail, launcher, switcher, notifications, OSD, controls, power, the `ask`
prompt) and the one ordinary toplevel it owns (the files explorer); the Sway IPC and herdr readers
that feed them; the D-Bus server and client roles (notification server, UPower, logind,
NetworkManager, BlueZ, MPRIS, PipeWire); the `shell.sock` CLI door; the systemd user units; the Nix
module; and Tom's composition (keybinds, outputs, hostnames, slot policy, fonts, palettes). It lives
in `pkgs/gpuix-shell/` and `home/gpuix-shell.nix` in Tom's private dotfiles and ships nowhere else
[w1-12 §3.2, §7; w1-21 §1]. The shared utilities are "applications of a spec": mail, CRM, projects,
chat (herdr-web-ui), files-as-app and "the vesence ones". They are built in the agency-agency GitHub
org, deployed on Cloudflare Workers for the web head, packaged with `npx @agency-agency/kit` for the
macOS head, and reached from the shell only by launching them, by reading their receipts, or by
hosting the OpenUI programs they emit through the adapter [w1-12 §2.1, w1-06 §A, w1-08 §2].

The founding split is the A/B/C of `UB/inputs/SEPARATION.md`: **A** = Tom's Sway-only shell (never
ported), **B** = desktop apps ported to the Mac by npx, **C** = Cloudflare deployments plus the
single MCP codemode door. "A stays home, B travels by npx, C is a manual runbook" (SEPARATION.md:21,
quoted in [w1-12 §2.1]). The 15-item "Never on the Mac" list (Sway IPC, rail outside an app window,
launcher/summon key, notification daemon, layer-shell bar, system-level Nix, daemons and listening
sockets, the 4188 bridge, the desk fork, privacy grants, keypress/window capture and clipboard
history, Anthropic font files and Claude-named palettes, tailnet membership, `defaults` writes) is
the mirror of what is personal-shell-only, so all of it is legitimately in gpuix-shell and none of
it may be factored out as shared [w1-12 §3.1].

The one-line test from [w1-08 §2.4], applied to every row of §3 below:

> compositor-bound → Tom's shell (dotfiles); GPU window without a compositor → Marwan's kit;
> browser-only → Frank's web head; otherwise → shared core, deployed per owner.

Three corollaries, from Tom's own rulings (§1) and the Friday/UB documents they produced:

- The division "follows reusable capability versus owner-specific composition. It does not follow
  Linux versus macOS" (FP/GUIDE.md:66-68, quoted in [w1-12 §3.1]). A Linux provider that another
  Sway user could reuse is *platform adaptation*, not personal composition; Tom's output names, slot
  policy, binds and fonts are personal composition. So the package has three layers: `src/core/`
  (platform-neutral, no `child_process`, D-Bus, `swaymsg`, GPUIX or filesystem imports),
  `src/platform/{sway,linux}/` (reusable providers) and `src/surfaces/` (GPUIX React views), with
  Tom's policy in rendered config [w1-12 §7 rule 2].
- "Sharing code/contracts does not mean sharing deployments, data, credentials, compute entitlements
  or personal policy" (FP/BOUNDARIES.md:5, [w1-12 §3.1]). The shell may share a type or a token file
  with a utility; it may not share the utility's mailbox, its Cloudflare account or its Keychain.
- herdr is read-only truth for the shell: it reads `herdr api snapshot` and `events.subscribe` and
  acts only through Sway; it never focuses, spawns, closes or answers herdr work [w1-16 §3–§5,
  w1-12 §7 rule 3, SCOPE S-005].

---

## 1. Tom's rulings that fix this boundary, verbatim

Newest first. "Stands" means it binds tonight; "superseded" names the newer ruling. Only Tom's own
words appear in quotation marks; the bracket after each gives the grounding note and its pointer.
Pointers in parentheses are the transcript ids and line numbers the notes cite.

| # | Date | Verbatim | Status |
|---|---|---|---|
| R1 | 2026-10-20 23:20 (BRIEF §5) | "a full implementation of the linux wayland sway facing https://github.com/vicinaehq/vicinae ... would be impressive to see. gpuix for the win." / "the vicinae implementation is also of interest so make sure to capture that as well" | stands: the Vicinae-parity launcher is a shell surface, its extension grammar is the shell's extension story [w1-35 §2, w1-36 T17] |
| R2 | 2026-10-20 23:20 (BRIEF §5) | "i would like to have a navidrome music selection in the gpuix shell ... raycast+spotify level searching and playing control from within the launcher"; "this is NOT ONLY about navidrome.. but indeed a welcome set of utilities you can demo for me" | stands: launcher-hosted utilities are shell features when they are compositor-side (daemon, MPRIS, credentials); their client types are extractable [w1-36 T18, MUSIC.md] |
| R3 | 2026-10-20 23:20 (BRIEF §1) | "the 'boundary' between personal desktop os shell versus common utilities (webui + macos native + wayland native; say for the email or crm utilities) should already be clear." | stands; this document is the restatement [w1-12 §1, BRIEF §3.8] |
| R4 | 2026-10-20 ~23:05 (BRIEF §1) | "make sure that the work you do will set the foundation for my subsequent work on achieving the world's most complete linux desktop shell without using quickshell. gpuix as the frontend all the way is desired. the rest, including scripts and other functionality, you can use what comes instinctively to you. for wifi menu, or bluetooth pairing menu; etc." | stands: GPUIX is the only frontend of the shell; wifi and bluetooth menus are shell surfaces [w1-23 §2, w1-36 T16] |
| R5 | 2026-10-20 ~22:50 (BRIEF §1) | "the crux of it is that we write scripts and functionality that is either a bespoke swaywm shortcut ; or a mod+d menu (vicinae remplacement) that presents a given functionality. notify-send remplacement to mako ; a left bar with workspace switcher that remplaces waybar" / "there is a lot of herdr-web-ui centricity here especially on the left sidebar idea" | stands: the shell's surface list; the rail descends from herdr-web-ui's leftbar [w1-23 §2, w1-36 T15] |
| R6 | 2026-10-20T14:50/14:53Z (01a15935) | "the only thing we can retain from before is the nautilus file picker (same as what google chrome uses) ; and the clui-ccc behavior (using the \"unified\" components collectin that i have. and it will intergrate with herdr-web-ui the same way." / "it s just the clui-cc reimplementation in gpuix really, with attention to herdr-centrality" | stands: the chat head is a utility; the shell integrates with herdr-web-ui, it does not re-host it; the GTK picker is tolerated, not replaced [w1-09 §2, w1-14 §2] |
| R7 | 2026-10-20T14:12:30Z (01a15935 L3126) | "it is important that fron t end we buikld built from the ground up with openUI methodology AND thezhortcut driven method as well (so that my human clicks on the webUI is the same as an agwent's usage of the api with \"trailing clicks\" happening by another aent thst just shows what is being worked through." | stands: OpenUI plus shortcut-driven is the method for shell and utilities alike [w1-08 §2.5, w1-24 §2] |
| R8 | 2026-10-20T13:47:28Z (01a15935 L2484) | "right. we drew the boundary of things that are my own versus things that we can all use are: the gpuix local shell. and that has been scoped very well previopusly" | stands: the shell is the only thing that is Tom's own [w1-08 §2.4] |
| R9 | 2026-10-20T12:03:43Z (1a517fb2 L751) | "a unified gppuix to linux program ; macos program ; AND browser webapps tjhat work on chromium ALLL IN ONE / openui … as the toolking that grows with us (instead of a prefactirated https://gpui-kit.com/ ) / this is a shared project on the frontend; and building with the same root will be desirtable / for my own personal usahgge, on swaywm, we havwe a saister project that is a gpuix shell that is no-quickshell … this is a SEPARATE project that uses the same kernel and has its learnngs feed into this project / being shortcut-vased … / we have 3+ users (thomass , marwan, frank) at minimum so building a high quality polished product that s repeatable is highly desired)" | stands: the shell is a separate project sharing the kernel; its learnings flow outward [w1-07 §2, w1-08 §2.3, w1-09 §2] |
| R10 | 2026-10-20 (`~/tuesday-oct20/desktop-ui.md`) | "it would make us completely agnostic to building native linux wayland (thomas); macos (marwan); AND web (frank). / the only boundary being of course the desktop shell, which would be exclusive to wayland-on-sway wm. / … the same llm generate all the front-end tooling, starting from my desktop shell all the way to webapps like email etc. / we build it once and it can be exported everywhere." | stands: three heads; the desktop shell is the one exclusive piece [w1-07 §1, w1-08 §2.1, w1-14 §2, w1-24 §2] |
| R11 | 2026-10-20 11:56:43Z | "ffrank's state constraint is: everythig as a webapp. he wants herdr-chat0ui as is on mine; so i need to install it for him on his mac…" | stands: Frank's head is browser-only [w1-07 §2] |
| R12 | 2026-10-20T10:53:53Z (MAP.md:99) | "i typically hae a one ot one mapping, with a limit of 9 open workspaces at a time; this helps with my mental overload" | stands: the nine-slot policy is personal composition, never a shared default [w1-23 §2, w1-19 §3] |
| R13 | 2026-10-17 01:12:51Z (T-31) | "this is my own local gpuix shell; for linux... but stylistiacally it s exactly the same as what is used for the frontend (gpuix whatever js - react or other - you end up using) ; for all users. email crm etc all the shebang." | stands: one style, two ownerships [w1-09 §2, w1-11 §2] |
| R14 | 2026-10-17T00:45:54Z | "we build for all : gpuix as the key and the code that it uses / … the email and crm etc are nothing more than \"applications of a spec\"" | stands: utilities are applications of a spec, not shell features [w1-08 §2.2] |
| R15 | 2026-10-17 00:23:29Z | "the design kit … deliberately omits things like the font (to be configured) becasue i like the anthropic-derived one but dnt want to share it on the interned.. these are locally deployed personal tools" | stands: fonts are personal composition; the kit carries a slot, not the files [w1-09 §2, w1-12 §5] |
| R16 | 2026-10-17 00:10:56Z (T-40) | "on the sway devices, the left bar of the ai chat is a waybar style workspace (1>9) launcher ; and there is the macos implementation" | stands: the rail is the Sway head of herdr-web-ui's leftbar; the macOS kit has its own [w1-09 §2, w1-19 §3, w1-25 §2] |
| R17 | 2026-10-16T08:12:14Z (T-38) | "we have a very clear separation of concerns being gpuix-specialized entire wayland shell and programs (email, crm, etc \"a la Vesence\") that are alos macos specific; all on the github+cloudflare+ai harness model. herdr-centril all the way, how hersr-web-ui is decomposed eg the leftbar becomes sway compatible. the nuance is that gpuix-shell is for ME and the substrate actual tooling is exported to macos native etc. by design. subagents must deliberte ont hius line (what goes in poersonal nixos dotfiles fleet vs external tooling that goes in agency gh org ; i already did that wiht email and crm i think)" | stands: the line is dotfiles fleet versus agency org; email and CRM already drawn [w1-08 §2.0, w1-09 §2] |
| R18 | 2026-10-16 (relay) | "please make sure to kee defining the xact boundary between personal shell versus 'shareable' for macos and others with a unified system" | stands [w1-12 §1] |
| R19 | 2026-10-14T20:52:34Z (L2913) | "it s important to separate out my swaywm-only deskto shell versus the desktop appoications like email ; herdr web ui chat ; crm and the other ones created. plus the cloudflare-side deployments ofthe agency-agency repos that need manual work and integrations on [the first user]'s account" | stands: the A/B/C split [w1-06 §A, w1-12 §2.1] |
| R20 | 2026-10-14T16:10:24Z (L1888) | "without invading into his macos desktop. this is where the diffreece lies. i give him high performance cloduflare deployed webappsthat he can use with codemode from the chat interface as well." | stands: the macOS head never carries a shell; Frank gets Workers [w1-06 §A, w1-12 §2.1] |
| R21 | 2026-10-14T16:08:40Z (56e498e4 L1861) | "agency-agency is the shared github org. it has separate implementations for pure full desktop like wayland (sway for now) desktop shell and the shared with macos that overlays / special features of sway: swap kitty terminla herdr and herdr web ui translated into my own implementation. sway has a contextual launcher, a herdr leftbar that is disjinted and contol sway workspaces, clipboard history.. all that stuff that macos version doesn't have. this creates a clean sepaeation layer which is much appreciated but it sits at the same library fundamentally." … "macos has parity with the \"tray/dock\" items: crm, email, projects, files, the vesence ones (resurface from investigation); this is what we build as native apps. there is the massive backdrop that has the cloudflrae." | stands: the founding ruling; "same library fundamentally", "tray/dock items" are the utilities [w1-05 §2, w1-06 §A, w1-12 §2.1, w1-35 §2] |
| R22 | 2026-10-14T14:53:35Z (5024ed4c L216) | "this is us packaging for that withtou the window mgmt functionlaity. this is building in unified email crm and other such tools ." | stands: the kit is the utilities minus window management [w1-12 §2.1] |
| R23 | 2026-10-14 ~01:26Z (`2026-10-14-computer-use-study/BRIEF.md:43`) | "for the launcher, feature parity at least with vicinae (already enjoyed on my setup) including how it interacts w google chrome tabs is very desirable" | stands: the Chrome-tab bridge is a shell (platform adapter) component, not a utility feature [w1-36 T14, w1-35 §2] |
| R24 | 2026-10-14 (`~/wednesday-oct14-midday.md:325,329`) | "the bottom macos tab bar: utilities like email etc can go below. herdr tabs on the left with sway and herdr control ;" / "it's utilities and skills and things that get a shortcut to that. the idea is that we \"puppetteer\" the desktiop interface without consuming lots of effort from the claude controlling llm. the desktop interfaces are sortcut driven." | stands: utilities are shortcut targets; herdr tabs plus Sway control are the shell's [w1-04 §2, w1-05 §2] |
| R25 | 2026-10-14 (T-32) | "the crown jewel is obviously the chat interface, beyond clui-cc and into something that is more comprehensive." | stands: the chat interface is a utility head, the most important one; the shell does not absorb it [w1-09 §2, w1-12 §2.1] |
| R26 | 2026-10-13 23:21Z (Codex rollout L3453) | "i m not intersted in \"native advantage\" . performance is not really the thing i m looking for here. \"supplies another renderer\" is fine for something that' react plus generic compositor functionlaity... vicinae (raycast clone) proves this theoretically ; we hae the sway ipc and omarchy's quickshell which you investigated a while back did exactly that." | stands: the shell is React plus generic compositor functionality on GPUIX; nothing Rust is ported [w1-36 T13, w1-23 §2] |
| R27 | 2026-10-13 23:19Z (MAP.md:95) | "gpuix is a cool project but we can use it as stylistic inspiration if it's not adapted" | stands: gpui-shell, herdr-bar and herdr-gpui are shape sources only [w1-23 §2] |
| R28 | 2026-10-13 22:33Z (Codex rollout L2025) | "… one sway-wired workspace switcher that can be toggled with mod i ; with herdr-provided status indicators. only for the top display" | stands: the switcher is Sway-wired and output-pinned, i.e. personal composition over a platform adapter [w1-36 T12] |
| R29 | 2026-10-13 21:11:34Z | "for terminal: herdr + kitty ; until superlogical releases their terminal. for browser, google chrome." | stands: terminal and browser are launched, never embedded [w1-01 §2] |
| R30 | 2026-10-13 20:41 (`crepuscule-2026-10-14/sessions/dotfiles-rulings.md:56`) | "the way we control brightness and volume should be keypress>sway>script execution, no need to tie in vicinae if we don't have to" | stands: keys stay in Sway, scripts stay the actuators, the shell only displays [w1-36 T10, w1-29 §3.5] |
| R31 | 2026-10-12 (commit f7167e3b) | "ROG control center, report vicinae bug, donate to vicinae, chatgpt, claude, Claude, gcloud, github (the chrome --app shortcut), GVim, openwebui, perplexity, photos, railway, soundcloud, whatsapp, youtube-music must all be gone" / "this goes for cross-nixosfleet not just on the client" | stands: the launcher catalogue is curated in dotfiles; no vendor rows [w1-35 §2] |
| R32 | 2026-10-12 | "re personal utilities being on multiple workers, that is totally fine by me. but i want to be able to have claude interface with them (via mcp) in one place." / "i want ot have a single mcp codemode for all my cf worker-deployed utilities like email and crm etc" | stands: the single MCP codemode door is the utilities' (C), not the shell's [w1-12 §2.1] |
| R33 | 2026-10-07 (`dematerialized-2026-10-07/00-TOM-WORDS-AND-FRAME.md:6`) | "i also push back completely on its \"keep vicinae\" framing.. i would like to fully supersede this." | stands (the 10-12 "we keep vicinae actually" is superseded by R1/R5) [w1-36 T1/T6, w1-35 §2] |
| R34 | 2026-10-07 | "herdr itself is becoming the true cornerstone of this setup. truely: herdr+kitty+chrome+claudecode + vicinae" | stands with Vicinae replaced by the shell: herdr-centrality is the organising principle [w1-35 §2] |
| R35 | 2026-10-07 | "i have given up on the chromium fork in any shape, now decided to stick to trusty google chrome." | stands: Chrome is launched; Chrome tabs are read through the Vicinae extension bridge [w1-12 §2.1, w1-36 §3.11] |
| R36 | 2026-10-01 | "anything in views c++ touches the wayland layer-shell; never a fullscreen app. … fullscreen things are either terminal or chrome tabs/browser windows. with the occasional gtk filepicker and nautilus; that's totally tolerable" | stands with "views c++" read as GPUIX: layer-shell only; fullscreen apps are terminal, Chrome, and tolerated GTK pickers [w1-11 §2, w1-12 §2.1] |
| R37 | 2026-10-01 / 2026-09-16 | "never sharing it w anybody" / "i will only be using that font for my personal use and nowhere else" | stands: Anthropic fonts never leave the dotfiles or enter git [w1-12 §5, w1-09 §2] |
| R38 | 2026-09-27 (`FE/00-RULING-2026-09-27-the-separation.md:5-8`) | "i can create a clear separation now: views for OSD: 'anything that goes through fzf launcher for me today' plus notifications, bar, launcher with icons, workspace switcher, clipboard menu. on the CUBS side we control wifi, bluetooth etc. … but crucially ANYTHING THAT's a webapp goes on cloudflare deployments: specifically the personal cloudflare-os paradigm; and this is where it all ties together." | stands with "views" read as GPUIX and wifi/bluetooth moved into `controls` (R4): the shell surface list; webapps on Cloudflare [w1-30 §2.8] |
| R39 | 2026-09-27 (`FE/00b-RULING-…-the-token-kernel.md:52-58`) | "so we can now start with a 'kernel of design' token, that i know will be interpreted into chromium lit ; views c++ components ; AND since anything that's an actual interactive front-end is on cloudflare workers we benefit from the primer-react inspired claude-anthropic brand kit" / "every and all front-ends i deploy will be done on cloudflare workers." | stands: one token kernel, three emitters; GPUIX is the third [w1-30 §2.8, w1-11 §2] |
| R40 | 2026-09-01 (`PROJECT-SCOPES-2026-09-06.md:2960,2969`) | fonts "NEVER EVER shared on the internet" / "ghostty and Herdr are IN, kitty terminal is OUT for these users as default" | stands: the friends' Omarchy fleet is not a head of this shell; herdr travels, the shell and fonts do not [w1-30 §1.2, §2.8] |
| R41 | 2026-06-30 (`june30/noon-chat.md:221`) | "you went a little overboard. i never asked for a toml config, not even sure that's the best way to configure things here.." | stands: no invented config format; Nix renders JSON fragments the shell reads [w1-30 §2.7, SCOPE S-009] |
| R42 | 2026-03-26 (kmux B6/B7) | "Composition over monolith. kitty remote control + niri msg + shpool > custom daemon." "> yes" / "The filesystem IS the API. JSONL + semaphore locks + inotify > RPC daemons." "> yes" | stands: the shell composes herdr, Sway and scripts; it owns no session truth [w1-30 §2.4, w1-29 §4] |
| R43 | 2026-03-16 | "We must start with a clear definition of boundaries" / "No the library is not glass / Blur is provided by the compositor." / "We want the same aesthetic that powers the spotlight search bar dock and other shell utilities to also be powering what I use to build local web apps" | stands in spirit; blur is now "no blur" (BRIEF) [w1-22 §2] |
| R44 | 2026-03 (AM #200) | "in my case it s a custom shell written for one person, so the utilities/plugins i need are configured from the dotfiles themselves. no need to 'enable' plugins or browse through them. to be precise, in my world, an ephemeral pomodoro widget has the same place as the main launcher (there is no hierarchy)" | stands: shell configuration is Nix-rendered personal composition; no store, no plugin browser [w1-29 §3.1, w1-30 §2.5] |
| R45 | 2026-03 (AM #186) | "WONT. this is also a clear design decision that i take from the start: i do not need help managing my gtk or qt theme etc. that is what dotfiles are for. this also complements my 'NO MATUGEN' decision" | stands: the shell reads `~/.config/theme`; dotfiles write every app fragment [w1-30 §2.5] |
| R46 | 2026-03 (AM #101) | "DONT i explicitly reject i18n support for now. this is MY shell i'm not trying to reinvent the linux shell for the entire world" | stands: single-user, English; nothing in the shell is built for an audience [w1-30 §2.5] |
| R47 | 2026-03 (AM #240) | "the calendar month grid display will be handled by a bespoke, fullscreen, on-brand calendar app FAR later down the line. i do not need such utility in my shell." | stands: calendar is a utility, never a shell surface [w1-29 §3.1, w1-30 §2.5] |

Standing rule REPORTED from `AGENTS.md` ("Scheduled work", Tom, 2026-09-30): "No scheduled agent
work is declared in dotfiles." It bears on Vicinae's `interval` commands and script `refreshTime`
[w1-36 §2, §3.4].

Superseded lines that a reader might otherwise apply: the 2026-10-07 "no native shell" framing is
overridden by R21 and BRIEF §1 [w1-12 §2.1]; the 2026-10-12 "we keep vicinae actually" by R1/R5
[w1-36 T6]; "SEPARATE project" in R9 means separate from the agency-agency kit repo, not separate
from dotfiles (INFERRED, consistent with R17 and R21); the March "WONT. i do not need a control
center" is overridden by BRIEF `controls` and R4's "wifi menu, or bluetooth pairing menu" [w1-29
§2.6, w1-30 §2.5]; the March "niri ONLY" and the 2026-10-13 Hyprland trial are overridden by Sway
("let s stick to sway window manager. less effort", BRIEF §1) [w1-30 §4.3]; kmux A14 SF Pro by the
Anthropic fonts (R37) [w1-30 §2.4].

---

## 2. What the shell may and must not do with the utilities

Grounded in SEPARATION.md Rule A, UTILITY-ACCESS.md and the [w1-12 §7] rules; each line names its
note.

### 2.1 May

| The shell may | Grounding |
|---|---|
| **Launch** a utility: open its Chrome PWA desktop entry or its native-kit window by argv, as the launcher opens any `.desktop` entry (via `gio launch`, never inheriting the launcher env); place it on a Sway workspace by rule (Chrome on 10, Mod+0) | R29, R35; [w1-18 §3, w1-36 §3.6 `app launch`, w1-30 §3.4, SCOPE S-060] |
| **Show OpenUI programs** that a utility (or the local model) emits, through the framework-neutral adapter: validate with `validateProgram`, resolve `ShellAction`s in the shell host against an allow-list, render in GPUIX; replay saved programs with no model | R7; [w1-24 §3, w1-12 §4.3, w1-14 §4, SCOPE S-201] |
| **Read receipts** and read-only state: herdr snapshots and events, speech playback receipts, paper-daemon receipts, `vpn-status` JSON, notification history it owns itself | [w1-16 §3, w1-12 §3.2, w1-29 §3.5, BRIEF §3.4] |
| **Receive** notifications from utilities as ordinary `org.freedesktop.Notifications` clients (Chrome, KDE Connect/Valent, kitty OSC 99, herdr semantic notifications with `[ui.toast] delivery = "system"`) | [w1-26 §3, w1-23 §3.3, w1-29 #65/#252, w1-30 G4] |
| **Host extensions** written to the Vicinae/Raycast grammar in a Bun worker per command, installed declaratively (`mkVicinaeExtension`/`mkRayCastExtension` outputs), with `AI`, `Wallpaper` and the store reported unavailable | R1; [w1-36 §4.2, §4.7, §3.12, SCOPE S-096] |
| **Read Chrome tabs** through the published Vicinae extension (`kcmipingpfbohfjckomimmahknoddnke`) and an own native host under `com.vicinae.vicinae`, focusing the tab and then Sway workspace 10 | R23, R35; [w1-36 §3.11, §4.6, SCOPE S-067] |
| **Expose a shortcut** to a utility: a launcher row, a rail custom button, a Sway bind calling `gpuix-shell` | R24; [w1-29 #58, w1-36 §3.13, KEYS] |
| **Import** from the shared core: theme token roles, the OpenUI contract and adapter, the status vocabulary, the LauncherProvider and command-registry contracts, the fuzzy/frecency helpers, the Vicinae wire vocabulary | R9, R13, R39; [w1-12 §3.2, w1-11 §3, w1-19 §3, w1-36 §4.3] |
| **Hand a payload to an agent** by copying it and switching to the chosen slot ("send to agent"), never by injecting into the PTY | [w1-16 §4, SCOPE S-194] |
| **Feed learnings back**: anything built tonight that passes the import fence (§5) is a candidate for extraction (§6) | R9 |

### 2.2 Must not

| The shell must not | Grounding |
|---|---|
| **Own a utility's data**: no mailbox, contact, project, deal or chat thread store in `$XDG_STATE_HOME/gpuix-shell`; the only stores the shell owns are notification history, clipboard history, launcher frecency/pins/MRU, extension `LocalStorage`, the music queue/index cache, and its own settings | FP/BOUNDARIES.md:5; [w1-12 §3.1, §7; SCOPE S-009, S-145; MUSIC.md] |
| **Embed a utility's React DOM** or web view: no WebView, no CDP screencast, no Chrome tab rendered inside a layer surface; Chrome tabs are listed and focused through the bridge only | R35, R36; [w1-36 §3.11, w1-12 §2.1, w1-30 §2.3 "no WebView"] |
| **Require a utility**: every surface starts and works with no mail, CRM, projects or chat deployed, with herdr-web-ui absent, with Chrome's extension missing, with Navidrome unreachable and with the local model down; herdr itself is read-only truth, and its absence degrades the rail to Sway-only slots | [w1-16 §3, w1-19 §3, w1-12 §7 rule 5, w1-24 §6, w1-36 G4] |
| **Hold a utility's credentials**: no Cloudflare token, no OAuth tokens for mail or CRM, no Navidrome password in git or in the shell config; secrets come from runtime files outside the store and never reach argv, logs or the automation tree | [w1-21 §4, w1-12 §5, MUSIC.md, BRIEF §2 "no secrets"] |
| **Issue a herdr focus verb** or any herdr write: `herdr workspace focus` is server-global; the shell focuses Sway workspaces only and never spawns, closes or renames herdr work itself (the `herdr-chord`/`sway-workspace` binds keep lifecycle) | [w1-16 §4, w1-19 §3, SCOPE S-005] |
| **Inject keystrokes**: no setcap input server, no `wtype` by default; "paste" degrades to copy plus HUD | [w1-35 §6.6, w1-36 G7, SCOPE S-147] |
| **Approve anything over the wire**: no `shell.sock` verb may answer a polkit, NM SecretAgent or BlueZ pairing prompt; irreversible session verbs need the hold-to-confirm in the UI; "`lock` is a safe one-way verb; `unlock` is not a verb at all" | [w1-29 §3.6, §4 value 16; w1-30 §3.2] |
| **Write Sway config, GTK or Qt themes, wallpaper, outputs or the dotfiles**: the shell reads `home/dot_config/sway/*` and `~/.config/theme`; dotfiles, kanshi and swaybg write them | R41, R45; [w1-29 §3.1 #160/#172/#186, w1-30 §2.5, SCOPE S-185] |
| **Speak for the utilities to agents**: the single MCP codemode door over the Workers utilities is theirs (C); the shell's socket is a local human-and-script door only, not reachable off-host | R32; [w1-12 §2.1, w1-36 §4.6] |
| **Ship Anthropic fonts or Claude/Anthropic brand names** into any shared package; fonts load at runtime by `registerFont(bytes)` from the system path and are never bundled | R15, R37, R40; [w1-12 §5, §7 rule 10; w1-11 §4; w1-15 §3.8] |
| **Reach a utility head's internals**: no import from herdr-web-ui's `src/`, from the kit's `apps/*`, from the `shared-parity` bundle or from any agency app; only published contracts and generated types, copied with a provenance comment | SEPARATION.md Rule A (mirrored); [w1-12 §3.3, w1-19 §3B] |
| **Register `x-scheme-handler/vicinae` or `raycast`** while Vicinae is still installed; the HM module asserts `programs.gpuixShell` and `programs.vicinae`/`services.mako` are exclusive | [w1-36 §4.6, w1-21 §4, SCOPE S-012] |
| **Schedule work**: no timers polling utilities; the Vicinae `interval` and `refreshTime` keys are parsed and gated off; refresh happens on events, socket calls and visibility | AGENTS.md "Scheduled work"; [w1-36 §3.4, §3.7, G8] |

---

## 3. Ownership table of every component

Owner values:

- **personal shell (dotfiles)** — Tom's composition or compositor-bound code; `pkgs/gpuix-shell/src/surfaces`, `home/gpuix-shell.nix`, `home/dot_config/sway/*`, `home/dot_local/bin/*`, rendered JSON config.
- **platform adapter (Linux, reusable)** — `src/platform/{sway,linux}`: Sway/Wayland/D-Bus providers that another Sway user could take; built in dotfiles tonight, extractable later, never personal policy.
- **shared core (agency)** — `src/core`: platform-neutral TypeScript with no `child_process`, D-Bus, `swaymsg`, filesystem or GPUIX import; built in dotfiles tonight where needed, destined for the agency library (§6).
- **utility head (B/C)** — mail, CRM, projects, chat, files-as-app; agency org; launched, never built here.
- **not built / out** — dropped by a ruling or deferred with a seam.

| Component | Owner |
|---|---|
| `gpuix-shell rail` process: left layer-shell bar, 56/220, slots 1–9 plus status cluster, one surface per output [w1-19 §3, w1-29 §3.1 #1–#26, SCOPE S-020/S-024] | personal shell (dotfiles) |
| Rail row model (slot number, label, status glyph, attention flag, last-visited acknowledgement) [w1-19 §3C, w1-16 §3, w1-25 §3] | shared core (agency): pure data; the rail renders it |
| herdr snapshot and `events.subscribe` reader (events are wake-ups, never state; `boot_id` change = forget cache), Sway marks `herdr-slot-N` / `herdr-label-*` / `herdr-closed-*` / `herdr-name-*` [w1-16 §3–§4, w1-23 §3.3, SCOPE S-005] | platform adapter (Linux, reusable) |
| herdr status vocabulary (blocked ◉ working ◐ done ● idle ✓ unknown ○), rank table (blocked < done < working < idle < unknown), generated API types [w1-16 §2, w1-19 §3B, w1-23 §3.2] | shared core (agency): already shared with herdr-web-ui and the kit's `herdr-types.ts` |
| Attention rule: `blocked` → Sway urgency + one actionable notification "Go"/"Dismiss"; `done` → rail mark until visited; never auto-focus [w1-16 §5, w1-18 §3, SCOPE S-109/S-190] | shared core: the rule; platform adapter: the urgency hint and the notification |
| Sway IPC client (i3-ipc framing, query + subscribe sockets, name quoting, verify-after-switch), workspace/window/output events, `fullscreen_mode` hide [w1-26 §2, w1-29 #159, w1-30 #10] | platform adapter (Linux, reusable) |
| Tom's output policy (eDP-1 top rail with slots, eDP-2 reduced rail, Chrome on workspace 10, Duo scale), nine-slot cap [R12, R28, w1-19 §3, w1-30 §3.1 #5–#6, SCOPE S-041] | personal shell (dotfiles) |
| `gpuix-shell launcher` (Mod+d overlay 700×580, Raycast list, action panel Ctrl+B, prefix modes, footer, HUD) [w1-35 §3.3–§3.4, w1-36 §4, SCOPE §2] | personal shell (dotfiles) |
| LauncherProvider contract (`pkgs/gpuix-shell/src/launcher/provider.ts`), `RootProvider`/`RootItem` registry, prefix router, entrypoint ids `provider:entrypoint` [w1-36 §4.3, SCOPE S-051/S-061, MUSIC.md] | shared core (agency) |
| Fuzzy match (herdr-bar constants SCORE_MATCH 16 etc.), frecency (Vicinae formula), MRU (cap 120, "current row never first"), pin store [w1-23 §3.2, w1-35 §3.1 ranking, w1-29 #90–#91] | shared core (agency): algorithms; the storage backend is injected |
| Apps provider (XDG `.desktop` parser with `Actions=`, the 11 PWA and 7 dotfiles entries, hide-list, `gio launch`) [w1-18 §3, w1-30 #83/#102, SCOPE S-060] | platform adapter (Linux, reusable): parser and launcher; personal shell: the hide-list and favourites |
| Files provider over `fd` (no indexer daemon), XBEL recent files, `gio trash` never `rm` [w1-29 #85, w1-35 §3.1 files, w1-36 Action.Trash, SCOPE S-065] | platform adapter (Linux, reusable) |
| Clipboard store: `wl-paste --watch gpuix-shell clipboard ingest`, kinds, hash dedupe, password-hint skip, eviction 86400 except pinned, image files + thumbnails, FTS [w1-29 #86, w1-30 #86, w1-35 §3.1 clipboard, SCOPE S-145] | platform adapter (Linux, reusable): the watcher and store; shared core: the schema and retention policy; personal shell: Mod+v and the thresholds |
| Emoji provider (Vicinae glyph table → JSON, 5 059 glyphs, GPL provenance noted), calculator (`=`), shell-command mode (`>`) [w1-35 §3.1 core, w1-29 #84/#87/#99] | shared core (agency): glyph data and calculator; platform adapter: command execution |
| Chrome tab search: published extension `kcmipingpfbohfjckomimmahknoddnke` + own Bun native host `com.vicinae.vicinae` (framing uint32+JSON, `browser/init`, `browser/tabs-changed`, `browser/focus-tab`, `browser/close-tab`), focus Sway workspace 10 after tab switch [w1-36 §3.11, §4.6, SCOPE S-067] | platform adapter (Linux, reusable): the native host; personal shell: the Nix manifest link and the Chrome-on-10 rule |
| `shell.sock` router (Vicinae framing: 4-byte native-endian + JSON-RPC 2.0, replies routed per connection) and the `dmenu` verb with Vicinae's flags and exit codes (herdr-picker compatibility) [w1-36 §3.5–§3.6, §4.6, SCOPE S-002/S-086] | personal shell (dotfiles) |
| Vicinae extension host: `@gpuix-shell/api` aliasing `@vicinae/api` / `@raycast/api`, view-tree wire vocabulary (`jsx.d.ts` intrinsics), reconciler port (handlers → ids, 60/s), Bun worker per command, manifest zod schema [w1-36 §3.1–§3.4, §4.2–§4.4, SCOPE S-096] | shared core (agency): wire vocabulary, reconciler, manifest schema, `Cache`; personal shell: the GPUIX element renderer (`virtual-list`, `anchored`, `Dialog`) |
| Vicinae extension data: `Icon` ids (854), `Keyboard.Shortcut.Common`, keybind ids, `favorites`/`fallbacks`/`providers` config shape [w1-36 §3.2, §3.8] | shared core (agency); icon SVGs only after the licence check [w1-36 G11] |
| Script-command header parser (`@vicinae.*`/`@raycast.*`, modes, arguments, `refreshTime` parsed but gated) and the dotfiles script catalogue it lists [w1-36 §3.7, SCOPE S-071] | shared core: the parser; personal shell: the catalogue |
| Navidrome music lane: `gpuix-shell music serve` daemon (sole reader of the credential file, owns mpv over fd-IPC, queue, index, art cache), own MPRIS `org.mpris.MediaPlayer2.gpuix_music`, launcher `♪` view, rail chip [BRIEF §5, w1-35 §3.1 media, MUSIC.md] | personal shell (dotfiles): daemon, MPRIS, credentials, mpv; shared core: `MusicBackend` interface, Subsonic client types/map, provider contract (INFERRED) |
| `gpuix-shell switcher` (Mod+i, slots 1–9 + 10, herdr status, running time, top display only) [R28, w1-19 §3, w1-29 #27/#173, SCOPE S-121] | personal shell (dotfiles) |
| `gpuix-shell notifications`: `org.freedesktop.Notifications` server (capabilities `actions body body-markup icon-static persistence`, `value` hint, replace-id, `ActivationToken`, flood cap, 1 s coalescing), toasts, history panel, DND, rules [w1-18 §3, w1-26 §3, w1-23 §3.1, w1-29 #65–#82] | platform adapter (Linux, reusable): the D-Bus server and history store; shared core: the notification store model; personal shell: anchor, timeouts, muted apps, rules |
| Toast and OSD React components (card, urgency stripe, progress fill, hint letters, action chips) [w1-11 §3, w1-18 §3, w1-23 §3.1] | shared core (agency): components without layer-shell; personal shell: the windows |
| OSD window (volume, brightness, mic, media card, audio-route switch, touchpad/Caps) driven by observing the service, not the key [w1-29 #122–#132, w1-23 §3.1 OSD] | personal shell (dotfiles); `volume`, `brightness`, `audio-route` scripts stay the backends (R30) |
| `gpuix-shell controls`: per-domain menus (Wi-Fi, Bluetooth, audio route, Tailscale peers, battery/power profile, airplane mode, DND, caffeine, night light), no control-center grid (INFERRED resolution of the March WONT) [w1-29 §1.6, §1.12, w1-30 §2.5, SCOPE §6] | personal shell (dotfiles): the menus; platform adapter: the operations behind them |
| Operation definitions with explicit target and result (`confirmed / failed(reason) / unknown`), READ/WRITE-reversible/ACTION-irreversible/SECRET-AUTH tagging, actor field on receipts [w1-12 §3.1 "Quick settings", §7 rules 4/6; w1-29 §3.6; w1-30 §3.2] | shared core (agency) |
| NetworkManager, BlueZ (+`Agent1` later), UPower, logind, power-profiles-daemon, MPRIS, PipeWire (`pw-dump`/`wpctl`), wl-gammarelay-rs clients over dbus-next, with the exact interface/member tables from gpui-shell [w1-26 §3–§5, w1-23 §3.4, SCOPE S-006] | platform adapter (Linux, reusable) |
| Tailscale peer provider (`tailscale status --json`, `vpn-status` script, exit-node pick) [w1-29 #41/#144, w1-30 G1, SCOPE S-031/S-135] | personal shell (dotfiles): the script and tailnet membership; platform adapter: the JSON reader |
| `gpuix-shell files` (Pinax-inspired explorer as an ordinary toplevel, `files pick` mode for `Form.FilePicker`; the GTK portal/Nautilus stays the picker for other apps) [BRIEF §3.2, R6, w1-20 §3, w1-36 §4.5, SCOPE §10/S-160] | personal shell (dotfiles) tonight, with a platform-neutral file model (INFERRED; R21 lists "files" among the tray/dock apps, so the model must be extractable) |
| `gpuix-shell power` (list + press-and-hold, monitors-off, hibernate detection, logind fallback chain) [w1-29 #218–#220, §5 MA A15, SCOPE S-140] | personal shell (dotfiles) |
| `gpuix-shell ask` (bounded OpenUI prompt against the local model, SSE `completionChunks`, library `gpuix-shell.ask@1`, `ShellAction` allow-list, replay log; `$mod+a` reserved) [w1-24 §3, BRIEF §3.7, SCOPE S-200/S-201, KEYS] | personal shell (dotfiles): the surface and its private vocabulary; shared core: validator, adapter, `stream.ts` |
| OpenUI contract: `defineComponent({component:null})`, `createLibrary`, `validateProgram`, `resolveStep`/`ShellAction` resolution, streaming parser, pruned-subset prompt [w1-24 §3, w1-14 §4, w1-12 §4.3] | shared core (agency): `shared-parity/src/openui/{contract,host,programs}.ts` is the seed |
| OpenUI MutationHost adapter (`shared-parity/src/native/adapter.ts`) and the GPUIX RetainedHost [w1-14 §4, w1-24 §4] | shared core (agency): the adapter interface; personal shell: the GPUIX host binding |
| Local model endpoint `strix:8731`, model id as a runtime file (`~/.config/gpuix-shell/model.json`, not Nix), no remote fallback, Halogen→Gufo cutover awareness [w1-24 §2, §6 item 16, AGENTS.md] | personal shell (dotfiles): the endpoint and config; never in the shared core |
| `gpuix-shell` CLI verbs: `toggle/open/close`, `cmd ls` / `cmd launch`, `dmenu`, `rail toggle --output`, `notifications dnd`, `osd show`, `clipboard *`, `music *`, `ping`, `state open`, `validate`, exit codes 0/1/2/3/69 [w1-36 §3.6, w1-23 §3.1 CLI, BRIEF §3.2, SCOPE S-002] | personal shell (dotfiles) |
| Theme fragment `~/.config/theme/gpuix-shell.json` rendered from `home/themes/*.nix` (noir, claude-dark, claude-light), live symlink watch, Vicinae-slot mapping reused [w1-11 §3, w1-12 §5, w1-36 §3.13, BRIEF §3.5, SCOPE S-180] | personal shell (dotfiles): the palettes and the watcher |
| Theme token roles (surface, hairline, text, selection, accent, `--dot-*`/`--status-*` families, 50 ms motion, 220/30/12/2/8 geometry) [w1-11 §3, w1-22 §3, w1-25 §3, w1-12 §5, DESIGN] | shared core (agency): brand-free keys; the kit's `core/theme.ts` and `palette.tsx` already hold a sibling set |
| Per-surface JSON config rendered by Nix (rail zones, toast anchor, hidden apps, favourites, provider prefs, clipboard rules), one zod schema; state under `$XDG_STATE_HOME/gpuix-shell/` [R41, R44, w1-29 #175/#178/#200, w1-36 §3.8, SCOPE S-009] | personal shell (dotfiles): values; shared core: the schema shape (INFERRED) |
| Anthropic Sans / Serif / AnthropicMono Nerd Font files and the font slot's personal value [R15, R37, R40, w1-12 §5] | personal shell (dotfiles), never in git, never shared |
| Font slot (configurable family; kit defaults `.SystemUIFont`/Georgia/Menlo) [w1-09 §3, w1-12 §5] | shared core (agency): the slot; each head supplies a value |
| Design kit rules U-01..U-19 (U-15 "The platform owns the frame", U-18 "Identity is a skin over one theme file") and P-01..P-16 [w1-09 §3, w1-11 §3] | shared core (agency): the document and the components it implies |
| React components without layer-shell: list row, section header, search field, action panel, toast card, status glyph, progress fill, dialog, form fields, metadata block, markdown detail [w1-11 §3, w1-36 §3.1, w1-23 §3.1 ui crate checklist] | shared core (agency) |
| Layer-shell window wrappers: anchors, exclusive zones, keyboard-interactivity, per-output instances, one window per renderer, several renderers per process allowed but one process per surface family stays the default [w1-14 §3, w1-15 §3.4, w1-19 §3, SCOPE S-001] | platform adapter (Linux, reusable) |
| GPUIX runtime facts the shell codes around (no window close/hide, no output selection, no layer reconfigure or input region, size 0 = stretch, no JS clipboard, runtime-error overlay → own `uncaughtException` exit) [w1-15 §3–§6] | platform adapter (Linux, reusable): documented in the wrapper, not scattered |
| Keybinds (`binds.conf`): Mod+d/space, Mod+i, Mod+v, Mod+o, Mod+x, Mod+comma, F-keys, Caps touchpad OSD, the 11 activated + 3 proposed binds [w1-18 §3, w1-36 §3.13, KEYS] | personal shell (dotfiles) |
| Keybinding cheatsheet (`?` prefix, parses the rendered Sway config + the shell keymap) [SCOPE S-165, w1-30 §3.5] | personal shell: the Sway parse; shared core: the key-chip renderer (INFERRED) |
| systemd user units `gpuix-shell-<surface>` on `sway-physical-session.target`, `Restart=on-failure` [w1-21 §3, BRIEF §2, SCOPE S-001] | personal shell (dotfiles) |
| Nix packaging: `buildNpmPackage` + `autoPatchelfHook` + `appendRunpaths [wayland vulkan-loader libGL]`, `package-lock.json` only, externals `@gpuix/native` `usocket` `x11`, `--check-native/--check-dbus/--check-theme`, `checks.gpuix-shell-themes`, `git add -N` visibility, conditional `home-profiles` asserts, `programs.gpuixShell.enable` exclusive with vicinae/mako [w1-21 §2–§5, SCOPE S-012] | personal shell (dotfiles) |
| HM option surface mirroring Vicinae's (`extensions`, `settings` override layer, `settingOverrides` for secrets, `browserIntegration.chrome`) [w1-36 §3.12] | personal shell (dotfiles) |
| Existing scripts kept as backends: `volume`, `brightness`, `audio-route`, `media`, `screenshot`, `colorpicker`, `screen-ocr(-area)`, `pomodoro`, `recording-toggle`, `vpn-status`, `theme`, `sleep-monitors`, `monitors-off`, `touchpad-toggle`, `sway-workspace`, `herdr-*`, `claude-capacity` [w1-18 §3, w1-29 §5 KEEP rows, w1-12 §7 rule 12] | personal shell (dotfiles) |
| Compositor smoke tests `tests/gpuix-shell/smoke_<surface>.py` under `runtime-test --render-node /dev/dri/renderD128` (never `test_*.py`, never a flake check) plus hermetic `test_*.py` unittest in `checks` [w1-21 §5.3c, §5.6, gap 18; w1-14 §5; BRIEF §4] | platform adapter (Linux, reusable): the harness template (`smoke_noicd.py` lineage); personal shell: the Duo-specific cases |
| `fakehost` test harness (kit `core/testing/fakehost.ts`) and the `RetainedHost` test pattern (`tests/native.test.ts`); `hasTestGpuixRenderer() === false` on Linux so UI tests are pure-logic [w1-14 §5, w1-19 §3B, w1-15 §5, MUSIC.md] | shared core (agency) |
| Mail, CRM, projects, chat (herdr-web-ui / clui-cc successor), "vesence ones" [R21, R25, w1-06 §A, w1-12 §2.1] | utility head (B/C): agency org; the shell launches them |
| herdr-web-ui leftbar logic (`status.ts`, `railGroups.ts`, `slotLabel.ts`, `workspaceRows.ts`, `sidebarAgents.ts`, `paletteSearch.ts`, `desk/shell/providers.ts`, `look.ts`, agent SVG marks) [w1-25 §5, w1-19 §3B] | shared core (agency): already there; the rail re-implements the Sway head of it, it does not import the web bundle |
| Agency native kit `@agency-agency/kit` (Solid on GPUIX 0.10.0, `core/{theme,keys,palette,frame,window}`, four windows, macOS-15 runner) [w1-12 §2.1, w1-09 §3] | utility head (B): Marwan's |
| Cloudflare Workers deployments, single MCP codemode door, manual runbook on the first user's account [R20, R32, w1-12 §2.1] | utility head (C): agency; never in dotfiles |
| herdr server, `herdr` CLI, kitty projector, Chrome, Nautilus/GTK portal picker, `herdr-chord` [R6, R29, R36, w1-01 §2, w1-16 §4] | out of the shell: launched or read, never built here |
| Calendar grid, notes, weather, KDE Connect panel, system monitor, settings GUI, onboarding wizard, update checker [w1-29 #240/#249/#43/#252/#245/#174/#265/#248, w1-30 G3/G4/G15] | not built / out: calendar and notes are utilities (R47); settings = read-only `core:settings` provider (SCOPE S-082); the rest LATER with a launcher seam |
| SNI tray host, polkit agent, BlueZ pairing agent, NM SecretAgent, lock screen, idle suite [w1-29 #29/#216/#152/#147/#203/§1.10, w1-26 §3, w1-30 G2/G10, SCOPE S-168/S-189/S-188/S-141] | not built tonight: polkit (Tom's MUST, needs a PAM helper), tray, Agent1 and SecretAgent are platform-adapter seams when built, single-owner bus names; lock and idle ICEBOX with the `gpuix-shell lock` seam |
| Material You/matugen, blur/glass, wallpaper picker, i18n, multi-compositor facade, Hyprland/niri modules, extension store at runtime, telemetry/news/sponsor rows [w1-29 DROP rows, w1-30 §2.4, §4.3, w1-36 §3.10, R31] | not built / out |
| Speech-input wake listener, dictation, NPU inference, FARA browser agent, tally [AGENTS.md, w1-29 §3.7] | not built / out: removed by Tom and never reintroduced |
| Friends' Omarchy Quattro fleet (ghostty + herdr, no kitty, no fonts) [R40, w1-30 §1.2, §3.4] | out: a separate NixOS fleet, not a head of this shell; herdr travels, the shell does not |

Count: 62 rows by primary owner: 23 personal shell, 11 platform adapter, 19 shared core, 3 utility
head, 4 not built / out, 2 out of the shell (launched or read); 17 of the rows name a second owner
for part of their code.

---

## 4. The three heads and what of tonight's code each can reuse

### 4.1 Tom — Sway + GPUIX layer-shell (this repo)

Everything in §3. Tom's head is the only one that runs layer-shell surfaces, owns a notification
server, reads Sway IPC and herdr marks, hosts a `shell.sock` door and carries the Anthropic fonts
[R10, R36, R37]. It consumes the shared core and the platform adapter and adds personal composition
(outputs, keys, hostnames, slot policy, palettes, the curated launcher catalogue). It launches the
utility heads: Chrome PWAs on workspace 10, herdr-web-ui in Chrome, and nothing of the macOS kit
[R29, R35]. Its renderer is GPUIX 0.11.0 under React 19 via `@gpuix/react`; one window per renderer,
one process per surface family by default [w1-15 §3.4, SCOPE S-001].

### 4.2 Marwan — native kit (`@agency-agency/kit`, Solid on GPUIX 0.10.0, macOS)

Reusable from tonight, after the morning extraction (§6), because none of it needs a compositor:

| Artefact | Why it transfers | Grounding |
|---|---|---|
| Theme token roles and the three palettes' *role names* (not the Claude-named values) | the kit's `core/theme.ts`, `palette.tsx` are a sibling; one DTCG/JSON file with brand-free keys can feed both (U-18) | [w1-11 §3, w1-12 §5, w1-09 §3] |
| OpenUI contract, validator, action resolution, `stream.ts` SSE parser | lang-core is framework-agnostic; the kit can host OpenUI programs in a native window | [w1-24 §3, w1-14 §4] |
| MutationHost adapter interface | framework-neutral by design; the kit supplies a Solid or GPUIX 0.10 host | [w1-14 §4] |
| LauncherProvider contract, `RootProvider` registry, fuzzy/frecency/MRU | the kit's `core/keys.ts` is already a command map; a kit palette could host the same providers | [w1-36 §4.3, w1-19 §3, w1-23 §3.2] |
| Status vocabulary, rank table and herdr types | the kit's `apps/chat/herdr-types.ts` is the same set | [w1-16 §2, w1-19 §3B, w1-23 §3.3] |
| Operation definitions and receipts (`confirmed / failed / unknown`, actor field) | the kit already needs the same "one operation, many callers" shape (R-A1) | [w1-12 §3.1, §7 rule 6] |
| Vicinae wire vocabulary, manifest schema, reconciler port | a native extension host for the kit's own palette; no layer-shell dependency | [w1-36 §3.3–§3.5, §4.2] |
| `fakehost` test pattern | already the kit's | [w1-14 §5] |
| React components without layer-shell | only as *designs*: the kit is Solid, so components transfer as specs (props, states, geometry), not as code | [w1-09 §3, w1-11 §3] (INFERRED) |

Not reusable by Marwan: the rail, the notification server, Sway IPC, D-Bus providers, systemd units,
Nix packaging, the OSD, the controls menus, the clipboard store, the Chrome native host (macOS path
and Keychain differ), the fonts [R20, R22, R37].

### 4.3 Frank — browser head (herdr-web-ui fork in Chrome on Cloudflare Workers)

| Artefact | Why it transfers | Grounding |
|---|---|---|
| Theme token roles as CSS custom properties (`--dot-*`, `--status-*`) | R39 names "chromium lit" as an emitter; the web head already consumes Primer-style tokens | [w1-30 §2.8, w1-11 §3, w1-25 §3] |
| OpenUI contract, validator, `stream.ts` | the web head renders OpenUI programs with React DOM; same lang-core | [w1-24 §3, w1-08 §2.5] |
| React components without layer-shell | direct code reuse: list row, action panel, toast card, status glyph, progress fill, dialog, as long as they import nothing from `@gpuix/*` | [w1-11 §3, w1-36 §3.1] |
| herdr-web-ui leftbar logic | it is already Frank's; the rail's Sway head only re-implements it | [w1-19 §3B, w1-25 §5] |
| Shortcut catalogue (`ui/shortcuts.ts`) and the "trailing clicks" presenter | R7 wants human clicks and agent API calls to be the same path | [w1-08 §2.5, w1-14 §4] |
| Vicinae-style extension vocabulary | a web palette can render the same view tree in DOM | [w1-36 §4.3] (INFERRED) |

Not reusable by Frank: anything needing a socket, a file system, D-Bus or a compositor; the clipboard
store; the Chrome native host; the fonts [R11, R37].

### 4.4 Not a head: the friends' Omarchy fleet

Omarchy Quattro (`PROJECT-SCOPES` card 11) is a separate NixOS fleet for Tom's friends: "ghostty and
Herdr are IN, kitty terminal is OUT for these users as default", and the fonts are "NEVER EVER shared
on the internet" [R40, w1-30 §1.2, §2.8]. herdr and the agency utilities travel there; gpuix-shell,
the Sway binds, the palettes and the fonts do not. Nothing in §3 is built for it.

### 4.5 Summary matrix

| Artefact | Tom | Marwan | Frank |
|---|---|---|---|
| Theme token roles | yes | yes | yes |
| Palette values with Claude/noir names | yes (private) | no (own skin) | no (own skin) |
| Anthropic fonts | yes (private) | no | no |
| OpenUI contract + adapter + stream | yes | yes | yes |
| React components without layer-shell | yes | as specs | yes |
| Layer-shell windows, GPUIX wrappers | yes | no | no |
| LauncherProvider / registry / fuzzy / MRU | yes | yes | yes |
| Status vocabulary + rank + herdr types | yes | yes | yes |
| Operation definitions + receipts | yes | yes | yes |
| Sway IPC, D-Bus providers | yes | no | no |
| Notification server, OSD, controls, power | yes | no | no |
| Vicinae wire vocabulary + reconciler | yes | yes | yes |
| Chrome native host | yes | no | no |
| Clipboard store | yes | no | no |
| `shell.sock`, `dmenu` verb | yes | no | no |
| Music daemon, MPRIS, credentials | yes | no | no |
| Subsonic client types, provider | yes | yes (INFERRED) | yes (INFERRED) |
| Nix module, systemd units | yes | no | no |

---

## 5. Import fence and packaging rules

These are the enforceable form of §2 and §3, mirrored from SEPARATION.md Rule A and the [w1-12 §7]
rules; they bind tonight's code in `pkgs/gpuix-shell/src/`.

1. **Direction and layers.** `src/surfaces` → `src/platform` → `src/core` only. Nothing under
   `src/core` imports `child_process`, `dbus-next`, `@gpuix/native`, `@gpuix/react`, `swaymsg`,
   `node:net`, `node:fs`, `bun:sqlite` or anything under `platform/` or `surfaces/`. An import-fence
   test (a grep over `src/core` for those names, run as a `bun test` and wired into the Nix `checks`
   set) enforces it (INFERRED: the fence is w1-12 §7 rule 2; the test shape is mine) [w1-12 §3.2,
   w1-21 §5].
2. **No utility internals.** No import from herdr-web-ui's `src/`, the kit's `apps/*`, the
   `shared-parity` bundle, or any agency app; only copied contracts with their provenance comment
   [w1-19 §3B, w1-14 §4, w1-25 §5].
3. **No brand in core.** Token keys in `src/core` are role names (`surface.base`, `text.muted`,
   `accent`, `dot.attention`); "noir", "claude-dark", "claude-light" and the Anthropic font names
   appear only in `home/themes/*.nix` and the rendered fragment [R15, R37, w1-12 §5, w1-12 §7 rule 10].
4. **No secrets in the store.** Navidrome, Tailscale and the model endpoint are read from runtime
   files outside Nix (`~/.config/gpuix-shell/model.json`, `NAVIDROME_CREDENTIALS_FILE`, HM
   `settingOverrides` paths); none is printed in logs, placed on argv, or reachable from the GPUIX
   automation tree [w1-21 §4, w1-24 §6, w1-36 §4.7, MUSIC.md].
5. **One compositor.** No facade: Sway IPC is called directly; a second compositor is a new adapter,
   not a branch [AM #158 principle, w1-29 §2.6, §4 value 3].
6. **Optional everything external.** herdr, Chrome and its extension, Navidrome, the local model,
   Vicinae's data dir: absent → the surface shows its empty state with a reason; never a crash, never
   a blocking retry; "unavailable is visible, with a reason" [w1-16 §3, w1-36 G4, w1-12 §7 rule 5].
7. **No timers.** Refresh happens on events, socket calls and visibility; the Vicinae `interval` and
   `refreshTime` keys are parsed but gated off [AGENTS.md "Scheduled work", w1-36 §3.4, §3.7].
8. **The shell's socket is local, and never a credential path.** `shell.sock` serves scripts,
   herdr-picker and the native host; it is not the MCP door, not reachable off-host, and no verb
   approves an auth prompt or focuses herdr [R32, w1-36 §4.6, w1-29 §3.6].
9. **Keys stay in Sway.** `bindsym` → `gpuix-shell` or a script; GPUIX registers no global
   shortcuts; "Set Global Shortcut" becomes "write a Sway bind" [w1-35 §3.4, w1-12 §7 rule 9, KEYS].
10. **Licence provenance.** Data and code taken from Vicinae (glyph table, component wrappers, icon
    ids) carry a provenance comment; the repo is private, so GPL/ISC obligations are met by not
    publishing; a licence check precedes any extraction to the agency org [w1-35 §6.12, w1-36 G11].
11. **Tests never touch the live session.** Compositor smokes run only under `runtime-test
    --render-node`; `test_*.py` and `bun test` are hermetic; nothing restarts herdr, the user manager
    or Sway [w1-21 §5, BRIEF §4, agent-runtime rules].

---

## 6. Foundation for later: what to extract into the agency shared library after the morning

Ordered by how little compositor residue each carries. Each row names the tonight location, the
target package (INFERRED names, inside the agency-agency org), and the condition for extraction.
Nothing here is extracted tonight; the morning is Tom's.

| # | Extract | From (tonight) | To (agency) | Condition |
|---|---|---|---|---|
| F1 | Theme token roles as one DTCG-style JSON with brand-free keys, plus the role→Vicinae-slot, role→CSS (`--dot-*`/`--status-*`) and role→GPUIX mapping tables | `home/themes/default.nix` slot mapping, `~/.config/theme/gpuix-shell.json` schema [w1-11 §3, w1-36 §3.13, w1-25 §3] | `@agency-agency/tokens` | palettes stay home; only keys and the three emitters' mapping go |
| F2 | OpenUI contract, `validateProgram`, action resolution (`resolveStep`/`ShellAction`), streaming parser, pruned-subset prompt builder | `shared-parity/src/openui/*`, `src/model/stream.ts`, tonight's `ask` host [w1-24 §3, w1-14 §4] | `@agency-agency/openui` | the `gpuix-shell.ask@1` vocabulary stays shell-private; the kernel goes |
| F3 | MutationHost adapter interface plus the React DOM and GPUIX reference hosts | `shared-parity/src/native/adapter.ts`, tonight's GPUIX RetainedHost [w1-14 §4] | `@agency-agency/openui` | GPUIX host stays in dotfiles as the Linux reference; the interface and the DOM host go |
| F4 | LauncherProvider contract, `RootProvider`/`RootItem` registry, prefix router, entrypoint-id grammar, shortcut catalogue | `pkgs/gpuix-shell/src/launcher/provider.ts`, `src/registry.ts`, `ui/shortcuts.ts` [w1-36 §4.3, w1-14 §4] | `@agency-agency/commands` | providers that spawn processes stay in the Linux adapter |
| F5 | Fuzzy (herdr-bar constants + golden corpus), frecency (Vicinae formula), MRU (cap 120, never-first rule), pin store (pure TS) | ports of `herdr-bar/src/{fuzzy,mru}.rs`, `root-item-manager.cpp` formula [w1-23 §3.2, §5; w1-35 §5] | `@agency-agency/commands` | storage backend injected, never `bun:sqlite` in core; replay `tests/data/fuzz-corpus.jsonl` as the golden test |
| F6 | Status vocabulary, glyph and rank tables, herdr generated types, rail row model, attention rule | `shared/herdr-api.generated.ts`, tonight's `core/rail.ts`, `core/attention.ts` [w1-16 §2, w1-19 §3B, w1-23 §3.2–§3.3] | `@agency-agency/herdr-types` (or herdr-web-ui's own `lib/`) | one source for web, kit and shell; herdr-web-ui already carries it |
| F7 | Operation definitions, verb classes (READ/WRITE/ACTION/SECRET), receipts (`confirmed / failed / unknown`, actor), error vocabulary (NOT_FOUND … INTERNAL), `replaySafe` tagging | tonight's `core/ops.ts` [w1-12 §3.1, w1-29 §3.6, §5 S06 rows] | `@agency-agency/commands` | the socket transport stays home |
| F8 | Vicinae-compatible extension vocabulary: `jsx.d.ts` wire tree, manifest zod schema, reconciler port, `Icon` ids, `Keyboard.Shortcut.Common`, `Cache`, script-command parser with its 7 test suites ported | tonight's `@gpuix-shell/api` [w1-36 §3.1–§3.7, §5] | `@agency-agency/extension-host` | licence check first (ISC packages, GPL server; copy only from the ISC packages) [w1-36 G11] |
| F9 | React components without layer-shell: list row, section, search field, action panel, toast card, status glyph, progress fill, dialog, form fields, metadata block, markdown detail | tonight's `src/core/ui/*` [w1-11 §3, w1-36 §3.1, w1-23 §3.1 ui checklist] | `@agency-agency/ui-react` | every component passes the import fence; the kit takes them as specs |
| F10 | Design kit rules U-01..U-19, P-01..P-16 and the geometry constants (220/30/12/2/8, 56, 700×580, toasts 390/140/4, OSD bottom 96) | SHELLS-DIGEST / HANDOFF-B, BRIEF §3.3, DESIGN [w1-09 §3, w1-11 §3] | `@agency-agency/tokens` docs | constants become tokens, not literals |
| F11 | `fakehost` harness and the RetainedHost test pattern | kit `core/testing/fakehost.ts`, `tests/native.test.ts` [w1-14 §5] | `@agency-agency/testing` | already the kit's; align the shell's to it |
| F12 | Compositor smoke template (`runtime-test --render-node`, headless Sway, grim pixel asserts, `results.json`, evidence dir) | `tests/gpuix-shell/smoke_<surface>.py`, `smoke_noicd.py` lineage [w1-21 §5.6, w1-14 §5] | `@agency-agency/linux-adapter` (Linux-only) | reusable by any Sway user; not by Marwan or Frank |
| F13 | Linux providers: Sway IPC client, D-Bus notification server, UPower/logind/NM/BlueZ/PPD/MPRIS proxies with gpui-shell's interface tables, PipeWire privacy reader, clipboard store, Chrome native host, XDG apps parser | tonight's `src/platform/*` [w1-26, w1-23 §3.4, w1-36 §3.11] | `@agency-agency/linux-adapter` | only after Tom's personal policy (outputs, binds, hostnames, thresholds) is stripped into config |
| F14 | File model for the explorer (entries, sort, preview kinds, shelf, trash via `gio trash`, picker protocol) | tonight's `files/model.ts` [w1-20 §3, w1-36 §3.1 `Action.Trash`, BRIEF §3.2] | `@agency-agency/files` | R21 lists "files" as a tray/dock app; the window stays home, the model goes (INFERRED) |
| F15 | `MusicBackend` interface, Subsonic/OpenSubsonic client types and mapping, re-ranking of `search3`, the music provider | tonight's `src/music/{types,subsonic/*}` [BRIEF §5, MUSIC.md] | `@agency-agency/commands` extras | credentials, mpv, MPRIS and the daemon stay home |
| F16 | Chrome bridge protocol types (`browser/init`, `browser/tabs-changed`, `browser/focus-tab`, `browser/close-tab`, framing) | tonight's `platform/linux/chrome-host.ts` [w1-36 §3.11] | `@agency-agency/linux-adapter` | the macOS kit would need its own host path; types only are neutral |

Not to extract, ever: palettes with Claude names, Anthropic fonts, `home/dot_config/sway/*`,
`home/dot_local/bin/*`, the Nix module, the systemd units, the `shell.sock` protocol and its
`dmenu` verb, Tom's slot policy, keybinds, hostnames, the model endpoint, the curated launcher
catalogue [R15, R31, R37, R44].

---

## 7. Open conflicts resolved tonight (each logged in ASSUMPTIONS.md)

| Conflict | Resolution tonight | Grounding |
|---|---|---|
| "files" is both a BRIEF shell surface and a tray/dock utility in R21 | build the window in dotfiles with a platform-neutral model (F14) | [w1-12 §2.1, BRIEF §3.2] INFERRED |
| "SEPARATE project" (R9) could mean a separate repo from dotfiles | it means separate from the agency kit; the shell stays in dotfiles | R17, R21 INFERRED |
| March "no control center" versus BRIEF `controls` | per-domain menus, no unified grid | [w1-29 §1.12, w1-30 §2.5] INFERRED |
| cliphist versus own clipboard store | own store per BRIEF §3.4 and SCOPE S-145, with cliphist's semantics (images, password skip, pins); a `cliphist list`-compatible import LATER | [w1-29 #86, w1-30 #86, G5] INFERRED |
| Chrome tab bridge: reuse Vicinae's extension or ship one | reuse the published extension, own native host under the same name; whether it is installed on the Zenbook is unverified | [w1-36 §3.11, G4] |
| MCP codemode: shell or utilities | utilities (C); the shell exposes none | R32 |
| Where the `ask` vocabulary lives | shell-private; validator/adapter/stream shared; no remote model fallback | [w1-24 §3, §6 item 16] INFERRED |
| Polkit agent, SNI tray, BlueZ Agent1, NM SecretAgent, lock screen | deferred; recorded as gaps with their D-Bus seams and single-owner bus-name rule | [w1-29 #216/#29/#152/#147/#203, w1-26, w1-23 §3.4, SCOPE S-189/S-168/S-188] |
| Music lane ownership | shell-side daemon, mpv, MPRIS and credentials; provider contract and client types extractable | MUSIC.md INFERRED |
| Import-fence enforcement | a grep-based `bun test` over `src/core`, wired into Nix `checks` | [w1-12 §7, w1-21 §5] INFERRED |
| Smoke test naming (`tests/native-compositor.py` in w1-14 vs `tests/gpuix-shell/smoke_<surface>.py` in SCOPE S-011/BRIEF §4) | SCOPE's names; `test_*.py` stays reserved for hermetic unittest in a flake check | [w1-21 gap 18] |
| "one window per process" (BRIEF §3.2) vs one window per renderer, several renderers per process (w1-15) | the wrapper allows several renderers; one process per surface family stays the default because long-run stability of two GPUI apps in one process is unverified | [w1-15 §3.4, SCOPE S-001] INFERRED |
| Vicinae extension story vs "no plugin browser" (R44) | extensions are Nix-declared files, no runtime store, no enable UI; the host is the shell's extension story and OpenUI programs are the model's | [w1-36 §3.10, §4.7, R44] INFERRED |
| Toast anchor: Tom's 2026-10-11 "top and center not top right" (mako) vs BRIEF/DESIGN A-15 top-right vs SCOPE §3 top-centre | personal composition, not a boundary question: a `layout.toast.anchor` config key exists; DESIGN A-15 and SCOPE §3 currently disagree on the default and the integrator must pick one (this document does not) | [w1-35 §6.4, w1-36 G13, DESIGN A-15] |
| `Clipboard.paste` / `Action.Paste` with the input server off | copy plus HUD; `wtype` only if Tom later allows injection | [w1-36 G7, SCOPE S-147] INFERRED |
| Model id source: `~/.config/substrate/models.toml` (fleet) vs `~/.config/gpuix-shell/model.json` (w1-24) | the shell reads its own runtime file; the fleet file stays `pi`'s | [w1-24 §2 recommendation] INFERRED |

---

## 8. What this pass left unverified

Per the workflow rule (light verification, log what was not checked):

- No independent verifier ran on this document; every quote was taken from the wave-1 notes'
  transcriptions, and the notes mark some of those REPORTED rather than re-opened at the JSONL line
  (w1-12 §6, w1-36 §2 "REPORTED" rows). R3–R5 and R26–R28 were cross-checked between two notes
  each; R6–R11 rest on w1-07/w1-08/w1-09 alone.
- The §3 owner column is my judgement against the one-line test; the FP/BOUNDARIES matrix
  [w1-12 §3.1] was the template, and every row absent from that matrix (extension host, Chrome
  bridge, music lane, cheatsheet, GPUIX runtime facts, Omarchy fleet) is INFERRED placement.
- Whether the kit's `apps/chat/herdr-types.ts`, herdr-web-ui's `lib/*.ts` and tonight's
  `shared/herdr-api.generated.ts` are byte-compatible was not checked; F6 assumes one source can
  serve all three.
- Licences: Vicinae's root GPL-3.0, its TypeScript packages' ISC and `src/server/LICENSE` (BSD-style)
  were read by w1-36 but not by me; F8 and rule 10 depend on that reading.
- Nothing was run: no import-fence test exists yet, no smoke was executed, no Chrome extension
  presence was checked on the Zenbook.
