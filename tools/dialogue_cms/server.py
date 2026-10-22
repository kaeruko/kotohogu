"""Local-only dialogue editor server. No third-party dependencies or cloud API."""
from __future__ import annotations

import json
import os
import re
import tempfile
from datetime import date
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import events
import facilities
from urllib.parse import parse_qs, urlsplit
from characters import (archive_code_blockers, load_catalog, validate_catalog,
                        save_catalog_and_dialogues)
from areas import load_areas, validate_areas, AREAS as AREA_DATA

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / "assets" / "dialogues" / "dialogues.json"
INDEX = Path(__file__).with_name("index.html")
SPRITES = ROOT / "assets" / "characters"


def portrait_path(folder):
    """Read only the front idle sprite from a safe asset directory."""
    if (not isinstance(folder, str)
            or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", folder)
            or ".." in folder):
        raise ValueError("Invalid character sprite folder")
    root = SPRITES.resolve()
    image = (root / folder / "idle_front_01.png").resolve()
    if not image.is_relative_to(root):
        raise ValueError("Portrait path escapes the sprite directory")
    if not image.is_file():
        raise FileNotFoundError(
            f"Portrait not found: assets/characters/{folder}/idle_front_01.png")
    return image


RUNTIME_SPRITE_FILE = re.compile(
    r"(?:idle_front_01|clap_front_0[12]|"
    r"walk_(?:front|back|left|right)_0[1-4])\.png\Z"
)


def runtime_catalog():
    """One validated snapshot for local remote-content experiments."""
    registry = validate_catalog(load_catalog())
    dialogues = json.loads(DATA.read_text(encoding="utf-8"))
    validate(dialogues, residents={row["id"] for row in registry["characters"]})
    active = {row["id"] for row in registry["characters"]
              if not row.get("archived", False)}
    visible = {"version": 1, "dialogues": [
        entry for entry in dialogues["dialogues"] if entry["residentId"] in active
    ]}
    validate(visible, residents=active)
    return {
        "version": 1,
        # The preview schema does not allow CMS-only archival metadata.
        "characters": [{key: value for key, value in row.items()
                        if key != "archived"} for row in registry["characters"]
                       if row["id"] in active],
        "dialogues": visible["dialogues"],
    }


def runtime_sprite_path(folder, filename):
    if (not isinstance(folder, str)
            or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", folder)
            or ".." in folder
            or not isinstance(filename, str)
            or RUNTIME_SPRITE_FILE.fullmatch(filename) is None):
        raise ValueError("Invalid runtime sprite path")
    catalog = validate_catalog(load_catalog())
    if folder not in {row["artFolder"] for row in catalog["characters"]}:
        raise ValueError("Unregistered sprite folder: " + folder)
    root = SPRITES.resolve()
    image = (root / folder / filename).resolve()
    if not image.is_relative_to(root):
        raise ValueError("Runtime sprite escaped asset root")
    if not image.is_file():
        raise FileNotFoundError(f"Missing runtime sprite: {folder}/{filename}")
    return image


def resident_ids():
    return {row["id"] for row in validate_catalog(load_catalog())["characters"]}
DIALOGUE_SITES = {'roster', 'town', 'salon', 'bakery', 'community_center'}
MISSIONS = {
    "all", "strength", "outside", "conversation", "movement", "sittingBreak",
    "food", "hobby", "weeklyStrength", "weeklyActive", "weeklyTogether",
    "weeklyLearn", "monthlyCommunity", "monthlyHabit", "monthlyReview",
}


def require_keys(obj, keys, location, optional=frozenset()):
    if not isinstance(obj, dict):
        raise ValueError(
            f"{location}: expected a JSON object, got {type(obj).__name__}")
    present = set(obj)
    missing = sorted(set(keys) - present)
    unexpected = sorted(present - (set(keys) | set(optional)))
    if missing or unexpected:
        raise ValueError(
            f"{location}: invalid fields; missing={missing}, unexpected={unexpected}")


def whole_number(value, minimum, maximum):
    return type(value) is int and minimum <= value <= maximum


def date_full(value):
    if not isinstance(value, str) or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", value):
        raise ValueError("Invalid YYYY-MM-DD")
    if date.fromisoformat(value).isoformat() != value:
        raise ValueError("Invalid calendar date")


def month_day(value):
    if not isinstance(value, str) or not re.fullmatch(r"\d{2}-\d{2}", value):
        raise ValueError("Invalid MM-DD")
    date_full("2000-" + value)  # Leap day can be an annual event.


