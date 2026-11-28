import 'dart:convert';
import 'dart:io';
import 'dart:math';

const duelEndpoint = 'https://dxopo67sm9.execute-api.ap-northeast-1.amazonaws.com';
final duelCodePattern = RegExp(r'^[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{8}$');
final duelTokenPattern = RegExp(r'^[0-9a-f]{64}$');

String newDuelToken() {
  final random = Random.secure();
  return List.generate(32, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

class DuelApiException implements Exception {
  const DuelApiException(this.status, this.code);
  final int status;
  final String code;
  @override
  String toString() => 'HTTP $status: $code';
}

class OnlineDuelState {
  OnlineDuelState.fromJson(Map<String, dynamic> json)
      : code = json['code'] as String,
        status = json['status'] as String,
        revision = json['revision'] as int,
        expiresAt = json['expiresAt'] as int,
        board = json['board'] as String,
        givens = json['givens'] as String,
        yourSide = json['yourSide'] as String,
        playerCount = json['playerCount'] as int,
        bonusRoom = json['bonusRoom'] as int?,
        targetRoom = json['targetRoom'] as int?,
        turn = json['turn'] as String?,
        winner = json['winner'] as String?,
        finishReason = json['finishReason'] as String?,
        flags = List<String?>.unmodifiable((json['flags'] as List).cast<String?>()),
        scores = Map<String, int>.unmodifiable((json['scores'] as Map).cast<String, int>()) {
    const sides = {'first', 'second'};
    if (json['rules'] != 'human-mini-v1' ||
        !duelCodePattern.hasMatch(code) ||
        !{'waiting', 'choosing_bonus', 'playing', 'finished'}.contains(status) ||
        !sides.contains(yourSide) || revision < 0 || expiresAt <= 0 ||
        playerCount < 1 || playerCount > 2 ||
        !RegExp(r'^[0-4]{16}$').hasMatch(board) ||
        !RegExp(r'^[0-4]{16}$').hasMatch(givens) ||
        flags.length != 4 || flags.any((f) => f != null && !sides.contains(f)) ||
        scores.length != 2 || !sides.every(scores.containsKey) ||
        scores.values.any((s) => s < 0 || s > 5) ||
        (bonusRoom != null && (bonusRoom! < 1 || bonusRoom! > 4)) ||
        (targetRoom != null && (targetRoom! < 1 || targetRoom! > 4)) ||
        (status == 'playing' && (!sides.contains(turn) || bonusRoom == null)) ||
        (status != 'playing' && (turn != null || targetRoom != null)) ||
        (status == 'finished' && (!sides.contains(winner) ||
            !{'flags', 'resigned'}.contains(finishReason))) ||
        (status != 'finished' && (winner != null || finishReason != null))) {
      throw const FormatException('Invalid online duel state');
    }
    for (var i = 0; i < 16; i++) {
      if (givens[i] != '0' && givens[i] != board[i]) {
        throw const FormatException('Online duel givens changed');
      }
    }
  }

  final String code, status, board, givens, yourSide;
  final int revision, expiresAt, playerCount;
  final int? bonusRoom, targetRoom;
  final String? turn, winner, finishReason;
  final List<String?> flags;
  final Map<String, int> scores;

  bool get myTurn => status == 'playing' && turn == yourSide;
  static int roomOf(int cell) => cell ~/ 8 * 2 + cell % 4 ~/ 2 + 1;
  bool canPlay(int cell) => myTurn && cell >= 0 && cell < 16 &&
      board[cell] == '0' && (targetRoom == null || roomOf(cell) == targetRoom);
}

typedef DuelTransport = Future<Map<String, dynamic>> Function(
    String method, String path, String token, Map<String, Object>? body);

class OnlineDuelApi {
  OnlineDuelApi({DuelTransport? transport}) : _transport = transport ?? _request;
  final DuelTransport _transport;

  Future<OnlineDuelState> _send(String method, String path, String token,
      Map<String, Object>? body, {String? code}) async {
    if (!duelTokenPattern.hasMatch(token)) throw const FormatException('Invalid duel token');
    if (code != null && !duelCodePattern.hasMatch(code)) {
      throw const FormatException('Invalid room code');
    }
    final state = OnlineDuelState.fromJson(await _transport(method, path, token, body));
    if (code != null && state.code != code) {
      throw const FormatException('Response room does not match request');
    }
    return state;
  }

  Future<OnlineDuelState> create(String token) =>
      _send('POST', '/v1/rooms', token, {});
  Future<OnlineDuelState> join(String code, String token) =>
      _send('POST', '/v1/rooms/$code/join', token, {}, code: code);
  Future<OnlineDuelState> get(String code, String token) =>
      _send('GET', '/v1/rooms/$code', token, null, code: code);
  Future<OnlineDuelState> bonus(OnlineDuelState state, String token, int room) =>
      _send('POST', '/v1/rooms/${state.code}/bonus', token,
          {'revision': state.revision, 'room': room}, code: state.code);
  Future<OnlineDuelState> move(OnlineDuelState state, String token, int cell, int digit) =>
      _send('POST', '/v1/rooms/${state.code}/move', token,
          {'revision': state.revision, 'cell': cell, 'digit': digit}, code: state.code);
  Future<OnlineDuelState> resign(OnlineDuelState state, String token) =>
      _send('POST', '/v1/rooms/${state.code}/resign', token,
          {'revision': state.revision}, code: state.code);

  static Future<Map<String, dynamic>> _request(String method, String path,
      String token, Map<String, Object>? body) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final uri = Uri.parse(duelEndpoint).resolve(path);
      final request = await client.openUrl(method, uri).timeout(const Duration(seconds: 12));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close().timeout(const Duration(seconds: 15));
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 12))) {
        if (bytes.length + chunk.length > 16384) {
          throw const FormatException('Duel response too large');
        }
        bytes.addAll(chunk);
      }
      final expected = path == '/v1/rooms' ? 201 : 200;
      if (response.headers.contentType?.mimeType != 'application/json') {
        throw DuelApiException(response.statusCode, 'unexpected_content_type');
      }
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      if (response.statusCode != expected) {
        throw DuelApiException(response.statusCode, json['error'] as String? ?? 'unexpected_response');
      }
      return json;
    } finally {
      client.close(force: true);
    }
  }
}
