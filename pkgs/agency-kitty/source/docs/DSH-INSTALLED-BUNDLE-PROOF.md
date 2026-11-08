# Installed DSH bundle admission

The installed `@agency/kitty-native` bundle and immutable NAS helper work in the
actual DSH 0.2.2-rc.1 Host. This required a fixture update, with no production
plugin change.

The previous probe used the DSH 0.2.1 single-call execution API. In 0.2.2,
`ctx.tools.execute()` selects an executor and accepts a batch of raw model-call
records. Seeing our registered schema does not imply that the asynchronously
mounted native executor is ready. The old probe failed before executing the
helper, with `ToolExecutorUnavailableError`.

Primary evidence is the exact installed DSH package at
`/nix/store/80blazz6zwcid0qdmbszhk21j5qmihxs-dsh-0.2.2-rc.1`:

- `dsh-tools/lib/index.js`, `selectExecutor()` and `execute()` select a scoped
  executor and delegate its complete batch.
- `dsh-tools/lib/types/executor.d.ts` defines `ToolBatchInput.calls` and correlated
  `ToolBatchResult.results`.
- `dsh-llm/lib/types/types.d.ts` defines raw calls with `type`, `id`, `name` and
  JSON-string `arguments`.
- `dsh-base/cordis.patch.yml` mounts the native executor by default;
  `dsh-tool-executor-native/lib/index.js` registers it with `setExecutor()`.

These paths are beneath the installed CLI's
`lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/` directory.

The corrected probe waits for both the registered tool and selected executor,
executes three single-element batches, and verifies each returned call ID. It
retains the old single-call path for the separately qualified 0.2.1 baseline.
A private `llm/stream` guard rejects any provider invocation. No Agent turn runs.

The fixture runs through `runtime-test`, then masks the real home with an exact
mount-identity assertion while preserving the `HOME` value. A private network
namespace permits only loopback. The Host and helper receive no inherited
`PYTHONPATH` or `PYTHONHOME`; the helper resolves its own immutable package.

The admitted bundle is
`/nix/store/87b874azygq8q0qx0z22lf7lyaxpsiq5-agency-kitty-dsh-0.1.0` and helper is
`/nix/store/rjrnqfsvawck1f2z0vlhmccqi2brrsl9-agency-kitty-0.1.0/bin/agency-kitty`.
The fixture verifies the package's `dsh.bundle.patch` discovery manifest and its
rendered absolute helper path, rather than inserting a source plugin directly.

Compute evidence:

- Latest immutable-bundle proof:
  `/home/tom/kitty-consolidation/proofs/dsh-installed-bundle-4-final/receipt.json`.
  Three invocations, two metadata rows, exact chat filtering, unknown UUID
  refusal, unchanged catalogue, zero provider calls, Host exit 0.
- Legacy 0.2.1-rc.2 compatibility proof:
  `/home/tom/kitty-consolidation/proofs/dsh-installed-bundle-legacy-1/receipt.json`.
  The same immutable bundle/helper passes its old single-call service API.
- Original failed proof is retained at `dsh-installed-bundle-1`. Iteration 2
  successfully exercised the new API but terminated the extra bubblewrap
  supervisor with SIGTERM. Iteration 3 moved the namespace reexec outside the
  Host process supervisor and achieved normal Host exit 0. The final proof adds
  exact mount identity and fixture-source hashes.

This admission proves read-only catalogue discovery and execution. It does not
claim a model turn, terminal input, launch, resume or desktop window movement.
