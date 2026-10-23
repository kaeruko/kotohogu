import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:future_lift/dialogue_engine.dart';
import 'package:future_lift/progress.dart';
import 'package:future_lift/resident_collection.dart';
import 'package:future_lift/resident_conversation_dialog.dart';

void main() {
  final catalog = DialogueCatalog.fromJson(jsonEncode({
    'version': 1,
    'dialogues': [
      for (final resident in TownResident.values)
        {
          'id': 'ordinary_${resident.id}',
          'residentId': resident.id,
          'text': 'ひとりのおはなし',
          'priority': 0,
          'once': false,
          'logic': 'all',
          'conditions': [],
        },
      {
        'id': 'farmer_and_daydreamer',
        'residentId': '026_farmer',
        'text': 'おやすみくん。農業をやらんかね。',
        'priority': 60,
        'once': false,
        'logic': 'all',
        'conditions': [
          {'type': 'townTogether', 'otherResidentId': '027_daydreamer'},
        ],
        'reply': {
          'residentId': '027_daydreamer',
          'text': 'いやもふ～～',
        },
      },
    ],
  }));

  Future<void> openDialogue(
    WidgetTester tester,
    TownResident speaker,
    Set<String> visible, {
    DialogueEntry? chosenLine,
    double textScale = 1,
  }) async {
    final progress = Progress.empty(DateTime(2026, 10, 15));
    final line = chosenLine ??
        (speaker == TownResident.c026_farmer
            ? catalog.selectById(
                id: 'farmer_and_daydreamer',
                resident: speaker,
                progress: progress,
                now: DateTime.utc(2026, 10, 15),
                townResidentIds: visible,
              )
            : catalog.select(
                resident: speaker,
                progress: progress,
                now: DateTime.utc(2026, 10, 15),
                townResidentIds: visible,
              ));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => ResidentConversationDialog(
                  speaker: speaker,
                  dialogue: line,
                ),
              ),
              child: const Text('会話を開く'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('会話を開く'));
    await tester.pumpAndSettle();
  }

  testWidgets('tap the dialogue itself to show the other resident',
      (tester) async {
    await openDialogue(
      tester,
      TownResident.c026_farmer,
      {'026_farmer', '027_daydreamer'},
    );
    expect(find.text('やすぞう'), findsOneWidget);
    expect(find.text('おやすみくん。農業をやらんかね。'), findsOneWidget);
    expect(find.text('いやもふ～～'), findsNothing);
    expect(find.text('つぎへ'), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('dialogue-visible-line')));
    await tester.pumpAndSettle();

    expect(find.text('おやすみくん'), findsOneWidget);
    expect(find.text('やすぞう'), findsNothing);
    expect(find.text('おやすみくん。農業をやらんかね。'), findsNothing);
    expect(find.text('いやもふ～～'), findsOneWidget);
    expect(find.text('2 / 2'), findsOneWidget);

    await tester.tap(find.text('また話そう'));
    await tester.pumpAndSettle();
    expect(find.byType(ResidentConversationDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ordinary dialogue still closes in one tap', (tester) async {
    await openDialogue(tester, TownResident.rabbit, {'002_usagi'});
    expect(find.text(TownResident.rabbit.label), findsOneWidget);
    expect(find.text('ひとりのおはなし'), findsOneWidget);
    expect(find.text('つづきへ'), findsNothing);
    expect(find.byKey(const ValueKey('dialogue-turn-count')), findsNothing);
    await tester.tap(find.text('また話そう'));
    await tester.pumpAndSettle();
    expect(find.byType(ResidentConversationDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('long dialogue uses readable pages without losing words',
      (tester) async {
    final original = List.filled(18, '今日はゆっくり過ごしてもいいんだよ。').join();
    final longCatalog = DialogueCatalog.fromJson(jsonEncode({
      'version': 1,
      'dialogues': [
        for (final resident in TownResident.values)
          {
            'id': 'fallback_long_${resident.id}',
            'residentId': resident.id,
            'text': 'こんにちは',
            'priority': 0,
            'once': false,
            'logic': 'all',
            'conditions': [],
          },
        {
          'id': 'long_rabbit',
          'residentId': '002_usagi',
          'text': original,
          'priority': 5,
          'once': false,
          'logic': 'all',
          'conditions': [],
        },
      ],
    }));
    await openDialogue(tester, TownResident.rabbit, {'002_usagi'},
        chosenLine: longCatalog.entries.last);

    expect(find.byKey(const ValueKey('dialogue-page-count')), findsOneWidget);
    expect(find.text(original), findsNothing);
    final height = tester.getSize(find.byType(AlertDialog)).height;
    final text = tester.widget<Text>(
        find.byKey(const ValueKey('dialogue-visible-line')));
    expect(text.style!.fontSize, 20);

    final seen = StringBuffer();
    var pageCount = 0;
    while (find.text('つぎへ').evaluate().isNotEmpty) {
      seen.write(tester.widget<Text>(
          find.byKey(const ValueKey('dialogue-visible-line'))).data);
      await tester.tap(find.byKey(const ValueKey('dialogue-next-button')));
      await tester.pumpAndSettle();
      pageCount++;
      expect(pageCount, lessThan(35));
      expect(tester.getSize(find.byType(AlertDialog)).height, height);
    }
    expect(pageCount, greaterThan(1));
    seen.write(tester.widget<Text>(
        find.byKey(const ValueKey('dialogue-visible-line'))).data);
    expect(seen.toString(), original);
    await tester.tap(find.text('また話そう'));
    await tester.pumpAndSettle();
    expect(find.byType(ResidentConversationDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scaled narrow layout pages before switching to second speaker',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final first = List.filled(10, '今日の公園はきれいだったよ。').join();
    final second = List.filled(9, 'またお散歩しようね。').join();
    final longCatalog = DialogueCatalog.fromJson(jsonEncode({
      'version': 1,
      'dialogues': [
        for (final resident in TownResident.values)
          {
            'id': 'fallback_scaled_${resident.id}',
            'residentId': resident.id,
            'text': 'こんにちは',
            'priority': 0,
            'once': false,
            'logic': 'all',
            'conditions': [],
          },
        {
          'id': 'long_pair',
          'residentId': '026_farmer',
          'text': first,
          'priority': 50,
          'once': false,
          'logic': 'all',
          'conditions': [
            {'type': 'townTogether', 'otherResidentId': '027_daydreamer'},
          ],
          'reply': {
            'residentId': '027_daydreamer',
            'text': second,
          },
        },
      ],
    }));
    await openDialogue(tester, TownResident.c026_farmer,
        {'026_farmer', '027_daydreamer'},
        chosenLine: longCatalog.entries.last, textScale: 1.7);

    final firstRead = StringBuffer();
    var firstPages = 0;
    while (find.text('やすぞう').evaluate().isNotEmpty) {
      firstRead.write(tester.widget<Text>(
          find.byKey(const ValueKey('dialogue-visible-line'))).data);
      expect(find.text('1 / 2'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('dialogue-next-button')));
      await tester.pumpAndSettle();
      firstPages++;
      expect(firstPages, lessThan(35));
    }
    expect(firstPages, greaterThan(1));
    expect(firstRead.toString(), first);
    expect(find.text('おやすみくん'), findsOneWidget);
    final replyRead = StringBuffer();
    var replyPages = 0;
    while (find.text('つぎへ').evaluate().isNotEmpty) {
      replyRead.write(tester.widget<Text>(
          find.byKey(const ValueKey('dialogue-visible-line'))).data);
      await tester.tap(find.byKey(const ValueKey('dialogue-next-button')));
      await tester.pumpAndSettle();
      replyPages++;
      expect(replyPages, lessThan(35));
    }
    replyRead.write(tester.widget<Text>(
        find.byKey(const ValueKey('dialogue-visible-line'))).data);
    expect(replyRead.toString(), second);
    await tester.tap(find.text('また話そう'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

}
