import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:future_lift/celebration.dart';
import 'package:future_lift/celebration_updates.dart';
import 'package:future_lift/dialogue_engine.dart';
import 'package:future_lift/main.dart';
import 'package:future_lift/oyasumi_club.dart';
import 'package:future_lift/oyasumi_config.g.dart';
import 'package:future_lift/progress.dart';
import 'package:future_lift/resident_collection.dart';

import 'progress_test.dart' show MemoryStore;

final testNow = DateTime(2026, 10, 9, 19);

Progress savedAt(
  int points, {
  bool withClub = false,
  OyasumiProgress club = const OyasumiProgress(),
}) => Progress(
  day: '2026-10-09',
  lastCompletedDay: points == 0 ? null : '2026-10-08',
  points: points,
  completed: const {},
  residents: ResidentCollection(
    baselinePoints: 0,
    counts: {
      '001_shiba': 1,
      '002_usagi': 1,
      if (withClub) OyasumiScene.host.id: 1,
      if (withClub) OyasumiScene.frog.id: 1,
    },
  ),
  oyasumi: club,
);

List<CelebrationUpdate> changes(Progress before, Progress after) =>
    celebrationUpdates(
      before: before,
      after: after,
      clubConfig: oyasumiConfig,
      now: testNow,
    );

void main() {
  test('crossing a town threshold announces only newly opened areas', () {
    final updates = changes(savedAt(380), savedAt(390));
    expect(updates.map((u) => u.id), ['area-library']);
    expect(updates.single.title, 'ことほぎ図書館が開放されました！');
    expect(changes(savedAt(390), savedAt(400)), isEmpty);
    expect(changes(savedAt(40), savedAt(50)), isEmpty);
  });

  test('public community center unlock is also announced once', () {
    final updates = changes(savedAt(230), savedAt(240));
    expect(updates.map((u) => u.id), ['community-center']);
    expect(updates.single.title, '公民館が開放されました！');
    expect(changes(savedAt(240), savedAt(250)), isEmpty);
  });

  test('club is announced when points make the next chapter ready', () {
    const club = OyasumiProgress(
      completed: 1,
      lastNight: '2026-10-08',
      lastKotohogi: 100,
    );
    expect(changes(
      savedAt(120, withClub: true, club: club),
      savedAt(130, withClub: true, club: club),
    ).map((u) => u.id), ['oyasumi-club']);
    expect(changes(
      savedAt(130, withClub: true, club: club),
      savedAt(140, withClub: true, club: club),
    ), isEmpty);
  });

  test('club is not announced without the real event residents', () {
    const club = OyasumiProgress(
      completed: 1,
      lastNight: '2026-10-08',
      lastKotohogi: 100,
    );
    expect(changes(savedAt(120, club: club), savedAt(130, club: club)), isEmpty);
  });

  test('backward lifetime progress fails instead of inventing an unlock', () {
    expect(() => changes(savedAt(390), savedAt(380)), throwsStateError);
  });

  testWidgets('celebration displays change notices beneath the reward',
      (tester) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(
      home: Celebration(
        missionTitle: '歩いた',
        total: 390,
        residents: [],
        updates: [
          CelebrationUpdate(
            id: 'area-library',
            symbol: '🗺️',
            title: 'ことほぎ図書館が開放されました！',
            detail: '新しい場所に行けるようになりました。',
          ),
          CelebrationUpdate(
            id: 'oyasumi-club',
            symbol: '🌙',
            title: 'おやすみクラブに新しいお話！',
            detail: '夜の中央ひろばへ。',
          ),
        ],
      ),
    ));
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byKey(const ValueKey('celebration-updates')), findsOneWidget);
    expect(find.text('ことほぎ図書館が開放されました！'), findsOneWidget);
    expect(find.text('おやすみクラブに新しいお話！'), findsOneWidget);
    expect(find.byKey(const ValueKey('close-celebration')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ordinary celebration has no change notice', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Celebration(missionTitle: '歩いた', total: 10, residents: []),
    ));
    expect(find.byKey(const ValueKey('celebration-updates')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mission completion passes real unlocks to celebration', (tester) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final store = MemoryStore()..raw = savedAt(380).encode();
    final controller = ProgressController(store, clock: () => testNow);
    final catalog = await tester.runAsync(DialogueCatalog.load);
    if (catalog == null) throw StateError('Dialogue catalog did not load');
    await tester.pumpWidget(FutureLiftApp(
      controller: controller,
      dialogueCatalog: catalog,
      enableTutorial: false,
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('footer-missions')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('complete-strength')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(controller.progress!.points, 390);
    expect(find.text('ことほぎ図書館が開放されました！'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('close-celebration')));
    await tester.pumpAndSettle();
    expect(Progress.decode(store.raw!).points, 390);
    expect(tester.takeException(), isNull);
  });
}
