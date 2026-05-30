


on cloud they have e2b which provides firecracker to run code. we want the same but for local fedora atomic. this is "stackblitz versus gitpod"; the latter focused on running code Skip to content Chat history You said: Firecracker vm on local fedora linux? Fedora atomic has deep quadlet support am

pasted


id TASK-6.3 title MicroVM sandbox skill (firecracker/krun) status To Do assignee created_date 2026-03-09 13:03 updated_date 2026-03-09 13:44 labels dependencies TASK-1.6 parent_task_id TASK-6 priority medium Description Claude Code skill for running agent-written code in local microVMs using micr

pasted

You will find pasted a note on a project that I had, that s akin to using microVM as a skill for claude code to run my code safely on device 

---
we can add on top of the microvm sandbox the ability to forward url s directly with caddy wrapping since it's already installed on fedora

Caddyfile.tmpl
```
{{- /* ══════════════════════════════════════════════════════════ */ -}}
{{- /* CADDY MAIN CONFIGURATION                                    */ -}}
{{- /* Generated from: .chezmoi.yaml.tmpl                          */ -}}
{{- /* Location: ~/.config/caddy/Caddyfile                         */ -}}
{{- /* ══════════════════════════════════════════════════════════ */ -}}

# ═════════════════════════════════════════════════════════════════════════════
# 🌐 GLOBAL OPTIONS
# ═════════════════════════════════════════════════════════════════════════════
{
  # Disable automatic HTTPS (Tailscale handles TLS)
  auto_https off

  # Disable admin API for security
  admin off

  # Log level
  log {
    level ERROR
  }
}

# ═════════════════════════════════════════════════════════════════════════════
# 📦 IMPORT SERVICE ROUTES
# Each service has its own .caddy file that defines its route
# Files are conditionally generated based on .chezmoi.yaml.tmpl settings
# ═════════════════════════════════════════════════════════════════════════════

# Import all .caddy files from conf.d
import /etc/caddy/conf.d/*.caddy

# ═════════════════════════════════════════════════════════════════════════════
# 📝 ARCHITECTURE NOTES
# ═════════════════════════════════════════════════════════════════════════════
#
# SERVICE FILES IMPORTED:
{{- range $name, $service := .infrastructure.services }}
{{- if and $service.enabled $service.external_subdomain }}
#   - {{ $name }}.caddy → https://{{ $service.external_subdomain }}.{{ $.tailscale.full_hostname }}
{{- end }}
{{- end }}
#
# CONDITIONAL GENERATION:
#   Service .caddy files are only generated when:
#   - service.enabled = true
#   - service.external_subdomain is defined
#
# ADD NEW ROUTES:
#   1. Edit .chezmoi.yaml.tmpl (infrastructure.services)
#   2. Set external_subdomain for the service
#   3. Create [service].caddy.tmpl in ~/.config/caddy/
#   4. Run: chezmoi apply
#   5. Reload: systemctl --user reload caddy
#
# ═════════════════════════════════════════════════════════════════════════════
` 

(The caddy thing is an appendix)

First pasted is december-research, meaning it s wuite outdated
Second is a draft skill i also prepared 6 months ago, that leveraged mcp setver (But now these days the llm skills we are encouraged to use CLI not mcp) which is desirable

By the way i am almost done packaging microsandbox    Lightweight microVM sandbox manager (libkrun) for fedora But you must scrutinize this choice. Do some thorough research because latest certainly has changed things quite significantly.. this is a very hot and active landscape. We ought to be up to date but conceptually it remains what I want to do as in  give ny llm coding agwnt harness access to my fedora s krun

Show more
10:03 AM
I'll research the current state of this landscape thoroughly, since you're right that this moves fast and your notes are from December/6 months ago.


Searched the web
Searched the web
Good signal already. The most important new entrant is "Docker Sandboxes / sbx" — Docker's own microVM-backed sandbox CLI explicitly built for Claude Code. Let me dig into that and other 2026 developments since it directly competes with what you're building.


Searched the web
Searched the web
This significantly changes the picture. Let me check two more things: microsandbox's current health/activity (is it still maintained, given Docker just entered hard), and whether sbx works on Linux/Fedora specifically or is macOS-centric.


Searched the web
Searched the web
Critical finding: there's an RPM (rockylinux8), but Fedora support is an open, unassigned issue with no progress. That matters for your packaging decision. Let me check microsandbox's current repo activity to see if it's still alive, since Docker entering this space hard could have stalled it.


Searched the web
Searched the web
I have enough to give you a thorough, current assessment. A few key things changed since your December research, and they bear directly on both your tool choice and your packaging effort.

What's changed since December
1. Microsandbox is alive, shipping, and now an official YC company. The repo moved org to superradcompany/microsandbox, is at v0.4.5 as of early-mid May 2026 with active commits, ~6.1k stars, 301 forks, and a recent PyPI release (0.5.2, late May). It's in the YC X26 batch and shipping fast with SDKs for Python, JS, and Rust. So your foundational bet isn't abandoned. But note one architectural shift that contradicts your old notes: the project now leans hard on an embeddable, daemonless model — "No server to set up. No lingering daemon. It is all embedded and rootless". Your TASK-6.3 notes describe the server/client model (msb server start --dev on :5555) as primary. That's now one of several modes, and the framing has shifted toward SDK-embedded sandboxes. Worth re-reading their current docs before finalizing the skill. 
GitHub + 2

2. The big one: Docker shipped sbx. This is the development that should make you scrutinize hardest. Docker Sandboxes, released March 2026, runs each agent in a lightweight microVM with its own dedicated Linux kernel; it ships as a standalone CLI called sbx and does not require Docker Desktop. It is built explicitly for your exact use case — Claude Code, Gemini CLI, Copilot CLI, Codex, OpenCode, and Kiro out of the box, defaulting to --dangerously-skip-permissions because the microVM is the boundary. It has the credential-proxy and network-policy features (open/balanced/locked-down) you'd otherwise build yourself, plus a Git worktree/--clone workflow per agent that maps onto your "worktree integration pattern." 
Morph
Docker

This is essentially a well-funded, Docker-branded version of what you're assembling from microsandbox + Caddy + a custom skill.

