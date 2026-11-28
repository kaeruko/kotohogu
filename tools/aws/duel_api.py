"""Kotohoguru invitation-only 4x4 duel HTTP API (Lambda proxy v2)."""
import hashlib
import hmac
import json
import os
import re
import secrets
import time

PUZZLE = "1004301020034020"
SOLUTION = "1234341221434321"
RULES = "human-mini-v1"
ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"
ROOM_CODE = re.compile(r"[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{8}")
TOKEN = re.compile(r"[0-9a-f]{64}")
TTL_SECONDS = 86400


class ApiError(Exception):
    def __init__(self, status, code):
        super().__init__(code)
        self.status = status
        self.code = code


def room_of(cell):
    return (cell // 8) * 2 + (cell % 4) // 2 + 1


def has_space(board, room):
    return any(digit == "0" and room_of(i) == room
               for i, digit in enumerate(board))


def scores(room):
    return {side: sum(2 if i + 1 == room["bonusRoom"] else 1
                      for i, owner in enumerate(room["flags"]) if owner == side)
            for side in ("first", "second")}


def other(side):
    return "second" if side == "first" else "first"


def member(room, digest):
    for side in ("first", "second"):
        value = room["players"].get(side)
        if value is not None and hmac.compare_digest(value, digest):
            return side
    raise ApiError(403, "not_a_member")


def public(room, side):
    # Explicit allowlist: never serialize credentials or the solution.
    return {**{key: room[key] for key in (
        "code", "rules", "status", "revision", "expiresAt", "board",
        "bonusRoom", "flags", "turn", "targetRoom", "lastCell",
        "winner", "finishReason")},
        "givens": PUZZLE, "yourSide": side,
        "playerCount": len(room["players"]), "scores": scores(room)}


def fields(data, expected):
    if type(data) is not dict or set(data) != set(expected):
        raise ApiError(400, "invalid_fields")


def integer(data, key, low, high):
    value = data[key]
    if type(value) is not int or not low <= value <= high:
        raise ApiError(400, "invalid_" + key)
    return value


class DuelApi:
    def __init__(self, store, clock=time.time, code_factory=None, side_factory=None):
        self.store = store
        self.clock = clock
        self.code_factory = code_factory or (
            lambda: "".join(secrets.choice(ALPHABET) for _ in range(8)))
        self.side_factory = side_factory or (
            lambda: secrets.choice(("first", "second")))

    def handle(self, method, path, token, data):
        if not isinstance(token, str) or not TOKEN.fullmatch(token):
            raise ApiError(401, "invalid_token")
        digest = hashlib.sha256(token.encode("ascii")).hexdigest()
        now = int(self.clock())
        if method == "POST" and path == "/v1/rooms":
            fields(data, ())
            code = self.code_factory()
            side = self.side_factory()
            room = {
                "code": code, "generation": secrets.token_hex(16),
                "rules": RULES, "status": "waiting", "revision": 0,
                "expiresAt": now + TTL_SECONDS,
                "players": {side: digest}, "board": PUZZLE,
                "bonusRoom": None, "flags": [None] * 4, "turn": None,
                "targetRoom": None, "lastCell": None, "winner": None,
                "finishReason": None,
            }
            self.store.create(room)
            return 201, public(room, side)

        match = re.fullmatch(r"/v1/rooms/([^/]+)(?:/(join|bonus|move|resign))?", path)
        if not match or not ROOM_CODE.fullmatch(match[1]):
            raise ApiError(404, "route_not_found")
        code, action = match.groups()
        if (method, action) not in {
            ("GET", None), ("POST", "join"), ("POST", "bonus"),
            ("POST", "move"), ("POST", "resign"),
        }:
            raise ApiError(404, "route_not_found")
        room = self.store.get(code)
        if room is None or room["expiresAt"] <= now:
            raise ApiError(404, "room_not_found")
        if room["rules"] != RULES:
            raise RuntimeError("Unsupported stored rules version")
        revision = room["revision"]
        generation = room["generation"]

        if action == "join":
            fields(data, ())
            for side, value in room["players"].items():
                if hmac.compare_digest(value, digest):
                    return 200, public(room, side)
            if room["status"] != "waiting":
                raise ApiError(409, "room_full")
            side = other(next(iter(room["players"])))
            room["players"][side] = digest
            room["status"] = "choosing_bonus"
        else:
            side = member(room, digest)
            if action is None:
                fields(data, ())
                return 200, public(room, side)
            expected = {
                "bonus": ("revision", "room"),
                "move": ("revision", "cell", "digit"),
                "resign": ("revision",),
            }[action]
            fields(data, expected)
            requested = integer(data, "revision", 0, 1000000)
            if requested != revision:
                raise ApiError(409, "stale_revision")
            if action == "bonus":
                if room["status"] != "choosing_bonus" or side != "second":
                    raise ApiError(409, "cannot_choose_bonus")
                room["bonusRoom"] = integer(data, "room", 1, 4)
                room["status"] = "playing"
                room["turn"] = "first"
                room["targetRoom"] = 1
            elif action == "move":
                if room["status"] != "playing" or room["turn"] != side:
                    raise ApiError(409, "not_your_turn")
                cell = integer(data, "cell", 0, 15)
                digit = integer(data, "digit", 1, 4)
                target = room["targetRoom"]
                if room["board"][cell] != "0" or (
                    target is not None and room_of(cell) != target
                ):
                    raise ApiError(422, "illegal_cell")
                if SOLUTION[cell] != str(digit):
                    raise ApiError(422, "wrong_digit")
                board = room["board"]
                room["board"] = board[:cell] + str(digit) + board[cell + 1:]
                room["lastCell"] = cell
                captured = room_of(cell)
                if not has_space(room["board"], captured):
                    room["flags"][captured - 1] = side
                if scores(room)[side] >= 3:
                    room["status"] = "finished"
                    room["winner"] = side
                    room["finishReason"] = "flags"
                    room["turn"] = room["targetRoom"] = None
                else:
                    room["turn"] = other(side)
                    room["targetRoom"] = digit if has_space(room["board"], digit) else None
            else:
                if room["status"] not in ("choosing_bonus", "playing"):
                    raise ApiError(409, "cannot_resign")
                room["status"] = "finished"
                room["winner"] = other(side)
                room["finishReason"] = "resigned"
                room["turn"] = room["targetRoom"] = None

        room["revision"] = revision + 1
        self.store.replace(room, revision, generation, now)
        return 200, public(room, side)


def json_value(value):
    # DynamoDB resource deserializes all numbers to Decimal. Our schema uses
    # only integers; reject non-integer or unknown stored types.
    from decimal import Decimal
    if isinstance(value, Decimal):
        if value != value.to_integral_value():
            raise ValueError("Non-integer number in stored duel")
        return int(value)
    if isinstance(value, list):
        return [json_value(item) for item in value]
    if isinstance(value, dict):
        return {key: json_value(item) for key, item in value.items()}
    if value is None or type(value) in (str, int, bool):
        return value
    raise TypeError("Unexpected DynamoDB duel value: " + type(value).__name__)


class DynamoStore:
    def __init__(self, table):
        self.table = table

    def create(self, room):
        try:
            self.table.put_item(Item=room, ConditionExpression="attribute_not_exists(code)")
        except self.table.meta.client.exceptions.ConditionalCheckFailedException as exc:
            raise ApiError(409, "room_code_collision") from exc

    def get(self, code):
        result = self.table.get_item(Key={"code": code}, ConsistentRead=True)
        return json_value(result["Item"]) if "Item" in result else None

    def replace(self, room, revision, generation, now):
        try:
            self.table.put_item(
                Item=room,
                ConditionExpression="revision = :r AND generation = :g AND expiresAt > :now",
                ExpressionAttributeValues={":r": revision, ":g": generation, ":now": now},
            )
        except self.table.meta.client.exceptions.ConditionalCheckFailedException as exc:
            raise ApiError(409, "stale_revision") from exc


def response(status, payload):
    return {"statusCode": status,
            "headers": {"content-type": "application/json", "cache-control": "no-store"},
            "body": json.dumps(payload, separators=(",", ":"))}


def dispatch(event, api):
    try:
        method = event["requestContext"]["http"]["method"]
        path = event["rawPath"]
        authorization = (event.get("headers") or {}).get("authorization", "")
        token = authorization[7:] if authorization.startswith("Bearer ") else None
        raw = event.get("body")
        if event.get("isBase64Encoded") or (
            raw is not None and (not isinstance(raw, str) or len(raw.encode("utf-8")) > 2048)
        ):
            raise ApiError(400, "invalid_body")
        if method == "GET":
            if raw:
                raise ApiError(400, "invalid_body")
            data = {}
        else:
            if not raw:
                raise ApiError(400, "invalid_body")
            try:
                data = json.loads(raw)
            except json.JSONDecodeError as exc:
                raise ApiError(400, "invalid_json") from exc
        status, payload = api.handle(method, path, token, data)
        return response(status, payload)
    except ApiError as exc:
        return response(exc.status, {"error": exc.code})
    # Unexpected errors propagate to Lambda with their original traceback.
    # Never log the request or its bearer token.


def handler(event, context):
    import boto3
    table = boto3.resource("dynamodb").Table(os.environ["DUEL_TABLE"])
    return dispatch(event, DuelApi(DynamoStore(table)))
