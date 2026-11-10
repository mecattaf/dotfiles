# Gemini CLI accounts on NAS

The NAS installs the pinned `llm-agents.nix` Gemini CLI. Launch one account at
a time and complete **Sign in with Google** in the browser:

| Command | Writable Gemini state |
| --- | --- |
| `gmni` | `~/.gemini/` |
| `gmni2` | `~/.gemini-account-2/.gemini/` |
| `gmni3` | `~/.gemini-account-3/.gemini/` |

Choose a different Google account for each command. Subsequent launches reuse
that account's saved OAuth credentials. Run the commands on NAS, where the
harnesses and credentials live. They preserve the real home directory and the
project directory, and forward every argument. For example, `gmni2 --resume
latest` resumes that account's latest session for the current project.

The wrappers select Google's OAuth method explicitly and use Gemini CLI's
file-backed credential storage, with private directories and umask 077. They
clear API-key, ADC and Vertex authentication overrides for the child process.
Signing into one account does not replace another account's OAuth file, and
launching `gmni` from inside `gmni2` selects account 1 again. Models, preferences
and sessions remain writable; Nix does not seed or reset them.

`GEMINI_CLI_HOME` names the parent of `.gemini`. The wrappers set this rather
than changing `HOME`. They default to `NO_BROWSER=true` on the headless NAS:
Gemini prints the login URL, you open it in the client browser, and paste the
authorization code back into the NAS terminal. No callback port forwarding is
needed. An explicitly supplied `NO_BROWSER` value is preserved.

These Google CLI logins are separate from the existing three AI Studio API
keys used by the native DSH Google provider. No API key is needed by `gmni`.
Access and quota are determined by Google for each signed-in account; an
installation or saved login does not prove a particular free allowance.

The `hyqhyq3/dsh-gemini-oauth-bridge` plugin authenticates independently and
does not invoke Gemini CLI or import these logins. A DSH extension that wraps
the official CLI, following `Norman-else/dsh-claude`, is a separate integration.

Upstream behavior checked against Gemini CLI v0.67.0:

- [Home override](https://github.com/google-gemini/gemini-cli/blob/v0.67.0/packages/core/src/utils/paths.ts)
- [OAuth file and alternative credential loading](https://github.com/google-gemini/gemini-cli/blob/v0.67.0/packages/core/src/code_assist/oauth2.ts)
- [Authentication override](https://github.com/google-gemini/gemini-cli/blob/v0.67.0/packages/cli/src/config/settings.ts)
- [Shared keychain account](https://github.com/google-gemini/gemini-cli/blob/v0.67.0/packages/core/src/code_assist/oauth-credential-storage.ts)
