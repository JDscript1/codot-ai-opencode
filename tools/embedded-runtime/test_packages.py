import hashlib
import importlib.util
import json
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest import mock

spec = importlib.util.spec_from_file_location("runtime_packages", Path(__file__).with_name("packages.py"))
assert spec is not None and spec.loader is not None
packages = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packages)


class PackageLockTests(unittest.TestCase):
    def test_debian_version_order_matches_dpkg_rules(self):
        cases = [
            ("1.0", "1.0", 0),
            ("1.0~rc1", "1.0", -1),
            ("1:1.0", "2.0", 1),
            ("2.0-1", "2.0-2", -1),
            ("2.0+deb13u1", "2.0", 1),
            ("1.0a", "1.0", 1),
        ]
        for first, second, expected in cases:
            with self.subTest(first=first, second=second):
                self.assertEqual(packages.compare_versions(first, second), expected)

    def test_dependency_resolution_uses_installed_and_transitive_packages(self):
        records = [
            {"Package": "app-lib", "Version": "2.0", "Architecture": "arm64", "Depends": "libx (>= 3), base"},
            {"Package": "libx", "Version": "3.2", "Architecture": "arm64", "Depends": "base"},
            {"Package": "base", "Version": "1.0", "Architecture": "arm64"},
            {"Package": "already", "Version": "5.0", "Architecture": "all"},
        ]
        index = packages.PackageIndex(records, {"base": "1.0", "already": "5.0"})
        selected = packages.resolve(index, ["already", "app-lib"])
        self.assertEqual([record["Package"] for record in selected], ["app-lib", "libx"])

    def test_alternative_and_versioned_dependency_are_understood(self):
        records = [
            {
                "Package": "target",
                "Version": "1.0",
                "Architecture": "arm64",
                "Depends": "missing | virtual-ssl (>= 3.0), base:any",
            },
            {"Package": "libssl", "Version": "3.0.1", "Architecture": "arm64", "Provides": "virtual-ssl"},
        ]
        index = packages.PackageIndex(records, {"base": "1.0"})
        selected = packages.resolve(index, ["target"])
        self.assertEqual([record["Package"] for record in selected], ["libssl", "target"])

    def test_unresolved_dependency_is_rejected(self):
        index = packages.PackageIndex([{"Package": "target", "Version": "1", "Depends": "absent"}], {})
        with self.assertRaisesRegex(RuntimeError, "Unresolved dependency"):
            packages.resolve(index, ["target"])

    def test_offline_repository_has_relative_debs_and_metadata(self):
        record = {
            "Package": "fixture",
            "Version": "1.0",
            "Architecture": "arm64",
            "Multi-Arch": "allowed",
            "Description": "Fixture package",
            "Filename": "pool/fixture.deb",
        }
        content = b"!<arch>\nfixture"
        record.update({"Size": str(len(content)), "SHA256": hashlib.sha256(content).hexdigest()})
        debian = {"repository": "https://deb.example", "asset": "debian-offline.zip"}
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)

            def fake_download(path, spec):
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(content)
                return path

            with mock.patch.object(packages, "download", side_effect=fake_download):
                archive = packages.build_debian_zip(root / "work", root / "out", [record], debian)
            with zipfile.ZipFile(archive) as bundle:
                self.assertEqual(bundle.read("fixture.deb"), content)
                index = bundle.read("Packages").decode()
                self.assertIn("Filename: ./fixture.deb", index)
                self.assertIn(f"SHA256: {record['SHA256']}", index)
                self.assertIn("Multi-Arch: allowed", index)

    def test_lock_only_contains_pinned_official_sources(self):
        lock = json.loads(Path(__file__).with_name("packages.json").read_text())
        self.assertEqual(lock["schema"], 1)
        for name in ("node", "pi"):
            self.assertTrue(lock[name]["url"].startswith("https://"))
            self.assertRegex(lock[name]["sha256"], r"^[0-9a-f]{64}$")
        self.assertEqual(
            lock["ziva"]["runtime"]["sha256"], "f485f3b0f381fe4ec40b10788f0af62bea487c94ec6d830ec811c09f24f32b39"
        )
        self.assertIn("xz-utils", lock["debian"]["packages"])


if __name__ == "__main__":
    unittest.main()
