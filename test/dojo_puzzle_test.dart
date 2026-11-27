import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:future_lift/dojo_puzzle.dart';
import 'package:future_lift/sudoku_duel.dart';

// Count solutions independently from the stored answer, stopping at two.
int solutions(DojoPuzzle puzzle) {
  final size = puzzle.size;
  final n = size.side;
  final board = List.of(puzzle.givens);
  int solve() {
    var cell = -1;
    var best = <int>[];
    for (var i = 0; i < board.length; i++) {
      if (board[i] != 0) continue;
      final candidates = {for (var d = 1; d <= n; d++) d};
      for (var j = 0; j < board.length; j++) {
        if (i ~/ n == j ~/ n || i % n == j % n ||
            size.roomOf(i) == size.roomOf(j)) {
          candidates.remove(board[j]);
        }
      }
      if (candidates.isEmpty) return 0;
      if (cell == -1 || candidates.length < best.length) {
        cell = i;
        best = candidates.toList();
        if (best.length == 1) break;
      }
    }
    if (cell == -1) return 1;
    var count = 0;
    for (final digit in best) {
      board[cell] = digit;
      count += solve();
      board[cell] = 0;
      if (count >= 2) return count;
    }
    return count;
  }
  return solve();
}

bool solvedBySingles(DojoPuzzle puzzle, {required bool hidden}) {
  final n = puzzle.size.side;
  final board = List.of(puzzle.givens);
  final units = [
    for (var i = 0; i < n; i++) [for (var j = 0; j < n; j++) i * n + j],
    for (var i = 0; i < n; i++) [for (var j = 0; j < n; j++) j * n + i],
    for (var i = 1; i <= n; i++) [for (var j = 0; j < n * n; j++) if (puzzle.size.roomOf(j) == i) j],
  ];
  while (board.contains(0)) {
    final candidates = List.generate(board.length, (i) {
      if (board[i] != 0) return <int>{};
      final values = {for (var digit = 1; digit <= n; digit++) digit};
      for (final unit in units) {
        if (unit.contains(i)) {
          for (final j in unit) {
            values.remove(board[j]);
          }
        }
      }
      return values;
    });
    final single = candidates.indexWhere((values) => values.length == 1);
    if (single >= 0) {
      board[single] = candidates[single].single;
      continue;
    }
    if (!hidden) return false;
    var placed = false;
    for (final unit in units) {
      for (var digit = 1; digit <= n; digit++) {
        final hits = unit.where((i) => candidates[i].contains(digit)).toList();
        if (hits.length == 1) {
          board[hits.single] = digit;
          placed = true;
          break;
        }
      }
      if (placed) break;
    }
    if (!placed) return false;
  }
  return puzzle.isComplete(board);
}

void main() {
  test('9x9 levels distinguish naked, hidden and more complex deductions', () {
    for (var seed = 0; seed < 12; seed++) {
      final random = Random(seed);
      final middle = DojoPuzzle.generate(DojoLevel.intermediate, random);
      final upper = DojoPuzzle.generate(DojoLevel.advanced, random);
      expect(solvedBySingles(middle, hidden: false), isTrue);
      expect(solvedBySingles(upper, hidden: false), isFalse);
      expect(solvedBySingles(upper, hidden: true), isTrue);
      for (final level in [DojoLevel.master, DojoLevel.oni]) {
        expect(solvedBySingles(DojoPuzzle.generate(level, random), hidden: true), isFalse);
      }
    }
  });

  test('each difficulty produces unique valid boards with all rooms playable', () {
    for (final level in DojoLevel.values) {
      final seen = <String>{};
      for (var seed = 0; seed < 12; seed++) {
        final puzzle = DojoPuzzle.generate(level, Random(seed));
        final n = puzzle.size.side;
        final digits = {for (var d = 1; d <= n; d++) d};
        expect(solutions(puzzle), 1, reason: '${level.name} seed $seed');
        expect(puzzle.isComplete(puzzle.answer), isTrue);
        expect(puzzle.isComplete(puzzle.givens), isFalse);
        for (var i = 0; i < n; i++) {
          expect({for (var j = 0; j < n; j++) puzzle.answer[i * n + j]}, digits);
          expect({for (var j = 0; j < n; j++) puzzle.answer[j * n + i]}, digits);
          final room = [for (var j = 0; j < n * n; j++) if (puzzle.size.roomOf(j) == i + 1) j];
          expect(room.map((j) => puzzle.answer[j]).toSet(), digits);
          expect(room.any((j) => puzzle.givens[j] == 0), isTrue);
        }
        for (var i = 0; i < n * n; i++) {
          expect(puzzle.givens[i] == 0 || puzzle.givens[i] == puzzle.answer[i], isTrue);
        }
        seen.add(puzzle.givens.join());
        var duel = puzzle.duel();
        while (!duel.isOver) {
          final cell = duel.legalCells.first;
          duel = duel.play(cell, puzzle.answer[cell])!;
        }
        if (puzzle.size == DuelSize.classic) {
          expect(DuelPlayer.values.map(duel.score).reduce(max), 5);
        }
      }
      expect(seen.length, greaterThan(1));
    }
  });
}
