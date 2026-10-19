import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:future_lift/resident_collection.dart';
import 'package:future_lift/town_areas.dart';
import 'package:future_lift/town_area_navigator.dart';

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
          level: 0, lifetimePoints: 0, residents: owned);
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