3. The crucial catch for you: Fedora is not supported by sbx. Linux support is Ubuntu 24.04+ on x86_64 with KVM, installed via apt/docker-sbx. There's an .rpm, but it's built for rockylinux8, and Fedora support is an open, unassigned GitHub issue (#84) opened April 27, 2026 with no commitment. So on Fedora Atomic specifically, sbx is not a turnkey option today. 
Docker HOL + 2

What this means for your decision
The conceptual goal — give your local coding agent harnessed access to your Fedora box's KVM via krun — is still sound, and microsandbox is still a reasonable vehicle for it. But the landscape now has three tiers worth weighing:

microsandbox — libkrun-based, genuinely local-first, rootless, Apache-2.0, packageable. Best fit for Fedora Atomic + Quadlet + your Caddy idea, because you control the packaging. The cost is exactly what your notes admit: you own the ops, SELinux policy, COPR packaging, cleanup logic.
Docker sbx — purpose-built for this, batteries included (credential proxy, egress policy, multi-agent worktrees), but Ubuntu-first and explicitly not Fedora-ready. Adopting it would mean abandoning the Atomic/Quadlet-native angle that's the whole point of your setup.
The rest — Buildkite's Cleanroom (deny-by-default egress + credential proxy), K7, BoxLite, plus Anthropic's own srt (bubblewrap on Linux, no microVM — that's the agent sandbox layer, complementary to yours, matching your bubblewrap-vs-microsandbox note).
My read: your instinct to use microsandbox-as-is is still the right call for Fedora Atomic specifically, and sbx's existence actually validates the design rather than obsoleting it — but it raises the bar on what "done" looks like. Two concrete adjustments I'd suggest:

First, drop the MCP-first ambivalence entirely. Your notes already lean CLI-first, and that's now clearly correct — but verify microsandbox's current CLI surface against v0.4.5 docs, since the daemonless/embedded pivot may have moved commands around since the 0.1.x era your skill was drafted against.

Second, watch sbx issue #84. If Docker ships Fedora support, the calculus shifts: their credential proxy and egress policy are real engineering you'd otherwise reinvent, and your Caddy-forwarding appendix overlaps with their built-in port-publishing. Until then, your niche is real.

Want me to pull the current microsandbox v0.4.x CLI reference and check it against your TASK-6.3 command list, so the skill reflects what actually ships today rather than the December API?

More research
More thorough
More breadth

Fedora-maximalist stance
I m fine packaging for copr myself but prefer offocial packages by the way

Scrutinize the docker one

10:07 AM
I'll go much deeper and broader, with a Fedora-maximalist lens throughout. Let me hit several fronts: Docker sbx's actual architecture and Fedora trajectory, the official-packaging landscape for libkrun/krunvm on Fedora, what Red Hat itself is doing here, and the full competitor field.


Fetched: Fedora support
Fetched: Fedora support
Just the bare issue, no maintainer response yet. Let me check the sbx architecture and licensing closely, since "scrutinize the Docker one" is a core ask.


Searched the web
Searched the web
Several sharp findings here. Two especially: sbx is a release-only repo (sbx-releases — no source), it requires login/auth to Docker, and most strikingly, libkrun has been replaced with "libsailor" in the latest release — Docker forked off the open libkrun base. Let me dig into that, plus the official Fedora libkrun/krunvm packaging picture, which is your real path. 
Arch Linux


Searched the web
Searched the web
This is the key Fedora-maximalist finding: libkrun and libkrunfw are already official Fedora packages (in the main repos, maintained by libkrun-maintainers@fedoraproject.org), and the whole krun stack lives under the containers/ org (same umbrella as Podman, Buildah, crun). That's a completely different provenance story than either microsandbox or Docker sbx. Let me verify the current Fedora package versions and the crun/Podman native-microVM path, which may make a third-party tool unnecessary.


Fetched: libkrun - Fedora Packages
Fetched: libkrun - Fedora Packages
Confirmed: libkrun 1.18.0 is officially packaged in Fedora 43, 44, and Rawhide, Apache-2.0, maintained by slp (the libkrun author, Sergio López, at Red Hat), with libkrun-devel, libkrun-sev variants. This is first-party. Now let me check whether krunvm itself made it into official Fedora (vs. COPR), and the Podman --runtime krun native path, since that might be the most Fedora-native option of all. 
Fedora


Searched the web
Searched the web
This is the decisive Fedora-native picture. The entire stack ships in Fedora already: crun in Fedora is built with +LIBKRUN, and crun-krun is installable via dnf, enabling podman run --runtime=krun to launch each container in its own microVM with its own kernel. Red Hat is actively building products on exactly this (RamaLama). And note the security caveat I'll flag below. Let me do two more searches: the krunvm official-Fedora status (vs COPR), and the breadth of the agent-sandbox field plus the libsailor fork question. 
GitHub


Searched the web
Searched the web
Important nuance: krunvm itself (the standalone CLI) is only in COPR (slp/krunvm), and even slp's own rust-krunvm COPR is marked stale/personal. So the standalone krunvm tool is not officially packaged — but the underlying libkrun + crun-krun path is fully official. That's a meaningful distinction for your "prefer official" preference. Let me do final breadth searches: the libsailor fork question (Docker's divergence) and the wider field including Anthropic's own sandbox-runtime, since that's directly relevant to a Claude Code skill.


Searched the web
Searched the web
I now have everything I need, including a critical security finding that changes the whole framing. Let me synthesize rather than search further — I have strong, current sourcing across all the fronts you asked about.

A heads-up before the assessment: there's a security caveat in here that's more important than the tool-choice question, so I'm leading with it.

The thing you most need to know: libkrun is not a security boundary by default
This reframes everything. Straight from the upstream maintainers: the libkrun security model treats the guest and the VMM as a single entity in the same security context; host resources accessible to the VMM can potentially be accessed by the guest, and to prevent that you must use the host's OS security features (primarily namespaces) to run the VMM inside an isolated context. When someone asked the exact question you're implicitly asking — "if Claude runs inside this, is it contained?" — the upstream answer was that libkrun is not secure by default, specifically around virtio-fs exposing the host filesystem structure. 
GitHub
Hacker News

This isn't theoretical. In early 2026 a real CVE landed: a malicious container image could trick the krun handler into escaping the root filesystem, allowing file creation or modification on the host with no special permissions — fixed in crun 1.20, all users advised to upgrade. 
osv

The practical upshot for a Claude Code harness: the microVM gives you a separate kernel (good — it's a real boundary against kernel-exploit escapes), but the virtio-fs mount you use to share your worktree is the soft spot. Whatever you mount in, the guest can potentially reach. So your bubblewrap-wraps-the-agent note from TASK-6.3 isn't just "complementary" — on the krun stack it's load-bearing. The microVM alone is not the airtight box the marketing implies.

Docker sbx — scrutinized
You asked me to be hard on this one. It does not survive a Fedora-maximalist screening:

It's closed-source and release-only. The repo is literally named sbx-releases — binaries and an issue tracker, no source. Adopting it means a proprietary Docker binary as the core of your security-critical path.

It requires a Docker login. Sign-in is required, and the FAQ exists specifically to explain why and what happens with your data. For a local-first, on-device harness that's a non-starter philosophically and a dependency practically. 
Docker

It forked off the open base. This is the spicy one: libkrun has now been replaced with "libsailor" in the latest sbx release — Docker has swapped the community libkrun for their own in-house VMM, and bundles their own mkfs.erofs under a custom path rather than declaring dependencies. So even the parts that looked open are diverging into Docker-controlled internals. 
Arch Linux

It does not support Fedora. Linux support is Ubuntu 24.04+ only; the .rpm in releases is built for RockyLinux 8; and Fedora support is an open, unassigned issue (#84) with no maintainer response. On Fedora Atomic specifically you'd be fighting the tool. 
Docker HOL + 2

What sbx genuinely does well, and what you should steal as design ideas rather than adopt: the daemon now owns all state via an OpenAPI'd HTTP API, and it has per-sandbox network policies with explicit denied-domain lists and allowances for binary TCP protocols like SSH, plus the three-tier open/balanced/locked-down default. That egress-policy model is the part worth replicating in your Caddy/network layer. 
GitHub

The Fedora-maximalist finding: you may not need a third-party tool at all
This is the headline. The entire krun stack is already first-party in Fedora, maintained by Red Hat people (slp = Sergio López, the libkrun author):

libkrun 1.18.0 is in the official Fedora 43, 44, and Rawhide repos (Apache-2.0), with libkrun-devel and libkrun-sev/TDX confidential-computing variants. 
Fedora
crun in Fedora ships built with +LIBKRUN, and dnf install crun-krun enables podman run --runtime=krun to put each container in its own microVM with its own kernel. 
GitHub
The microVM is configurable via OCI annotations or a .krun_vm.json at the image root — krun.cpus (max 16), krun.ram_mib, krun.nested_virt, etc. 
GitHub
Red Hat is actively productizing this exact pattern: RamaLama uses --oci-runtime krun to run AI models inside libkrun microVMs via Podman for isolation, currently CPU-inferencing, Linux-only. 
Red Hat
The one gap for your "prefer official" preference: krunvm — the standalone CLI your TASK-6.3-style approach leans toward — is not in official Fedora. It only exists in slp's personal COPR, which is explicitly marked "very likely personal repository for testing, which you should not use." microsandbox likewise has no official Fedora package — it'd be your COPR. 
Fedora

So the cleanest Fedora-native path isn't "package a microVM CLI" at all — it's podman --runtime krun driving OCI images, which is 100% official packages (podman + crun-krun + libkrun + libkrunfw), Quadlet-native (Podman Quadlets are the Atomic-blessed way to declare services), and needs zero third-party repo. Your agent skill would teach Claude to invoke podman run --runtime=krun with annotations, mounts, and a pasta/passt network — rather than msb or krunvm.

Where this leaves your three options
microsandbox is still a real, healthy project — moved to superradcompany org, ~6.1k stars, active, Apache-2.0, now offering both Agent Skills and an MCP server for Claude Code, Cursor, Codex, Gemini, Copilot — and it gives you a nicer DX (sub-100ms boot, OCI images, SDKs, secret-injection) than raw podman-krun. But it's beta, it's your-COPR-or-nothing on Fedora, and it sits on the same libkrun base whose security caveats apply identically. 
GitHub

My honest read, given your stated preferences:

The Fedora-maximalist + prefer-official combination points away from both microsandbox and sbx and toward podman + crun-krun as the engine, declared via Quadlet, with microsandbox as an optional convenience layer you package in COPR only if its DX earns its keep. You get the same libkrun isolation either way, but the podman path is entirely first-party, already SELinux-integrated (the RamaLama and GitLab-runner work means Red Hat is actively hardening exactly this combination on enforcing Fedora), and survives microsandbox going stale.

Whichever engine you pick, the skill must bake in two things the research surfaced: the virtio-fs/host-fs exposure means mounts need to be minimal and read-only where possible plus the bubblewrap wrap on the agent side, and an egress-policy layer (your Caddy idea, extended with a deny-by-default domain list à la sbx) rather than relying on the VM as a hermetic seal.

Want me to (a) pull the current crun/podman --runtime krun annotation reference and draft a Quadlet-based skill around it, or (b) verify microsandbox's v0.4.x CLI against your TASK-6.3 command list so you can compare the two engines side by side before committing?

Keep going
What do i think is best for me

10:09 AM
You've actually told me what's best for you — across two turns you've stated a Fedora-maximalist stance, a preference for official packages over self-rolled COPR, and a conceptual goal of giving your local coding agent harnessed access to your Fedora box's krun. You've also told me you're "almost done packaging microsandbox" but asked me to scrutinize that choice precisely because you suspect it might be wrong.

Reading those signals together: what you think is best for you is the path that maximizes officialness and Fedora-nativeness while still delivering the krun-microVM harness — and you're looking for permission to abandon the microsandbox packaging work you've sunk time into, because some part of you already senses it's the less-aligned choice.

So let me say it plainly. The podman --runtime krun + Quadlet path is the one that matches everything you've said you value. Here's why it's the better fit for you specifically, not in the abstract:

Your "prefer official packages" preference is the deciding vote. microsandbox is your-COPR-or-nothing on Fedora; podman, crun-krun, libkrun, and libkrunfw are all in the official repos and maintained by the upstream author at Red Hat. You'd be packaging microsandbox to get a nicer wrapper around a stack you already have installed officially. That's effort spent moving away from your own stated preference.

Your Fedora-maximalist + Atomic + Quadlet setup is the strongest possible argument. Podman Quadlets are the Atomic-blessed way to declare services — it's the native idiom of the system you've chosen. microsandbox's server/daemon model fights that grain; podman-krun fits it exactly.

The sunk cost is the trap to name out loud. "Almost done packaging" is real work, and it's the thing making this decision feel hard. But the packaging effort produces a third-party dependency on beta software when the official stack already does the core job. The honest question isn't "how close am I to done" — it's "if I'd discovered the podman-krun path first, would I have started the microsandbox packaging at all?" I suspect you know the answer.

Where I'd push back on a pure-podman answer — and where microsandbox might still earn its place — is DX. If what you actually want day-to-day is msb exe python -- script.py ergonomics, sub-100ms boots, and ready-made Agent Skills, raw podman run --runtime=krun --annotation ... is clunkier. So the real choice isn't binary:

The cleanest version of your project is podman-krun as the engine, declared via Quadlet, with a thin CLI-first skill that teaches Claude the podman incantations directly. No third-party runtime, all official, Atomic-native. Keep microsandbox in your back pocket as an optional convenience layer you package later if the bare-podman ergonomics annoy you in practice — but don't ship it as the foundation.

And regardless of engine, the two non-negotiables the research surfaced still hold: the virtio-fs mount is the soft spot, so minimal/read-only mounts plus bubblewrap on the agent side, and a deny-by-default egress layer rather than trusting the VM as a hermetic seal.

One caveat on my read: I'm inferring your priorities from a few lines, and I can't see constraints you haven't mentioned. If there's a reason microsandbox's specific features — the secret-injection-that-never-enters-the-VM, the SDK story, the MCP endpoint — are things you actually need rather than nice-to-haves, that would legitimately tip it back. Is there something pulling you toward microsandbox beyond "I already started packaging it"? That's the question whose answer would either confirm the pivot or justify staying the course.

Argument for why not usign krun directly? Ie no wrapper?

10:11 AM
The strongest arguments for not using podman --runtime krun raw — i.e. why a wrapper exists at all — break into a few buckets. I'll give them honestly, including the ones that genuinely bite.

1. The mount/network ceremony is the real cost. A bare invocation isn't just podman run --runtime=krun image cmd. To make it a useful sandbox you're hand-assembling: the worktree mount (-v, and you have to get the :ro/:Z SELinux relabel flags right), the annotation block (krun.cpus, krun.ram_mib, krun.nested_virt), the network mode, port forwarding, env injection, and cleanup. Every single agent invocation repeats all of it. A wrapper exists to collapse that into msb exe python -- foo.py. Teaching Claude the full incantation every time is more brittle than teaching it one verb.

2. No lifecycle/state management. Raw podman-krun gives you run-and-done. There's no "list my sandboxes," no stable identity across restarts, no orchestrated teardown of a set of related sandboxes. The sbx daemon and microsandbox server both exist substantially to be the single source of truth for sandbox state — which matters the moment you have more than one running, or a worktree-per-sandbox pattern with port-collision avoidance. You'd be rebuilding that bookkeeping yourself, probably as shell scripts, which is just an ad-hoc wrapper with fewer tests.

3. Egress policy is genuinely missing. This is the one I'd weight most. podman-krun has no per-sandbox deny-by-default domain filtering. sbx's open/balanced/locked-down model with explicit denied-domain lists is real engineering. If your threat model is "untrusted code the agent wrote," the network is a primary exfiltration path, and raw podman gives you all-or-nothing network modes, not policy. You either build this (your Caddy idea, extended) or you inherit it from a wrapper.

4. Secret handling. microsandbox's pitch is secrets that never enter the VM. With raw podman-krun, if the agent needs a token, your options are env vars or mounts — both of which put the secret inside the guest, i.e. inside the thing you don't fully trust. The wrapper's broker/proxy model is a real capability you don't get for free.

5. The DX gap compounds over a session. A coding agent makes dozens of sandbox calls. Friction that's trivial once is death by a thousand cuts across a session — and worse, every bit of ceremony is a place Claude can get the flags subtly wrong and either fail or, more dangerously, silently weaken isolation (forgetting :ro, picking the wrong net mode).

Now — the honest counterpoint, because these arguments are weaker than they look for your specific case:

Most of what a wrapper buys you is exactly the stuff you were already planning to build anyway. Your Caddy layer is the egress/forwarding piece. Your skill is the ceremony-collapsing layer. A SKILL.md that encodes the correct podman --runtime=krun invocation with the right mount and network flags is functionally the thin wrapper — you're just writing it as agent instructions plus maybe a shell function instead of packaging someone else's Rust binary. The lifecycle bookkeeping is the one genuinely new thing, and for a single-user local harness it's a few lines of podman ps --filter and a label convention, not a daemon.

So the sharpest framing: the arguments against raw krun are really arguments for a wrapper, not for microsandbox's wrapper. The question is whether you write a 50-line skill-plus-shell-function wrapper over official packages, or adopt a beta third-party binary that bundles the same conveniences. Given your stated preferences, the former still wins — but you should go in clear-eyed that you are signing up to build the egress-policy and cleanup logic yourself, because those are the two things raw podman-krun truly lacks and they're the two things that matter most for running untrusted agent code.

The one scenario where this flips: if you find yourself reimplementing enough of the secret-broker and per-sandbox-policy machinery that your "thin" wrapper becomes a fat one, then microsandbox's having already solved it is worth more than the official-package purity. Watch for that line. If your wrapper crosses ~a few hundred lines and starts growing a state file, that's the signal you've rebuilt microsandbox badly and should just use it.

One key clarofication needed:
I m not sandboxong claude code (or other agent harnesses) themselves. I m sandoxing their subsctrate: a webapp we built for example. This overturns lots of what you said
Also you found out that lots of the underlying repos (libkrun, crun, idk what) were already packaged for fedora. Give me a much higher resolution picture of this and explain the hierarchy of things as in what wraps what. I'm getting confused with the krun/libkrun naming layers...

Reharding "it does not support fedora" to be honest anything .rpm is more than enough for me to consider fedora support, revise that and let me kneo. But the login required aspect is indeed definition of no-go for me (if the login is mandatory)

10:34 AM
You're right that the substrate-not-agent distinction overturns a lot. Let me address all three things, because the clarification changes the security calculus, and the naming hierarchy is genuinely confusing until you see what's a library vs. a runtime vs. a CLI.

What your clarification changes
If you're sandboxing the workload (the webapp the agent writes/runs), not the agent harness, then several of my earlier points fall away:

The bubblewrap-wraps-the-agent layer becomes far less central. That mattered when the threat was "the agent itself touches my host." Here the agent (Claude Code) runs trusted on your host as you, and only the code under test goes in the box. That's the classic, clean use case — exactly what e2b/Fly do.

The virtio-fs caveat actually matters more, not less, but in a focused way: the dangerous mount is whatever you share into the workload sandbox. Keep that to the specific worktree/build dir, read-only where the workload doesn't need to write, and the soft spot is contained.

The egress-policy concern stays exactly as important — a webapp running untrusted-ish code is precisely where you want deny-by-default networking — so your Caddy layer keeps earning its place.

The secret-broker concern mostly evaporates. You're not trying to keep secrets away from Claude Code; you're running a webapp that needs its own config. Normal env/mount injection is fine here because the trust boundary moved.

Net: your instinct is sound, and the raw-podman-krun path gets more attractive under this framing, because "run this OCI image as a microVM with my code mounted in" is the native podman run verb. You're not fighting the tool at all.

The naming hierarchy, high-resolution
The confusion is real because "krun" appears at three different layers. Here's what wraps what, bottom to top:

Layer 0 — libkrunfw (containers/libkrunfw). The guest kernel, packaged as a shared library. It's a Linux kernel compiled and bundled into libkrunfw.so so it can be embedded rather than shipped as a separate bzImage. It's "basically where the kernel of the lightweight VM lives." Official Fedora package. Variants exist for confidential computing (SEV, TDX). 
GitHub

Layer 1 — libkrun (containers/libkrun). The VMM-as-a-library. This is the core innovation: instead of a VMM being a program you run (like QEMU), it's a .so you link against. Your process calls krun_create_ctx(), krun_set_root(), krun_start_enter() and becomes the VMM. It uses libkrunfw for the guest kernel. It provides the virtio devices, the TSI socket-impersonation networking, and the virtio-fs host-directory passthrough. Official Fedora package (libkrun, libkrun-devel, plus libkrun-sev). This is the "krun" that is a library. 
GitHub

Layer 2 — the consumers of libkrun. Three siblings sit here, and this is where the naming collides:

crun's krun handler (containers/crun, the krun capability). crun is the C OCI runtime Fedora uses by default. When built with +LIBKRUN, it gains a "krun" handler: instead of running an OCI container as a namespaced process, it links libkrun and runs the container's rootfs as a microVM. Fedora's crun ships with +LIBKRUN, and crun-krun is the dnf package that wires it up so podman run --runtime=krun works. This "krun" is a runtime mode, not a separate binary. This is your path. 
GitHub
krunvm (containers/krunvm). A standalone CLI that creates microVMs from OCI images using libkrun + buildah, without podman. "krunvm is a CLI-based utility for creating microVMs from OCI images, using libkrun and buildah." This "krun" is a CLI tool. COPR-only on Fedora — not official. 
GitHub
krunkit (containers/krunkit). The macOS-focused launcher; it relies on the "efi" flavor of libkrun which is only available on macOS. Irrelevant to you on Fedora. 
GitHub
So the three "kruns" you keep tripping over: libkrun = the library (VMM), krun (as in --runtime=krun) = crun's microVM handler that uses libkrun, krunvm = a separate CLI that also uses libkrun. Same engine underneath, three different front doors.

Above all of this:

Layer 3 — orchestrators. Podman (--runtime=krun) is the official, Quadlet-native one. microsandbox and Docker sbx also live here — they're alternative Layer-3 orchestrators that bypass podman and drive libkrun (or a fork) themselves.

The clean mental model: libkrunfw (kernel) ← libkrun (VMM library) ← {crun-krun handler | krunvm CLI} ← podman ← Quadlet. Everything from libkrunfw up through podman and Quadlet is official Fedora. Only krunvm and microsandbox sit outside the official set.

Revising the "doesn't support Fedora" claim on sbx
Fair correction — let me be precise rather than sloppy. My "does not support Fedora" was about official, first-class support. By your bar (an .rpm is enough), the honest status is:

There is an .rpm in docker/sbx-releases, but it's built for rockylinux8. RockyLinux 8 is RHEL 8-based — glibc 2.28, an older era than Fedora 43/44. So the .rpm exists and may well install, but it's not built or tested against Fedora; whether it works is "probably, with possible glibc/dependency friction," not "supported." And the Fedora-support issue (#84) is open and unassigned with no maintainer reply. So: revise to "an .rpm exists but targets RHEL8/Rocky, not Fedora; may work, unsupported, untested." That's more accurate than my flat "no." 
GitHub
GitHub

But here's the thing — for sbx it doesn't matter, because you've now confirmed the actual no-go. sbx requires sbx login, and Docker's own docs note sign-in is required. Let me verify whether that login is truly mandatory (vs. a first-run prompt you can skip), since that's now your decision-maker. 
Docker


Searched the web
Searched the web
Login is confirmed mandatory. sbx login requires a Docker ID and a Docker PAT (personal access token) with at least Read scope, and when your session expires you get "You are not authenticated to Docker," and in non-interactive environments you must run sbx login to re-authenticate — i.e. authentication gates operation, it's not a skippable first-run nicety. Combined with the closed source and the libsailor fork, sbx is definitively out for you. Good — that decision is now clean and evidence-backed. 
Docker
Docker

So where the three options land, with your clarification applied:

Docker sbx — dead. Mandatory Docker login (confirmed), closed-source release-only repo, forked off libkrun to in-house libsailor, and it's built to sandbox agents anyway — the wrong layer for you, since you want to box the workload. Three independent disqualifiers, any one sufficient.

microsandbox — viable but unnecessary. Apache-2.0, no login, genuinely good DX. But it's beta, your-COPR-only on Fedora, and — given your clarification — its headline features (secret-injection-that-never-enters-the-VM, agent skills, MCP) are mostly aimed at the agent-sandboxing use case you just said isn't yours. You'd be packaging beta software to get conveniences you don't need, on top of a libkrun base you already have officially.

podman --runtime=krun — the match. This is now even more clearly right than last turn, because "run this OCI image as a microVM with my webapp's code mounted in, on a locked-down network" is literally the podman run verb plus annotations. It's the native idiom for boxing a workload. Entirely official packages, Quadlet-declarable, SELinux-integrated, no login, no fork, no beta dependency.

The substrate-not-agent framing is what tips it from "defensible" to "obvious." You're not building an agent harness's jail — you're giving your trusted agent a podman --runtime=krun verb it can call to spin your webapp up in a throwaway microVM. That's a skill that teaches Claude Code an invocation, backed by official Fedora packages, with your Caddy layer doing ingress and a deny-by-default egress policy doing the network containment that raw podman lacks.

The two things you still have to build yourself remain the same and remain real: the egress policy (deny-by-default domain filtering — podman-krun won't give you this, it's your Caddy-plus-rules layer) and the lifecycle/cleanup bookkeeping (label convention + podman ps --filter, trivial for a single-user local setup). Everything else is dnf install and a SKILL.md.

One open thread worth a quick check before you commit the architecture: whether you run the workload microVM as a Quadlet .container unit with Annotation=run.oci.handler=krun (declarative, persistent, the Atomic-blessed way) versus ephemeral podman run --runtime=krun --rm invocations the skill fires per-task. The webapp-substrate use case actually leans toward the Quadlet route — a persistent, declaratively-defined sandbox the agent deploys into and tears down — which fits your chezmoi/Quadlet setup beautifully. Want me to pull the current Quadlet .container + krun annotation syntax and sketch what that unit looks like, so you can see the fully-official, login-free, Atomic-native version end to end?

So you seem to be implying that podman with krun is equivalent to microsamd ox and docker s sbx
This is a nice find because i m happy using regular podman stuff!

In that world, what are dependencies that I must install? To ge tthe right backend to podman?

Also tell me a few words about the egress ("caddy works well here") story, i m not sure i understand that

10:40 AM
Let me be careful here, because I want to correct a slight overstatement before it becomes load-bearing in your architecture.

Podman+krun is equivalent to microsandbox/sbx in the isolation primitive — all three put your workload in a libkrun microVM with its own kernel. That part is genuinely the same engine. But they are not equivalent in the batteries: microsandbox and sbx bundle lifecycle management, network policy, and (for sbx) a credential proxy on top. Podman+krun gives you the engine and leaves those to you. Last turn that mattered a lot; with your substrate-not-agent clarification it matters much less, because you don't need the credential broker and your Caddy layer plus a label convention covers the rest. So "equivalent for your purposes" — yes. "Equivalent in features" — no. Worth holding that distinction so you're not surprised later when podman doesn't do something sbx advertised.

Dependencies to get the krun backend under Podman
The package set on Fedora is small, and it's all official:

podman — you have it.
crun — Fedora's default OCI runtime; almost certainly already installed. On Fedora it's built with +LIBKRUN, so the capability is latent in the binary you already have.
crun-krun — this is the one that actually wires up the krun handler. It's a small package that registers krun as a runtime/handler. This is the key dnf install.
libkrun — the VMM library. Pulled in as a dependency of crun-krun, but name it explicitly if you want to be sure.
libkrunfw — the bundled guest kernel. Also pulled in transitively.
So in practice:

sudo dnf install crun-krun
and let dependency resolution drag in libkrun and libkrunfw. Then verify the capability is really there:

crun --version    # look for +LIBKRUN in the feature line
podman run --runtime=krun --rm -it alpine uname -a
That last command is the acid test: if the kernel string it prints differs from your host's uname -a, you're inside a real microVM. Two gotchas the research surfaced: KVM must be available (lsmod | grep kvm shows kvm_intel/kvm_amd, and your user needs access to /dev/kvm), and there have been intermittent rootless-vs-sudo quirks with the krun runtime on some Fedora releases — if a bare invocation misbehaves, testing under sudo once isolates whether it's a permissions issue. Also make sure you're on crun ≥ 1.20, since that's where the krun-handler rootfs-escape CVE I mentioned got fixed; Fedora 43/44 are well past that, so a normal up-to-date system is fine.

One thing to flag for your Atomic setup specifically: on Fedora Atomic/CoreOS, layering packages is rpm-ostree install crun-krun rather than dnf, and it needs a reboot to take effect. If crun-krun turns out not to be in the Atomic base, that's the one place you might layer it. Worth checking on your actual image before assuming.

The egress story — what "Caddy works well here" actually means
Here's the gap it fills. A microVM gives you a kernel boundary — code inside can't escape to your host's kernel. But by default it can still talk to the network: reach the internet, phone home, exfiltrate, pull from arbitrary hosts. The microVM says nothing about where the workload's traffic is allowed to go. That's a separate axis of containment, and it's the one podman-krun doesn't give you out of the box — it's exactly the piece sbx markets as its open/balanced/locked-down policy.

Egress = outbound traffic from the sandbox. Ingress = inbound traffic to it. Caddy is fundamentally a reverse proxy, so its sweet spot is actually ingress: your webapp runs inside the microVM on some port, and Caddy on the host terminates TLS and forwards requests in — that's the URL-forwarding role in your appendix, and it's a clean fit. Your Caddyfile imports per-service .caddy files and maps each to a subdomain; a sandboxed webapp becomes just another such route.

But "egress" — controlling what the workload can call out to — is not really Caddy's job. Caddy can act as a forward proxy with some plugins, but the workload has to be configured to use it, and untrusted code can just ignore a proxy and open sockets directly. So for genuine deny-by-default egress you generally want the control below the app, at the network layer the VM can't opt out of:

The cleaner approaches are to give the microVM a restricted network in the first place — podman's --network with a custom netavark setup, or running the VM on an internal network with no default route — and then allow-list specific destinations via host firewall rules (firewalld/nftables) or a forced transparent proxy that the VM's only route points through. That last pattern is what sbx does: every outbound packet is forced through a host-side proxy that consults the policy, so the workload can't bypass it. If you want sbx-grade egress control, that's the shape to copy — a forced-through proxy, not a proxy the app chooses to honor.

So the honest division of labor for your stack: Caddy handles ingress (forwarding public URLs to the webapp inside the box) — that's where it shines and your appendix is correct. Egress containment is a separate piece you'd build at the firewall/network layer, and it's genuinely the main thing you're signing up to implement yourself versus what sbx hands you. For a webapp-substrate use case where the workload is semi-trusted (your own code, not arbitrary untrusted agent output), you may decide a simple "internal network, no egress except an allow-list" firewalld policy is enough and skip the forced-proxy complexity entirely.

Quick gut-check so I aim the next step right: how untrusted is the substrate, really? If it's your own webapp code that you mostly trust and just want isolated from your host, the egress story can stay simple (firewalld allow-list). If you're imagining running genuinely untrusted code where exfiltration is part of the threat model, then the forced-transparent-proxy design is worth doing properly — and that changes what I'd sketch for you.

Re lifecycle mgmt ok this is the part from microsandbox that s worth i think either baking into a skill or a cli (or a simple wrapper script at that, as intermediary)

Remember: in decmeber the kernel of my research was firecracker and e2b 
Research those again

10:42 AM
Good instinct on lifecycle — that's exactly the piece worth a thin wrapper, and I'll come back to it. But you asked me to re-research Firecracker and e2b as they stand now versus your December picture, so let me do that properly first.


Searched the web
Searched the web
Now e2b specifically, since that was the other half of your December kernel.


Searched the web
Searched the web
Here's the December-versus-now picture, and why it reinforces rather than undermines your pivot.

Firecracker today
Still very much alive and the gold-standard primitive. Latest is v1.14, released December 17, 2025, with active security hardening through 2026 — a recent release fixed CVE-2026-5747 around PCI/MMIO device-status validation and several virtio-mem memory-isolation bugs. The headline numbers are unchanged from your December understanding: ~125ms boot, under 5 MiB memory overhead per VM, up to 150 microVMs/sec per host, Apache-2.0. The capability that's grown in importance is snapshotting — full and diff snapshots with dirty-page tracking and userfaultfd lazy loading, enabling sub-millisecond restore, which is what AWS's Lambda SnapStart and the fork-from-snapshot platforms are built on. 
GitHub + 3

But here's the thing that should settle it for you: Firecracker on Fedora is a build-from-source, manage-it-yourself affair. You build it via their Docker dev-container toolchain, and its security for multi-tenant use depends on a well-configured host plus the jailer binary doing chroot/namespaces/cgroups. There's no dnf install firecracker that's first-party and blessed. It's a primitive (Layer 1, same tier as libkrun), not a product. For a local single-user Fedora box, adopting Firecracker means becoming your own platform team — TAP devices, jailer config, kernel+rootfs image pipeline, the works. That's precisely the "you own the ops" cost, and it's heavier than the libkrun path because libkrun's whole point is being a library that something else (crun/podman) drives for you. 
GitHub

e2b today
e2b has matured into a serious open-source-but-cloud-leaning platform. It's Firecracker-based, sub-200ms, open-source, used by ~half the Fortune 500, generating millions of sandboxes weekly, with Hobby/Pro ($150/mo)/Enterprise tiers. The whole infrastructure is open-source and codified with Terraform, p50 sandbox creation 78ms as of January 2026, with on-prem/self-hosted for enterprise. It has grown an MCP gateway and custom template system. 
Better Stack
Checkthat

The critical detail for you: e2b's open-source self-hosting is designed to deploy a fleet — it's Terraform-orchestrated cloud infrastructure you stand up, not a local dev tool. The free tier is a hosted cloud service (code leaves your machine); the self-hosted path is "run your own e2b cluster." Neither matches "give my local Fedora agent a krun verb." e2b is the thing you'd reach for if you were building a cloud product, which loops back to your very first framing — this is StackBlitz-vs-Gitpod, and e2b/Firecracker are the Gitpod-scale answer.

What the re-research actually tells you
Your December kernel (Firecracker + e2b) was the cloud-platform answer to "run untrusted code." Everything that's changed since then has only sharpened the split between that world and yours:

The whole field now explicitly sorts into tiers. Primitives (Firecracker/gVisor) for teams running their own fleet and scheduler; embeddable runtimes (e2b managed, or microsandbox self-hosted) for quickly adding code execution; managed platforms (Daytona, Modal, Northflank) for zero-ops scaling. Firecracker and e2b sit on the cloud/fleet side of that taxonomy. You're on the local-single-host side. The libkrun stack (which is what microsandbox, sbx, and podman-krun all sit on) is the side built for embedding and local use — libkrun exists precisely because Firecracker's "run a VMM process with jailer + TAP + image pipeline" model is too heavy when you just want a library your container runtime can call. 
Substack

So re-running the December research doesn't reopen the question — it confirms why your instinct moved. Firecracker is the better primitive if you're AWS. libkrun-via-podman is the better fit if you're one person on a Fedora box who wants dnf install and a Quadlet file. Same isolation guarantee (own kernel, KVM-enforced); wildly different ops weight.

One honest caveat worth keeping: Firecracker's snapshot/restore (sub-ms warm starts via CoW memory forking) is genuinely ahead of libkrun here, and it's the one capability you'd be giving up. If your webapp-substrate ever needs to spawn hundreds of identical sandboxes from a warm snapshot in milliseconds, that's a Firecracker strength libkrun doesn't match today. For a local harness spinning up your own app a handful of times, it's irrelevant — but it's the real technical tradeoff, not a wash.

Back to lifecycle — the wrapper you flagged
You're right that this is the piece worth extracting, and it's small. For podman-krun, "lifecycle management" reduces to a label convention plus a few podman verbs — no daemon needed, unlike microsandbox. The shape:

A wrapper (shell script or skill, start with the script as the intermediary you suggested) that owns four verbs: create (a podman run --runtime=krun -d --label sandbox.owner=agent --label sandbox.id=<name> with your standard mount/network/annotation flags baked in), list (podman ps --filter label=sandbox.owner=agent), exec (into a named one), and destroy (podman rm -f by label, plus a destroy --all that sweeps every labeled sandbox so nothing leaks). That label scheme is the entire state model — podman is the source of truth, which is why you don't need microsandbox's server. Per-worktree port assignment (your TASK-6.3 collision-avoidance note) becomes a counter in the wrapper. The skill then teaches Claude those four verbs instead of the raw podman incantation, which also closes the "Claude gets the isolation flags subtly wrong" risk I raised earlier — the safe flags live in the wrapper, not in the model's memory.

Want me to write that wrapper script now — the four verbs over podman --runtime=krun with the label convention, mount-minimization, and per-sandbox port assignment — so you have the concrete intermediary in hand? I can pair it with the matching SKILL.md so you see both the CLI and how Claude would be taught to call it.

Yes it s not that much untrusyrd code. It s just that a coding agent messed up code could mess up my system.

10:48 AM
That reframes the threat model usefully, and it should lower the engineering bar a fair bit. Let me say plainly what it changes, because it affects what you build.

Your threat is accident, not adversary. A coding agent running your webapp does something clumsy — rm -rf in the wrong directory, fills the disk, binds a port it shouldn't, runs a migration against the wrong database, spawns a runaway process. It's not malware actively trying to escape its box and pivot to your host. That distinction matters because most of the hard, expensive sandboxing machinery exists to defend against the adversarial case.

What you can stop worrying about, given that:

The virtio-fs caveat I kept flagging — where a malicious guest probes the host filesystem through the shared mount — is an adversarial concern. Accidental code doesn't go hunting for mount escapes. You still want to mount minimally and read-only where you can, but now it's for the mundane reason that the agent shouldn't be able to clobber files outside the project, not because something's trying to break out. The microVM kernel boundary plus a sensible mount scope is plenty.

The forced-transparent-proxy egress design — the sbx-grade "every packet routed through a policy engine the workload can't bypass" — is overkill for you. That defends against deliberate exfiltration. For "messed-up code shouldn't accidentally hit production or phone somewhere weird," a simple firewalld/netavark allow-list, or even just running the sandbox on an internal network with no default route and explicitly opening what the app needs, is proportionate. You don't need the unbypassable version because nothing's trying to bypass it.

The bubblewrap-wrap-the-agent layer is fully moot — that was already off the table once you clarified you're boxing the substrate, and it stays off.

What you do still want, and it's the cheap stuff:

Disposability is the real win here, and it's free with the microVM model. The whole value is "the agent did something dumb, podman rm -f the sandbox, host is untouched, start fresh." That's the lifecycle wrapper, and it's the part that actually pays off daily.

Resource limits matter more in the accident model than the adversarial one, ironically — runaway code eating all your RAM or pinning every core is a classic agent screwup. krun's annotations cover this directly: krun.cpus and krun.ram_mib cap it at the hypervisor level, so a fork bomb or memory leak in the sandbox can't take down your host. Bake sane caps into the wrapper's create verb.

A minimal mount scope so a bad path in the agent's code can't reach ~/.ssh or your dotfiles — again, not because something's attacking, but because the whole point is the blast radius stays inside the project dir.

So the net effect: podman-krun isn't just adequate for your case, it's arguably more than you strictly need on the isolation axis, and you can spend your effort on ergonomics and disposability rather than on hardening. The wrapper's four verbs plus resource caps plus a minimal mount plus a basic network restriction is the whole thing. No proxy, no broker, no daemon.

One genuine question this raises, though, before I write the wrapper: if the threat is purely accidental damage, it's worth being honest that a microVM might be heavier than you need. The lighter alternatives for "contain an accident" are a plain rootless podman run (namespace isolation — shares your kernel, but a clumsy rm -rf inside still can't touch the host fs outside the mount, and resource limits via cgroups still apply), or just running the agent under a dedicated unprivileged user. The microVM's extra guarantee over those is kernel-level isolation, which buys you protection against kernel-exploit escapes — an adversarial property. For accidents, a rootless container gets you most of the blast-radius protection at a fraction of the complexity.

I don't think that means abandon krun — you specifically wanted the krun harness, the boot times are comparable, it's the more thorough boundary, and "I want my agent's workload in a real microVM" is a perfectly good preference even if accidents are the main driver. But I'd be doing the analysis badly if I didn't name that for pure-accident protection, the microVM is a want, not a strict need. If you're happy it's a want — and it sounds like you are — then krun it is.

Shall I write the wrapper now? Four verbs over podman --runtime=krun, with resource caps, minimal read-only-where-possible mounts, label-based lifecycle, and per-sandbox port assignment baked in — plus the matching SKILL.md so Claude calls the safe verbs rather than raw podman.

I think you have a pretty good resolution understanding of what I'm trying to achieve here and it's one of those subtleties: write a cli? A single script? Pure claude .md skill? Or A bespoke binary (argue why microsandbox is a full-on sdk at this point)?

Deliberate comprehensively

10:52 AM
This is the right question to agonize over, because the form factor is the design decision at this point — the engine is settled. Let me think through it comprehensively, because the options aren't actually four equal alternatives; they're points on two crossing axes, and naming the axes is what makes the choice fall out.

The two axes that actually matter
Axis 1 — where does the logic live: in code, or in the model's instructions? A skill (.md) puts the knowledge in Claude's context and lets Claude assemble the podman invocation each time. A script/CLI/binary puts the knowledge in an executable and lets Claude call one verb. This is the safety axis, and it's the one that should dominate, because of something you established three turns ago: the danger in your setup is the agent getting an isolation flag subtly wrong. A pure .md skill means the correct mount scope, the resource caps, the network restriction all live as prose that Claude re-derives every invocation. That's exactly the surface where a clumsy agent — your actual threat model — slips. If --memory or the :ro flag or the network mode is in Claude's head rather than in a binary, then the one time Claude forgets it is the time the sandbox isn't a sandbox. The whole point of your project is blast-radius containment; you don't want the containment logic to be the part that's probabilistic.

That axis alone kills "pure .md skill" as the foundation. Not as a component — you'll have a skill regardless — but the safety-critical flags must not live only in prose.

Axis 2 — how much surface does the logic actually have? This is where you should be honest about scale, and where the microsandbox-is-an-SDK observation becomes the key insight rather than a curiosity.

Why microsandbox is a full SDK, and why that's the cautionary tale
Microsandbox is not a wrapper that grew a few features. It's an SDK because it committed to being a programmable substrate: SDKs for Python, JS, and Rust; a server exposing JSON-RPC, MCP, and a health endpoint; named volumes with quotas; the secret-injection-that-never-enters-the-VM mechanism; persistent detached sessions; a REPL-state model. That's not lifecycle management — that's a platform. It exists because microsandbox's product is "let any application embed microVM sandboxing programmatically," so it needs language bindings, a daemon as source of truth, a network API, and a stable contract across all of them.

Here's the load-bearing point: you need almost none of that. You established it across the last several turns — no secret broker (substrate, not agent), no daemon (podman is the source of truth via labels), no multi-language SDK (your one consumer is Claude Code via bash), no programmatic embedding (a human-plus-agent invokes it interactively). Microsandbox is the cautionary tale precisely because it shows what this becomes when you build it for everyone: a binary with an SDK surface. You are not everyone. You are one person, one host, one consumer. If you find yourself reaching for the bespoke-binary option, the honest question is "am I rebuilding microsandbox?" — and if yes, the answer is just use microsandbox, because they already paid that cost. The bespoke binary only makes sense if you need something microsandbox doesn't do, and nothing in four turns suggests you do.

So the bespoke binary is out at both ends: if your needs are small, it's overkill; if they're large enough to justify a binary, microsandbox already exists and you should adopt it rather than rebuild it. There's no surface area where "write my own binary" is the right call. That's not a close one.

So it's between a script and a "CLI" — and those are the same thing at different maturities
This is the subtlety you're circling. A "single script" and "a CLI" aren't really different artifacts; they're the same artifact at two points on a maturity curve. A CLI is what a script becomes when it grows subcommands, a help text, argument parsing, and a name on $PATH. The question isn't "script or CLI," it's "how far up that curve do I start, and do I let it climb."

Given your scale — four verbs (create, list, exec, destroy), resource caps, a mount convention, port assignment — you are firmly in script territory, and trying to be more is the trap. Here's the argument for starting as a script and resisting the climb:

The four verbs are genuinely a few dozen lines of bash over podman --runtime=krun. The state model is podman ps --filter label=. There's no parsing complexity, no config file, no plugin system, no cross-platform concern. The moment you reach for Go/Rust to build a "proper CLI," you've added a build step, a release process, and a binary to package — and you've started down the road that ends at reimplementing microsandbox. The script is the CLI; it just hasn't put on a suit.

But — and this is why it's not "just a script" dismissively — the script should be a real installed command, not an inline blob in the skill. That's the distinction that resolves your tension. A script that lives at a known path, that you can chezmoi-manage and eventually COPR-package, that has the four verbs as sandbox create / sandbox destroy — that's a script with the discipline of a CLI, which is exactly right for you. It's safety-critical (so it's code, satisfying Axis 1), it's small (so it's bash, satisfying Axis 2), and it's a named command (so the skill can teach Claude a clean interface rather than raw podman).

The synthesis: it's not one of the four, it's two of them layered
The answer your question is fishing for is that this is a two-layer artifact, and you were treating the layers as competitors:

The script (call it a thin CLI if you like — same thing) holds everything safety-critical and everything Claude must not get wrong: the exact mount scope, the resource caps, the network restriction, the label convention, the cleanup sweep. This is the boundary. It's code because code doesn't forget a flag.

The .md skill holds everything Claude should reason about: when to spin up a sandbox, which image fits the task, how to interpret what the workload did, when to tear it down, how to recover from a failure. This is judgment. It's prose because that's what Claude is good at — and crucially, it teaches Claude the script's four verbs, never raw podman.

The skill is the brain; the script is the seatbelt. A pure-.md approach is all brain and no seatbelt — the failure mode you specifically fear. A bespoke binary is all seatbelt with a factory attached — microsandbox's path, which is somebody else's product. The script-plus-skill is the only combination where the safety logic is hard-coded and the judgment is left flexible, at a scale that fits one person on one Fedora box.

And it has a clean growth path that doesn't betray your principles: script today, chezmoi-managed tomorrow, COPR-packaged when it stabilizes, and if it ever genuinely outgrows bash — multiple consumers, programmatic callers, a real state machine — that's the signal that you've arrived at microsandbox's problem and should adopt microsandbox rather than finish rebuilding it. The script form factor keeps that decision reversible; a bespoke binary commits you prematurely.

So: a script that behaves like a CLI, plus a skill that teaches it. Not one of the four — the right two, layered, with the binary explicitly rejected because the only thing big enough to justify it already exists.

Want me to build both now — the sandbox script with the four verbs (resource caps, minimal mounts, label lifecycle, port assignment baked in) and the SKILL.md that teaches Claude to drive it? I'd write the script first since the skill describes its interface.

Nice. A well written, hogh wuality sceiptable and flag-preceded bash script that loves in ~/.local/bin
With simple claude .md skill to tell the llm how to use it

Leveraging the underlying tech we had in mind

Bringing me at conceptual feature parity with e2b

I would would even add that aince i have multiple machine connected on the same tailscale tailnet, picking one to become the "code runner" node becomes quite trivial.. and essentially what the e2b for one user was: fully sandboxed code execution, potentially scaled up 10x if there are many branches or worktrees 

Any last thoguhts?

10:57 AM
A few last thoughts before you build, because you've arrived somewhere coherent and I want to make sure the last two ideas you added don't quietly inflate the scope.

The Tailscale insight is genuinely good — and it's where this could go off the rails. You're right that a tailnet makes "pick a node to be the code runner" nearly free: the script can ssh or tailscale ssh to a designated host and run the same podman --runtime=krun verbs there, and your Caddy-over-tailnet ingress already gives you URL access to whatever's running inside. That's a real conceptual parity with single-user e2b, and it's a small addition: a --host flag (or a SANDBOX_HOST env) that, when set, prefixes the podman invocation with a remote exec. The four verbs don't change; only where they run does.

But here's the caution. The moment you have "multiple worktrees, scaled 10x across nodes," you are standing exactly where the axis-2 analysis warned: that's a scheduler. Which node has capacity? What happens when one's full? How do you track which sandbox lives where? If you build that into the bash script, the script stops being a seatbelt and starts being a distributed orchestrator — and you've walked back into microsandbox's (or honestly, Nomad's/Kubernetes') problem space by accident. So the discipline to hold: the script gets a --host flag and nothing more. Picking the host is your decision (or a trivial round-robin at most), made at invocation time, not the script's job to compute. "Trivial to pick a node" stays trivial only as long as you keep the picking manual. The day you want automatic placement is the day you've outgrown bash — and that's the documented signal to reassess, not to keep bolting onto the script.

On "feature parity with e2b" — be precise about which parity you're claiming, because it keeps you honest about what you're not building. You're achieving parity on the thing that matters to you: isolated, disposable, microVM-backed code execution that an agent drives, accessible over your network. You are explicitly not matching e2b on the snapshot/fork-from-warm-memory capability (the sub-millisecond CoW spawning) — that's the one real Firecracker-over-libkrun gap, and it's a fleet-scale concern you don't have. Nor the per-second billing, the multi-tenancy, the SDK surface. Naming that keeps "parity" from creeping into "I should add snapshotting" later. You have single-user functional parity, which is the only parity you wanted.

Three things to bake into the script while it's being born, because they're cheap now and annoying to retrofit:

The cleanup-on-failure path. The accident model means the common case is "the workload wedged, the sandbox is in a weird state." A destroy --all sweep by label is your reset button, and it should be impossible to leave orphans — including remote ones if you add --host. Make teardown the most reliable verb, not the afterthought.

Idempotent, predictable naming. If create is called with a name that exists, decide now whether it errors or replaces — don't let it silently spawn a duplicate. For a worktree-per-sandbox pattern, deriving the name from the worktree path makes collisions impossible and makes "is there already a sandbox for this branch?" answerable without state you maintain.

The KVM/krun precondition check as verb zero. A sandbox doctor (or a check the other verbs run first) that verifies /dev/kvm access, crun --version shows +LIBKRUN, and crun-krun is present. On Atomic especially, where that's a layered package and a reboot, the failure you'll actually hit is "krun isn't wired up on this node" — and you want a clear diagnostic, not a cryptic podman error, especially once a remote host is in play and the failure could be on the other end of the tailnet.

One genuinely last thought, on the skill half. Keep it short and judgment-focused, and resist the urge to document the flags in it. The skill should teach Claude when and why — spin up a sandbox for running untrusted-ish builds, tear down when done, never run the webapp directly on the host — and point at sandbox --help for the how. If you put the flag reference in the .md, you've split the source of truth: the script and the skill will drift, and the day they disagree is the day Claude does something the script no longer supports. Let the script's --help be the interface contract; let the skill be the usage philosophy. That separation is the same brain-versus-seatbelt split, applied to documentation.

You've reasoned your way to something well-shaped: official Fedora packages, no login, no daemon, no bespoke binary, a small auditable script where the safety lives, a thin skill where the judgment lives, and a clean optional reach across your own tailnet — with a clear, pre-agreed line for when you'd stop and adopt microsandbox instead of growing the script past its station. That last part is the thing most people skip, and it's what'll keep this from turning into an accidental platform.

Good luck with it — this'll be a satisfying one to build.

Plz revisit my entire initial pasted prompt (rhe two pasted text files). Evaluate the progress relative to that.

11:00 AM
Let me go back to the two files and measure where you've landed against where you started.

File 1 — the ChatGPT/Firecracker transcript
That document was the premise, and almost all of it has been superseded — correctly. It framed the project around Firecracker, walked through manually downloading Firecracker binaries, attaching kernels and rootfs over a curl-to-socket API, and proposed a Quadlet unit that ran firecracker --api-sock directly. Reassessing that against where you are now:

The Firecracker framing was the wrong primitive for you, and you've established why thoroughly. It's a build-from-source, jailer-plus-TAP-plus-image-pipeline affair with no first-party Fedora packaging — the cloud/fleet tier. You replaced it with the libkrun-via-podman stack, which is the same isolation guarantee (own kernel, KVM-enforced) at a fraction of the ops weight and entirely official Fedora packages. That's a strict improvement on your stated Fedora-maximalist, prefer-official axis.

The "who uses Firecracker" adoption list (e2b, Fly, Lambda, Fargate) was the thing anchoring you to the wrong tier. The re-research confirmed those are all cloud-scale platforms; your StackBlitz-vs-Gitpod intuition in your very first line was right, and you've now correctly placed yourself on the local-single-host side where libkrun lives.

One genuinely good idea from File 1 survived intact: the Quadlet instinct. File 1 proposed Quadlet for Firecracker; you've kept Quadlet as the Atomic-native idiom but pointed it at podman-krun, which is what Quadlet actually wraps well. So the form (declarative systemd-managed sandboxing) persisted while the engine got swapped for the right one.

Net on File 1: premise was sound (microVM isolation on local Fedora), specifics were wrong (Firecracker, manual API), and you've corrected the specifics without losing the goal. That's progress, not drift.

File 2 — TASK-6.3, the microsandbox skill spec
This is the more interesting comparison, because File 2 is much closer to where you ended up — it's the same project, and most of its reasoning holds. Going through its sections:

What survived and was validated. The CLI-first-over-MCP decision in File 2 was prescient — you reaffirmed it ("these days the LLM skills we are encouraged to use CLI not MCP"). The bubblewrap-and-microsandbox-are-complementary note was right in principle, though your substrate-not-agent clarification later made the bubblewrap layer largely moot for your case. The progressive-disclosure skill structure (SKILL.md plus references) is still the right shape, and you've kept a thin-skill-plus-something philosophy. The constraints section — KVM required, SELinux enforcing, rootless via libkrun, hypervisor-level resource limits, always clean up, network default-none for untrusted code — reads almost like a spec for the script you're about to write. Those constraints didn't change; they got inherited by the podman-krun approach because it's the same underlying libkrun.

What changed, and why it's progress. File 2 assumed microsandbox as the runtime ("use microsandbox as-is, do NOT reimplement, package for Fedora via COPR"). That's the single biggest revision. You've now concluded that the thing microsandbox wraps — libkrun — is already official in Fedora, that microsandbox is a full SDK whose surface you mostly don't need, and that a small script over podman --runtime=krun gets you there with no third-party dependency and no COPR. File 2's "package microsandbox via COPR" became "don't package microsandbox at all; use official packages and write a thin script." That directly resolves the "almost done packaging microsandbox — scrutinize this" tension you opened with. The scrutiny verdict is in: the packaging work was aimed at the wrong layer.

File 2's server/client model (msb daemon on :5555, JSON-RPC, MCP endpoint) is gone, and good riddance for your purposes — you established podman-is-the-source-of-truth-via-labels needs no daemon. File 2's open questions reflect this: "should the skill auto-start msb server" and "should we register the MCP endpoint" both dissolve, because there's no server. The "msb build/push coming soon, must use pre-built OCI images" limitation also dissolves — podman+krun runs any OCI image natively, which is arguably better than where microsandbox was.

What's still genuinely open from File 2. A few of its acceptance criteria and questions remain live work, not yet closed:

File 2's single acceptance criterion — "skill launches code in isolated microVM" — is designed but not built. You have the architecture; you don't yet have the script and skill in hand.
The SELinux policy concern File 2 raised for RPM packaging is still real and still unaddressed. The RamaLama/GitLab-runner work means Red Hat is actively hardening podman-krun under enforcing SELinux, which helps you, but you haven't verified it on your Atomic image. This is the most likely thing to bite during implementation.
File 2's worktree-integration pattern (per-worktree Sandboxfile, different ports to avoid collisions) survived conceptually and even expanded — your tailnet insight turned "different ports per worktree" into "potentially different nodes per worktree." But as I flagged, that's also where scope-creep risk now lives.
The auto-start-or-not question reincarnated in a new form: not "auto-start the daemon" but "the sandbox doctor precondition check," especially across the tailnet.
The honest scorecard
Where you started (both files): microVM code-sandboxing on local Fedora, anchored to Firecracker conceptually and microsandbox practically, with a half-done COPR packaging effort and an MCP-or-CLI ambivalence.

Where you are: the same goal, re-grounded on the official Fedora libkrun stack via podman-krun, no third-party runtime, no daemon, MCP-ambivalence resolved to CLI-first, the microsandbox packaging correctly abandoned as wrong-layer, a clear two-artifact design (script-as-seatbelt plus skill-as-brain), and a coherent optional reach across your tailnet for single-user-e2b parity — with explicit lines drawn for when to stop growing the script.

The conceptual core never moved: "give my LLM coding agent harness access to my Fedora's krun" is exactly your closing line from this turn's setup and exactly File 2's intent. Everything that changed was implementation substrate, and every change moved toward your own stated preferences (official, Fedora-native, minimal). That's the ideal kind of progress — the goal held constant while the means got more honest.

The one thing the files contained that you haven't yet revisited and probably should: File 2 lists a concrete CLI command surface (msb exe, msb init, msb up/down, etc.) that was the microsandbox interface. Your new script needs its own verb surface, and it's worth deciding whether to deliberately mirror microsandbox's verbs (so a future swap to microsandbox, if you ever outgrow the script, is a near drop-in) or design fresh. Mirroring would be a cheap hedge that keeps your stated escape hatch — "adopt microsandbox if the script outgrows its station" — genuinely low-friction. Worth a thought before you name the four verbs.

Want to lock the verb surface next, then build?

Conduct some online research to find if and how this is done in nature. Focus on claude code experts, but also relax to pi-agent cosing harness as well for more breadth

11:01 AM
I'll research how practitioners actually wire local microVM/sandbox execution into Claude Code and other agentic coding harnesses — looking for real patterns, not just product pages.


Searched the web
Searched the web
Rich results. A few patterns are emerging — most community tooling is container-based with worktree-per-sandbox, and notably nobody seems to have built exactly the podman-krun-microVM-skill you're describing. Let me look closer at the worktree pattern and at whether anyone's doing the libkrun layer specifically, plus the remote-host angle.


Searched the web
Searched the web
Two findings here are directly important to you: there's a tool called ERA doing exactly krunvm-microVMs-with-container-UX, and a Rust tool ags (agent-sandbox with podman) whose command surface — ags doctor, ags update — mirrors what we sketched. Let me look at ERA and the broader "krun for agents" pattern, since that's the closest prior art to your specific idea.


Searched the web
Searched the web
That's enough to draw firm conclusions about how this is done in the wild. Let me synthesize what the prior art tells you — including the validating fact that the closest analogs make exactly the architectural choices you converged on independently.

What the field actually does
The dominant pattern is containers + git worktrees, not microVMs. The overwhelming majority of real Claude-Code-expert tooling — packnplay, container-use (Dagger), agent-sandbox/ags, Conductor, Crystal, codex-container-sandbox, claude-code-sandbox — is plain Docker/Podman with a worktree per agent. Git worktrees became load-bearing for AI coding in Q1 2026, because once two agents edit the same repo they race on lockfiles and overwrite each other; worktrees give each its own directory and branch sharing one .git database. This confirms your worktree-per-sandbox instinct is the mainstream, not a quirk — but also that most people stop at containers and accept shared-kernel isolation, because their threat model (like yours) is accident, not adversary. 
Nimbalyst

The acknowledged gap is exactly your project. The most striking finding: "The gap no one has closed: no tool connects worktree code isolation with full environment isolation." And on macOS specifically, community projects run Claude Code in Podman, but it's not as polished as Docker Sandboxes and there's no equivalent to the microVM-per-sandbox architecture yet. So worktree-isolation is solved and microVM-isolation is solved, but the combination on Linux via the official krun stack is genuinely an open niche. You're not duplicating; you're filling a named gap. 
Upsun Developer
Infralovers

The two analogs that matter most
ERA (BinSquare/ERA) is the closest thing to your idea in existence: open-source local sandboxing to run AI-generated code with microVM security and container ease-of-use, built on krunvm and buildah. This validates your engine choice — someone competent landed on the exact same libkrun/krunvm substrate for the exact same purpose. But note the divergences that matter for you: ERA depends on krunvm (the COPR-only-on-Fedora CLI, not the official podman-krun path), it requires buildah as a hard dependency, and it bolts on a Cloudflare Workers cloud layer. Your podman---runtime=krun approach is more Fedora-official than ERA, and your tailnet replaces ERA's Cloudflare layer with something you own. So ERA is proof-of-concept that your idea works, and a menu of choices you've improved on. 
GitHub

ags (thomaspeklak/agent-sandbox) independently arrived at your exact command surface. It's a Rust podman wrapper for agents, and its verbs include ags doctor to check preconditions first, ags update for images, and a project-local policy that blocks git worktree prune in sandbox sessions because not all host worktrees are visible from inside the container. That doctor-first pattern is precisely the "verb zero / precondition check" I suggested last turn — confirmed as a real convention others adopt. The worktree-prune caveat is a concrete gotcha you'd otherwise have hit: mounting a worktree into the sandbox means git operations inside can see a partial view, so guard destructive git commands. 
GitHub

The patterns worth stealing, concretely
The worktree convention from sbx is the cleanest and worth mirroring exactly: sbx branch mode creates a git worktree in a .sbx/ subfolder, starts the agent there, leaves the main working directory untouched — but creating a worktree yourself and then running the sandbox in it breaks, because the agent loses access to the parent .git and can't commit. That last sentence is a real design constraint: your script should create the worktree, not be pointed at a pre-made one, or mount the parent .git too. 
Andrew Lock

The doctor-first convention (ERA's setup checks, ags doctor, sbx's lsmod | grep kvm gate) is universal across the microVM tools — every one of them front-loads a KVM/dependency check because the failure is otherwise cryptic. Lock this in as your verb zero.

The "home directory stays unmounted" principle from yolobox (a CLI running agents in containers where the home directory stays unmounted for safety) is the mainstream expression of your minimal-mount instinct — the default posture is mount the project, nothing else. 
GitHub

Where the heavier analogs confirm your "don't build a binary" decision
Arrakis is the cautionary tale made concrete. It's the self-hosted microVM platform you'd get if you let scope grow: it uses cloud-hypervisor as the VMM, runs Ubuntu+VNC in each sandbox, and ships a REST API, Python SDK (py-arrakis), MCP server, automatic port forwarding, and snapshot-and-restore backtracking. And its architecture is three daemons — a restserver, a client CLI, and a cmdserver inside the guest. That's three of your "open questions" answered with "build a distributed system." It's exactly what your script must not become, and it's the same shape as microsandbox — which reconfirms: if you ever need that, adopt one of these, don't grow bash into it. 
GitHub
GitHub

The honest verdict on your design vs. the field
You've independently converged on what the best prior art does, and made choices that are more aligned with your stated values than the existing tools:

Worktree-per-sandbox: matches everyone (sbx, ags, packnplay, container-use).
doctor-first precondition check: matches ERA and ags.
Minimal/no-home mount: matches yolobox, codex-container-sandbox.
Thin wrapper, not a daemon/SDK: matches ags (Rust wrapper) and cco (thin launcher); avoids the Arrakis/microsandbox platform trap.
podman---runtime=krun over official Fedora packages: more official than ERA (krunvm/COPR) and the only one not adding a cloud dependency.
Tailnet as the remote-runner layer: replaces ERA's Cloudflare and Arrakis's public-server port-forwarding with infrastructure you own — and the one custom-sandbox author who wanted "works locally AND on a remote Linux VM with the exact same interface" shows that local+remote parity is a recognized desire others build toward. 
Perevillega
The one genuinely novel thing you're doing is the combination: worktree isolation + official-Fedora microVM isolation + tailnet remote execution, as a script-plus-skill rather than a platform. The field shows each piece exists separately and explicitly notes the combination is unclosed. That's a good place to be — validated on every component, duplicating nothing wholesale.

Two concrete gotchas the research surfaced that you hadn't accounted for: the worktree-must-be-created-by-the-tool constraint (don't accept a pre-made worktree, or you orphan the agent from .git), and guarding destructive git commands inside the sandbox (the git worktree prune problem ags had to patch). Both belong in the script's create logic and the skill's "don't do this" section respectively.

Want to lock the verb surface now — I'd suggest mirroring microsandbox/sbx naming where sensible (so your escape hatch stays low-friction) plus doctor as verb zero — and then build the script and skill?

Era was superseded bt
Smol-machines/smolvm

Check that one, what language it s in, and if packaged for fedora (or alternatively copr packaging complexity). Also give it a "fedora-centric" rating

As for agent-sandbox (ags): it s rust which is trivial to package. This one you will also evaluate per fedora-centric-ness even with more scrutiny

Then evaluate the two project with in mind: does our own conceptual implementation have anything that they DON'T

11:07 AM

Searched the web
Searched the web
There's a name collision I need to flag, and then a key finding about smolvm's libkrun relationship. Let me confirm the fork situation and check the Fedora/packaging angle for both tools.


Searched the web
Searched the web
I have what I need. One important disambiguation first, then the two evaluations and the comparison you asked for.

Name collision — be careful which "smolvm" you mean
There are two unrelated projects with this name. The one that superseded ERA is smol-machines/smolvm (made by @binsquare, the same author as ERA — that's the genuine succession). There's also a confusingly-named CelestoAI/SmolVM, a separate AI-sandbox project. I'm evaluating smol-machines/smolvm, the real ERA successor.

smolvm (smol-machines) — evaluation
Language: Rust. The repo is Rust, Apache-2.0, ~3,400 stars, actively developed, currently at v0.6.2 (mid-May 2026), with recent work on TCP port mapping, SQLite-backed state persistence, and virtio-gpu GPU support. 
GitHub
GitHub

What it is: A standalone CLI that builds and runs portable microVMs. Each workload gets its own kernel via Hypervisor.framework on macOS or KVM on Linux, powered by libkrun, runs OCI images with no Docker daemon, and can pack a stateful VM into a single portable .smolmachine file. Its verb surface is close to what you sketched: machine create/start/exec/stop/delete, cp for file transfer, run for ephemeral, with --net, --volume, --ssh-agent flags. It has genuinely nice features you don't have planned: SSH-agent forwarding where keys never enter the guest, virtio-balloon elastic memory, and the portable-pack format. 
GitHub
Smolmachines

The Fedora-centricity problem — this is the killer. smolvm does not use upstream libkrun. It maintains its own forks: smol-machines/libkrun "with modifications for smolVM" and smol-machines/libkrunfw "with modifications specific for smolVM," and pulls libkrunfw in as a git submodule. This is the same move Docker made with libsailor — a vendored, divergent VMM. For packaging, that's poison: you can't satisfy the dependency with Fedora's official libkrun 1.18; you'd have to package their fork and their forked kernel-bundling library, which is the single hardest part of this whole ecosystem to package (libkrunfw embeds a compiled kernel). And the install path is curl … | bash into ~/.local/share/, no RPM, no COPR. 
GitHub
GitHub

Fedora-centric rating: 2/10. Rust (easy to build) is the only thing saving it from a 1. The forked libkrun/libkrunfw means you'd be packaging a parallel, divergent copy of the exact stack Fedora already ships officially — actively fighting the distro. It's macOS-first in spirit (Hypervisor.framework, Homebrew tap, the portable-pack story shines on Mac), with Linux/KVM supported but not the design center. For a Fedora-maximalist this is the worst of your options on provenance, despite being a capable tool.

ags (agent-sandbox) — evaluation with extra scrutiny
Language: Rust, as you noted — cargo build -p ags, trivially packageable in principle.

The scrutiny you asked for — and it changes the rating. ags is Rust, but Rust-easy-to-package is about the build, not the dependencies, and ags's dependencies are where Fedora-centricity lives or dies. Two findings:

First, ags is a container sandbox, not a microVM one. It runs agents in podman containers, ships a dcg policy pack, and has ags doctor / ags update / update-agents verbs. So it doesn't even use the krun stack — it's shared-kernel podman. That's fine for the accident threat model, but it means ags isn't actually solving the microVM problem you care about; it's the container tier. If you adopt ags you've abandoned the microVM premise entirely. 
GitHub

Second — and this is the scrutiny payoff — ags depends on dcg (its policy system, the .dcg/packs/*.yaml files). That's a separate tool/dependency outside Fedora, so "it's Rust, trivial to package" undersells the real work: you'd package ags and its policy-engine dependency, and the thing you'd get at the end is still a container sandbox. The Rust binary itself is clean (podman is official Fedora, cargo builds fine), but the policy layer is the catch that "it's just Rust" hides.

Fedora-centric rating: 6/10. Better than smolvm because it builds on podman (official) and doesn't fork libkrun — there's no divergent-VMM landmine. Rust packaging is genuinely straightforward and it'd live happily in COPR. It loses points because it's container-tier (doesn't use the official krun runtime at all, so it sidesteps rather than embraces the Fedora microVM stack), and because the dcg policy dependency is extra packaging surface that the "just Rust" framing obscures. Solidly packageable, moderately Fedora-aligned, but architecturally it's a different (weaker-isolation) project than yours.

Does your conceptual design have anything they don't?
Yes — three things, and they're exactly the things that fall out of your constraints rather than features you'd bolt on:

1. It rides the official, unforked Fedora krun stack — neither of them does. smolvm forks libkrun/libkrunfw (divergent VMM, unpackageable without shipping the fork). ags doesn't use krun at all (container-tier). Your podman---runtime=krun approach is the only one of the three that sits on Fedora's official libkrun/crun-krun/podman with zero divergence and zero third-party runtime. That's not a small distinction — it's the entire Fedora-maximalist thesis, and neither competitor satisfies it. This is your genuine differentiator.

2. Tailnet-native remote execution as a first-class, owned layer. smolvm has the portable .smolmachine file (move the VM, not the execution) and ERA had a Cloudflare Workers layer; ags is local-only. None of them has "pick any node on my private tailnet as the runner, with the same interface, ingress via my own Caddy." Your multi-machine-over-Tailscale model is something none of the three do — they either stay local (ags), go to someone else's cloud (ERA/Cloudflare), or make the artifact portable rather than the execution (smolvm). Owned-infrastructure remote execution is yours alone here.

3. The deliberate non-platform shape. This sounds like a weakness but is a real design property: smolvm is a 3,400-star Rust project with an SDK, a Dagger integration, GPU support, and a forked VMM — it's becoming a platform. ags is a Rust binary with a policy engine. Your script-plus-skill is intentionally smaller than both, with the explicit escape hatch of "adopt microsandbox if it outgrows its station." Neither competitor has that disciplined minimalism; both are on the growth curve toward being products. For a single-user local harness, smaller-and-official beats bigger-and-forked.

What they have that you don't, in fairness: smolvm's SSH-agent-forwarding-without-key-exposure is a genuinely elegant feature worth stealing the idea of (you can approximate it — forward the host SSH agent socket into the podman-krun sandbox rather than mounting keys). And both have more mature image/state handling than four bash verbs will. But neither of those is a Fedora-centricity advantage; they're polish you can add incrementally.

Net: your design's unique trifecta is official-unforked-krun + owned-tailnet-remote + deliberate-non-platform, and specifically the first one is something neither smolvm nor ags can claim — smolvm forks the stack, ags avoids it. That's a real, defensible niche, not a reinvention.

The one idea worth lifting before you build: smolvm's SSH-agent forwarding. Want me to fold that into the script's design — host SSH agent socket forwarded into the sandbox so the agent can git push without keys ever entering the guest — alongside the four verbs, doctor, and the tailnet --host flag, then write it?

Please diacount the tailscale tailnet consideration to almost-nothing. Tailnet and multidevice on tailnet is really secondary minimal here. Let s make jt 

And yes i like the ssh-agent forwarding concept

Again, maximal fedora-canon is the norm, using krun and other things that redhat does fir us

Give me the downsides of a single bash script by the way - perhaps having lingrering podman containers loose on the desktop without knowing where they came from isn t great?

11:17 AM
Good — discounting the tailnet to near-zero simplifies things and removes the one place scope was creeping. The --host flag can stay as a someday-maybe one-liner, but it's no longer part of the design's identity. Fedora-canon krun + SSH-agent forwarding it is.

Now the question you actually asked, which is the right one to ask before writing a line: what's wrong with a single bash script? Here are the real downsides, roughly in order of how much they'd actually bite you.

1. Orphaned sandboxes — your instinct is exactly right, and it's the worst one. This is the failure mode that matters most for your accident-threat model. A bash script has no lifecycle owner. If the script dies mid-run (you Ctrl-C it, the terminal closes, the SSH session drops, Claude Code crashes), the podman run it started keeps running. There's no parent process tracking it, no cleanup handler that reliably fires. Over a few weeks of agent use you accumulate microVMs nobody remembers starting — eating RAM (each is a real VM with a real kernel), holding ports, mounting worktrees that you've since deleted. You go to podman ps and find a dozen sandbox-* containers and can't tell which are live work and which are zombies.

The mitigations exist but they're exactly the discipline a naive script lacks: a rigorous label convention (sandbox.owner, sandbox.created, sandbox.worktree) so every sandbox is self-describing and you can always answer "where did this come from"; --rm on ephemeral runs so they self-destruct on exit; a trap in the script to clean up on signal; and a reap/destroy --all verb plus maybe a --max-age sweep for anything that outlived its purpose. None of that is hard, but a single script written casually won't have it — and the gap is invisible until you're three weeks in and your desktop is humming with forgotten VMs. So the answer to your question is yes: this is the single best argument for treating the script with CLI-discipline rather than as a quick wrapper.

2. No source of truth beyond podman itself. This is actually a feature you chose deliberately (podman-is-the-state-store via labels), but it has a sharp edge: if your labels are inconsistent, or you ever start a sandbox by hand without the script, podman's state and the script's mental model diverge and there's nothing to reconcile them. The label convention has to be enforced — the script must be the only thing that creates sandboxes, and it must never forget a label. A bash script can't enforce that the way a typed program can; you're relying on discipline.

3. Bash error handling is genuinely treacherous for this. The standard footguns hit hard when the operations are stateful: a failed command mid-script can leave a half-created sandbox (worktree made, container not started, or vice versa). Without set -euo pipefail and careful trap-based rollback, you get partial states that are worse than clean failures. And set -e has notorious edge cases (it doesn't fire inside if conditions, command substitutions, pipelines without pipefail) that make "the script stops on error" less reliable than people assume. For a tool whose whole job is clean create/destroy, sloppy error handling means orphans and partial mounts.

4. Argument parsing degrades as verbs grow. Four verbs with a few flags each is fine in bash. But create --memory 2G --cpus 2 --net none --volume ... --ssh-agent --name ... parsing, with validation and good error messages, is where bash gets ugly fast. You end up with a case statement and manual shift loops that are bug-prone and hard to keep consistent across verbs. This is the dimension that, if it grows, signals you've outgrown bash.

5. Concurrency and naming races. If two agent invocations fire near-simultaneously (parallel worktrees — your actual use case), two creates can race on name generation or port assignment. Bash has no easy locking; you'd need flock and careful design. A single casual script will occasionally double-assign a port or collide on a name under parallel load.

6. Testability and drift. A bash script is hard to unit-test, so behavior drift between the script and the skill's description of it goes uncaught. The Rust tools (ags, smolvm) get cargo test; you get "run it and see."

7. Silent isolation-flag regressions. This is the safety one I keep returning to: if someone edits the script and drops a :ro or fumbles the --network default, there's no type system or test to catch that the sandbox got weaker. The flags that constitute the security boundary live as string fragments in bash, and bash won't tell you when one's wrong.

Now — the honest counterweight, because these downsides argue for discipline, not against bash:

Every one of these is mitigable in bash, and for your scale (single user, handful of sandboxes, accident-not-adversary) the mitigated bash script is genuinely sufficient. The orphan problem is solved by labels + --rm + trap + a reap verb. Error handling is solved by set -euo pipefail + traps. The rest are "watch for the signal to graduate." The reason bash still wins as the starting point is that the alternative — jumping straight to Rust like ags/smolvm — commits you to a build/release/package cycle before you know your verb surface is stable, and the whole prior-art lesson was that the heavier tools are heavier than you need.

So the framing that falls out: the downsides of a single bash script are real but bounded, and they all point at the same discipline — make it a labelled, trap-guarded, set -euo pipefail, reap-capable script that behaves like a CLI, not a quick wrapper. The orphan problem specifically is the one to design against from line one, because it's the one that silently degrades your machine over time and it's the one you correctly flagged.

The graduation signal, concretely: when the argument parsing gets painful, or you genuinely need concurrent-safe port/name allocation under parallel load, or you want real tests around the isolation flags — that's when you rewrite the same verb surface in Rust (which, as you said, packages trivially and is what ags/smolvm did). Keeping the bash version's verbs aligned with what you'd want in Rust keeps that rewrite cheap.

So before building: do you want the orphan-prevention to lean on --rm-ephemeral-by-default (sandboxes vanish on exit unless explicitly persisted), or on persistent-by-default-with-a-reaper (sandboxes survive but a reap verb and age-sweep clean them)? That choice shapes the whole script — the first is safer against orphans but loses state between runs; the second matches the worktree-per-branch pattern better but leans harder on the labelling discipline to stay clean. Which fits how you picture using it?

Just to clarify: we re keeping tailscale tailnet for sure but i wanted the tool (whatever form jt ends up becoming) to be very independent of it. As in orthogonal to it.

11:18 AM
Got it — that's a cleaner framing than "discount it," and it changes the design instruction in a specific way.

Orthogonal means the tool knows nothing about Tailscale. No --host flag, no SSH-to-a-runner-node logic, no tailnet awareness baked in anywhere. The tool's job ends at "manage a krun sandbox on this machine, correctly." Tailscale is then a layer that operates around it, not through it — and that's actually the more robust design, because the two compose without coupling.

Concretely, what orthogonality buys you and how it works:

The tool runs identically on any machine, knowing only about localhost. If you want it to run on another box, you ssh (or tailscale ssh) into that box and run the exact same command there. The tool doesn't reach across the network; you (or a thin outer wrapper, or Claude) do the reaching, and the tool just runs locally wherever it's invoked. That's the Unix-composition version of remote execution — ssh node 'sandbox create ...' — rather than the tool growing network limbs.

Ingress is likewise external. Your Caddy-over-tailnet config forwards a URL to a local port; the sandbox publishes to a local port via podman; Caddy doesn't know it's a sandbox and the sandbox doesn't know Caddy or the tailnet exist. They meet at "a port on localhost," which is the clean seam. The tool's only responsibility is to publish predictably to a host port; everything network-facing is Caddy's problem, configured separately.

This means one concrete subtraction from the design and one principle:

Subtraction: drop the --host flag entirely, even as a someday-maybe. If it's orthogonal, host-selection is never the tool's concern — it's ssh's. Adding --host would be the exact coupling you're ruling out. Good riddance; it was the one bit of scope that didn't belong.

Principle: the tool exposes local primitives cleanly enough that network layers can compose on top without the tool's help. Predictable port publishing, machine-readable output (so an outer script can parse sandbox list and know what's running where), stable exit codes. Those are what make it composable with ssh/Caddy/tailnet without knowing about any of them. "Be a good local citizen with parseable output" is the whole contract.

The nice consequence: this also keeps the tool honest about the graduation question from last turn. A tool that stays local-only and orthogonal has a much harder ceiling to hit — most of the "this needs to become Rust / a daemon" pressure came from distributed concerns (placement, multi-node state, concurrent remote runs). Strip those out as orthogonal and the local tool can stay a disciplined bash script for far longer, because its entire problem space is "one machine, a handful of sandboxes, clean lifecycle." The tailnet scaling story still exists — it just lives entirely outside the tool, as ssh + Caddy, which you already have.

So the revised shape: a local-only, tailnet-ignorant sandbox tool (labelled, trap-guarded, reap-capable, SSH-agent-forwarding, krun-on-official-Fedora) that publishes predictably to localhost and emits parseable output — and Tailscale composes around it untouched, by your existing ssh and Caddy layers, with zero awareness in either direction.

That leaves the one design fork still open from last turn, and it's purely local now so it's cleanly answerable: ephemeral-by-default (--rm, sandboxes vanish on exit, safest against orphans) versus persistent-by-default-with-a-reaper (sandboxes survive across runs to match the worktree-per-branch pattern, leans on labelling to stay clean). Which one fits how you picture using it?

And per your previous point: this is valid but there is something you keep going back to: 
"You need discipline". Ok. What s maximal discipline then? What does that entail for a well wrottenscript (bash or go)? Or is it a skill.md thing? Both?

11:46 AM
Right — I keep invoking "discipline" as if it's self-evident, which is a cop-out. Let me make it concrete and exhaustive, because "maximal discipline" is actually a definable checklist, and it splits cleanly across the two artifacts. The short version: discipline is mostly a script property, partly a skill property, and the single most important move is making it impossible to express an unsafe sandbox, not merely documenting how to express a safe one.

The governing principle
Maximal discipline = the safe path is the only expressible path. Every other rule below is a special case of that. If the script can produce an unsafe or orphaned sandbox, then sooner or later it will, because the agent — or you at 2am — will hit the path that does. Discipline means removing the unsafe paths from existence, not annotating them with warnings. Warnings live in prose and prose is advisory; constraints live in code and code is binding. That's why this is mostly a script concern: the skill can only ever advise, and you don't want your security boundary to be advisory.

Script-level discipline (this is ~80% of it)
Fail loudly and atomically. set -euo pipefail at the top, and a trap that fires on ERR, EXIT, INT, and TERM. The trap's job is rollback: if create made a worktree but the container failed to start, the trap tears the worktree back down so you never have a half-built sandbox. The invariant is every operation either completes fully or leaves no trace — no partial states, because partial states are how orphans and confusion are born. In Go this is defer + explicit cleanup on error; same idea, sturdier.

Orphan prevention is structural, not behavioral. This is the one you flagged and it deserves the most rigor:

Every sandbox is created with a complete, mandatory label set — sandbox.managed-by=<toolname>, sandbox.created=<iso8601>, sandbox.worktree=<path>, sandbox.id=<name>. There is no code path that creates a container without these. That label set is what makes every sandbox self-describing, so "where did this come from" is always answerable by podman inspect.
The trap-on-exit handles the crash case (Ctrl-C, terminal close): ephemeral runs get --rm so podman itself reaps them, and the trap covers the rest.
A reap verb handles the accumulation case: it sweeps everything carrying sandbox.managed-by=<toolname>, optionally filtered by age (--older-than 24h via the created label). This is your "I don't know where these came from" insurance — it's impossible to have a mystery sandbox because the tool only ever made labelled ones, and reap finds all of them.
doctor (verb zero) and list both surface orphans proactively, so they're visible before they pile up.
The isolation flags are centralized and unbypassable. Every security-relevant flag — --network, the :ro on mounts, --memory, --cpus, the krun runtime selection — is set in exactly one function that every create path funnels through. There is no second place a sandbox can be born. This is what stops the "someone edited the script and dropped a :ro" regression: there's only one line to get right, and it's the line every sandbox passes through. Defaults are the safe values (--network none, read-only mounts, conservative memory/cpu caps); relaxing them requires an explicit flag the caller must consciously pass. Safe-by-default, unsafe-by-effort.

Inputs are validated and quoted, always. Sandbox names validated against a charset (no injection via a crafted name), paths resolved and checked to exist before mounting, every variable expansion quoted ("$var"). This matters more than usual because the agent is generating some of these arguments — you're parsing input from an LLM, which is exactly the situation where an unvalidated name or path bites.

Idempotency and predictable naming. create with an existing name either errors clearly or replaces deterministically — never silently spawns a duplicate. Names derive from the worktree where possible, so "is there already a sandbox for this branch?" is answerable without external state. This is also your race protection: derive-from-worktree plus a check makes parallel creates collide detectably rather than double-allocating.

Machine-readable output. list (and friends) can emit parseable output (a --json mode, or stable columns), stable exit codes per failure class. This is what keeps the tool composable (your orthogonality requirement) and testable.

Minimal, auditable, single-file. The whole point of bash here is that the script is short enough to read in one sitting and verify by eye. Discipline includes not letting it grow features that obscure the security-critical core. The moment it's too long to audit at a glance, that's a graduation signal.

Skill-level discipline (the other ~20% — judgment, not enforcement)
The skill cannot enforce anything, so its discipline is about teaching Claude when and why, and crucially not duplicating the script's interface (or the two drift and the skill starts lying):

Point at --help, don't restate flags. The script's --help is the single source of truth for how. The skill describes when: spin up a sandbox for running builds/tests/the webapp, never run untrusted-ish workload code directly on the host, tear down when done.
Encode the "don't" cases the research surfaced. Don't point the tool at a pre-made worktree (orphans the agent from .git); guard destructive git commands inside the sandbox (the worktree prune problem); always reap or destroy when finished. These are judgment rules prose is good at.
Teach the failure-recovery loop. "If doctor fails, here's what's likely wrong"; "if a sandbox is wedged, destroy and recreate rather than poking at it." This is where the skill earns its keep — recovery is judgment, and it's exactly what an agent gets wrong without guidance.
State the invariants as intentions. "Sandboxes are disposable; never store anything in one you can't lose." That's not enforceable, but it shapes how Claude uses the tool.
Bash or Go — does the answer change?
The checklist is identical; what changes is how much the language helps you hold the line:

Bash gives you set -euo pipefail, trap, flock for the rare concurrency need — enough to implement every item above, but it relies on you to apply them and gives you no compiler to catch a lapse. Go gives you defer, typed argument parsing (cobra/flag), real error returns, os/signal handling, and go test — so the discipline is partly enforced by the toolchain rather than purely by your vigilance. Go also packages trivially as you noted, and it's what ags/smolvm chose for exactly these reasons.

So the honest answer to "bash or go": start in bash if your verb surface is still settling, because the iteration cost is lower and the script-being-auditable-at-a-glance is itself a form of discipline. Move to Go the moment any of these is true — argument parsing gets painful, you need tested guarantees around the isolation flags, you want concurrency safety under parallel worktrees, or the script grows past easy-audit length. The verb surface stays identical across the move, so it's cheap. Neither language makes discipline automatic; Go just makes lapses harder.

The one-sentence version
Maximal discipline is: a single-file, set -euo pipefail, trap-guarded script where every sandbox is born through one centralized function that stamps mandatory labels and safe-by-default isolation flags, paired with a reap verb that can always find every sandbox it ever made — and a skill that teaches when and why while delegating how to --help so the two never drift. The script makes unsafe states inexpressible; the skill makes good judgment likely; and "discipline" is just the name for having done both deliberately instead of hoping.

Given all this is now specified, the ephemeral-vs-persistent default is the last real decision and it directly determines how hard the reaper has to work — want to settle that and have me write it?

Example of a well enforce ddiscipline (i m ideating here, you tell me best practices)
Make the podman containers ephemeral by default? And perisstence as a specific flag? That way we avoid the pile up of them on disk or on ram over time?

11:47 AM
Yes — that's exactly the right enforcement instinct, and it's a textbook case of the governing principle: ephemeral-by-default makes the orphan-pileup state hard to reach instead of merely discouraged. You're not relying on anyone remembering to clean up; the default behavior cleans up itself, and accumulation requires a conscious opt-in. That's discipline expressed as a default, which is the strongest kind. Let me sharpen it with the best practices around it, because there's a subtlety that determines whether it actually works.

The core mechanism is podman run --rm: the container is removed automatically the moment its main process exits. So sandbox run <something> spins up the microVM, does the thing, the process ends, podman reaps it — zero residue, no pileup possible on that path. Persistence becomes sandbox create --persist (or a separate create verb vs. run verb), which deliberately omits --rm and stamps a label saying "this one is meant to stick around." That split — ephemeral run vs. persistent create — is cleaner than a --persist flag on one verb, because the verb name itself signals intent and you can't fat-finger it.

But here's the subtlety that makes-or-breaks it: --rm only fires on clean process exit. It does not save you from the crash case. If you Ctrl-C, the terminal dies, the SSH session drops, or the agent harness is killed mid-run, the container can be left in a stopped-but-not-removed state, or running detached with nothing watching it. --rm handles the graceful path; it's not a complete orphan defense by itself. This is the gap people miss when they think "ephemeral-by-default" is the whole answer. So the real best-practice is ephemeral-by-default plus two backstops:

The trap backstop catches the interactive-crash case. Your set -euo pipefail script installs a trap on INT/TERM/EXIT that explicitly removes the sandbox it started, by name, so even an ungraceful exit gets cleaned. Between --rm (clean exit) and the trap (signal/crash), the interactive path is fully covered.

The reap backstop catches everything else — the cases no trap can reach, like a hard kill (SIGKILL, OOM-killer, power loss) where the script never gets to run its trap. reap sweeps every container carrying your sandbox.managed-by label, optionally age-filtered. This is the "belt and suspenders" layer: --rm and trap make orphans rare, and reap guarantees they're recoverable when the rare case happens. You want all three; ephemeral-by-default alone is necessary but not sufficient.

A few more best-practices that pair with this:

Distinguish RAM pileup from disk pileup, because they have different lifecycles. A running microVM eats RAM; a stopped-or-orphaned container eats disk (its writable layer) and holds the name/ports. --rm addresses both for the clean path. But also be deliberate about the image layer and any volumes: ephemeral containers can still leave dangling anonymous volumes unless you use --rm which (with podman) also removes anonymous volumes created with the container. Worth confirming that behavior and, if you ever attach named volumes for persistence, making clear those are intentionally outside the ephemeral lifecycle — a persistent sandbox's whole point is its volume survives, so reap should treat named-volume-backed sandboxes more cautiously than throwaway ones.

Make persistence expire-able, not eternal. Even opted-in persistent sandboxes should carry the created timestamp label so reap --older-than 7d can catch a persistent sandbox you forgot you made. "Persistent" should mean "survives across runs," not "lives forever unmonitored." Otherwise the --persist escape hatch just relocates the pileup problem to a slower timescale.

list should make the ephemeral/persistent distinction visible at a glance — a column showing which sandboxes are throwaway vs. sticky, and how old. The whole discipline collapses if you can't see what's accumulating; visibility is what lets reap be a conscious choice rather than a periodic panic.

Decide the detached-ephemeral question explicitly, because it's the one genuinely awkward combination. A webapp substrate often needs to run detached (in the background, serving requests) while still being ephemeral (gone when you're done). --rm plus -d works in podman, but now there's no foreground process for a trap to hang off — the sandbox outlives the script invocation by design. For that case, the cleanup owner shifts entirely to reap and to an explicit sandbox stop <name>, since --rm won't fire until you stop it and the trap never had a process to watch. So "ephemeral" means two slightly different things for a foreground run (dies with the command) versus a detached service (dies when you stop it or reap it), and the script should be clear about which it's doing.

So your instinct, refined into the best-practice shape: ephemeral-by-default via --rm, persistence as an explicit opt-in verb/flag that stamps a label, trap-based cleanup for the interactive-crash gap, a label-driven reap as the universal backstop for the hard-kill gap, age-stamping even on persistent sandboxes so nothing is truly eternal, and list surfacing the distinction so accumulation is always visible. Ephemeral-default is the load-bearing decision you've correctly identified; the trap and reap are what make it actually airtight rather than just usually-fine.

This also happens to settle the design fork I kept parking: you've chosen ephemeral-by-default, so the reaper is a backstop rather than the primary mechanism — which is the lighter, safer configuration and keeps the script firmly in disciplined-bash territory.

If you're happy with that shape, the next concrete thing is the verb surface itself — I'd propose run (ephemeral foreground), create/up (persistent), list, exec, stop, destroy, reap, and doctor, with the SSH-agent forwarding and centralized safe-flags baked into the shared create path. Want me to write it now, bash first, single auditable file?

List all the github repos to clone locally to read through here
The official krun (layers 0 trhough 2 you mentioned) that we re building on top, that are available on fedora officially
The reference repos including the omes we found later
Just the url s plz

12:09 PM
Official krun stack (layers 0–2, what you're building on):

https://github.com/containers/libkrunfw
https://github.com/containers/libkrun
https://github.com/containers/crun
https://github.com/containers/krunvm
https://github.com/containers/podman
https://github.com/containers/crun-vm
Reference repos (the tools we evaluated):

https://github.com/superradcompany/microsandbox
https://github.com/docker/sbx-releases
https://github.com/BinSquare/ERA
https://github.com/smol-machines/smolvm
https://github.com/thomaspeklak/agent-sandbox
https://github.com/abshkbh/arrakis
https://github.com/textcortex/claude-code-sandbox
https://github.com/efrecon/gh-runner-krunvm
Curated lists worth skimming for more:

https://github.com/dloss/awesome-agent-sandboxes
https://gist.github.com/wincent/2752d8d97727577050c043e4ff9e386e
Two notes: krunvm and crun-vm are under the containers/ org (canonical upstream) but aren't in Fedora's main repos — krunvm is COPR-only (slp/krunvm), and crun-vm is a separate QEMU-image runtime, not the krun path. The truly official-in-Fedora packages are libkrunfw, libkrun, crun (built with +LIBKRUN), and podman. The first four URLs are the ones that matter most for understanding the engine you're sitting on; crun specifically, because its krun.1.md and the krun handler source are where the annotation surface (krun.cpus, krun.ram_mib, etc.) actually lives.

To clarify: we can do everything that we want eith the things that exist on fedora, plus a bash script and a well written claude skill

12:10 PM
Correct — with one small precision so you're not surprised mid-build.

Everything in your actual design is covered by what's already on Fedora plus your two artifacts. The engine — microVM with its own kernel, OCI images, resource caps, mounts, port publishing, the krun annotations — is all podman + crun-krun + libkrun + libkrunfw, every one an official package. The lifecycle, labelling, ephemeral-by-default, trap cleanup, reap, doctor, SSH-agent forwarding, centralized safe-flags — all bash over those packages. The when/why/recovery judgment — the Claude skill. The network ingress — Caddy, already on your box. Nothing in that list needs a third-party runtime, a daemon, a login, or a COPR package. So yes: Fedora-canon + one disciplined bash script + one well-written skill is the complete kit.

The precision: "everything we want" is true; "everything those other tools do" is not — and the gap is deliberate, not a shortfall. Two capabilities you've seen in the references genuinely aren't free on the official stack:

Snapshot/restore backtracking (Arrakis's checkpoint-and-restore, Firecracker's CoW forking) — libkrun doesn't do this the way Firecracker/cloud-hypervisor do. You decided you don't need it (single-user, spin-up-a-few-times), so it's a non-want, not a missing piece.

The egress policy engine (sbx's deny-by-default domain filtering, the forced transparent proxy) — that's not in podman-krun. But you also decided you don't need the unbypassable version, because your threat model is accident not exfiltration. Your network containment is the simple end: --network none by default, or an internal network with a firewalld allow-list when the workload needs out. That's achievable with official Fedora (firewalld/netavark) plus a flag in your script — so it's still "covered," just at the proportionate tier rather than the sbx tier.

And the one feature you did want from the references — SSH-agent forwarding without keys entering the guest — is doable on the official stack: forward the host's SSH_AUTH_SOCK into the sandbox as a mount/socket rather than copying keys. No special tooling, just the right podman invocation in your create path.

So the honest full statement: everything you've scoped is buildable with Fedora-canon + bash + skill. The things that would require more (snapshot forking, unbypassable egress) are exactly the things you consciously scoped out, and scoping them out is why the simple kit suffices. That alignment between "what's easy on official Fedora" and "what you actually want" is the whole reason this project landed where it did — you let the threat model and the platform agree with each other instead of fighting either.

You're clear to build. The only undecided atom left is the verb names; everything else is settled. Want the script now?







Claude is AI and can make mistakes. Please double-check responses.
