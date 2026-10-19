import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:future_lift/game_home.dart';
import 'package:future_lift/progress.dart';
import 'package:future_lift/resident_collection.dart';

void main() {
  testWidgets('home residents step in place using front walking sprites', (tester) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final talkedTo = <TownResident>[];
    final progress = Progress.empty(DateTime(2026, 10, 12));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GameHome(
            progress: progress,
            onMissions: () {},
            onTown: () {},
            onResident: talkedTo.add,
          ),
        ),
      ),
    );
    // Periodic stepping should not cause pumpAndSettle to time out.
    await tester.pumpAndSettle();

    final shiba = find.byKey(const ValueKey('home-resident-sprite-001_shiba'));
    final rabbit = find.byKey(const ValueKey('home-resident-sprite-002_usagi'));
    String asset(Finder finder) =>
        (tester.widget<Image>(finder).image as AssetImage).assetName;

    expect(asset(shiba), TownResident.shiba.walkAsset(WalkDirection.front, 0));
    expect(asset(rabbit), TownResident.rabbit.walkAsset(WalkDirection.front, 2));
    final shibaPosition = tester.getTopLeft(shiba);
    final rabbitPosition = tester.getTopLeft(rabbit);

    await tester.pump(const Duration(milliseconds: 180));
    expect(asset(shiba), TownResident.shiba.walkAsset(WalkDirection.front, 1));
    expect(asset(rabbit), TownResident.rabbit.walkAsset(WalkDirection.front, 3));
    expect(tester.getTopLeft(shiba), shibaPosition);
    expect(tester.getTopLeft(rabbit), rabbitPosition);

    await tester.pump(const Duration(milliseconds: 170));
    expect(asset(shiba), TownResident.shiba.walkAsset(WalkDirection.front, 2));
    expect(asset(rabbit), TownResident.rabbit.walkAsset(WalkDirection.front, 0));
    expect(tester.getTopLeft(shiba), shibaPosition);
    expect(tester.getTopLeft(rabbit), rabbitPosition);

    await tester.tap(shiba);
    expect(talkedTo, [TownResident.shiba]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('home residents remain still with reduced motion', (tester) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: GameHome(
                progress: Progress.empty(DateTime(2026, 10, 12)),
                onMissions: () {},
                onTown: () {},
                onResident: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    final shiba = find.byKey(const ValueKey('home-resident-sprite-001_shiba'));
    final rabbit = find.byKey(const ValueKey('home-resident-sprite-002_usagi'));
    String asset(Finder finder) =>
        (tester.widget<Image>(finder).image as AssetImage).assetName;
    expect(asset(shiba), TownResident.shiba.idleAsset);
    expect(asset(rabbit), TownResident.rabbit.idleAsset);
    final position = tester.getTopLeft(shiba);
    await tester.pump(const Duration(seconds: 3));
    expect(asset(shiba), TownResident.shiba.idleAsset);
    expect(asset(rabbit), TownResident.rabbit.idleAsset);
    expect(tester.getTopLeft(shiba), position);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
