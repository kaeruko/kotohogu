import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:future_lift/progress.dart';
import 'package:future_lift/story_data.dart';
import 'package:future_lift/story_progress.dart';
import 'package:future_lift/story_screen.dart';
import 'package:future_lift/sudoku_duel.dart';
import 'package:future_lift/sudoku_duel_view.dart';

import 'progress_test.dart' show MemoryStore;
import 'sudoku_duel_test.dart' show solveSingles;

StoryProgress atEpisode(int index, int turns) => StoryProgress.fromJson({
  'completed': index,
  'dialogueTurns': turns,
  'unreadClue': false,
  'signature': bundledStory.progressSignature,
});

void main() {
  final today = DateTime(2026, 11, 24, 12);
  const pairs = {
    2: ('しばいぬ', 'ぽむぽむ'),
    4: ('モサエド', 'おししょう'),
    7: ('およめさん', 'パティシエ'),
  };

  test('legacy bakery duels resume and finish on the original board', () {
    final episode = storyEpisodes[7];
    const endings = {
      1: [4, 5, 3, 8, 11, 12, 13],
      0: [4, 5, 3, 8, 12, 11, 13],
      -1: [5, 3, 8, 4, 12, 11, 13],
    };
    for (final ending in endings.entries) {
      var story = StoryProgress.fromJson({
        ...atEpisode(7, episode.dialogue.length).toJson(),
        'duelMoves': [ending.value.first],
      });
      for (final cell in ending.value.skip(1)) {
        story = story.playDuelMove(
          7,
          episode.unlockAt,
          cell,
          episode.answerAt(cell),
        );
        story = StoryProgress.fromJson(story.toJson());
      }
      story.validateFor(bundledStory, episode.unlockAt);
      final game = story.duelPosition(episode);
      expect(
        game.score(DuelPlayer.first).compareTo(game.score(DuelPlayer.second)),
        ending.key,
      );
      expect(story.finishDuel(7, episode.unlockAt).unreadClue, isTrue);
    }
  });

  test(
    'story duel logs reject impossible moves and preserve old solo saves',
    () {
      const index = 4;
      final episode = storyEpisodes[index];
      final ready = atEpisode(index, episode.dialogue.length);
      final position = ready.duelPosition(episode);
      final first = position.legalCells.first;
      final saved = ready.playDuelMove(
        index,
        180,
        first,
        episode.answerAt(first),
      );
      expect(saved.finishDuel(index, 180), same(saved));
      expect(saved.useHint(index, 180, null), same(saved));
      final restored = StoryProgress.fromJson(saved.toJson());
      expect(restored.duelLayout, 2);
      restored.validateFor(bundledStory, 180);
      expect(restored.duelPosition(episode).turn, DuelPlayer.second);
      expect(
        restored.duelPosition(episode).targetRoom,
        saved.duelPosition(episode).targetRoom,
      );
      expect(
        () => StoryProgress.fromJson({
          ...saved.toJson(),
          'duelMoves': [first, first],
        }).validateFor(bundledStory, 180),
        throwsFormatException,
      );
      expect(
        () => StoryProgress.fromJson({
          ...saved.toJson(),
          'board': episode.puzzle,
        }),
        throwsFormatException,
      );
      for (final invalid in [null, 3, 2.0, '2']) {
        expect(
          () => StoryProgress.fromJson({
            ...saved.toJson(),
            'duelLayout': invalid,
          }),
          throwsFormatException,
        );
      }
      expect(
        () => StoryProgress.fromJson({...ready.toJson(), 'duelLayout': 2}),
        throwsFormatException,
      );
      final legacy = StoryProgress.fromJson({
        ...ready.toJson(),
        'board': episode.puzzle,
      });
      legacy.validateFor(bundledStory, 180);
      expect(
        legacy.useHint(index, 180, first).board![first],
        episode.answerAt(first),
      );
      expect(
        legacy.playDuelMove(index, 180, first, episode.answerAt(first)),
        same(legacy),
      );
    },
  );

  for (final entry in pairs.entries) {
    final index = entry.key;
    final (player, npc) = entry.value;
    test(
      '$player can force a win and all three outcomes occur against $npc',
      () {
        final episode = storyEpisodes[index];
        final start = atEpisode(
          index,
          episode.dialogue.length,
        ).duelPosition(episode);
        final answer = solveSingles(start);
        expect(answer.join(), episode.solution);

        Iterable<SudokuDuel> moves(SudokuDuel game) =>
            game.legalCells.map((cell) => game.play(cell, answer[cell])!);
        int result(SudokuDuel game) => game
            .score(DuelPlayer.first)
            .compareTo(game.score(DuelPlayer.second));

        // Even an opponent who sees the whole game cannot stop every opening.
        bool canForceWin(SudokuDuel game) {
          if (game.isOver) return result(game) > 0;
          return game.turn == DuelPlayer.first
              ? moves(game).any(canForceWin)
              : moves(game).every(canForceWin);
        }

        final winningOpenings = moves(start).where(canForceWin).length;
        expect(winningOpenings, greaterThan(0));
        expect(winningOpenings, lessThan(start.legalCells.length));

        // These results must be reachable against the same AI the player faces.
        final outcomes = <int>{};
        final random = Random(7);
        void playAgainstNpc(SudokuDuel game) {
          if (game.isOver) {
            outcomes.add(result(game));
          } else if (game.turn == DuelPlayer.second) {
            playAgainstNpc(game.computerMove(episode.duel!.rival, random));
          } else {
            moves(game).forEach(playAgainstNpc);
          }
        }

        playAgainstNpc(start);
        expect(outcomes, {-1, 0, 1});
      },
    );

    testWidgets(
      '$player plays $npc inside the episode, resumes, and earns the clue',
      (tester) async {
        tester.view.physicalSize = const Size(390, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final episode = storyEpisodes[index];
        final store = MemoryStore();
        await store.save(
          Progress(
            day: localDay(today),
            lastCompletedDay: localDay(today),
            points: episode.unlockAt,
            completed: {},
            story: atEpisode(index, episode.dialogue.length - 1),
          ),
        );
        late ProgressController controller;
        Future<void> launch() async {
          await tester.pumpWidget(const SizedBox());
          await tester.pump();
          controller = ProgressController(store, clock: () => today);
          await controller.initialize();
          await tester.pumpWidget(
            MaterialApp(
              home: StoryScreen(
                controller: controller,
                catalog: bundledStory,
                onSelfCare: () {},
                onVisitDestination: (_) {},
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        Finder key(String name) => find.byKey(ValueKey(name));
        Future<void> tap(Finder finder) async {
          await Scrollable.ensureVisible(
            tester.element(finder),
            alignment: 0.5,
          );
          await tester.pump();
          await tester.tap(finder);
          await tester.pump();
        }

        Future<void> open() async {
          await tap(key('story-open-episode'));
          await tester.pumpAndSettle();
        }

        Future<void> humanMove(SudokuDuel game) async {
          final cell = game.legalCells.first;
          await tap(key('duel-cell-$cell'));
          await tap(key('duel-digit-${episode.answerAt(cell)}'));
        }

        await launch();
        await open();
        expect(find.text('$npcと対戦する'), findsOneWidget);
        await tap(key('story-advance-dialogue'));
        expect(find.text('$player VS $npc'), findsOneWidget);
        expect(key('story-puzzle'), findsNothing);
        await humanMove(controller.progress!.story.duelPosition(episode));
        expect(Progress.decode(store.raw!).story.duelMoves, hasLength(1));
        expect(find.text('$npcが考え中…'), findsOneWidget);
        await launch();
        await open();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();
        expect(Progress.decode(store.raw!).story.duelMoves, hasLength(2));
        var game = controller.progress!.story.duelPosition(episode);
        while (!game.isOver) {
          final before = controller.progress!.story.duelMoves!.length;
          if (game.turn == DuelPlayer.first) await humanMove(game);
          await tester.pump(const Duration(seconds: 1));
          await tester.pump();
          expect(
            controller.progress!.story.duelMoves!.length,
            greaterThan(before),
          );
          game = controller.progress!.story.duelPosition(episode);
        }
        await launch();
        await open();
        expect(key('story-finish-duel'), findsOneWidget);
        await tap(key('story-finish-duel'));
        expect(key('story-result-dialogue'), findsOneWidget);
        expect(controller.progress!.story.completed, index + 1);
        expect(controller.progress!.story.duelMoves, isNull);
        for (final _ in episode.resultDialogue) {
          await tap(key('story-advance-result-dialogue'));
        }
        await tap(key('story-finish-clue'));
        await tester.pumpAndSettle();

        // Reopening a cleared clue must not offer another duel or alter
        // the saved story. The player can still read the dialogue.
        final writes = store.writes;
        await tester.scrollUntilVisible(
          find.text(episode.clue).hitTestable(),
          180,
        );
        await tap(find.text(episode.clue));
        await tester.pumpAndSettle();
        expect(key('story-replay-duel'), findsNothing);
        expect(find.textContaining('でもう一局'), findsNothing);
        expect(key('story-result-dialogue'), findsOneWidget);
        expect(key('story-advance-result-dialogue'), findsOneWidget);
        expect(find.byType(SudokuDuelView), findsNothing);
        for (final _ in episode.resultDialogue) {
          await tap(key('story-advance-result-dialogue'));
        }
        expect(find.text(episode.clue), findsOneWidget);
        expect(store.writes, writes);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
