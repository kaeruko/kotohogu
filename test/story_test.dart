import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:future_lift/dialogue_engine.dart';
import 'package:future_lift/main.dart';
import 'package:future_lift/progress.dart';
import 'package:future_lift/resident_collection.dart';
import 'package:future_lift/story_data.dart';
import 'package:future_lift/story_progress.dart';
import 'package:future_lift/town_areas.dart';

import 'progress_test.dart' show MemoryStore;

void main() {
  final today = DateTime(2026, 11, 22, 12);

  test(
    'every puzzle has a unique answer reachable by filling forced digits',
    () {
      for (final episode in storyEpisodes) {
        final board = episode.initialBoard();
        while (board.contains(0)) {
          var filled = false;
          for (var cell = 0; cell < board.length; cell++) {
            if (board[cell] != 0) continue;
            final used = {
              for (var other = 0; other < board.length; other++)
                if (episode.sharesGroup(cell, other)) board[other],
            };
            final candidates = [
              for (var digit = 1; digit <= episode.size; digit++)
                if (!used.contains(digit)) digit,
            ];
            expect(candidates, isNotEmpty, reason: episode.title);
            if (candidates.length != 1) continue;
            board[cell] = candidates.single;
            filled = true;
          }
          expect(filled, isTrue, reason: episode.title);
        }
        expect(episode.isSolved(board), isTrue, reason: episode.title);
        for (var cell = 0; cell < board.length; cell++) {
          expect(
            episode.hasConflict(board, cell),
            isFalse,
            reason: episode.title,
          );
        }
      }
    },
  );

  test(
    'the eight-episode story opens at its scene milestones',
    () {
      var story = const StoryProgress.empty();
      final destinations = <TownArea>[];
      for (final (index, episode) in storyEpisodes.indexed) {
        final points = episode.unlockAt;
        expect(points, [0, 90, 120, 150, 180, 210, 240, 270][index]);
        if (index > 0) {
          expect(story.advanceDialogue(index, points - 10), same(story));
        }
        expect(story.advanceDialogue(index + 1, points + 90), same(story));
        for (final _ in episode.dialogue) {
          story = story.advanceDialogue(index, points);
        }
        expect(story.board, isNull);
        for (var cell = 0; cell < episode.puzzle.length; cell++) {
          if (episode.givenAt(cell) == 0) {
            story = story.useHint(index, points, cell);
          }
        }
        expect(story.completed, index + 1);
        expect(story.unreadClue, isTrue);
        expect(story.resumeIndex, index);
        if (episode.destination case final destination?) {
          expect(destination.isUnlocked(points - 10), isFalse);
          expect(destination.isUnlocked(points), isTrue);
          destinations.add(destination);
        }
        final loaded = StoryProgress.fromJson(story.toJson());
        loaded.validateFor(bundledStory, points);
        expect(loaded.unreadClue, isTrue);
        expect(loaded.readClue(index), same(loaded));
        var reading = loaded;
        for (final _ in episode.resultDialogue) {
          reading = reading.advanceResultDialogue(index);
        }
        expect(reading.resultDialogueTurns, episode.resultDialogue.length);
        story = reading.readClue(index);
        expect(story.resumeIndex, index + 1);
      }
      expect(destinations, isEmpty);
      expect(story.completed, 8);
    },
  );

  test('three story chapters preserve the existing episode structure', () {
    expect(storyChapters.map((chapter) => chapter.title),
      ['しばぽめ', 'モサエド', 'およめさん']);
    expect(storyChapters.map((chapter) => chapter.startIndex), [0, 3, 5]);
    expect(bundledStory.chapterIndexForEpisode(0), 0);
    expect(bundledStory.chapterIndexForEpisode(2), 0);
    expect(bundledStory.chapterIndexForEpisode(3), 1);
    expect(bundledStory.chapterIndexForEpisode(4), 1);
    expect(bundledStory.chapterIndexForEpisode(5), 2);
    expect(bundledStory.chapterIndexForEpisode(7), 2);
    expect(() => bundledStory.chapterIndexForEpisode(8), throwsRangeError);
  });

  test('every solved puzzle has a short story exchange', () {
    for (final episode in storyEpisodes) {
      expect(episode.resultDialogue, isNotEmpty, reason: episode.title);
      expect(
        episode.resultDialogue.every((turn) => turn.$2.isNotEmpty),
        isTrue,
      );
    }
    expect(storyEpisodes.first.dialogue.last.$2, contains('これはなにぽむ？'));
  });

  test('post-sudoku dialogue position survives save/load and fails fast on invalid data', () {
    var story = const StoryProgress.empty();
    final episode = storyEpisodes.first;
    for (final _ in episode.dialogue) {
      story = story.advanceDialogue(0, 0);
    }
    for (var cell = 0; cell < episode.puzzle.length; cell++) {
      if (episode.givenAt(cell) == 0) {
        story = story.useHint(0, 0, cell);
      }
    }
    expect(story.unreadClue, isTrue);
    expect(story.readClue(0), same(story));
    story = story.advanceResultDialogue(0);
    expect(story.resultDialogueTurns, 1);
    final saved = StoryProgress.fromJson(story.toJson());
    saved.validateFor(bundledStory, 0);
    expect(saved.resultDialogueTurns, 1);
    expect(saved.readClue(0), same(saved));
    final invalid = {...saved.toJson(), 'resultDialogueTurns': 999};
    expect(
      () => StoryProgress.fromJson(invalid).validateFor(bundledStory, 0),
      throwsFormatException,
    );
    expect(
      () => StoryProgress.fromJson({
        ...saved.toJson(),
        'resultDialogueTurns': '1',
      }),
      throwsFormatException,
    );
  });

  test('editions restart only story, preserve other data, reject invalid signatures', () {
    var original = const StoryProgress.empty().forCatalog(bundledStory);
    original = original.advanceDialogue(0, 0);
    final saved = StoryProgress.fromJson(original.toJson());
    expect(saved.signature, bundledStory.progressSignature);
    expect(saved.forCatalog(bundledStory).dialogueTurns, 1);
    final edited = StoryCatalog(
      title: '別のお話',
      episodes: storyEpisodes.sublist(0, 2),
      chapters: const [
        StoryChapter(id: 'shibapome', title: 'しばぽめ', startIndex: 0),
      ],
    );
    expect(edited.progressSignature, isNot(bundledStory.progressSignature));
    expect(() => saved.validateFor(edited, 0), throwsFormatException);
    final restart = saved.forCatalog(edited);
    expect(restart.hasStarted, isFalse);
    expect(restart.signature, edited.progressSignature);
    final user = Progress.empty(today).complete(Mission.strength)
        .withStory(saved);
    final migrated = user.withStory(user.story.forCatalog(edited));
    expect(migrated.points, user.points);
    expect(migrated.residents.encode(), user.residents.encode());
    expect(migrated.completed, user.completed);
    expect(migrated.story.hasStarted, isFalse);
    expect(
      () => StoryProgress.fromJson({...saved.toJson(), 'signature': 'broken'}),
      throwsFormatException,
    );
  });

  test('story saves coexist with old saves, gacha and date changes', () {
    var progress = Progress.decode(Progress.empty(today).encode());
    expect(progress.story.hasStarted, isFalse);
    for (final mission in Mission.values.take(9)) {
      progress = progress.complete(mission);
    }
    var story = progress.story.forCatalog(bundledStory);
    for (final _ in storyEpisodes.first.dialogue) {
      story = story.advanceDialogue(0, progress.points);
    }
    story = story.enterNumber(0, progress.points, 2, 2);
    progress = progress
        .withStory(story)
        .acquireResident(TownResident.c052_pome)
        .onDay(today.add(const Duration(days: 1)));
    final loaded = Progress.decode(progress.encode());
    expect(loaded.points, 90);
    expect(loaded.residents.availableKotohogi(loaded.points), 60);
    expect(storyEpisodes[1].isAvailable(loaded.points), isTrue);
    expect(storyEpisodes[1].isAvailable(60), isFalse);
    expect(loaded.story.board![2], 2);
    expect(loaded.story.dialogueTurns, storyEpisodes.first.dialogue.length);

    final corrupt = jsonDecode(progress.encode()) as Map<String, dynamic>;
    (corrupt['story'] as Map<String, dynamic>)['board'] = '0204412300301342';
    final corruptProgress = Progress.decode(jsonEncode(corrupt));
    expect(
      () => corruptProgress.story.validateFor(
        bundledStory,
        corruptProgress.points,
      ),
      throwsFormatException,
    );
  });

  testWidgets(
    'home story resumes dialogue, a board and the unread clear result',
    (tester) async {
      tester.view.physicalSize = const Size(360, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final store = MemoryStore();
      final catalog = (await tester.runAsync(DialogueCatalog.load))!;

      Future<void> launch() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await tester.pumpWidget(
          FutureLiftApp(
            controller: ProgressController(store, clock: () => today),
            dialogueCatalog: catalog,
            enableTutorial: false,
          ),
        );
        await tester.pumpAndSettle();
      }

      Future<void> tap(String key) async {
        final target = find.byKey(ValueKey(key));
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        await tester.tap(target);
        await tester.pumpAndSettle();
      }

      Future<void> open() async {
        await tap('open-story');
        await tap('story-open-episode');
      }

      await launch();
      await open();
      expect(find.text('ぽむぽむ'), findsOneWidget);
      expect(find.byKey(const ValueKey('story-view-list')), findsOneWidget);
      await tap('story-advance-dialogue');
      await launch();
      await open();
      expect(find.text('しばいぬ'), findsOneWidget);
      await tap('story-advance-dialogue');
      await tap('story-advance-dialogue');
      expect(find.byKey(const ValueKey('story-view-list')), findsOneWidget);
      await tap('story-cell-2');
      await tap('story-number-2');
      expect(find.text('同じ数字が重なっているマスがあります。'), findsOneWidget);

      await launch();
      await open();
      expect(Progress.decode(store.raw!).story.board![2], 2);
      expect(find.byKey(const ValueKey('story-puzzle')), findsOneWidget);
      for (var i = 0; i < 4; i++) {
        await tap('story-hint');
      }
      expect(
        find.byKey(const ValueKey('story-result-dialogue')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('story-view-list')), findsOneWidget);
      expect(find.textContaining('とけたぽむ！'), findsOneWidget);
      expect(find.textContaining('「おおきな きのした」'), findsOneWidget);
      expect(find.textContaining('すごいわん！'), findsNothing);
      expect(find.text('おおきな きのした'), findsNothing);
      expect(find.byKey(const ValueKey('story-finish-clue')), findsNothing);
      await tap('story-advance-result-dialogue');
      expect(Progress.decode(store.raw!).story.resultDialogueTurns, 1);
      await launch();
      await open();
      expect(find.textContaining('すごいわん！'), findsOneWidget);
      expect(find.textContaining('「おおきな きのした」'), findsNothing);
      for (var i = 1; i < storyEpisodes.first.resultDialogue.length; i++) {
        await tap('story-advance-result-dialogue');
      }
      expect(find.byKey(const ValueKey('story-result-dialogue')), findsNothing);
      expect(find.text('おおきな きのした'), findsOneWidget);
      expect(
        Progress.decode(store.raw!).story.resultDialogueTurns,
        storyEpisodes.first.resultDialogue.length,
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('story-finish-clue')),
        160,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('story-clue')),
          matching: find.byType(Scrollable),
        ),
      );
      await tap('story-finish-clue');
      expect(find.text('あと9回、セルフケアを記録すると開きます。'), findsOneWidget);
      expect(find.byKey(const ValueKey('story-open-episode')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'episode list button returns to the story index and resumes the same line',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final store = MemoryStore();
      final controller = ProgressController(store, clock: () => today);
      final catalog = (await tester.runAsync(DialogueCatalog.load))!;
      await tester.pumpWidget(
        FutureLiftApp(
          controller: controller,
          dialogueCatalog: catalog,
          enableTutorial: false,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('open-story')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('story-open-episode')));
      await tester.pumpAndSettle();

      final listButton = find.byKey(const ValueKey('story-view-list'));
      expect(listButton, findsOneWidget);
      expect(find.text('お話一覧へ'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('story-advance-dialogue')));
      await tester.pumpAndSettle();
      expect(find.text('しばいぬ'), findsOneWidget);

      await tester.tap(listButton);
      await tester.pumpAndSettle();
      expect(find.text('ストーリー'), findsOneWidget);
      expect(find.byKey(const ValueKey('story-open-episode')), findsOneWidget);
      expect(find.byKey(const ValueKey('story-view-list')), findsNothing);
      expect(controller.progress!.story.dialogueTurns, 1);

      await tester.tap(find.byKey(const ValueKey('story-open-episode')));
      await tester.pumpAndSettle();
      expect(find.text('しばいぬ'), findsOneWidget);
      expect(find.byKey(const ValueKey('story-view-list')), findsOneWidget);
      expect(Progress.decode(store.raw!).story.dialogueTurns, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  for (final startingPoints in [20, 80]) {
    testWidgets(
      'mission after $startingPoints points follows story unlock rules',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final store = MemoryStore();
        var progress = Progress.empty(today);
        for (final mission
            in Mission.values
                .where((mission) => mission != Mission.strength)
                .take(startingPoints ~/ 10)) {
          progress = progress.complete(mission);
        }
        var story = progress.story.forCatalog(bundledStory);
        for (final _ in storyEpisodes.first.dialogue) {
          story = story.advanceDialogue(0, progress.points);
        }
        for (var cell = 0; cell < storyEpisodes.first.puzzle.length; cell++) {
          if (storyEpisodes.first.givenAt(cell) == 0) {
            story = story.useHint(0, progress.points, cell);
          }
        }
        for (final _ in storyEpisodes.first.resultDialogue) {
          story = story.advanceResultDialogue(0);
        }
        progress = progress.withStory(story.readClue(0));
        await store.save(progress);
        await tester.pumpWidget(
          FutureLiftApp(
            controller: ProgressController(store, clock: () => today),
            dialogueCatalog: (await tester.runAsync(DialogueCatalog.load))!,
            enableTutorial: false,
            initialPage: 1,
          ),
        );
        await tester.pumpAndSettle();

        final mission = find.byKey(const ValueKey('complete-strength'));
        await tester.ensureVisible(mission);
        await tester.pumpAndSettle();
        await tester.tap(mission);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1400));
        expect(find.text(storyTitle), findsNothing);
        final open = find.byKey(const ValueKey('celebration-open-story'));
        if (startingPoints == 20) {
          expect(open, findsNothing);
          expect(Progress.decode(store.raw!).points, 30);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          return;
        }
        expect(open, findsOneWidget);
        expect(find.text('ふれあい公園が開放されました！'), findsOneWidget);
        await tester.ensureVisible(open);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tap(open);
        await tester.pumpAndSettle();
        expect(Progress.decode(store.raw!).points, startingPoints + 10);
        expect(find.text(storyTitle), findsOneWidget);
        expect(find.text('木の下になにがある？'), findsWidgets);
        expect(find.byKey(const ValueKey('story-open-episode')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  test('Mosædo first duel starts in the hall and ends with Oshishō challenge', () {
    final episode = storyEpisodes[3];
    expect(episode.id, 'episode_03');
    expect(episode.area, TownArea.plaza);
    expect(episode.unlockAt, 150);
    expect(episode.dialogue.last.$2, contains('あおんあおん！'));
    expect(episode.dialogue.any((turn) => turn.$2.contains('かわりに解いて')), isFalse);
    expect(episode.resultDialogue.first.$2, '勝ったでござる！ あおんあおん！');
    expect(episode.resultDialogue.last.$2, 'うちに勝てはりますやろか？');
    expect(episode.resultDialogue.any((turn) => turn.$2.contains('新手の挑戦者')), isFalse);
  });

  test('Oshisho accepts the duel and hints at the white bear', () {
    final duel = storyEpisodes[4];
    expect(duel.id, 'episode_04');
    expect(duel.title, 'おししょうの一局');
    expect(duel.area, TownArea.plaza);
    expect(duel.unlockAt, 180);
    expect(duel.dialogue.first.$1.label, 'おししょう');
    expect(duel.dialogue.any((turn) => turn.$1.label == 'モサエド'), isTrue);
    expect(duel.resultDialogue.any((turn) => turn.$2.contains('白い熊')), isTrue);
    expect(duel.resultDialogue.last.$1.label, 'モサエド');
  });

  test('the bakery couple enjoys three ordinary Sudoku games without the bear legend', () {
    final bakeryEpisodes = storyEpisodes.skip(5).toList();
    expect(bakeryEpisodes.map((e) => e.title), [
      '帳簿と数独',
      'ケーキ無料！？',
      'ふたりの休憩時間',
    ]);
    expect(bakeryEpisodes.map((e) => e.area), everyElement(TownArea.shopping));
    expect(bakeryEpisodes.map((e) => e.unlockAt), [210, 240, 270]);
    expect(bakeryEpisodes.every((e) => e.dialogue.any((turn) => turn.$1.label == 'およめさん')), isTrue);
    expect(bakeryEpisodes.every((e) => e.dialogue.any((turn) => turn.$1.label == 'パティシエ')), isTrue);
    expect(bakeryEpisodes[1].dialogue.any((turn) => turn.$1.label == 'しんだんし'), isTrue);
    for (final episode in bakeryEpisodes) {
      final text = [
        episode.clue,
        episode.result,
        for (final turn in episode.dialogue) turn.$2,
        for (final turn in episode.resultDialogue) turn.$2,
      ].join(' ');
      expect(text, isNot(contains('コトホグマ')));
      expect(episode.size, 4);
    }
    expect(bakeryEpisodes[0].resultDialogue.last.$2, contains('試食'));
    expect(bakeryEpisodes[1].dialogue.any((turn) => turn.$2.contains('ケーキ 無料')), isTrue);
    expect(bakeryEpisodes[1].dialogue.any((turn) => turn.$2.contains('風で飛んじゃった')), isTrue);
    expect(bakeryEpisodes[1].resultDialogue.any((turn) => turn.$2.contains('無料なのは試食だけ')), isTrue);
    expect(bakeryEpisodes[2].resultDialogue.any((turn) => turn.$2.contains('数独はわたしの勝ち')), isTrue);
    expect(bakeryEpisodes.last.resultDialogue.last.$2, 'あら、よかった！ また一緒に遊びましょう');
  });

  testWidgets('the third episode reveals Gonsuke before the next chapter', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = MemoryStore();
    const points = 120;
    var story = const StoryProgress.empty().forCatalog(bundledStory);
    for (final (index, episode) in storyEpisodes.take(3).indexed) {
      for (final _ in episode.dialogue) {
        story = story.advanceDialogue(index, points);
      }
      for (var cell = 0; cell < episode.puzzle.length; cell++) {
        if (episode.givenAt(cell) == 0) {
          story = story.useHint(index, points, cell);
        }
      }
      if (index != 2) {
        for (final _ in episode.resultDialogue) {
          story = story.advanceResultDialogue(index);
        }
        story = story.readClue(index);
      }
    }
    await store.save(Progress(
      day: localDay(today),
      lastCompletedDay: localDay(today),
      points: points,
      completed: {},
      story: story,
    ));
    final catalog = (await tester.runAsync(DialogueCatalog.load))!;
    await tester.pumpWidget(
      FutureLiftApp(
        controller: ProgressController(store, clock: () => today),
        dialogueCatalog: catalog,
        enableTutorial: false,
      ),
    );
    await tester.pumpAndSettle();

    Future<void> tap(String key) async {
      final target = find.byKey(ValueKey(key));
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();
    }

    await tap('open-story');
    expect(find.text('暗号 2 / 8'), findsOneWidget);
    await tap('story-open-episode');
    for (final turn in storyEpisodes[2].resultDialogue) {
      expect(find.text(turn.$1.label), findsOneWidget);
      expect(find.text(turn.$2), findsOneWidget);
      await tap('story-advance-result-dialogue');
    }
    expect(find.text('さくらのはんこ 🌸'), findsOneWidget);
    await tap('story-finish-clue');
    // The grouped episode list may retain its prior scroll position.
    // Scroll back to the progress meter before checking its visible text.
    for (var attempt = 0;
        attempt < 5 && find.text('暗号 3 / 8').evaluate().isEmpty;
        attempt++) {
      await tester.drag(find.byType(ListView).last, const Offset(0, 600));
      await tester.pumpAndSettle();
    }
    expect(find.text('暗号 3 / 8'), findsOneWidget);
    expect(find.text('数独道場破りでござる！'), findsWidgets);
    expect(Progress.decode(store.raw!).story.completed, 3);
    expect(Progress.decode(store.raw!).story.unreadClue, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
