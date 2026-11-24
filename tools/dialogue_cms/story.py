"""Validate and resolve the files in the published Sudoku story."""

import json
import re
import struct
from pathlib import Path

from areas import load_areas, validate_areas


ROOT = Path(__file__).resolve().parents[2] / "assets" / "story"
DATA = ROOT / "story.json"
LEGACY_DATA = ROOT / "legacy_story.json"
V2_DATA = ROOT / "story_v2.json"
MAX_JSON_BYTES = 256 * 1024
IMAGE_NAME = re.compile(r"[a-z0-9][a-z0-9_-]{0,79}\.(?:png|webp)")
EPISODE_ID = re.compile(r"[a-z][a-z0-9_]{0,47}")
EPISODE_FIELDS = {
    "id", "title", "area", "unlockAt", "image", "dialogue", "puzzle",
    "solution", "clue", "result", "resultDialogue",
}


def load_story(resident_ids):
    return _load_document(DATA, resident_ids)


def load_legacy_story(resident_ids):
    """Frozen 11-part story for already-installed app versions."""
    return _load_document(LEGACY_DATA, resident_ids, legacy=True)


def load_v2_story(resident_ids):
    """Frozen PNG-only chapter catalog for installed v2 clients."""
    return _load_document(V2_DATA, resident_ids, png_only=True)


def _load_document(path, resident_ids, *, legacy=False, png_only=False):
    raw = path.read_bytes()
    if len(raw) > MAX_JSON_BYTES:
        raise ValueError(f"Sudoku story exceeds {MAX_JSON_BYTES} bytes")
    areas = {row["id"]: row["unlockAt"]
             for row in validate_areas(load_areas())["areas"]
             if row["id"] != "hospital"}
    doc = validate_story(json.loads(raw), resident_ids, areas, legacy=legacy)
    if len(json.dumps(doc, ensure_ascii=False).encode("utf-8")) + 1 > MAX_JSON_BYTES:
        raise ValueError(f"Encoded Sudoku story exceeds {MAX_JSON_BYTES} bytes")
    for image in story_images(doc):
        if (legacy or png_only) and not image.endswith(".png"):
            raise ValueError(f"Frozen story requires PNG: {image}")
        story_image_bytes(image)
    return doc


