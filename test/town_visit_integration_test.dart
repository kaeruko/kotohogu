import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:future_lift/dialogue_engine.dart';
import 'package:future_lift/main.dart';
import 'package:future_lift/progress.dart';
import 'package:future_lift/resident_collection.dart';
import 'package:future_lift/town.dart';

import 'progress_test.dart' show MemoryStore;
import 'support/town_random.dart';

void main() {
  testWidgets('town entry, area navigation and conversations share one outing',
      (tester) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final progress = Progress(
      day: '2026-10-18', lastCompletedDay: '2026-10-18',
      points: 90, completed: {},
      residents: ResidentCollection(baselinePoints: 0, counts: {
        '01_shiba': 1, '02_rabbit': 1,
        '032_miner': 1, '027_daydreamer': 1,
      }),
    );
    final store = MemoryStore()..raw = progress.encode();
    final controller = ProgressController(store,
        clock: () => DateTime(2026, 10, 18, 12));
    final random = ScriptedTownRandom([0, 1, 1, 1, 1, 0, 0, 0]);
    final catalog = DialogueCatalog.fromJson(jsonEncode({
      'version': 1,
      'dialogues': [
        for (final resident in TownResident.values) {
          'id': '${resident.id}_outing_basic', 'residentId': resident.id,
          'text': 'こんにちは。', 'priority': 0, 'once': false,
          'logic': 'all', 'conditions': [],
        },
        {
          'id': 'miner_outing_pair', 'residentId': '032_miner',
          'text': '公園でも、一緒におしゃべり！',
          'priority': 10, 'once': true, 'logic': 'all',
          'conditions': [{'type': 'townTogether', 'otherResidentId': '027_daydreamer'}],
          'reply': {'residentId': '027_daydreamer', 'text': 'また会えたもふ。'},
        },
      ],
    }));
    await tester.pumpWidget(FutureLiftApp(controller: controller,
        dialogueCatalog: catalog, enableTutorial: false, townRandom: random));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('footer-town')));
    await tester.pumpAndSettle();
    final visit = tester.widget<TownScene>(find.byType(TownScene)).visit;
    expect(visit, isNotNull);
    expect(random.calls, 4);
    expect(find.byTooltip('もぐた'), findsNothing);
    final rawBeforeNavigation = store.raw;

    await tester.tap(find.byKey(const ValueKey('footer-town')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('town-area-next')));
    await tester.pumpAndSettle();
    expect(tester.widget<TownScene>(find.byType(TownScene)).visit, same(visit));
    expect(find.byTooltip('もぐた'), findsOneWidget);
    expect(find.byTooltip('おやすみくん'), findsOneWidget);
    expect(random.calls, 4);
    expect(store.raw, rawBeforeNavigation, reason: 'Outings never change saved progress');

    await tester.tap(find.byTooltip('もぐた'));
    await tester.pumpAndSettle();
    expect(find.text('公園でも、一緒におしゃべり！'), findsOneWidget);
    expect(tester.widget<TownScene>(find.byType(TownScene)).visit, same(visit));
    expect(random.calls, 4, reason: 'Saving the read ID must not redraw the town');
    await tester.tap(find.byKey(const ValueKey('dialogue-next-button')));
    await tester.pump();
    expect(find.text('また会えたもふ。'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('dialogue-next-button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('footer-home')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('footer-town')));
    await tester.pumpAndSettle();
    expect(tester.widget<TownScene>(find.byType(TownScene)).visit, isNot(same(visit)));
    expect(random.calls, 8);
    expect(find.byTooltip('もぐた'), findsNothing);
    expect(find.byTooltip('しばいぬ'), findsOneWidget);
    expect(controller.progress!.points, 90);
    expect(controller.progress!.residents.counts, progress.residents.counts);
    expect(controller.progress!.seenDialogues, contains('miner_outing_pair'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
