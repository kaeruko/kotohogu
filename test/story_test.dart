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
    'the entire story advances at 30 point milestones in town unlock order',
    () {
      var story = const StoryProgress.empty();
      final destinations = <TownArea>[];
      for (final (index, episode) in storyEpisodes.indexed) {
        final points = index * 30;
        expect(episode.unlockAt, points);
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
      expect(destinations, [
        TownArea.park,
        TownArea.shopping,
        TownArea.village,
      ]);
    },
  );

  test('every solved puzzle has a short story exchange', () {
    for (final episode in storyEpisodes) {
      expect(episode.resultDialogue, isNotEmpty, reason: episode.title);
      expect(
        episode.resultDialogue.every((turn) => turn.$2.isNotEmpty),
        isTrue,
      );
    }
    expect(storyEpisodes.first.resultDialogue.first.$2, contains('これはなにぽむ！？'));
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

  test('story saves coexist with old saves, gacha and date changes', () {
    var progress = Progress.decode(Progress.empty(today).encode());
    expect(progress.story.hasStarted, isFalse);
    for (final mission in Mission.values.take(9)) {
      progress = progress.complete(mission);
    }
    var story = progress.story;
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
    expect(storyEpisodes[3].isAvailable(loaded.points), isTrue);
    expect(storyEpisodes[3].isAvailable(60), isFalse);
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
      expect(find.textContaining('これはなにぽむ！？'), findsOneWidget);
      expect(find.textContaining('すごいわん！'), findsNothing);
      expect(find.text('れんしゅうクリア！'), findsNothing);
      expect(find.byKey(const ValueKey('story-finish-clue')), findsNothing);
      await tap('story-advance-result-dialogue');
      expect(Progress.decode(store.raw!).story.resultDialogueTurns, 1);
      await launch();
      await open();
      expect(find.textContaining('すごいわん！'), findsOneWidget);
      expect(find.textContaining('これはなにぽむ！？'), findsNothing);
      for (var i = 1; i < storyEpisodes.first.resultDialogue.length; i++) {
        await tap('story-advance-result-dialogue');
      }
      expect(find.byKey(const ValueKey('story-result-dialogue')), findsNothing);
      expect(find.text('れんしゅうクリア！'), findsOneWidget);
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
      expect(find.text('あと3回、セルフケアを記録すると開きます。'), findsOneWidget);
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
      'mission after $startingPoints points offers a route to the story',
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
        var story = progress.story;
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
        expect(open, findsOneWidget);
        if (startingPoints == 80) {
          expect(find.text('ふれあい公園が開放されました！'), findsOneWidget);
        }
        await tester.ensureVisible(open);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tap(open);
        await tester.pumpAndSettle();
        expect(Progress.decode(store.raw!).points, startingPoints + 10);
        expect(find.text(storyTitle), findsOneWidget);
        expect(find.text('広場のふしぎな紙'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('story-open-episode')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('the park clue opens the corresponding town area', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = MemoryStore();
    var progress = Progress.empty(today);
    for (final mission in Mission.values.take(9)) {
      progress = progress.complete(mission);
    }
    var story = progress.story;
    for (final (index, episode) in storyEpisodes.take(4).indexed) {
      for (final _ in episode.dialogue) {
        story = story.advanceDialogue(index, progress.points);
      }
      for (var cell = 0; cell < episode.puzzle.length; cell++) {
        if (episode.givenAt(cell) == 0) {
          story = story.useHint(index, progress.points, cell);
        }
      }
      if (index < 3) {
        for (final _ in episode.resultDialogue) {
          story = story.advanceResultDialogue(index);
        }
        story = story.readClue(index);
      }
    }
    await store.save(progress.withStory(story));
    final catalog = (await tester.runAsync(DialogueCatalog.load))!;
    await tester.pumpWidget(
      FutureLiftApp(
        controller: ProgressController(store, clock: () => today),
        dialogueCatalog: catalog,
        enableTutorial: false,
      ),
    );
    await tester.pumpAndSettle();

    Future<void> tap(Finder target) async {
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();
    }

    await tap(find.byKey(const ValueKey('open-story')));
    expect(find.text('ふれあい公園へ行く'), findsNothing);
    await tap(find.byKey(const ValueKey('story-open-episode')));
    expect(find.text('こうえん'), findsNothing);
    for (final _ in storyEpisodes[3].resultDialogue) {
      await tap(find.byKey(const ValueKey('story-advance-result-dialogue')));
    }
    expect(find.text('こうえん'), findsOneWidget);
    await tap(find.byKey(const ValueKey('story-finish-clue')));
    await tap(find.text('ふれあい公園へ行く'));
    expect(find.byKey(const ValueKey('town-page-fullscreen')), findsOneWidget);
    expect(find.text('ふれあい公園'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