def validate_story(doc, resident_ids, areas, *, legacy=False):
    required = {"version", "title", "coverImage", "episodes"}
    if not legacy:
        required.add("chapters")
    if (not isinstance(doc, dict) or set(doc) != required
            or type(doc["version"]) is not int or doc["version"] != 1):
        raise ValueError("Invalid Sudoku story schema or version")
    _text(doc["title"], "story title")
    _image_name(doc["coverImage"])
    episodes = doc["episodes"]
    if not isinstance(episodes, list) or not 1 <= len(episodes) <= 128:
        raise ValueError("Invalid Sudoku story episode count")
    previous_unlock = -1
    ids = set()
    for index, row in enumerate(episodes):
        if (not isinstance(row, dict) or not EPISODE_FIELDS <= row.keys()
                or row.keys() - EPISODE_FIELDS - {"destination", "resultImage"}):
            raise ValueError(f"Invalid Sudoku story episode fields: {index}")
        identifier = row["id"]
        if (not isinstance(identifier, str) or not EPISODE_ID.fullmatch(identifier)
                or identifier in ids):
            raise ValueError(f"Invalid or duplicate Sudoku episode ID: {identifier}")
        ids.add(identifier)
        unlock = row["unlockAt"]
        locations = [row["area"]] + ([row["destination"]] if "destination" in row else [])
        if (type(unlock) is not int or unlock % 10 or unlock <= previous_unlock
                or (index == 0 and unlock != 0)
                or any(not isinstance(area, str) or area not in areas
                       or unlock < areas[area] for area in locations)):
            raise ValueError(f"Invalid Sudoku story unlock or area: {identifier}")
        previous_unlock = unlock
        for field in ("title", "clue", "result"):
            _text(row[field], f"{identifier}.{field}")
        for field in ("image", "resultImage"):
            if field in row:
                _image_name(row[field])
        for field in ("dialogue", "resultDialogue"):
            turns = row[field]
            if (not isinstance(turns, list) or len(turns) > 20
                    or (field == "dialogue" and not turns)):
                raise ValueError(f"Invalid Sudoku story turns: {identifier}.{field}")
            for turn in turns:
                if (not isinstance(turn, dict) or set(turn) != {"speaker", "text"}
                        or not isinstance(turn["speaker"], str)
                        or turn["speaker"] not in resident_ids):
                    raise ValueError(f"Invalid Sudoku story speaker: {identifier}.{field}")
                _text(turn["text"], f"{identifier}.{field}")
        _validate_puzzle(row["puzzle"], row["solution"], identifier)
    if not legacy:
        chapters = doc["chapters"]
        if (not isinstance(chapters, list)
                or not 1 <= len(chapters) <= len(episodes)):
            raise ValueError("Invalid Sudoku story chapter count")
        order = {row["id"]: index for index, row in enumerate(episodes)}
        chapter_ids = set()
        previous_start = -1
        for number, chapter in enumerate(chapters):
            if not isinstance(chapter, dict) or set(chapter) != {
                    "id", "title", "startEpisodeId"}:
                raise ValueError(f"Invalid Sudoku chapter fields: {number}")
            identifier = chapter["id"]
            first = chapter["startEpisodeId"]
            if (not isinstance(identifier, str)
                    or EPISODE_ID.fullmatch(identifier) is None
                    or identifier in chapter_ids
                    or not isinstance(first, str) or first not in order
                    or order[first] <= previous_start
                    or (number == 0 and order[first] != 0)):
                raise ValueError(f"Invalid Sudoku chapter boundary: {number}")
            _text(chapter["title"], f"chapter {identifier} title")
            chapter_ids.add(identifier)
            previous_start = order[first]
    return doc



def save_story(doc):
    """Validate the CMS document and atomically replace only story.json.

    Valid story structures may be revised freely. A changed structure
    receives a new story signature in the app.
    """
    from characters import commit_files, load_catalog, validate_catalog

    registry = validate_catalog(load_catalog())
    active = {row["id"] for row in registry["characters"]
              if not row.get("archived", False)}
    areas = {row["id"]: row["unlockAt"]
             for row in validate_areas(load_areas())["areas"]
             if row["id"] != "hospital"}
    validate_story(doc, active, areas)
    payload = json.dumps(doc, ensure_ascii=False, indent=2) + "\n"
    if len(payload.encode("utf-8")) > MAX_JSON_BYTES:
        raise ValueError(f"Sudoku story exceeds {MAX_JSON_BYTES} bytes")
    for image in story_images(doc):
        story_image_bytes(image)
    commit_files({DATA: payload})


def _text(value, field):
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"Empty Sudoku story text: {field}")


def _image_name(name):
    if not isinstance(name, str) or not IMAGE_NAME.fullmatch(name):
        raise ValueError(f"Invalid Sudoku story image name: {name!r}")


def story_images(doc):
    return sorted({doc["coverImage"], *(row["image"] for row in doc["episodes"]),
                   *(row["resultImage"] for row in doc["episodes"] if "resultImage" in row)})


def story_image_bytes(name):
    _image_name(name)
    root = ROOT.resolve()
    path = (root / name).resolve()
    if not path.is_relative_to(root):
        raise ValueError(f"Sudoku story image is outside the asset directory: {name}")
    with path.open("rb") as source:
        raw = source.read(8 * 1024 * 1024 + 1)
    if len(raw) > 8 * 1024 * 1024:
        raise ValueError(f"Sudoku story image exceeds size limit: {name}")
    if name.endswith(".png"):
        if (len(raw) < 33
                or raw[:16] != b"\x89PNG\r\n\x1a\n\x00\x00\x00\x0dIHDR"
                or not all(1 <= size <= 4096 for size in struct.unpack(">II", raw[16:24]))):
            raise ValueError(f"Invalid Sudoku story PNG: {name}")
    else:
        _validate_webp(raw, name)
    return raw


