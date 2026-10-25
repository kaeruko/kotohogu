"""Room-wide sprite scale stays consistent across CMS and Flutter."""
import copy
import unittest

import facilities


class FacilityScaleTests(unittest.TestCase):
    def test_shared_size_is_single_source_of_truth(self):
        doc = facilities.load()
        salon, bakery, center, hospital = doc["facilities"]
        self.assertEqual(salon["spriteSize"], 230)
        self.assertEqual(bakery["spriteSize"], 235)
        self.assertEqual(center["spriteSize"], 150)
        self.assertEqual(center["background"], "assets/kotohogu/community_center_background_001.png")
        self.assertEqual((center["width"], center["height"]), (941, 1672))
        self.assertEqual([p["residentId"] for p in center["placements"]],
                         ["031_kimono_fox", "037_tora", "051_dog_aunt",
                          "001_shiba", "042_senior_dog"])
        self.assertLess(center["placements"][0]["x"] + center["spriteSize"],
                        center["placements"][1]["x"])
        self.assertEqual(hospital["label"], "びょういん")
        self.assertEqual(hospital["background"], "assets/kotohogu/hospital_background_001.png")
        self.assertEqual((hospital["width"], hospital["height"]), (941, 1672))
        self.assertEqual(hospital["owner"], "004_neko")
        self.assertEqual(hospital["spriteSize"], 125)
        self.assertEqual([p["residentId"] for p in hospital["placements"]],
                         ["004_neko", "024_nurse"])
        self.assertLess(hospital["placements"][0]["x"] + hospital["spriteSize"],
                        hospital["placements"][1]["x"])
        for room in (salon, bakery, center, hospital):
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

    def test_clinic_staff_membership_is_not_silently_ignored(self):
        doc = copy.deepcopy(facilities.load())
        doc["facilities"][-1]["placements"].pop()
        with self.assertRaisesRegex(ValueError, "診療所の配置"):
            facilities.validate(doc)
        doc = copy.deepcopy(facilities.load())
        doc["facilities"][-1]["placements"].append(
            {"residentId": "001_shiba", "x": 340, "y": 800})
        with self.assertRaisesRegex(ValueError, "診療所の配置"):
            facilities.validate(doc)

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
        doc["facilities"][0]["placements"][0]["x"] = 700
        with self.assertRaisesRegex(ValueError, "背景内"):
            facilities.validate(doc)


if __name__ == "__main__":
    unittest.main()
