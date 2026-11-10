"""Unsigned actual-source/full unchanged SDK ownership regression harness."""

import hashlib
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SOURCE = Path(os.environ.get("OWNERSHIP_SOURCE_ROOT", ROOT)).resolve()


@unittest.skipUnless(sys.platform == "darwin", "requires macOS pure text frameworks")
class OwnershipTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(
            prefix="native-encoding-ownership-", dir=os.environ.get("OWNERSHIP_TMPDIR")
        )
        cls.binary = Path(cls.temp.name) / "ownership"
        api = SOURCE / "4D Plugin API"
        data = (api / "4DPluginAPI.c").read_bytes()
        blob = hashlib.sha1(f"blob {len(data)}\0".encode() + data).hexdigest()
        if blob != "62f745e91d81ef2c3c901c656ea8e175d3b173e8":
            cls.temp.cleanup()
            raise AssertionError("Re-audit the SDK before changing the pinned source blob")
        result = subprocess.run([
            "clang++", "-std=c++14", "-x", "objective-c++",
            "-include", "Carbon/Carbon.h",
            "-I", str(SOURCE), "-I", str(SOURCE / "support"),
            "-I", str(api), "-I", str(api / "Classes"),
            "-fsanitize=address,undefined", "-fno-sanitize=alignment",
            "-fno-omit-frame-pointer", "-g",
            "-Wno-deprecated-declarations", "-Wno-return-type-c-linkage",
            "-Wno-ignored-attributes", "-Wno-writable-strings",
            str(api / "4DPluginAPI.c"),
            *map(str, sorted((api / "Classes").glob("*.cpp"))),
            str(SOURCE / "support/4DPlugin-JSON.cpp"),
            str(ROOT / ".github/tests/ownership_host.mm"),
            "-framework", "Cocoa", "-framework", "Carbon",
            "-o", str(cls.binary),
        ], capture_output=True, text=True)
        if result.returncode:
            cls.temp.cleanup()
            raise AssertionError(result.stdout + result.stderr)

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def test_ownership_matrix(self):
        cases = (
            "set-narrow", "set-wide", "set-utf16", "set-wchar", "picture",
            "get-text", "get-bool", "get-number", "get-collection-mismatch",
            "get-text-collection", "get-bool-object", "get-number-collection",
            "get-text-picture", "get-bool-picture", "get-number-picture",
            "get-collection-object",
            "get-bool-match", "get-number-match", "handoffs", "missing",
            "get-text-failure", "get-bool-failure", "get-number-failure",
            "get-collection-failure", "stringify", "stringify-failure",
            "stringify-handle-failure", "stringify-mismatch",
            "scalar", "arrays", "dispatcher",
        )
        for case in cases:
            for text in ("ASCII", "\u65e5", "\U0001f600", ""):
                for empty in ("allocated", "null"):
                    with self.subTest(case=case, text=text, empty=empty):
                        result = subprocess.run(
                            [str(self.binary), case, text, empty],
                            env={**os.environ, "ASAN_OPTIONS": "detect_leaks=0",
                                 "UBSAN_OPTIONS": "halt_on_error=1"},
                            capture_output=True, text=True,
                        )
                        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                        self.assertIn("strings=0 pictures=0 nodes=0 handles=0", result.stdout)


if __name__ == "__main__":
    unittest.main()