def story_image_mime(name):
    _image_name(name)
    return {"png": "image/png", "webp": "image/webp"}[name.rsplit(".", 1)[1]]


def _validate_webp(raw, name):
    def invalid():
        raise ValueError(f"Invalid Sudoku story WebP: {name}")

    if (len(raw) < 20 or raw[:4] != b"RIFF" or raw[8:12] != b"WEBP"
            or int.from_bytes(raw[4:8], "little") != len(raw) - 8):
        invalid()
    offset = 12
    dimensions = []
    image_count = 0
    while offset < len(raw):
        if offset + 8 > len(raw):
            invalid()
        tag = raw[offset:offset + 4]
        length = int.from_bytes(raw[offset + 4:offset + 8], "little")
        end = offset + 8 + length
        padded_end = end + (length & 1)
        if padded_end > len(raw):
            invalid()
        chunk = raw[offset + 8:end]
        if tag == b"VP8X":
            if offset != 12 or length != 10 or chunk[0] & 0x02:
                invalid()
            dimensions.append((1 + int.from_bytes(chunk[4:7], "little"),
                               1 + int.from_bytes(chunk[7:10], "little")))
        elif tag == b"VP8 ":
            if length < 10 or chunk[0] & 1 or chunk[3:6] != b"\x9d\x01\x2a":
                invalid()
            dimensions.append((int.from_bytes(chunk[6:8], "little") & 0x3fff,
                               int.from_bytes(chunk[8:10], "little") & 0x3fff))
            image_count += 1
        elif tag == b"VP8L":
            if length < 5 or chunk[0] != 0x2f:
                invalid()
            bits = int.from_bytes(chunk[1:5], "little")
            if bits >> 29:
                invalid()
            dimensions.append((1 + (bits & 0x3fff), 1 + ((bits >> 14) & 0x3fff)))
            image_count += 1
        elif tag in (b"ANIM", b"ANMF"):
            invalid()
        offset = padded_end
    if (image_count != 1 or not dimensions
            or any(not all(1 <= size <= 4096 for size in pair) for pair in dimensions)
            or any(pair != dimensions[0] for pair in dimensions)):
        invalid()


def _validate_puzzle(puzzle, solution, identifier):
    if (not isinstance(puzzle, str) or len(puzzle) not in (16, 36)
            or not isinstance(solution, str) or len(solution) != len(puzzle)):
        raise ValueError(f"Invalid Sudoku dimensions: {identifier}")
    size = 4 if len(puzzle) == 16 else 6
    digits = set("123456"[:size])
    if (set(puzzle) - digits - {"0"} or set(solution) - digits or "0" not in puzzle
            or any(given not in ("0", answer) for given, answer in zip(puzzle, solution))):
        raise ValueError(f"Invalid Sudoku digits: {identifier}")
    box_width = size // 2

    def group(cell):
        row, col = divmod(cell, size)
        return row, col, (row // 2) * 2 + col // box_width

    groups = [group(cell) for cell in range(len(puzzle))]
    peers = [[other for other, target in enumerate(groups) if other != cell and
              any(a == b for a, b in zip(keys, target))]
             for cell, keys in enumerate(groups)]
    if any(solution[other] == solution[cell] for cell, group_peers in enumerate(peers)
           for other in group_peers):
        raise ValueError(f"Invalid Sudoku solution: {identifier}")
    board = list(puzzle)

    def solutions():
        options = [(digits - {board[other] for other in peers[i]}, i)
                   for i, value in enumerate(board) if value == "0"]
        if not options:
            return 1
        candidates, cell = min(options, key=lambda item: len(item[0]))
        count = 0
        for digit in candidates:
            board[cell] = digit
            count += solutions()
            if count >= 2:
                break
        board[cell] = "0"
        return count

    if solutions() != 1:
        raise ValueError(f"Sudoku puzzle must have one solution: {identifier}")
