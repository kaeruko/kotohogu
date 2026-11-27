import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:future_lift/dojo_puzzle.dart';
import 'package:future_lift/duel_move_effect.dart';
import 'package:future_lift/kotohoguru_dojo.dart';

void main() {
  final wrong = find.byKey(const ValueKey('dojo-effect-wrong'));
  final correct = find.byKey(const ValueKey('dojo-effect-correct'));

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pump();
  }

  Future<void> choose(WidgetTester tester, int cell, int digit) async {
    await tap(tester, find.byKey(ValueKey('dojo-cell-$cell')));
    await tap(tester, find.byKey(ValueKey('dojo-digit-$digit')));
  }

  DuelMoveEffectPainter painter(WidgetTester tester, Finder finder) =>
      tester.widget<CustomPaint>(finder).painter! as DuelMoveEffectPainter;

  testWidgets('solo feedback uses flat coordinates, ignores notes and erases, celebrates completion',
      (tester) async {
    final puzzle = DojoPuzzle.generate(DojoLevel.entry, Random(4));
    final blanks = [for (var i = 0; i < puzzle.givens.length; i++)
      if (puzzle.givens[i] == 0) i];
    final cell = blanks.first;
    final answer = puzzle.answer[cell];
    await tester.pumpWidget(MaterialApp(home: DojoPracticePage.solo(puzzle: puzzle)));
    expect(correct, findsNothing);
    await choose(tester, cell, answer % puzzle.size.side + 1);
    expect(wrong, findsOneWidget);
    expect(painter(tester, wrong).flatBoard, isTrue);
    expect(painter(tester, wrong).effect.cell, cell);
    await tap(tester, find.text('消す'));
    expect(wrong, findsNothing);
    expect(correct, findsNothing);

    await tap(tester, find.text('候補メモ'));
    await choose(tester, cell, answer);
    expect(correct, findsNothing);
    expect(wrong, findsNothing);
    await tap(tester, find.text('候補メモ'));

    await choose(tester, cell, answer);
    expect(correct, findsOneWidget);
    expect(painter(tester, correct).effect.victory, isFalse);
    await tester.pump(const Duration(milliseconds: 700));
    expect(correct, findsNothing);

    for (final i in blanks.skip(1)) {
      await choose(tester, i, puzzle.answer[i]);
    }
    expect(correct, findsOneWidget);
    expect(painter(tester, correct).effect.victory, isTrue);
    expect(find.byKey(const ValueKey('dojo-finish-solo')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion skips effects but retains wrong number feedback',
      (tester) async {
    final puzzle = DojoPuzzle.generate(DojoLevel.entry, Random(7));
    final cell = puzzle.givens.indexOf(0);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: DojoPracticePage.solo(puzzle: puzzle),
    ));
    await choose(tester, cell, puzzle.answer[cell] % puzzle.size.side + 1);
    expect(wrong, findsNothing);
    expect(tester.widget<Semantics>(find.byKey(ValueKey('dojo-cell-$cell'))).properties.label,
        contains('不正解'));
    await choose(tester, cell, puzzle.answer[cell]);
    expect(correct, findsNothing);
    expect(tester.widget<Semantics>(find.byKey(ValueKey('dojo-cell-$cell'))).properties.label,
        isNot(contains('不正解')));
  });
}
