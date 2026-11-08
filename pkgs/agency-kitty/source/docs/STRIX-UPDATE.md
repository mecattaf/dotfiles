# Strix update and activation receipt

The user explicitly requested latest Kitty, Codex, Claude Code and DSH in
dotfiles, followed by a Strix update and qualification there. This pass built
and activated a NixOS generation on `strix-coordinator`; it did not reimage a
disk or reboot the machine. No NAS or client generation was switched.

Dotfiles revision `943175b0884b81bbbcfbcd8506a88afb1d959ebd` carries Kitty0.50.0,
Codex0.167.0, Claude Code2.1.319 and DSH0.2.2-rc.1. Only the harness catalogue
lock closure and the explicit Kitty leaf recipe changed their relevant pins.
Kernel, Mesa and the host nixpkgs source remained pinned. The stable NAS recipe
needed the qualified fresh Go1.26.10 and shader-slang2026.19 build tools; its
old build tools could not compile the new source offline. Both Kitty build
variants passed all1,383 upstream tests.

The final activated runtime is:

```
/nix/store/cpn7dg6mrf70a5d7zli6pi61nyc3qhg5-nixos-system-strix-coordinator-26.11.20260723.e2587ca
```

The persistent system profile points to the matching deploy-rs activatable
wrapper, `llhddx3875sr9499hhpgpsfqkcg9g9xc`. The exact Kitty used by the final
native proofs is `/nix/store/rs4s3ggn03a65bbwj9r1ps20d4kichm1-kitty-0.50.0/bin/kitty`.
It is in the system closure through the editor dependencies. The headless
compute role does not put Kitty on its ordinary command PATH, and the NAS-only
harness role was not moved to compute. Tests invoke the new binaries by their
exact store paths. This is not a claim that live NAS harness sessions changed.

## Existing hardware failure and deployment recovery

`thunderbolt-ibverbs-check.service` was already failed before the switch. The
activation retried that check and waited its300-second timeout. It failed
again with the same hardware condition after the new system and Home Manager
had activated. No policy, module requirement, timeout or failed-state evidence
was weakened or hidden.

The initial deploy-rs engine returned the activation warning and tried its
automatic rollback. Its old generation lacked `deploy-rs-activate`, so the
legacy rollback could change the persistent profile but could not reactivate
the old runtime. This left a temporary runtime/profile mismatch. The retained
logs record the failed rollback; it was not treated as a clean deployment.

After verifying the exact new runtime, unchanged kernel, SSH availability,
Gufo `/health` response, and a failed-unit list identical to the preflight,
the local deploy-rs engine finalized the already running reviewed generation
with its `--boot` mode. This repaired the persistent profile without rerunning
or restarting the hardware check. The final runtime and persistent profile are
consistent. The pre-existing hardware failure remains visible.

The compute host deliberately lacks the NAS deployment SSH credential. The
local activation engine avoided copying it or forwarding an agent. No user
manager, live NAS Herdr, harness session, SSH daemon or model server was
restarted to repair an experiment. The NAS Herdr PID/start identity stayed
unchanged. An owned confirmation observer was terminated after its deployment
engine had exited; no service was killed.

Final and preflight receipts are in `docs/evidence/strix-deploy/`. Full logs,
closure diffs and intermediate failure receipts remain at
`strix-coordinator:/home/tom/work/kitty-consolidation/strix-release-deploy/`.
The `deploy-activate` build gate built all four hosts' closures on compute;
only the coordinator generation was activated.
