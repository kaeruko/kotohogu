import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:future_lift/sudoku_duel.dart';

import 'sudoku_duel_test.dart' show solveSingles;

// Enumerate every legal correct move, independently of the CPU search.
// Returns the minimax value, all reachable winners and the first player's
// win probability when both choose uniformly among legal cells.
({int optimal, Set<DuelPlayer> winners, double firstWin}) evaluate(
  SudokuDuel game, List<int> solution,
) {
  if (game.isOver) {
    final first = game.score(DuelPlayer.first);
    final second = game.score(DuelPlayer.second);
    expect(max(first, second), greaterThanOrEqualTo(3));
    expect(min(first, second), lessThan(3));
    expect(game.legalCells, isEmpty);
    final winner = first > second ? DuelPlayer.first : DuelPlayer.second;
    return (
      optimal: winner == DuelPlayer.first ? 1 : -1,
      winners: {winner},
      firstWin: winner == DuelPlayer.first ? 1.0 : 0.0,
    );
  }

  final options = [
    for (final cell in game.legalCells)
      evaluate(game.play(cell, solution[cell])!, solution),
  ];
  expect(options, isNotEmpty);
  return (
    optimal: options.map((x) => x.optimal).reduce(
      game.turn == DuelPlayer.first ? max : min,
    ),
    winners: {for (final option in options) ...option.winners},
    firstWin: options.map((x) => x.firstWin).reduce((a, b) => a + b) /
        options.length,
  );
}

void main() {
  test('human mini requires an explicit legal bonus room', () {
    for (final invalid in [0, 5]) {
      expect(() => SudokuDuel.humanMini(bonusRoom: invalid), throwsRangeError);
    }
    final game = SudokuDuel.humanMini(bonusRoom: 3);
    expect(game.turn, DuelPlayer.first);
    expect(game.targetRoom, 1);
    expect(game.bonusRoom, 3);
    expect(game.legalCells, [1, 5]);
    expect(game.play(1, 1), isNull);
    expect(() => game.computerMove(DuelRival.oshisho, Random(1)),
        throwsStateError);
    expect(game.play(1, 2)!.bonusRoom, 3);
  });

  test('each bonus placement allows both winners; exact minimax is recorded', () {
    const optimal = [-1, -1, -1, 1];
    const randomFirstWin = [0.5, 47 / 96, 47 / 96, 50 / 96];
    for (var bonus = 1; bonus <= 4; bonus++) {
      final game = SudokuDuel.humanMini(bonusRoom: bonus);
      final solution = solveSingles(game);
      expect(solution.join(), '1234341221434321');
      final result = evaluate(game, solution);
      expect(result.winners, DuelPlayer.values.toSet());
      expect(result.optimal, optimal[bonus - 1]);
      expect(result.firstWin, closeTo(randomFirstWin[bonus - 1], 1e-12));
    }
  });

  test('human bonus does not alter normal and authored game settings', () {
    expect(SudokuDuel.start(DuelSize.mini).bonusRoom, isNull);
    expect(SudokuDuel.humanMini(bonusRoom: 2).stage, isNull);
  });
}
