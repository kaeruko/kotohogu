import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:future_lift/oyasumi_club.dart';
import 'package:future_lift/oyasumi_config.g.dart';
import 'package:future_lift/oyasumi_remote_config.dart';

void main() {
  Map<String, dynamic> copyConfig() =>
      jsonDecode(jsonEncode(oyasumiConfig)) as Map<String, dynamic>;

  test('published club document preserves known stages and all three speakers', () {
    final parsed = parseHostedOyasumi(jsonEncode(copyConfig()));
    expect((parsed['followupChapters'] as List).length, 2);
    final scene = OyasumiScene(
      config: parsed,
      saved: const OyasumiProgress(
        completed: 4,
        lastNight: '2026-10-23',
        lastKotohogi: 160,
        resignationAtKotohogi: 190,
        settlingAtKotohogi: 220,
      ),
      owned: {
        OyasumiScene.host, OyasumiScene.frog, OyasumiScene.koala,
      },
      now: DateTime(2026, 10, 25, 19),
      earnedKotohogi: 250,
      parkCleanerStarted: true,
    );
    expect(scene.stage, 'koala');
    expect(scene.cast, [
      OyasumiScene.host, OyasumiScene.frog, OyasumiScene.koala,
    ]);
    expect(scene.introduction(OyasumiScene.frog, 'koala'), isTrue);
  });

  test('AWS can append another chapter without changing Dart stage logic', () {
    final doc = copyConfig();
    final chapters = doc['followupChapters'] as List<dynamic>;
    chapters.add({
      'stage': 'after_koala',
      'requiredSeenDialogues': <String>[],
      'requiredOwned': <String>[],
      'kotohogiAfterPrevious': 30,
    });
    final stages = doc['stages'] as Map<String, dynamic>;
    final newStage = jsonDecode(jsonEncode(stages['settling'])) as Map<String, dynamic>;
    newStage['label'] = 'もうひとつの夜';
    newStage['intro'] = {
      'speaker': '029_office_worker',
      'text': 'またお話したいことがあるんだ。',
    };
    stages['after_koala'] = newStage;
    final parsed = parseHostedOyasumi(jsonEncode(doc));
    const saved = OyasumiProgress(
      completed: 5, lastNight: '2026-10-23',
      lastKotohogi: 160, resignationAtKotohogi: 190,
      settlingAtKotohogi: 220,
      chapterKotohogi: {'settling': 220, 'koala': 250},
    );
    OyasumiScene build(int points) => OyasumiScene(
      config: parsed, saved: saved,
      owned: {OyasumiScene.host, OyasumiScene.frog, OyasumiScene.koala},
      now: DateTime(2026, 10, 25, 19),
      earnedKotohogi: points,
      parkCleanerStarted: true,
    );
    expect(build(270).stage, 'koala');
    final next = build(280);
    expect(next.stage, 'after_koala');
    expect(next.cast, [OyasumiScene.host, OyasumiScene.frog]);
    expect(next.introduction(OyasumiScene.frog, 'after_koala'), isTrue);
    final updated = next.completeIntroduction(OyasumiScene.frog, 'after_koala');
    expect(updated.completed, 6);
    expect(updated.chapterKotohogi['after_koala'], 280);
    expect(OyasumiProgress.fromJson(updated.toJson()).chapterKotohogi['after_koala'], 280);
  });

  test('unknown resident or invalid cloud chapter stops instead of falling back', () {
    final doc = copyConfig();
    final stages = doc['stages'] as Map<String, dynamic>;
    final koala = stages['koala'] as Map<String, dynamic>;
    final positions = koala['positions'] as Map<String, dynamic>;
    positions['not_registered'] = [0.5, 0.6];
    expect(() => parseHostedOyasumi(jsonEncode(doc)),
        throwsFormatException);
    final missing = copyConfig()..remove('followupChapters');
    expect(() => parseHostedOyasumi(jsonEncode(missing)),
        throwsFormatException);
    final corrupt = copyConfig();
    (corrupt['followupChapters'] as List)[1]['kotohogiAfterPrevious'] = 15;
    expect(() => parseHostedOyasumi(jsonEncode(corrupt)),
        throwsFormatException);
  });

  test('old saved Koala completion receives a deterministic migration point', () {
    const old = OyasumiProgress(
      completed: 5, lastNight: '2026-10-23',
      lastKotohogi: 160, resignationAtKotohogi: 190,
      settlingAtKotohogi: 220,
    );
    final migrated = old.migrateLegacy(450);
    expect(migrated.chapterKotohogi['koala'], 450);
    expect(migrated.settlingAtKotohogi, 220);
    expect(migrated.migrateLegacy(999).chapterKotohogi['koala'], 450);
  });
}