def validate(doc, residents=None):
    if residents is None:
        residents = resident_ids()
    require_keys(doc, {"version", "dialogues"}, "root")
    if doc["version"] != 1 or type(doc["version"]) is not int:
        raise ValueError("Unsupported dialogue version")
    rows = doc["dialogues"]
    if not isinstance(rows, list) or not rows:
        raise ValueError("Dialogues must be a nonempty list")
    ids = set()
    defaults = set()
    introductions = set()
    for i, entry in enumerate(rows):
        require_keys(entry, {"id", "residentId", "text", "priority",
                              "once", "logic", "conditions"}, f"dialogues[{i}]",
                     optional={"reply", "firstGreeting"})
        identifier = entry["id"]
        if not isinstance(identifier, str) or not re.fullmatch(r"[A-Za-z0-9_-]{1,80}", identifier):
            raise ValueError(f"Invalid id at row {i}")
        if identifier in ids:
            raise ValueError(f"Duplicate dialogue id: {identifier}")
        ids.add(identifier)
        if entry["residentId"] not in residents:
            raise ValueError(f"Unknown resident: {identifier}")
        if not isinstance(entry["text"], str) or not entry["text"].strip() or len(entry["text"]) > 500:
            raise ValueError(f"Invalid text: {identifier}")
        if not whole_number(entry["priority"], -1000, 1000):
            raise ValueError(f"Invalid priority: {identifier}")
        if type(entry["once"]) is not bool or entry["logic"] not in {"all", "any"}:
            raise ValueError(f"Invalid once/logic: {identifier}")
        if "firstGreeting" in entry:
            if entry["firstGreeting"] is not True:
                raise ValueError(f"firstGreeting must be true when present: {identifier}")
            if (not entry["once"] or entry["priority"] == -1000 or
                    entry["conditions"] or "reply" in entry):
                raise ValueError(f"Invalid first greeting: {identifier}")
            if entry["residentId"] in introductions:
                raise ValueError(f"Duplicate first greeting: {entry['residentId']}")
            introductions.add(entry["residentId"])
        conditions = entry["conditions"]
        if not isinstance(conditions, list) or len(conditions) > 8:
            raise ValueError(f"Invalid conditions: {identifier}")
        if entry["logic"] != "all" and any(
                isinstance(c, dict) and c.get("type") == "site" for c in conditions):
            raise ValueError(f"Location-specific dialogue requires AND: {identifier}")
        if not conditions and not entry["once"]:
            defaults.add(entry["residentId"])
        for j, condition in enumerate(conditions):
            loc = f"{identifier}.conditions[{j}]"
            if not isinstance(condition, dict):
                raise ValueError(f"Invalid condition: {loc}")
            kind = condition.get("type")
            if kind == "site":
                require_keys(condition, {"type", "siteId"}, loc)
                if type(condition["siteId"]) is not str or condition["siteId"] not in DIALOGUE_SITES:
                    raise ValueError(f"Invalid conversation site: {loc}")
            elif kind == "seenDialogue":
                require_keys(condition, {"type", "dialogueId"}, loc)
                prerequisite = condition["dialogueId"]
                if not isinstance(prerequisite, str) or not re.fullmatch(
                        r"[A-Za-z0-9_-]{1,80}", prerequisite):
                    raise ValueError(f"Invalid prerequisite dialogue ID: {loc}")
            elif kind == "oyasumiClub":
                require_keys(condition, {"type", "completed"}, loc)
                if type(condition["completed"]) is not bool:
                    raise ValueError(f"Invalid oyasumi club completion: {loc}")
            elif kind == "residentOwned":
                require_keys(condition, {"type", "residentId", "owned"}, loc)
                if condition["residentId"] not in residents or type(condition["owned"]) is not bool:
                    raise ValueError(f"Invalid resident ownership: {loc}")
            elif kind == "townTogether":
                require_keys(condition, {"type", "otherResidentId"}, loc)
                other = condition["otherResidentId"]
                if other not in residents or other == entry["residentId"]:
                    raise ValueError(f"Invalid town companion: {loc}")
            elif kind == "mission":
                require_keys(condition, {"type", "missionId", "minCount"}, loc, optional={"withinDays"})
                if condition["missionId"] not in MISSIONS or not whole_number(condition["minCount"], 1, 1000000):
                    raise ValueError(f"Invalid mission count: {loc}")
                if "withinDays" in condition and not whole_number(condition["withinDays"], 1, 1):
                    raise ValueError(f"Recent mission must be same-day only: {loc}")
            elif kind == "kotohogi":
                require_keys(condition, {"type", "min"}, loc)
                if not whole_number(condition["min"], 0, 10000000):
                    raise ValueError(f"Invalid kotohogi: {loc}")
            elif kind == "date":
                mode = condition.get("mode")
                if mode == "exact":
                    require_keys(condition, {"type", "mode", "date"}, loc)
                    date_full(condition["date"])
                elif mode == "range":
                    require_keys(condition, {"type", "mode", "start", "end"}, loc)
                    date_full(condition["start"])
                    date_full(condition["end"])
                    if condition["start"] > condition["end"]:
                        raise ValueError(f"Reversed range: {loc}")
                elif mode == "annual":
                    require_keys(condition, {"type", "mode", "date"}, loc)
                    month_day(condition["date"])
                elif mode == "annual_range":
                    require_keys(condition, {"type", "mode", "start", "end"}, loc)
                    month_day(condition["start"])
                    month_day(condition["end"])
                elif mode == "weekday":
                    require_keys(condition, {"type", "mode", "days"}, loc)
                    days = condition["days"]
                    if not isinstance(days, list) or not days or len(set(map(str, days))) != len(days) or not all(whole_number(d, 1, 7) for d in days):
                        raise ValueError(f"Invalid weekdays: {loc}")
                else:
                    raise ValueError(f"Invalid date mode: {loc}")
            else:
                raise ValueError(f"Unknown condition type: {loc}")
        if "reply" in entry:
            reply = entry["reply"]
            require_keys(reply, {"residentId", "text"}, f"{identifier}.reply")
            other = reply["residentId"]
            if (other not in residents or
                    not isinstance(reply["text"], str) or
                    not reply["text"].strip() or len(reply["text"]) > 500 or
                    entry["logic"] != "all" or
                    not any(c["type"] == "townTogether" and
                            c["otherResidentId"] == other for c in conditions)):
                raise ValueError(f"Reply requires matching AND town companion: {identifier}")
    for entry in rows:
        for condition in entry["conditions"]:
            if condition["type"] == "seenDialogue":
                prerequisite = condition["dialogueId"]
                if prerequisite not in ids or prerequisite == entry["id"]:
                    raise ValueError(
                        f"Invalid prerequisite dialogue for {entry['id']}: {prerequisite}")
    if defaults != residents:
        raise ValueError(f"Every resident needs an unconditional non-once dialogue. Missing: {sorted(residents - defaults)}")
    return doc


