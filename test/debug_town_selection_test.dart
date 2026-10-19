import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:future_lift/debug_menu_screen.dart';
import 'package:future_lift/google_drive_content_source.dart';
import 'package:future_lift/local_content_preview.dart';
import 'package:future_lift/dialogue_engine.dart';
import 'package:future_lift/game_home.dart';
import 'package:future_lift/main.dart';
import 'package:future_lift/progress.dart';
import 'package:future_lift/resident_collection.dart';
import 'package:future_lift/town.dart';
import 'package:future_lift/town_area_navigator.dart';
import 'package:future_lift/town_areas.dart';

import 'progress_test.dart' show MemoryStore;

void main() {
  test('debug override selects unowned residents without mutating ownership', () {
    final owned = [TownResident.shiba, TownResident.rabbit];
    expect(visibleTownResidents(owned), owned);
    final special = [TownResident.c027_daydreamer, TownResident.c026_farmer];
    expect(visibleTownResidents(owned, debugOverride: special), special);
    expect(visibleTownResidents(owned, debugOverride: []), isEmpty);
    expect(owned, [TownResident.shiba, TownResident.rabbit]);

    expect(
      () => visibleTownResidents(
        owned,
        debugOverride: [TownResident.shiba, TownResident.shiba],
      ),
      throwsArgumentError,
    );
    expect(
      visibleTownResidents(owned, debugOverride: TownResident.values.toList()),
      TownResident.values.toList(),
    );
    expect(
      visibleTownResidents(TownResident.values).length,
      TownResident.values.where(
          (resident) => resident.walkInTown &&
              resident.homeAreaId != 'salon').length,
    );
  });

  testWidgets('debug cast changes home and town without writing save data',
      (tester) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final store = MemoryStore();
    final catalog = DialogueCatalog.fromJson(jsonEncode({
      'version': 1,
      'dialogues': [
        for (final resident in TownResident.values)
          {
            'id': 'fallback_${resident.id}',
            'residentId': resident.id,
            'text': 'こんにちは、${resident.label}です。',
            'priority': 0,
            'once': false,
            'logic': 'all',
            'conditions': [],
          },
      ],
    }));
    final controller = ProgressController(
      store,
      clock: () => DateTime(2026, 10, 15, 12),
    );
    await tester.pumpWidget(FutureLiftApp(
      controller: controller,
      dialogueCatalog: catalog,
      enableTutorial: false,
    ));
    await tester.pumpAndSettle();
    final originalSave = store.raw;
    final originalWrites = store.writes;

    await tester.tap(find.byKey(const ValueKey('footer-menu')));
    await tester.pumpAndSettle();
    final toggle = find.byKey(const ValueKey('debug-town-enable'));
    await tester.scrollUntilVisible(toggle, 200);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    final selectedBefore = tester.widget<DebugMenuScreen>(
      find.byType(DebugMenuScreen),
    ).debugTownResidents;
    expect(selectedBefore, [TownResident.shiba, TownResident.rabbit]);

    final daydreamer = find.byKey(
      const ValueKey('debug-town-resident-027_daydreamer'),
    );
    await tester.scrollUntilVisible(daydreamer, 160);
    await tester.pumpAndSettle();
    await tester.tap(daydreamer);
    await tester.pumpAndSettle();
    expect(
      tester.widget<DebugMenuScreen>(find.byType(DebugMenuScreen))
          .debugTownResidents,
      [TownResident.shiba, TownResident.rabbit, TownResident.c027_daydreamer],
    );

    await tester.tap(find.byKey(const ValueKey('footer-home')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<GameHome>(find.byType(GameHome)).debugTownResidents,
      contains(TownResident.c027_daydreamer),
    );
    expect(
      find.byKey(const ValueKey('home-resident-sprite-027_daydreamer')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('footer-town')));
    await tester.pumpAndSettle();
    final town = tester.widget<TownScene>(find.byType(TownScene));
    expect(town.debugTownResidents,
        [TownResident.shiba, TownResident.rabbit, TownResident.c027_daydreamer]);
    expect(find.byKey(const ValueKey('resident-2')), findsNothing);
    // A resident stays in the assigned home area even in debug preview.
    await tester.tap(find.byKey(const ValueKey('town-area-next')));
    await tester.pumpAndSettle();
    expect(tester.widget<TownAreaNavigator>(find.byType(TownAreaNavigator)).area,
        TownArea.park);
    expect(tester.widget<TownScene>(find.byType(TownScene)).area,
        TownArea.park);
    final daydreamerInTown = find.byTooltip(TownResident.c027_daydreamer.label);
    expect(daydreamerInTown, findsOneWidget);
    // A debug-only dialogue must not modify seen IDs or ownership.
    await tester.tap(daydreamerInTown);
    await tester.pumpAndSettle();
    expect(find.text('こんにちは、おやすみくんです。'), findsOneWidget);
    await tester.tap(find.text('また話そう'));
    await tester.pumpAndSettle();
    expect(store.raw, originalSave);
    expect(store.writes, originalWrites);
    expect(controller.progress!.seenDialogues, isEmpty);
    expect(controller.progress!.residents.owned,
        [TownResident.shiba, TownResident.rabbit]);

    await tester.tap(find.byKey(const ValueKey('footer-menu')));
    await tester.pumpAndSettle();
    final restore = find.byKey(const ValueKey('debug-town-enable'));
    await tester.scrollUntilVisible(restore, 200);
    await tester.pumpAndSettle();
    await tester.tap(restore);
    await tester.pumpAndSettle();
    expect(
      tester.widget<DebugMenuScreen>(find.byType(DebugMenuScreen))
          .debugTownResidents,
      isNull,
    );
    await tester.tap(find.byKey(const ValueKey('footer-town')));
    await tester.pumpAndSettle();
    final restoredTown =
        tester.widget<TownAreaNavigator>(find.byType(TownAreaNavigator));
    expect(restoredTown.debugTownResidents, isNull);
    expect(restoredTown.area, TownArea.plaza,
        reason: 'Leaving debug mode returns from the locked village');
    expect(find.byKey(const ValueKey('resident-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('town-area-next')), findsNothing);
    expect(find.text('まだ行けないエリアだよ'), findsNothing);
    expect(store.raw, originalSave);
    expect(store.writes, originalWrites);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('salon debug mode is session only and keeps saves untouched',
      (tester) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = MemoryStore();
    final catalog = DialogueCatalog.fromJson(jsonEncode({
      'version': 1,
      'dialogues': [
        for (final resident in TownResident.values)
          {
            'id': 'debug_salon_${resident.id}',
            'residentId': resident.id,
            'text': 'こんにちは、${resident.label}です。',
            'priority': 0,
            'once': false,
            'logic': 'all',
            'conditions': [],
          },
      ],
    }));
    final controller = ProgressController(
      store, clock: () => DateTime(2026, 10, 16, 12));
    Future<void> start(ProgressController active) async {
      await tester.pumpWidget(FutureLiftApp(
        controller: active,
        dialogueCatalog: catalog,
        enableTutorial: false,
      ));
      await tester.pumpAndSettle();
    }

    await start(controller);
    final originalRaw = store.raw;
    final originalWrites = store.writes;
    await tester.tap(find.byKey(const ValueKey('footer-menu')));
    await tester.pumpAndSettle();
    final forceOpen = find.byKey(const ValueKey('debug-salon-mode-forceOpen'));
    await tester.scrollUntilVisible(forceOpen, 170);
    await tester.pumpAndSettle();
    await tester.tap(forceOpen);
    await tester.pumpAndSettle();
    expect(tester.widget<DebugMenuScreen>(find.byType(DebugMenuScreen))
        .salonUnlockMode, SalonUnlockDebugMode.forceOpen);
    expect(find.text('テスト中の状態：開放'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('footer-town')));
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const ValueKey('town-area-next')));
      await tester.pumpAndSettle();
    }
    expect(tester.widget<TownAreaNavigator>(find.byType(TownAreaNavigator))
        .area, TownArea.village);
    await tester.tap(find.byKey(const ValueKey('village-salon-entrance')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('salon-resident-035_beaty')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('salon-fox-resident')),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('salon-resident-035_beaty')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('こんにちは、つやこです。'), findsOneWidget);
    await tester.tap(find.text('また話そう'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(controller.progress!.seenDialogues, isEmpty);
    expect(controller.progress!.residents.owned,
        [TownResident.shiba, TownResident.rabbit]);
    expect(store.raw, originalRaw);
    expect(store.writes, originalWrites);

    await tester.tap(find.byKey(const ValueKey('salon-return-village')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('footer-menu')));
    await tester.pumpAndSettle();
    final forceClosed = find.byKey(
        const ValueKey('debug-salon-mode-forceClosed'));
    await tester.scrollUntilVisible(forceClosed, 170);
    await tester.pumpAndSettle();
    await tester.tap(forceClosed);
    await tester.pumpAndSettle();
    expect(find.text('テスト中の状態：未開放'), findsOneWidget);

    // Switching facility preview off returns from the locked village.
    final resetMode = find.byKey(const ValueKey('debug-salon-mode-normal'));
    await tester.scrollUntilVisible(resetMode, 170);
    await tester.pumpAndSettle();
    await tester.tap(resetMode);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('footer-town')));
    await tester.pumpAndSettle();
    expect(tester.widget<TownAreaNavigator>(find.byType(TownAreaNavigator))
        .area, TownArea.plaza);
    expect(find.byKey(const ValueKey('town-area-next')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('footer-menu')));
    await tester.pumpAndSettle();

    // A fresh app session uses normal mode without any stored override.
    await tester.pumpWidget(const SizedBox());
    await start(ProgressController(
      store, clock: () => DateTime(2026, 10, 16, 12)));
    await tester.tap(find.byKey(const ValueKey('footer-menu')));
    await tester.pumpAndSettle();
    expect(tester.widget<DebugMenuScreen>(find.byType(DebugMenuScreen))
        .salonUnlockMode, SalonUnlockDebugMode.normal);
    expect(store.raw, originalRaw);
    expect(store.writes, originalWrites);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });


  testWidgets('unowned remote residents need an explicit debug toggle', (tester) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final store = MemoryStore();
    final progress = ProgressController(
      store, clock: () => DateTime(2026, 10, 18, 12),
    );
    final bundled = DialogueCatalog.fromJson(jsonEncode({
      'version': 1,
      'dialogues': [
        for (final resident in TownResident.values)
          {
            'id': 'fallback_remote_gate_${resident.id}',
            'residentId': resident.id,
            'text': 'こんにちは！',
            'priority': 0,
            'once': false,
            'logic': 'all',
            'conditions': [],
          }
      ],
    }));
    final remote = RemoteContentCatalog.fromJson(jsonEncode({
      'version': 1,
      'characters': [
        {
          'key': 'c038_owl',
          'id': '038_owl',
          'label': 'ふくろう',
          'artFolder': '038_owl',
          'homeAreaId': 'plaza',
          'nextDialogueNumber': 2,
          'walkInTown': true,
          'inGacha': true,
          'profile': '',
        },
      ],
      'dialogues': [
        {
          'id': '038_owl_001',
          'residentId': '038_owl',
          'text': 'こんにちは',
          'priority': 0,
          'once': false,
          'logic': 'all',
          'conditions': [],
        },
      ],
    }));
    await tester.pumpWidget(FutureLiftApp(
      controller: progress,
      dialogueCatalog: bundled,
      enableTutorial: false,
      remoteContentLoader: () async => HostedTownContent(
        baseUri: localServerUri('http://10.0.2.2:8765'),
        catalog: remote,
      ),
    ));
    await tester.pumpAndSettle();
    final originalSave = store.raw;
    final originalWrites = store.writes;

    // Live remote data is loaded, but it is not a license to spawn visitors.
    await tester.tap(find.byKey(const ValueKey('footer-town')));
    await tester.pumpAndSettle();
    expect(tester.widget<TownAreaNavigator>(
      find.byType(TownAreaNavigator)).remoteVisitors, isEmpty);

    await tester.tap(find.byKey(const ValueKey('footer-menu')));
    await tester.pumpAndSettle();
    final toggle = find.byKey(const ValueKey('debug-unowned-preview-enable'));
    await tester.scrollUntilVisible(toggle, 160);
    await tester.pumpAndSettle();
    expect(tester.widget<DebugMenuScreen>(
      find.byType(DebugMenuScreen)).showUnownedPreviewVisitors, isFalse);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<DebugMenuScreen>(
      find.byType(DebugMenuScreen)).showUnownedPreviewVisitors, isTrue);

    await tester.tap(find.byKey(const ValueKey('footer-town')));
    await tester.pumpAndSettle();
    final preview = tester.widget<TownAreaNavigator>(
      find.byType(TownAreaNavigator));
    expect(preview.remoteVisitors.map((visitor) => visitor.id), ['038_owl']);
    expect(preview.residents, [TownResident.shiba, TownResident.rabbit]);

    await tester.tap(find.byKey(const ValueKey('footer-menu')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(toggle, 160);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('footer-town')));
    await tester.pumpAndSettle();
    expect(tester.widget<TownAreaNavigator>(
      find.byType(TownAreaNavigator)).remoteVisitors, isEmpty);
    expect(store.raw, originalSave);
    expect(store.writes, originalWrites);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

}
