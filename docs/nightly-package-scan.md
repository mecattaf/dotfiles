# Nightly package scan list

`lib/nightly-packages.json` is the owner-requested package inventory for a
mechanical update scan. It does not add a clock, daemon, agent or activation
command. The agency protocol owns when work is due and whether a verified
candidate can be switched safely.

The ten families reconcile the October 10 seven-package request with later
instructions: DSH replaces pi; Tailscale, Domicile and Gufo join the list.
The November 15 clarification explicitly includes current kitty, Chrome and
Domicile on the mobile client, and permits automatic client flashing only
at home. Unknown home presence defers; a working tailnet route proves no
physical location.

For each row, `hosts` names existing consumers, `provider` identifies the
packaging boundary, `versionAttributes` identifies Nix evaluation paths
(`{host}` is substituted from that row), and `updateMechanism` records how
to advance it. These are inventory data, not shell commands. Actual package
attributes and source interfaces must be checked against the candidate.

A mechanical consumer reads stable release feeds/catalogs, compares versions
and reports `current`, `update-available`, `blocked` or `unknown`, including
packaging lag. No cloud LLM is needed; optional judgment may use local Gufo.
The file is a declared interface; no scanner consumer is installed by this
change. Never interpret absent evidence as current.

Refreshing `llm-agents` covers its selected installed catalog packages.
Refreshing `nixpkgs-fresh` alone does not advance kitty's source recipe or
fish/Tailscale while they remain on host base pins. Those coverage gaps must
be reported and addressed explicitly. Incidental catalog/overlay leaves
remain visible in closure review; they are not additional independently
requested package families.

Successful userspace maintenance switches safe updates without reboot and
checks normal fresh-launch paths. Existing processes may retain old code.
Kernel staging and any blocked runtime transition are reported separately;
a boot-staged application update does not count as an active update. Gufo
qualification preserves current routes and moves no model weights. Herdr
updates preserve the server that owns live PTYs.