def write_document(doc):
    validate(doc)
    # New IDs must also reserve their sequence in the character catalog.
    # The CMS uses /api/cms for that atomic multi-file update.
    if DATA.exists():
        previous = json.loads(DATA.read_text(encoding="utf-8"))
        validate(previous)
        previous_by_id = {entry["id"]: entry["residentId"] for entry in previous["dialogues"]}
        for entry in doc["dialogues"]:
            old_resident = previous_by_id.get(entry["id"])
            if old_resident is None:
                raise ValueError("Use /api/cms to add dialogues and reserve IDs")
            if old_resident != entry["residentId"]:
                raise ValueError(f"Existing dialogue resident cannot change: {entry['id']}")
    DATA.parent.mkdir(parents=True, exist_ok=True)
    # Atomic overwrite after validation, never truncate the prior good file.
    payload = json.dumps(doc, ensure_ascii=False, indent=2) + "\n"
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=DATA.parent,
                                     prefix=".dialogues-", suffix=".tmp",
                                     delete=False) as tmp:
        name = tmp.name
        try:
            tmp.write(payload)
            tmp.flush()
            os.fsync(tmp.fileno())
        except BaseException:
            os.unlink(name)
            raise
    try:
        os.replace(name, DATA)
    finally:
        if os.path.exists(name):
            os.unlink(name)


