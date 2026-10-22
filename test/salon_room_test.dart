import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:future_lift/resident_collection.dart';
import 'package:future_lift/salon_room.dart';
import 'package:future_lift/facility_layout.dart';
import 'package:future_lift/town_areas.dart';

void main() {
  test('salon residents need to be acquired and never walk outdoors', () {
    expect(SalonRoom.host, TownResident.c035_beaty);
    expect(TownResident.c038_lion_lady.id, '038_lion_lady');
    expect(TownResident.c038_lion_lady.inGacha, true);
    expect(TownResident.c038_lion_lady.walkInTown, true);
    expect(TownResident.c038_lion_lady.homeAreaId, 'salon');
    expect(TownResident.c035_beaty.homeAreaId, 'salon');
    expect(TownResident.c035_beaty.inGacha, true);
    expect(TownResident.c035_beaty.walkInTown, false);
    const nailist = TownResident.c050_nailist;
    expect(nailist.inGacha, isTrue);
    expect(nailist.homeAreaId, 'salon');
    expect(nailist.walkInTown, isFalse);
    expect(salonResidents([nailist]), [nailist]);
    expect(salonResidents([TownResident.c035_beaty, nailist]),
        [TownResident.c035_beaty, nailist]);
    expect(isSalonUnlocked(const []), isFalse);
    expect(isSalonUnlocked([TownResident.c038_lion_lady]), isFalse);
    expect(isSalonUnlocked([TownResident.c035_beaty]), isTrue);
    expect(salonResidents(const []), isEmpty);
    expect(salonResidents([TownResident.c038_lion_lady]), [TownResident.c038_lion_lady]);
    expect(salonResidents([TownResident.c035_beaty]),
        [TownResident.c035_beaty]);
    expect(salonResidents([TownResident.c038_lion_lady, TownResident.c035_beaty]),
        [TownResident.c035_beaty, TownResident.c038_lion_lady]);
    expect(TownResident.gachaPool, contains(TownResident.c035_beaty));
    expect(TownResident.gachaPool, contains(TownResident.c038_lion_lady));
    expect(TownResident.gachaPool, contains(TownResident.c050_nailist));
    expect(isSalonUnlocked([TownResident.c050_nailist]), isFalse);
    expect(visibleTownResidents(TownResident.values),
        isNot(contains(TownResident.c050_nailist)));
    expect(areaResidents(TownResident.values, TownArea.plaza,
        lifetimePoints: 500, visit: TownVisit()),
        isNot(contains(TownResident.c050_nailist)));
    expect(areaResidents(TownResident.values, TownArea.village,
        lifetimePoints: 300, visit: TownVisit()),
        isNot(contains(TownResident.c038_lion_lady)));
    expect(visibleTownResidents(TownResident.values),
        isNot(contains(TownResident.c038_lion_lady)));
    expect(visibleTownResidents(TownResident.values),
        isNot(contains(TownResident.c035_beaty)));
    expect(areaResidents(TownResident.values, TownArea.shopping,
        lifetimePoints: 300, visit: TownVisit()),
        isNot(contains(TownResident.c035_beaty)));
  });

  test('debug salon modes respect ownership in normal mode', () {
    const foxOnly = [TownResident.c038_lion_lady];
    const ownerOnly = [TownResident.c035_beaty];
    expect(isSalonAccessible(foxOnly), isFalse);
    expect(isSalonAccessible(foxOnly,
        debugMode: SalonUnlockDebugMode.forceOpen), isTrue);
    expect(isSalonAccessible(ownerOnly,
        debugMode: SalonUnlockDebugMode.forceClosed), isFalse);
    expect(isSalonAccessible(ownerOnly), isTrue);
    expect(isSalonUnlocked(foxOnly), isFalse);
    expect(isSalonUnlocked(ownerOnly), isTrue);
    expect(salonResidents(foxOnly), foxOnly);
    expect(salonResidents(const [], previewUnowned: true),
        [TownResident.c035_beaty, TownResident.c038_lion_lady,
         TownResident.c050_nailist]);
  });

  test('one shared display size applies to every facility resident', () {
    final salon = facilityPlacements('salon');
    expect(salon.map((p) => p.residentId), [
      TownResident.c035_beaty.id,
      TownResident.c038_lion_lady.id,
      TownResident.c050_nailist.id,
    ]);
    expect(salon.map((p) => p.size).toSet(), {230.0});
    expect(facilityPlacements('bakery').map((p) => p.size).toSet(), {235.0});
    expect(
      (salon.singleWhere((p) => p.residentId == TownResident.c035_beaty.id).y
          + 230),
      710,
      reason: 'Resizing must keep the owner at the original floor position',
    );
    expect(
      (salon.singleWhere((p) => p.residentId == TownResident.c038_lion_lady.id).y
          + 230),
      1005,
      reason: 'Resizing must keep the other resident at the original floor position',
    );
  });

  testWidgets('forced preview renders all unowned salon characters',
      (tester) async {
    tester.view.physicalSize = const Size(430, 930);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(
      home: SalonRoom(previewUnownedResidents: true),
    ));
    expect(find.byKey(const ValueKey('salon-resident-035_beaty')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('salon-resident-038_lion_lady')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('salon-resident-050_nailist')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  test('nailist has a first greeting, fashion talk, and practical care tips', () {
    final root = jsonDecode(File('assets/dialogues/dialogues.json').readAsStringSync()) as Map<String,dynamic>;
    final messages = (root['dialogues'] as List)
        .where((row) => row['residentId'] == '050_nailist').toList();
    expect(messages.length, greaterThanOrEqualTo(24));
    expect(messages.where((row) => row['firstGreeting'] == true).length, 1);
    expect(messages.any((row) => (row['text'] as String).contains('頭皮までシャワー')), isTrue);
    expect(messages.any((row) => (row['text'] as String).contains('ネイル')), isTrue);
    expect(messages.any((row) => (row['text'] as String).contains('洗濯物')), isTrue);
    expect(messages.any((row) => (row['text'] as String).contains('手伝って')), isTrue);
  });

  testWidgets('owned nailist appears in the salon and can be spoken to',
      (tester) async {
    tester.view.physicalSize = const Size(430, 930);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final spoken = <TownResident>[];
    await tester.pumpWidget(MaterialApp(
      home: SalonRoom(
        ownedResidents: const [TownResident.c035_beaty, TownResident.c050_nailist],
        onResident: (resident) async { spoken.add(resident); },
      ),
    ));
    final nailist = find.byKey(const ValueKey('salon-resident-050_nailist'));
    final owner = find.byKey(const ValueKey('salon-resident-035_beaty'));
    expect(nailist, findsOneWidget);
    expect(owner, findsOneWidget);
    expect(tester.getRect(nailist).overlaps(tester.getRect(owner)), isFalse);
    await tester.tap(nailist);
    await tester.pump();
    expect(spoken, [TownResident.c050_nailist]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('both acquired salon residents appear and can talk',
      (tester) async {
    tester.view.physicalSize = const Size(430, 930);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final spoken = <TownResident>[];
    await tester.pumpWidget(MaterialApp(
      home: SalonRoom(
        ownedResidents: const [
          TownResident.c035_beaty, TownResident.c038_lion_lady,
        ],
        onResident: (resident) async {
          spoken.add(resident);
        },
      ),
    ));
    final fox = find.byKey(const ValueKey('salon-resident-038_lion_lady'));
    final tsuya = find.byKey(const ValueKey('salon-resident-035_beaty'));
    expect(fox, findsOneWidget);
    expect(tsuya, findsOneWidget);
    expect(tester.getRect(fox).overlaps(tester.getRect(tsuya)), isFalse);
    expect(find.byKey(const ValueKey('salon-sprite-035_beaty')), findsOneWidget);
    await tester.tap(tsuya);
    await tester.pump();
    await tester.tap(fox);
    await tester.pump();
    expect(spoken, [TownResident.c035_beaty, TownResident.c038_lion_lady]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });


  testWidgets('owner and fox stand deeper in the salon at stable spots',
      (tester) async {
    tester.view.physicalSize = const Size(430, 930);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Future<void> show(List<TownResident> owned) async {
      await tester.pumpWidget(MaterialApp(
        home: SalonRoom(ownedResidents: owned),
      ));
      await tester.pump();
    }

    Positioned station(String key) => tester.widget<Positioned>(
      find.ancestor(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(Positioned),
      ).first,
    );

    await show(const [TownResident.c038_lion_lady]);
    final foxOnly = find.byKey(const ValueKey('salon-resident-038_lion_lady'));
    expect(foxOnly, findsOneWidget);
    expect(station('salon-resident-038_lion_lady').left, 182);
    expect(station('salon-resident-038_lion_lady').top, 775);
    expect(station('salon-resident-038_lion_lady').width, 230);
    expect(station('salon-resident-038_lion_lady').height, 230);
    // Enlarging changes neither the center nor the feet position.
    expect(station('salon-resident-038_lion_lady').left! +
        station('salon-resident-038_lion_lady').width! / 2, 297);
    expect(station('salon-resident-038_lion_lady').top! +
        station('salon-resident-038_lion_lady').height!, 1005);
    final foxPosition = tester.getRect(foxOnly);

    await show(const [
      TownResident.c035_beaty, TownResident.c038_lion_lady,
    ]);
    expect(tester.getRect(foxOnly), foxPosition,
        reason: 'Acquiring the owner must not relocate the fox');
    final owner = station('salon-resident-035_beaty');
    expect(owner.left, 350);
    expect(owner.top, 480);
    expect(owner.width, 230);
    expect(owner.height, 230);
    expect(station('salon-resident-038_lion_lady').width, owner.width,
        reason: 'All salon characters must use one shared sprite size');
    expect(tester.getRect(
        find.byKey(const ValueKey('salon-resident-035_beaty')))
        .overlaps(tester.getRect(foxOnly)), isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('fox steps in place, claps, and pauses for dialogue',
      (tester) async {
    tester.view.physicalSize = const Size(430, 930);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final gate = Completer<void>();
    var conversations = 0;
    await tester.pumpWidget(MaterialApp(
      home: SalonRoom(
        ownedResidents: const [TownResident.c038_lion_lady],
        onResident: (_) {
        conversations++;
        return gate.future;
      }),
    ));
    final fox = find.byKey(const ValueKey('salon-resident-038_lion_lady'));
    final sprite = find.byKey(const ValueKey('salon-sprite-038_lion_lady'));
    String asset() => (tester.widget<Image>(sprite).image as AssetImage).assetName;
    final position = tester.getRect(fox);

    expect(asset(), TownResident.c038_lion_lady.idleAsset);
    await tester.pump(const Duration(milliseconds: 800));
    expect(asset(), TownResident.c038_lion_lady.walkAsset(WalkDirection.front, 0));
    await tester.pump(const Duration(milliseconds: 200));
    expect(asset(), TownResident.c038_lion_lady.walkAsset(WalkDirection.front, 1));
    await tester.pump(const Duration(milliseconds: 5400));
    expect(asset(), TownResident.c038_lion_lady.clapAssets[0]);
    await tester.pump(const Duration(milliseconds: 400));
    expect(asset(), TownResident.c038_lion_lady.clapAssets[1]);
    expect(tester.getRect(fox), position);

    await tester.tap(fox);
    await tester.pump();
    expect(conversations, 1);
    expect(asset(), TownResident.c038_lion_lady.idleAsset);
    await tester.pump(const Duration(seconds: 3));
    expect(asset(), TownResident.c038_lion_lady.idleAsset);
    await tester.tap(fox);
    await tester.pump();
    expect(conversations, 1, reason: 'Do not start overlapping conversations');

    gate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(asset(), TownResident.c038_lion_lady.clapAssets[1]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reduced motion keeps salon fox idle', (tester) async {
    tester.view.physicalSize = const Size(430, 930);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: const SalonRoom(
          ownedResidents: [TownResident.c038_lion_lady],
        ),
      ),
    ));
    final sprite = find.byKey(const ValueKey('salon-sprite-038_lion_lady'));
    String asset() => (tester.widget<Image>(sprite).image as AssetImage).assetName;
    expect(asset(), TownResident.c038_lion_lady.idleAsset);
    await tester.pump(const Duration(seconds: 10));
    expect(asset(), TownResident.c038_lion_lady.idleAsset);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an acquired fox can use regular dialogue',
      (tester) async {
    tester.view.physicalSize = const Size(430, 930);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    TownResident? spokenTo;

    await tester.pumpWidget(MaterialApp(
      home: SalonRoom(
        ownedResidents: const [TownResident.c038_lion_lady],
        onResident: (resident) async {
        spokenTo = resident;
      }),
    ));
    await tester.pump();

    expect(find.byKey(const ValueKey('salon-background')), findsOneWidget);
    final host = find.byKey(const ValueKey('salon-resident-038_lion_lady'));
    expect(host, findsOneWidget);
    await tester.tap(host);
    await tester.pump();
    expect(spokenTo, TownResident.c038_lion_lady);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
