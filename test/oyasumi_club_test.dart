import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:future_lift/oyasumi_club.dart';
import 'package:future_lift/progress.dart';
import 'package:future_lift/resident_collection.dart';
import 'package:future_lift/town_areas.dart';
import 'package:future_lift/town_rules.dart';
import 'package:future_lift/main.dart';
import 'package:future_lift/dialogue_engine.dart';

import 'progress_test.dart' show MemoryStore;

const host = OyasumiScene.host;
const frog = OyasumiScene.frog;
OyasumiScene scene(
  int day, {
  int hour = 19,
  bool hasFrog = true,
  OyasumiProgress saved = const OyasumiProgress(),
}) => OyasumiScene(
  saved: saved,
  owned: [host, if (hasFrog) frog],
  now: DateTime(2026, 10, day, hour),
);
Progress progress(DateTime now, OyasumiProgress state) => Progress(
  day: localDay(now),
  lastCompletedDay: null,
  points: 0,
  completed: {},
  oyasumi: state,
  residents: ResidentCollection(
    baselinePoints: 0,
    debugTicketsGranted: 2,
    counts: {"001_shiba": 1, "002_usagi": 1, host.id: 1, frog.id: 1},
  ),
);
void main() {
  test('runtime and CMS match the shared 96-scenario contract', () {
    final cases = jsonDecode(
      File('test/fixtures/oyasumi_preview.json').readAsStringSync(),
    ) as List;
    for (final row in cases) {
      final input = row['input'];
      final state = OyasumiProgress(
        completed: input['completed'],
        lastNight: input['lastNight'],
      );
      final model = OyasumiScene(
        saved: state,
        owned: (input['owned'] as List).map((id) => TownResident.fromId(id)),
        now: DateTime.parse(input['now']),
      );
      final speaker = model.step == 1 ? host : frog;
      final next = model.completeIntroduction(speaker, model.stage);
      expect(
        {
          'active': model.active,
          'stage': model.stage,
          'nightKey': model.nightKey,
          'cast': model.cast.map((r) => r.id).toList(),
          'frogResting': model.frogResting,
          'canComplete':
              model.introduction(speaker, model.stage) && model.laterNight,
          'nextCompleted': next.completed,
        },
        row['expected'],
        reason: input.toString(),
      );
    }
  });
  test('unowned frog waits indefinitely, owned frog needs distinct completed nights', () {
    var first = scene(20, hasFrog: false);
    expect(first.stage, 'solo');
    var saved = first.completeIntroduction(host, 'solo');
    expect(saved.completed, 1);
    expect(scene(30, hasFrog: false, saved: saved).stage, 'solo');
    expect(scene(20, saved: saved).stage, 'solo');
    expect(scene(21, hour: 1, saved: saved).nightKey, '2026-10-20');
    expect(scene(21, hour: 1, saved: saved).stage, 'solo');
    var second = scene(23, saved: saved);
    expect(second.stage, 'watching');
    expect(
      second.route(TownArea.plaza, frog)!.x,
      greaterThan(second.route(TownArea.plaza, host)!.x),
    );
    expect(second.completeIntroduction(host, 'watching'), same(saved));
    saved = second.completeIntroduction(frog, 'watching');
    expect(scene(23, saved: saved).stage, 'watching');
    var third = scene(24, saved: saved);
    expect(third.stage, 'joining');
    saved = third.completeIntroduction(frog, 'joining');
    expect(saved.completed, 3);
    expect(scene(24, saved: saved).stage, 'joined');
    var daytime = scene(25, hour: 12, saved: saved);
    expect(daytime.active, isFalse);
    expect(daytime.group(frog, inPlaza: false), 'resting');
    expect(daytime.dialogue(frog, 'resting', 0).text, contains('会社を辞めて'));
  });
  test('night boundaries and missing host do not activate club', () {
    expect(scene(20, hour: 17).active, isFalse);
    expect(scene(20, hour: 18).active, isTrue);
    expect(scene(21, hour: 4).active, isTrue);
    expect(scene(21, hour: 5).active, isFalse);
    expect(
      OyasumiScene(
        saved: const OyasumiProgress(),
        owned: [frog],
        now: DateTime(2026, 10, 20, 19),
      ).active,
      isFalse,
    );
  });
  test('exclusive cast and conversation peers use same event placement', () {
    final now = DateTime(2026, 10, 20, 19), state = scene(20);
    final rules = TownRules(
      progress(now, const OyasumiProgress()),
      visit: TownVisit(),
      oyasumi: state,
    );
    expect(rules.outdoors(TownArea.plaza), contains(host));
    expect(rules.outdoors(TownArea.plaza), isNot(contains(frog)));
    expect(
      rules.conversationPeers(ConversationSite.town, area: TownArea.plaza),
      {host.id, '001_shiba', '002_usagi'},
    );
    for (final area in TownArea.values.where((a) => a != TownArea.plaza)) {
      expect(rules.outdoors(area), isEmpty);
    }
  });
  test(
    'save roundtrip, midnight, missions and history clearing retain progress',
    () {
      var saved = progress(
        DateTime(2026, 10, 20),
        const OyasumiProgress(completed: 2, lastNight: '2026-10-19'),
      );
      saved = Progress.decode(saved.encode())
          .onDay(DateTime(2026, 10, 21))
          .complete(Mission.hobby)
          .clearHistory()
          .markDialogueSeen('other');
      expect(saved.oyasumi.completed, 2);
      expect(saved.oyasumi.lastNight, '2026-10-19');
      final old = jsonDecode(saved.encode()) as Map<String, dynamic>;
      old.remove('oyasumi');
      expect(Progress.decode(jsonEncode(old)).oyasumi.completed, 0);
      expect(
        () => OyasumiProgress.fromJson({
          'completed': 1,
          'lastNight': '2026-02-30',
        }),
        throwsFormatException,
      );
    },
  );
  test('failed saves do not publish progress; stale completion cannot advance twice', () async {
    final now = DateTime(2026, 10, 20, 19);
    final store = MemoryStore()
      ..raw = progress(now, const OyasumiProgress()).encode();
    final controller = ProgressController(store, clock: () => now);
    await controller.initialize();
    final old = store.raw;
    store.saveError = StateError('disk full');
    expect(await controller.completeOyasumi(scene(20), host, 'solo'), isFalse);
    expect(controller.progress!.oyasumi.completed, 0);
    expect(store.raw, old);
    controller.dispose();
    store.saveError = null;
    final retry = ProgressController(store, clock: () => now);
    await retry.initialize();
    expect(await retry.completeOyasumi(scene(20), host, 'solo'), isTrue);
    expect(await retry.completeOyasumi(scene(20), host, 'solo'), isFalse);
    expect(retry.progress!.oyasumi.completed, 1);
    retry.dispose();
  });
  testWidgets('actual game uses night art and saves only after final page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 930);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final now = DateTime(2026, 10, 20, 19);
    final store = MemoryStore()
      ..raw = progress(
        now,
        const OyasumiProgress(),
      ).markDialogueSeen('tutorial_kotohogisu_v1').encode();
    final controller = ProgressController(store, clock: () => now);
    await controller.initialize();
    await tester.pumpWidget(
      MaterialApp(
        home: FutureLiftHome(
          controller: controller,
          initialPage: 2,
          enableTutorial: false,
          dialogueCatalog: DialogueCatalog.fromJson(
            jsonEncode({
              'version': 1,
              'dialogues': [
                for (final r in TownResident.values)
                  {
                    'id': r.id,
                    'residentId': r.id,
                    'text': 'こんにちは',
                    'priority': 0,
                    'once': false,
                    'logic': 'all',
                    'conditions': [],
                  },
              ],
            }),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final background = tester.widget<Image>(
      find.byKey(const ValueKey('town-background')),
    );
    expect(
      (background.image as AssetImage).assetName,
      'assets/kotohogu/town_background_night.jpg',
    );
    await tester.tap(find.byTooltip(host.label));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.progress!.oyasumi.completed, 0);
    // Dismiss without reaching final page: no progress.
    Navigator.of(tester.element(find.byType(AlertDialog))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(controller.progress!.oyasumi.completed, 0);
    await tester.tap(find.byTooltip(host.label));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    for (
      var i = 0;
      i < 12 && find.byType(AlertDialog).evaluate().isNotEmpty;
      i++
    ) {
      await tester.tap(find.byType(AlertDialog));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(controller.progress!.oyasumi.completed, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
