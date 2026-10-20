import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:future_lift/dialogue_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Kaeru self-talk tips stay editable, repeatable and non-prescriptive', () async {
    final catalogue = await DialogueCatalog.load();
    const ids = <String>[
      '029_office_worker_017',
      '029_office_worker_018',
      '029_office_worker_019',
    ];
    const fragments = <String>[
      'ぼくにも自分の考えがあるんだ',
      '今のぼくのままでも、話していい',
      'しっくりこない日もあるんだ',
    ];
    expect(ids.length, fragments.length);
    for (var i = 0; i < ids.length; i++) {
      final entry = catalogue.entries.singleWhere((e) => e.id == ids[i]);
      expect(entry.residentId, '029_office_worker');
      expect(entry.text, contains(fragments[i]));
      expect(entry.once, isFalse, reason: ids[i]);
      expect(entry.firstGreeting, isFalse, reason: ids[i]);
      expect(entry.conditions, isEmpty, reason: ids[i]);
      expect(entry.priority, 10, reason: ids[i]);
    }

    final registry = jsonDecode(
      File('assets/characters/characters.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final character = (registry['characters'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .singleWhere((entry) => entry['id'] == '029_office_worker');
    expect(character['nextDialogueNumber'], 20);
  });
}
