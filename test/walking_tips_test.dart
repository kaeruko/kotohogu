import 'package:flutter_test/flutter_test.dart';
import 'package:future_lift/dialogue_engine.dart';
import 'package:future_lift/progress.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('walking tips are bundled as editable resident dialogues', () async {
    final live = await DialogueCatalog.load();
    const ids = <String>[
      '001_shiba_002',
      '001_shiba_003',
      '026_farmer_004',
      '026_farmer_005',
      '027_daydreamer_004',
      '027_daydreamer_005',
      '027_daydreamer_006',
      '029_office_worker_013',
      '029_office_worker_014',
      '029_office_worker_015',
      '041_pig_middle_047',
      '041_pig_middle_048',
    ];
    expect(ids.length, 12);
    for (final id in ids) {
      final matches = live.entries.where((entry) => entry.id == id).toList();
      expect(matches, hasLength(1), reason: id);
      final line = matches.single;
      expect(line.once, isFalse, reason: id);
      expect(line.priority, greaterThanOrEqualTo(0), reason: id);
      expect(line.text, isNot(contains('予防できる')), reason: id);
      expect(line.text, isNot(contains('認知症を予防')), reason: id);
    }
  });

  test('same-day praise does not assume a mission happened in the past', () async {
    final live = await DialogueCatalog.load();
    final before = Progress.empty(DateTime(2026, 10, 20));
    final afterOutside = before.complete(Mission.outside);
    final afterBreak = before.complete(Mission.sittingBreak);
    final today = DateTime.utc(2026, 10, 20, 2); // JST 2026-10-20
    final tomorrow = DateTime.utc(2026, 10, 20, 15); // JST 2026-10-21

    for (final id in <String>[
      '001_shiba_003',
      '027_daydreamer_006',
      '041_pig_middle_048',
    ]) {
      final entry = live.entries.singleWhere((e) => e.id == id);
      expect(entry.matches(before, today, {}), isFalse, reason: id);
      expect(entry.matches(afterOutside, today, {}), isTrue, reason: id);
      expect(entry.matches(afterOutside, tomorrow, {}), isFalse, reason: id);
    }

    final sittingBreak = live.entries.singleWhere(
      (e) => e.id == '029_office_worker_015',
    );
    expect(sittingBreak.matches(before, today, {}), isFalse);
    expect(sittingBreak.matches(afterBreak, today, {}), isTrue);
    expect(sittingBreak.matches(afterBreak, tomorrow, {}), isFalse);
    expect(sittingBreak.matches(afterOutside, today, {}), isFalse);
  });

  test('research step thresholds preserve disease topics without naming Nakanojo', () async {
    final live = await DialogueCatalog.load();
    const expected = <String, List<String>>{
      '004_neko_030': ['2,000歩', '0分', '寝たきり'],
      '029_office_worker_016': ['4,000歩', '5分', 'うつ病'],
      '007_hitsuji_011': ['5,000歩', '7分半', '認知症'],
      '004_neko_031': ['7,000歩', '15分', '骨粗しょう症'],
      '004_neko_032': ['8,000歩', '20分', '糖尿病'],
      '026_farmer_006': ['10,000歩', '30分', 'メタボリックシンドローム'],
      '026_farmer_007': ['12,000歩', '40分', '肥満'],
    };
    expect(expected.length, 7);
    for (final item in expected.entries) {
      final line = live.entries.singleWhere((e) => e.id == item.key);
      for (final expectedPhrase in item.value) {
        expect(line.text, contains(expectedPhrase), reason: item.key);
      }
      expect(line.text, contains('研究によれば'), reason: item.key);
      expect(line.text, isNot(contains('中之条')), reason: item.key);
      expect(line.once, isFalse, reason: item.key);
      expect(line.conditions, isEmpty, reason: item.key);
    }
    for (final id in <String>[
      '041_pig_middle_049',
      '027_daydreamer_007',
      '004_neko_033',
    ]) {
      final line = live.entries.singleWhere((e) => e.id == id);
      if (id != '027_daydreamer_007') {
        expect(line.text, contains('研究によれば'), reason: id);
      }
      expect(line.text, isNot(contains('中之条')), reason: id);
      expect(line.once, isFalse, reason: id);
      expect(line.conditions, isEmpty, reason: id);
    }
  });
}