class Handler(BaseHTTPRequestHandler):
    def _headers(self, code, mime="application/json; charset=utf-8", size=0):
        self.send_response(code)
        self.send_header("Content-Type", mime)
        self.send_header("Content-Length", str(size))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "DENY")
        self.end_headers()

    def _send(self, code, value):
        content = json.dumps(value, ensure_ascii=False).encode("utf-8")
        self._headers(code, size=len(content))
        self.wfile.write(content)

    def do_GET(self):
        url = urlsplit(self.path)
        path = url.path
        if path == "/":
            raw = INDEX.read_bytes()
            self._headers(200, "text/html; charset=utf-8", len(raw))
            self.wfile.write(raw)
        elif path in {"/facilities", "/facilities.js", "/api/facilities", "/api/facility-background"}:
            try:
                if path == "/api/facilities":
                    return self._send(200, facilities.load())
                if path == "/api/facility-background":
                    args = parse_qs(url.query, strict_parsing=True, max_num_fields=1)
                    if set(args) != {"id"} or len(args["id"]) != 1 or args["id"][0] not in facilities.FIXED:
                        raise ValueError("Unknown facility")
                    file = ROOT / facilities.FIXED[args["id"][0]]["background"]
                    mime = "image/png" if file.suffix == ".png" else "image/jpeg"
                else:
                    file = Path(__file__).parent / ("facilities.html" if path == "/facilities" else "facilities.js")
                    mime = "text/html; charset=utf-8" if path == "/facilities" else "text/javascript; charset=utf-8"
                raw = file.read_bytes()
                self._headers(200, mime, len(raw))
                self.wfile.write(raw)
            except (OSError, ValueError, TypeError) as exc:
                self._send(400, {"error": str(exc)})
        elif path in {"/events", "/events.js", "/api/events", "/api/event-background"}:
            try:
                if path == "/api/events":
                    return self._send(200, events.load())
                if path == "/api/event-background":
                    file = ROOT / events.load()["background"]
                    mime = "image/jpeg"
                else:
                    file = Path(__file__).parent / ("events.html" if path == "/events" else "events.js")
                    mime = "text/html; charset=utf-8" if path == "/events" else "text/javascript; charset=utf-8"
                raw = file.read_bytes()
                self._headers(200, mime, len(raw))
                self.wfile.write(raw)
            except (OSError, ValueError, TypeError) as exc:
                self._send(400, {"error": str(exc)})
        elif path == "/api/portrait":
            try:
                args = parse_qs(url.query, strict_parsing=True,
                                keep_blank_values=True, max_num_fields=1)
                if set(args) != {"folder"} or len(args["folder"]) != 1:
                    raise ValueError("Exactly one portrait folder is required")
                image = portrait_path(args["folder"][0])
                raw = image.read_bytes()
                if not raw.startswith(b"\x89PNG\r\n\x1a\n"):
                    raise OSError(f"Not a valid PNG: {image}")
                self._headers(200, "image/png", len(raw))
                self.wfile.write(raw)
            except ValueError as exc:
                self._send(400, {"error": str(exc)})
            except FileNotFoundError as exc:
                self._send(404, {"error": str(exc)})
            except OSError as exc:
                self._send(500, {"error": str(exc)})
        elif path == "/api/runtime/catalog":
            if url.query:
                self._send(400, {"error": "Runtime catalog takes no query parameters"})
                return
            try:
                self._send(200, runtime_catalog())
            except (OSError, ValueError, TypeError) as exc:
                self._send(500, {"error": str(exc)})
        elif path.startswith("/api/runtime/sprites/"):
            try:
                if url.query:
                    raise ValueError("Runtime sprites take no query parameters")
                segments = path.removeprefix("/api/runtime/sprites/").split("/")
                if len(segments) != 2:
                    raise ValueError("Runtime sprite requires folder and filename")
                image = runtime_sprite_path(*segments)
                raw = image.read_bytes()
                if not raw.startswith(b"\x89PNG\r\n\x1a\n"):
                    raise OSError(f"Invalid PNG file: {image}")
                self._headers(200, "image/png", len(raw))
                self.wfile.write(raw)
            except ValueError as exc:
                self._send(400, {"error": str(exc)})
            except FileNotFoundError as exc:
                self._send(404, {"error": str(exc)})
            except OSError as exc:
                self._send(500, {"error": str(exc)})
        elif path == "/api/characters":
            try:
                document = validate_catalog(load_catalog())
                self._send(200, document)
            except (OSError, ValueError, TypeError) as exc:
                self._send(500, {"error": str(exc)})
        elif path == "/api/character-archive-blockers":
            if url.query:
                return self._send(400, {"error": "Archive blockers take no query parameters"})
            try:
                catalog = validate_catalog(load_catalog())
                self._send(200, {"blockers": archive_code_blockers(catalog)})
            except (OSError, ValueError, TypeError) as exc:
                self._send(500, {"error": str(exc)})
        elif path == "/api/areas":
            if url.query:
                return self._send(400, {"error": "Areas endpoint takes no query parameters"})
            try:
                self._send(200, validate_areas(load_areas()))
            except (OSError, ValueError, TypeError) as exc:
                self._send(500, {"error": str(exc)})
        elif path == "/api/area-background":
            try:
                args = parse_qs(url.query, strict_parsing=True,
                                keep_blank_values=True, max_num_fields=1)
                if set(args) != {"id"} or len(args["id"]) != 1:
                    raise ValueError("Exactly one area ID is required")
                areas = validate_areas(load_areas())["areas"]
                selected = next((area for area in areas if area["id"] == args["id"][0]), None)
                if selected is None:
                    raise ValueError("Unknown town area")
                background = (ROOT / selected["backgroundAsset"]).resolve()
                if not background.is_relative_to(ROOT.resolve()):
                    raise ValueError("Background path escapes the repository")
                raw = background.read_bytes()
                mime = "image/png" if background.suffix.lower() == ".png" else "image/jpeg"
                self._headers(200, mime, len(raw))
                self.wfile.write(raw)
            except ValueError as exc:
                self._send(400, {"error": str(exc)})
            except OSError as exc:
                self._send(500, {"error": str(exc)})
        elif path == "/api/dialogues":
            try:
                document = json.loads(DATA.read_text(encoding="utf-8"))
                validate(document)
                self._send(200, document)
            except (OSError, ValueError, TypeError) as exc:
                self._send(500, {"error": str(exc)})
        else:
            self._send(404, {"error": "Not found"})

    def do_PUT(self):
        endpoint = urlsplit(self.path).path
        if endpoint not in {"/api/dialogues", "/api/cms", "/api/events", "/api/facilities"}:
            return self._send(404, {"error": "Not found"})
        # A cross-origin website must not be able to modify local files.
        expected = f"http://127.0.0.1:{self.server.server_port}"
        if self.headers.get("Origin") != expected:
            return self._send(403, {"error": "Same-origin editor only"})
        if self.headers.get("Content-Type", "").split(";")[0] != "application/json":
            return self._send(415, {"error": "JSON required"})
        try:
            size = int(self.headers.get("Content-Length", "-1"))
            if not 0 < size <= 1024 * 1024:
                return self._send(413, {"error": "Invalid document size"})
            raw = self.rfile.read(size)
            value = json.loads(raw.decode("utf-8"))
            if endpoint == "/api/facilities":
                facilities.save(value)
                self._send(200, {"ok": True})
            elif endpoint == "/api/events":
                events.save(value)
                self._send(200, {"ok": True})
            elif endpoint == "/api/cms":
                result = save_catalog_and_dialogues(value, validate)
                self._send(200, result)
            else:
                write_document(value)
                self._send(200, {"ok": True, "count": len(value["dialogues"])})
        except (ValueError, TypeError, UnicodeDecodeError) as exc:
            self._send(400, {"error": str(exc)})
        except OSError as exc:
            self._send(500, {"error": str(exc)})

    def do_POST(self):
        if self.path != "/api/event-preview":
            return self._send(405, {"error": "Method not allowed"})
        if self.headers.get("Origin") != f"http://127.0.0.1:{self.server.server_port}":
            return self._send(403, {"error": "Same-origin editor only"})
        try:
            size = int(self.headers.get("Content-Length", "-1"))
            if not 0 < size <= 1024 * 1024: raise ValueError("Invalid document size")
            result = events.preview(json.loads(self.rfile.read(size).decode("utf-8")))
            self._send(200, result)
        except (ValueError, TypeError, KeyError, OverflowError) as exc:
            self._send(400, {"error": str(exc)})


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Kotohogu local dialogue CMS")
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    if not 1 <= args.port <= 65535:
        parser.error("Invalid port")
    if not INDEX.exists() or not DATA.exists() or not AREA_DATA.exists() or not (ROOT / "assets/characters/characters.json").exists():
        raise SystemExit("CMS HTML or dialogues.json not found")
    with ThreadingHTTPServer(("127.0.0.1", args.port), Handler) as server:
        print(f"Open http://127.0.0.1:{args.port} (Ctrl+C to stop)", flush=True)
        server.serve_forever()
