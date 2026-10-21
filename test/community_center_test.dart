import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:future_lift/community_center_room.dart';
import 'package:future_lift/facility_layout.dart';
import 'package:future_lift/resident_collection.dart';
import 'package:future_lift/town_area_navigator.dart';
import 'package:future_lift/town_areas.dart';

void main() {
  test('community center opens at 240 earned points, not gacha ownership', () {
    expect(isCommunityCenterUnlocked(239), isFalse);
    expect(isCommunityCenterUnlocked(240), isTrue);
    expect(isCommunityCenterUnlocked(300), isTrue);
    expect(communityCenterResidents(),
        [TownResident.c031_kimono_fox, TownResident.c037_tora]);
    final flower = facilityPlacement('community_center', '031_kimono_fox');
    final exercise = facilityPlacement('community_center', '037_tora');
    expect(flower.x + flower.size, lessThan(exercise.x));
    expect(flower.y + flower.size, lessThan(1000));
    expect(exercise.y + exercise.size, lessThan(1000));
    expect(CommunityCenterRoom.backgroundAsset,
        'assets/kotohogu/community_center_background_001.png');
    expect(File(CommunityCenterRoom.backgroundAsset).existsSync(), isTrue);
  });

  testWidgets('shopping street only reveals community center when opened',
      (tester) async {
    tester.view.physicalSize = const Size(430, 930);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Widget app(int points) => MaterialApp(
      home: Scaffold(body: TownAreaNavigator(
        area: TownArea.shopping,
        onAreaChanged: (_) {},
        lifetimePoints: points,
        residents: const [],
      )),
    );
    const entry = ValueKey('shopping-community-center-entrance');
    await tester.pumpWidget(app(239));
    expect(find.byKey(entry), findsNothing);
    await tester.pumpWidget(app(240));
    expect(find.byKey(entry), findsOneWidget);
    await tester.tap(find.byKey(entry));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(CommunityCenterRoom), findsOneWidget);
    expect(find.byKey(const ValueKey('community-center-background')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('community-center-resident-031_kimono_fox')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('community-center-resident-037_tora')),
        findsOneWidget);
    await tester.tap(find.byKey(
        const ValueKey('community-center-return-shopping')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 650));
    await tester.pump();
    expect(find.byType(CommunityCenterRoom), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('both instructors can be spoken to regardless of ownership',
      (tester) async {
    tester.view.physicalSize = const Size(430, 930);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final spoken = <TownResident>[];
    await tester.pumpWidget(MaterialApp(
      home: CommunityCenterRoom(onResident: (resident) async {
        spoken.add(resident);
      }),
    ));
    final flower = find.byKey(
        const ValueKey('community-center-resident-031_kimono_fox'));
    final exercise = find.byKey(
        const ValueKey('community-center-resident-037_tora'));
    expect(flower, findsOneWidget);
    expect(exercise, findsOneWidget);
    expect(tester.getRect(flower).overlaps(tester.getRect(exercise)), isFalse);
    await tester.tap(flower);
    await tester.pump();
    await tester.tap(exercise);
    await tester.pump();
    expect(spoken, [TownResident.c031_kimono_fox, TownResident.c037_tora]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
