import 'dart:math';

import 'story_duel_stage.dart';

enum DuelSize {
  mini(2, 2, '1034301001434000', '1234341221434321'),
  six(
    2,
    3,
    '023450450123204560560234340610012345',
    '123456456123234561561234345612612345',
  ),
  classic(
    3,
    3,
    '000670012'
        '672095308'
        '108002007'
        '050061020'
        '420053790'
        '710004850'
        '960007204'
        '200019630'
        '045280100',
    '534678912'
        '672195348'
        '198342567'
        '859761423'
        '426853791'
        '713924856'
        '961537284'
        '287419635'
        '345286179',
  );

  const DuelSize(this.boxRows, this.boxColumns, this._givens, this._answer);
  final int boxRows;
  final int boxColumns;
  final String _givens;
  final String _answer;
  int get side => boxRows * boxColumns;

  // Rooms are numbered from 1, exactly like the digits that send a player.
  int roomOf(int cell) =>
      (cell ~/ side ~/ boxRows) * (side ~/ boxColumns) +
      (cell % side ~/ boxColumns) +
      1;
}

enum DuelPlayer {
  first,
  second;

  DuelPlayer get other => this == first ? second : first;
}

enum DuelRival { mosaedo, oshisho, pomupomu, patissier }

class SudokuDuel {
  SudokuDuel._(
    this.size,
    this._givens,
    this._answer,
    this._board,
    this._blanks,
    this._flags,
    this.turn,
    this.targetRoom,
    this.lastCell,
    this.stage, {
    this.humanBonusRoom,
  });

  /// Without a shuffle the mini game opens on the introductory position.
  /// Swapping digits, bands and rows within bands preserves a unique solution.
  factory SudokuDuel.start(DuelSize size, {Random? shuffle}) {
    List<int> axisOrder(int groupSize) {
      final bands = List.generate(size.side ~/ groupSize, (band) {
        final rows = List.generate(groupSize, (i) => band * groupSize + i);
        if (shuffle != null) rows.shuffle(shuffle);
        return rows;
      });
      if (shuffle != null) bands.shuffle(shuffle);
      return bands.expand((band) => band).toList();
    }

    final rows = axisOrder(size.boxRows);
    final columns = axisOrder(size.boxColumns);
    final digits = List.generate(size.side, (i) => i + 1);
    if (shuffle != null) digits.shuffle(shuffle);
    final symbols = [0, ...digits];
    List<int> read(String pattern) => [
      for (final row in rows)
        for (final column in columns)
          symbols[pattern.codeUnitAt(row * size.side + column) - 48],
    ];
    return SudokuDuel._startBoard(size, read(size._givens), read(size._answer));
  }

  /// The story catalog validates the givens and their solution on load.
  factory SudokuDuel.story(
    String puzzle,
    String solution,
    List<int> moves, {
    StoryDuelStage? stage,
    int variant = 0,
  }) {
    if (stage == null && variant != 0) {
      throw const FormatException('Board variant requires a story duel stage');
    }
    final board = stage?.boardForVariant(variant);
    if (board != null &&
        (board.puzzle != puzzle || board.solution != solution)) {
      throw FormatException(
        'Board does not match story duel stage: ${stage!.name}, variant $variant',
      );
    }
    final size = switch (puzzle.length) {
      16 => DuelSize.mini,
      36 => DuelSize.six,
      81 => DuelSize.classic,
      _ => throw FormatException(
        'Invalid story duel dimensions: ${puzzle.length}',
      ),
    };
    List<int> digits(String text) => [
      for (final unit in text.codeUnits) unit - 48,
    ];
    var game = SudokuDuel._startBoard(
      size,
      digits(puzzle),
      digits(solution),
      stage: stage,
    );
    for (final cell in [...?board?.opening, ...moves]) {
      if (cell < 0 || cell >= puzzle.length || !game.canPlay(cell)) {
        throw FormatException(
          'Invalid story duel move: cell $cell, room ${game.targetRoom}',
        );
      }
      game = game._place(cell);
    }
    return game;
  }

  /// A complete, validated puzzle from the independent dojo catalog.
  factory SudokuDuel.dojo(DuelSize size, List<int> givens, List<int> answer) {
    if (givens.length != size.side * size.side || answer.length != givens.length) {
      throw ArgumentError('Invalid dojo board dimensions');
    }
    return SudokuDuel._startBoard(size, List.of(givens), List.of(answer));
  }

  /// A preverified four-room human match. The caller must obtain the bonus
  /// room from the second player before starting; no CPU or story catalog is used.
  factory SudokuDuel.humanMini({required int bonusRoom}) {
    RangeError.checkValueInInterval(bonusRoom, 1, 4, 'bonusRoom');
    const puzzle = '1004301020034020';
    const solution = '1234341221434321';
    List<int> digits(String text) => [
      for (final unit in text.codeUnits) unit - 48,
    ];
    return SudokuDuel._startBoard(
      DuelSize.mini,
      digits(puzzle),
      digits(solution),
      humanBonusRoom: bonusRoom,
    );
  }

