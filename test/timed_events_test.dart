import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:future_lift/town.dart';
import 'package:future_lift/timed_events.dart';
import 'package:future_lift/resident_collection.dart';
import 'package:future_lift/town_areas.dart';

void main() {
  final gonsuke = TownResident.c042_senior_dog;
  final shiba = TownResident.shiba;
  final pome = TownResident.c052_pome;

  test('morning exercises: Gonsuke hosts owned friends only', () {
    final unowned = TownTimedEvents(
        now: DateTime(2026, 10, 23, 6), owned: [shiba, pome]);
    expect(unowned.eventFor(TownArea.park), isNotNull);
    expect(unowned.takesOver(TownArea.park), true);
    expect(unowned.residents(TownArea.park, [shiba, pome]), isEmpty);
    expect(unowned.route(TownArea.park, shiba), isNull);
    expect(unowned.stepsInPlace(TownArea.park, shiba), false);

    for (final (owned, expected) in [
      ([gonsuke], [gonsuke]),
      ([gonsuke, shiba], [gonsuke, shiba]),
      ([gonsuke, pome], [gonsuke, pome]),
      ([gonsuke, shiba, pome], [gonsuke, shiba, pome]),
    ]) {
      final morning = TownTimedEvents(
          now: DateTime(2026, 10, 23, 7), owned: owned);
      expect(morning.residents(TownArea.park, [shiba, pome]), expected);
      expect(morning.residents(TownArea.plaza, owned), isEmpty);
      for (final resident in expected) {
        final route = morning.route(TownArea.park, resident)!;
        expect(route.stay, true);
        expect(morning.stepsInPlace(TownArea.park, resident), true);
      }
    }
    final all = TownTimedEvents(now: DateTime(2026, 10, 23, 8, 59),
        owned: [gonsuke, shiba, pome]);
    expect(all.route(TownArea.park, gonsuke)!.x, .48);
    expect(all.route(TownArea.park, shiba)!.x, .34);
    expect(all.route(TownArea.park, pome)!.x, .61);

    for (final date in [
      DateTime(2026, 10, 23, 5, 59),
      DateTime(2026, 10, 23, 9),
    ]) {
      final daytime = TownTimedEvents(now: date,
          owned: [gonsuke, shiba, pome]);
      expect(daytime.eventFor(TownArea.park), isNull);
      expect(daytime.residents(TownArea.park, [shiba]), [shiba]);
      expect(daytime.stepsInPlace(TownArea.park, shiba), false);
    }
  });

  testWidgets('morning participants step in place, reduced motion stays still',
      (tester) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final morning = TownTimedEvents(now: DateTime(2026, 10, 23, 7),
        owned: [gonsuke, shiba, pome]);

    Widget scene({bool reduced = false}) => MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: SizedBox(width: 360, child: TownScene(
            area: TownArea.park, lifetimePoints: 90,
            residents: [gonsuke, shiba, pome], timedEvents: morning,
          )),
        ),
      ),
    );
    await tester.pumpWidget(scene());
    final initial = <Rect>[];
    for (var i = 0; i < 3; i++) {
      final finder = find.byKey(ValueKey('resident-sprite-$i'));
      expect(finder, findsOneWidget);
      initial.add(tester.getRect(finder));
      final image = tester.widget<Image>(finder).image as AssetImage;
      expect(image.assetName, contains('/walk_front_'));
    }
    await tester.pump(const Duration(milliseconds: 450));
    for (var i = 0; i < 3; i++) {
      final finder = find.byKey(ValueKey('resident-sprite-$i'));
      expect(tester.getRect(finder), initial[i]);
      final image = tester.widget<Image>(finder).image as AssetImage;
      expect(image.assetName, contains('/walk_front_'));
    }

    await tester.pumpWidget(scene(reduced: true));
    for (var i = 0; i < 3; i++) {
      final image = tester.widget<Image>(
          find.byKey(ValueKey('resident-sprite-$i'))).image as AssetImage;
      expect(image.assetName, [gonsuke, shiba, pome][i].idleAsset);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  test('overnight start-day weekdays and boundaries', () {
    final w = EventTimeWindow(startMinute: 1080, endMinute: 300, weekdays: [5]);
    expect(w.includes(DateTime(2026, 10, 23, 18)), true);
    expect(w.includes(DateTime(2026, 10, 24, 4, 59)), true);
    expect(w.includes(DateTime(2026, 10, 24, 5)), false);
    expect(w.includes(DateTime(2026, 10, 24, 18)), false);
    expect(w.occurrenceDay(DateTime(2026, 10, 24, 4)).day, 23);
    expect(() => EventTimeWindow(startMinute: 0, endMinute: 0, weekdays: []),
        throwsFormatException);
  });
  test('rejects invalid host and stepping configuration', () {
    Map<String, dynamic> event() => {
      'id': 'test', 'label': 'test', 'areaId': 'park',
      'schedule': {'start': '06:00', 'end': '09:00', 'weekdays': []},
      'mode': 'replace', 'requiresOwned': false,
      'hostResidentId': gonsuke.id,
      'residents': [
        {'residentId': shiba.id, 'x': .4, 'y': .6, 'stay': true,
          'stepInPlace': true},
      ],
    };
    expect(() => TownTimedEvents(now: DateTime(2026, 10, 23, 7),
        owned: [shiba], config: {'version': 1, 'events': [event()]}),
        throwsFormatException);
    final bad = event();
    bad.remove('hostResidentId');
    (bad['residents'] as List).first['stay'] = false;
    expect(() => TownTimedEvents(now: DateTime(2026, 10, 23, 7),
        owned: [shiba], config: {'version': 1, 'events': [bad]}),
        throwsFormatException);
  });

  test('add, exclude, debug bypass, conflicting events', () {
    Map<String, dynamic> event(String id, String mode) => {
      'id': id, 'label': id, 'areaId': 'park',
      'schedule': {'start': '06:00', 'end': '09:00', 'weekdays': []},
      'mode': mode, 'requiresOwned': false,
      'residents': [
        {'residentId': gonsuke.id, 'x': .4, 'y': .6, 'stay': true}
      ],
    };
    TownTimedEvents fixture(String mode, {bool enabled = true,
        bool ownsGonsuke = true}) =>
        TownTimedEvents(now: DateTime(2026, 10, 23, 7),
            owned: [if (ownsGonsuke) gonsuke, TownResident.shiba],
            enabled: enabled, config: {'version': 1,
              'events': [event('first', mode)]});
    expect(fixture('add').residents(TownArea.park, [TownResident.shiba]),
        [TownResident.shiba, gonsuke]);
    expect(fixture('add', ownsGonsuke: false).residents(
        TownArea.park, [TownResident.shiba]), [TownResident.shiba]);
    expect(fixture('exclude').residents(TownArea.park,
        [TownResident.shiba, gonsuke]), [TownResident.shiba]);
    expect(fixture('replace', enabled: false).residents(
        TownArea.park, [TownResident.shiba]), [TownResident.shiba]);
    expect(fixture('replace', ownsGonsuke: false).residents(
        TownArea.park, [TownResident.shiba]), isEmpty);
    final conflict = TownTimedEvents(now: DateTime(2026, 10, 23, 7),
        owned: [], config: {'version': 1,
        'events': [event('one', 'replace'), event('two', 'add')]});
    expect(() => conflict.eventFor(TownArea.park), throwsStateError);
    expect(() => fixture('replace').residents(
        TownArea.park, [], scriptedEventActive: true), throwsStateError);
  });
}
