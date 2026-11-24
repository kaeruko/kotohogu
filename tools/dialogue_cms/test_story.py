"""Publication rejects broken clues, cast, images and Sudoku boards."""

import copy
import unittest

from areas import load_areas
from characters import load_catalog
from story import load_story, story_image_bytes, story_image_mime, validate_story, _validate_webp


class SudokuStoryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.residents = {row["id"] for row in load_catalog()["characters"]
                         if not row.get("archived", False)}
        cls.areas = {row["id"]: row["unlockAt"] for row in load_areas()["areas"]
                     if row["id"] != "hospital"}
        cls.story = load_story(cls.residents)

    def test_sudoku_requires_a_unique_solution(self):
        doc = copy.deepcopy(self.story)
        first = doc["episodes"][0]
        first["puzzle"] = "0" * len(first["puzzle"])
        with self.assertRaisesRegex(ValueError, "must have one solution"):
            validate_story(doc, self.residents, self.areas)

    def test_invalid_chapter_boundaries_are_rejected(self):
        for reason, modify in (
            ("missing chapters", lambda doc: doc.pop("chapters")),
            ("unknown chapter start", lambda doc:
             doc["chapters"][1].update(startEpisodeId="missing")),
            ("out-of-order chapters", lambda doc:
             doc["chapters"][1].update(startEpisodeId="episode_07")),
            ("duplicate chapter ID", lambda doc:
             doc["chapters"][1].update(id="shibapome")),
        ):
            with self.subTest(reason=reason):
                doc = copy.deepcopy(self.story)
                modify(doc)
                with self.assertRaisesRegex(ValueError, "chapter|schema"):
                    validate_story(doc, self.residents, self.areas)

    def test_unregistered_speaker_and_nonlocal_png_are_rejected(self):
        doc = copy.deepcopy(self.story)
        doc["episodes"][0]["dialogue"][0]["speaker"] = "missing"
        with self.assertRaisesRegex(ValueError, "Invalid Sudoku story speaker"):
            validate_story(doc, self.residents, self.areas)
        with self.assertRaisesRegex(ValueError, "Invalid Sudoku story image name"):
            story_image_bytes("../cover.png")

    def test_webp_images_and_invalid_header(self):
        name = self.story["coverImage"]
        self.assertEqual(story_image_mime(name), "image/webp")
        raw = story_image_bytes(name)
        self.assertEqual(raw[8:12], b"WEBP")
        with self.assertRaisesRegex(ValueError, "Invalid Sudoku story WebP"):
            _validate_webp(raw[:-1], name)
        with self.assertRaisesRegex(ValueError, "Invalid Sudoku story WebP"):
            _validate_webp(b"not an image", name)
