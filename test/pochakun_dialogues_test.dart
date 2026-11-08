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
    expect(lines, hasLength(23));
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

  test('Tanuki-face search is a gated two-part conversation', () async {
    final catalog = await DialogueCatalog.load();
    final now = DateTime.utc(2026, 11, 9);
    final before = Progress.empty(now);
    final opened = Progress(
      day: '2026-11-09', lastCompletedDay: null,
      points: 390, completed: {},
    );
    const tanuki = TownResident.c054_tanuki;
    const yagi = TownResident.c020_yagi;
    const first = '054_tanuki_018';
    const second = '020_yagi_007';
    final both = {tanuki.id, yagi.id};

    final firstLine = catalog.entries.singleWhere((line) => line.id == first);
    expect(firstLine.once, isTrue);
    expect(firstLine.text, contains('たぬき男子'));
    expect(firstLine.reply?.text, contains('たぬき顔男子'));
    expect(firstLine.closing, contains('そっちはある'));

    expect(() => catalog.selectById(
      id: first, resident: tanuki, progress: before, now: now,
      townResidentIds: both, site: 'town',
    ), throwsStateError);
    expect(() => catalog.selectById(
      id: first, resident: tanuki, progress: opened, now: now,
      townResidentIds: {tanuki.id}, site: 'town',
    ), throwsStateError);

    expect(catalog.selectById(
      id: first, resident: tanuki, progress: opened, now: now,
      townResidentIds: both, site: 'town',
    ).id, first);
    expect(() => catalog.selectById(
      id: second, resident: yagi, progress: opened, now: now,
      townResidentIds: both, site: 'town',
    ), throwsStateError, reason: 'The continuation must not precede the search');

    final afterFirst = opened.markDialogueSeen(first);
    final lastLine = catalog.selectById(
      id: second, resident: yagi, progress: afterFirst, now: now,
      townResidentIds: both, site: 'town',
    );
    expect(lastLine.once, isTrue);
    expect(lastLine.text, 'よかったじゃない');
    expect(lastLine.reply?.residentId, tanuki.id);
    expect(lastLine.reply?.text, contains('人間ばっかり'));
    expect(lastLine.closing, 'そりゃそうだよ！');

    expect(() => catalog.selectById(
      id: first, resident: tanuki, progress: afterFirst, now: now,
      townResidentIds: both, site: 'town',
    ), throwsStateError);
    expect(() => catalog.selectById(
      id: second, resident: yagi,
      progress: afterFirst.markDialogueSeen(second), now: now,
      townResidentIds: both, site: 'town',
    ), throwsStateError);
  });

  test('Pochakun and Pasokon-kun exchange four makeover jokes in the library', () async {
    final catalog = await DialogueCatalog.load();
    final now = DateTime.utc(2026, 11, 9);
    final before = Progress.empty(now);
    final opened = Progress(
      day: '2026-11-09', lastCompletedDay: null,
      points: 390, completed: {},
    );
    const tanuki = TownResident.c054_tanuki;
    const yagi = TownResident.c020_yagi;
    final pairs = [
      ('054_tanuki_019', tanuki, yagi),
      ('054_tanuki_020', tanuki, yagi),
      ('054_tanuki_021', tanuki, yagi),
      ('020_yagi_008', yagi, tanuki),
    ];
    for (final (id, speaker, companion) in pairs) {
      final line = catalog.entries.singleWhere((entry) => entry.id == id);
      expect(line.once, isFalse);
      expect(line.reply?.residentId, companion.id);
      expect(line.closing, isNotEmpty);
      expect(line.conditions.any((condition) =>
          condition.fields['type'] == 'kotohogi' &&
          condition.fields['min'] == 390), isTrue);
      expect(line.conditions.any((condition) =>
          condition.fields['type'] == 'townTogether' &&
          condition.fields['otherResidentId'] == companion.id), isTrue);

      expect(() => catalog.selectById(
        id: id, resident: speaker, progress: before, now: now,
        site: 'town', townResidentIds: {speaker.id, companion.id},
      ), throwsStateError, reason: 'Not unlocked: $id');

      expect(() => catalog.selectById(
        id: id, resident: speaker, progress: opened, now: now,
        site: 'town', townResidentIds: {speaker.id},
      ), throwsStateError, reason: 'Companion missing: $id');

      expect(catalog.selectById(
        id: id, resident: speaker, progress: opened, now: now,
        site: 'town', townResidentIds: {speaker.id, companion.id},
      ).id, id);
    }
    expect(catalog.entries.singleWhere((e) => e.id == '054_tanuki_019').reply!.text, contains('おでこ'));
    expect(catalog.entries.singleWhere((e) => e.id == '054_tanuki_020').closing, contains('ぜんぶ黒い'));
    expect(catalog.entries.singleWhere((e) => e.id == '054_tanuki_021').closing, contains('かっこいい'));
  });

  test('monthly tanuki wildness dialogue follows the reading order', () async {
    final catalog = await DialogueCatalog.load();
    final now = DateTime.utc(2026, 11, 9);
    final beforeUnlock = Progress.empty(now);
    var opened = Progress(
      day: '2026-11-09', lastCompletedDay: null,
      points: 390, completed: {},
    );
    const tanuki = TownResident.c054_tanuki;
    const yagi = TownResident.c020_yagi;
    final both = {tanuki.id, yagi.id};
    final chapters = [
      ('054_tanuki_022', tanuki, yagi),
      ('020_yagi_009', yagi, tanuki),
      ('054_tanuki_023', tanuki, yagi),
    ];
    for (final (id, speaker, companion) in chapters) {
      final line = catalog.entries.singleWhere((item) => item.id == id);
      expect(line.once, isTrue);
      expect(line.reply?.residentId, companion.id);
      expect(line.closing, isNotEmpty);
      expect(line.conditions.any((c) =>
        c.fields['type'] == 'kotohogi' && c.fields['min'] == 390), isTrue);
      expect(line.conditions.any((c) =>
        c.fields['type'] == 'townTogether' &&
        c.fields['otherResidentId'] == companion.id), isTrue);
      expect(() => catalog.selectById(
        id: id, resident: speaker, progress: beforeUnlock, now: now,
        site: 'town', townResidentIds: both,
      ), throwsStateError, reason: 'Library must be unlocked: $id');
      expect(() => catalog.selectById(
        id: id, resident: speaker, progress: opened, now: now,
        site: 'town', townResidentIds: {speaker.id},
      ), throwsStateError, reason: 'Both characters required: $id');
      expect(catalog.selectById(
        id: id, resident: speaker, progress: opened, now: now,
        site: 'town', townResidentIds: both,
      ).id, id);
      opened = opened.markDialogueSeen(id);
      expect(() => catalog.selectById(
        id: id, resident: speaker, progress: opened, now: now,
        site: 'town', townResidentIds: both,
      ), throwsStateError, reason: 'Only once: $id');
    }

    expect(catalog.entries.singleWhere(
      (line) => line.id == '054_tanuki_022').text, contains('ワイルド'));
    expect(catalog.entries.singleWhere(
      (line) => line.id == '054_tanuki_023').text, contains('Wi-Fi'));
    expect(catalog.entries.singleWhere(
      (line) => line.id == '054_tanuki_023').closing, 'じゃあ無理だよぉ！！');

    for (final id in ['020_yagi_009', '054_tanuki_023']) {
      expect(() => catalog.selectById(
        id: id,
        resident: id.startsWith('020') ? yagi : tanuki,
        progress: Progress(
          day: '2026-11-09', lastCompletedDay: null,
          points: 390, completed: {},
        ),
        now: now, site: 'town', townResidentIds: both,
      ), throwsStateError, reason: 'No jumping ahead to $id');
    }
  });
}
