import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:future_lift/resident_collection.dart';
import 'package:future_lift/town_areas.dart';
import 'package:future_lift/town_area_navigator.dart';
import 'package:future_lift/town.dart';
import 'support/town_random.dart';

void main() {
  test('hospital requires the teacher regardless of points', () {
    expect(TownArea.hospital.isUnlocked(100000), isFalse);
    expect(TownArea.hospital.isUnlocked(0, owned: [TownResident.cat]), isTrue);
    expect(unlockedTownAreas(0, owned: [TownResident.cat]),
        [TownArea.plaza, TownArea.hospital]);
    expect(areaResidents([TownResident.cat], TownArea.hospital,
        lifetimePoints: 0, visit: TownVisit()), [TownResident.cat]);
    expect(areaResidents([], TownArea.hospital,
        lifetimePoints: 300, visit: TownVisit()), isEmpty);
  });


  test('doctor opens the clinic; the nurse joins only when owned', () {
    const doctor = TownResident.cat;
    const nurse = TownResident.c024_nurse;
    expect(TownArea.hospital.isUnlocked(300, owned: [nurse]), isFalse);
    expect(TownArea.hospital.isUnlocked(0, owned: [doctor]), isTrue);

    final beforeOpening = TownVisit(
        random: ScriptedTownRandom([0]));
    expect(areaResidents([nurse], TownArea.hospital,
        lifetimePoints: 0, visit: beforeOpening), isEmpty);
    expect(areaResidents([nurse], TownArea.plaza,
        lifetimePoints: 0, visit: beforeOpening), [nurse]);

    final open = TownVisit(random: ScriptedTownRandom([]));
    expect(areaResidents([doctor], TownArea.hospital,
        lifetimePoints: 0, visit: open), [doctor]);
    expect(areaResidents([doctor, nurse], TownArea.hospital,
        lifetimePoints: 0, visit: open), [doctor, nurse]);
    for (final area in [TownArea.plaza, TownArea.park,
        TownArea.shopping, TownArea.village]) {
      expect(areaResidents([doctor, nurse], area,
          lifetimePoints: 300, visit: open), isEmpty);
    }
  });

  testWidgets('clinic staff stand in separate rooms and can be tapped',
      (tester) async {
    tester.view.physicalSize = const Size(430, 930);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tapped = <TownResident>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: TownScene(
          area: TownArea.hospital,
          residents: const [TownResident.cat, TownResident.c024_nurse],
          lifetimePoints: 0,
          visit: TownVisit(random: ScriptedTownRandom([])),
          fillViewport: true,
          onResident: (resident) async => tapped.add(resident),
        ),
      ),
    )));
    final doctor = find.byKey(const ValueKey('resident-0'));
    final nurse = find.byKey(const ValueKey('resident-1'));
    expect(doctor, findsOneWidget);
    expect(nurse, findsOneWidget);
    expect(tester.getRect(doctor).center.dx,
        lessThan(tester.getRect(nurse).center.dx));
    expect(tester.getRect(doctor).bottom,
        lessThan(tester.view.physicalSize.height / 2));
    expect(tester.getRect(nurse).bottom,
        lessThan(tester.view.physicalSize.height / 2));

    await tester.tap(doctor);
    await tester.pump();
    await tester.tap(nurse);
    await tester.pump();
    expect(tapped, [TownResident.cat, TownResident.c024_nurse]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('newly acquired teacher opens hospital across locked areas', (tester) async {
    tester.view.physicalSize = const Size(430, 930);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var area = TownArea.plaza;
    var owned = <TownResident>[];
    late StateSetter change;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: StatefulBuilder(builder: (context, setState) {
        change = setState;
        return TownAreaNavigator(area: area,
          onAreaChanged: (next) => setState(() => area = next),
          lifetimePoints: 0, residents: owned);
      }),
    )));
    expect(find.byKey(const ValueKey('town-area-next')), findsNothing);
    change(() => owned = [TownResident.cat]);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('town-area-next')));
    await tester.pump();
    expect(area, TownArea.hospital);
    expect(find.text('2 / 2'), findsOneWidget);
    final background = tester.widget<Image>(find.byKey(const ValueKey('town-background')));
    expect((background.image as AssetImage).assetName,
        'assets/kotohogu/hospital_background_001.png');
    await tester.tap(find.byKey(const ValueKey('town-area-previous')));
    await tester.pump();
    expect(area, TownArea.plaza);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
