# PS4 GTT capacity qualification

`ps4-memory-probe` distinguishes a configured memory ceiling from a successful
allocation. It uses libdrm/amdgpu on one explicitly named AMD render device,
without KFD, an OpenCL/Vulkan runtime, a GPU queue or shader submission.

The default command performs only identity, heap and memory queries:

```sh
~/.local/bin/runtime-test --allow-render /dev/dri/renderD128 -- \
  ps4-memory-probe --node /dev/dri/renderD128
```

Inspect the actual node and GPU identity before substituting a device name.
The program refuses symlinks, non-render devices, non-AMD devices and drivers
other than amdgpu. It opens the named render node read-write because libdrm's
subsequent allocation APIs require that access; query mode allocates no BO,
records no command stream and never makes a model-serving request.

An explicit allocation requests one GTT BO, reserves a distinct GPU virtual
address and asks the kernel to map that BO at the GPU address:

```sh
~/.local/bin/runtime-test --allow-render /dev/dri/renderD128 -- \
  ps4-memory-probe --node /dev/dri/renderD128 --allocate-mib 1 --touch
```

The one-MiB command is the bounded development smoke test. Run it on Strix only
after the orchestrator has approved that specific device/test stage. Do not
run the PS4-sized allocation on the Strix development host.

On the actual PS4, once its ordinary memory map, TTM ceiling and idle service
state have been inspected, the target command is:

```sh
~/.local/bin/runtime-test --allow-render /dev/dri/renderD128 -- \
  ps4-memory-probe --node /dev/dri/renderD128 --allocate-mib 7168 --touch \
  | tee ps4-memory-7168MiB.jsonl
```

Preserve the command's exit status when recording through a pipe, for example
with the fleet Bash shell's `set -o pipefail`. Never substitute a lower-precision
model or cache configuration to make this memory test pass.

Both the initial preflight and the check immediately before allocation require
`MemAvailable >= requested bytes + 256 MiB`. The tool rechecks the 256-MiB
headroom during page touching and aborts if it disappears. This is a measured
preflight, not a memory reservation against competing processes. Allocation
size conversion and page alignment are checked before any allocation.

Only `--touch` creates the CPU mapping. It touches two bytes on every CPU page
of the same BO and verifies the first, middle and last page patterns. It makes
no second weight-sized allocation. A small fixed-size vector queries `mincore`
in chunks. If that device mapping does not support `mincore`, residency remains
explicitly unknown; CPU touching and accepted mappings retain their separate
results. Even a successful residency observation does not pin the pages.

Each stage writes a JSON line with the C source SHA256 embedded at build time.
The records keep these observations separate:

| Observation | What it establishes |
| --- | --- |
| `memTotalBytes`, `memAvailableBytes` | Ordinary Linux physical-memory accounting at that stage. |
| `gttReportedBytes`, usage and maximum allocation | The driver's reported shared backing policy, including other users. These are not extra RAM to add to `MemTotal`. |
| `allocationAccepted` | The driver accepted the one requested GTT BO. |
| `gpuVaMappingAccepted` | The kernel accepted that BO's GPU-address-space mapping. |
| `cpuTouchedPages`, CPU sample readback | Every listed page was CPU-accessible and the sampled patterns read back on the CPU. |
| `cpuResidentPages` | `mincore`'s separately observed count, or `null` when unavailable. |
| GPU read, bandwidth and coherence fields | Always false in this tool. Those need a subsequent known shader and readback oracle. |

Normal failures and SIGINT/SIGTERM interruptions release the CPU map, GPU map,
GPU VA range, BO, libdrm handle and file descriptor in reverse order, reporting
release failures explicitly. Unexpected SIGBUS/SIGSEGV faults are not hidden or
converted into passing receipts. Stages preceding a fault remain in the JSONL.

The API contract is taken from the fleet's pinned libdrm 2.4.134
[`amdgpu.h`](https://gitlab.freedesktop.org/mesa/drm/-/blob/libdrm-2.4.134/amdgpu/amdgpu.h)
and its accompanying `amdgpu_drm.h`: GTT allocation, VA reservation/map,
CPU map/unmap, heap queries and resource release. No inference backend is
implemented by this probe.

## Recorded development validation

On 27 November 2026 the package compiled on Strix with `-Wall -Wextra -Werror`.
Nine guard cases passed under `runtime-test` without passing any GPU device
into the test: malformed/overflowing sizes, missing allocation for `--touch`,
an invalid node type, the large-request memory preflight and query mode with
the render node unavailable. All reported no accepted allocation or submission.

The orchestrator then authorized exactly a query and a one-MiB allocation on
Strix's `/dev/dri/renderD128`, under the installed runtime wrapper and the
candidate render-only wrapper nested inside it. The query returned four
passing stage records and requested zero bytes. The one-MiB test returned
15 passing stages: one GTT BO, a GPU VA mapping and CPU mapping were accepted;
all 256 CPU pages were touched and reported resident by `mincore`; the three
sample patterns read back correctly. Every resource-release API returned
success and the process exited zero. No shader or model ran in either test.

Both receipts identify C source SHA256
`49540d9cff115455a0244081ed2eea6c55aeecbe8e2945b4c57d2c5f1c5e08dc`.
The query JSONL SHA256 is
`f46d6c8d3ac39ed40a28d8f572ed9b2b45462ebf907fb59be0c238f56634f4b4`;
the one-MiB JSONL SHA256 is
`db3a4bc6b4d7bfdd1991956ea7733056fe6e6b417596515cabc58ae4b95b5638`.
These are bounded API/cleanup observations on Strix, not PS4 capacity or speed
results. No seven-GiB allocation was attempted on Strix.

## Unknowns and proposed defaults

Physical PS4 allocation and page-touch results are pending until this tool runs
on the console. Keep any TTM limit above the requested BO large enough for the
driver's other allocations, while separately preserving OS headroom. The tool
does not change that limit, clocks, driver state, model settings or services.
An accepted seven-GiB BO is a capacity result; preserve the separate follow-up
for useful GPU bandwidth, visibility/coherence, Garlic parity and Bonsai inference.
