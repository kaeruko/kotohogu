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
    'published story keeps the original save contract and pins its cast',
    () {
      final json = storyDocument();
      final catalog = parse(json);
      expect(catalog.baseUri, base);
      expect(catalog.title, json['title']);
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
      'とけたぽむ！\n数字がぜんぶうまったぽむ〜！',
      'すごいわん！\nはんこじゃなくて、数独っていう数字のパズルだったわん！',
      'すうどく……？ ふしぎな紙ぽむ。だれが書いたぽむ？',
      '紙のうらにも何か書いてあるわん。こんどいっしょに調べるわん！',
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

  test('each solved Sudoku opens with two cheers without adding dialogue turns', () {
    final hostedEpisodes = parse(storyDocument()).episodes;
    expect(hostedEpisodes.length, storyEpisodes.length);
    for (var index = 0; index < storyEpisodes.length; index++) {
      final hosted = hostedEpisodes[index].resultDialogue;
      final bundled = storyEpisodes[index].resultDialogue;
      expect(hosted.length, bundled.length, reason: 'episode $index');
      expect(hosted.first.$2, startsWith('とけたぽむ！\n'), reason: 'episode $index');
      expect(hosted[1].$2, startsWith('すごいわん！\n'), reason: 'episode $index');
      expect(hosted.map((turn) => turn.$2), bundled.map((turn) => turn.$2));
    }
  });

  test(
    'published dialogue can change, but a legacy stage cannot be reordered',
    () {
      final json = storyDocument();
      json['title'] = '配信から更新した章';
      final episodes = _episodes(json);
      episodes.first['dialogue'][0]['text'] = '配信から更新したセリフ';
      final catalog = parse(json);
      expect(catalog.title, '配信から更新した章');
      expect(catalog.episodes.first.dialogue.first.$2, '配信から更新したセリフ');

      episodes[1]['id'] = 'changed_stage';
      expect(() => parse(json), throwsFormatException);
    },
  );

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
    final previous = episodes.last as Map<String, dynamic>;
    final points = (previous['unlockAt'] as int) + 30;
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
    await tester.tap(find.byKey(const ValueKey('open-story')));
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
