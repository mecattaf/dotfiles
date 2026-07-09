# llm-agents.nix — installed product sweep

Every package the maximalist `llmAgentsAll` buildEnv installs on the fleet
(`home/home.nix`, sourced from the `llm-agents.nix` flake input's
`overlays.default` → `pkgs.llm-agents.*`).

**139 products** (18 unfree). Auto-generated from `meta` — this is
the full catalog we pull in wholesale; the install is programmatic (every
buildable member), so this list is a *snapshot* and will grow as upstream
adds agents on the next `nix flake update llm-agents`.

This is a deliberate comprehensive sweep — most of these are expected to be
pruned later. Use the checkboxes to mark keepers vs. cuts; to actually drop
one, add its name to `alreadyInstalled`/a denylist in `home/home.nix` or
narrow the buildEnv filter.

`†` = unfree.

| Keep? | Product | Version | Description |
|:-:|---|---|---|
| ☐ | `agent-browser` | 0.31.1 | Headless browser automation CLI for AI agents |
| ☐ | `agent-deck` | 1.9.73 | Your AI agent command center |
| ☐ | `agentsview` | 0.37.2 | Local-first viewer and analytics for AI coding agent sessions |
| ☐ | `aionui` | 2.1.31 | Desktop and WebUI cowork app that turns AI agents into a local assistant and server |
| ☐ | `amp †` | 0.0.1783574196-g30f6f2 | CLI for Amp, an agentic coding tool in research preview from Sourcegraph |
| ☐ | `annot` | 0.13.1 | Human-in-the-loop annotation tool for AI workflows |
| ☐ | `antigravity †` | 1.1.0 | CLI for Google Antigravity, an agentic development platform |
| ☐ | `antigravity-cli †` | 1.1.0 | CLI for Google Antigravity, an agentic development platform |
| ☐ | `aperant` | 2.7.6 | Autonomous multi-agent coding framework powered by Claude AI |
| ☐ | `apm` | 0.24.0 | Agent Package Manager — dependency manager for AI agents |
| ☐ | `auto-claude` | 2.7.6 | Autonomous multi-agent coding framework powered by Claude AI |
| ☐ | `backlog-md` | 1.47.1 | Backlog.md - A tool for managing project collaboration between humans and AI Agents in a git ecosystem |
| ☐ | `beads` | 1.1.0 | A distributed issue tracker designed for AI-supervised coding workflows |
| ☐ | `beads-rust` | 0.2.16 | Fast Rust port of beads - a local-first issue tracker for git repositories |
| ☐ | `beads-viewer` | 0.18.0 | Graph-aware TUI for the Beads issue tracker |
| ☐ | `bernstein` | 3.1.0 | Multi-agent orchestrator for CLI coding agents — spawn, coordinate, and manage parallel AI agents |
| ☐ | `buildNpmPackage` | — | nixpkgs buildNpmPackage with an eval guard for fetcherVersion=2 |
| ☐ | `bun2nix` | 2.1.1 | A fast rust based bun lockfile to nix expression converter. |
| ☐ | `but †` | 0.21.0 | GitButler CLI - virtual branches and AI-assisted Git workflow from the terminal |
| ☐ | `catnip` | 0.12.1 | Developer environment that's like catnip for agentic programming |
| ☐ | `cc-sdd` | 3.0.2 | Spec-driven development framework for AI coding agents |
| ☐ | `cc-switch-cli` | 5.9.0 | CLI version of CC Switch - All-in-One Assistant for Claude Code, Codex & Gemini CLI |
| ☐ | `ccstatusline` | 2.2.22 | A highly customizable status line formatter for Claude Code CLI |
| ☐ | `ccusage` | 20.0.14 | Analyze coding agent CLI token usage and costs from local data |
| ☐ | `chainlink` | 1.6.0 | Simple, lean issue tracker CLI designed for AI-assisted development |
| ☐ | `ck` | 0.7.11 | Local first semantic and hybrid BM25 grep / search tool for use by AI and humans! |
| ☐ | `claude-agent-acp` | 0.57.0 | An ACP-compatible coding agent powered by the Claude Code SDK (TypeScript) |
| ☐ | `claude-code †` | 2.1.205 | Agentic coding tool that lives in your terminal, understands your codebase, and helps you code faster |
| ☐ | `claude-code-router` | 3.0.0 | Use Claude Code without an Anthropics account and route it to another LLM provider |
| ☐ | `claude-desktop †` | 1.18286.2 | Desktop application for Claude.ai |
| ☐ | `claude-plugins` | 0.2.0 | CLI tool for managing Claude Code plugins |
| ☐ | `claudebox` | — | Sandboxed environment for Claude Code |
| ☐ | `claw-code` | 0-unstable-2026-06-26 | Claude Code rewrite CLI built from the official claw-code Rust workspace |
| ☐ | `cli-proxy-api` | 7.2.54 | Unified proxy providing OpenAI/Gemini/Claude/Codex compatible APIs for AI coding CLI tools |
| ☐ | `code` | 0.6.143 | Fork of codex. Orchestrate agents from OpenAI, Claude, Gemini or any provider. |
| ☐ | `code-review-graph` | 2.3.6 | Local knowledge graph for AI coding agents — builds persistent map of your codebase for token-efficient code reviews |
| ☐ | `codegraph` | 1.3.1 | Semantic code intelligence for AI coding agents |
| ☐ | `coderabbit-cli †` | 0.6.5 | AI-powered code review CLI tool |
| ☐ | `codex` | 0.143.0 | OpenAI Codex CLI - a coding agent that runs locally on your computer |
| ☐ | `codex-acp` | 0.16.0 | An ACP-compatible coding agent powered by Codex |
| ☐ | `codex-auth` | 0.2.10 | CLI tool for switching Codex accounts |
| ☐ | `context-hub` | 0.1.4 | CLI for Context Hub - search and retrieve LLM-optimized docs and skills |
| ☐ | `copilot-cli †` | 1.0.69 | GitHub Copilot CLI brings the power of Copilot coding agent directly to your terminal. |
| ☐ | `copilot-language-server` | 1.519.0 | GitHub Copilot Language Server - AI pair programmer LSP |
| ☐ | `crush` | 0.83.0 | The glamourous AI coding agent for your favourite terminal |
| ☐ | `cubic †` | 1.7.2 | AI code review CLI from cubic.dev - fast pre-flight review before you push |
| ☐ | `cursor-agent †` | 2026.07.08-0c04a8a | Cursor Agent - CLI tool for Cursor AI code editor |
| ☐ | `default` | — | Interactive fzf launcher for llm-agents.nix packages |
| ☐ | `dolt` | 2.1.10 | Relational database with version control and CLI a-la Git |
| ☐ | `droid †` | 0.168.2 | Factory AI's Droid - AI-powered development agent for your terminal |
| ☐ | `eca` | 0.144.0 | Editor Code Assistant (ECA) - AI pair programming capabilities agnostic of editor |
| ☐ | `entire` | 0.8.42 | CLI tool that captures AI agent sessions and links them to code changes |
| ☐ | `fence` | 0.1.62 | Lightweight, container-free sandbox for running commands with network and filesystem restrictions |
| ☐ | `flake-inputs` | — |  |
| ☐ | `forge` | 2.13.16 | AI-Enhanced Terminal Development Environment - A comprehensive coding agent that integrates AI capabilities with your development environment |
| ☐ | `forgecode` | 2.13.16 | AI-Enhanced Terminal Development Environment - A comprehensive coding agent that integrates AI capabilities with your development environment |
| ☐ | `formatelf` | 26.05pre-git | Setup hook that patches ELF binaries via formatelf |
| ☐ | `formatter` | — | One CLI to format the code tree |
| ☐ | `gascity` | 1.3.3 | Orchestration-builder SDK for multi-agent coding workflows |
| ☐ | `gastown` | 1.2.1 | Gas Town - multi-agent workspace manager |
| ☐ | `gemini-cli` | 0.50.0 | AI agent that brings the power of Gemini directly into your terminal |
| ☐ | `git-surgeon` | 0.1.17 | Git primitives for autonomous coding agents |
| ☐ | `gitbutler †` | 0.21.0 | Git client for simultaneous branches on top of your existing workflow |
| ☐ | `gitclaw` | 2.0.1 | Universal git-native multimodal AI agent (formerly gitagent) |
| ☐ | `gitnexus †` | 1.6.9 | Graph-powered code intelligence for AI agents |
| ☐ | `gnhf` | 0.1.42 | Ralph/autoresearch-style orchestrator that keeps coding agents running while you sleep |
| ☐ | `gno` | 1.12.0 | Local-first knowledge engine with hybrid search, RAG Q&A, and MCP server integration |
| ☐ | `go-bin` | 1.26.5 | Latest Go toolchain (prebuilt binary) for building packages that need a newer patch release than nixpkgs ships |
| ☐ | `goose-cli` | 1.41.0 | CLI for Goose - a local, extensible, open source AI agent that automates engineering tasks |
| ☐ | `grok †` | 0.2.93 | Grok Build, xAI's agentic coding tool |
| ☐ | `handy` | 0.9.0 | Fast and accurate local transcription app using AI models |
| ☐ | `happy-coder` | 1.1.10 | Mobile and Web client for Codex and Claude Code, with realtime voice and encryption |
| ☐ | `herdr` | 0.7.3 | Terminal workspace manager for AI coding agents |
| ☐ | `hermes-agent` | 2026.7.7 | Self-improving AI agent by Nous Research — creates skills from experience and runs anywhere |
| ☐ | `hermes-desktop` | 0.7.3 | Desktop companion for Hermes Agent |
| ☐ | `hermes-hud` | 0.5.0 | TUI consciousness monitor for Hermes Agent |
| ☐ | `hunk` | 0.17.0 | Terminal diff viewer for agentic changesets |
| ☐ | `icm` | 0.10.57 | Persistent memory for AI agents with hybrid search, temporal decay, and multilingual embeddings |
| ☐ | `iflow-cli` | 0.5.19 | AI coding agent for the terminal with free model access via the iFlow platform |
| ☐ | `jscpd` | 5.0.12 | Copy/paste detector for programming source code |
| ☐ | `jules †` | 0.1.42 | Jules, the asynchronous coding agent from Google, in the terminal |
| ☐ | `junie †` | 2206.3 | Junie, JetBrains AI coding agent CLI |
| ☐ | `kilocode-cli` | 7.4.1 | The open-source AI coding agent. Now available in your terminal. |
| ☐ | `lean-ctx` | 3.9.3 | Context OS for AI development — compression, memory, and routing for LLM context |
| ☐ | `letta-code` | 0.27.29 | Memory-first coding agent that learns and evolves across sessions |
| ☐ | `localgpt` | 0.3.6 | Local AI assistant with persistent markdown memory, autonomous tasks, and semantic search |
| ☐ | `mardi-gras` | 0.26.0 | Terminal UI for Beads issue tracking with a parade-inspired workflow view |
| ☐ | `mcporter` | 0.12.3 | TypeScript runtime and CLI for the Model Context Protocol |
| ☐ | `memvid-cli` | 2.0.160 | AI memory CLI - crash-safe, single-file storage with semantic search |
| ☐ | `mimo-code` | 0.1.5 | Open-source AI coding agent with cross-session memory |
| ☐ | `mistral-vibe` | 2.19.0 | Minimal CLI coding agent by Mistral AI - open-source command-line coding assistant powered by Devstral |
| ☐ | `nanocoder` | 1.28.1 | A beautiful local-first coding agent running in your terminal - built by the community for the community ⚒ |
| ☐ | `nono` | 0.67.1 | Kernel-enforced agent sandbox. Capability-based isolation with secure key management, atomic rollback, cryptographic immutable audit chain of provenance. Run your agents in a zero-trust environment. |
| ☐ | `officecli` | 1.0.132 | CLI for creating and editing Office Open XML documents |
| ☐ | `oh-my-claudecode` | 4.15.3 | Multi-agent orchestration system for Claude Code |
| ☐ | `oh-my-codex` | 0.19.1 | Multi-agent orchestration layer for OpenAI Codex CLI |
| ☐ | `oh-my-opencode †` | 4.16.0 | The Best AI Agent Harness - Multi-Model Orchestration for OpenCode |
| ☐ | `omp` | 16.3.12 | A terminal-based coding agent with multi-model support |
| ☐ | `openclaw` | 2026.6.11 | Your own personal AI assistant. Any OS. Any Platform. The lobster way |
| ☐ | `opencode` | 1.17.16 | AI coding agent built for the terminal |
| ☐ | `openfang` | 0.6.9 | Open-source Agent OS built in Rust — CLI for the OpenFang platform |
| ☐ | `openskills` | 1.5.0 | Universal skills loader for AI coding agents - install and load Anthropic SKILL.md format skills in any agent |
| ☐ | `openspec` | 1.5.0 | Spec-driven development for AI coding assistants |
| ☐ | `openspecui` | 5.0.0 | Visual interface for spec-driven development |
| ☐ | `parallel-cli` | 0.7.1 | AI-powered web search, extraction, and research CLI from Parallel |
| ☐ | `paseo-desktop` | 0.1.104 | Voice-controlled desktop development environment for AI coding agents |
| ☐ | `pi` | 0.80.3 | A terminal-based coding agent with multi-model support |
| ☐ | `picoclaw` | 0.3.1 | Tiny, fast, and deployable anywhere — automate the mundane, unleash your creativity |
| ☐ | `plannotator` | 0.22.0 | Interactive plan and code review tool for AI coding agents |
| ☐ | `qmd` | 2.5.3 | mini cli search engine for your docs, knowledge bases, meeting notes, whatever. Tracking current sota approaches while being all local |
| ☐ | `qoder-cli †` | 1.0.40 | Qoder AI CLI tool - Terminal-based AI assistant for code development |
| ☐ | `qwen-code` | 0.19.8 | Command-line AI workflow tool for Qwen3-Coder models |
| ☐ | `ralph-tui` | 0.12.0 | AI Agent Loop Orchestrator TUI |
| ☐ | `reasonix` | 1.17.9 | DeepSeek-native AI coding agent for your terminal |
| ☐ | `rtk` | 0.43.0 | CLI proxy that reduces LLM token consumption by 60-90% on common dev commands |
| ☐ | `sandbox-runtime` | 0.0.64 | Lightweight sandboxing tool for enforcing filesystem and network restrictions |
| ☐ | `semble` | 0.5.0 | Fast and accurate local code search for AI agents — CLI and MCP server |
| ☐ | `showboat` | 0.6.1 | Create executable demo documents showing and proving an agent's work |
| ☐ | `sidecar` | 0.86.0 | Terminal-based development companion for AI coding agents |
| ☐ | `skills` | 1.5.15 | The open agent skills tool for installing and managing skills across AI coding agents |
| ☐ | `skills-installer` | 0.3.1 | Install agent skills across multiple AI coding clients |
| ☐ | `spec-kit` | 0.12.8 | Specify CLI, part of GitHub Spec Kit. A tool to bootstrap your projects for Spec-Driven Development (SDD) |
| ☐ | `td` | 0.51.0 | A minimalist CLI for tracking tasks across AI coding sessions. |
| ☐ | `terminal-use` | 1.2.0 | Headless virtual terminal for AI agents |
| ☐ | `toon` | 0.5.0 | Rust implementation of TOON - Token-Oriented Object Notation for LLM prompts |
| ☐ | `trellis` | 0.6.5 | An out-of-the-box engineering framework for AI coding. |
| ☐ | `tuicr` | 0.18.0 | Review AI-generated diffs like a GitHub pull request, right from your terminal |
| ☐ | `unpinCargoMsrvHook` | 26.05pre-git | Setup hook that removes rust-version (MSRV) constraints from Cargo manifests |
| ☐ | `unpinGoModVersionHook` | 26.05pre-git | Setup hook that relaxes go.mod version constraints to match the build toolchain |
| ☐ | `versionCheckHomeHook` | 26.05pre-git | Setup hook that provides a writable HOME for versionCheckHook |
| ☐ | `vessel-browser` | 0.1.171 | Agent-oriented browser with durable state and MCP control |
| ☐ | `vibe-kanban` | 0.1.44 | Kanban board to orchestrate AI coding agents like Claude Code, Codex, and Gemini CLI |
| ☐ | `vix` | 0.5.3 | Sleek, Fast and Token Efficient AI Coding Agent |
| ☐ | `voxterm` | 0.3.0 | Local real-time voice transcription TUI with speaker diarization |
| ☐ | `voxtype` | 0.7.5 | Push-to-talk voice-to-text for Wayland |
| ☐ | `workmux` | 0.1.218 | Git worktrees + tmux windows for zero-friction parallel dev |
| ☐ | `wrapBuddy` | 26.05pre-git | Setup hook that patches ELF binaries with stub loader |
| ☐ | `zat` | 0.5.4 | Code outline viewer for LLM coding agents — shows exported symbols with line numbers |
| ☐ | `zeroclaw` | 0.8.2 | Fast, small, and fully autonomous AI assistant infrastructure |

