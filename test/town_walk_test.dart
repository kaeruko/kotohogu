import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:future_lift/resident_collection.dart';
import 'package:future_lift/town.dart';
import 'package:future_lift/town_areas.dart';
import 'package:future_lift/town_walk.dart';

import 'support/town_random.dart';

void main() {
  test('every stroll stays inside the plaza and cycles through all directions', () {
    for (var index = 0; index < townWalkSlots.length; index++) {
      final directions = <WalkDirection>{};
      var pauses = 0;
      for (var millis = 0; millis < 25600; millis += 150) {
        final pose = townWalkPose(index, Duration(milliseconds: millis));
        // A sprite takes at most 14% of the width and ~18% of height.
        expect(pose.x, inInclusiveRange(0, .86), reason: 'slot $index');
        expect(pose.y, inInclusiveRange(0, .82), reason: 'slot $index');
        expect(pose.frame, inInclusiveRange(0, 3));
        if (pose.direction case final direction?) {
          directions.add(direction);
        } else {
          pauses++;
        }
      }
      expect(directions, WalkDirection.values.toSet());
      expect(pauses, greaterThan(0));
    }
    expect(townWalkPose(0, Duration.zero).direction, WalkDirection.right);
    expect(townWalkPose(0, const Duration(milliseconds: 3000)).walking, false);
    expect(townWalkPose(0, const Duration(milliseconds: 3900)).direction,
        WalkDirection.front);
    expect(townWalkPose(0, const Duration(milliseconds: 6400)).direction,
        WalkDirection.left);
    expect(townWalkPose(0, const Duration(milliseconds: 10300)).direction,
        WalkDirection.back);
    expect(townWalkPose(0, const Duration(milliseconds: 12800)).direction,
        WalkDirection.right);
    expect(() => townWalkPose(-1, Duration.zero), throwsRangeError);
    expect(townWalkPose(8, Duration.zero, totalSlots: 12).x,
        inInclusiveRange(0, .86));
    expect(
      () => townWalkPose(12, Duration.zero, totalSlots: 12),
      throwsRangeError,
    );
  });

  test('more than eight walkers use distinct, bounded positions', () {
    for (final count in [9, 12, 25, 60]) {
      final origins = <(double, double)>{};
      for (var i = 0; i < count; i++) {
        final origin = townWalkOrigin(i, totalSlots: count);
        expect(origins.add(origin), isTrue, reason: 'duplicate slot $i');
        final pose = townWalkPose(
          i, const Duration(milliseconds: 1350), totalSlots: count);
        expect(pose.x, inInclusiveRange(0, .86));
        expect(pose.y, inInclusiveRange(0, .82));
      }
      expect(origins.length, count);
    }
    expect(() => townWalkOrigin(0, totalSlots: 0), throwsRangeError);
  });

  test('park favorites stay at landmarks regardless of collection order', () {
    const residents = [
      TownResident.c027_daydreamer,
      TownResident.c037_tora,
      TownResident.c026_farmer,
      TownResident.rabbit,
      TownResident.squirrel,
    ];
    final expected = <String, (double, double)>{
      '027_daydreamer': (.60, .63),
      '037_tora': (.63, .45),
      '026_farmer': (.45, .55),
      '02_rabbit': (.39, .46),
      '05_squirrel': (.30, .54),
    };
    for (var index = 0; index < residents.length; index++) {
      final id = residents[index].id;
      final route = parkWalkRoute(id, index, totalSlots: residents.length);
      expect((route.x, route.y), expected[id], reason: id);
      for (var millis = 0; millis < 26000; millis += 150) {
        final pose = townWalkPose(index, Duration(milliseconds: millis),
            totalSlots: residents.length, route: route);
        expect(pose.x, inInclusiveRange(route.x, route.x + route.width));
        expect(pose.y, inInclusiveRange(route.y, route.y + route.height));
        if (id == '027_daydreamer') {
          expect(pose.walking, false, reason: 'bench is for resting');
        }
      }
    }
    // Rearranging the owned cast never changes the favorite spot.
    expect(parkWalkRoute('027_daydreamer', 4, totalSlots: 5).x, .60);
    expect(parkWalkRoute('037_tora', 0, totalSlots: 5).x, .63);
    expect(townWalkPose(0, Duration.zero).x,
        townWalkOrigin(0, totalSlots: 8).$1);
  });

  test('park extra visitors get bounded paths and invalid routes fail fast', () {
    for (final count in [2, 8, 9, 25]) {
      final spots = <(double, double)>{};
      for (var slot = 0; slot < count; slot++) {
        final route = parkWalkRoute('visitor_$slot', slot,
            totalSlots: count);
        expect(spots.add((route.x, route.y)), isTrue);
        final pose = townWalkPose(slot,
            const Duration(milliseconds: 9500),
            totalSlots: count, route: route);
        expect(pose.x, inInclusiveRange(0, .86));
        expect(pose.y, inInclusiveRange(0, .82));
      }
    }
    expect(() => parkWalkRoute('stranger', -1, totalSlots: 2),
        throwsRangeError);
    expect(() => parkWalkRoute('stranger', 2, totalSlots: 2),
        throwsRangeError);
    expect(() => townWalkPose(0, Duration.zero,
        route: const TownWalkRoute(.84, .82, width: .05)),
        throwsRangeError);
  });

  test('sprite directions use the real files, shiba mirrors left explicitly', () {
    for (final resident in TownResident.values) {
      for (final direction in WalkDirection.values) {
        for (var frame = 0; frame < 4; frame++) {
          final path = resident.walkAsset(direction, frame);
          final suffix = (frame + 1).toString().padLeft(2, '0');
          final assetDirection = direction == WalkDirection.left &&
                  resident == TownResident.shiba
              ? 'right'
              : direction.name;
          expect(path, endsWith('walk_${assetDirection}_$suffix.png'));
        }
      }
      expect(resident.mirrorWalk(WalkDirection.left),
          resident == TownResident.shiba);
      expect(() => resident.walkAsset(WalkDirection.front, -1),
          throwsRangeError);
      expect(() => resident.walkAsset(WalkDirection.front, 4),
          throwsRangeError);
    }
  });

  testWidgets('all referenced walking PNGs are bundled with Flutter', (tester) async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    for (final resident in TownResident.values) {
      expect(manifest.listAssets().contains(resident.idleAsset), true);
      for (final direction in WalkDirection.values) {
        for (var frame = 0; frame < 4; frame++) {
          final asset = resident.walkAsset(direction, frame);
          expect(manifest.listAssets().contains(asset), true,
              reason: 'Missing $asset in pubspec.yaml');
        }
      }
    }
  });

  testWidgets('walkers move with sprites and pause while talking', (tester) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final gate = Completer<void>();
    var conversations = 0;
    Widget scene(List<TownResident> residents) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 360,
            child: TownScene(
              level: 0,
              lifetimePoints: 0,
              residents: residents,
              onResident: (_) async {
                conversations++;
                await gate.future;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(scene([TownResident.shiba, TownResident.rabbit]));
    final shiba = find.byKey(const ValueKey('resident-0'));
    final sprite = find.byKey(const ValueKey('resident-sprite-0'));
    expect(shiba, findsOneWidget);
    expect(find.byKey(const ValueKey('resident-1')), findsOneWidget);
    AssetImage source() => tester.widget<Image>(sprite).image as AssetImage;
    expect(source().assetName, TownResident.shiba.walkAsset(WalkDirection.right, 0));
    final initialPosition = tester.getTopLeft(shiba);
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.getTopLeft(shiba).dx, greaterThan(initialPosition.dx));
    expect(source().assetName, contains('/walk_right_'));
    await tester.tap(shiba);
    await tester.pump();
    expect(conversations, 1);
    expect(source().assetName, TownResident.shiba.idleAsset);
    final stoppedAt = tester.getTopLeft(shiba);
    await tester.pump(const Duration(seconds: 2));
    expect(tester.getTopLeft(shiba), stoppedAt);
    expect(source().assetName, TownResident.shiba.idleAsset);

    gate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(source().assetName, contains('/walk_right_'));
    expect(tester.getTopLeft(shiba).dx, greaterThan(stoppedAt.dx));

    // Gacha additions also get their own independent walker.
    await tester.pumpWidget(scene([
      TownResident.shiba, TownResident.rabbit, TownResident.penguin,
    ]));
    expect(find.byKey(const ValueKey('resident-2')), findsOneWidget);
    // The penguin joins during its natural rest phase, then starts walking.
    final joiningSprite = tester.widget<Image>(
      find.byKey(const ValueKey('resident-sprite-2')),
    );
    expect((joiningSprite.image as AssetImage).assetName,
        TownResident.penguin.idleAsset);
    await tester.pump(const Duration(milliseconds: 900));
    final walkingSprite = tester.widget<Image>(
      find.byKey(const ValueKey('resident-sprite-2')),
    );
    expect((walkingSprite.image as AssetImage).assetName,
        contains('/walk_'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });


  testWidgets('owned walkers appear together, then move home when unlocked',
      (tester) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const owned = [
      TownResident.shiba,
      TownResident.rabbit,
      TownResident.cat,
      TownResident.bear,
      TownResident.c035_beaty,
      TownResident.c031_kimono_fox,
    ];

    Future<void> show(TownArea area, int points,
        List<TownResident> expected) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: TownScene(
              level: 0,
              area: area,
              lifetimePoints: points,
              residents: owned,
              fillViewport: true,
            ),
          ),
        ),
      ));
      for (var index = 0; index < expected.length; index++) {
        final finder = find.byKey(ValueKey('resident-sprite-$index'));
        expect(finder, findsOneWidget,
            reason: '${area.id} at $points, walker $index');
        final image = tester.widget<Image>(finder).image as AssetImage;
        expect(image.assetName, expected[index].idleAsset);
      }
      expect(find.byKey(ValueKey('resident-${expected.length}')),
          findsNothing, reason: 'No extra walker in ${area.id}');
      expect(tester.takeException(), isNull);
    }

    // Before the park opens, all four outdoor friends gather in the plaza.
    await show(TownArea.plaza, 10, const [
      TownResident.shiba, TownResident.rabbit,
      TownResident.cat, TownResident.bear,
    ]);
    await show(TownArea.plaza, 90, const [
      TownResident.shiba, TownResident.cat, TownResident.bear,
    ]);
    await show(TownArea.park, 90, const [TownResident.rabbit]);
    await show(TownArea.plaza, 180, const [
      TownResident.shiba, TownResident.bear,
    ]);
    await show(TownArea.shopping, 180, const [TownResident.cat]);
    await show(TownArea.plaza, 300, const [TownResident.shiba]);
    await show(TownArea.village, 300, const [TownResident.bear]);
    await tester.pumpWidget(const SizedBox());
  });


  testWidgets('walkers grow with depth without moving their foot anchors',
      (tester) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const residents = [
      TownResident.cat,
      TownResident.c009_chef,
      TownResident.c032_miner,
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 360,
            child: MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: TownScene(
                level: 0,
                area: TownArea.shopping,
                lifetimePoints: 300,
                residents: residents,
              ),
            ),
          ),
        ),
      ),
    ));
    final townRect = tester.getRect(find.byType(TownScene));
    final originalSize =
        (townRect.width * .14).clamp(22.0, 76.0).toDouble();
    const expectedScales = [1.2, 1.2, 1.4];
    for (var index = 0; index < residents.length; index++) {
      final sprite = find.byKey(ValueKey('resident-sprite-$index'));
      final image = tester.widget<Image>(sprite);
      final rect = tester.getRect(sprite);
      final origin = townWalkOrigin(index, totalSlots: residents.length);
      expect(image.width, closeTo(originalSize * expectedScales[index], .01));
      expect(image.height, closeTo(image.width!, .01));
      // The old sprite's bottom-center is the fixed anchor, regardless
      // of its new visual size.
      expect(rect.center.dx,
          closeTo(townRect.left + townRect.width * origin.$1 +
              originalSize / 2, .01));
      expect(rect.bottom,
          closeTo(townRect.top + townRect.height * origin.$2 +
              originalSize, .01));
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('park idle sprites use their own favorite positions', (tester) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const residents = [
      TownResident.c027_daydreamer,
      TownResident.c037_tora,
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 360,
            child: MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: TownScene(
                level: 0,
                area: TownArea.park,
                lifetimePoints: 90,
                residents: residents,
              ),
            ),
          ),
        ),
      ),
    ));
    final rect = tester.getRect(find.byType(TownScene));
    final size = (rect.width * .14).clamp(22.0, 76.0).toDouble();
    for (var index = 0; index < residents.length; index++) {
      final route = parkWalkRoute(residents[index].id, index,
          totalSlots: residents.length);
      final sprite = tester.getRect(find.byKey(
          ValueKey('resident-sprite-$index')));
      expect(sprite.center.dx, closeTo(
          rect.left + rect.width * route.x + size / 2, .01));
      expect(sprite.bottom, closeTo(
          rect.top + rect.height * route.y + size, .01));
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('all town areas apply the new walker scale', (tester) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final residents = TownResident.values.toList();
    final visit = TownVisit(random: ScriptedTownRandom([
      for (var i = 0; i < visibleTownResidents(residents).length; i++) i % 4,
    ]));
    for (final area in TownArea.values) {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: TownScene(
              level: 0,
              area: area,
              visit: visit,
              lifetimePoints: 300,
              residents: residents,
              fillViewport: true,
            ),
          ),
        ),
      ));
      final active = areaResidents(residents, area,
          lifetimePoints: 300, visit: visit);
      expect(active, isNotEmpty);
      final base =
          (area.sourceWidth!.toDouble() * .14).clamp(22.0, 76.0).toDouble();
      final sprite = tester.widget<Image>(
          find.byKey(const ValueKey('resident-sprite-0')));
      expect(sprite.width, closeTo(base * 1.2, .01),
          reason: 'area: ${area.id}');
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reduced-motion mode shows only idle sprites', (tester) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: const TownScene(
                level: 0,
                lifetimePoints: 0,
                residents: [TownResident.shiba, TownResident.rabbit],
              ),
            ),
          ),
        ),
      ),
    );
    final sprite = find.byKey(const ValueKey('resident-sprite-0'));
    final shiba = find.byKey(const ValueKey('resident-0'));
    final initialPosition = tester.getTopLeft(shiba);
    expect((tester.widget<Image>(sprite).image as AssetImage).assetName,
        TownResident.shiba.idleAsset);
    await tester.pump(const Duration(seconds: 5));
    expect(tester.getTopLeft(shiba), initialPosition);
    expect((tester.widget<Image>(sprite).image as AssetImage).assetName,
        TownResident.shiba.idleAsset);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
