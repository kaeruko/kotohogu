"""Publication rejects broken clues, cast, images and Sudoku boards."""

import copy
import unittest

from areas import load_areas
from characters import load_catalog
from story import load_story, story_image_bytes, validate_story


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

    def test_unregistered_speaker_and_nonlocal_png_are_rejected(self):
        doc = copy.deepcopy(self.story)
        doc["episodes"][0]["dialogue"][0]["speaker"] = "missing"
        with self.assertRaisesRegex(ValueError, "Invalid Sudoku story speaker"):
            validate_story(doc, self.residents, self.areas)
        with self.assertRaisesRegex(ValueError, "Invalid Sudoku story PNG name"):
            story_image_bytes("../cover.png")
