# Gemini CLI investigation — retired 2026-11-10

Google rejected personal sign-in on CLI 0.67.0: this client no longer supports Gemini Code Assist for individuals, and directs users to Antigravity. The installed package and gmni launchers were replaced by [Antigravity](antigravity-cli.md). Existing AI Studio API keys remain separate.

Retained findings:

- GEMINI_CLI_HOME names the parent of .gemini, rather than the config directory itself.
- Google API keys and Google account OAuth are separate authentication offerings.
- GEMINI_CLI_AUTH_OVERRIDE is one-shot and is consumed by the CLI supervisor/settings loader; it cannot enforce an account method across restarts.
- Gemini system-policy files and their ancestors must be root-owned. User config paths are rejected; Nix sandbox UID remapping also affects tests of this check.
- Separate credential files prevent the shared OS-keyring account from colliding.
- A successful OAuth flow cannot restore an offering that the server has retired.
- ACP delegates the inner agent; the minimal Gemini SDK is a different implementation.

The detailed CLI capability map, architecture and source references are preserved in the owned dsh-gemini-cli repository. The earlier implementation is retained in Git history (PRs710 and711); no login data is deleted.
