import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:future_lift/dialogue_engine.dart';
import 'package:future_lift/marche.dart';
import 'package:future_lift/progress.dart';
import 'package:future_lift/resident_collection.dart';
import 'package:future_lift/town.dart';
import 'package:future_lift/town_areas.dart';

Progress tonkoProgress({bool owned = true}) => Progress(
  day: '2026-10-17',
  lastCompletedDay: '2026-10-16',
  points: 300,
  residents: ResidentCollection(
    baselinePoints: 0,
    counts: {
      '01_shiba': 1,
      '02_rabbit': 1,
      if (owned) '041_pig_middle': 1,
    },
  ),
  completed: {},
);

void main() {
  test('opening the stall requires owning Tonko and her saved dialogue', () {
    final owned = tonkoProgress();
    final unowned = tonkoProgress(owned: false);
    expect(isMarcheOpen(owned), isFalse);
    expect(isMarcheOpen(owned.markDialogueSeen('041_pig_middle_032')), isFalse);
    expect(isMarcheOpen(unowned.markDialogueSeen(tonkoMarcheOpeningDialogueId)),
        isFalse);
    final open = owned.markDialogueSeen(tonkoMarcheOpeningDialogueId);
    expect(isMarcheOpen(open), isTrue);
    expect(isMarcheOpen(Progress.decode(open.encode(), expectedVersion: 5)),
        isTrue);
    expect(isMarcheOpen(open.onDay(DateTime(2026, 10, 18))), isTrue);
  });

  test('marche story persists across days, then rotates daily remarks', () {
    final catalog = DialogueCatalog.fromJson(
        File('assets/dialogues/dialogues.json').readAsStringSync());
    var progress = tonkoProgress().markDialogueSeen(
        tonkoMarcheOpeningDialogueId);
    expect(isMarcheStoryComplete(progress), isFalse);
    for (final id in tonkoMarcheStoryDialogueIds) {
      final line = selectMarcheDialogue(
        catalog: catalog, progress: progress,
        now: DateTime.utc(2026, 10, 17));
      expect(line.id, id);
      expect(line.once, id != tonkoMarcheGreetingDialogueId);
      progress = progress.markDialogueSeen(line.id);
      // Save/reload mid-story and roll over into a new calendar day.
      progress = Progress.decode(progress.encode(), expectedVersion: 5)
          .onDay(DateTime(2026, 10, 18));
    }
    expect(isMarcheStoryComplete(progress), isTrue);
    for (var i = 0; i < tonkoMarcheDailyDialogueIds.length * 2; i++) {
      final line = selectMarcheDialogue(
        catalog: catalog, progress: progress,
        now: DateTime.utc(2026, 10, 20), dailyRotation: i);
      expect(line.id, tonkoMarcheDailyDialogueIds[
          i % tonkoMarcheDailyDialogueIds.length]);
      expect(line.once, isFalse);
      progress = progress.markDialogueSeen(line.id);
    }
    expect(isMarcheStoryComplete(
        Progress.decode(progress.encode(), expectedVersion: 5)), isTrue);
    expect(() => selectMarcheDialogue(
        catalog: catalog, progress: progress,
        now: DateTime.utc(2026, 10, 20), dailyRotation: -1),
        throwsRangeError);
    expect(() => selectMarcheDialogue(
        catalog: catalog, progress: tonkoProgress(),
        now: DateTime.utc(2026, 10, 20)),
        throwsStateError);
  });

  test('marche exclusive conversation IDs stay out of normal rotation', () {
    final catalog = DialogueCatalog.fromJson(
        File('assets/dialogues/dialogues.json').readAsStringSync());
    var progress = tonkoProgress().markDialogueSeen(
        tonkoMarcheOpeningDialogueId);
    for (final id in tonkoMarcheStoryDialogueIds) {
      progress = progress.markDialogueSeen(id);
    }
    final exclusive = {
      ...tonkoMarcheStoryDialogueIds,
      ...tonkoMarcheDailyDialogueIds,
    };
    for (var rotation = 0; rotation < 30; rotation++) {
      expect(catalog.select(
        resident: tonkoMarcheOwner,
        progress: progress,
        now: DateTime.utc(2026, 10, 17),
        rotation: rotation,
      ).id, isNot(isIn(exclusive)));
    }
  });

  test('shopkeeper moves to plaza without ever being duplicated', () {
    const owner = TownResident.c041_pig_middle;
    const residents = [TownResident.shiba, owner, TownResident.rabbit];
    expect(areaResidents(residents, TownArea.village,
        lifetimePoints: 300), [owner]);
    expect(areaResidents(residents, TownArea.plaza,
        lifetimePoints: 300), [TownResident.shiba]);

    expect(areaResidents(residents, TownArea.plaza,
        lifetimePoints: 300, marcheOpen: true),
        [TownResident.shiba, owner]);
    expect(areaResidents(residents, TownArea.village,
        lifetimePoints: 300, marcheOpen: true), isEmpty);
    final all = [
      for (final area in TownArea.values)
        ...areaResidents(residents, area,
            lifetimePoints: 300, marcheOpen: true),
    ];
    expect(all.length, residents.length);
    expect(all.toSet().length, residents.length);

    // Debug-only cast residents stay in their assigned neighborhood.
    expect(areaResidents(residents, TownArea.plaza,
        lifetimePoints: 300, marcheOpen: true,
        debugOverride: [owner]), isEmpty);
    expect(areaResidents(residents, TownArea.village,
        lifetimePoints: 300, marcheOpen: true,
        debugOverride: [owner]), [owner]);

    // Pre-unlock behavior is unchanged: the village resident meets at plaza.
    expect(areaResidents(residents, TownArea.plaza,
        lifetimePoints: 0), contains(owner));
  });

  test('the checked-in story progresses into the opening in six chats', () {
    final catalog = DialogueCatalog.fromJson(
        File('assets/dialogues/dialogues.json').readAsStringSync());
    var progress = tonkoProgress();
    final milestones = [
      '041_pig_middle_011', '041_pig_middle_012',
      '041_pig_middle_021', '041_pig_middle_022',
      '041_pig_middle_032',
      tonkoMarcheOpeningDialogueId,
    ];
    for (final id in milestones) {
      final entry = catalog.select(
        resident: tonkoMarcheOwner,
        progress: progress,
        now: DateTime.utc(2026, 10, 17),
      );
      expect(entry.id, id);
      expect(isMarcheOpen(progress), isFalse);
      progress = progress.markDialogueSeen(entry.id);
    }
    expect(isMarcheOpen(progress), isTrue);
    final greeting = catalog.entries.singleWhere(
        (entry) => entry.id == tonkoMarcheGreetingDialogueId);
    expect(greeting.residentId, tonkoMarcheOwner.id);
    expect(greeting.once, isFalse);
    expect(greeting.matches(progress, DateTime.utc(2026, 10, 17), {}),
        isTrue);
    for (var rotation = 0; rotation < 30; rotation++) {
      expect(catalog.select(
        resident: tonkoMarcheOwner,
        progress: progress,
        now: DateTime.utc(2026, 10, 17),
        rotation: rotation,
      ).id, isNot(tonkoMarcheGreetingDialogueId));
    }
  });

  testWidgets('stall is shown only in the opened plaza and can be tapped',
      (tester) async {
    tester.view.physicalSize = const Size(430, 930);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var visits = 0;
    Widget scene(TownArea area, bool open) => MaterialApp(
      home: Scaffold(
        body: TownScene(
          level: 0, area: area, lifetimePoints: 300,
          residents: const [], fillViewport: true,
          marcheOpen: open,
          onVisitMarche: () { visits++; },
        ),
      ),
    );
    const key = ValueKey('plaza-marche-entrance');
    await tester.pumpWidget(scene(TownArea.plaza, false));
    expect(find.byKey(key), findsNothing);
    await tester.pumpWidget(scene(TownArea.park, true));
    expect(find.byKey(key), findsNothing);
    await tester.pumpWidget(scene(TownArea.plaza, true));
    expect(find.byKey(key), findsOneWidget);
    final rect = tester.getRect(find.byKey(key));
    expect(rect.width, greaterThan(60));
    expect(rect.height, greaterThan(60));
    await tester.tap(find.byKey(key));
    await tester.pump();
    expect(visits, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Tonko tends her stall and responds with the market greeting',
      (tester) async {
    tester.view.physicalSize = const Size(430, 930);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var marketGreetings = 0;
    var ordinaryConversations = 0;
    Widget town(TownArea area, bool open, {
      List<TownResident>? preview,
    }) => MaterialApp(
      home: Scaffold(
        body: TownScene(
          level: 0,
          area: area,
          lifetimePoints: 300,
          residents: const [TownResident.c041_pig_middle],
          debugTownResidents: preview,
          fillViewport: true,
          marcheOpen: open,
          onVisitMarche: () { marketGreetings++; },
          onResident: (resident) async { ordinaryConversations++; },
        ),
      ),
    );
    const staff = ValueKey('marche-shopkeeper');
    const stall = ValueKey('plaza-marche-entrance');

    await tester.pumpWidget(town(TownArea.plaza, false));
    expect(find.byKey(staff), findsNothing);
    await tester.pumpWidget(town(TownArea.village, false));
    expect(find.byKey(staff), findsNothing);
    expect(find.byKey(const ValueKey('resident-0')), findsOneWidget);
    await tester.pumpWidget(town(TownArea.village, true));
    expect(find.byKey(staff), findsNothing);
    expect(find.byKey(const ValueKey('resident-0')), findsNothing);

    await tester.pumpWidget(town(TownArea.plaza, true));
    expect(find.byKey(staff), findsOneWidget);
    expect(find.byKey(const ValueKey('marche-shopkeeper-sprite')),
        findsOneWidget);
    expect(find.byKey(stall), findsOneWidget);
    expect(find.byKey(const ValueKey('resident-0')), findsNothing);

    final actorRect = tester.getRect(find.byKey(staff));
    final stallRect = tester.getRect(find.byKey(stall));
    expect(actorRect.center.dx, lessThan(stallRect.center.dx),
        reason: 'The shopkeeper stands by the left side of the stall');
    expect(actorRect.bottom, greaterThan(stallRect.top));
    expect(actorRect.top, lessThan(stallRect.bottom));
    expect(plazaMarcheStaffRoute.stay, isTrue);

    await tester.tap(find.byKey(staff));
    await tester.pump();
    expect(marketGreetings, 1);
    expect(ordinaryConversations, 0);

    await tester.tap(find.byKey(stall));
    await tester.pump();
    expect(marketGreetings, 2);

    await tester.pumpWidget(town(TownArea.plaza, true,
        preview: const [TownResident.c041_pig_middle]));
    expect(find.byKey(staff), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  test('the transparent market image fits the plaza source canvas', () {
    final bytes = File('assets/kotohogu/marche.png').readAsBytesSync();
    expect(bytes.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);
    final header = bytes.buffer.asByteData();
    expect(header.getUint32(16), 540);
    expect(header.getUint32(20), 474);
    expect(bytes[25], 6);
    expect(plazaMarcheRect.right, lessThan(768));
    expect(plazaMarcheRect.bottom, lessThan(1376));
  });
}
