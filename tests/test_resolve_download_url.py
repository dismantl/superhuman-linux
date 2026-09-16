import base64
import contextlib
import importlib.util
import io
from pathlib import Path
import unittest
from unittest.mock import patch


SPEC = importlib.util.spec_from_file_location(
    "resolve_download_url", Path(__file__).resolve().parents[1] / "scripts/resolve-download-url.py"
)
resolver = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(resolver)


class InstallerChecksumTests(unittest.TestCase):
    def setUp(self):
        self.filename = "Superhuman Setup 1.2.3-latest.exe"
        self.checksum = base64.b64encode(bytes(range(64))).decode("ascii")
        self.metadata = {
            "version": "1.2.3",
            "files": [{"url": self.filename, "sha512": self.checksum}],
        }

    def resolve(self, metadata):
        with patch.object(resolver, "fetch_latest_yml", return_value=metadata):
            with contextlib.redirect_stderr(io.StringIO()):
                return resolver.resolve_from_update_channel("amd64")

    def test_checksum_is_bound_to_exact_installer(self):
        result = self.resolve(self.metadata)
        self.assertEqual(result["version"], "1.2.3")
        self.assertEqual(result["sha512"], bytes(range(64)).hex())
        self.assertTrue(result["url"].endswith("Superhuman%20Setup%201.2.3-latest.exe"))

    def test_missing_mismatched_or_ambiguous_checksum_fails(self):
        for files in (
            [],
            [{"url": "different.exe", "sha512": self.checksum}],
            [{"url": self.filename, "sha512": "invalid!"}],
            [{"url": self.filename, "sha512": base64.b64encode(b"short").decode()}],
            [{"url": self.filename, "sha512": self.checksum}] * 2,
        ):
            with self.subTest(files=files):
                self.assertIsNone(self.resolve({"version": "1.2.3", "files": files}))

    def test_legacy_top_level_checksum_cannot_replace_files_entry(self):
        metadata = {"version": "1.2.3", "path": self.filename, "sha512": self.checksum}
        self.assertIsNone(self.resolve(metadata))


if __name__ == "__main__":
    unittest.main()