  factory SudokuDuel._startBoard(
    DuelSize size,
    List<int> givens,
    List<int> answer, {
    StoryDuelStage? stage,
    int? humanBonusRoom,
  }) {
    final blanks = List.filled(size.side, 0);
    for (var cell = 0; cell < givens.length; cell++) {
      if (givens[cell] == 0) blanks[size.roomOf(cell) - 1]++;
    }
    return SudokuDuel._(
      size,
      givens,
      answer,
      givens,
      blanks,
      List.filled(size.side, null),
      DuelPlayer.first,
      blanks.first == 0 ? null : 1,
      null,
      stage,
      humanBonusRoom: humanBonusRoom,
    );
  }

  final DuelSize size;
  final List<int> _givens;
  final List<int> _answer;
  final List<int> _board;
  final List<int> _blanks;
  final List<DuelPlayer?> _flags;
  final DuelPlayer turn;
  final int? targetRoom;
  final int? lastCell;
  final StoryDuelStage? stage;
  final int? humanBonusRoom;

  int? get bonusRoom => humanBonusRoom ?? stage?.doubleRoom;

  int valueAt(int cell) => _board[cell];
  bool isGiven(int cell) => _givens[cell] != 0;
  DuelPlayer? flagAt(int room) => _flags[room - 1];
  bool hasSpace(int room) => _blanks[room - 1] > 0;
  int score(DuelPlayer player) {
    final bonus = bonusRoom;
    return _flags.where((owner) => owner == player).length +
        (bonus != null && flagAt(bonus) == player ? 1 : 0);
  }

  bool get isOver {
    if (!_blanks.any((count) => count > 0)) return true;
    final target = humanBonusRoom != null
        ? 3
        : stage?.firstTo ?? (size == DuelSize.classic ? 5 : null);
    return target != null &&
        (score(DuelPlayer.first) >= target ||
            score(DuelPlayer.second) >= target);
  }

  bool _available(int cell) =>
      valueAt(cell) == 0 &&
      (targetRoom == null || size.roomOf(cell) == targetRoom);

  bool canPlay(int cell) => !isOver && _available(cell);

  Iterable<int> get legalCells sync* {
    if (isOver) return;
    for (var cell = 0; cell < _board.length; cell++) {
      if (_available(cell)) yield cell;
    }
  }

  /// An incorrect guess keeps the current position and turn intact.
  SudokuDuel? play(int cell, int digit) {
    RangeError.checkValueInInterval(digit, 1, size.side, 'digit');
    if (!canPlay(cell)) {
      throw StateError('Cannot play cell $cell in room $targetRoom');
    }
    return digit == _answer[cell] ? _place(cell) : null;
  }

  SudokuDuel _place(int cell) {
    final digit = _answer[cell];
    final room = size.roomOf(cell) - 1;
    final board = List.of(_board)..[cell] = digit;
    final blanks = List.of(_blanks);
    blanks[room]--;
    final flags = blanks[room] == 0 ? (List.of(_flags)..[room] = turn) : _flags;
    return SudokuDuel._(
      size,
      _givens,
      _answer,
      board,
      blanks,
      flags,
      turn.other,
      blanks[digit - 1] == 0 ? null : digit,
      cell,
      stage,
      humanBonusRoom: humanBonusRoom,
    );
  }

  static const _winScore = 100;
  int get _strongDepth => size == DuelSize.mini ? _board.length : 3;

  SudokuDuel computerMove(DuelRival? rival, Random random) {
    if (humanBonusRoom != null) {
      throw StateError('A human duel cannot use a computer move');
    }
    if (isOver) throw StateError('The duel has already ended');
    final choices = legalCells.toList()..shuffle(random);
    if (stage case final authored?) {
      return _bestMove(choices, authored.lookAhead);
    }
    return _bestMove(choices, switch (rival) {
      DuelRival.pomupomu => 1,
      DuelRival.mosaedo || DuelRival.patissier => 2,
      DuelRival.oshisho => _strongDepth,
      null => throw StateError('Missing NPC for a standard duel'),
    });
  }

  SudokuDuel _bestMove(Iterable<int> choices, int depth) {
    late SudokuDuel best;
    var bestScore = -_winScore - 1;
    for (final cell in choices) {
      final next = _place(cell);
      final score = -next._lookAhead(depth - 1, -_winScore - 1, -bestScore);
      if (score > bestScore) {
        bestScore = score;
        best = next;
        if (score == _winScore) break;
      }
    }
    return best;
  }

  // Evaluate from the side to move. Ending the game outweighs any partial lead.
  int _lookAhead(int depth, int alpha, int beta) {
    final lead = score(turn) - score(turn.other);
    if (isOver) return _winScore * lead.sign;
    if (depth == 0) return lead;
    var best = -_winScore - 1;
    for (final cell in legalCells) {
      best = max(best, -_place(cell)._lookAhead(depth - 1, -beta, -alpha));
      if (best >= beta || best == _winScore) break;
      alpha = max(alpha, best);
    }
    return best;
  }
}
