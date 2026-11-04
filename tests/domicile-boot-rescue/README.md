# Booted-system rescue preparation

A bounded Python 3 standard-library tool for the Zenbook's actual NixOS
systemd-boot layout: /boot is both ESP and $BOOT, x86 EFI-stub Linux,
Secure Boot disabled. It reads /run/booted-system, never substitutes
/run/current-system or a firmware-history entry for the booted closure.
It does not build, activate, select an entry, change a password or restart a
service. The installer template is deliberately separate from the reader.

Run from NAS after committing this worktree (choose a fresh output directory):

~~~sh
set -o pipefail
fleet-exec strix-coordinator --cwd /home/tom/compute/dotfiles-domicile-boot-rescue -- cat tests/domicile-boot-rescue/run-nas.py |
  python3 - --out /home/tom/.local/state/domicile-autonomous-20261104/boot-rescue/recheck-01
~~~

This streams only the read-only observer to ssh client sudo -n python3 - observe.
SSH credentials remain on NAS. Snapshot validation, script generation and
an actual systemd-boot 261 parsing/ordering preview run on Strix. Only bounded
JSON, entry text, plan, the generated reviewed installer and receipt return to
NAS. The observer records file magic metadata, sizes and SHA-256; no kernel,
initrd or checkout is copied. A fresh output directory is required and failed
runs retain their receipts.

The client observer uses read-only bootctl commands, findmnt and
nix-store -qR. **Do not add nix-store --query --roots to this read-only
path:** an exploratory invocation unexpectedly removed stale temporary-root
records on 2026-11-04. It was excluded from the delivered runner. That incident
is recorded separately in the NAS run folder.

plan.json, PLAN.txt, rescue-entry.conf, install-reviewed.py, preview.json
and receipt.json are the review artifacts. The before/after snapshots include
hashes of EFI boot/default/oneshot selectors and all existing entry contents.
The closure proof enumerates registered references and checks every store path
exists; it hashes the list and the three source files. It does not rehash every
file in the full system closure. The Strix preview uses small placeholder assets
in a private ESP-shaped directory, never a host ESP. It proves parsing and
entry order, not firmware execution or a successful rescue boot.

The installed NixOS bootloader source is read as text, never sourced or executed.
Its measured GC removes /EFI/nixos/* and nixos-*.conf entries. Rescue files
therefore live in /EFI/domicile-rescue/ and a named domicile-rescue-*.conf.
The entry uses sort-key nixos and version Generation 0 rescue, empirically
below the installed positive Generation versions. A plain version 0 is a
regression: systemd-boot treats it as newer. Wildcard defaults outside the
measured nixos-* pattern and unknown version layouts are refused.

## Later installation, with Tom at the keyboard

No installer is run during preparation. Refresh the dry run if any identity,
boot, entry, kernel or configuration state has changed. Review the generated
script, its hash and preview before authorizing the physical transition.
The exact root command with the full expected closure is printed in PLAN.txt.
Run that command on client only after separate authorization, capturing stdout
and stderr as an installation receipt. The artifact is self-contained Python;
there is no repo import on client. It refuses a wrong hostname, machine, boot ID,
source digest, command line, layout, selector, entry, installed closure or
destination collision before writing.

The installer creates a permanent direct root under /nix/var/nix/gcroots/
to the complete booted system closure **first**, outside the auto-root reaper.
It fsyncs that root, stages and hashes the immutable kernel and initrd on the
ESP, then atomically publishes each by renameat2(RENAME_NOREPLACE). It writes
and fsyncs the entry last and publishes it atomically without replacing any
file. It calls only bootctl list to verify a real Type #1 entry with the exact
paths and options, unchanged effective default, unchanged EFI selectors and
unchanged existing entries/loader.conf. It never writes EFI variables or a
default/oneshot selector.

After a post-publication verification/fsync failure it withdraws only its new
entry. Partial assets, stages and GC protection remain for inspection, and it
exits with failure. A crash or power loss can leave a partial install; reruns
refuse collisions. Inspect and reconcile them explicitly rather than deleting
protection blindly. The directory lock coordinates this installer with itself;
avoid concurrent deployment or ESP maintenance. No live FAT write or power-loss
test was done in this preparation.

Require INSTALLED_VERIFIED_NOT_DEFAULT before treating the entry as present.
Then confirm the named entry in the physical systemd-boot menu and manually
select it for a supervised boot test. Until that succeeds this is a prepared
recovery path, not a proven rescue boot. Keep the GC root, entry and dedicated
assets until recovery is no longer needed; remove those exact three artifact
paths and root only under a separately reviewed cleanup.

## Tests

All fixture/temporary-runtime experiments run on Strix through the wrapper:

~~~sh
fleet-exec strix-coordinator --cwd /home/tom/compute/dotfiles-domicile-boot-rescue -- \
  /home/tom/.local/bin/runtime-test -- \
  python3 -m unittest discover -s tests/domicile-boot-rescue -p 'test_*.py' -v
~~~

Fixtures cover failure inputs, stale review and tampering, actual systemd-boot
sorting, generated standalone-script authorization, preflight no-write behavior,
failed copy retention, postverification withdrawal, entry fsync failure and
atomic refusal to overwrite. Filesystem phase tests use only temporary fixture
directories with client observations mocked. No Nix build is needed.
