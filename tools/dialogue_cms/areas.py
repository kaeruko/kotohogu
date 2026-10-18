"""Validated, CMS-owned town areas; the four stable area IDs are not editable.

The generated Flutter enum keeps the current static API and saved progress
unchanged. Resident homeAreaId still belongs to characters.json.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
AREAS = ROOT / "assets" / "town" / "areas.json"
DART = ROOT / "lib" / "town_areas.dart"
AREA_IDS = ("plaza", "park", "shopping", "village")
START = "  // BEGIN CMS TOWN AREAS"
END = "  // END CMS TOWN AREAS"
FIELDS = {
    "id", "label", "description", "unlockAt",
    "backgroundAsset", "sourceWidth", "sourceHeight",
}


def load_areas():
    return json.loads(AREAS.read_text(encoding="utf-8"))


def validate_areas(doc, previous=None, *, asset_root=None):
    if not isinstance(doc, dict) or set(doc) != {"version", "areas"}:
        raise ValueError("Invalid town areas root")
    if type(doc["version"]) is not int or doc["version"] != 1:
        raise ValueError("Unsupported town areas version")
    entries = doc["areas"]
    if not isinstance(entries, list) or len(entries) != len(AREA_IDS):
        raise ValueError("Town area IDs and order must remain fixed")
    root = asset_root if asset_root is not None else ROOT
    last_unlock = -1
    for i, (entry, expected_id) in enumerate(zip(entries, AREA_IDS)):
        if not isinstance(entry, dict) or set(entry) != FIELDS:
            raise ValueError(f"Invalid fields for town area {expected_id}")
        if entry["id"] != expected_id:
            raise ValueError("Town area IDs and order must remain fixed")
        if not isinstance(entry["label"], str) or not 1 <= len(entry["label"].strip()) <= 40:
            raise ValueError(f"Invalid label for town area {expected_id}")
        if not isinstance(entry["description"], str) or not 1 <= len(entry["description"].strip()) <= 300:
            raise ValueError(f"Invalid description for town area {expected_id}")
        value = entry["unlockAt"]
        if type(value) is not int or not 0 <= value <= 10_000_000:
            raise ValueError(f"Invalid unlock threshold for {expected_id}")
        if i == 0 and value != 0:
            raise ValueError("Central plaza must be open from the beginning")
        if i and value <= last_unlock:
            raise ValueError("Area unlock thresholds must increase in navigation order")
        last_unlock = value

        background = entry["backgroundAsset"]
        if not isinstance(background, str) or not re.fullmatch(
                r"assets/kotohogu/[A-Za-z0-9_][A-Za-z0-9_.-]*\.(?:png|jpg|jpeg)",
                background):
            raise ValueError(f"Invalid background path for {expected_id}")
        if not (root / background).is_file():
            raise ValueError(f"Background file does not exist: {background}")
        for field in ("sourceWidth", "sourceHeight"):
            dimension = entry[field]
            if type(dimension) is not int or not 1 <= dimension <= 10000:
                raise ValueError(f"Invalid {field} for {expected_id}")
    if previous is not None:
        validate_areas(previous, asset_root=root)
        if [a["id"] for a in entries] != [a["id"] for a in previous["areas"]]:
            raise ValueError("Cannot change existing town area IDs")
    return doc


def generate_town_areas(source, doc):
    validate_areas(doc)
    if source.count(START) != 1 or source.count(END) != 1:
        raise ValueError("CMS town area markers missing or duplicated")
    lines = []
    for row in doc["areas"]:
        label = json.dumps(row["label"], ensure_ascii=False).replace("$", r"\$")
        description = json.dumps(row["description"], ensure_ascii=False).replace("$", r"\$")
        asset = json.dumps(row["backgroundAsset"], ensure_ascii=False)
        lines.append(
            f'  {row["id"]}("{row["id"]}", {label}, {description}, '
            f'{row["unlockAt"]}, {asset}, '
            f'{row["sourceWidth"]}, {row["sourceHeight"]})'
        )
    before, rest = source.split(START, 1)
    _, after = rest.split(END, 1)
    return before + START + "\n" + ",\n".join(lines) + ";\n  " + END + after
