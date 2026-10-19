import 'package:flutter_test/flutter_test.dart';
import 'package:future_lift/progress.dart';
import 'package:future_lift/resident_collection.dart';
import 'package:future_lift/town_areas.dart';
import 'package:future_lift/town_rules.dart';
import 'package:future_lift/marche.dart';

import 'support/town_random.dart';

Progress fixture({bool tonkoOwned = true, int points = 300}) => Progress(
  day: '2026-10-17',
  lastCompletedDay: points == 0 ? null : '2026-10-16',
  points: points,
  residents: ResidentCollection(
    baselinePoints: 0,
    counts: {
      '001_shiba': 1,
      '002_usagi': 1,
      if (tonkoOwned) '041_pig_middle': 1,
    },
  ),
  completed: {},
);

void main() {
  test('one progress snapshot drives facility state and outdoor placement', () {
    var progress = fixture();
    final visit = TownVisit(random: ScriptedTownRandom([0, 1, 3]));
    var rules = TownRules(progress, visit: visit);
    expect(rules.marcheOpen, isFalse);
    expect(rules.salonUnlocked, isFalse);
    expect(rules.outdoors(TownArea.village),
        [TownResident.c041_pig_middle]);
    expect(rules.conversationPeers(
      ConversationSite.town, area: TownArea.village),
      {'041_pig_middle'});

    progress = progress.markDialogueSeen(tonkoMarcheOpeningDialogueId);
    rules = TownRules(progress, visit: visit);
    expect(rules.marcheOpen, isTrue);
    expect(rules.outdoors(TownArea.village), isEmpty);
    expect(rules.outdoors(TownArea.plaza),
        [TownResident.shiba, TownResident.c041_pig_middle]);
    expect(rules.conversationPeers(
      ConversationSite.town, area: TownArea.plaza),
      {'001_shiba', '041_pig_middle'});
    expect(rules.conversationPeers(
      ConversationSite.town, area: TownArea.village), isEmpty);
    expect(rules.conversationPeers(ConversationSite.roster),
        {'001_shiba', '002_usagi', '041_pig_middle'});
    expect(rules.conversationPeers(ConversationSite.salon), isEmpty);
    expect(() => rules.conversationPeers(ConversationSite.town),
        throwsArgumentError);
    expect(() => rules.conversationPeers(
      ConversationSite.roster, area: TownArea.plaza),
      throwsArgumentError);
    expect(() => rules.conversationPeers(
      ConversationSite.town, area: TownArea.plaza,
      previewSalonUnowned: true), throwsArgumentError);
  });

  test('debug cast never changes permanent market unlocks or placement', () {
    final saved = fixture(tonkoOwned: false)
        .markDialogueSeen(tonkoMarcheOpeningDialogueId);
    final rules = TownRules(saved,
        visit: TownVisit(random: ScriptedTownRandom([])),
        debugTownResidents: [TownResident.c041_pig_middle]);
    expect(rules.marcheOpen, isFalse);
    expect(rules.outdoors(TownArea.plaza), isEmpty);
    expect(rules.outdoors(TownArea.village),
        [TownResident.c041_pig_middle]);
  });

  test('salon ownership is distinct from outdoor and dialogue conditions', () {
    final base = fixture();
    final withSalon = Progress(
      day: base.day,
      lastCompletedDay: base.lastCompletedDay,
      points: base.points,
      residents: ResidentCollection(
        baselinePoints: 0,
        counts: {
          '001_shiba': 1,
          '002_usagi': 1,
          '035_beaty': 1,
        },
      ),
      completed: {},
    );
    final rules = TownRules(withSalon,
        visit: TownVisit(random: ScriptedTownRandom([0, 0])));
    expect(rules.salonUnlocked, isTrue);
    expect(rules.conversationPeers(ConversationSite.salon),
        {'035_beaty'});
    for (final area in TownArea.values) {
      expect(rules.outdoors(area), isNot(contains(TownResident.c035_beaty)));
    }
  });
}
