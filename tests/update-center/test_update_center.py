"""Hermetic tests for hosts/nas/update-center.sh (#354 producer half).

nix, nix-store, attic and atticd-atticadm are fakes; jq and ssh-keygen are
real, so the manifest bytes and the signature are exactly what an adopter
verifies.
"""

import json
import os
import shutil
import stat
import subprocess
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
SCRIPT = os.path.join(REPO, "hosts", "nas", "update-center.sh")

META = {
    "url": "github:mecattaf/dotfiles/abc123?narHash=sha256-x",
    "lastModified": 1789320532,
    "locks": {
        "nodes": {
            "root": {"inputs": {}},
            "tally-b": {"locked": {"type": "git", "url": "https://github.com/mecattaf/tally",
                                   "rev": "b3a0", "narHash": "sha256-tallyb"}},
            "herdr-kitten": {"locked": {"type": "github", "owner": "mecattaf", "repo": "herdr-kitten",
                                        "rev": "c0ff", "narHash": "sha256-kitten"}},
            "nixpkgs": {"locked": {"type": "github", "owner": "NixOS", "repo": "nixpkgs",
                                   "rev": "e258", "narHash": "sha256-nixpkgs"}},
        }
    },
}

FAKES = {
    "nix": r"""#!/bin/sh
echo "nix $*" >> "$FIXTURE/calls.log"
case "$1" in
  flake) cat "$FIXTURE/meta.json" ;;
  hash) for a; do h="$a"; done; echo "nix32-${h#sha256-}" ;;
  build)
    for a; do ref="$a"; done
    host="${ref#*nixosConfigurations.}"; host="${host%%.*}"
    case " $FAIL_BUILD " in *" $host "*) echo "error: build of $host failed" >&2; exit 1 ;; esac
    echo "$UPDATE_CENTER_STORE_DIR/$(printf '%s' "$host" | cut -c1-1 | sed 's/./&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&/')-nixos-system-$host-26.11" ;;
esac
""",
    "nix-store": r"""#!/bin/sh
echo "nix-store $*" >> "$FIXTURE/calls.log"
case "$1" in
  --print-fixed-path) echo "/nix/store/fixed-$4-source" ;;
  --check-validity)
    case "$2" in
      /nix/store/fixed-*) [ -e "$FIXTURE/valid/$(basename "$2")" ] ;;
      *) [ -e "$2" ] || [ -e "$FIXTURE/valid/$(basename "$2")" ] ;;
    esac ;;
esac
""",
    "attic": r"""#!/bin/sh
echo "attic $*" >> "$FIXTURE/calls.log"
[ "$1" = push ] || exit 0
for a; do p="$a"; done
host="${p##*-nixos-system-}"; host="${host%-*}"
case " $FAIL_PUSH " in *" $host "*) exit 1 ;; esac
exit 0
""",
    "atticd-atticadm": "#!/bin/sh\necho token\n",
}


class UpdateCenterTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="update-center-test-")
        self.bin = os.path.join(self.tmp, "bin")
        self.state = os.path.join(self.tmp, "state")
        self.store = os.path.join(self.tmp, "store")
        os.makedirs(self.bin)
        os.makedirs(os.path.join(self.tmp, "valid"))
        os.makedirs(self.store)
        for name, text in FAKES.items():
            path = os.path.join(self.bin, name)
            with open(path, "w") as stream:
                stream.write(text)
            os.chmod(path, os.stat(path).st_mode | stat.S_IEXEC)
        with open(os.path.join(self.tmp, "meta.json"), "w") as stream:
            json.dump(META, stream)
        self.key = os.path.join(self.tmp, "host_key")
        subprocess.run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", self.key], check=True)
        with open(self.key + ".pub") as stream:
            pub = stream.read().strip()
        self.signers = os.path.join(self.tmp, "allowed_signers")
        with open(self.signers, "w") as stream:
            stream.write(f'nas namespaces="fleet-update" {pub}\n')

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def run_center(self, *args, fail_build="", fail_push=""):
        env = dict(os.environ)
        env.update({
            "PATH": self.bin + ":" + os.environ["PATH"],
            "FIXTURE": self.tmp,
            "FAIL_BUILD": fail_build,
            "FAIL_PUSH": fail_push,
            "UPDATE_CENTER_HOSTS": "coordinator worker client",
            "UPDATE_CENTER_STATE_DIR": self.state,
            "UPDATE_CENTER_SIGNING_KEY": self.key,
            "UPDATE_CENTER_STORE_DIR": self.store,
        })
        return subprocess.run(["bash", SCRIPT, *args], env=env, capture_output=True, text=True)

    def pointer(self, host):
        return os.path.join(self.state, "public", "candidates", host)

    def manifest(self, host):
        with open(os.path.join(self.pointer(host), "manifest.json"), "rb") as stream:
            return stream.read()

    def verify(self, host):
        d = self.pointer(host)
        with open(os.path.join(d, "manifest.json"), "rb") as stream:
            return subprocess.run(
                ["ssh-keygen", "-Y", "verify", "-f", self.signers, "-I", "nas", "-n", "fleet-update",
                 "-s", os.path.join(d, "manifest.json.sig")],
                stdin=stream, capture_output=True,
            ).returncode

    def test_all_hosts_publish_signed_manifests(self):
        r = self.run_center()
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        for host in ("coordinator", "worker", "client"):
            self.assertEqual(self.verify(host), 0)
            m = json.loads(self.manifest(host))
            self.assertEqual(m["schema"], 1)
            self.assertEqual(m["host"], host)
            self.assertEqual(m["rev"], META["url"])
            self.assertEqual(m["last_modified"], META["lastModified"])
            self.assertIn(f"-nixos-system-{host}-", m["store_path"])
            self.assertTrue(os.path.islink(self.pointer(host)))
            self.assertFalse(os.readlink(self.pointer(host)).startswith("/"))

    def test_failed_build_keeps_previous_pointer(self):
        self.assertEqual(self.run_center().returncode, 0)
        before = self.manifest("coordinator")
        before_link = os.readlink(self.pointer("coordinator"))
        worker_before = os.readlink(self.pointer("worker"))
        META2 = dict(META, lastModified=META["lastModified"] + 10)
        with open(os.path.join(self.tmp, "meta.json"), "w") as stream:
            json.dump(META2, stream)
        import time
        time.sleep(1.1)  # a distinct release stamp
        r = self.run_center(fail_build="coordinator")
        self.assertEqual(r.returncode, 1)
        self.assertIn("build FAILED for coordinator", r.stderr)
        self.assertEqual(self.manifest("coordinator"), before)
        self.assertEqual(os.readlink(self.pointer("coordinator")), before_link)
        self.assertNotEqual(os.readlink(self.pointer("worker")), worker_before)
        self.assertEqual(json.loads(self.manifest("worker"))["last_modified"], META2["lastModified"])
        self.assertEqual(self.verify("worker"), 0)

    def test_failed_push_publishes_nothing(self):
        r = self.run_center(fail_push="worker")
        self.assertEqual(r.returncode, 1)
        self.assertFalse(os.path.lexists(self.pointer("worker")))
        self.assertTrue(os.path.lexists(self.pointer("client")))

    def test_seed_preflight_names_gaps(self):
        open(os.path.join(self.tmp, "valid", "fixed-nix32-tallyb-source"), "w").close()
        r = self.run_center()
        self.assertIn("seed present: tally-b", r.stdout)
        self.assertIn("seed-missing herdr-kitten github:mecattaf/herdr-kitten@c0ff", r.stderr)
        self.assertNotIn("nixpkgs", r.stdout + r.stderr.replace("github:mecattaf", ""))

    def test_releases_are_pruned(self):
        import time
        for _ in range(5):
            self.assertEqual(self.run_center().returncode, 0)
            time.sleep(1.1)
        releases = [n for n in os.listdir(os.path.join(self.state, "public", "releases")) if n.startswith("worker-")]
        self.assertEqual(len(releases), 3)
        self.assertEqual(self.verify("worker"), 0)

    def test_publish_only(self):
        host_path = os.path.join(self.store, "w" * 32 + "-nixos-system-worker-26.11")
        os.makedirs(host_path)
        r = self.run_center("--publish-only", "worker", host_path, "github:mecattaf/dotfiles/abc123")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(json.loads(self.manifest("worker"))["store_path"], host_path)
        self.assertEqual(self.verify("worker"), 0)
        self.assertNotIn("nix build", open(os.path.join(self.tmp, "calls.log")).read())

    def test_publish_only_refuses_wrong_or_missing_closure(self):
        coord = os.path.join(self.store, "c" * 32 + "-nixos-system-coordinator-26.11")
        os.makedirs(coord)
        r = self.run_center("--publish-only", "worker", coord, "github:mecattaf/dotfiles/abc123")
        self.assertEqual(r.returncode, 2)
        missing = os.path.join(self.store, "w" * 32 + "-nixos-system-worker-26.11")
        r = self.run_center("--publish-only", "worker", missing, "github:mecattaf/dotfiles/abc123")
        self.assertEqual(r.returncode, 2)
        self.assertFalse(os.path.lexists(self.pointer("worker")))

    def test_publish_only_refuses_when_push_fails(self):
        host_path = os.path.join(self.store, "w" * 32 + "-nixos-system-worker-26.11")
        os.makedirs(host_path)
        r = self.run_center("--publish-only", "worker", host_path, "github:mecattaf/dotfiles/abc123",
                            fail_push="worker")
        self.assertEqual(r.returncode, 1)
        self.assertFalse(os.path.lexists(self.pointer("worker")))


if __name__ == "__main__":
    unittest.main()
