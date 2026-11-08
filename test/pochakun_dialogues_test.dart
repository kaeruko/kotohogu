import 'package:flutter_test/flutter_test.dart';
import 'package:future_lift/dialogue_engine.dart';
import 'package:future_lift/progress.dart';
import 'package:future_lift/resident_collection.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Pochakun has ten new lines with a library-themed set', () async {
    final catalog = await DialogueCatalog.load();
    final lines = {
      for (final entry in catalog.entries)
        if (entry.residentId == TownResident.c054_tanuki.id) entry.id: entry,
    };
    expect(lines, hasLength(17));
    for (var number = 3; number <= 12; number++) {
      final id = '054_tanuki_${number.toString().padLeft(3, '0')}';
      expect(lines, contains(id));
      expect(lines[id]!.once, isFalse);
      expect(lines[id]!.text, isNotEmpty);
    }
    expect(lines['054_tanuki_004']!.text, contains('47回'));
    expect(lines['054_tanuki_005']!.text, contains('自然体'));
    for (final number in [9, 10, 11]) {
      final id = '054_tanuki_${number.toString().padLeft(3, '0')}';
      final line = lines[id]!;
      expect(line.conditions, hasLength(1));
      expect(line.conditions.single.fields['type'], 'kotohogi');
      expect(line.conditions.single.fields['min'], 390);
    }
  });

  test('conversations need their actual companion in the same town', () async {
    final catalog = await DialogueCatalog.load();
    final progress = Progress.empty(DateTime(2026, 11, 9));
    final now = DateTime.utc(2026, 11, 9);
    const tanuki = TownResident.c054_tanuki;
    for (final pair in [
      ('054_tanuki_007', TownResident.c020_yagi),
      ('054_tanuki_008', TownResident.c020_yagi),
      ('054_tanuki_012', TownResident.c027_daydreamer),
    ]) {
      expect(() => catalog.selectById(
        id: pair.$1, resident: tanuki, progress: progress, now: now,
        site: 'town', townResidentIds: {tanuki.id},
      ), throwsStateError);
      final line = catalog.selectById(
        id: pair.$1, resident: tanuki, progress: progress, now: now,
        site: 'town', townResidentIds: {tanuki.id, pair.$2.id},
      );
      expect(line.reply?.residentId, pair.$2.id);
      expect(line.reply?.text, isNotEmpty);
      expect(line.closing, isNotEmpty);
    }
  });

  test('new library conversations require the other speaker and 390 points', () async {
    final catalog = await DialogueCatalog.load();
    final before = Progress.empty(DateTime(2026, 11, 9));
    final opened = Progress(
      day: '2026-11-09', lastCompletedDay: null,
      points: 390, completed: {},
    );
    final now = DateTime.utc(2026, 11, 9);
    const tanuki = TownResident.c054_tanuki;
    const yagi = TownResident.c020_yagi;
    final pairs = [
      for (var n = 13; n <= 17; n++)
        ('054_tanuki_${n.toString().padLeft(3, '0')}', tanuki, yagi),
      for (var n = 2; n <= 4; n++)
        ('020_yagi_${n.toString().padLeft(3, '0')}', yagi, tanuki),
    ];
    for (final (id, speaker, companion) in pairs) {
      final line = catalog.entries.singleWhere((entry) => entry.id == id);
      expect(line.reply?.residentId, companion.id);
      expect(line.closing, isNotEmpty);
      expect(line.conditions.any((c) =>
          c.fields['type'] == 'kotohogi' && c.fields['min'] == 390), isTrue);
      expect(line.conditions.any((c) =>
          c.fields['type'] == 'townTogether' &&
          c.fields['otherResidentId'] == companion.id), isTrue);
      expect(() => catalog.selectById(
          id: id, resident: speaker, progress: before, now: now,
          townResidentIds: {speaker.id, companion.id}, site: 'town',
        ), throwsStateError, reason: 'Before unlocking: $id');
      expect(() => catalog.selectById(
          id: id, resident: speaker, progress: opened, now: now,
          townResidentIds: {speaker.id}, site: 'town',
        ), throwsStateError, reason: 'Other speaker absent: $id');
      expect(catalog.selectById(
        id: id, resident: speaker, progress: opened, now: now,
        townResidentIds: {speaker.id, companion.id}, site: 'town',
      ).id, id);
    }
    for (final id in ['020_yagi_005', '020_yagi_006']) {
      final line = catalog.entries.singleWhere((e) => e.id == id);
      expect(line.reply, isNull);
      expect(line.conditions.single.fields['min'], 390);
      expect(catalog.selectById(
        id: id, resident: yagi, progress: opened, now: now,
        site: 'town', townResidentIds: {yagi.id},
      ).id, id);
    }
  });
}
