"""Validated character registry for the local CMS.

Saves a catalog, dialogue data, generated Flutter enum and asset manifest.
Existing resident IDs never change so stored collections remain readable.
"""
from __future__ import annotations

import json
import os
import re
import tempfile
from pathlib import Path
from areas import (load_areas, validate_areas, generate_town_areas,
                   AREAS as AREA_DATA, DART as AREA_DART)

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "assets" / "characters" / "characters.json"
DART = ROOT / "lib" / "resident_collection.dart"
PUBSPEC = ROOT / "pubspec.yaml"
DIALOGUES = ROOT / "assets" / "dialogues" / "dialogues.json"
DART_START = "  // BEGIN CMS RESIDENTS"
DART_END = "  // END CMS RESIDENTS"
ASSETS_START = "    # BEGIN CMS CHARACTER ASSETS"
ASSETS_END = "    # END CMS CHARACTER ASSETS"
FIELDS = {"key", "id", "label", "profile", "artFolder", "inGacha", "walkInTown", "nextDialogueNumber", "homeAreaId"}
AREA_IDS = {"plaza", "park", "shopping", "village", "salon"}
DIRECTIONS = ("front", "back", "left", "right")


def load_catalog():
    return json.loads(CATALOG.read_text(encoding="utf-8"))


def validate_catalog(document, previous=None, *, characters_root=None):
    if not isinstance(document, dict) or set(document) != {"version", "characters"}:
        raise ValueError("Invalid character catalog root")
    if type(document["version"]) is not int or document["version"] != 5:
        raise ValueError("Unsupported character catalog version")
    characters = document["characters"]
    if not isinstance(characters, list) or not 1 <= len(characters) <= 64:
        raise ValueError("Characters must contain 1-64 residents")
    ids, keys, folders = set(), set(), set()
    root = characters_root if characters_root is not None else CATALOG.parent
    for index, row in enumerate(characters):
        if not isinstance(row, dict) or set(row) not in (FIELDS, FIELDS | {"archived"}):
            raise ValueError(f"Invalid character fields at row {index}")
        if "archived" in row and row["archived"] is not True:
            raise ValueError(f"Archived flag must be true when present at row {index}")
        key, identifier, folder = row["key"], row["id"], row["artFolder"]
        if not isinstance(key, str) or not re.fullmatch(r"[a-z][a-z0-9_]*", key):
            raise ValueError(f"Invalid character key at row {index}")
        if key in {"values", "index", "name", "byName", "id", "label", "artFolder",
                   "inGacha", "walkInTown", "archived", "homeAreaId", "nextDialogueNumber", "gachaPool",
                   "abstract", "as", "assert", "async", "await", "base", "break",
                   "case", "catch", "class", "const", "continue", "covariant",
                   "default", "deferred", "do", "dynamic", "else", "enum",
                   "export", "extends", "extension", "external", "factory",
                   "false", "final", "finally", "for", "Function", "get",
                   "hide", "if", "implements", "import", "in", "interface",
                   "is", "late", "library", "mixin", "new", "null", "on",
                   "operator", "part", "required", "rethrow", "return",
                   "sealed", "set", "show", "static", "super", "switch",
                   "sync", "this", "throw", "true", "try", "typedef", "var",
                   "void", "when", "while", "with", "yield"}:
            raise ValueError(f"Reserved character key: {key}")
        if not isinstance(identifier, str) or not re.fullmatch(r"[0-9]{2,}_[a-z][a-z0-9_]*", identifier):
            raise ValueError(f"Invalid resident ID at row {index}")
        if not isinstance(folder, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", folder) or ".." in folder:
            raise ValueError(f"Invalid sprite folder at row {index}")
        if identifier != folder:
            raise ValueError(f"Character ID and sprite folder must match: {identifier} != {folder}")
        if previous is not None and index >= len(previous["characters"]):
            if key != f"c{identifier}" or folder != identifier:
                raise ValueError(f"New resident key and art folder must be derived from ID: {identifier}")
        if not isinstance(row["label"], str) or not 1 <= len(row["label"].strip()) <= 40:
            raise ValueError(f"Invalid resident name at row {index}")
        if not isinstance(row["profile"], str) or len(row["profile"]) > 1000:
            raise ValueError(f"Invalid profile for {identifier}: expected string of at most 1000 characters")
        if type(row["inGacha"]) is not bool or type(row["walkInTown"]) is not bool:
            raise ValueError(f"Invalid resident flags at row {index}")
        if type(row["homeAreaId"]) is not str or row["homeAreaId"] not in AREA_IDS:
            raise ValueError(f"Invalid home area for {identifier}: {row['homeAreaId']!r}")
        if type(row["nextDialogueNumber"]) is not int or not 1 <= row["nextDialogueNumber"] <= 1000000000:
            raise ValueError(f"Invalid next dialogue number for {identifier}")
        if identifier in ids or key in keys or folder in folders:
            raise ValueError(f"Duplicate resident ID, key, or sprite folder at row {index}")
        ids.add(identifier)
        keys.add(key)
        folders.add(folder)
        directory = root / folder
        if not directory.is_dir() or not directory.resolve().is_relative_to(root.resolve()):
            raise ValueError(f"Sprite folder not found: {folder}")
        required = ["idle_front_01.png", "clap_front_01.png", "clap_front_02.png"]
        required += [
            f"walk_{direction}_{frame:02d}.png"
            for direction in DIRECTIONS
            for frame in range(1, 5)
            if not (identifier == "001_shiba" and direction == "left")
        ]
        missing = [name for name in required if not (directory / name).is_file()]
        if missing:
            raise ValueError(f"Missing sprite in {folder}: {missing[0]}")
    owner = next((row for row in characters if row["id"] == "035_beaty"), None)
    if owner is not None and (
        owner.get("archived") is True
        or owner["homeAreaId"] != "salon"
        or owner["inGacha"] is not True
        or owner["walkInTown"] is not False
    ):
        raise ValueError(
            "Salon owner 035_beaty must be in salon, in gacha, and not walk outside"
        )
    if sum(row["homeAreaId"] == "salon" and not row.get("archived", False)
           for row in characters) > 7:
        raise ValueError("Salon supports at most 7 assigned residents")
    if not any(row["inGacha"] and not row.get("archived", False)
               for row in characters):
        raise ValueError("At least one resident must be available in gacha")
    if previous is not None:
        prior = previous["characters"]
        if len(characters) < len(prior):
            raise ValueError("Existing residents cannot be removed (saved data uses their IDs)")
        for index, old in enumerate(prior):
            new = characters[index]
            if any(old[field] != new[field] for field in ("key", "id", "artFolder")):
                raise ValueError(f"Existing resident identity cannot change: {old['id']}")
            if new["nextDialogueNumber"] < old["nextDialogueNumber"]:
                raise ValueError(f"Dialogue number cannot decrease: {old['id']}")
    return document


def validate_dialogue_ids(catalog, dialogues, previous_catalog, previous_dialogues):
    """Keep persisted IDs stable and never allocate retired dialogue numbers."""
    old_entries = {entry["id"]: entry["residentId"]
                   for entry in previous_dialogues["dialogues"]}
    current_rows = {row["id"]: row for row in catalog["characters"]}
    old_rows = {row["id"]: row for row in previous_catalog["characters"]}
    for entry in dialogues["dialogues"]:
        identifier = entry["id"]
        resident_id = entry["residentId"]
        if identifier in old_entries and old_entries[identifier] != resident_id:
            raise ValueError(f"Existing dialogue resident cannot change: {identifier}")
        row = current_rows[resident_id]
        prefix = resident_id + "_"
        suffix = identifier[len(prefix):] if identifier.startswith(prefix) else ""
        numbered = re.fullmatch(r"[0-9]{3,}", suffix) is not None
        if identifier not in old_entries:
            if not numbered or int(suffix) < 1 or suffix != str(int(suffix)).zfill(3):
                raise ValueError(f"New dialogue ID must use character ID and serial: {identifier}")
            if resident_id in old_rows and int(suffix) < old_rows[resident_id]["nextDialogueNumber"]:
                raise ValueError(f"Dialogue number already reserved: {identifier}")
        if numbered and int(suffix) >= row["nextDialogueNumber"]:
            raise ValueError(f"Dialogue number was not reserved: {identifier}")


def replace_section(source, start, end, lines):
    if source.count(start) != 1 or source.count(end) != 1:
        raise ValueError(f"Generated section marker missing or duplicated: {start}")
    before, remainder = source.split(start, 1)
    _, after = remainder.split(end, 1)
    return before + start + "\n" + lines + "\n" + end + after


def generate_dart(source, characters):
    declarations = []
    for row in characters:
        # Dart interpolates dollar signs inside quoted strings; preserve literal labels.
        label = json.dumps(row["label"], ensure_ascii=False).replace("$", r"\$")
        profile = json.dumps(row["profile"], ensure_ascii=False).replace("$", r"\$")
        # Keep persisted enum keys unchanged, including legacy underscored keys.
        ignore_lint = "  // ignore: constant_identifier_names\n" if "_" in row["key"] else ""
        active = not row.get("archived", False)
        # Keep old IDs and assets, so already saved collections still decode.
        home = row["homeAreaId"] if active else "plaza"
        archived = "" if active else ", archived: true"
        declarations.append(
            f'{ignore_lint}  {row["key"]}("{row["id"]}", {label}, "{row["artFolder"]}", '
            f'{"true" if active and row["inGacha"] else "false"}, '
            f'{"true" if active and row["walkInTown"] else "false"}, {profile}, "{home}"{archived})'
        )
    return replace_section(source, DART_START, DART_END, ",\n".join(declarations))


def generate_pubspec(source, characters):
    # The tutorial character is registered separately, without gacha access.
    folders = sorted({row["artFolder"] for row in characters
                      if row["artFolder"] != "013_kotohogisu"})
    rows = "\n".join(f"    - assets/characters/{folder}/" for folder in folders)
    return replace_section(source, ASSETS_START, ASSETS_END, rows)


def commit_files(contents):
    """Stage all files before writing, restoring earlier replacements on failure."""
    originals = {}
    staged = []
    replaced = []
    try:
        for path, text in contents.items():
            originals[path] = path.read_bytes()
            with tempfile.NamedTemporaryFile(
                "wb", dir=path.parent, prefix=".kotohogu-cms-", suffix=".tmp",
                delete=False
            ) as tmp:
                tmp.write(text.encode("utf-8"))
                tmp.flush()
                os.fsync(tmp.fileno())
                staged.append((Path(tmp.name), path))
        try:
            for tmp, path in staged:
                os.replace(tmp, path)
                replaced.append(path)
        except OSError as original_error:
            rollback_errors = []
            for path in reversed(replaced):
                try:
                    with tempfile.NamedTemporaryFile(
                        "wb", dir=path.parent, prefix=".kotohogu-rollback-",
                        suffix=".tmp", delete=False
                    ) as restored:
                        restored.write(originals[path])
                        restored.flush()
                        os.fsync(restored.fileno())
                        recovery = restored.name
                    try:
                        os.replace(recovery, path)
                    finally:
                        if os.path.exists(recovery):
                            os.unlink(recovery)
                except OSError as rollback_error:
                    rollback_errors.append(f"{path}: {rollback_error}")
            if rollback_errors:
                raise OSError(f"CMS write failed: {original_error}; "
                              f"rollback failed: {'; '.join(rollback_errors)}") from original_error
            raise
    finally:
        for temp, _ in staged:
            if temp.exists():
                temp.unlink()


def validate_archive_dependencies(catalog, dialogues):
    """Prevent live dialogue conditions from referencing archived residents."""
    retired = {row["id"] for row in catalog["characters"] if row.get("archived")}
    retired_lines = {entry["id"] for entry in dialogues["dialogues"]
                     if entry["residentId"] in retired}
    for entry in dialogues["dialogues"]:
        if entry["residentId"] in retired:
            continue
        for condition in entry["conditions"]:
            resident = (
                condition.get("residentId") if condition["type"] == "residentOwned"
                else condition.get("otherResidentId") if condition["type"] == "townTogether"
                else None
            )
            if resident in retired or (
                condition["type"] == "seenDialogue"
                and condition["dialogueId"] in retired_lines
            ):
                raise ValueError(
                    f"Active dialogue {entry['id']} depends on archived character: "
                    f"{resident or condition.get('dialogueId')}"
                )
        if entry.get("reply", {}).get("residentId") in retired:
            raise ValueError(f"Active dialogue {entry['id']} replies as archived character")


def archive_code_blockers(catalog):
    """Share the same core/code restrictions with the editor and save validator."""
    sources = []
    for path in sorted((ROOT / "lib").rglob("*.dart")):
        source = path.read_text(encoding="utf-8")
        if path == DART:
            source = replace_section(source, DART_START, DART_END, "")
        sources.append((path.relative_to(ROOT), source))
    blockers = {}
    for row in catalog["characters"]:
        if row["id"] in {"001_shiba", "002_usagi", "035_beaty"}:
            blockers[row["id"]] = f"Core resident cannot be archived: {row['id']}"
            continue
        for path, source in sources:
            if (re.search(r"\bTownResident\." + re.escape(row["key"]) + r"\b", source)
                    or re.search(r"(?<![A-Za-z0-9])" + re.escape(row["id"])
                                 + r"(?![A-Za-z0-9])", source)):
                blockers[row["id"]] = (
                    f"Character {row['id']} is used by app code in "
                    f"{path}; remove the dependency before archiving"
                )
                break
    return blockers


def validate_archive_code_references(catalog, previous):
    """Block removal from play while hard-coded Dart dependencies remain."""
    previously_retired = {row["id"] for row in previous["characters"]
                          if row.get("archived")}
    blockers = archive_code_blockers(catalog)
    for row in catalog["characters"]:
        if (row.get("archived") and row["id"] not in previously_retired
                and row["id"] in blockers):
            raise ValueError(blockers[row["id"]])


def save_catalog_and_dialogues(payload, validate_dialogues):
    if (not isinstance(payload, dict) or
            set(payload) not in ({"characters", "dialogues"},
                                 {"characters", "dialogues", "areas"})):
        raise ValueError("Expected character, dialogue and optional area documents")
    previous_areas = validate_areas(load_areas())
    area_doc = validate_areas(payload.get("areas", previous_areas), previous=previous_areas)
    previous = load_catalog()
    catalog = validate_catalog(payload["characters"], previous=previous)
    ids = {row["id"] for row in catalog["characters"]}
    dialogues = validate_dialogues(payload["dialogues"], residents=ids)
    previous_dialogues = json.loads(DIALOGUES.read_text(encoding="utf-8"))
    validate_dialogues(previous_dialogues, residents={row["id"] for row in previous["characters"]})
    validate_dialogue_ids(catalog, dialogues, previous, previous_dialogues)
    validate_archive_dependencies(catalog, dialogues)
    validate_archive_code_references(catalog, previous)
    dart = generate_dart(DART.read_text(encoding="utf-8"), catalog["characters"])
    pubspec = generate_pubspec(PUBSPEC.read_text(encoding="utf-8"), catalog["characters"])
    town_dart = generate_town_areas(AREA_DART.read_text(encoding="utf-8"), area_doc)
    commit_files({
        CATALOG: json.dumps(catalog, ensure_ascii=False, indent=2) + "\n",
        DIALOGUES: json.dumps(dialogues, ensure_ascii=False, indent=2) + "\n",
        DART: dart,
        PUBSPEC: pubspec,
        AREA_DATA: json.dumps(area_doc, ensure_ascii=False, indent=2) + "\n",
        AREA_DART: town_dart,
    })
    return {"ok": True, "characters": len(catalog["characters"]),
            "dialogues": len(dialogues["dialogues"]),
            "areas": len(area_doc["areas"])}
