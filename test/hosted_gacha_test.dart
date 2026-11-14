import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:future_lift/local_content_preview.dart';
import 'package:future_lift/local_town_visitors.dart';
import 'package:future_lift/progress.dart';
import 'package:future_lift/resident_collection.dart';
import 'package:future_lift/town_areas.dart';

import 'progress_test.dart' show MemoryStore;
import 'resident_collection_test.dart' show FixedRandom, funded;
import 'support/town_random.dart';

RemoteContentCatalog testCatalog() => RemoteContentCatalog.fromJson(
  jsonEncode({
    'version': 1,
    'characters': [
      for (final data in [
        ('001_shiba', true),
        ('002_usagi', true),
        ('060_owl', true),
        ('061_retired', false),
      ])
        {
          'key': 'c${data.$1}', 'id': data.$1, 'label': data.$1,
          'artFolder': data.$1, 'profile': '',
          'homeAreaId': 'park', 'nextDialogueNumber': 2,
          'inGacha': data.$2, 'walkInTown': true,
        },
    ],
    'dialogues': [
      for (final id in ['001_shiba', '002_usagi', '060_owl', '061_retired'])
        {
          'id': '${id}_001', 'residentId': id, 'text': 'こんにちは',
          'priority': 0, 'once': false, 'logic': 'all',
          'conditions': [],
        },
    ],
  }),
);

void main() {
  test('CDN gacha draws a brand new ID, saves it and restores without enum', () async {
    final store = MemoryStore()..raw = funded(points: 60).encode();
    final random = FixedRandom(2);
    final controller = ProgressController(
      store, clock: () => DateTime(2026, 10, 11), random: random,
    );
    await controller.initialize();
    final catalog = testCatalog();
    expect(catalog.gachaPool.map((r) => r.id), ['001_shiba', '002_usagi', '060_owl']);
    final drawn = await controller.drawHostedResident(catalog);
    expect(drawn!.id, '060_owl');
    expect(store.writes, 1);
    expect(controller.progress!.residents.counts['060_owl'], 1);
    expect(controller.progress!.residents.remotelyOwnedIds, ['060_owl']);
    expect(controller.progress!.residents.owned,
        [TownResident.shiba, TownResident.rabbit]);
    expect(controller.progress!.residents.availableKotohogi(60), 30);
    final restored = Progress.decode(store.raw!);
    expect(restored.residents.counts['060_owl'], 1);
    catalog.validateSavedResidentIds(restored.residents.counts.keys);
    expect(restored.residents.remotelyOwnedIds, ['060_owl']);
  });

  test('retired but registered ID remains readable and never draws', () {
    final catalog = testCatalog();
    final saved = funded(points: 60).acquireResidentId('061_retired');
    final restored = Progress.decode(saved.encode());
    catalog.validateSavedResidentIds(restored.residents.counts.keys);
    expect(restored.residents.remotelyOwnedIds, ['061_retired']);
    expect(catalog.gachaPool.map((r) => r.id), isNot(contains('061_retired')));
    expect(() => catalog.validateSavedResidentIds(['062_removed']),
        throwsFormatException);
    expect(() => funded(points: 60).acquireResidentId('invalid id'),
        throwsFormatException);
  });

  test('owned server resident appears in town but unowned ones do not', () {
    final catalog = testCatalog();
    final visit = TownVisit(random: ScriptedTownRandom([0, 0]));
    final owned = localVisitorsForArea(
      catalog, TownArea.plaza, lifetimePoints: 0, visit: visit,
      owned: const [TownResident.shiba, TownResident.rabbit],
      ownedRemoteIds: const ['060_owl'],
    );
    expect(owned.map((x) => x.id), ['060_owl']);
    expect(localVisitorsForArea(
      catalog, TownArea.plaza, lifetimePoints: 0,
      visit: TownVisit(), owned: const [TownResident.shiba],
    ), isEmpty);
  });

  test('hosted draw retains original save failure without publishing result', () async {
    final error = StateError('disk full');
    final store = MemoryStore()
      ..raw = funded(points: 30).encode()
      ..saveError = error;
    final controller = ProgressController(
      store, clock: () => DateTime(2026, 10, 11),
      random: FixedRandom(2),
    );
    await controller.initialize();
    expect(await controller.drawHostedResident(testCatalog()), isNull);
    expect(controller.failure!.error, same(error));
    expect(controller.failure!.stackTrace.toString(), isNotEmpty);
    expect(controller.progress!.residents.counts.containsKey('060_owl'), false);
    expect(store.writes, 1);
  });
}
