# Frozen real-link software cohort

This cohort observes one input byte written into a private client PTY and the
arrival of its exact sequence marker from the NAS. It uses the actual Tailnet
link from `100.121.160.100` to `100.65.85.114`. It does not observe Kitty,
Domicile, a display frame, a physical key, or light from the screen. Its absolute
values must not be combined with the separate native Kitty observer cohort.

The five frozen paths are plain OpenSSH with default timing protection, plain
OpenSSH with timing protection explicitly disabled, SSH PTY to the retained
holder under each of those policies, and the compiled local holder client over
an SSH Unix-socket forward. The final path has no interactive TTY on its SSH
connection and does not provide interactive keystroke padding. Its nominal
`ssh -G` timing setting does not make its policy equivalent to the first path.
The receipt records effective SSH settings and this distinction.

Each path runs idle and busy, one case at a time, for three seeded randomized
rounds. The busy worker writes exactly 219 bytes on row 20 at intervals of at
least 2 ms; echoes occupy row 10. The geometry is 120 columns by 40 rows with
1560 by 1080 pixels. Both processes are pinned to declared CPUs, with actual
affinity and load recorded. No governor or live desktop setting is changed.

Each case sends five input-quiet samples, each after 3.25 seconds without input,
then ten warmups, then 80 ongoing samples. Ongoing targets follow an absolute
clock with seeded 40–80 ms intervals. The reader continually drains output while
waiting. Actual send and receive times, intervals, and lateness remain in the
receipt; late samples are counted and retained. Busy cases remain output-active
during the input-quiet interval. The resulting quiet and ongoing distributions
are separate, with 15 and 240 samples per path and workload respectively.

Every echo contains the full random case identity, sequence number, and input
byte. A prior case, a prior sequence, or an ANSI control sequence cannot satisfy
the oracle. The driver retains each case's raw output with a 16 MiB incremental
bound. Binary and source SHA256 values, interpreter paths, worker PID/start
identity, actual geometry, SSH connection addresses, and namespaces are recorded.

All runtime endpoints use `runtime-test`, including the client driver, each NAS
SSH action, and a bounded NAS supervisor. That supervisor holds one private PID
namespace across reconnects and owns exact per-case sockets under the private
run directory. It accepts only fixed typed operations. A case closes before the
next starts. Cleanup attempts local PTY, forward, and remote holder cleanup
independently, records escalation, and refuses success if owned processes remain.
The work deadline is 840 seconds, reserving 60 seconds for cleanup; the NAS
supervisor has an independent 860-second deadline. HOME remains unchanged.

Source and nonsecret holder binaries are staged at
`/home/tom/.wt/kitty-consolidation/network-cohort` on both hosts. The client uses
its existing SSH identity in place, strict NAS host-key verification, no agent,
no connection sharing, and an empty SSH configuration file. The only forwarding
exception is the exact private Unix socket in the forwarding case. There is no
Kitty process, live Kitty socket, Wayland connection, or input device in this
cohort.

The preparation admission uses `--functional-only`: two sequence-checked keys
per case and fresh reconnects for holder paths, with no latency samples saved.
Final-source admission passed all ten cases and confirmed the same worker PID
and start identity after reconnect. Receipt:
`/home/tom/.wt/kitty-consolidation/artifacts/native-unix-forward/real-network/admission-final/receipt.json`.

Collection requires an explicit `--collect` invocation and refuses to start
before 2026-11-08 03:00 UTC. It is not scheduled automatically. The approved
client command, itself launched through strict SSH from NAS, is:

```sh
/home/tom/.local/bin/runtime-test -- python3 \
  /home/tom/.wt/kitty-consolidation/network-cohort/frozen_network_cohort.py \
  --collect --client-cpu 21 --nas-cpu 7 \
  --nas-python /etc/profiles/per-user/tom/bin/python3
```
