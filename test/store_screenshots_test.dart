import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:future_lift/resident_collection.dart';
import 'package:future_lift/resident_conversation_dialog.dart';
import 'package:future_lift/store_screenshots.dart';
import 'package:future_lift/progress.dart';

void main() {
  test('five screenshot scenes use four existing navigation destinations', () {
    expect(screenshotPageNames, [
      'home', 'missions', 'town', 'history', 'conversation',
    ]);
    expect([
      for (final page in screenshotPageNames) screenshotPageIndex(page),
    ], [0, 1, 2, 3, 2]);
    expect(() => screenshotPageIndex('developer'), throwsArgumentError);
    expect(() => screenshotPageIndex(null), throwsArgumentError);
  });

  testWidgets('conversation screenshot displays a real CMS line and avatar',
      (tester) async {
    final now = DateTime(2026, 10, 19, 12);
    final progress = buildStoreScreenshotProgress(now);
    final dialogue = await loadScreenshotConversation(progress, now);
    expect(dialogue.id, screenshotConversationDialogueId);
    expect(dialogue.residentId, TownResident.rabbit.id);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => ResidentConversationDialog(
                speaker: TownResident.rabbit,
                dialogue: dialogue,
              ),
            ),
            child: const Text('会話を開く'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('会話を開く'));
    await tester.pumpAndSettle();
    expect(find.text('およめさん'), findsOneWidget);
    expect(find.textContaining('ちょうどお茶をいれたところ'), findsOneWidget);
    expect(find.byKey(const ValueKey('dialogue-visible-line')), findsOneWidget);
    expect(find.byKey(const ValueKey('dialogue-next-button')), findsOneWidget);
  });

  test('sample capture content has believable missions and town residents', () {
    final snapshot = buildStoreScreenshotProgress(DateTime(2026, 10, 19, 12));
    expect(snapshot.day, '2026-10-19');
    expect(snapshot.lastCompletedDay, snapshot.day);
    expect(snapshot.points, greaterThanOrEqualTo(180));
    expect(snapshot.residents.owned.length, greaterThan(4));
    expect(snapshot.residents.availableKotohogi(snapshot.points), greaterThan(0));
    expect(snapshot.completed, containsAll([Mission.outside, Mission.food]));
    expect(snapshot.history.length, greaterThanOrEqualTo(3));
    expect(snapshot.seenDialogues, contains('tutorial_kotohogisu_v1'));
    final decoded = Progress.decode(snapshot.encode(), expectedVersion: 5);
    expect(decoded.points, snapshot.points);
    expect(decoded.residents.owned, snapshot.residents.owned);
    expect(decoded.history, snapshot.history);
  });
}
