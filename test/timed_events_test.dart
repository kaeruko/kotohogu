import 'package:flutter_test/flutter_test.dart';
import 'package:future_lift/timed_events.dart';
import 'package:future_lift/resident_collection.dart';
import 'package:future_lift/town_areas.dart';

void main() {
  final gonsuke = TownResident.c042_senior_dog;
  test('morning park is Gonsuke only regardless of gacha ownership', () {
    final morning = TownTimedEvents(now: DateTime(2026, 10, 23, 6), owned: []);
    expect(morning.residents(TownArea.park, [TownResident.shiba]), [gonsuke]);
    expect(morning.residents(TownArea.plaza, [gonsuke, TownResident.shiba]),
        [TownResident.shiba]);
    expect(morning.route(TownArea.park, gonsuke)!.stay, true);
    expect(morning.takesOver(TownArea.park), true);
    final daytime = TownTimedEvents(now: DateTime(2026, 10, 23, 9), owned: []);
    expect(daytime.residents(TownArea.park, [TownResident.shiba]),
        [TownResident.shiba]);
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
  test('add, exclude, debug bypass, conflicting events', () {
    Map<String, dynamic> event(String id, String mode) => {
      'id': id, 'label': id, 'areaId': 'park',
      'schedule': {'start': '06:00', 'end': '09:00', 'weekdays': []},
      'mode': mode, 'requiresOwned': false,
      'residents': [
        {'residentId': gonsuke.id, 'x': .4, 'y': .6, 'stay': true}
      ],
    };
    TownTimedEvents fixture(String mode, {bool enabled = true}) =>
        TownTimedEvents(now: DateTime(2026, 10, 23, 7), owned: [],
            enabled: enabled, config: {'version': 1,
              'events': [event('first', mode)]});
    expect(fixture('add').residents(TownArea.park, [TownResident.shiba]),
        [TownResident.shiba, gonsuke]);
    expect(fixture('exclude').residents(TownArea.park,
        [TownResident.shiba, gonsuke]), [TownResident.shiba]);
    expect(fixture('replace', enabled: false).residents(
        TownArea.park, [TownResident.shiba]), [TownResident.shiba]);
    final conflict = TownTimedEvents(now: DateTime(2026, 10, 23, 7),
        owned: [], config: {'version': 1,
        'events': [event('one', 'replace'), event('two', 'add')]});
    expect(() => conflict.eventFor(TownArea.park), throwsStateError);
    expect(() => fixture('replace').residents(
        TownArea.park, [], scriptedEventActive: true), throwsStateError);
  });
}
