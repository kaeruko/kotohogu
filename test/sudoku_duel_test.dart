import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:future_lift/dialogue_engine.dart';
import 'package:future_lift/main.dart';
import 'package:future_lift/progress.dart';
import 'package:future_lift/sudoku_duel.dart';

import 'progress_test.dart' show MemoryStore;

// Solve from the visible givens, independently of the game's stored answer.
List<int> solveSingles(SudokuDuel game) {
  final size = game.size.side;
  final board = List.generate(size * size, game.valueAt);
  while (board.contains(0)) {
    var progress = false;
    for (var i = 0; i < board.length; i++) {
      if (board[i] != 0) continue;
      final candidates = {for (var digit = 1; digit <= size; digit++) digit};
      for (var j = 0; j < board.length; j++) {
        if (i ~/ size == j ~/ size ||
            i % size == j % size ||
            game.size.roomOf(i) == game.size.roomOf(j)) {
          candidates.remove(board[j]);
        }
      }
      if (candidates.length == 1) {
        board[i] = candidates.single;
        progress = true;
      }
    }
    expect(progress, isTrue, reason: 'The givens must force every digit');
  }
  return board;
}

void main() {
  test('the introductory fork sends both replies to a one-cell room', () {
    final start = SudokuDuel.start(DuelSize.mini);
    expect(start.legalCells, [1, 5]);
    expect(start.play(1, 3), isNull);
    expect(start.valueAt(1), 0);
    expect(() => start.play(0, 1), throwsStateError);
    expect(() => start.play(7, 2), throwsStateError);
    expect(() => start.play(1, 5), throwsRangeError);

    final trap = start.play(5, 4)!;
    expect(trap.targetRoom, 4);
    for (final (cell, digit, reply) in [(14, 2, 7), (15, 1, 1)]) {
      final next = trap.play(cell, digit)!;
      expect(next.targetRoom, digit);
      expect(next.legalCells, [reply]);
      final captured = next.play(reply, 2)!;
      expect(captured.flagAt(digit), DuelPlayer.first);
    }
    final gift = start.play(1, 2)!.play(7, 2)!;
    expect(gift.flagAt(2), DuelPlayer.second);
    expect(gift.targetRoom, isNull);
    expect(gift.legalCells, containsAll([5, 8, 14]));
  });

  test(
    'Mosaedo avoids gifting a flag and Oshisho finds the only winning reply',
    () {
      final game = SudokuDuel.start(DuelSize.mini);
      expect(game.computerMove(DuelRival.mosaedo, Random(42)).lastCell, 5);
      final open = game.play(1, 2)!.play(7, 2)!.play(8, 2)!;
      expect(open.legalCells, [5, 13, 14, 15]);
      final reply = open.computerMove(DuelRival.oshisho, Random(42));
      expect(reply.lastCell, 5);
      expect(reply.flagAt(1), DuelPlayer.second);
      expect(open.valueAt(5), 0);
      expect(open.flagAt(1), isNull);
    },
  );

  test('four rooms can end in a draw and no further moves are accepted', () {
    var game = SudokuDuel.start(DuelSize.mini);
    for (final (cell, digit) in [
      (1, 2),
      (7, 2),
      (5, 4),
      (14, 2),
      (8, 2),
      (13, 3),
      (15, 1),
    ]) {
      expect(game.isOver, isFalse);
      game = game.play(cell, digit)!;
    }
    expect(game.isOver, isTrue);
    expect(game.score(DuelPlayer.first), 2);
    expect(game.score(DuelPlayer.second), 2);
    expect(game.legalCells, isEmpty);
    expect(
      () => game.computerMove(DuelRival.oshisho, Random(1)),
      throwsStateError,
    );
    expect(() => game.play(1, 2), throwsStateError);
  });

  test(
    'shuffled boards retain their unique answer and finish at the flag limit',
    () {
      for (final size in DuelSize.values) {
        final boards = <String>{};
        var sawEarlyWin = false;
        for (var seed = 0; seed < 8; seed++) {
          final random = Random(seed);
          var game = SudokuDuel.start(size, shuffle: seed == 0 ? null : random);
          boards.add(List.generate(size.side * size.side, game.valueAt).join());
          final solution = solveSingles(game);
          while (!game.isOver) {
            final legal = game.legalCells.toList();
            final before = game;
            if (game.turn == DuelPlayer.first) {
              final cell = legal[random.nextInt(legal.length)];
              game = game.play(cell, solution[cell])!;
            } else {
              game = game.computerMove(DuelRival.values[seed % 2], random);
            }
            final cell = game.lastCell!;
            expect(legal, contains(cell));
            expect(game.valueAt(cell), solution[cell]);
            expect(before.valueAt(cell), 0);
          }
          final flags = DuelPlayer.values.map(game.score);
          if (size != DuelSize.classic) {
            expect(flags.reduce((a, b) => a + b), size.side);
          } else {
            expect(flags.reduce(max), 5);
            sawEarlyWin |= flags.reduce((a, b) => a + b) < 9;
          }
        }
        expect(boards.length, greaterThan(1));
        if (size == DuelSize.classic) expect(sawEarlyWin, isTrue);
      }
    },
  );

  testWidgets(
    'story index has no free-play duel button and still opens the story',
    (tester) async {
      tester.view.physicalSize = const Size(360, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final store = MemoryStore();
      final controller = ProgressController(store);
      await tester.pumpWidget(
        FutureLiftApp(
          controller: controller,
          dialogueCatalog: (await tester.runAsync(DialogueCatalog.load))!,
          enableTutorial: false,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('open-story')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('story-open-duel')), findsNothing);
      expect(find.text('おくりマス数独のフリー対戦'), findsNothing);
      expect(find.text('お話一覧・手がかり帳'), findsOneWidget);
      expect(find.byKey(const ValueKey('story-open-episode')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('story-open-episode')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('story-dialogue')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}
