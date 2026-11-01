"""Check OCI layer semantics and path/mode handling without real image bytes."""

import importlib.util
import io
import json
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest


spec = importlib.util.spec_from_file_location("unpack_image", sys.argv.pop(1))
extractor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(extractor)


def layer(entries):
    output = io.BytesIO()
    with tarfile.open(fileobj=output, mode="w") as archive:
        for name, data, mode, target in entries:
            info = tarfile.TarInfo(name)
            info.mode = mode
            if target is not None:
                info.type = tarfile.SYMTYPE
                info.linkname = target
                archive.addfile(info)
            else:
                info.size = len(data)
                archive.addfile(info, io.BytesIO(data))
    return output.getvalue()


def image(path, layers):
    with tarfile.open(path, mode="w") as archive:
        for name, data in [("manifest.json", json.dumps([{"Layers": [f"{i}.tar" for i in range(len(layers))]}]).encode()), *[(f"{i}.tar", data) for i, data in enumerate(layers)]]:
            info = tarfile.TarInfo(name)
            info.size = len(data)
            archive.addfile(info, io.BytesIO(data))


class Unpack(unittest.TestCase):
    def test_layers_whiteouts_links_modes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive, output = root / "image.tar", root / "output"
            image(archive, [
                layer([("usr/bin/tool", b"executable", 0o4755, None), ("data/old", b"old", 0o644, None), ("remove", b"gone", 0o644, None)]),
                layer([("data/new", b"new", 0o644, None), ("data/.wh..wh..opq", b"", 0o644, None), (".wh.remove", b"", 0o644, None), ("bin", b"", 0o777, "/usr/bin")]),
            ])
            extractor.unpack(archive, output)
            self.assertEqual((output / "bin/tool").read_bytes(), b"executable")
            self.assertEqual((output / "usr/bin/tool").stat().st_mode & 0o7777, 0o755)
            self.assertEqual((output / "data/new").read_bytes(), b"new")
            self.assertFalse((output / "data/old").exists())
            self.assertFalse((output / "remove").exists())

    def test_escape_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive = root / "image.tar"
            image(archive, [layer([("../escape", b"bad", 0o644, None)])])
            with self.assertRaises(ValueError):
                extractor.unpack(archive, root / "output")
            self.assertFalse((root / "escape").exists())


if __name__ == "__main__":
    unittest.main()
