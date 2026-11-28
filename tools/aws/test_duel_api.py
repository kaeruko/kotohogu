import copy
import json
from pathlib import Path
import re
import unittest

from deploy_duel import render
from duel_api import ApiError, DuelApi, PUZZLE, SOLUTION, dispatch, room_of


class MemoryStore:
    def __init__(self):
        self.rooms = {}

    def create(self, room):
        if room["code"] in self.rooms:
            raise ApiError(409, "room_code_collision")
        self.rooms[room["code"]] = copy.deepcopy(room)

    def get(self, code):
        return copy.deepcopy(self.rooms.get(code))

    def replace(self, room, revision, generation, now):
        old = self.rooms[room["code"]]
        if old["revision"] != revision or old["generation"] != generation or old["expiresAt"] <= now:
            raise ApiError(409, "stale_revision")
        self.rooms[room["code"]] = copy.deepcopy(room)


class DuelTests(unittest.TestCase):
    def setUp(self):
        self.store = MemoryStore()
        self.now = 1000
        self.api = DuelApi(self.store, lambda: self.now,
                           lambda: "ABCD2345", lambda: "first")
        self.first = "a" * 64
        self.second = "b" * 64
        self.third = "c" * 64
        self.path = "/v1/rooms/ABCD2345"

    def call(self, token, action=None, data=None):
        return self.api.handle("GET" if action is None else "POST",
                               self.path + ("/" + action if action else ""),
                               token, {} if data is None else data)[1]

    def create(self):
        return self.api.handle("POST", "/v1/rooms", self.first, {})[1]

    def start(self, bonus=3):
        self.create()
        self.call(self.second, "join")
        return self.call(self.second, "bonus", {"revision": 1, "room": bonus})

    def error(self, code, fn):
        with self.assertRaises(ApiError) as caught:
            fn()
        self.assertEqual(caught.exception.code, code)

    def test_members_and_bonus_permissions(self):
        created = self.create()
        self.assertEqual(created["status"], "waiting")
        self.error("room_code_collision", self.create)
        self.error("not_a_member", lambda: self.call(self.third))
        joined = self.call(self.second, "join")
        self.assertEqual(joined["yourSide"], "second")
        self.assertEqual(joined, self.call(self.second, "join"))
        self.error("room_full", lambda: self.call(self.third, "join"))
        self.error("cannot_choose_bonus", lambda: self.call(
            self.first, "bonus", {"revision": 1, "room": 3}))
        self.error("invalid_room", lambda: self.call(
            self.second, "bonus", {"revision": 1, "room": True}))
        started = self.call(self.second, "bonus", {"revision": 1, "room": 3})
        self.assertEqual(started["turn"], "first")
        self.assertEqual(started["revision"], 2)
        self.assertNotIn("players", started)
        self.assertNotIn("solution", started)
        self.assertNotIn(self.first, json.dumps(started))
        self.assertNotIn(self.second, json.dumps(started))

    def test_host_can_be_second(self):
        self.api.side_factory = lambda: "second"
        self.assertEqual(self.create()["yourSide"], "second")
        self.assertEqual(self.call(self.second, "join")["yourSide"], "first")
        self.assertEqual(self.call(self.first, "bonus", {"revision": 1, "room": 2})["turn"], "first")

    def test_invalid_moves_and_stale_revision_do_not_write(self):
        start = self.start()
        self.error("not_your_turn", lambda: self.call(
            self.second, "move", {"revision": 2, "cell": 1, "digit": 2}))
        self.error("wrong_digit", lambda: self.call(
            self.first, "move", {"revision": 2, "cell": 1, "digit": 1}))
        self.error("illegal_cell", lambda: self.call(
            self.first, "move", {"revision": 2, "cell": 2, "digit": 3}))
        self.error("invalid_cell", lambda: self.call(
            self.first, "move", {"revision": 2, "cell": 16, "digit": 2}))
        self.assertEqual(self.call(self.second), start)
        move = self.call(self.first, "move", {"revision": 2, "cell": 1, "digit": 2})
        self.assertEqual(move["targetRoom"], 2)
        self.assertEqual(move["turn"], "second")
        self.error("stale_revision", lambda: self.call(
            self.second, "move", {"revision": 2, "cell": 2, "digit": 3}))

    def test_all_legal_paths_match_flag_and_send_rules(self):
        for bonus in range(1, 5):
            with self.subTest(bonus=bonus):
                self.setUp()
                self.start(bonus)
                winners = set()

                def visit():
                    before = copy.deepcopy(self.store.rooms["ABCD2345"])
                    current = self.call(self.first)
                    if current["status"] == "finished":
                        winners.add(current["winner"])
                        self.assertGreaterEqual(current["scores"][current["winner"]], 3)
                        self.assertLess(current["scores"]["second" if current["winner"] == "first" else "first"], 3)
                        self.assertIsNone(current["turn"])
                        return
                    side = current["turn"]
                    token = self.first if side == "first" else self.second
                    legal = [i for i, v in enumerate(current["board"]) if v == "0"
                             and (current["targetRoom"] is None or room_of(i) == current["targetRoom"])]
                    self.assertTrue(legal)
                    for cell in legal:
                        digit = int(SOLUTION[cell])
                        moved = self.call(token, "move", {"revision": current["revision"], "cell": cell, "digit": digit})
                        expected = current["board"][:cell] + str(digit) + current["board"][cell+1:]
                        self.assertEqual(moved["board"], expected)
                        flags = current["flags"][:]
                        if not any(v == "0" and room_of(i) == room_of(cell) for i, v in enumerate(expected)):
                            flags[room_of(cell)-1] = side
                        self.assertEqual(moved["flags"], flags)
                        score = sum(2 if i+1 == bonus else 1 for i, f in enumerate(flags) if f == side)
                        self.assertEqual(moved["scores"][side], score)
                        self.assertEqual(moved["status"], "finished" if score >= 3 else "playing")
                        if score < 3:
                            target = digit if any(v == "0" and room_of(i) == digit for i, v in enumerate(expected)) else None
                            self.assertEqual(moved["targetRoom"], target)
                            self.assertEqual(moved["turn"], "second" if side == "first" else "first")
                        visit()
                        self.store.rooms["ABCD2345"] = copy.deepcopy(before)

                visit()
                self.assertEqual(winners, {"first", "second"})

    def test_resign_and_expiry(self):
        self.start()
        result = self.call(self.first, "resign", {"revision": 2})
        self.assertEqual(result["winner"], "second")
        self.assertEqual(result["finishReason"], "resigned")
        self.error("not_your_turn", lambda: self.call(
            self.second, "move", {"revision": 3, "cell": 1, "digit": 2}))
        self.now = result["expiresAt"]
        self.error("room_not_found", lambda: self.call(self.first))

    def test_store_compare_and_swap(self):
        self.start()
        old = self.store.get("ABCD2345")
        self.call(self.first, "move", {"revision": 2, "cell": 1, "digit": 2})
        self.error("stale_revision", lambda: self.store.replace(
            old, 2, old["generation"], self.now))

    def test_http_contract_and_template(self):
        event = {"requestContext": {"http": {"method": "POST"}},
                 "rawPath": "/v1/rooms", "headers": {"authorization": "Bearer " + self.first},
                 "body": "{}"}
        result = dispatch(event, self.api)
        self.assertEqual(result["statusCode"], 201)
        self.assertEqual(result["headers"]["cache-control"], "no-store")
        self.assertEqual(dispatch({**event, "body": "{"}, self.api)["statusCode"], 400)
        self.assertEqual(dispatch({**event, "headers": {}}, self.api)["statusCode"], 401)
        template = json.loads(render())
        self.assertIn("def handler(", template["Resources"]["Function"]["Properties"]["Code"]["ZipFile"])
        dart = (Path(__file__).resolve().parents[2] / "lib/sudoku_duel.dart").read_text(encoding="utf-8")
        human = dart.split("factory SudokuDuel.humanMini", 1)[1].split("factory SudokuDuel._startBoard", 1)[0]
        self.assertEqual(re.search(r"const puzzle = '([0-9]+)'", human)[1], PUZZLE)
        self.assertEqual(re.search(r"const solution = '([0-9]+)'", human)[1], SOLUTION)


if __name__ == "__main__":
    unittest.main()
