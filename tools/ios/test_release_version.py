import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import release_version


class IOSReleaseVersionTest(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.path = Path(self.folder.name) / "pubspec.yaml"
        self.path.write_text("name: future_lift\nversion: 1.0.3+6\n", encoding="utf-8")

    def test_plan_and_persist(self):
        self.assertEqual(release_version.plan(self.path), {
            "current_ios_version": "1.0.3",
            "source_version": "1.0.3+6",
            "next_ios_version": "1.0.4",
        })
        release_version.persist(self.path, "1.0.3+6", "1.0.4")
        self.assertEqual(self.path.read_text(encoding="utf-8"),
                         "name: future_lift\nversion: 1.0.4+6\n")

    def test_patch_increment_with_large_number(self):
        self.path.write_text("version: 2.12.99+123\n", encoding="utf-8")
        self.assertEqual(release_version.plan(self.path)["next_ios_version"], "2.12.100")

    def test_rejects_stale_version_without_modifying_file(self):
        original = self.path.read_bytes()
        with self.assertRaisesRegex(ValueError, "Version changed"):
            release_version.persist(self.path, "1.0.2+6", "1.0.4")
        self.assertEqual(self.path.read_bytes(), original)

    def test_rejects_wrong_next_version_without_modifying_file(self):
        original = self.path.read_bytes()
        with self.assertRaisesRegex(ValueError, "Next iOS version"):
            release_version.persist(self.path, "1.0.3+6", "1.0.5")
        self.assertEqual(self.path.read_bytes(), original)

    def test_invalid_or_duplicate_version_fails_fast(self):
        for content in ("version: 1.0.3\n",
                        "version: 01.0.3+6\n",
                        "version: 1.0.3+0\n",
                        "version: 1.0.3+6\nversion: 1.0.4+6\n"):
            with self.subTest(content=content):
                self.path.write_text(content, encoding="utf-8")
                with self.assertRaisesRegex(ValueError, "exactly one version"):
                    release_version.plan(self.path)


if __name__ == "__main__":
    unittest.main()
