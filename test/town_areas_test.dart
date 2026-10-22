import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:future_lift/gacha_hud.dart';
import 'package:future_lift/resident_collection.dart';
import 'package:future_lift/town.dart';
import 'package:future_lift/salon_room.dart';
import 'package:future_lift/town_area_navigator.dart';
import 'package:future_lift/town_areas.dart';

import 'support/town_random.dart';

void main() {
  test('stable area IDs and lifetime unlock thresholds', () {
    expect(TownArea.fromId('plaza'), TownArea.plaza);
    expect(TownArea.fromId('shopping'), TownArea.shopping);
    expect(TownArea.park.backgroundAsset,
        'assets/kotohogu/park_background_001.png');
    expect(TownArea.plaza.backgroundAsset,
        'assets/kotohogu/town_background_001.jpg');
    expect(TownArea.shopping.backgroundAsset,
        'assets/kotohogu/street_background_001.png');
    expect(() => TownArea.fromId('invalid'), throwsFormatException);
    expect(TownArea.plaza.isUnlocked(0), true);
    expect(TownArea.park.isUnlocked(89), false);
    expect(TownArea.park.isUnlocked(90), true);
    expect(TownArea.village.isUnlocked(299), false);
    expect(TownArea.village.isUnlocked(300), true);
  });

  test('area pagination counts only actually unlocked neighborhoods', () {
    expect(unlockedTownAreas(0), [TownArea.plaza]);
    expect(unlockedTownAreas(89), [TownArea.plaza]);
    expect(unlockedTownAreas(90), [TownArea.plaza, TownArea.park]);
    expect(unlockedTownAreas(179), [TownArea.plaza, TownArea.park]);
    expect(unlockedTownAreas(180),
        [TownArea.plaza, TownArea.park, TownArea.shopping]);
    expect(unlockedTownAreas(299),
        [TownArea.plaza, TownArea.park, TownArea.shopping]);
    expect(unlockedTownAreas(300), TownArea.values.where((area) => area != TownArea.hospital));
    expect(() => unlockedTownAreas(90).add(TownArea.village),
        throwsUnsupportedError);
  });

  test('source dimensions match bundled backgrounds exactly', () {
    final decoded = {
      for (final area in TownArea.values)
        if (area.backgroundAsset != null)
          area: _imageDimensions(File(area.backgroundAsset!).readAsBytesSync()),
    };
    debugPrint('Background dimensions: ${decoded.map((area, size) =>
        MapEntry(area.id, '${size.$1}x${size.$2}'))}');
    for (final area in TownArea.values) {
      final asset = area.backgroundAsset;
      if (asset == null) {
        expect(area.sourceWidth, isNull);
        expect(area.sourceHeight, isNull);
        continue;
      }
      final pixels = decoded[area]!;
      expect(pixels.$1, area.sourceWidth,
          reason: '${area.id} background width');
      expect(pixels.$2, area.sourceHeight,
          reason: '${area.id} background height');
    }
  });

  test('one outing allocates every outdoor resident without a global cap', () {
    final all = TownResident.values.toList();
    final walkers = visibleTownResidents(all);
    final visit = TownVisit(random: ScriptedTownRandom([
      for (var i = 0; i < walkers.length; i++) i % 4,
    ]), familyOutingOverride: false);
    final together = [
      for (final area in TownArea.values)
        ...areaResidents(all, area, lifetimePoints: 300, visit: visit),
    ];
    expect(together.toSet(), walkers.toSet());
    expect(together.length, walkers.length);
    expect(areaResidents(all, TownArea.village, lifetimePoints: 300,
        visit: visit, debugOverride: [TownResident.shiba, TownResident.c034_artist]),
        [TownResident.c034_artist]);
    expect(() => areaResidents(all, TownArea.plaza, lifetimePoints: 300,
        visit: visit, debugOverride: [TownResident.shiba, TownResident.shiba]),
        throwsArgumentError);
  });

  test('outdoor outing destination ignores legacy home metadata', () {
    // Outdoor homeAreaId values remain in old catalogs for compatibility,
    // but every walker can visit every opened area with equal chance.
    for (final legacy in ['plaza', 'park', 'shopping', 'village']) {
      final rng = ScriptedTownRandom([2]);
      final visit = TownVisit(random: rng);
      final first = visit.destinationFor(
        residentId: 'outdoor_test_resident',
        walkInTown: true,
        homeAreaId: legacy,
        lifetimePoints: 300,
      );
      expect(first, TownArea.shopping, reason: legacy);
      final repeat = visit.destinationFor(
        residentId: 'outdoor_test_resident',
        walkInTown: true,
        homeAreaId: legacy,
        lifetimePoints: 300,
      );
      expect(repeat, first);
      expect(rng.calls, 1, reason: 'Do not redraw while in the same town visit');
    }
  });

  test('salon walking flag does not put an indoor resident outdoors', () {
    const rio = TownResident.c038_lion_lady;
    final visit = TownVisit(random: ScriptedTownRandom([]));
    expect(rio.homeAreaId, 'salon');
    expect(rio.walkInTown, isTrue);
    for (final points in [0, 90, 300]) {
      expect(residentCurrentArea(rio, points, visit: visit), isNull);
      for (final area in TownArea.values) {
        expect(areaResidents([rio], area,
            lifetimePoints: points, visit: visit), isEmpty);
        expect(areaResidents(const [], area, lifetimePoints: points,
            visit: visit, debugOverride: [rio]), isEmpty);
      }
    }
    expect(visibleTownResidents([rio]), isEmpty);
    expect(salonResidents([rio]), contains(rio));
  });

  test('all outings use plaza while it is the only unlocked area', () {
    const owned = [
      TownResident.shiba, TownResident.rabbit, TownResident.cat,
      TownResident.bear, TownResident.c035_beaty, TownResident.c031_kimono_fox,
    ];
    const outdoors = [
      TownResident.shiba, TownResident.rabbit, TownResident.bear,
    ];
    for (final points in [0, 10, 89]) {
      final visit = TownVisit(random: ScriptedTownRandom([0, 0, 0, 0]));
      expect(areaResidents(owned, TownArea.plaza,
          lifetimePoints: points, visit: visit), outdoors);
      for (final area in TownArea.values.skip(1).where((a) => a != TownArea.hospital)) {
        expect(areaResidents(owned, area,
            lifetimePoints: points, visit: visit), isEmpty);
      }
    }
    // おししょうさん is now assigned to the public community center.
    expect(salonResidents(owned), [TownResident.c035_beaty]);
  });

  test('mother and daughter share a shopping visit but keep ordinary locations otherwise', () {
    const mother = TownResident.c051_dog_aunt;
    const daughter = TownResident.c050_nailist;
    const owned = [mother, daughter];
    final visit = TownVisit(
      random: ScriptedTownRandom([0]), familyOutingOverride: true);
    expect(visit.isFamilyOuting(owned, 180), false,
      reason: 'The story has not ended; do not draw even in debug override');
    expect(areaResidents(owned, TownArea.shopping,
      lifetimePoints: 180, visit: visit), isEmpty);
    expect(visit.isFamilyOuting(owned, 179, afterOyasumiClub: true), false,
      reason: 'Shopping must be unlocked first');
    expect(visit.isFamilyOuting([mother], 180, afterOyasumiClub: true), false,
      reason: 'The daughter must be acquired');
    expect(visit.isFamilyOuting(owned, 180, afterOyasumiClub: true), true);
    expect(areaResidents(owned, TownArea.shopping,
      lifetimePoints: 180, visit: visit, afterOyasumiClub: true),
      [mother, daughter]);
    for (final area in [TownArea.plaza, TownArea.park, TownArea.village]) {
      expect(areaResidents(owned, area,
        lifetimePoints: 180, visit: visit, afterOyasumiClub: true), isEmpty);
    }
    expect(visit.isFamilyOuting(owned, 180, afterOyasumiClub: true), true,
      reason: 'The selection remains stable during the same town visit');
    expect(visit.nextFamilyOutingDialogueId(mother), '051_dog_aunt_020');
    expect(visit.nextFamilyOutingDialogueId(mother), '051_dog_aunt_021');
    expect(visit.nextFamilyOutingDialogueId(daughter), '050_nailist_028');
    expect(visit.nextFamilyOutingDialogueId(daughter), '050_nailist_029');

    final ordinary = TownVisit(
      random: ScriptedTownRandom([2]), familyOutingOverride: false);
    expect(areaResidents(owned, TownArea.shopping,
      lifetimePoints: 180, visit: ordinary, afterOyasumiClub: true),
      [mother]);
    expect(areaResidents(owned, TownArea.plaza,
      lifetimePoints: 180, visit: ordinary, afterOyasumiClub: true),
      isEmpty);
  });

  test('debug preview keeps CMS homes even before area unlock', () {
    const preview = [
      TownResident.shiba, TownResident.rabbit, TownResident.cat, TownResident.bear,
    ];
    final visit = TownVisit(random: ScriptedTownRandom([]));
    for (final area in TownArea.values) {
      expect(areaResidents(const [], area, lifetimePoints: 0,
          visit: visit, debugOverride: preview),
          preview.where((resident) => resident.homeAreaId == area.id).toList());
    }
  });

  testWidgets('facility debug modes override only salon entry temporarily',
      (tester) async {
    tester.view.physicalSize = const Size(430, 930);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Widget scene(SalonUnlockDebugMode mode, {
      List<TownResident> owned = const [TownResident.c031_kimono_fox],
    }) => MaterialApp(
      // A debug-mode change starts a fresh route tree after returning from
      // the salon, so an outgoing route cannot intercept the next door tap.
      key: ValueKey(mode),
      home: Scaffold(
        body: TownAreaNavigator(
          area: TownArea.village,
          onAreaChanged: (_) {},
          lifetimePoints: 0,
          residents: owned,
          salonUnlockMode: mode,
        ),
      ),
    );

    const markerKey = ValueKey('village-salon-open-marker');
    await tester.pumpWidget(scene(SalonUnlockDebugMode.forceOpen));
    expect(find.byKey(const ValueKey('village-salon-entrance')),
        findsOneWidget, reason: 'Debug override reaches locked village door');
    expect(find.byKey(markerKey), findsOneWidget);
    await tester.tap(find.byKey(markerKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(SalonRoom), findsOneWidget);
    expect(find.byKey(const ValueKey('salon-resident-035_beaty')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('salon-fox-resident')),
        findsNothing, reason: 'おししょうさん teaches at the community center');
    await tester.tap(find.byKey(const ValueKey('salon-return-village')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.pumpWidget(scene(
      SalonUnlockDebugMode.forceClosed,
      owned: const [TownResident.c035_beaty],
    ));
    await tester.pump();
    expect(find.byKey(markerKey), findsNothing);
    await tester.tap(find.byKey(const ValueKey('village-salon-entrance')));
    await tester.pump();
    expect(find.text('デバッグ設定で桜の美容室を未開放にしています'),
        findsOneWidget);
    expect(find.byType(SalonRoom), findsNothing);

    await tester.pumpWidget(scene(SalonUnlockDebugMode.normal));
    await tester.pump();
    expect(find.text('まだ行けないエリアだよ'), findsOneWidget);
    expect(find.byKey(const ValueKey('village-salon-entrance')), findsNothing);
    expect(find.byKey(markerKey), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('salon opens with owner, not with its fox employee',
      (tester) async {
    tester.view.physicalSize = const Size(430, 930);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Widget app(List<TownResident> owned) => MaterialApp(
      home: Scaffold(
        body: TownAreaNavigator(
          area: TownArea.village,
          onAreaChanged: (_) {},
          lifetimePoints: 300,
          residents: owned,
        ),
      ),
    );

    // The fox can live in the salon without ever unlocking its entrance.
    await tester.pumpWidget(app(const [TownResident.c031_kimono_fox]));
    final entrance = find.byKey(const ValueKey('village-salon-entrance'));
    final marker = find.byKey(const ValueKey('village-salon-open-marker'));
    expect(entrance, findsOneWidget);
    expect(marker, findsNothing,
        reason: 'The employee alone does not open the salon');
    await tester.tap(entrance);
    await tester.pump();
    expect(find.textContaining('おしゃれさんをガチャでお迎えすると'),
        findsOneWidget);
    expect(find.byType(SalonRoom), findsNothing);

    // Once the owner is acquired, the sign appears and also opens the door.
    await tester.pumpWidget(app(const [TownResident.c035_beaty]));
    expect(marker, findsOneWidget);
    await tester.tap(marker);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(SalonRoom), findsOneWidget);
    expect(find.byKey(const ValueKey('salon-fox-resident')), findsNothing);
    expect(find.byKey(const ValueKey('salon-resident-035_beaty')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('village front door can be tapped without intercepting other areas',
      (tester) async {
    tester.view.physicalSize = const Size(430, 930);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var visits = 0;
    Future<void> show(TownArea area) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TownScene(
            area: area,
            lifetimePoints: 300,
            residents: const [],
            fillViewport: true,
            showSalonEntranceMarker: area == TownArea.village && visits == 1,
            onEnterSalon: () => visits++,
          ),
        ),
      ));
      await tester.pump();
    }

    const markerKey = ValueKey('village-salon-open-marker');
    await show(TownArea.plaza);
    expect(find.byKey(const ValueKey('village-salon-entrance')), findsNothing);
    expect(find.byKey(markerKey), findsNothing);

    await show(TownArea.village);
    final door = find.byKey(const ValueKey('village-salon-entrance'));
    expect(door, findsOneWidget);
    expect(find.byKey(markerKey), findsNothing);
    await tester.tap(door);
    await tester.pump();
    expect(visits, 1);

    await show(TownArea.village);
    final marker = find.byKey(markerKey);
    expect(marker, findsOneWidget);
    final doorRect = tester.getRect(door);
    final markerRect = tester.getRect(marker);
    expect(markerRect.bottom, lessThan(doorRect.top));
    expect(markerRect.center.dx, lessThan(doorRect.center.dx));
    await tester.tap(marker);
    await tester.pump();
    expect(visits, 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });


  testWidgets('town area name and counter clear the pinned HUD at every width',
      (tester) async {
    addTearDown(tester.view.reset);
    for (final width in [320.0, 390.0, 680.0]) {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      for (final area in [TownArea.plaza, TownArea.park, TownArea.village]) {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: PinnedGachaHud(
              points: 20,
              contentBehindHud: true,
              contentBuilder: (context, height) => TownAreaNavigator(
                area: area,
                onAreaChanged: (_) {},
                lifetimePoints: 300,
                residents: const [],
              ),
            ),
          ),
        ));
        await tester.pump();

        final hud = tester.getRect(find.byKey(const ValueKey('kotohogi-bar-art')));
        final name = tester.getRect(find.byKey(const ValueKey('town-area-name')));
        final counter = tester.getRect(find.text(
            '${area.index + 1} / ${unlockedTownAreas(300).length}'));
        expect(name.top, greaterThan(hud.bottom + 8),
            reason: '$area at width $width overlaps the pinned currency HUD');
        expect(counter.top, greaterThanOrEqualTo(name.bottom),
            reason: '$area at width $width overlaps its page counter');
        expect(tester.takeException(), isNull);
      }
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('shopping area label hangs in the lantern gap', (tester) async {
    tester.view.physicalSize = const Size(320, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Widget scene(int points, TownArea area) => MaterialApp(
      home: Scaffold(
        body: TownAreaNavigator(
          area: area,
          onAreaChanged: (_) {},
          lifetimePoints: points,
          residents: const [],
        ),
      ),
    );

    await tester.pumpWidget(scene(180, TownArea.shopping));
    await tester.pump();
    final sign = find.byKey(const ValueKey('town-area-hanging-sign'));
    final frame = tester.getRect(find.byType(TownAreaNavigator));
    expect(sign, findsOneWidget);
    expect(find.byKey(const ValueKey('town-area-name')), findsOneWidget);
    expect(find.text('ことほぎ商店街'), findsWidgets);
    expect(find.text('3 / 3'), findsOneWidget);
    final signRect = tester.getRect(sign);
    // Phone width: the sign must clear the arrow/counter rather than
    // overlapping the navigation row.
    expect(signRect.top, closeTo(frame.top + 148, 1));
    expect(signRect.center.dx, closeTo(frame.center.dx, 1));
    expect(signRect.top, greaterThan(
        tester.getRect(find.text('3 / 3')).bottom + 8));
    expect(tester.takeException(), isNull);

    // Wide iPad layout: the sign stays in the sky above the shrine roof,
    // not halfway down the background as it did at 50% of scene width.
    tester.view.physicalSize = const Size(968, 1250);
    await tester.pumpWidget(scene(180, TownArea.shopping));
    await tester.pump();
    final wideFrame = tester.getRect(find.byType(TownAreaNavigator));
    final wideSign = tester.getRect(sign);
    expect(wideSign.top, closeTo(wideFrame.top + wideFrame.width * .23, 1));
    expect(wideSign.center.dx, closeTo(wideFrame.center.dx, 1));
    expect(wideSign.top, greaterThan(
        tester.getRect(find.text('3 / 3')).bottom + 8));
    expect(tester.takeException(), isNull);

    // A locked shopping area has no lantern art to attach a sign to.
    await tester.pumpWidget(scene(179, TownArea.shopping));
    expect(sign, findsNothing);
    expect(find.byKey(const ValueKey('town-area-name')), findsOneWidget);
    expect(find.byKey(const ValueKey('town-area-next')), findsNothing);
    expect(find.text('未開放'), findsOneWidget);
    expect(find.text('3 / 3'), findsNothing);

    // Other neighborhoods keep the normal top navigation heading.
    await tester.pumpWidget(scene(180, TownArea.park));
    expect(sign, findsNothing);
    expect(find.byKey(const ValueKey('town-area-name')), findsOneWidget);
    expect(find.text('2 / 3'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  test('shopping PNG uses its declared 768x1376 source dimensions', () {
    final file = File('assets/kotohogu/street_background_001.png');
    expect(file.existsSync(), isTrue);
    final dims = _imageDimensions(file.readAsBytesSync());
    expect(dims.$1, TownArea.shopping.sourceWidth);
    expect(dims.$2, TownArea.shopping.sourceHeight);
    expect(dims, (768, 1376));
  });

  testWidgets('shopping and plaza sprites use matching source-size scale',
      (tester) async {
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Future<double> spriteWidth(TownArea area) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: TownScene(
              area: area,
              lifetimePoints: 300,
              residents: const [],
              debugTownResidents: area == TownArea.shopping
                  ? const [TownResident.cat]
                  : const [TownResident.shiba],
              fillViewport: true,
            ),
          ),
        ),
      ));
      await tester.pump();
      final sprite = find.byKey(const ValueKey('resident-sprite-0'));
      expect(sprite, findsOneWidget);
      expect(tester.takeException(), isNull);
      return tester.getRect(sprite).width;
    }

    final plazaWidth = await spriteWidth(TownArea.plaza);
    final shoppingWidth = await spriteWidth(TownArea.shopping);
    expect(shoppingWidth, closeTo(plazaWidth, 1.0),
        reason: 'street background is wider but walkers should not shrink');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('navigation hides locked destinations and blocks swipes',
      (tester) async {
    tester.view.physicalSize = const Size(430, 930);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var points = 0;
    var area = TownArea.plaza;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: StatefulBuilder(builder: (context, setState) {
        return TownAreaNavigator(
          area: area,
          onAreaChanged: (next) => setState(() => area = next),
          lifetimePoints: points,
          residents: const [
            TownResident.shiba, TownResident.rabbit,
            TownResident.squirrel, TownResident.c026_farmer,
          ],
        );
      })),
    ));
    Future<void> refresh(int amount) async {
      points = amount;
      // Updating the displayed widget rebuilds with the new earned points.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: StatefulBuilder(builder: (context, setState) {
          return TownAreaNavigator(
            area: area,
            onAreaChanged: (next) => setState(() => area = next),
            lifetimePoints: points,
            residents: const [
              TownResident.shiba, TownResident.rabbit,
              TownResident.squirrel, TownResident.c026_farmer,
            ],
          );
        })),
      ));
      await tester.pump();
    }

    // Zero points means only the plaza exists: no arrows or navigation band.
    expect(find.byKey(const ValueKey('town-area-next')), findsNothing);
    expect(find.byKey(const ValueKey('town-area-previous')), findsNothing);
    expect(find.byKey(const ValueKey('town-area-name')), findsNothing);
    await tester.drag(
        find.byType(TownAreaNavigator), const Offset(-170, 0));
    await tester.pump();
    expect(area, TownArea.plaza);

    await refresh(89);
    expect(find.byKey(const ValueKey('town-area-next')), findsNothing);
    await refresh(90);
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.byKey(const ValueKey('town-area-next')), findsOneWidget);
    expect(find.byKey(const ValueKey('town-area-previous')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('town-area-next')));
    await tester.pump();
    expect(area, TownArea.park);
    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.byKey(const ValueKey('town-background')), findsOneWidget);
    // This visit began before the unlock, so its residents stay at the plaza.
    expect(find.byKey(const ValueKey('resident-0')), findsNothing);
    expect(find.byKey(const ValueKey('resident-1')), findsNothing);
    expect(find.byKey(const ValueKey('town-area-next')), findsNothing);
    expect(find.byKey(const ValueKey('town-area-previous')), findsOneWidget);
    await tester.drag(
        find.byType(TownAreaNavigator), const Offset(-170, 0));
    await tester.pump();
    expect(area, TownArea.park);
    expect(find.text('まだ行けないエリアだよ'), findsNothing);

    await refresh(179);
    expect(find.byKey(const ValueKey('town-area-next')), findsNothing);
    await refresh(180);
    expect(find.text('2 / 3'), findsOneWidget);
    expect(find.byKey(const ValueKey('town-area-next')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('town-area-next')));
    await tester.pump();
    expect(area, TownArea.shopping);
    expect(find.text('3 / 3'), findsOneWidget);
    expect(find.byKey(const ValueKey('town-area-next')), findsNothing);
    await refresh(299);
    expect(find.byKey(const ValueKey('town-area-next')), findsNothing);
    await refresh(300);
    expect(find.text('3 / 4'), findsOneWidget);
    expect(find.byKey(const ValueKey('town-area-next')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('town-area-next')));
    await tester.pump();
    expect(area, TownArea.village);
    expect(find.text('4 / 4'), findsOneWidget);
    expect(find.byKey(const ValueKey('town-area-next')), findsNothing);
    expect(find.byKey(const ValueKey('town-area-previous')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('debug resident preview still navigates locked areas',
      (tester) async {
    tester.view.physicalSize = const Size(430, 930);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var area = TownArea.plaza;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: StatefulBuilder(builder: (context, setState) {
        return TownAreaNavigator(
          area: area,
          onAreaChanged: (next) => setState(() => area = next),
          lifetimePoints: 0,
          residents: const [],
          debugTownResidents: const [],
        );
      })),
    ));
    for (var i = 0; i < TownArea.values.length - 1; i++) {
      expect(find.byKey(const ValueKey('town-area-next')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('town-area-next')));
      await tester.pump();
    }
    expect(area, TownArea.hospital);
    expect(find.byKey(const ValueKey('town-background')), findsOneWidget);
    expect(find.text('未開放'), findsOneWidget,
        reason: 'Debug-only access does not affect area counts');
    expect(find.text('4 / 4'), findsNothing);
    expect(find.byKey(const ValueKey('town-area-next')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}

/// Read only the PNG IHDR / JPEG SOF size fields; no asynchronous image
/// decoding or test-engine frame scheduling is involved.
(int, int) _imageDimensions(Uint8List data) {
  if (data.length < 24) {
    throw const FormatException('Image is too short for dimension metadata');
  }
  final header = ByteData.sublistView(data);
  const png = [137, 80, 78, 71, 13, 10, 26, 10];
  if (List.generate(8, (i) => data[i]).toString() == png.toString()) {
    if (String.fromCharCodes(data.sublist(12, 16)) != 'IHDR') {
      throw const FormatException('PNG has no IHDR header');
    }
    return (
      header.getUint32(16, Endian.big),
      header.getUint32(20, Endian.big),
    );
  }
  if (data[0] == 0xff && data[1] == 0xd8) {
    var index = 2;
    while (index + 4 < data.length) {
      if (data[index] != 0xff) {
        throw FormatException('Invalid JPEG marker at byte $index');
      }
      while (index < data.length && data[index] == 0xff) {
        index++;
      }
      if (index >= data.length) break;
      final marker = data[index++];
      if (marker == 0xd9 || marker == 0xda) break;
      if (marker == 0x01 || marker >= 0xd0 && marker <= 0xd7) {
        continue;
      }
      if (index + 2 > data.length) break;
      final length = header.getUint16(index, Endian.big);
      if (length < 2 || index + length > data.length) {
        throw FormatException('Invalid JPEG segment length: $length');
      }
      if ((marker >= 0xc0 && marker <= 0xc3) ||
          (marker >= 0xc5 && marker <= 0xc7) ||
          (marker >= 0xc9 && marker <= 0xcb) ||
          (marker >= 0xcd && marker <= 0xcf)) {
        if (length < 7) throw const FormatException('Invalid JPEG SOF');
        return (
          header.getUint16(index + 5, Endian.big),
          header.getUint16(index + 3, Endian.big),
        );
      }
      index += length;
    }
    throw const FormatException('JPEG has no supported SOF segment');
  }
  throw const FormatException('Only PNG and JPEG town art is supported');
}
