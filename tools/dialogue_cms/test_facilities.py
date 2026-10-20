"""Room-wide sprite scale stays consistent across CMS and Flutter."""
import copy
import unittest

import facilities


class FacilityScaleTests(unittest.TestCase):
    def test_shared_size_is_single_source_of_truth(self):
        doc = facilities.load()
        salon, bakery = doc["facilities"]
        self.assertEqual(salon["spriteSize"], 230)
        self.assertEqual(bakery["spriteSize"], 235)
        for room in (salon, bakery):
            self.assertTrue(all("size" not in p for p in room["placements"]))
            size = room["spriteSize"]
            for placement in room["placements"]:
                self.assertGreaterEqual(placement["x"], 0)
                self.assertGreaterEqual(placement["y"], 0)
                self.assertLessEqual(placement["x"] + size, room["width"])
                self.assertLessEqual(placement["y"] + size, room["height"])
        self.assertEqual(
            facilities.generated(doc),
            facilities.DART.read_text(encoding="utf-8"),
            "CMS-generated Dart must not drift from its source JSON",
        )

    def test_old_individual_sizes_are_rejected(self):
        doc = copy.deepcopy(facilities.load())
        doc["facilities"][0]["placements"][0]["size"] = 210
        with self.assertRaisesRegex(ValueError, "配置キャラ"):
            facilities.validate(doc)

    def test_invalid_room_size_and_overflow_fail(self):
        good = facilities.load()
        for invalid in (-1, 79, 401, None, True, "230", float("nan")):
            with self.subTest(invalid=invalid):
                doc = copy.deepcopy(good)
                doc["facilities"][0]["spriteSize"] = invalid
                with self.assertRaisesRegex(ValueError, "共通キャラサイズ"):
                    facilities.validate(doc)
        doc = copy.deepcopy(good)
        doc["facilities"][0]["spriteSize"] = 400
        with self.assertRaisesRegex(ValueError, "背景内"):
            facilities.validate(doc)


if __name__ == "__main__":
    unittest.main()
