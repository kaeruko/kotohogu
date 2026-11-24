"""CMS story editor, save compatibility, and HTTP route regression tests."""
import copy
import json
import tempfile
import threading
import unittest
from http.server import ThreadingHTTPServer
from pathlib import Path
from unittest.mock import patch
from urllib.error import HTTPError
from urllib.request import Request, urlopen

import story
from characters import load_catalog
from server import Handler


class StoryCmsTests(unittest.TestCase):
    def setUp(self):
        source = story.DATA.read_bytes()
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.path = Path(temporary.name) / "story.json"
        self.path.write_bytes(source)
        override = patch.object(story, "DATA", self.path)
        override.start()
        self.addCleanup(override.stop)
        self.residents = {
            row["id"] for row in load_catalog()["characters"]
            if not row.get("archived", False)
        }

    def loaded(self):
        return story.load_story(self.residents)

    def test_new_chapter_duels_require_a_stage_and_do_not_edit_the_old_catalog(self):
        original = story.load_v3_story(self.residents)
        draft = copy.deepcopy(original)
        episode = copy.deepcopy(draft["episodes"][-1])
        for field in ("puzzle", "solution"):
            del episode[field]
        episode.update(id="future_duel", unlockAt=episode["unlockAt"] + 30,
                       duel={"player": "001_shiba", "opponent": "038_lion_lady"})
        draft["episodes"].append(episode)
        chapter = {"id": "future", "title": "追加章", "startEpisodeId": episode["id"]}
        draft["chapters"].append(chapter)
        with self.assertRaisesRegex(ValueError, "requires a chapter stage"):
            story.save_story(draft)
        chapter["duelStage"] = "sacrifice"
        story.save_story(draft)
        self.assertEqual(self.loaded(), draft)
        self.assertEqual(draft["episodes"][:-1], original["episodes"])
        self.assertEqual(story.load_v3_story(self.residents), original)
        for stage in ("typo", None, []):
            chapter["duelStage"] = stage
            with self.assertRaisesRegex(ValueError, "Unknown Sudoku duel stage"):
                story.save_story(draft)
        chapter["duelStage"] = "firstFlag"
        for opponent in ("not_a_resident", episode["duel"]["player"]):
            episode["duel"]["opponent"] = opponent
            with self.assertRaisesRegex(ValueError, "Invalid Sudoku duel cast"):
                story.save_story(draft)

    def test_editing_text_and_speakers_is_saved_without_changing_progress_contract(self):
        original = self.loaded()
        edited = copy.deepcopy(original)
        edited["title"] = "CMSで直したナゾ"
        edited["episodes"][0]["resultDialogue"][0]["text"] = "とけたぽむ！"
        edited["episodes"][0]["dialogue"][0]["text"] = "ふしぎな紙を発見ぽむ"
        story.save_story(edited)
        self.assertEqual(self.loaded(), edited)
        self.assertEqual(
            [row["id"] for row in edited["episodes"]],
            [row["id"] for row in original["episodes"]],
        )

    def test_revised_structure_can_be_saved_without_preserving_old_indices(self):
        original = self.loaded()
        shortened = copy.deepcopy(original)
        shortened["episodes"] = shortened["episodes"][:2]
        shortened["chapters"] = shortened["chapters"][:1]
        story.save_story(shortened)
        self.assertEqual(len(self.loaded()["episodes"]), 2)

        changed = copy.deepcopy(shortened)
        changed["episodes"][0]["puzzle"] = original["episodes"][1]["puzzle"]
        changed["episodes"][0]["solution"] = original["episodes"][1]["solution"]
        changed["episodes"][0]["resultDialogue"].append(
            copy.deepcopy(changed["episodes"][0]["resultDialogue"][0])
        )
        changed["episodes"][1]["unlockAt"] = 100
        story.save_story(changed)
        self.assertEqual(self.loaded(), changed)

    def test_chapter_titles_edit_without_rewriting_episodes(self):
        original = self.loaded()
        changed = copy.deepcopy(original)
        changed["chapters"][1]["title"] = "モサエドの挑戦"
        story.save_story(changed)
        self.assertEqual(self.loaded()["chapters"][1]["title"], "モサエドの挑戦")
        self.assertEqual(self.loaded()["episodes"], original["episodes"])

    def test_invalid_structure_fails_without_overwriting_previous_story(self):
        original = self.loaded()
        raw = self.path.read_bytes()
        invalid = copy.deepcopy(original)
        invalid["episodes"][0]["puzzle"] = "0" * 16
        with self.assertRaisesRegex(ValueError, "one solution"):
            story.save_story(invalid)
        self.assertEqual(self.path.read_bytes(), raw)

    def test_unknown_speaker_and_missing_picture_fail_without_overwrite(self):
        original = self.loaded()
        raw = self.path.read_bytes()
        bad_speaker = copy.deepcopy(original)
        bad_speaker["episodes"][0]["resultDialogue"][0]["speaker"] = "missing_resident"
        with self.assertRaisesRegex(ValueError, "speaker"):
            story.save_story(bad_speaker)
        bad_picture = copy.deepcopy(original)
        bad_picture["episodes"][0]["image"] = "not_uploaded.png"
        with self.assertRaises(FileNotFoundError):
            story.save_story(bad_picture)
        self.assertEqual(self.path.read_bytes(), raw)

    def test_story_editor_pages_api_and_same_origin_put(self):
        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(thread.join)
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        base = f"http://127.0.0.1:{server.server_port}"

        with urlopen(base + "/story", timeout=5) as response:
            page = response.read().decode("utf-8")
        self.assertIn("お話一覧", page)
        with urlopen(base + "/story.js", timeout=5) as response:
            script = response.read().decode("utf-8")
        self.assertIn('"/api/story"', script)
        with urlopen(base + "/", timeout=5) as response:
            index = response.read().decode("utf-8")
        self.assertIn('href="/story"', index)

        with urlopen(base + "/api/story", timeout=5) as response:
            doc = json.load(response)
        self.assertEqual(doc, self.loaded())
        with urlopen(base + "/api/runtime/story-v3", timeout=5) as response:
            self.assertEqual(json.load(response), doc)
        with urlopen(base + "/api/runtime/story-v4", timeout=5) as response:
            self.assertEqual(json.load(response), doc)
        with urlopen(base + "/api/runtime/story-v2", timeout=5) as response:
            v2 = json.load(response)
        self.assertTrue(all(name.endswith(".png") for name in story.story_images(v2)))
        for name, mime in ((doc["coverImage"], "image/webp"), (v2["coverImage"], "image/png")):
            with urlopen(base + "/api/runtime/story-images/" + name, timeout=5) as response:
                self.assertEqual(response.headers.get_content_type(), mime)
                self.assertEqual(response.read(), story.story_image_bytes(name))
        with urlopen(base + "/api/runtime/story", timeout=5) as response:
            frozen = json.load(response)
        self.assertEqual(len(frozen["episodes"]), 11)
        self.assertEqual(len(doc["episodes"]), 11)
        before = self.path.read_bytes()
        edited = copy.deepcopy(doc)
        edited["episodes"][0]["resultDialogue"][0]["text"] = "ぽむぽむ、できたぽむ！"
        payload = json.dumps(edited, ensure_ascii=False).encode("utf-8")
        request = Request(
            base + "/api/story",
            data=payload,
            method="PUT",
            headers={"Content-Type": "application/json",
                     "Origin": "http://example.invalid"},
        )
        with self.assertRaises(HTTPError) as denied:
            urlopen(request, timeout=5)
        self.assertEqual(denied.exception.code, 403)
        self.assertEqual(self.path.read_bytes(), before)

        request = Request(
            base + "/api/story",
            data=payload,
            method="PUT",
            headers={"Content-Type": "application/json", "Origin": base},
        )
        with urlopen(request, timeout=5) as response:
            result = json.load(response)
        self.assertEqual(result, {"ok": True, "episodes": len(edited["episodes"])})
        self.assertEqual(self.loaded(), edited)
        with urlopen(base + "/api/runtime/story-v3", timeout=5) as response:
            self.assertEqual(json.load(response), doc)
        with urlopen(base + "/api/runtime/story-v4", timeout=5) as response:
            self.assertEqual(json.load(response), edited)

        illegal = copy.deepcopy(edited)
        illegal["episodes"][0]["resultDialogue"][0]["speaker"] = "missing_resident"
        request = Request(
            base + "/api/story",
            data=json.dumps(illegal, ensure_ascii=False).encode("utf-8"),
            method="PUT",
            headers={"Content-Type": "application/json", "Origin": base},
        )
        committed = self.path.read_bytes()
        with self.assertRaises(HTTPError) as denied:
            urlopen(request, timeout=5)
        self.assertEqual(denied.exception.code, 400)
        self.assertEqual(self.path.read_bytes(), committed)


if __name__ == "__main__":
    unittest.main()
