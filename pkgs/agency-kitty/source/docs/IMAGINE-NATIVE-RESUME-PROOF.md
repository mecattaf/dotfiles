# Native Imagine resume click qualification

The installed-pair qualification passed in 11.34 seconds. The retained
[receipt](evidence/native-imagine-resume/receipt.json),
[invocation](evidence/native-imagine-resume/invocation.json) and
[proof index](evidence/native-imagine-resume/proof-index.json) identify the
exact binaries, complete snapshots, trusted pointer events and cleanup.
The seat helper is `gwgza962…`; the NAS helper is `llib0gcd…`, both from source
`48307add` / `af93cf0`. Neither helper used a Python source override.

`tests/native_imagine_resume.py` is a post-timing-phase functional fixture. It
uses the complete Imagine `8954bbe` production bundle, official engine `63db244`,
the installed seat and NAS helpers, a private real SSH server and retained NAS
fish processes. It changes no Desktop, AgencyKeys, deployment module or engine.

The original NAS catalogue source is copied and patched only in the private
fixture. Its installed native metadata companion executes the real NAS helper.
The only substituted provider is a valid fixed chat-attention snapshot; the
separate DSH PTY carrier is absent and explicitly unavailable. This is not an
agent/provider or DSH transport qualification.

All ten currently configured Imagine workspaces receive actual native Kitty
occupants. Trusted pointer events then click the actual native terminal buttons.
The real helper validates the canonical NAS UUID/chat link over SSH and launches
the matching native Kitty class. Read-only Imagine snapshot IPC observes window
identity, workspace placement and focus. Exact NAS fish PID/start identities
must survive. Additional cases hold an actual helper receipt or actual launch
to verify that newer focus and navigation choices win, and create duplicate
native classes to verify that a disabled human action allocates nothing.

The saved-terminal catalogue is independent of chat slots. The global Imagine
workspace inventory in this fixture remains the existing fixed ten workspaces;
this test does not demonstrate a redesign of that global inventory.

The fixture requires `runtime-test`, masks the real home at its existing path
without changing HOME, uses private runtime/network/login-record namespaces,
and creates only throwaway SSH keys. A separately invoked root SSH supervisor
joins that exact private namespace. Every cleanup signal is confined to owned
child handles or a random fixture token plus checked PID/start identity inside
the exact private PID namespace. Files, logs, helper receipts and snapshots stay
in the private output directory. Unexpected errors remain in its receipt.

The first installed attempt exposed a real launch bug: detached Kitty inherited
the desktop helper's capture pipes, keeping the real Imagine helper request in
its Opening state. `open_window()` now redirects Kitty startup diagnostics to
exclusive 0600 files under the private session state's `launches` directory.
The receipt schema is unchanged. Its two regression checks verify actual EOF
while the detached native child stays alive, diagnostic preservation and a
symlink-directory refusal. Their retained log is
[diagnostics-regression.log](evidence/native-imagine-resume/diagnostics-regression.log).
The final installed-pair run includes that fix and passes all four cases.

This proof uses CDP's trusted engine pointer routing to actual shell/native
widgets, not a call to React handlers or a mocked compositor API. It qualifies
functional native launch, placement, focus, identity and refusal behavior; it
does not measure a physical keyboard, rendering latency, DSH transport or a real
model provider. The fixed chat-attention snapshot and absent DSH carrier are
declared fixture inputs. Final cleanup reports no surviving owned processes.
