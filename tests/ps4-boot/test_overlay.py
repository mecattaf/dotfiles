import gzip
import importlib.util
from pathlib import Path
import stat
import unittest

SPEC = importlib.util.spec_from_file_location("ps4_vm", Path(__file__).with_name("run.py"))
VM = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VM)


class CpioOverlay(unittest.TestCase):
    def test_newc_headers_names_modes_and_proof_content(self):
        data = gzip.decompress(VM.synthetic_overlay(b"synthetic proof\n"))
        entries = {}
        offset = 0
        while offset < len(data):
            self.assertEqual(data[offset:offset + 6], b"070701")
            fields = [int(data[offset + 6 + index * 8:offset + 14 + index * 8], 16)
                      for index in range(13)]
            inode, mode, uid, gid, links, mtime, length, _, _, _, _, name_size, _ = fields
            self.assertEqual((uid, gid, mtime), (0, 0, 0))
            name = data[offset + 110:offset + 110 + name_size - 1].decode()
            offset = (offset + 110 + name_size + 3) // 4 * 4
            content = data[offset:offset + length]
            offset = (offset + length + 3) // 4 * 4
            entries[name] = (mode, content)
        self.assertEqual(entries["lib/firmware/amdgpu"][0], stat.S_IFDIR | 0o755)
        self.assertEqual(entries["lib/firmware/amdgpu/ps4-vm-proof"],
                         (stat.S_IFREG | 0o755, b"synthetic proof\n"))
        self.assertIn("TRAILER!!!", entries)
        self.assertNotIn("key/eap_hdd_key.bin", entries)

    def test_fixture_is_deterministic(self):
        self.assertEqual(VM.synthetic_overlay(b"same"), VM.synthetic_overlay(b"same"))


if __name__ == "__main__":
    unittest.main()
