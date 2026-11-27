import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:future_lift/dojo_puzzle.dart';
import 'package:future_lift/kotohoguru_dojo.dart';

void main() {
  for (final level in [
    DojoLevel.entry,
    DojoLevel.beginner,
    DojoLevel.intermediate,
  ]) {
    testWidgets('${level.name}: candidate notes pack, resize and remain editable',
        (tester) async {
      tester.view.physicalSize = const Size(345, 742);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final puzzle = DojoPuzzle.generate(level, Random(4));
      final cell = puzzle.givens.indexOf(0);
      final square = find.byKey(ValueKey('dojo-cell-$cell'));
      Finder note(int digit) => find.descendant(
        of: square,
        matching: find.byKey(ValueKey('dojo-note-$digit')),
      );
      Future<void> tap(Finder finder) async {
        await tester.ensureVisible(finder);
        await tester.tap(finder);
        await tester.pump();
      }

      await tester.pumpWidget(
        MaterialApp(home: DojoPracticePage.solo(puzzle: puzzle)),
      );
      await tap(square);
      await tap(find.text('候補メモ'));
      await tap(find.byKey(const ValueKey('dojo-digit-1')));
      expect(note(1), findsOneWidget);
      final singleHeight = tester.getRect(note(1)).height;
      expect(tester.widget<Text>(note(1)).style!.decoration,
          TextDecoration.underline);

      for (var digit = 2; digit <= puzzle.size.side; digit++) {
        await tap(find.byKey(ValueKey('dojo-digit-$digit')));
        expect(note(digit), findsOneWidget);
        expect(tester.getRect(note(digit)).width, greaterThan(0));
      }
      expect(tester.getRect(note(1)).height, lessThan(singleHeight));
      expect(tester.widget<Text>(note(1)).style!.decoration,
          TextDecoration.none);
      // Every visible digit fits inside its cell and has its own space.
      final bounds = tester.getRect(square).inflate(0.01);
      for (var digit = 1; digit <= puzzle.size.side; digit++) {
        final rect = tester.getRect(note(digit));
        expect(bounds.contains(rect.topLeft), isTrue);
        expect(bounds.contains(rect.bottomRight), isTrue);
        for (var other = digit + 1; other <= puzzle.size.side; other++) {
          expect(rect.overlaps(tester.getRect(note(other))), isFalse);
        }
      }
      for (var digit = puzzle.size.side; digit >= 2; digit--) {
        await tap(find.byKey(ValueKey('dojo-digit-$digit')));
        expect(note(digit), findsNothing);
      }
      expect(tester.getRect(note(1)).height, closeTo(singleHeight, 0.01));
      await tap(find.text('候補メモ'));
      await tap(find.byKey(ValueKey('dojo-digit-${puzzle.answer[cell]}')));
      expect(note(1), findsNothing);
      expect(find.descendant(of: square, matching: find.text('${puzzle.answer[cell]}')),
          findsOneWidget);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
