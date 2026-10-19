"""Local CMS schema and atomic save regression checks."""
import copy
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from server import (portrait_path, runtime_catalog, runtime_sprite_path,
                    validate, write_document)
from characters import (archive_code_blockers, validate_archive_dependencies, validate_archive_code_references,
                         load_catalog, validate_catalog, generate_dart, generate_pubspec,
                        DART, PUBSPEC, save_catalog_and_dialogues, validate_dialogue_ids)


def sample():
    source = json.loads((Path(__file__).resolve().parents[2] /
                         "assets/dialogues/dialogues.json").read_text("utf-8"))
    return source


class CmsTests(unittest.TestCase):
    def test_character_ids_match_sprite_folders_including_rabbit(self):
        original = load_catalog()
        self.assertTrue(all(row["id"] == row["artFolder"]
                            for row in original["characters"]))
        rabbit = next(row for row in original["characters"]
                      if row["key"] == "rabbit")
        self.assertEqual(rabbit["id"], "002_usagi")
        self.assertNotIn("archived", rabbit)
        mismatched = copy.deepcopy(original)
        mismatched["characters"][0]["artFolder"] = "002_usagi"
        with self.assertRaisesRegex(ValueError, "must match"):
            validate_catalog(mismatched, previous=original)

    def test_resident_ownership_conditions_validate_strictly(self):
        current = sample()
        self.assertIs(validate(current), current)
        entry = next(row for row in current["dialogues"]
                     if row["id"] == "003_penguin_002")
        self.assertEqual(entry["conditions"], [
            {"type": "residentOwned", "residentId": "035_beaty", "owned": False},
        ])
        for value in ("no", 0, None):
            invalid = copy.deepcopy(current)
            target = next(row for row in invalid["dialogues"]
                          if row["id"] == "003_penguin_002")
            target["conditions"][0]["owned"] = value
            with self.subTest(value=value), self.assertRaisesRegex(
                    ValueError, "Invalid resident ownership"):
                validate(invalid)
        unknown = copy.deepcopy(current)
        next(row for row in unknown["dialogues"]
             if row["id"] == "003_penguin_002")["conditions"][0]["residentId"] = "does_not_exist"
        with self.assertRaisesRegex(ValueError, "Invalid resident ownership"):
            validate(unknown)

    def test_character_portrait_resolves_idle_png_only(self):
        catalog = load_catalog()
        folder = next(row["artFolder"] for row in catalog["characters"]
                      if row["id"] == "037_tora")
        image = portrait_path(folder)
        self.assertEqual(image.name, "idle_front_01.png")
        self.assertTrue(image.read_bytes().startswith(b"\x89PNG\r\n\x1a\n"))
        for invalid in ("", ".", "..", "../characters", "037_tora/../001_shiba",
                        "037_tora?file=other", "/tmp", None):
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                portrait_path(invalid)
        with self.assertRaises(FileNotFoundError):
            portrait_path("999999_missing")


    def test_runtime_catalog_includes_new_residents_and_dialogues(self):
        result = runtime_catalog()
        self.assertEqual(result["version"], 1)
        characters = {row["id"] for row in result["characters"]}
        self.assertIn("037_tora", characters)
        self.assertTrue(any(row["residentId"] == "037_tora"
                            for row in result["dialogues"]))
        self.assertEqual(len(characters), len(result["characters"]))

    def test_runtime_sprite_paths_are_explicit_and_safe(self):
        image = runtime_sprite_path("037_tora", "idle_front_01.png")
        self.assertTrue(image.is_file())
        self.assertTrue(image.read_bytes().startswith(b"\x89PNG\r\n\x1a\n"))
        self.assertEqual(runtime_sprite_path("037_tora", "clap_front_02.png").suffix, ".png")
        for folder, filename in (
            ("../../tmp", "idle_front_01.png"),
            ("037_tora", "../../characters.json"),
            ("037_tora", "preview_clap.gif"),
            ("037_tora", "random.png"),
            ("99999_unregistered", "idle_front_01.png"),
        ):
            with self.subTest(folder=folder, filename=filename):
                with self.assertRaises(ValueError):
                    runtime_sprite_path(folder, filename)

    def test_runtime_catalog_invalid_data_fails_without_fallback(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "dialogues.json"
            path.write_text('{"version":1,"dialogues":[]}', encoding="utf-8")
            with patch("server.DATA", path):
                with self.assertRaisesRegex(ValueError, "nonempty"):
                    runtime_catalog()

    def test_character_registry_and_generated_files(self):
        registry = validate_catalog(load_catalog())
        # New residents are appended over time; preserve the original seven.
        self.assertGreaterEqual(len(registry["characters"]), 7)
        self.assertEqual(generate_dart(DART.read_text("utf-8"), registry["characters"]),
                         DART.read_text("utf-8"))
        self.assertEqual(generate_pubspec(PUBSPEC.read_text("utf-8"), registry["characters"]),
                         PUBSPEC.read_text("utf-8"))

    def test_generated_dart_escapes_dollar_sign_in_names(self):
        entries = copy.deepcopy(load_catalog()["characters"])
        entries[0]["label"] = "価格$100"
        output = generate_dart(DART.read_text("utf-8"), entries)
        self.assertIn(r"価格\$100", output)

    def test_profile_updates_preserve_character_ids_and_generate_dart(self):
        original = load_catalog()
        modified = copy.deepcopy(original)
        modified["characters"][0]["profile"] = "おさんぽが好き。\n今日も一緒に歩こう！"
        self.assertIs(validate_catalog(modified, previous=original), modified)
        generated = generate_dart(DART.read_text("utf-8"), modified["characters"])
        self.assertIn(r"おさんぽが好き。\n今日も一緒に歩こう！", generated)

    def test_profile_requires_explicit_schema_and_valid_string(self):
        original = load_catalog()
        old_version = copy.deepcopy(original)
        old_version["version"] = 3
        with self.assertRaisesRegex(ValueError, "Unsupported character catalog version"):
            validate_catalog(old_version)

        missing = copy.deepcopy(original)
        del missing["characters"][0]["profile"]
        with self.assertRaisesRegex(ValueError, "Invalid character fields"):
            validate_catalog(missing, previous=original)

        for value in (None, 42, ["wrong"], "あ" * 1001):
            modified = copy.deepcopy(original)
            modified["characters"][0]["profile"] = value
            with self.subTest(value_type=type(value).__name__), self.assertRaisesRegex(ValueError, "Invalid profile"):
                validate_catalog(modified, previous=original)

        allowed = copy.deepcopy(original)
        allowed["characters"][0]["profile"] = "あ" * 1000
        validate_catalog(allowed, previous=original)

    def test_home_area_validation_and_generator(self):
        original = load_catalog()
        moved = copy.deepcopy(original)
        moved["characters"][0]["homeAreaId"] = "park"
        validate_catalog(moved, previous=original)
        self.assertIn('"park")', generate_dart(DART.read_text("utf-8"), moved["characters"]))
        salon = copy.deepcopy(original)
        salon_resident = next(row for row in salon["characters"]
                              if row["id"] == "035_beaty")
        self.assertEqual(salon_resident["homeAreaId"], "salon")
        self.assertTrue(salon_resident["inGacha"])
        validate_catalog(salon, previous=original)
        self.assertIn('"salon")',
                      generate_dart(DART.read_text("utf-8"), salon["characters"]))
        invalid_owner = copy.deepcopy(original)
        row = next(row for row in invalid_owner["characters"]
                   if row["id"] == "035_beaty")
        row["homeAreaId"] = "shopping"
        with self.assertRaisesRegex(ValueError, "Salon owner"):
            validate_catalog(invalid_owner, previous=original)
        row["homeAreaId"] = "salon"
        row["inGacha"] = False
        with self.assertRaisesRegex(ValueError, "Salon owner"):
            validate_catalog(invalid_owner, previous=original)
        overcrowded = copy.deepcopy(original)
        for row in overcrowded["characters"][:8]:
            row["homeAreaId"] = "salon"
        with self.assertRaisesRegex(ValueError, "at most 7"):
            validate_catalog(overcrowded, previous=original)
        for invalid_area in ("unknown", "", None, 9):
            bad = copy.deepcopy(original)
            bad["characters"][0]["homeAreaId"] = invalid_area
            with self.assertRaisesRegex(ValueError, "Invalid home area"):
                validate_catalog(bad, previous=original)

    def test_profile_dart_escapes_interpolation_and_quotes(self):
        characters = copy.deepcopy(load_catalog()["characters"])
        characters[0]["profile"] = '価格$100と"お話"'
        generated = generate_dart(DART.read_text("utf-8"), characters)
        self.assertIn(r'価格\$100と\"お話\"', generated)

    def test_existing_character_ids_cannot_change(self):
        original = load_catalog()
        for change in ("remove", "id", "folder"):
            modified = copy.deepcopy(original)
            if change == "remove":
                modified["characters"].pop(0)
            elif change == "id":
                modified["characters"][0]["id"] = "01_new"
            else:
                modified["characters"][0]["artFolder"] = "002_usagi"
            with self.subTest(change=change), self.assertRaises(ValueError):
                validate_catalog(modified, previous=original)

    def test_archived_resident_stays_decodable_and_leaves_gacha(self):
        original = load_catalog()
        retired = copy.deepcopy(original)
        row = next(item for item in retired["characters"] if item["id"] == "037_tora")
        row["archived"] = True
        self.assertIs(validate_catalog(retired, previous=original), retired)
        generated = generate_dart(DART.read_text("utf-8"), retired["characters"])
        self.assertIn('c037_tora("037_tora", "とらお", "037_tora", false, false, "", "plaza", archived: true)',
                      generated)
        self.assertIn("assets/characters/037_tora/", generate_pubspec(
            PUBSPEC.read_text("utf-8"), retired["characters"]))
        bad = copy.deepcopy(retired)
        next(item for item in bad["characters"] if item["id"] == "037_tora")["archived"] = False
        with self.assertRaisesRegex(ValueError, "Archived flag"):
            validate_catalog(bad, previous=original)
        del row["archived"]
        validate_catalog(retired, previous=original)
        restored = generate_dart(DART.read_text("utf-8"), retired["characters"])
        self.assertNotIn("archived: true", restored)

    def test_archive_blockers_match_save_validation_without_mutating_rabbit(self):
        catalog = {"characters": [
            {"id": "002_usagi", "key": "rabbit"},
            {"id": "037_tora", "key": "c037_tora"},
            {"id": "038_lion_lady", "key": "c038_lion_lady"},
        ]}
        original = copy.deepcopy(catalog)
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "lib").mkdir()
            (root / "lib/dependency.dart").write_text(
                'const friend = "037_tora";', encoding="utf-8")
            with patch("characters.ROOT", root):
                blockers = archive_code_blockers(catalog)
                self.assertIn("Core resident", blockers["002_usagi"])
                self.assertIn("lib/dependency.dart", blockers["037_tora"])
                self.assertNotIn("038_lion_lady", blockers)
                for identifier, reason in blockers.items():
                    candidate = copy.deepcopy(catalog)
                    next(row for row in candidate["characters"]
                         if row["id"] == identifier)["archived"] = True
                    with self.assertRaises(ValueError) as error:
                        validate_archive_code_references(candidate, catalog)
                    self.assertEqual(str(error.exception), reason)
        self.assertEqual(catalog, original)

    def test_archive_blocks_core_residents_and_active_dependencies(self):
        original = load_catalog()
        for identifier in ("001_shiba", "002_usagi"):
            retired = copy.deepcopy(original)
            next(row for row in retired["characters"] if row["id"] == identifier)["archived"] = True
            with self.assertRaisesRegex(ValueError, "Core resident"):
                validate_archive_code_references(retired, original)
        retired = copy.deepcopy(original)
        next(row for row in retired["characters"] if row["id"] == "037_tora")["archived"] = True
        original_data = sample()
        altered = copy.deepcopy(original_data)
        target = next(row for row in altered["dialogues"] if row["residentId"] == "001_shiba")
        target["conditions"] = [{"type": "residentOwned", "residentId": "037_tora", "owned": False}]
        with self.assertRaisesRegex(ValueError, "depends on archived"):
            validate_archive_dependencies(retired, altered)
        archived_dialogue = next(row["id"] for row in original_data["dialogues"]
                                 if row["residentId"] == "037_tora")
        target["conditions"] = [{"type": "seenDialogue", "dialogueId": archived_dialogue}]
        with self.assertRaisesRegex(ValueError, "depends on archived"):
            validate_archive_dependencies(retired, altered)
        target["conditions"] = [{"type": "townTogether", "otherResidentId": "037_tora"}]
        with self.assertRaisesRegex(ValueError, "depends on archived"):
            validate_archive_dependencies(retired, altered)

    def test_archive_rejects_handwritten_dart_references(self):
        original = load_catalog()
        retired = copy.deepcopy(original)
        next(row for row in retired["characters"] if row["id"] == "037_tora")["archived"] = True
        with tempfile.TemporaryDirectory() as folder:
            lib = Path(folder) / "lib"
            lib.mkdir()
            (lib / "dependency.dart").write_text('const friend = "037_tora";', encoding="utf-8")
            with patch("characters.ROOT", Path(folder)):
                with self.assertRaisesRegex(ValueError, "used by app code"):
                    validate_archive_code_references(retired, original)

    def test_runtime_catalog_hides_retired_residents(self):
        original = load_catalog()
        retired = copy.deepcopy(original)
        next(row for row in retired["characters"] if row["id"] == "037_tora")["archived"] = True
        with patch("server.load_catalog", return_value=retired):
            live = runtime_catalog()
        self.assertNotIn("037_tora", {row["id"] for row in live["characters"]})
        self.assertTrue(all(row["residentId"] != "037_tora"
                            for row in live["dialogues"]))
        self.assertTrue(all("archived" not in row for row in live["characters"]))
        self.assertIn("001_shiba", {row["id"] for row in live["characters"]})

    def test_new_character_needs_sprite_and_unconditional_dialogue(self):
        original = load_catalog()
        modified = copy.deepcopy(original)
        modified["characters"].append({
            "key": "c999_owl", "id": "999_owl", "label": "ふくろう",
            "artFolder": "999_owl", "nextDialogueNumber": 2,
            "profile": "",
            "inGacha": True, "walkInTown": True, "homeAreaId": "plaza"
        })
        with self.assertRaisesRegex(ValueError, "Sprite folder"):
            validate_catalog(modified, previous=original)
        # A new ID still needs an unconditional line, irrespective of art files.
        with self.assertRaisesRegex(ValueError, "Missing"):
            validate(sample(), residents={
                row["id"] for row in original["characters"]
            } | {"999_owl"})

    def test_three_digit_id_generates_dart_key_and_folder(self):
        original = load_catalog()
        validate_catalog(original)
        # This formerly synthetic character is now a real resident. Do not
        # append its ID again and accidentally test a duplicate.
        self.assertIn("007_hitsuji",
                      {row["id"] for row in original["characters"]})
        dart = generate_dart(DART.read_text("utf-8"), original["characters"])
        self.assertIn('c007_hitsuji("007_hitsuji", "めりぃ", "007_hitsuji"', dart)

        modified = copy.deepcopy(original)
        modified["characters"].append({
            "key": "c999_testowl", "id": "999_testowl", "label": "テストふくろう",
            "artFolder": "999_testowl", "nextDialogueNumber": 2,
            "profile": "",
            "inGacha": True, "walkInTown": True, "homeAreaId": "plaza"
        })
        with self.assertRaisesRegex(ValueError, "Sprite folder"):
            validate_catalog(modified, previous=original)
        for field, value in (("key", "chef"), ("artFolder", "009_wrong")):
            mismatched = copy.deepcopy(modified)
            mismatched["characters"][-1][field] = value
            with self.subTest(field=field), self.assertRaisesRegex(
                    ValueError, "derived from ID" if field == "key" else "must match"):
                validate_catalog(mismatched, previous=original)

    def test_dialogue_serials_preserve_existing_ids_and_retired_numbers(self):
        original = load_catalog()
        modified = copy.deepcopy(original)
        modified["characters"][0]["nextDialogueNumber"] = 4
        dialogues = sample()
        dialogues["dialogues"].append({
            "id": "001_shiba_002", "residentId": "001_shiba",
            "text": "新しい話", "priority": 0, "once": False,
            "logic": "all", "conditions": [],
        })
        dialogues["dialogues"].append({
            "id": "001_shiba_003", "residentId": "001_shiba",
            "text": "次の話", "priority": 0, "once": False,
            "logic": "all", "conditions": [],
        })
        validate_catalog(modified, previous=original)
        validate(dialogues)
        validate_dialogue_ids(modified, dialogues, original, sample())

        not_reserved = copy.deepcopy(modified)
        not_reserved["characters"][0]["nextDialogueNumber"] = 3
        with self.assertRaisesRegex(ValueError, "not reserved"):
            validate_dialogue_ids(not_reserved, dialogues, original, sample())

        previously_reserved = copy.deepcopy(original)
        previously_reserved["characters"][0]["nextDialogueNumber"] = 4
        future = copy.deepcopy(previously_reserved)
        future["characters"][0]["nextDialogueNumber"] = 5
        new_dialogues = sample()
        new_dialogues["dialogues"].append({
            "id": "001_shiba_003", "residentId": "001_shiba",
            "text": "削除済み番号の再利用", "priority": 0, "once": False,
            "logic": "all", "conditions": [],
        })
        with self.assertRaisesRegex(ValueError, "already reserved"):
            validate_dialogue_ids(future, new_dialogues, previously_reserved, sample())

        renamed = copy.deepcopy(dialogues)
        renamed["dialogues"][0]["residentId"] = "002_usagi"
        with self.assertRaisesRegex(ValueError, "resident cannot change"):
            validate_dialogue_ids(modified, renamed, original, sample())

        invalid = copy.deepcopy(dialogues)
        invalid["dialogues"][-1]["id"] = "line_123"
        with self.assertRaisesRegex(ValueError, "character ID and serial"):
            validate_dialogue_ids(modified, invalid, original, sample())

        rollback_counter = copy.deepcopy(original)
        rollback_counter["characters"][0]["nextDialogueNumber"] = 4
        with self.assertRaisesRegex(ValueError, "cannot decrease"):
            validate_catalog(original, previous=rollback_counter)

    def test_bad_catalog_keeps_files_intact(self):
        original = load_catalog()
        modified = copy.deepcopy(original)
        modified["characters"][0]["key"] = "renamed"
        prior = {path: path.read_bytes() for path in (DART, PUBSPEC)}
        with self.assertRaises(ValueError):
            save_catalog_and_dialogues({"characters": modified, "dialogues": sample()}, validate)
        for path, raw in prior.items():
            self.assertEqual(path.read_bytes(), raw)

    def test_character_catalog_has_no_tip_source_or_dialogue_kinds(self):
        registry = validate_catalog(load_catalog())
        self.assertEqual(registry["version"], 5)
        for resident in registry["characters"]:
            self.assertNotIn("tipSource", resident)
        invalid = copy.deepcopy(registry)
        invalid["characters"][0]["tipSource"] = "adult"
        with self.assertRaisesRegex(ValueError, "Invalid character fields"):
            validate_catalog(invalid, previous=registry)
        dialogues = sample()
        self.assertEqual(dialogues["version"], 1)
        for entry in dialogues["dialogues"]:
            self.assertNotIn("kind", entry)
            self.assertIn("conditions", entry)
        validate(dialogues)

    def test_invalid_dialogue_fields_report_exact_missing_and_extra_keys(self):
        extra = sample()
        extra["dialogues"][0]["kind"] = "normal"
        with self.assertRaisesRegex(
                ValueError,
                r"dialogues\[0\]: invalid fields; missing=\[\], unexpected=\['kind'\]"):
            validate(extra)

        missing = sample()
        del missing["dialogues"][0]["logic"]
        with self.assertRaisesRegex(
                ValueError,
                r"dialogues\[0\]: invalid fields; missing=\['logic'\], unexpected=\[\]"):
            validate(missing)

    def test_first_greetings_are_once_only_and_unique(self):
        data = sample()
        introductions = [row for row in data["dialogues"]
                         if row.get("firstGreeting") is True]
        resident_ids = {row["id"] for row in load_catalog()["characters"]}
        self.assertEqual({row["residentId"] for row in introductions}, resident_ids)
        self.assertEqual(len(introductions), len(resident_ids))
        validate(data)
        for row in introductions:
            self.assertTrue(row["once"])
            self.assertEqual(row["conditions"], [])
            self.assertGreater(row["priority"], -1000)

        duplicate = copy.deepcopy(data)
        extra = copy.deepcopy(introductions[0])
        extra["id"] = "test_extra_introduction"
        duplicate["dialogues"].append(extra)
        with self.assertRaisesRegex(ValueError, "Duplicate first greeting"):
            validate(duplicate)

        for change in ({"once": False}, {"conditions": [
                {"type": "mission", "missionId": "all", "minCount": 1}
                ]}, {"priority": -1000}, {"firstGreeting": False}):
            invalid = copy.deepcopy(data)
            edited = next(row for row in invalid["dialogues"]
                          if row.get("firstGreeting") is True)
            edited.update(change)
            with self.subTest(change=change), self.assertRaises(ValueError):
                validate(invalid)

    def test_valid_bundled_content(self):
        validate(sample())
        frog = [entry for entry in sample()["dialogues"]
                if entry["residentId"] == "029_office_worker" and not entry.get("firstGreeting")]
        self.assertEqual(len(frog), 11)
        self.assertEqual([row["id"] for row in frog],
                         [f"029_office_worker_{number:03d}" for number in range(1, 12)])
        for entry in frog[6:10]:
            self.assertTrue(entry["once"])
            self.assertEqual(entry["conditions"][0]["withinDays"], 1)
        self.assertFalse(frog[10]["once"])
        self.assertEqual(frog[10]["conditions"], [])

    def test_rejects_invalid_dates_and_missions(self):
        for bad in (
            {"type": "date", "mode": "exact", "date": "2026-02-30"},
            {"type": "date", "mode": "range", "start": "2026-10-22", "end": "2026-10-10"},
            {"type": "date", "mode": "annual", "date": "13-01"},
            {"type": "date", "mode": "weekday", "days": [0]},
            {"type": "mission", "missionId": "unknown", "minCount": 2},
            {"type": "mission", "missionId": "outside", "minCount": 1, "withinDays": 0},
            {"type": "mission", "missionId": "outside", "minCount": 1, "withinDays": 2},
            {"type": "mission", "missionId": "outside", "minCount": 1, "withinDays": 3},
            {"type": "mission", "missionId": "outside", "minCount": 1, "withinDays": True},
            {"type": "mission", "missionId": "outside", "minCount": 1, "withinDays": "3"},
            {"type": "kotohogi", "min": -1},
        ):
            with self.subTest(bad=bad):
                doc = sample()
                doc["dialogues"][-1]["conditions"] = [bad]
                with self.assertRaises(ValueError):
                    validate(doc)

    def test_town_companion_and_two_speaker_reply_validation(self):
        normal = sample()
        selected = normal["dialogues"][0]
        selected["conditions"] = [{"type": "townTogether", "otherResidentId": "002_usagi"}]
        selected["reply"] = {"residentId": "002_usagi", "text": "絵を描きたい！"}
        validate(normal)
        for condition in (
            {"type": "townTogether", "otherResidentId": "001_shiba"},
            {"type": "townTogether", "otherResidentId": "unknown"},
            {"type": "townTogether", "otherResidentId": 10},
            {"type": "townTogether"},
        ):
            with self.subTest(condition=condition):
                invalid = copy.deepcopy(normal)
                invalid["dialogues"][0]["conditions"] = [condition]
                with self.assertRaises(ValueError):
                    validate(invalid)
        invalid_reply = copy.deepcopy(normal)
        invalid_reply["dialogues"][0]["logic"] = "any"
        with self.assertRaisesRegex(ValueError, "matching AND"):
            validate(invalid_reply)
        invalid_reply = copy.deepcopy(normal)
        invalid_reply["dialogues"][0]["reply"] = {
            "residentId": "003_penguin", "text": "違う人の返事"}
        with self.assertRaisesRegex(ValueError, "matching AND"):
            validate(invalid_reply)
        invalid_reply = copy.deepcopy(normal)
        invalid_reply["dialogues"][0]["reply"]["text"] = " "
        with self.assertRaisesRegex(ValueError, "matching AND"):
            validate(invalid_reply)
        invalid_reply = copy.deepcopy(normal)
        invalid_reply["dialogues"][0]["reply"]["unknown"] = True
        with self.assertRaisesRegex(ValueError, "invalid fields"):
            validate(invalid_reply)

    def test_cross_character_seen_dialogue_reference(self):
        data = sample()
        prerequisite = data["dialogues"][5]["id"]
        dependent = data["dialogues"][0]
        self.assertNotEqual(data["dialogues"][5]["residentId"],
                            dependent["residentId"])
        dependent["conditions"] = [
            {"type": "seenDialogue", "dialogueId": prerequisite}]
        validate(data)

        removed = copy.deepcopy(data)
        removed["dialogues"] = [
            row for row in removed["dialogues"] if row["id"] != prerequisite]
        with self.assertRaisesRegex(ValueError, "Invalid prerequisite dialogue"):
            validate(removed)

        for bad in (dependent["id"], "missing", "", 42, None):
            invalid = copy.deepcopy(data)
            invalid["dialogues"][0]["conditions"] = [
                {"type": "seenDialogue", "dialogueId": bad}]
            with self.subTest(id=bad), self.assertRaises(ValueError):
                validate(invalid)

        missing_field = copy.deepcopy(data)
        missing_field["dialogues"][0]["conditions"] = [{"type": "seenDialogue"}]
        with self.assertRaises(ValueError):
            validate(missing_field)

    def test_save_is_atomic_and_invalid_changes_leave_old_file(self):
        with tempfile.TemporaryDirectory() as temp:
            target = Path(temp) / "dialogues.json"
            with patch("server.DATA", target):
                good = sample()
                write_document(good)
                prior = target.read_bytes()
                invalid = copy.deepcopy(good)
                invalid["dialogues"][0]["residentId"] = "invalid"
                with self.assertRaises(ValueError):
                    write_document(invalid)
                self.assertEqual(target.read_bytes(), prior)
                self.assertEqual(json.loads(prior)["version"], 1)

    def test_dialogue_only_endpoint_cannot_allocate_without_counter(self):
        with tempfile.TemporaryDirectory() as temp:
            target = Path(temp) / "dialogues.json"
            with patch("server.DATA", target):
                write_document(sample())
                before = target.read_bytes()
                modified = sample()
                modified["dialogues"].append({
                    "id": "001_shiba_002", "residentId": "001_shiba",
                    "text": "新しい話", "priority": 0, "once": False,
                    "logic": "all", "conditions": [],
                })
                with self.assertRaisesRegex(ValueError, "Use /api/cms"):
                    write_document(modified)
                self.assertEqual(target.read_bytes(), before)

    def test_every_resident_needs_fallback_line(self):
        doc = sample()
        doc["dialogues"] = [
            e for e in doc["dialogues"]
            if e["residentId"] != "001_shiba" or e["conditions"]
        ]
        with self.assertRaises(ValueError):
            validate(doc)


if __name__ == "__main__":
    unittest.main()
