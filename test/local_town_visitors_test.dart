import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:future_lift/local_content_preview.dart';
import 'package:future_lift/local_town_visitors.dart';
import 'package:future_lift/resident_collection.dart';
import 'package:future_lift/town_areas.dart';

import 'support/town_random.dart';

Map<String, Object?> character(String id, String area,
    {bool walk = true}) => {
  'key': 'c$id', 'id': id, 'label': id,
  'artFolder': id, 'nextDialogueNumber': 2,
  'inGacha': true, 'walkInTown': walk,
  'profile': '', 'homeAreaId': area,
};
Map<String, Object?> line(String speaker,
    {int priority = 0, bool once = false, List<Object> conditions = const []}) => {
  'id': '${speaker}_001', 'residentId': speaker, 'text': 'こんにちは！',
  'priority': priority, 'once': once, 'logic': 'all',
  'conditions': conditions,
};
RemoteContentCatalog catalog(List<Object> characters, List<Object> lines) =>
  RemoteContentCatalog.fromJson(jsonEncode({
    'version': 1, 'characters': characters, 'dialogues': lines,
  }));

void main() {
  test('normal play never shows unowned CMS visitors, even with live data', () {
    final content = catalog([
      character('01_shiba', 'plaza'),
      character('038_owl', 'park'),
      character('039_new', 'shopping'),
    ], [
      line('01_shiba'), line('038_owl'), line('039_new'),
    ]);
    final random = ScriptedTownRandom([0, 0]);
    final visit = TownVisit(random: random);

    // The default is deliberately disabled, including for never-before-seen
    // remote-only characters. No random positions should even be assigned.
    for (final points in [0, 90, 300]) {
      for (final area in TownArea.values) {
        final visitors = localVisitorsForArea(
          content, area,
          lifetimePoints: points, visit: visit,
          owned: const [TownResident.shiba, TownResident.rabbit],
        );
        expect(visitors, isEmpty, reason: 'Normal town: ${area.name}');
      }
    }
    expect(random.calls, 0);

    // An explicit preview remains possible for developer testing.
    final preview = localVisitorsForArea(
      content, TownArea.plaza, lifetimePoints: 0,
      visit: visit, owned: const [TownResident.shiba, TownResident.rabbit],
      debugRemotePreviewEnabled: true,
    );
    expect(preview.map((resident) => resident.id), ['039_new', '038_owl']);
    expect(random.calls, 2);
  });

  test('unknown CMS resident visits only unlocked areas without duplicates', () {
    final content = catalog([
      character('01_shiba', 'plaza'),
      character('037_tora', 'park'),
      character('038_owl', 'park'),
      character('039_cat', 'salon', walk: false),
    ], [
      line('01_shiba'), line('037_tora'), line('038_owl'), line('039_cat'),
    ]);
    final before = localVisitorsForArea(content, TownArea.plaza, debugRemotePreviewEnabled: true, lifetimePoints: 0, visit: TownVisit(),
      owned: const [TownResident.shiba, TownResident.rabbit],
    );
    expect(before.map((row) => row.id), ['038_owl', '037_tora']);
    expect(localVisitorsForArea(content, TownArea.park, debugRemotePreviewEnabled: true,
      lifetimePoints: 0, visit: TownVisit(),
      owned: const [TownResident.shiba]), isEmpty);
    final after = localVisitorsForArea(content, TownArea.park, debugRemotePreviewEnabled: true, lifetimePoints: 90,
      visit: TownVisit(random: ScriptedTownRandom([1, 1])),
      owned: const [TownResident.shiba, TownResident.rabbit],
    );
    expect(after.map((row) => row.id), ['038_owl', '037_tora']);
    expect(localVisitorsForArea(content, TownArea.plaza, debugRemotePreviewEnabled: true,
      lifetimePoints: 90,
      visit: TownVisit(random: ScriptedTownRandom([1, 1])),
      owned: const [TownResident.shiba]), isEmpty);
    expect(localVisitorsForArea(content, TownArea.park, debugRemotePreviewEnabled: true,
      lifetimePoints: 90, visit: TownVisit(), owned: const [],
      debugTownSelectionActive: true), isEmpty);
  });

  test('salon residents with walking enabled never visit outdoor areas', () {
    final content = catalog([
      character('038_lion_lady', 'salon', walk: true),
      character('039_new', 'salon', walk: false),
      character('040_new', 'plaza'),
    ], [
      line('038_lion_lady'), line('039_new'), line('040_new'),
    ]);
    for (final points in [0, 90, 300]) {
      for (final area in TownArea.values) {
        final visitors = localVisitorsForArea(content, area, debugRemotePreviewEnabled: true,
            lifetimePoints: points, visit: TownVisit(), owned: const []);
        expect(visitors.map((resident) => resident.id),
            isNot(contains('038_lion_lady')));
        expect(visitors.map((resident) => resident.id),
            isNot(contains('039_new')));
      }
    }
    expect(localVisitorsForArea(content, TownArea.plaza, debugRemotePreviewEnabled: true,
        lifetimePoints: 0, visit: TownVisit(), owned: const []).map((row) => row.id),
        ['040_new']);
  });

  test('every new remote-only resident appears without a fixed visitor cap', () {
    final chars = [
      for (var i = 40; i < 51; i++) character('${i}_new', 'plaza'),
    ];
    final lines = [
      for (var i = 40; i < 51; i++) line('${i}_new'),
    ];
    expect(localVisitorsForArea(catalog(chars, lines), TownArea.plaza, debugRemotePreviewEnabled: true,
      lifetimePoints: 0, visit: TownVisit(), owned: const []).length, 11);
  });

  test('remote visitors share one stable outing across area changes', () {
    final content = catalog([
      character('040_new', 'village'), character('041_new', 'shopping'),
    ], [line('040_new'), line('041_new')]);
    final random = ScriptedTownRandom([1, 1]);
    final visit = TownVisit(random: random);
    for (var pass = 0; pass < 3; pass++) {
      final all = [
        for (final area in TownArea.values)
          ...localVisitorsForArea(content, area, debugRemotePreviewEnabled: true, lifetimePoints: 90,
              visit: visit, owned: const []),
      ];
      expect(all.map((resident) => resident.id), ['040_new', '041_new']);
      expect(localVisitorsForArea(content, TownArea.park, debugRemotePreviewEnabled: true, lifetimePoints: 90,
          visit: visit, owned: const []).length, 2);
      expect(random.calls, 2);
    }
  });

  test('visitor greeting picks unconditional non-once highest priority', () {
    final basic = catalog(
      [character('038_owl', 'park')],
      [
        line('038_owl', priority: 1),
        {
          ...line('038_owl', priority: 90),
          'id': '038_owl_002',
          'conditions': [
            {'type': 'mission', 'missionId': 'outside', 'minCount': 3},
          ],
        },
        {...line('038_owl', priority: 80, once: true), 'id': '038_owl_003'},
        {...line('038_owl', priority: 10), 'id': '038_owl_004'},
      ],
    );
    expect(visitorGreeting(basic, '038_owl').id, '038_owl_004');
  });

  test('missing non-once unconditional dialogue is invalid', () {
    expect(() => catalog(
      [character('038_owl', 'plaza')],
      [line('038_owl', once: true)],
    ), throwsFormatException);
  });
}
