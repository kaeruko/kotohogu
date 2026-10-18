import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:future_lift/celebration.dart';
import 'package:future_lift/clap_characters.dart';
import 'package:future_lift/main.dart';
import 'package:future_lift/gacha_hud.dart';
import 'package:future_lift/home_skin.dart';
import 'package:future_lift/missions_screen.dart';
import 'package:future_lift/history_screen.dart';
import 'package:future_lift/kotohogisu_tutorial.dart';
import 'package:future_lift/dialogue_engine.dart';
import 'package:future_lift/progress.dart';
import 'package:future_lift/resident_collection.dart';
import 'package:future_lift/residents.dart';
import 'package:future_lift/town.dart';

import 'progress_test.dart' show MemoryStore;

void main() {
  test('all confetti particles fall completely past the screen by the end', () {
    // Use the same deterministic random stream and particle timing as the painter.
    final random = math.Random(31);
    const height = 900.0;
    for (var i = 0; i < 110; i++) {
      random.nextDouble(); // start X
      final delay = random.nextDouble() * .38;
      final exponent = .7 + random.nextDouble() * .65;
      random.nextDouble(); // horizontal drift

      expect(confettiFallFraction(0, delay, exponent), 0);
      expect(confettiFallY(0, delay, exponent, height), -30);
      var previous = -30.0;
      for (var step = 1; step <= 100; step++) {
        final y = confettiFallY(step / 100, delay, exponent, height);
        expect(
          y,
          greaterThanOrEqualTo(previous),
          reason: 'Particle $i at $step%',
        );
        previous = y;
      }
      expect(confettiFallFraction(.99, delay, exponent), lessThan(1));
      expect(confettiFallFraction(1, delay, exponent), 1);
      // The painter culls particles beyond height + 35.
      expect(
        confettiFallY(1, delay, exponent, height),
        greaterThan(height + 35),
        reason: 'Particle $i stayed visible',
      );
    }
  });

  testWidgets('researched cost illustration accompanies applause', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() => tester.view.reset());

    await tester.pumpWidget(
      const MaterialApp(
        home: Celebration(
          missionTitle: '筋力を使った',
          total: 10,
          residents: [],
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));

    expect(
      find.text('🎊 日本の社会保障に貢献！ 🎊').hitTestable(),
      findsOneWidget,
    );
    expect(find.text('社会保障に貢献しました！'), findsOneWidget);
    // Celebration uses the same full-screen wallpaper as the missions list.
    final celebrationBackground = tester.widget<Image>(
      find.byKey(const ValueKey('celebration-background')),
    );
    expect(
      (celebrationBackground.image as AssetImage).assetName,
      MissionsScreen.backgroundAsset,
    );
    expect(celebrationBackground.fit, BoxFit.cover);
    expect(find.byKey(const ValueKey('close-celebration')), findsOneWidget);
    expect(
      find.text('参考推計：医療・介護費 年間約81,000円（研究集団の比較）'),
      findsOneWidget,
    );
    expect(find.textContaining('研究2件の集団間費用差'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('up to eight sprites clap in sequence and respect reduced motion', (
    tester,
  ) async {
    Future<void> show(double phase, {bool reduced = false}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: ClapCharacters(phase: phase, reduced: reduced),
            ),
          ),
        ),
      );
    }

    int frame() => tester
        .widget<IndexedStack>(find.byKey(const ValueKey('clap-01_shiba')))
        .index!;

    await show(0);
    expect(find.byType(IndexedStack), findsNWidgets(applauseResidentLimit));
    expect(frame(), 0);
    await show(.25);
    expect(frame(), 1);
    await show(.5);
    expect(frame(), 0);
    await show(.75);
    expect(frame(), 1);
    await show(0, reduced: true);
    expect(
      tester
          .widgetList<IndexedStack>(find.byType(IndexedStack))
          .every((sprite) => sprite.index == 1),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  Future<ProgressController> launch(
    WidgetTester tester,
    MemoryStore store, {
    bool showTutorial = false,
  }) async {
    final controller = ProgressController(
      store,
      clock: () => DateTime(2026, 10, 9, 12),
    );
    final catalog = await tester.runAsync(DialogueCatalog.load);
    if (catalog == null) throw StateError('Dialogue asset did not load');
    await tester.pumpWidget(FutureLiftApp(
      controller: controller,
      dialogueCatalog: catalog,
      enableTutorial: showTutorial,
    ));
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets('bottom navigation shows icons without visible labels',
      (tester) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await launch(tester, MemoryStore());
    final nav = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(nav.labelBehavior, NavigationDestinationLabelBehavior.alwaysHide);
    expect(tester.getSize(find.byType(NavigationBar)).height, 80);
    expect(
      nav.destinations.map((destination) =>
          (destination as NavigationDestination).label).toList(),
      ['ホーム', 'ミッション', 'みんなのまち', '履歴', 'メニュー'],
    );
    for (final id in [
      'footer-home', 'footer-missions', 'footer-town',
      'footer-history', 'footer-menu',
    ]) {
      expect(find.byKey(ValueKey(id)), findsOneWidget);
    }

    await tester.tap(find.byKey(const ValueKey('footer-missions')));
    await tester.pumpAndSettle();
    expect(tester.widget<NavigationBar>(find.byType(NavigationBar))
        .selectedIndex, 1);
    expect(find.byType(MissionsScreen), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('footer-home')));
    await tester.pumpAndSettle();
    expect(tester.widget<NavigationBar>(find.byType(NavigationBar))
        .selectedIndex, 0);
    expect(tester.takeException(), isNull);
  });


  testWidgets('missions and history use the park artwork, developer page retains its own',
      (tester) async {
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await launch(tester, MemoryStore());
    final wallpaper = find.byKey(const ValueKey('shared-page-background'));

    String displayedAsset() =>
        (tester.widget<Image>(wallpaper).image as AssetImage).assetName;

    await tester.tap(find.byKey(const ValueKey('footer-missions')));
    await tester.pumpAndSettle();
    expect(find.byType(MissionsScreen), findsOneWidget);
    expect(displayedAsset(), MissionsScreen.backgroundAsset);
    expect(tester.getRect(wallpaper).contains(
        tester.getCenter(find.byType(GachaHud))), isTrue);

    await tester.tap(find.byKey(const ValueKey('footer-history')));
    await tester.pumpAndSettle();
    expect(find.byType(HistoryScreen), findsOneWidget);
    expect(displayedAsset(), MissionsScreen.backgroundAsset);
    expect(tester.getRect(wallpaper).contains(
        tester.getCenter(find.byType(GachaHud))), isTrue);

    await tester.tap(find.byKey(const ValueKey('footer-menu')));
    await tester.pumpAndSettle();
    expect(displayedAsset(), 'assets/kotohogu/town_background.png');
    await tester.tap(find.byKey(const ValueKey('footer-missions')));
    await tester.pumpAndSettle();
    expect(displayedAsset(), MissionsScreen.backgroundAsset);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('standalone mission preview also uses the park artwork',
      (tester) async {
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MissionsScreen(
          progress: Progress.empty(DateTime(2026, 10, 16)),
          busy: false,
          onComplete: (_) {},
          period: MissionPeriod.daily,
          onPeriodChanged: (_) {},
        ),
      ),
    ));
    final background = tester.widget<Image>(
        find.byKey(const ValueKey('mission-background')));
    expect((background.image as AssetImage).assetName,
        MissionsScreen.backgroundAsset);
    expect(background.fit, BoxFit.cover);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('standalone history also uses the mission park wallpaper',
      (tester) async {
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HistoryScreen(
          progress: Progress.empty(DateTime(2026, 10, 16)),
          busy: false,
          onClear: () async {},
        ),
      ),
    ));
    final background = tester.widget<Image>(
        find.byKey(const ValueKey('history-background')));
    expect((background.image as AssetImage).assetName,
        MissionsScreen.backgroundAsset);
    expect(background.fit, BoxFit.cover);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('all five main pages share one header size and position',
      (tester) async {
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await launch(tester, MemoryStore());

    expect(find.byType(GachaHud), findsOneWidget);
    expect(find.byType(PlayerNameplate), findsOneWidget);
    expect(find.byType(KotohogiBar), findsOneWidget);
    final initialHeader = tester.getRect(find.byType(GachaHud));
    final initialName = tester.getRect(find.byType(PlayerNameplate));
    final initialBalance = tester.getRect(find.byType(KotohogiBar));
    expect(find.text('ハル'), findsOneWidget);

    for (final tab in [
      'footer-missions', 'footer-town', 'footer-history',
      'footer-menu', 'footer-home',
    ]) {
      await tester.tap(find.byKey(ValueKey(tab)));
      await tester.pumpAndSettle();
      expect(find.byType(GachaHud), findsOneWidget, reason: tab);
      expect(find.byType(PlayerNameplate), findsOneWidget, reason: tab);
      expect(find.byType(KotohogiBar), findsOneWidget, reason: tab);
      final header = tester.getRect(find.byType(GachaHud));
      final name = tester.getRect(find.byType(PlayerNameplate));
      final amount = tester.getRect(find.byType(KotohogiBar));
      expect(header.left, closeTo(initialHeader.left, .01), reason: tab);
      expect(header.top, closeTo(initialHeader.top, .01), reason: tab);
      expect(header.width, closeTo(initialHeader.width, .01), reason: tab);
      expect(name, initialName, reason: tab);
      expect(amount, initialBalance, reason: tab);
      expect(find.byKey(const ValueKey('total-points')), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('home, missions and town show one spendable balance',
      (tester) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // 190 points earned, 60 spent on two draws, 130 available.
    final seed = Progress(
      day: '2026-10-09',
      lastCompletedDay: '2026-10-08',
      points: 190,
      residents: ResidentCollection(
        baselinePoints: 0,
        counts: const {'01_shiba': 2, '02_rabbit': 2},
      ),
      completed: const {},
    );
    final store = MemoryStore()..raw = seed.encode();
    final controller = await launch(tester, store);
    final originalSave = store.raw;
    final originalWrites = store.writes;
    expect(controller.progress!.points, 190);
    expect(controller.progress!.residents.availableKotohogi(190), 130);

    void expectBalance() {
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('total-points'))).data,
        '130',
      );
    }

    expectBalance(); // Home
    await tester.tap(find.byKey(const ValueKey('footer-missions')));
    await tester.pumpAndSettle();
    expectBalance(); // Mission header
    await tester.tap(find.byKey(const ValueKey('footer-town')));
    await tester.pumpAndSettle();
    expectBalance(); // Town
    await tester.tap(find.byKey(const ValueKey('footer-home')));
    await tester.pumpAndSettle();
    expectBalance(); // Return home

    expect(store.raw, originalSave);
    expect(store.writes, originalWrites);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('celebration displays spendable 120, not lifetime 180',
      (tester) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // Two past gacha draws spent 60 of the 170 lifetime points.
    final seed = Progress(
      day: '2026-10-09',
      lastCompletedDay: '2026-10-08',
      points: 170,
      residents: ResidentCollection(
        baselinePoints: 0,
        counts: const {'01_shiba': 2, '02_rabbit': 2},
      ),
      completed: const {},
    );
    final store = MemoryStore()..raw = seed.encode();
    final controller = await launch(tester, store);
    expect(controller.progress!.residents.availableKotohogi(170), 110);

    await tester.tap(find.byKey(const ValueKey('footer-missions')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('complete-strength')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(controller.progress!.points, 180);
    expect(controller.progress!.residents.availableKotohogi(180), 120);
    expect(
      find.descendant(
        of: find.byType(Celebration),
        matching: find.text('ことほぎ +10'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('celebration-spendable-balance')),
        findsOneWidget);
    expect(find.text('所持ことほぎ  120'), findsOneWidget);
    expect(find.text('所持ことほぎ  180'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('close-celebration')));
    await tester.pumpAndSettle();
    expect(controller.progress!.residents.availableKotohogi(
        controller.progress!.points), 120);
    expect(Progress.decode(store.raw!).residents.availableKotohogi(180), 120);
    expect(tester.takeException(), isNull);
  });

  testWidgets('town companions speak one at a time', (tester) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final defaults = [
      for (final resident in TownResident.values)
        {
          'id': '${resident.id}_fallback',
          'residentId': resident.id,
          'text': 'ふつうのおはなし',
          'priority': 0,
          'once': false,
          'logic': 'all',
          'conditions': [],
        },
    ];
    final catalogue = DialogueCatalog.fromJson(jsonEncode({
      'version': 1,
      'dialogues': [
        ...defaults,
        {
          'id': '01_shiba_001',
          'residentId': '01_shiba',
          'text': '今日は雲を眺めようよ',
          'priority': 20,
          // Make this two-turn fixture a first-time event so the widget test
          // verifies dialogue advance, not the separate random draw behavior.
          'once': true,
          'logic': 'all',
          'conditions': [
            {'type': 'townTogether', 'otherResidentId': '02_rabbit'},
          ],
          'reply': {
            'residentId': '02_rabbit', 'text': 'あの雲、描いてみたい！',
          },
        },
      ],
    }));
    final controller = ProgressController(
      MemoryStore(), clock: () => DateTime(2026, 10, 15, 12));
    await tester.pumpWidget(FutureLiftApp(
      controller: controller,
      dialogueCatalog: catalogue,
      enableTutorial: false,
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('footer-town')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('resident-0')));
    await tester.pumpAndSettle();
    final dialogue = find.byType(AlertDialog);
    expect(find.descendant(of: dialogue, matching: find.text('しばいぬ')),
        findsOneWidget);
    expect(find.text('今日は雲を眺めようよ'), findsOneWidget);
    expect(find.text('あの雲、描いてみたい！'), findsNothing);
    expect(find.text('1 / 2'), findsOneWidget);
    await tester.tap(find.text('つぎへ'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: dialogue, matching: find.text('うさぎ')),
        findsOneWidget);
    expect(find.text('今日は雲を眺めようよ'), findsNothing);
    expect(find.text('あの雲、描いてみたい！'), findsOneWidget);
    expect(find.text('2 / 2'), findsOneWidget);
    await tester.tap(find.text('また話そう'));
    await tester.pumpAndSettle();
    expect(dialogue, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('core journey: missions, celebration, +10, town, tip, restart', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() => tester.view.reset());
    final store = MemoryStore();
    final controller = await launch(tester, store);
    await tester.tap(find.byKey(const ValueKey('footer-missions')));
    await tester.pumpAndSettle();
    for (final mission in Mission.forPeriod(MissionPeriod.daily)) {
      await tester.scrollUntilVisible(find.text(mission.title), 200);
      expect(find.text(mission.title), findsOneWidget);
    }
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('complete-strength')),
      -250,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('complete-strength')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(
      find.text('🎊 日本の社会保障に貢献！ 🎊').hitTestable(),
      findsOneWidget,
    );
    expect(find.text('社会保障に貢献しました！'), findsOneWidget);
    expect(
      find.text('参考推計：医療・介護費 年間約81,000円（研究集団の比較）'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('ミッション達成！ 日本の社会保障に貢献！'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(Celebration),
        matching: find.text('ことほぎ +10'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(Celebration),
        matching: find.byType(ClapCharacters),
      ),
      findsOneWidget,
    );
    expect(controller.progress!.points, 10);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('close-celebration')));
    await tester.pumpAndSettle();
    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('complete-strength')),
    );
    expect(button.onPressed, isNull);
    expect(find.text('できた！  達成済み'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('footer-home')));
    await tester.pumpAndSettle();
    // On shorter screens, the larger currency/ticket HUD reserves more
    // vertical space. The bottom home action remains reachable by scrolling.
    await tester.ensureVisible(find.byKey(const ValueKey('open-missions')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('open-missions')).hitTestable(),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('footer-town')));
    await tester.pumpAndSettle();
    expect(tester.widget<TownScene>(find.byType(TownScene)).level, 0);
    final background = tester.widget<Image>(
      find.descendant(
        of: find.byType(TownScene),
        matching: find.byKey(const ValueKey('town-background')),
      ),
    );
    expect(background.image, isA<AssetImage>());
    expect(
      (background.image as AssetImage).assetName,
      'assets/kotohogu/town_background_001.jpg',
    );
    expect(background.fit, BoxFit.cover);
    await tester.tap(find.byKey(const ValueKey('resident-0')));
    await tester.pumpAndSettle();
    expect(find.text(Resident.child.tips.first), findsOneWidget);
    // Ordinary repeatable dialogue IDs are now saved for global prerequisites.
    expect(controller.progress!.seenDialogues, contains('shiba_default_1'));
    await tester.tap(find.text('また話そう'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('resident-0')));
    await tester.pumpAndSettle();
    expect(find.text(Resident.child.tips[1]), findsOneWidget);
    await tester.tap(find.text('また話そう'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    final restarted = await launch(tester, store);
    expect(restarted.progress!.completed, {Mission.strength});
    expect(restarted.progress!.points, 10);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final size in <Size>[
    const Size(320, 720),
    const Size(360, 720),
    const Size(402, 874),
  ]) {
    testWidgets('town fills the first screen without duplicate titles at $size',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await launch(tester, MemoryStore());
      await tester.tap(find.byKey(const ValueKey('footer-town')));
      await tester.pumpAndSettle();

      // The footer is icon-only; selected destinations still have a label
      // for semantics and identification.
      expect(tester.widget<NavigationBar>(find.byType(NavigationBar))
          .selectedIndex, 2);
      expect(find.text(townNames.first), findsOneWidget);
      expect(find.text('LEVEL 0'), findsOneWidget);
      expect(find.byKey(const ValueKey('town-page-shrine-background')),
          findsNothing);
      final art = find.byType(TownScene);
      expect(tester.widget<TownScene>(art).fillViewport, isTrue);
      final scene = tester.getRect(art);
      final fullScreen = tester.getRect(
        find.byKey(const ValueKey('town-page-fullscreen')),
      );
      final nav = tester.getRect(find.byType(NavigationBar));
      expect(scene.left, closeTo(fullScreen.left, .1));
      expect(scene.top, closeTo(fullScreen.top, .1));
      expect(scene.width, closeTo(fullScreen.width, .1));
      expect(scene.height, closeTo(fullScreen.height, .1));
      expect(fullScreen.width, closeTo(size.width, .1));
      expect(fullScreen.bottom, lessThanOrEqualTo(nav.top + .1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'storage failure displays halt and original diagnostics, no celebration',
    (tester) async {
      await launch(tester, MemoryStore()..saveError = StateError('disk full'));
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('open-missions')),
        150,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open-missions')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('complete-strength')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('complete-strength')));
      await tester.pumpAndSettle();
      expect(find.text('記録を確認できないため、停止しました'), findsOneWidget);
      expect(find.byType(Celebration), findsNothing);
      await tester.tap(find.text('診断情報'));
      await tester.pumpAndSettle();
      expect(find.textContaining('disk full'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('compact screen, large text and reduced motion remain usable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = ProgressController(
      MemoryStore(),
      clock: () => DateTime(2026, 10, 9),
    );
    final catalog = await tester.runAsync(DialogueCatalog.load);
    if (catalog == null) throw StateError('Dialogue asset did not load');
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.5),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: FutureLiftHome(
          controller: controller,
          dialogueCatalog: catalog,
          enableTutorial: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('footer-missions')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('complete-strength')),
      150,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('complete-strength')));
    await tester.pumpAndSettle();
    expect(find.byType(Celebration), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('close-celebration')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('close-celebration')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('footer-town')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('resident-0')),
      100,
    );
    // This page intentionally paints behind the pinned currency HUD.
    // Bring the sprite to the visible middle before tapping, not directly
    // underneath the overlay at the top of the scrollable.
    await Scrollable.ensureVisible(
      tester.element(find.byKey(const ValueKey('resident-0'))),
      alignment: .5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('resident-0')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'journal shows only celebrations and deletion preserves progress',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final saved = Progress(
        day: '2026-10-09',
        lastCompletedDay: '2026-10-09',
        points: 30,
        completed: {Mission.strength},
        history: {
          '2026-09-30': {Mission.outside},
          '2026-10-09': {Mission.strength},
        },
      );
      final store = MemoryStore()..raw = saved.encode();
      final controller = await launch(tester, store);
      await tester.tap(find.byKey(const ValueKey('footer-history')));
      await tester.pumpAndSettle();
      expect(find.text('これまで言祝がれた日々'), findsOneWidget);
      expect(find.text('直近30日は 2日、2個の行動を言祝ぎました。'), findsOneWidget);
      expect(find.text('今月は1日、1個の行動を言祝ぎました。'), findsOneWidget);
      expect(find.text('祝'), findsOneWidget);
      expect(find.text('×'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('previous-history-month')));
      await tester.pumpAndSettle();
      expect(find.text('2026年9月'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('history-day-30')));
      await tester.pumpAndSettle();
      expect(find.text('外に出た・歩いた'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('next-history-month')));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('clear-history')),
        160,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('history-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('clear-history')));
      await tester.pumpAndSettle();
      expect(find.text('すべての履歴を削除しますか？'), findsOneWidget);
      await tester.tap(find.text('やめる'));
      await tester.pumpAndSettle();
      expect(controller.progress!.history.length, 2);

      await tester.tap(find.byKey(const ValueKey('clear-history')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-clear-history')));
      await tester.pumpAndSettle();
      expect(controller.progress!.history, isEmpty);
      expect(controller.progress!.points, 30);
      expect(controller.progress!.completed, {Mission.strength});
      expect(Progress.decode(store.raw!).history, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('three mission periods can be selected and celebrated', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = MemoryStore();
    final controller = await launch(tester, store);
    await tester.tap(find.byKey(const ValueKey('footer-missions')));
    await tester.pumpAndSettle();
    expect(find.text(Mission.movement.title), findsOneWidget);
    expect(find.text('いつもより身体を動かした'), findsNothing);
    expect(find.text('0/7 言祝ぎ'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('mission-tab-weekly')));
    await tester.pumpAndSettle();
    expect(find.text('0/4 言祝ぎ'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('complete-weeklyStrength')),
      160,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('complete-weeklyStrength')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byType(Celebration), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('close-celebration')));
    await tester.pumpAndSettle();
    expect(controller.progress!.weeklyCompleted, {Mission.weeklyStrength});

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('mission-tab-monthly')),
      -180,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mission-tab-monthly')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('mission-period-progress')),
      -100,
    );
    await tester.pumpAndSettle();
    expect(find.text('0/3 言祝ぎ'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text(Mission.monthlyReview.title),
      160,
    );
    expect(find.text(Mission.monthlyReview.title), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('debug menu replays thanks without changing points or history', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final original = Progress.empty(DateTime(2026, 10, 9))
        .complete(Mission.strength);
    final store = MemoryStore()..raw = original.encode();
    final controller = await launch(tester, store);

    await tester.tap(find.byKey(const ValueKey('footer-menu')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('debug-replay-celebration')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('debug-current-points')),
        findsOneWidget);
    expect(
      tester.widget<Text>(
        find.byKey(const ValueKey('debug-current-points')),
      ).data,
      contains('所持ことほぎ：10'),
    );
    final saved = store.raw;
    final writes = store.writes;

    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byKey(const ValueKey('debug-replay-celebration')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      final celebration = tester.widget<Celebration>(find.byType(Celebration));
      expect(celebration.preview, isTrue);
      expect(celebration.total, 10);
      expect(celebration.missionTitle, Mission.strength.title);
      expect(find.byKey(const ValueKey('debug-preview-label')), findsOneWidget);
      expect(find.byKey(const ValueKey('close-celebration')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('close-celebration')));
      await tester.pumpAndSettle();
      expect(controller.progress!.points, 10);
      expect(controller.progress!.completed, {Mission.strength});
      expect(controller.progress!.history['2026-10-09'], {Mission.strength});
      expect(store.writes, writes);
      expect(store.raw, saved);
    }

    await tester.tap(find.byKey(const ValueKey('debug-preview-mission')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(Mission.outside.title).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('debug-replay-celebration')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    final different = tester.widget<Celebration>(find.byType(Celebration));
    expect(different.missionTitle, Mission.outside.title);
    expect(different.total, 10);
    await tester.tap(find.byKey(const ValueKey('close-celebration')));
    await tester.pumpAndSettle();
    expect(store.writes, writes);
    expect(store.raw, saved);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('town HUD shows only the spendable kotohogi on small phones', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = MemoryStore();
    final controller = await launch(tester, store);
    await tester.tap(find.byKey(const ValueKey('footer-town')));
    await tester.pumpAndSettle();

    final nameplate = find.byKey(const ValueKey('gacha-player-nameplate'));
    final art = find.byKey(const ValueKey('kotohogi-bar-art'));
    final amount = find.byKey(const ValueKey('total-points'));
    expect(find.byKey(const ValueKey('town-page-fullscreen')), findsOneWidget);
    expect(find.byKey(const ValueKey('town-background')), findsOneWidget);
    expect(nameplate, findsOneWidget);
    expect(art, findsOneWidget);
    expect(find.byKey(const ValueKey('kotohogi-bar-label')), findsNothing);
    expect(tester.widget<Text>(amount).data, '0');
    expect(find.textContaining('ガチャ券'), findsNothing);
    expect(tester.getRect(nameplate).right,
        lessThan(tester.getRect(art).left));
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('footer-menu')));
    await tester.pumpAndSettle();
    final addCurrency = find.byKey(const ValueKey('debug-add-ticket-10'));
    await tester.ensureVisible(addCurrency);
    await tester.pumpAndSettle();
    await tester.tap(addCurrency);
    await tester.pumpAndSettle();
    expect(controller.progress!.residents.availableKotohogi(0), 300);
    await tester.tap(find.byKey(const ValueKey('footer-town')));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(amount).data, '300');
    expect(find.textContaining('ガチャ券'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('debug currency buttons update and persist balance without lifetime points', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = MemoryStore();
    final controller = await launch(tester, store);
    await tester.tap(find.byKey(const ValueKey('footer-menu')));
    await tester.pumpAndSettle();

    final plusOne = find.byKey(const ValueKey('debug-add-ticket-1'));
    final plusTen = find.byKey(const ValueKey('debug-add-ticket-10'));
    await tester.ensureVisible(plusOne);
    await tester.pumpAndSettle();
    await tester.tap(plusOne);
    await tester.pumpAndSettle();
    expect(controller.progress!.residents.tickets(0), 1);
    expect(find.text('所持ことほぎ：30'), findsOneWidget);
    expect(find.text('ガチャ券 +1枚'), findsNothing);
    await tester.ensureVisible(plusTen);
    await tester.tap(plusTen);
    await tester.pumpAndSettle();
    expect(controller.progress!.residents.tickets(0), 11);
    expect(controller.progress!.residents.availableKotohogi(0), 330);
    expect(controller.progress!.points, 0);
    expect(controller.progress!.history, isEmpty);
    expect(store.writes, 2);
    expect(Progress.decode(store.raw!).residents.tickets(0), 11);
    expect(Progress.decode(store.raw!).residents.availableKotohogi(0), 330);

    await tester.tap(find.byKey(const ValueKey('footer-town')));
    await tester.pumpAndSettle();
    expect(
      controller.progress!.residents.tickets(controller.progress!.points),
      11,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('debug menu reset confirms and clears mission flags only', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final original = Progress.empty(DateTime(2026, 10, 9))
        .complete(Mission.strength)
        .complete(Mission.weeklyStrength)
        .complete(Mission.monthlyReview);
    final store = MemoryStore()..raw = original.encode();
    final controller = await launch(tester, store);
    await tester.tap(find.byKey(const ValueKey('footer-menu')));
    await tester.pumpAndSettle();
    final reset = find.byKey(const ValueKey('debug-reset-all-missions'));
    await tester.ensureVisible(reset);
    await tester.pumpAndSettle();
    await tester.tap(reset);
    await tester.pumpAndSettle();
    expect(find.text('全ミッションをリセットしますか？'), findsOneWidget);
    expect(find.textContaining('ことほぎが再び加算'), findsOneWidget);
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect(controller.progress!.completed, {Mission.strength});
    expect(controller.progress!.weeklyCompleted, {Mission.weeklyStrength});
    expect(controller.progress!.monthlyCompleted, {Mission.monthlyReview});
    expect(store.writes, 0);

    await tester.tap(reset);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('debug-confirm-reset-missions')),
    );
    await tester.pumpAndSettle();
    expect(find.text('全ミッションの達成状態をリセットしました'), findsOneWidget);
    expect(controller.progress!.completed, isEmpty);
    expect(controller.progress!.weeklyCompleted, isEmpty);
    expect(controller.progress!.monthlyCompleted, isEmpty);
    expect(controller.progress!.points, 30);
    expect(controller.progress!.history, original.history);
    expect(store.writes, 1);
    final restored = Progress.decode(store.raw!);
    expect(restored.completed, isEmpty);
    expect(restored.weeklyCompleted, isEmpty);
    expect(restored.monthlyCompleted, isEmpty);
    expect(restored.history, original.history);

    await tester.tap(find.byKey(const ValueKey('footer-missions')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('complete-strength')),
      160,
    );
    await tester.pumpAndSettle();
    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('complete-strength')),
    );
    expect(button.onPressed, isNotNull);
    await tester.tap(find.byKey(const ValueKey('complete-strength')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byType(Celebration), findsOneWidget);
    expect(controller.progress!.points, 40);
    await tester.tap(find.byKey(const ValueKey('close-celebration')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  test('sixteen non-duplicate fixed tips are available', () {
    expect(Resident.values.expand((r) => r.tips).toSet().length, 16);
  });
  testWidgets('Kotohogisu appears once and guides to missions', (tester) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() => tester.view.reset());
    final store = MemoryStore();
    final controller = await launch(tester, store, showTutorial: true);
    expect(find.byKey(const ValueKey('kotohogisu-tutorial')), findsOneWidget);
    expect(find.textContaining('ぼくはコトホギス'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('kotohogisu-next')));
    await tester.pumpAndSettle();
    expect(find.textContaining('ミッション」で教えてね'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('kotohogisu-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('kotohogisu-next')));
    await tester.pumpAndSettle();
    expect(controller.progress!.seenDialogues, contains('tutorial_kotohogisu_v1'));
    expect(find.byKey(const ValueKey('kotohogisu-tutorial')), findsNothing);
    expect(find.byKey(const ValueKey('complete-strength')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await launch(tester, store, showTutorial: true);
    expect(find.byKey(const ValueKey('kotohogisu-tutorial')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Kotohogisu skip keeps points unchanged', (tester) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() => tester.view.reset());
    final store = MemoryStore();
    final controller = await launch(tester, store, showTutorial: true);
    await tester.tap(find.byKey(const ValueKey('kotohogisu-skip')));
    await tester.pumpAndSettle();
    expect(controller.progress!.seenDialogues, contains('tutorial_kotohogisu_v1'));
    expect(controller.progress!.points, 0);
    expect(find.byKey(const ValueKey('kotohogisu-tutorial')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('debug tutorial replay is repeatable and never writes progress', (tester) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final initial = Progress.empty(DateTime(2026, 10, 9))
        .complete(Mission.strength)
        .markDialogueSeen('tutorial_kotohogisu_v1');
    final original = initial.encode();
    final store = MemoryStore()..raw = original;
    final controller = await launch(tester, store, showTutorial: true);
    expect(find.byKey(const ValueKey('kotohogisu-tutorial')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('footer-menu')));
    await tester.pumpAndSettle();
    final replay = find.byKey(const ValueKey('debug-replay-tutorial'));
    await tester.ensureVisible(replay);
    await tester.pumpAndSettle();
    await tester.tap(replay);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('kotohogisu-tutorial')), findsOneWidget);
    expect(find.textContaining('ぼくはコトホギス'), findsOneWidget);

    // Navigation cannot leave the replay before the user finishes or skips.
    await tester.tap(find.byKey(const ValueKey('footer-missions')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('kotohogisu-tutorial')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('kotohogisu-skip')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('kotohogisu-tutorial')), findsNothing);
    expect(find.byKey(const ValueKey('open-missions')), findsOneWidget);
    expect(store.writes, 0);
    expect(store.raw, original);

    await tester.tap(find.byKey(const ValueKey('footer-menu')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(replay);
    await tester.pumpAndSettle();
    await tester.tap(replay);
    await tester.pumpAndSettle();
    expect(find.textContaining('ぼくはコトホギス'), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const ValueKey('kotohogisu-next')));
      await tester.pumpAndSettle();
    }
    expect(find.byKey(const ValueKey('kotohogisu-tutorial')), findsNothing);
    expect(find.byKey(const ValueKey('complete-strength')), findsOneWidget);
    expect(controller.progress!.points, initial.points);
    expect(controller.progress!.seenDialogues, initial.seenDialogues);
    expect(controller.progress!.completed, initial.completed);
    expect(store.writes, 0);
    expect(store.raw, original);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Kotohogisu sprite walks in, faces forward, and waves', (tester) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KotohogisuTutorial(
            onSkip: () {},
            onFinish: () {},
          ),
        ),
      ),
    );

    String displayedAsset() {
      final sprite = tester.widget<Image>(
        find.byKey(const ValueKey('kotohogisu-sprite')),
      );
      return (sprite.image as AssetImage).assetName;
    }

    expect(
      displayedAsset(),
      'assets/characters/013_kotohogisu/walk_left_01.png',
    );
    await tester.pump(const Duration(milliseconds: 350));
    expect(displayedAsset(), startsWith('assets/characters/013_kotohogisu/walk_left_'));
    await tester.pumpAndSettle();
    expect(
      displayedAsset(),
      'assets/characters/013_kotohogisu/idle_front_01.png',
    );
    await tester.tap(find.byKey(const ValueKey('kotohogisu-next')));
    await tester.pumpAndSettle();
    expect(
      displayedAsset(),
      'assets/characters/013_kotohogisu/clap_front_01.png',
    );
    await tester.tap(find.byKey(const ValueKey('kotohogisu-next')));
    await tester.pumpAndSettle();
    expect(
      displayedAsset(),
      'assets/characters/013_kotohogisu/clap_front_02.png',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Kotohogisu respects reduced motion with a still image', (tester) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: KotohogisuTutorial(onSkip: () {}, onFinish: () {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final image = tester.widget<Image>(
      find.byKey(const ValueKey('kotohogisu-sprite')),
    );
    expect(
      (image.image as AssetImage).assetName,
      'assets/characters/013_kotohogisu/idle_front_01.png',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

}
