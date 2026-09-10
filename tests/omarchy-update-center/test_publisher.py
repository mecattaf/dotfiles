#!/usr/bin/env python3
"""Hermetic publication tests: no Nix builds, cache mutation, or laptop access."""
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch


SOURCE = Path(__file__).resolve().parents[2] / "hosts/nas/omarchy-update-publish.py"
SPEC = importlib.util.spec_from_file_location("publisher", SOURCE)
publisher = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(publisher)


class PublisherTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.state = self.root / "state"
        self.state.mkdir()
        self.key = self.root / "host_key"
        subprocess.run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", str(self.key)], check=True)
        self.revision = "a" * 40
        self.calls = []
        self.fail = None

    def tearDown(self):
        self.temporary.cleanup()

    def command(self, *args, **kwargs):
        self.calls.append(args)
        if args[0:3] == ("nix", "flake", "metadata"):
            return json.dumps({"locked": {"rev": self.revision}})
        if args[:2] == ("nix", "build"):
            if self.fail == "build":
                raise RuntimeError("build failed")
            device = args[-1].split("nixosConfigurations.")[1].split(".")[0]
            value = f"/nix/store/{'a' * 32}-nixos-system-{device}-26.05"
            Path(args[args.index("--out-link") + 1]).symlink_to(value)
            return value
        if args[:2] == ("atticd-atticadm", "make-token"):
            return "fixture-token"
        if args[:2] == ("attic", "login"):
            return ""
        if args[:2] == ("attic", "push"):
            if self.fail == "push":
                raise RuntimeError("push failed")
            return ""
        if args[0] == "ssh-keygen":
            if self.fail == "sign":
                raise RuntimeError("sign failed")
            subprocess.run(args, check=True, capture_output=True)
            return ""
        if args[:3] == ("nix-store", "--query", "--requisites"):
            return "\n".join(args[3:])
        self.fail_test(args)

    def fail_test(self, args):
        raise AssertionError(f"unexpected external command: {args}")

    def publish(self):
        with patch.object(publisher, "run", side_effect=self.command):
            return publisher.publish(self.state, "/fixture/checkout", self.revision,
                                     "A reviewed update.\n", list(publisher.DEVICES), str(self.key))

    def test_immutable_source_rejects_branches_and_extra_query(self):
        for revision in ("main", "abc123", "a" * 39, "A" * 40):
            with self.assertRaises(ValueError):
                publisher.immutable_source("https://example.test/fleet.git", revision)
        for source in ("path:/tmp/fleet", "https://example.test/fleet?ref=main", "git+ssh://host/fleet"):
            with self.assertRaises(ValueError):
                publisher.immutable_source(source, self.revision)
        self.assertEqual(publisher.immutable_source("/path with space/fleet", self.revision),
                         "git+file:///path%20with%20space/fleet?rev=" + self.revision)

    def test_success_publishes_only_after_push_and_real_signature_verifies(self):
        manifest = self.publish()
        current = self.state / "public/current"
        self.assertEqual(json.loads((current / "manifest.json").read_text()), manifest)
        self.assertEqual(set(manifest["devices"]), set(publisher.DEVICES))
        build_calls = [call for call in self.calls if call[:2] == ("nix", "build")]
        self.assertEqual(len(build_calls), 2)
        for call in build_calls:
            self.assertIn("--no-update-lock-file", call)
            self.assertIn("?rev=" + self.revision + "#", call[-1])
            self.assertEqual(call[call.index("--max-jobs") + 1], "1")
        push_index = next(i for i, call in enumerate(self.calls) if call[:2] == ("attic", "push"))
        sign_index = next(i for i, call in enumerate(self.calls) if call[0] == "ssh-keygen")
        self.assertLess(push_index, sign_index)
        allowed = self.root / "allowed_signers"
        allowed.write_text("nas " + self.key.with_suffix(".pub").read_text())
        command = ["ssh-keygen", "-Y", "verify", "-f", str(allowed), "-I", "nas",
                   "-n", "fleet-update", "-s", str(current / "manifest.json.sig")]
        original = (current / "manifest.json").read_bytes()
        self.assertEqual(subprocess.run(command, input=original, capture_output=True).returncode, 0)
        self.assertNotEqual(subprocess.run(command, input=original + b"tampered", capture_output=True).returncode, 0)

    def test_failed_build_push_or_signature_preserves_offer_and_roots(self):
        self.publish()
        current = self.state / "public/current"
        previous_target = current.resolve()
        previous_bytes = (current / "manifest.json").read_bytes()
        for failure in ("build", "push", "sign"):
            self.fail = failure
            with self.assertRaises(RuntimeError):
                self.publish()
            self.assertEqual(current.resolve(), previous_target)
            self.assertEqual((current / "manifest.json").read_bytes(), previous_bytes)
            self.assertEqual(len(list((self.state / "public/releases").iterdir())), 1)
            self.assertEqual(len(list((self.state / "roots").iterdir())), 1)

    def test_two_releases_and_their_gc_roots_are_retained(self):
        self.publish()
        first = (self.state / "public/current").resolve()
        self.publish()
        second = (self.state / "public/current").resolve()
        self.assertEqual((self.state / "public/previous").resolve(), first)
        self.publish()
        self.assertEqual((self.state / "public/previous").resolve(), second)
        self.assertFalse(first.exists())
        self.assertEqual(len(list((self.state / "public/releases").iterdir())), 2)
        self.assertEqual(len(list((self.state / "roots").iterdir())), 2)

    def test_revision_mismatch_publishes_nothing(self):
        with patch.object(publisher, "run", return_value=json.dumps({"locked": {"rev": "b" * 40}})):
            with self.assertRaises(ValueError):
                publisher.publish(self.state, "/fixture", self.revision, "notes", ["xps"], str(self.key))
        self.assertFalse((self.state / "public/current").exists())

    def test_keepalive_repushes_and_heads_nars_without_building(self):
        self.publish()
        self.calls.clear()
        with patch.object(publisher, "run", side_effect=self.command), patch.object(publisher, "urlopen") as opener:
            opener.return_value.__enter__.return_value.status = 200
            publisher.keepalive(self.state)
            self.assertEqual(opener.call_count, 2)
            for call in opener.call_args_list:
                self.assertEqual(call.args[0].method, "HEAD")
                self.assertIn("/fleet/nar/", call.args[0].full_url)
        self.assertFalse(any(call[:2] == ("nix", "build") for call in self.calls))
        self.assertTrue(any(call[:2] == ("attic", "push") for call in self.calls))


if __name__ == "__main__":
    unittest.main()
