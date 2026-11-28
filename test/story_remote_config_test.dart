import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:future_lift/dialogue_engine.dart';
import 'package:future_lift/google_drive_content_source.dart';
import 'package:future_lift/local_content_preview.dart';
import 'package:future_lift/main.dart';
import 'package:future_lift/oyasumi_config.g.dart';
import 'package:future_lift/progress.dart';
import 'package:future_lift/story_data.dart';
import 'package:future_lift/story_duel_stage.dart';
import 'package:future_lift/story_progress.dart';
import 'package:future_lift/story_remote_config.dart';

import 'progress_test.dart' show MemoryStore;

Map<String, dynamic> _document(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

List<dynamic> _episodes(Map<String, dynamic> story) =>
    story['episodes'] as List;

class _LoopbackHttp extends HttpOverrides {}

void main() {
  final base = Uri.parse('https://content.example.test/releases/${'7' * 64}/');
  final registry = _document('assets/characters/characters.json');
  final residents = RemoteContentCatalog([
    for (final row in registry['characters'] as List)
      if (row['archived'] != true) RemoteResident.fromJson(row),
  ], const []);

  Map<String, dynamic> storyDocument() => _document('assets/story/story.json');
  StoryCatalog parse(Map<String, dynamic> story) =>
      parseHostedStory(jsonEncode(story), base, residents);

  test(
    'the hosted seventeen-episode story pins its cast and artwork',
    () {
      final json = storyDocument();
      final catalog = parse(json);
      expect(catalog.baseUri, base);
      expect(catalog.title, json['title']);
      expect(catalog.episodes.length, 17);
      expect(catalog.episodes.length, _episodes(json).length);
      expect(catalog.episodes.first.id, storyEpisodes.first.id);
      final first = catalog.episodes.first.dialogue.first.$1;
      final speaker = _episodes(json).first['dialogue'][0]['speaker'] as String;
      expect(
        first.portrait,
        remoteSpriteUri(
          base,
          residents.residentById(speaker),
          'idle_front_01.png',
        ),
      );
    },
  );

  test('the opening clue conversation matches the bundled story', () {
    final hosted = parse(storyDocument()).episodes.first.resultDialogue;
    final bundled = storyEpisodes.first.resultDialogue;
    const expected = [
      'とけたぽむ！\n「おおきな きのした」……おおきなおやつがあるぽむ！？',
      'すごいわん！\nふれあい公園の大きな木かもしれないわん！',
      'ぽむ、木の下を見にいきたいぽむ〜！',
      'いっしょに探しにいくわん！',
    ];
    expect(hosted.map((turn) => turn.$2), expected);
    expect(bundled.map((turn) => turn.$2), expected);
    final hostedIntro = parse(storyDocument()).episodes.first.dialogue;
    final bundledIntro = storyEpisodes.first.dialogue;
    expect(hostedIntro.map((turn) => turn.$2), bundledIntro.map((turn) => turn.$2));
    expect(hostedIntro.first.$2, contains('いち、に、ぽむ、ぽむ！'));
    expect(hostedIntro[1].$2, contains('たいそうのはんこカードわん？'));
    expect(hostedIntro[2].$2, contains('ぽむもはんこほしいぽむ〜！'));
  });

  test('each episode keeps its solved dialogue aligned with bundled data', () {
    final hostedEpisodes = parse(storyDocument()).episodes;
    expect(hostedEpisodes.length, 17);
    expect(storyEpisodes.length, 14);
    for (var index = 0; index < storyEpisodes.length; index++) {
      final hosted = hostedEpisodes[index].resultDialogue;
      final bundled = storyEpisodes[index].resultDialogue;
      expect(hosted.length, bundled.length, reason: 'episode $index');
      if (index < 3) {
        expect(hosted.first.$2, startsWith('とけたぽむ！\n'), reason: 'episode $index');
        expect(hosted[1].$2, startsWith('すごいわん！\n'), reason: 'episode $index');
      } else if (index == 3) {
        expect(hosted.first.$2, startsWith('勝ったでござる！'), reason: 'episode $index');
        expect(hosted.last.$2, 'うちに勝てはりますやろか？');
      } else if (index == 4) {
        expect(hosted.first.$1.label, 'モサエド');
        expect(hosted.last.$2, contains('あおんあおん！'));
      } else if (index <= 7) {
        expect(hosted.isNotEmpty, isTrue);
        expect(hosted.last.$1.label, isIn(['およめさん', 'パティシエ']));
      } else if (index <= 10) {
        expect(hosted.isNotEmpty, isTrue);
        expect(hosted.last.$1.label, 'おやすみくん');
      } else {
        expect(hosted.isNotEmpty, isTrue);
        expect(hosted.last.$1.label,
            index == 11 ? 'おしゃべりさん' : 'おしゃれさん');
      }
      expect(hosted.map((turn) => turn.$2), bundled.map((turn) => turn.$2));
      expect(hosted.map((turn) => turn.$1.label), bundled.map((turn) => turn.$1.label));
    }
  });

  test('stamp arc ends before the Mosædo story begins', () {
    final catalog = parse(storyDocument());
    expect(catalog.episodes.length, 17);
    expect(catalog.episodes.map((e) => e.unlockAt), [0, 90, 120, 150, 180, 210, 240, 270, 300, 330, 360, 390, 420, 450, 480, 510, 540]);
    expect(catalog.episodes.map((e) => e.title), [
      'たいそうのはんこカード？',
      '木の下になにがある？',
      'ひみつのごほうび',
      '数独道場破りでござる！',
      'おししょうの一局',
      '帳簿と数独',
      'ケーキ無料！？',
      'ふたりの休憩時間',
      'むかしのおしごと',
      'ひさしぶりの同僚',
      'まだまだこれから',
      'きれいになる待ち時間',
      'ふわふわ大事件！',
      'みんなおそろい！？',
      'ねるのネイルサロン',
      'まま、ねるかわいい？',
      'ママとおでかけ',
    ]);
    expect(catalog.episodes.first.clue, 'おおきな きのした');
    expect(catalog.episodes[1].clue, 'ほんとうにはんこカード！');
    expect(catalog.chapters.map((chapter) => chapter.title),
        ['しばぽめ', 'モサエド', 'およめさん', 'おやすみクラブ', 'おしゃれさんの美容室', 'ねるとママのおやくそく']);
    expect(catalog.chapters.map((chapter) => chapter.startIndex), [0, 3, 5, 8, 11, 14]);
    expect(catalog.chapters.take(storyChapters.length).map((chapter) => chapter.id),
        storyChapters.map((chapter) => chapter.id));
    final ending = catalog.episodes[2].resultDialogue;
    expect(ending.any((line) => line.$1.label == 'ごんすけ'), isTrue);
    expect(ending.any((line) => line.$2.contains('朝の体操第二')), isTrue);
    expect(ending.any((line) => line.$2.contains('おやつじゃないぽむ')), isTrue);
    final duel = catalog.episodes[3];
    expect(duel.area.id, 'plaza');
    expect(duel.dialogue.any((turn) => turn.$1.label == 'モサエド'), isTrue);
    expect(duel.resultDialogue.last.$1.label, 'おししょう');
    expect(duel.resultDialogue.last.$2, 'うちに勝てはりますやろか？');
    final oshisho = catalog.episodes[4];
    expect(oshisho.id, 'episode_04');
    expect(oshisho.dialogue.first.$1.label, 'おししょう');
    expect(oshisho.resultDialogue.any((line) => line.$2.contains('白い熊')), isTrue);
    final bakery = catalog.episodes.skip(5).take(3).toList();
    expect(bakery.length, 3);
    expect(bakery.map((e) => e.area.id), ['shopping', 'shopping', 'shopping']);
    expect(bakery[1].dialogue.any((turn) => turn.$1.label == 'しんだんし'), isTrue);
    expect(bakery[1].dialogue.any((turn) => turn.$2.contains('ケーキ 無料')), isTrue);
    expect(bakery[1].resultDialogue.any((turn) => turn.$2.contains('無料なのは試食だけ')), isTrue);
    expect(bakery[2].resultDialogue.last.$2, 'あら、よかった！ また一緒に遊びましょう');
    for (final episode in bakery) {
      final allText = [
        episode.clue,
        episode.result,
        for (final turn in episode.dialogue) turn.$2,
        for (final turn in episode.resultDialogue) turn.$2,
      ].join(' ');
      expect(allText, isNot(contains('コトホグマ')));
    }
    final club = catalog.episodes.skip(8).take(3).toList();
    expect(club.map((episode) => episode.area.id), ['plaza', 'park', 'plaza']);
    expect(club[1].dialogue.any((turn) => turn.$1.label == 'げんばくん'), isTrue);
    expect(club[1].resultDialogue.any((turn) => turn.$1.label == 'げんばくん'), isTrue);
    expect(club.last.resultDialogue.last.$2, 'ぼくはまだまだこれからなんだ〜');
    for (final episode in club) {
      expect(episode.dialogue.any((turn) => turn.$1.label == 'おやすみくん'), isTrue);
    }
    final salon = catalog.episodes.skip(11).take(3).toList();
    expect(salon.map((e) => e.size), [6, 6, 6]);
    expect(salon.every((e) => e.dialogue.any((t) => t.$1.label == 'おしゃれさん')), isTrue);
    expect(salon[0].dialogue.any((t) => t.$1.label == 'おしゃべりさん'), isTrue);
    expect(salon[1].dialogue.any((t) => t.$1.label == 'ネイリスト'), isTrue);
    expect(salon[2].resultDialogue.any((t) => t.$2.contains('正解は一つじゃない')), isTrue);
    for (final (i, episode) in catalog.episodes.indexed) {
      expect(episode.size, i < 11 ? 4 : 6);
    }
  });


  test('chapter six uses a single duel rule with three distinct boards', () {
    final catalog = parse(storyDocument());
    final chapter = catalog.chapters.last;
    final episodes = catalog.episodes.skip(14).toList();
    expect(chapter.id, 'neru_mama');
    expect(chapter.startIndex, 14);
    expect(chapter.duelStage, StoryDuelStage.crossRoom);
    expect(episodes.length, 3);
    expect(episodes.map((episode) => episode.duel!.stage),
        everyElement(StoryDuelStage.crossRoom));
    expect(episodes.map((episode) => episode.duel!.variant).toList(), [0, 1, 2]);
    expect(episodes.map((episode) => episode.duel!.player.label),
        everyElement('ネイリスト'));
    expect(episodes.map((episode) => episode.duel!.opponent.label),
        everyElement('おしゃべりさん'));
    expect(episodes.map((episode) => episode.size), everyElement(6));
    expect(episodes.map((episode) => episode.puzzle).toSet().length, 3);
    expect(episodes.map((episode) => episode.solution).toSet().length, 3);
    expect(episodes.map((episode) => episode.image).toList(), [
      'story_017_neru_nails_before.webp',
      'story_018_neru_home_before_v2.webp',
      'story_019_neru_shopping_before.webp',
    ]);
    expect(episodes.map((episode) => episode.resultImage).toList(), [
      'story_017_neru_nails_after.webp',
      'story_018_neru_home_after_v2.webp',
      'story_019_neru_shopping_after.webp',
    ]);
    expect(episodes.every((episode) => episode.image != episode.resultImage), isTrue);
  });

  test('text edits retain a signature and structural edits create a new edition', () {
    final original = parse(storyDocument());
    final textEdit = storyDocument();
    _episodes(textEdit).first['dialogue'][0]['text'] = '配信から更新したセリフ';
    expect(parse(textEdit).progressSignature, original.progressSignature);
    final renamed = storyDocument();
    (renamed['chapters'] as List).first['title'] = 'しばぽめのふしぎ';
    expect(parse(renamed).progressSignature, original.progressSignature);
    final rewritten = storyDocument();
    final chapters = _episodes(rewritten);
    chapters.removeRange(2, chapters.length);
    (rewritten['chapters'] as List).removeRange(1, (rewritten['chapters'] as List).length);
    final updated = parse(rewritten);
    expect(updated.episodes.length, 2);
    expect(updated.progressSignature, isNot(original.progressSignature));
    chapters.first['dialogue'].add({
      'speaker': '001_shiba',
      'text': 'あたらしいセリフだわん。',
    });
    expect(parse(rewritten).progressSignature, isNot(updated.progressSignature));
  });

  test(
    'hosted duels use the tuned openings until their catalog puzzle changes',
    () {
      final document = storyDocument();
      final hosted = parse(document);
      for (final index in [2, 4, 7]) {
        final episode = hosted.episodes[index];
        expect(episode.duelPuzzle, storyEpisodes[index].duelPuzzle);
        expect(episode.duelPuzzle, isNot(episode.puzzle));
      }
      final rows = _episodes(document);
      rows[2]['puzzle'] = rows.first['puzzle'];
      rows[2]['solution'] = rows.first['solution'];
      final edited = parse(document).episodes[2];
      expect(edited.duelPuzzle, rows.first['puzzle']);
    },
  );

  test('invalid chapter boundaries fail fast', () {
    final missing = storyDocument()..remove('chapters');
    expect(() => parse(missing), throwsFormatException);
    final unknown = storyDocument();
    (unknown['chapters'] as List)[1]['startEpisodeId'] = 'missing_episode';
    expect(() => parse(unknown), throwsFormatException);
    final outOfOrder = storyDocument();
    (outOfOrder['chapters'] as List)[1]['startEpisodeId'] = 'episode_07';
    expect(() => parse(outOfOrder), throwsFormatException);
    final duplicate = storyDocument();
    (duplicate['chapters'] as List)[1]['id'] = 'shibapome';
    expect(() => parse(duplicate), throwsFormatException);
  });

  test('the story uses WebP art and rejects unsupported image types', () {
    final current = parse(storyDocument());
    expect(current.coverImage, endsWith('.webp'));
    expect(() => parse(storyDocument()..['coverImage'] = 'cover.jpg'),
        throwsFormatException);
  });

  test('unknown cast and external image paths are rejected', () {
    final json = storyDocument();
    _episodes(json).first['dialogue'][0]['speaker'] = 'not_a_resident';
    expect(() => parse(json), throwsFormatException);
    final unsafe = storyDocument()..['coverImage'] = '../cover.png';
    expect(() => parse(unsafe), throwsFormatException);
  });

  test(
    'the pinned release supplies all three datasets and requires its story',
    () async {
      final ids = residents.characters.map((resident) => resident.id).toSet();
      final dialogue = _document('assets/dialogues/dialogues.json');
      final bodies = {
        'api/runtime/catalog': jsonEncode({
          'version': 1,
          'characters': [
            for (final row in registry['characters'] as List)
              if (ids.contains(row['id'])) row,
          ],
          'dialogues': [
            for (final row in dialogue['dialogues'] as List)
              if (ids.contains(row['residentId'])) row,
          ],
        }),
        'api/runtime/oyasumi': File('assets/events/oyasumi_club.json')
            .readAsStringSync(),
        storyJsonPath: jsonEncode(storyDocument()),
      };
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final pinned = Uri.parse('http://127.0.0.1:${server.port}${base.path}');
      final requests = <String>[];
      server.listen((request) async {
        final path = request.uri.path;
        requests.add(path);
        final payload = path.startsWith(pinned.path)
            ? bodies[path.substring(pinned.path.length)]
            : null;
        if (payload == null) {
          request.response.statusCode = HttpStatus.notFound;
        } else {
          request.response.headers.contentType = ContentType.json;
          request.response.write(payload);
        }
        await request.response.close();
      });
      Future<HostedTownContent> load() => HttpOverrides.runWithHttpOverrides(
        () => loadPinnedTownContent(pinned),
        _LoopbackHttp(),
      );
      final content = await load();
      expect(content.story.baseUri, pinned);
      expect(
        requests,
        unorderedEquals(bodies.keys.map((path) => pinned.path + path)),
      );
      bodies.remove(storyJsonPath);
      await expectLater(load(), throwsA(isA<HttpException>()));
    },
  );

  testWidgets('the app opens a saved board from a newly hosted episode', (
    tester,
  ) async {
    final body = storyDocument()..['title'] = '配信から更新した章';
    final episodes = _episodes(body);
    final previous = episodes[13] as Map<String, dynamic>;
    final points = (episodes.last['unlockAt'] as int) + 30;
    final index = episodes.length;
    episodes.add({
      ...previous,
      'id': 'test_new_episode',
      'title': '配信から追加したお話',
      'unlockAt': points,
    });
    final hosted = parse(body);
    final episode = hosted.episodes.last;
    var story = StoryProgress.fromJson({
      'completed': index,
      'dialogueTurns': 0,
      'unreadClue': false,
      'signature': hosted.progressSignature,
    });
    for (final _ in episode.dialogue) {
      story = story.advanceDialogue(index, points, episodes: hosted.episodes);
    }
    final emptyCells = episode
        .initialBoard()
        .asMap()
        .entries
        .where((entry) => entry.value == 0)
        .map((entry) => entry.key)
        .toList();
    final cell = emptyCells.first;
    story = story.useHint(index, points, cell, episodes: hosted.episodes);
    final today = DateTime(2026, 11, 23, 12);
    final save = Progress(
      day: localDay(today),
      lastCompletedDay: localDay(today),
      points: points,
      completed: {},
      story: story,
    );
    final store = MemoryStore()..raw = save.encode();
    final controller = ProgressController(store, clock: () => today);
    final dialogues = (await tester.runAsync(DialogueCatalog.load))!;
    await tester.pumpWidget(
      FutureLiftApp(
        controller: controller,
        dialogueCatalog: dialogues,
        enableTutorial: false,
        remoteContentLoader: () async => HostedTownContent(
          baseUri: base,
          catalog: residents,
          clubConfig: oyasumiConfig,
          story: hosted,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('footer-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-story')));
    await tester.pumpAndSettle();
    expect(find.text(hosted.title), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('story-open-episode')));
    await tester.pumpAndSettle();
    expect(find.text(episode.title), findsOneWidget);
    expect(find.byKey(const ValueKey('story-puzzle')), findsOneWidget);
    expect(controller.progress!.story.board![cell], episode.answerAt(cell));
    final hint = find.byKey(const ValueKey('story-hint'));
    await tester.scrollUntilVisible(
      hint,
      120,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('story-puzzle')),
        matching: find.byType(Scrollable),
      ).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(hint);
    await tester.pumpAndSettle();
    final restored = Progress.decode(store.raw!);
    restored.story.validateFor(hosted, points);
    expect(
      restored.story.board![emptyCells[1]],
      episode.answerAt(emptyCells[1]),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
