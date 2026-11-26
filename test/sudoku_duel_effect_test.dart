import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:future_lift/duel_move_effect.dart';
import 'package:future_lift/resident_collection.dart';
import 'package:future_lift/story_data.dart';
import 'package:future_lift/story_duel_stage.dart';
import 'package:future_lift/sudoku_duel.dart';
import 'package:future_lift/sudoku_duel_view.dart';

void main() {
  const stage = StoryDuelStage.firstFlag;
  const match = StoryDuel.authored(
    StorySpeaker.local(TownResident.shiba),
    StorySpeaker.local(TownResident.c052_pome),
    stage,
  );
  final correct = find.byKey(const ValueKey('duel-effect-correct'));
  final wrong = find.byKey(const ValueKey('duel-effect-wrong'));

  DuelMoveEffect effect(WidgetTester tester, Finder finder) =>
      (tester.widget<CustomPaint>(finder).painter! as DuelMoveEffectPainter)
          .effect;

  Future<void> choose(WidgetTester tester, int cell, int digit) async {
    final square = find.byKey(ValueKey('duel-cell-$cell'));
    await tester.ensureVisible(square);
    await tester.tap(square);
    await tester.pump();
    final number = find.byKey(ValueKey('duel-digit-$digit'));
    await tester.ensureVisible(number);
    await tester.tap(number);
    await tester.pump();
  }

  testWidgets('wrong, correct, flag and victory effects track committed moves',
      (tester) async {
    var position = SudokuDuel.story(
      stage.puzzle, stage.solution, [], stage: stage,
    ).play(1, 2)!.play(7, 2)!;
    late StateSetter refresh;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: StatefulBuilder(
            builder: (context, setState) {
              refresh = setState;
              return SudokuDuelView.story(
                match: match,
                position: position,
                onMove: (cell, digit) => refresh(() {
                  position = position.play(cell, digit)!;
                }),
                onFinish: () {},
              );
            },
          ),
        ),
      ),
    ));
    // Loading an existing match does not replay its last move.
    expect(correct, findsNothing);
    await choose(tester, 2, 1);
    expect(wrong, findsOneWidget);
    expect(effect(tester, wrong).wrong, isTrue);
    expect(position.valueAt(2), 0);
    expect(position.turn, DuelPlayer.first);

    await choose(tester, 2, 3);
    expect(wrong, findsNothing);
    expect(correct, findsOneWidget);
    final success = effect(tester, correct);
    expect(success.cell, 2);
    expect(success.capturedRoom, 2);
    expect(success.victory, isTrue);
    expect(position.isOver, isTrue);
    // A routine rebuild must not restart the animation.
    await tester.pump(const Duration(milliseconds: 400));
    refresh(() {});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(correct, findsNothing);
    expect(find.byKey(const ValueKey('story-finish-duel')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion keeps the move but skips the animation',
      (tester) async {
    var position = SudokuDuel.story(
      stage.puzzle, stage.solution, [], stage: stage,
    ).play(1, 2)!.play(7, 2)!;
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: StatefulBuilder(
            builder: (context, refresh) => SudokuDuelView.story(
              match: match,
              position: position,
              onMove: (cell, digit) => refresh(() {
                position = position.play(cell, digit)!;
              }),
              onFinish: () {},
            ),
          ),
        ),
      ),
    ));
    await choose(tester, 2, 1);
    expect(wrong, findsNothing);
    await choose(tester, 2, 3);
    expect(position.isOver, isTrue);
    expect(correct, findsNothing);
  });
}
