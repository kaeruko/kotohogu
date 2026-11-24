"""Offline checks for reproducible and fail-fast AWS content publishing."""
from __future__ import annotations

import json
import copy
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import publish_content as publisher


class PublishContentTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.png = self.base / "frame.png"
        self.png.write_bytes(
            publisher.PNG_SIGNATURE + b"\x00\x00\x00\x0dIHDR"
            + b"\x00" * 13
        )
        self.catalog = {
            "version": 1,
            "characters": [{"id": "038_owl", "artFolder": "038_owl"}],
            "dialogues": [{"id": "038_owl_001", "text": "こんにちは"}],
        }

    def test_snapshot_is_deterministic_and_contains_only_runtime_assets(self):
        actual_catalog = publisher.runtime_catalog()
        people = {row["id"] for row in actual_catalog["characters"]}
        story = publisher.load_story(people)
        legacy_story = publisher.load_legacy_story(people)
        v2_story = publisher.load_v2_story(people)
        v3_story = publisher.load_v3_story(people)
        with (patch.object(publisher, "runtime_catalog", return_value=self.catalog),
              patch.object(publisher, "load_story", return_value=story),
              patch.object(publisher, "load_legacy_story", return_value=legacy_story),
              patch.object(publisher, "load_v2_story", return_value=v2_story),
              patch.object(publisher, "load_v3_story", return_value=v3_story),
              patch.object(publisher, "runtime_sprite_path",
                           return_value=self.png)):
            first, records, current = publisher.prepare(self.base / "one")
            second, second_records, current2 = publisher.prepare(self.base / "two")
        self.assertEqual(first, second)
        self.assertEqual(records, second_records)
        self.assertEqual(current, current2)
        all_images = (set(publisher.story_images(story)) | set(publisher.story_images(legacy_story))
                      | set(publisher.story_images(v2_story)) | set(publisher.story_images(v3_story)))
        self.assertEqual(len(records), 25 + len(all_images))
        self.assertIn("api/runtime/oyasumi", [row["path"] for row in records])
        self.assertIn("api/runtime/story", [row["path"] for row in records])
        self.assertIn("api/runtime/story-v2", [row["path"] for row in records])
        self.assertEqual(json.loads((self.base / "one" / "api/runtime/story").read_text("utf-8"))["episodes"], legacy_story["episodes"])
        self.assertEqual(json.loads((self.base / "one" / "api/runtime/story-v2").read_text("utf-8")), v2_story)
        self.assertEqual(json.loads((self.base / "one" / "api/runtime/story-v3").read_text("utf-8")), v3_story)
        self.assertEqual(json.loads((self.base / "one" / "api/runtime/story-v4").read_text("utf-8")), story)
        self.assertTrue(all(name.endswith(".png") for name in publisher.story_images(v2_story)))
        self.assertTrue(all(name.endswith(".webp") for name in publisher.story_images(story)))
        self.assertEqual(len(first), 64)
        self.assertEqual(
            (self.base / "one" / "api/runtime/catalog").read_bytes(),
            publisher.encode_json(self.catalog),
        )
        for row in records:
            self.assertEqual(
                publisher.digest((self.base / "one" / row["path"]).read_bytes()),
                row["sha256"],
            )
            self.assertNotIn("preview", row["path"])
            self.assertNotIn("sheet", row["path"])
        manifest = json.loads((self.base / "one" / "manifest.json").read_text("utf-8"))
        self.assertEqual(manifest["releaseId"], first)
        self.assertEqual(manifest["objects"], records)
        self.assertEqual(current["basePath"], f"/releases/{first}/")
        self.assertEqual(current["manifestSha256"],
                         publisher.digest((self.base / "one" / "manifest.json").read_bytes()))

    def test_missing_png_fails_before_publishing_pointer(self):
        with (patch.object(publisher, "runtime_catalog", return_value=self.catalog),
              patch.object(publisher, "load_story", return_value={"coverImage": "unused.png", "episodes": []}),
              patch.object(publisher, "load_legacy_story", return_value={"coverImage": "unused.png", "episodes": []}),
              patch.object(publisher, "load_v2_story", return_value={"coverImage": "unused.png", "episodes": []}),
              patch.object(publisher, "load_v3_story", return_value={"coverImage": "unused.png", "episodes": []}),
              patch.object(publisher, "story_image_bytes", return_value=b"art"),
              patch.object(publisher, "runtime_sprite_path",
                           side_effect=FileNotFoundError("missing idle sprite"))):
            with self.assertRaisesRegex(FileNotFoundError, "missing idle sprite"):
                publisher.prepare(self.base / "broken")
        self.assertFalse((self.base / "broken" / "manifest.json").exists())

    def test_non_png_rejected_without_substitution(self):
        self.png.write_bytes(b"not-png")
        with (patch.object(publisher, "runtime_catalog", return_value=self.catalog),
              patch.object(publisher, "load_story", return_value={"coverImage": "unused.png", "episodes": []}),
              patch.object(publisher, "load_legacy_story", return_value={"coverImage": "unused.png", "episodes": []}),
              patch.object(publisher, "load_v2_story", return_value={"coverImage": "unused.png", "episodes": []}),
              patch.object(publisher, "load_v3_story", return_value={"coverImage": "unused.png", "episodes": []}),
              patch.object(publisher, "story_image_bytes", return_value=b"art"),
              patch.object(publisher, "runtime_sprite_path", return_value=self.png)):
            with self.assertRaisesRegex(ValueError, "Invalid PNG sprite"):
                publisher.prepare(self.base / "invalid")

    def test_content_publisher_accepts_a_shorter_rewritten_story(self):
        actual_catalog = publisher.runtime_catalog()
        story_doc = publisher.load_story(
            {row["id"] for row in actual_catalog["characters"]}
        )
        shorter = copy.deepcopy(story_doc)
        shorter["episodes"] = shorter["episodes"][:2]
        with (patch.object(publisher, "runtime_catalog", return_value=self.catalog),
              patch.object(publisher, "load_story", return_value=shorter),
              patch.object(publisher, "load_legacy_story", return_value=story_doc),
              patch.object(publisher, "load_v2_story", return_value=story_doc),
              patch.object(publisher, "load_v3_story", return_value=story_doc),
              patch.object(publisher, "runtime_sprite_path",
                           return_value=self.png)):
            _, records, _ = publisher.prepare(self.base / "rewritten")
        saved = json.loads((self.base / "rewritten" /
                            "api/runtime/story-v4").read_text("utf-8"))
        self.assertEqual(len(saved["episodes"]), 2)
        frozen = json.loads((self.base / "rewritten" /
                             "api/runtime/story").read_text("utf-8"))
        self.assertEqual(len(frozen["episodes"]), len(story_doc["episodes"]))
        self.assertTrue(any(row["path"] == "api/runtime/story-v3" for row in records))

    def test_explicit_shiba_mirror_exception_only(self):
        shiba = publisher.frames_for({"id": "001_shiba"})
        owl = publisher.frames_for({"id": "038_owl"})
        self.assertNotIn("walk_left_01.png", shiba)
        self.assertIn("walk_left_01.png", owl)
        self.assertIn("walk_right_01.png", shiba)
        self.assertEqual(len(shiba), 15)
        self.assertEqual(len(owl), 19)

    def test_incomplete_s3_release_rejected(self):
        args = SimpleNamespace(region="ap-northeast-1", profile=None)
        with patch.object(publisher, "aws_json", return_value={
            "Contents": [{"Key": "releases/abc/api/runtime/catalog", "Size": 1}],
            "IsTruncated": False,
        }):
            with self.assertRaisesRegex(RuntimeError, "missing="):
                publisher.verify_release(
                    args, "bucket", "releases/abc/",
                    [{"path": "api/runtime/catalog", "size": 1}],
                    self.png,
                )

    def test_aws_failure_preserves_cause_and_stderr(self):
        error = subprocess.CalledProcessError(
            42, ["aws"], output="output details", stderr="AccessDenied",
        )
        args = SimpleNamespace(region="ap-northeast-1", profile=None)
        with patch.object(publisher.subprocess, "run", side_effect=error):
            with self.assertRaises(RuntimeError) as result:
                publisher.aws(args, "s3api", "head-bucket", "--bucket", "example")
        self.assertIs(result.exception.__cause__, error)
        self.assertIn("AccessDenied", str(result.exception))
        self.assertIn("exit=42", str(result.exception))


if __name__ == "__main__":
    unittest.main()
