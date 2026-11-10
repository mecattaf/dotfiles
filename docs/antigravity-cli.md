# Antigravity CLI accounts on NAS

The NAS installs Antigravity CLI from the existing `llm-agents.nix` input.
Only the account launchers reach PATH; each calls the pinned vendor binary
directly. Gemini CLI is removed: Google rejects free individual logins there.

Authenticate each account once in the NAS terminal:

```sh
agy acp --login
agy2 acp --login
agy3 acp --login
```

Open the printed URL in the client browser, choose a different Google account,
and paste the authorization code back into that terminal. Authorization codes
and tokens do not belong in chat, Git or Nix. Later `agy`, `agy2` and `agy3`
launch the interactive CLI for their accounts; `agy2 acp` starts that account's
official ACP server for the DSH extension.

| Command | Private account root |
| --- | --- |
| `agy` | `~/.local/share/antigravity-cli/accounts/1` |
| `agy2` | `~/.local/share/antigravity-cli/accounts/2` |
| `agy3` | `~/.local/share/antigravity-cli/accounts/3` |

An explicit `XDG_DATA_HOME` replaces `~/.local/share`. The root is mode 0700,
and new files use umask 077. The vendor stores each Google token at
`<account-root>/antigravity-cli/antigravity-oauth-token`. HOME, cwd and arguments
are preserved. Model and settings choices remain writable vendor state.

The supported `--gemini_dir` and `--app_data_dir` flags select each root.
The **underscore spelling** works with both the TUI and ACP in version 1.5.3;
the hyphen spelling only works with ACP. Global `--help` short-circuits parsing
and is insufficient evidence that a flag actually works.

Google OAuth otherwise uses one shared OS-keyring entry regardless of data
directory. `DBUS_SESSION_BUS_ADDRESS=disabled:` is local to the CLI child and
makes the official composite store fall back to the account's token file.
This does not change any live D-Bus service. CLI tool children inherit this
environment; D-Bus-dependent commands need a deliberate real session address.
The helper variables `ANTIGRAVITY_CREDENTIAL_SCOPE` and `AGY_ACCOUNT` do not
isolate Google sign-in and must not be used for that purpose.

NAS has a Zen+ CPU whose RDRAND instruction is unreliable (also blacklisted by
the kernel). Google's BoringSSL checks CPUID itself and aborts without the
per-command `OPENSSL_ia32cap=~0x4000000000000000` mask. This supported mask clears
only RDRAND; OS entropy and crypto health checks remain enabled. No services,
kernel settings or microcode are changed. The automatic vendor updater is
disabled; the existing llm-agents input watch owns version updates.

The free Individual plan includes CLI with a workload-dependent weekly quota;
it does not promise the retired Gemini CLI's 1,000 daily requests. The exact
models and limits belong to the signed-in account. No API key is required.

Sources: [plans](https://antigravity.google/docs/plans/),
[authentication](https://antigravity.google/docs/install),
[ACP](https://antigravity.google/docs/cli/acp),
[BoringSSL CPU masking](https://boringssl.googlesource.com/boringssl/+/HEAD/crypto/cpu_intel.cc).
The retained [Gemini investigation](gemini-cli.md) records the superseded path.
