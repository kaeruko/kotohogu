import 'package:flutter_test/flutter_test.dart';
import 'package:future_lift/dialogue_engine.dart';
import 'package:future_lift/progress.dart';
import 'package:future_lift/resident_collection.dart';
import 'package:future_lift/town_areas.dart';
import 'package:future_lift/town_rules.dart';

import 'support/town_random.dart';

void main() {
  test('every walker draws once from unlocked areas with no duplicates', () {
    final owned = TownResident.values;
    final walkers = visibleTownResidents(owned);
    for (final points in [0, 89, 90, 179, 180, 299, 300]) {
      final unlocked = unlockedTownAreas(points);
      final random = ScriptedTownRandom([
        for (var i = 0; i < walkers.length; i++) i % unlocked.length,
      ]);
      final visit = TownVisit(random: random);
      final placements = {
        for (final area in TownArea.values)
          area: areaResidents(owned, area,
              lifetimePoints: points, visit: visit),
      };
      final appeared = placements.values.expand((r) => r).toList();
      expect(appeared.toSet(), walkers.toSet());
      expect(appeared.length, walkers.length);
      expect(random.calls, walkers.length);
      for (final area in TownArea.values) {
        if (!unlocked.contains(area)) expect(placements[area], isEmpty);
        expect(areaResidents(owned, area,
            lifetimePoints: points, visit: visit), placements[area]);
      }
      expect(random.calls, walkers.length, reason: 'No redraw during a visit');
    }
  });

  test('miner and daydreamer can meet after park unlock, using the painted visit', () {
    const miner = TownResident.c032_miner;
    const daydreamer = TownResident.c027_daydreamer;
    final random = ScriptedTownRandom([1, 1]);
    final visit = TownVisit(random: random);
    final progress = Progress(
      day: '2026-10-18', lastCompletedDay: '2026-10-18',
      points: 90, completed: {},
      residents: ResidentCollection(baselinePoints: 0, counts: {
        '01_shiba': 1, '02_rabbit': 1,
        miner.id: 1, daydreamer.id: 1,
      }),
    );
    // Assign these two before the other residents to control their outing.
    expect(residentCurrentArea(miner, 90, visit: visit), TownArea.park);
    expect(residentCurrentArea(daydreamer, 90, visit: visit), TownArea.park);
    final extended = TownVisit(random: ScriptedTownRandom([0, 0, 1, 1]));
    final rules = TownRules(progress, visit: extended);
    expect(rules.outdoors(TownArea.park), [miner, daydreamer]);
    final line = DialogueEntry.parse({
      'id': 'miner_outing_pair', 'residentId': miner.id,
      'text': 'また一緒におしゃべりできたね。',
      'priority': 10, 'once': false, 'logic': 'all',
      'conditions': [{'type': 'townTogether', 'otherResidentId': daydreamer.id}],
    });
    expect(line.matches(progress, DateTime.utc(2026, 10, 18),
        rules.conversationPeers(ConversationSite.town, area: TownArea.park)), isTrue);
    expect(line.matches(progress, DateTime.utc(2026, 10, 18),
        rules.conversationPeers(ConversationSite.town, area: TownArea.plaza)), isFalse);
    expect(random.calls, 2);
  });

  test('new residents and unlocks do not redraw existing destinations', () {
    final random = ScriptedTownRandom([0, 1]);
    final visit = TownVisit(random: random);
    expect(residentCurrentArea(TownResident.shiba, 0, visit: visit), TownArea.plaza);
    expect(residentCurrentArea(TownResident.shiba, 90, visit: visit), TownArea.plaza);
    expect(residentCurrentArea(TownResident.rabbit, 90, visit: visit), TownArea.park);
    expect(residentCurrentArea(TownResident.shiba, 300, visit: visit), TownArea.plaza);
    expect(random.calls, 2);
    final nextVisit = TownVisit(random: ScriptedTownRandom([1]));
    expect(residentCurrentArea(TownResident.shiba, 300, visit: nextVisit), TownArea.park);
  });

  test('salon residents and the working shopkeeper never draw outdoor locations', () {
    final random = ScriptedTownRandom([]);
    final visit = TownVisit(random: random);
    for (final resident in [TownResident.c035_beaty,
        TownResident.c031_kimono_fox, TownResident.c038_lion_lady]) {
      expect(residentCurrentArea(resident, 300, visit: visit), isNull);
    }
    expect(residentCurrentArea(TownResident.c041_pig_middle, 300,
        visit: visit, marcheOpen: true), TownArea.plaza);
    expect(random.calls, 0);
  });

  test('invalid placement input stops without inventing another destination', () {
    final random = ScriptedTownRandom([1]);
    final visit = TownVisit(random: random);
    expect(() => visit.destinationFor(residentId: 'new', walkInTown: true,
        homeAreaId: 'missing', lifetimePoints: 300), throwsFormatException);
    expect(() => residentCurrentArea(TownResident.shiba, -1, visit: visit),
        throwsRangeError);
    expect(random.calls, 0);
    expect(residentCurrentArea(TownResident.shiba, 90, visit: visit), TownArea.park);
    expect(() => residentCurrentArea(TownResident.shiba, 0, visit: visit),
        throwsStateError);
    expect(random.calls, 1);
  });
}
