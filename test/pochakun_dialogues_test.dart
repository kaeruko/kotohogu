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
    expect(lines, hasLength(12));
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
}
