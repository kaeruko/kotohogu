import 'package:flutter_test/flutter_test.dart';
import 'package:future_lift/online_duel_api.dart';

Map<String, dynamic> snapshot({
  String code = 'ABCD2345',
  String rules = 'human-mini-v1',
  String board = '1004301020034020',
}) => {
  'code': code, 'rules': rules, 'status': 'playing',
  'revision': 2, 'expiresAt': 1795929178,
  'board': board, 'givens': '1004301020034020',
  'yourSide': 'first', 'playerCount': 2,
  'bonusRoom': 3, 'targetRoom': 1, 'turn': 'first',
  'winner': null, 'finishReason': null,
  'flags': [null, null, null, null],
  'scores': {'first': 0, 'second': 0},
};

void main() {
  test('validate state and available cells from server, not local answer', () {
    final state = OnlineDuelState.fromJson(snapshot());
    expect(state.myTurn, isTrue);
    expect([for (var i = 0; i < 16; i++) if (state.canPlay(i)) i], [1, 5]);
    expect(() => OnlineDuelState.fromJson(snapshot(rules: 'unknown')), throwsFormatException);
    expect(() => OnlineDuelState.fromJson(snapshot(board: '2004301020034020')), throwsFormatException);
    expect(duelTokenPattern.hasMatch(newDuelToken()), isTrue);
  });

  test('send only move, revision and token, propagate failures without retry', () async {
    var calls = 0;
    final token = List.filled(64, 'a').join();
    final api = OnlineDuelApi(transport: (method, path, auth, body) async {
      calls++;
      expect(method, 'POST');
      expect(path, '/v1/rooms/ABCD2345/move');
      expect(auth, token);
      expect(body, {'revision': 2, 'cell': 1, 'digit': 2});
      throw const DuelApiException(409, 'stale_revision');
    });
    await expectLater(api.move(OnlineDuelState.fromJson(snapshot()), token, 1, 2),
        throwsA(isA<DuelApiException>()));
    expect(calls, 1);
  });

  test('do not accept a different room or invalid code', () async {
    var calls = 0;
    final api = OnlineDuelApi(transport: (method, path, auth, body) async {
      calls++;
      return snapshot(code: 'ABCD2346');
    });
    final token = List.filled(64, 'a').join();
    await expectLater(api.get('ABCD2345', token), throwsFormatException);
    await expectLater(api.get('invalid', token), throwsFormatException);
    expect(calls, 1);
  });
}
