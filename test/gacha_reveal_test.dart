import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:future_lift/consultation_scene.dart';
import 'package:future_lift/gacha_reveal.dart';
import 'package:future_lift/gacha_screen.dart';
import 'package:future_lift/gacha_hud.dart';
import 'package:future_lift/home_skin.dart';
import 'package:future_lift/progress.dart';
import 'package:future_lift/resident_gacha.dart';
import 'package:future_lift/resident_collection.dart';

import 'progress_test.dart' show MemoryStore;
import 'resident_collection_test.dart' show funded, FixedRandom;

void main() {
  Future<ProgressController> open(
    WidgetTester tester,
    MemoryStore store, {
    bool reduced = false,
  }) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = ProgressController(
      store,
      clock: () => DateTime(2026, 10, 11),
      random: FixedRandom(2),
    );
    await controller.initialize();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: reduced,
          ),
          child: child!,
        ),
        home: GachaScreen(controller: controller),
      ),
    );
    await tester.pump();
    return controller;
  }

  testWidgets('hall shows animated walkers and the new two art buttons',
      (tester) async {
    final controller = await open(
      tester,
      MemoryStore()..raw = funded(points: 60).encode(),
    );
    expect(find.byKey(const ValueKey('gacha-shrine-bg')), findsOneWidget);
    // The consultation HUD is pinned to the upper-right, with space
    // remaining to the left for the hall's sign and decoration.
    final hallHud = tester.getRect(find.byType(KotohogiBar));
    final hallHeader = tester.getRect(find.byType(GachaHud));
    final hallName = tester.getRect(find.byType(PlayerNameplate));
    expect(hallHeader.left, closeTo(12, .5));
    expect(hallHud.right, closeTo(348, .5));
    expect(hallHud.left, greaterThan(150));
    expect(hallName.right, lessThan(hallHud.left));
    expect(find.text('ハル'), findsOneWidget);
    expect(find.byKey(const ValueKey('consultation-stage')), findsOneWidget);
    expect(
      (tester.widget<Image>(
        find.byKey(const ValueKey('consultation-stage')),
      ).image as AssetImage).assetName,
      'assets/gacya/stage.png',
    );
    expect(find.byType(ConsultationBackground), findsOneWidget);
    for (var index = 0; index < 4; index++) {
      expect(find.byKey(ValueKey('consultation-walker-$index')),
          findsOneWidget);
    }
    expect(find.byKey(const ValueKey('gacha-draw-one')), findsOneWidget);
    expect(find.byKey(const ValueKey('resident-list-button')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('gacha-draw-ten')), findsNothing);
    expect(find.byKey(const ValueKey('gacha-back-town')), findsNothing);
    final hallBack = find.byKey(const ValueKey('consultation-town-back'));
    expect(hallBack, findsOneWidget);
    expect(
      (tester.widget<Image>(
        find.descendant(of: hallBack, matching: find.byType(Image)),
      ).image as AssetImage).assetName,
      'assets/gacya/back.png',
    );
    expect(tester.getRect(hallBack).bottom, lessThanOrEqualTo(640));
    expect(find.text('開催費：30ことほぎ'), findsOneWidget);
    expect(controller.progress!.residents.availableKotohogi(60), 60);

    final first = tester.widget<Image>(
      find.descendant(
        of: find.byKey(const ValueKey('consultation-walker-0')),
        matching: find.byType(Image),
      ),
    );
    final firstAsset = (first.image as AssetImage).assetName;
    await tester.pump(const Duration(milliseconds: 170));
    final second = tester.widget<Image>(
      find.descendant(
        of: find.byKey(const ValueKey('consultation-walker-0')),
        matching: find.byType(Image),
      ),
    );
    final backSprite = (second.image as AssetImage).assetName;
    expect(backSprite, isNot(firstAsset));
    expect(backSprite, contains('/walk_back_'));
    final walker = tester.getRect(
      find.byKey(const ValueKey('consultation-walker-0')),
    );
    expect(walker.height, greaterThan(60));
    expect(walker.top, lessThan(320));
    expect(walker.bottom, lessThan(400));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('resident steps onto stage, arrival banner, repeat, list',
      (tester) async {
    final store = MemoryStore()..raw = funded(points: 60).encode();
    final controller = await open(tester, store);
    await tester.tap(find.byKey(const ValueKey('gacha-draw-one')));
    await tester.pumpAndSettle();

    expect(find.byType(GachaReveal), findsOneWidget);
    final revealHud = tester.getRect(find.byType(KotohogiBar));
    final revealHeader = tester.getRect(find.byType(GachaHud));
    expect(revealHeader.left, closeTo(12, .5));
    expect(revealHud.right, closeTo(348, .5));
    expect(revealHud.left, greaterThan(150));
    expect(find.byType(PlayerNameplate), findsOneWidget);
    expect(find.text('ハル'), findsOneWidget);
    expect(find.byKey(const ValueKey('gacha-back-town')), findsNothing);
    expect(find.byKey(const ValueKey('consultation-town-back')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('gacha-reveal-glow')), findsOneWidget);
    expect(find.byKey(const ValueKey('gacha-stage-resident')),
        findsOneWidget);
    final stageResident = tester.getRect(
      find.byKey(const ValueKey('gacha-stage-resident')),
    );
    expect(stageResident.height, greaterThan(120));
    // Feet remain on the blue stage instead of dropping below its front edge.
    final stage = tester.getRect(
      find.byKey(const ValueKey('consultation-stage')),
    );
    // The platform is lower than before, bridging the blank space above the
    // bottom actions. The resident's feet rest on its blue upper surface.
    expect(stage.top, inInclusiveRange(400, 435));
    expect(stage.bottom, inInclusiveRange(480, 510));
    expect(stageResident.bottom, inInclusiveRange(430, 470));
    expect(stageResident.bottom, greaterThan(stage.top));
    expect(stageResident.bottom, lessThan(stage.bottom));
    expect(find.byKey(const ValueKey('resident-arrival-banner')),
        findsOneWidget);
    final bannerRect = tester.getRect(
      find.byKey(const ValueKey('resident-arrival-banner')),
    );
    // The full arrival card stays above the resident's head.
    expect(bannerRect.bottom, lessThan(stageResident.top - 10));
    final arrival = tester.widget<Image>(
      find.byKey(const ValueKey('resident-arrival-banner')),
    );
    expect(
      (arrival.image as AssetImage).assetName,
      'assets/gacya/resident_arrival_banner.png',
    );
    expect(
      tester.widget<Semantics>(
        find.byKey(const ValueKey('gacha-result')),
      ).properties.label,
      '${TownResident.penguin.label}が、まちにやってきました！',
    );
    // First arrival uses the NEW artwork, never the reunion stamp.
    final newBadge = find.byKey(const ValueKey('gacha-new-badge'));
    expect(newBadge, findsOneWidget);
    expect(find.byKey(const ValueKey('gacha-reunion-badge')), findsNothing);
    expect(
      (tester.widget<Image>(newBadge).image as AssetImage).assetName,
      'assets/gacya/parts/badge_new.png',
    );
    expect(find.bySemanticsLabel('NEW'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('gacha-banner-resident-name')),
      findsOneWidget,
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('resident-arrival-banner')))
          .width,
      greaterThan(200),
    );
    expect(store.writes, 1);
    expect(controller.progress!.residents.availableKotohogi(60), 30);

    await tester.tap(find.byKey(const ValueKey('resident-list-button')));
    await tester.pumpAndSettle();
    expect(find.text('住民一覧'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text(TownResident.penguin.label),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('閉じる'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('button_again')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Semantics>(
        find.byKey(const ValueKey('gacha-result')),
      ).properties.label,
      '${TownResident.penguin.label}とまた出会いました！',
    );
    expect(find.byKey(const ValueKey('gacha-reunion-badge')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('gacha-new-badge')), findsNothing);
    expect(
      (tester.widget<Image>(
        find.byKey(const ValueKey('gacha-reunion-badge')),
      ).image as AssetImage).assetName,
      'assets/gacya/parts/badge_reunion.png',
    );
    final badge = tester.getRect(
      find.byKey(const ValueKey('gacha-reunion-badge')),
    );
    final returningResident = tester.getRect(
      find.byKey(const ValueKey('gacha-stage-resident')),
    );
    // The reunion badge belongs at the resident's lower right, not outside
    // the viewport on the left edge of the arrival banner.
    expect(badge.left, greaterThan(returningResident.center.dx));
    expect(badge.top, greaterThan(returningResident.center.dy));
    expect(badge.left, greaterThanOrEqualTo(0));
    expect(badge.right, lessThanOrEqualTo(360));
    expect(badge.bottom, lessThanOrEqualTo(640));
    // A returning resident still gets the arrival panel, with the reunion
    // badge added separately. Repeated draws must not silently omit it.
    expect(find.byKey(const ValueKey('resident-arrival-banner')),
        findsOneWidget);
    expect(
      tester.widget<Text>(
        find.byKey(const ValueKey('gacha-banner-resident-name')),
      ).data,
      TownResident.penguin.label,
    );
    expect(controller.progress!.residents.counts['03_penguin'], 2);
    expect(controller.progress!.residents.availableKotohogi(60), 0);
    expect(
      tester.widget<TextButton>(find.byKey(const ValueKey('button_again')))
          .onPressed,
      isNull,
    );
    expect(store.writes, 2);
    final returnToTown = find.byKey(const ValueKey('consultation-town-back'));
    final bottomReturn = tester.getRect(returnToTown);
    final repeat = tester.getRect(find.byKey(const ValueKey('button_again')));
    expect(bottomReturn.top, greaterThanOrEqualTo(repeat.bottom));
    expect(bottomReturn.bottom, lessThanOrEqualTo(640));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final viewport in <Size>[
    const Size(320, 640),
    const Size(360, 640),
    const Size(402, 874),
  ]) {
    testWidgets('NEW badge stays on screen beside resident at $viewport',
        (tester) async {
      tester.view.physicalSize = viewport;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller = ProgressController(
        MemoryStore()..raw = funded(points: 60).encode(),
        clock: () => DateTime(2026, 10, 11),
        random: FixedRandom(2),
      );
      await controller.initialize();
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: GachaReveal(
            controller: controller,
            resident: TownResident.penguin,
            isNew: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final badge = find.byKey(const ValueKey('gacha-new-badge'));
      final resident = find.byKey(const ValueKey('gacha-stage-resident'));
      final banner = find.byKey(const ValueKey('resident-arrival-banner'));
      expect(badge, findsOneWidget);
      expect(find.byKey(const ValueKey('gacha-reunion-badge')), findsNothing);
      expect(resident, findsOneWidget);
      expect(banner, findsOneWidget);
      expect(
        (tester.widget<Image>(badge).image as AssetImage).assetName,
        'assets/gacya/parts/badge_new.png',
      );
      final b = tester.getRect(badge);
      final r = tester.getRect(resident);
      expect(tester.getRect(banner).bottom, lessThan(r.top - 10));
      expect(b.left, greaterThanOrEqualTo(0));
      expect(b.right, lessThanOrEqualTo(viewport.width));
      expect(b.top, greaterThanOrEqualTo(0));
      expect(b.bottom, lessThanOrEqualTo(viewport.height));
      expect(b.left, greaterThan(r.center.dx));
      expect(b.top, greaterThan(r.center.dy));
      expect(find.bySemanticsLabel('NEW'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final viewport in <Size>[
    const Size(320, 640),
    const Size(360, 640),
    const Size(402, 874),
  ]) {
    testWidgets('reunion badge stays on screen beside resident at $viewport',
        (tester) async {
      tester.view.physicalSize = viewport;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller = ProgressController(
        MemoryStore()..raw = funded(points: 60).encode(),
        clock: () => DateTime(2026, 10, 11),
        random: FixedRandom(2),
      );
      await controller.initialize();
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: GachaReveal(
            controller: controller,
            resident: TownResident.penguin,
            isNew: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final badge = find.byKey(const ValueKey('gacha-reunion-badge'));
      final resident = find.byKey(const ValueKey('gacha-stage-resident'));
      final banner = find.byKey(const ValueKey('resident-arrival-banner'));
      expect(badge, findsOneWidget);
      expect(resident, findsOneWidget);
      expect(banner, findsOneWidget);
      final b = tester.getRect(badge);
      final r = tester.getRect(resident);
      final arrivalRect = tester.getRect(banner);
      expect(arrivalRect.bottom, lessThan(r.top - 10),
          reason: 'Arrival card must not cover resident at $viewport');
      expect(b.left, greaterThanOrEqualTo(0));
      expect(b.right, lessThanOrEqualTo(viewport.width));
      expect(b.top, greaterThanOrEqualTo(0));
      expect(b.bottom, lessThanOrEqualTo(viewport.height));
      expect(b.left, greaterThan(r.center.dx));
      expect(b.top, greaterThan(r.center.dy));
      expect(find.bySemanticsLabel('また会えた'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final viewport in <Size>[
    const Size(320, 640),
    const Size(360, 640),
    const Size(402, 874),
  ]) {
    testWidgets('bottom art back stays below actions at $viewport',
        (tester) async {
      tester.view.physicalSize = viewport;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller = ProgressController(
        MemoryStore()..raw = funded(points: 60).encode(),
        clock: () => DateTime(2026, 10, 11),
        random: FixedRandom(2),
      );
      await controller.initialize();
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: GachaReveal(
          controller: controller,
          resident: TownResident.penguin,
          isNew: false,
        ),
      ));
      await tester.pumpAndSettle();
      final back = find.byKey(const ValueKey('consultation-town-back'));
      final residents = find.byKey(const ValueKey('resident-list-button'));
      final again = find.byKey(const ValueKey('button_again'));
      expect(back, findsOneWidget);
      expect(find.byKey(const ValueKey('gacha-back-town')), findsNothing);
      final rect = tester.getRect(back);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(viewport.width));
      expect(rect.top, greaterThanOrEqualTo(tester.getRect(residents).bottom));
      expect(rect.top, greaterThanOrEqualTo(tester.getRect(again).bottom));
      expect(rect.bottom, lessThanOrEqualTo(viewport.height));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('saving blocks another draw until the first finishes',
      (tester) async {
    final store = MemoryStore()..raw = funded(points: 60).encode();
    await open(tester, store);
    store.gate = Completer<void>();
    await tester.tap(find.byKey(const ValueKey('gacha-draw-one')));
    await tester.pump();
    expect(
      tester.widget<TextButton>(find.byKey(const ValueKey('gacha-draw-one')))
          .onPressed,
      isNull,
    );
    expect(store.writes, 1);
    store.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(GachaReveal), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('welcome button draws exactly once and starts the reveal',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = MemoryStore()..raw = funded(points: 60).encode();
    final controller = ProgressController(
      store,
      clock: () => DateTime(2026, 10, 11),
      random: FixedRandom(2),
    );
    await controller.initialize();
    var visitedTown = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ResidentGacha(
            controller: controller,
            onTown: () => visitedTown = true,
          ),
        ),
      ),
    ));
    await tester.ensureVisible(find.byKey(const ValueKey('draw-resident')));
    await tester.tap(find.byKey(const ValueKey('draw-resident')));
    await tester.pumpAndSettle();
    expect(find.byType(GachaReveal), findsOneWidget);
    expect(find.byKey(const ValueKey('resident-arrival-banner')),
        findsOneWidget);
    expect(controller.progress!.residents.counts['03_penguin'], 1);
    expect(store.writes, 1);
    await tester.tap(find.byKey(const ValueKey('consultation-town-back')));
    await tester.pumpAndSettle();
    expect(find.byType(GachaReveal), findsNothing);
    expect(find.byType(GachaScreen), findsNothing);
    expect(visitedTown, isTrue);
    expect(store.writes, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('consultation fee stays at 30 while the wallet changes',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    for (final balance in [10, 30, 60]) {
      final controller = ProgressController(
        MemoryStore()..raw = funded(points: balance).encode(),
        clock: () => DateTime(2026, 10, 11),
        random: FixedRandom(2),
      );
      await controller.initialize();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ResidentGacha(controller: controller),
          ),
        ),
      ));
      await tester.pump();

      final cost = tester.widget<Text>(
        find.byKey(const ValueKey('consultation-cost')),
      );
      expect(cost.data, '30ことほぎ', reason: 'wallet = $balance');
      if (balance < 30) {
        expect(find.text('あと${30 - balance}ことほぎで移住相談会を開けます。'),
            findsOneWidget);
      } else {
        expect(find.text('30ことほぎで移住相談会を1回開けます。'),
            findsOneWidget);
      }
      expect(
        tester.widget<TextButton>(
          find.byKey(const ValueKey('draw-resident')),
        ).onPressed == null,
        balance < 30,
      );
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('welcome requires enough kotohogi before starting a draw',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = MemoryStore();
    final controller = ProgressController(
      store,
      clock: () => DateTime(2026, 10, 11),
      random: FixedRandom(2),
    );
    await controller.initialize();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ResidentGacha(controller: controller),
        ),
      ),
    ));
    final welcome = tester.widget<TextButton>(
      find.byKey(const ValueKey('draw-resident')),
    );
    expect(welcome.onPressed, isNull);
    expect(store.writes, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reduced motion shows the completed result immediately',
      (tester) async {
    await open(
      tester,
      MemoryStore()..raw = funded().encode(),
      reduced: true,
    );
    await tester.tap(find.byKey(const ValueKey('gacha-draw-one')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('gacha-result')), findsOneWidget);
    expect(find.byKey(const ValueKey('resident-arrival-banner')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
