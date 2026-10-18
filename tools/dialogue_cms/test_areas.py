"""Tests for the CMS town-area and appearance editor."""
import copy
import shutil
import subprocess
import unittest
from pathlib import Path

from areas import AREA_IDS, DART, END, ROOT, generate_town_areas, load_areas, validate_areas

class TownAreaCmsTests(unittest.TestCase):
    def test_bundled_areas_match_generated_flutter_definition(self):
        areas = validate_areas(load_areas())
        self.assertEqual(tuple(row["id"] for row in areas["areas"]), AREA_IDS)
        original = DART.read_text(encoding="utf-8")
        self.assertEqual(generate_town_areas(original, areas), original)

    def test_area_name_description_and_threshold_generate_flutter(self):
        modified = copy.deepcopy(load_areas())
        modified["areas"][1]["label"] = "新しい森の公園"
        modified["areas"][1]["description"] = "季節のお花と おさんぽ。"
        modified["areas"][1]["unlockAt"] = 120
        original = DART.read_text(encoding="utf-8")
        result = generate_town_areas(original, modified)
        self.assertIn('park("park", "新しい森の公園", "季節のお花と おさんぽ。", 120,', result)
        # Keep existing business rules and resident-placement functions untouched.
        self.assertIn("residentCurrentArea(", result)
        self.assertEqual(result.split(END, 1)[1], original.split(END, 1)[1])

    def test_invalid_area_settings_fail_before_writing(self):
        baseline = load_areas()
        variants = []
        for field,value in (
            ("id","renamed"),
            ("unlockAt",-1),
            ("unlockAt",True),
            ("unlockAt",0),
            ("description",""),
            ("label"," "),
            ("sourceWidth",False),
            ("backgroundAsset","../../private.json"),
            ("backgroundAsset","assets/kotohogu/not-real.png"),
        ):
            bad = copy.deepcopy(baseline)
            bad["areas"][1][field] = value
            variants.append((field,value,bad))
        missing = copy.deepcopy(baseline)
        missing["areas"].pop()
        variants.append(("areas","missing",missing))
        extra = copy.deepcopy(baseline)
        extra["areas"][0]["unexpected"] = 1
        variants.append(("fields","extra",extra))
        for field,value,bad in variants:
            with self.subTest(field=field,value=value), self.assertRaises(ValueError):
                validate_areas(bad, previous=baseline)

    def test_dart_escaping_and_stable_source_markers(self):
        edited = copy.deepcopy(load_areas())
        edited["areas"][0]["label"] = '風の"$"ひろば'
        generated = generate_town_areas(DART.read_text(encoding="utf-8"), edited)
        self.assertIn(r'風の\"\$\"ひろば', generated)
        with self.assertRaisesRegex(ValueError, "markers"):
            generate_town_areas("enum TownArea { plaza; }", edited)

    @unittest.skipUnless(shutil.which("node"), "Node.js is optional for local Python-only CMS")
    def test_outing_preview_matches_runtime_placement_contract(self):
        process = subprocess.run(
            ["node", "--test", str(ROOT / "tools/dialogue_cms/test_town_visits.mjs")],
            text=True, capture_output=True, timeout=15, check=False)
        self.assertEqual(process.returncode, 0, process.stdout + process.stderr)

    @unittest.skipUnless(shutil.which("node"), "Node.js is optional for local Python-only CMS")
    def test_inline_editor_javascript_is_syntactically_valid(self):
        html = (ROOT / "tools/dialogue_cms/index.html").read_text(encoding="utf-8")
        self.assertEqual(html.count("<script>"), 1)
        self.assertEqual(html.count("</script>"), 1)
        code = html.split("<script>",1)[1].split("</script>",1)[0]
        process = subprocess.run(["node", "--check", "-"], input=code, text=True,
                                 capture_output=True, timeout=15, check=False)
        self.assertEqual(process.returncode, 0, process.stderr)

if __name__ == "__main__":
    unittest.main()
