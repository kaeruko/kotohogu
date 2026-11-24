import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:future_lift/local_content_preview.dart';
import 'package:future_lift/resident_collection.dart';
import 'package:future_lift/story_data.dart';
import 'package:future_lift/story_duel_stage.dart';
import 'package:future_lift/story_progress.dart';
import 'package:future_lift/story_remote_config.dart';
import 'package:future_lift/sudoku_duel.dart';
import 'package:future_lift/sudoku_duel_view.dart';

import 'sudoku_duel_test.dart' show solveSingles;

void main() {
  final original = File('assets/story/story.json').readAsStringSync();
  final registry = jsonDecode(
    File('assets/characters/characters.json').readAsStringSync(),
  );
  final residents = RemoteContentCatalog([
    for (final row in registry['characters'])
      if (row['archived'] != true) RemoteResident.fromJson(row),
  ], const []);
  StoryCatalog parse(String source) => parseHostedStory(
    source,
    Uri.parse('https://content.example.test/release/'),
    residents,
  );
  final old = parse(original);
  Map<String, dynamic> append(StoryDuelStage stage) {
    final doc = jsonDecode(original) as Map<String, dynamic>;
    final episode = Map<String, dynamic>.from(doc['episodes'].last as Map)
      ..remove('puzzle')
      ..remove('solution')
      ..addAll({
        'id': 'new_duel',
        'unlockAt': 9000,
        'duel': {'player': '001_shiba', 'opponent': '038_lion_lady'},
      });
    doc['episodes'].add(episode);
    doc['chapters'].add({
      'id': 'next_chapter',
      'title': '追加章',
      'startEpisodeId': 'new_duel',
      'duelStage': stage.name,
    });
    return doc;
  }

  for (final stage in StoryDuelStage.values) {
    test('${stage.name} is winnable and resumes on its own rules', () {
      final catalog = parse(jsonEncode(append(stage)));
      final index = old.episodes.length;
      final episode = catalog.episodes[index];
      expect(episode.duel!.stage, stage);
      expect(episode.duel!.opponent.portrait!.path, contains('038_lion_lady'));
      expect(
        solveSingles(SudokuDuel.story(stage.puzzle, stage.solution, [])).join(),
        stage.solution,
      );
      var progress = StoryProgress.fromJson({
        'signature': old.progressSignature,
        'completed': index,
        'dialogueTurns': 0,
        'unreadClue': false,
      }).forCatalog(catalog);
      expect(progress.completed, index);
      for (var i = 0; i < episode.dialogue.length; i++) {
        progress = progress.advanceDialogue(
          index,
          9000,
          episodes: catalog.episodes,
        );
      }
      var game = progress.duelPosition(episode);
      expect(game.turn, DuelPlayer.first);
      SudokuDuel place(SudokuDuel position, int cell) =>
          position.play(cell, episode.answerAt(cell))!;
      bool canWin(SudokuDuel position) {
        if (position.isOver) {
          return position.score(DuelPlayer.first) >
              position.score(DuelPlayer.second);
        }
        bool winningReply(int cell) => canWin(place(position, cell));
        return position.turn == DuelPlayer.first
            ? position.legalCells.any(winningReply)
            : position.legalCells.every(winningReply);
      }

      expect(canWin(game), isTrue);
      if (stage == StoryDuelStage.endgame) {
        expect(DuelPlayer.values.map(game.score), [3, 3]);
      }
      if (stage == StoryDuelStage.flagOrder ||
          stage == StoryDuelStage.sacrifice) {
        final take = stage == StoryDuelStage.flagOrder ? 0 : 32;
        final better = stage == StoryDuelStage.flagOrder ? 8 : 15;
        expect(canWin(place(game, take)), isFalse);
        expect(canWin(place(game, better)), isTrue);
      }
      final rng = Random(17);
      var moves = 0;
      while (!game.isOver) {
        final next = game.turn == DuelPlayer.first
            ? place(game, game.legalCells.first)
            : game.computerMove(null, rng);
        final cell = next.lastCell!;
        progress = progress.playDuelMove(
          index,
          9000,
          cell,
          next.valueAt(cell),
          episodes: catalog.episodes,
        );
        progress = StoryProgress.fromJson(progress.toJson());
        progress.validateFor(catalog, 9000);
        game = progress.duelPosition(episode);
        expect(progress.duelMoves, hasLength(++moves));
        expect(game.targetRoom, next.targetRoom);
        expect(
          DuelPlayer.values.map(game.score),
          DuelPlayer.values.map(next.score),
        );
        expect(game.lastCell, cell);
      }
      final points = DuelPlayer.values.map(game.score);
      if (stage.firstTo == 1) expect(points.reduce(max), 1);
      if (stage.doubleRoom != null) expect(points.reduce((a, b) => a + b), 5);
      if (episode.size == 9) expect(points.reduce(max), 5);
      expect(
        progress.finishDuel(index, 9000, episodes: catalog.episodes).completed,
        index + 1,
      );
    });
  }

  for (final stage in StoryDuelStage.values) {
    test('${stage.name}: five matches vary safely within a chapter', () {
      final doc = append(stage);
      final originalEpisode = doc['episodes'].last as Map;
      for (var variant = 1; variant < 5; variant++) {
        doc['episodes'].add({
          ...originalEpisode,
          'id': 'new_duel_$variant',
          'unlockAt': 9000 + variant * 30,
        });
      }
      final catalog = parse(jsonEncode(doc));
      final matches = catalog.episodes.skip(old.episodes.length).toList();
      expect(matches.map((episode) => episode.puzzle).toSet(), hasLength(5));
      final originalGame = SudokuDuel.story(
        stage.puzzle, stage.solution, [], stage: stage,
      );
      for (final (variant, episode) in matches.indexed) {
        expect(episode.duel!.stage, stage);
        expect(episode.duel!.variant, variant);
        final board = stage.boardForVariant(variant);
        expect(episode.puzzle, board.puzzle);
        expect(episode.solution, board.solution);
        expect(
          solveSingles(SudokuDuel.story(episode.puzzle, episode.solution, [])).join(),
          episode.solution,
        );
        final index = old.episodes.length + variant;
        var progress = StoryProgress.fromJson({
          'completed': index,
          'dialogueTurns': episode.dialogue.length,
          'unreadClue': false,
          'signature': catalog.progressSignature,
        });
        var game = progress.duelPosition(episode);
        var reference = originalGame;
        // Compare the same sequence on both boards, including pre-played moves.
        // Every legal alternative has a one-to-one corresponding move.
        while (true) {
          expect(game.turn, reference.turn);
          expect(game.targetRoom, reference.targetRoom);
          expect(game.isOver, reference.isOver);
          expect(
            game.legalCells.toSet(),
            reference.legalCells.map((cell) => board.cellMap[cell]).toSet(),
          );
          for (final player in DuelPlayer.values) {
            expect(game.score(player), reference.score(player));
          }
          for (var room = 1; room <= game.size.side; room++) {
            expect(game.flagAt(room), reference.flagAt(room));
          }
          for (var cell = 0; cell < board.cellMap.length; cell++) {
            final mapped = board.cellMap[cell];
            expect(game.size.roomOf(mapped), reference.size.roomOf(cell));
            expect(game.valueAt(mapped), reference.valueAt(cell));
            expect(game.isGiven(mapped), reference.isGiven(cell));
            expect(episode.answerAt(mapped), int.parse(stage.solution[cell]));
          }
          if (game.isOver) break;
          final cell = reference.legalCells.first;
          final digit = int.parse(stage.solution[cell]);
          reference = reference.play(cell, digit)!;
          progress = progress.playDuelMove(
            index, episode.unlockAt, board.cellMap[cell], digit,
            episodes: catalog.episodes,
          );
          progress = StoryProgress.fromJson(progress.toJson());
          // Loading the same JSON again must reconstruct the identical board.
          final reopened = parse(jsonEncode(doc));
          progress.validateFor(reopened, episode.unlockAt);
          game = progress.duelPosition(reopened.episodes[index]);
        }
      }
    });
  }

  test('appending a match keeps earlier board variants and their progress', () {
    final doc = append(StoryDuelStage.flagOrder);
    final first = doc['episodes'].last as Map;
    doc['episodes'].add({...first, 'id': 'second_duel', 'unlockAt': 9030});
    final before = parse(jsonEncode(doc));
    final index = old.episodes.length + 1;
    final episode = before.episodes[index];
    var progress = StoryProgress.fromJson({
      'completed': index,
      'dialogueTurns': episode.dialogue.length,
      'unreadClue': false,
      'signature': before.progressSignature,
    });
    final cell = progress.duelPosition(episode).legalCells.first;
    progress = progress.playDuelMove(
      index, 9030, cell, episode.answerAt(cell), episodes: before.episodes,
    );
    doc['episodes'].add({...first, 'id': 'third_duel', 'unlockAt': 9060});
    final after = parse(jsonEncode(doc));
    final resumed = progress.forCatalog(after);
    resumed.validateFor(after, 9030);
    expect(after.episodes[index].puzzle, episode.puzzle);
    expect(resumed.duelMoves, progress.duelMoves);
    expect(resumed.duelPosition(after.episodes[index]).lastCell, cell);
    expect(after.episodes.last.duel!.variant, 2);
    expect(
      () => SudokuDuel.story(
        episode.puzzle, episode.solution, [], stage: StoryDuelStage.flagOrder,
      ),
      throwsFormatException,
    );
  });

  test('appending preserves published matches, unread clues and current save data', () {
    final catalog = parse(jsonEncode(append(StoryDuelStage.firstFlag)));
    for (var i = 0; i < old.episodes.length; i++) {
      expect(catalog.episodes[i].duel, same(old.episodes[i].duel));
      expect(catalog.episodes[i].duelPuzzle, old.episodes[i].duelPuzzle);
    }
    final turns = old.episodes[2].dialogue.length;
    for (final extras in [
      {'completed': 2, 'dialogueTurns': turns},
      {
        'completed': 2,
        'dialogueTurns': turns,
        'duelMoves': [1],
      },
      {'completed': 3, 'unreadClue': true, 'resultDialogueTurns': 1},
      {'completed': 11},
    ]) {
      final saved = StoryProgress.fromJson({
        'completed': 0,
        'dialogueTurns': 0,
        'unreadClue': false,
        'signature': old.progressSignature,
        ...extras,
      });
      final next = saved.forCatalog(catalog);
      next.validateFor(catalog, 9000);
      expect(next.toJson(), {
        ...saved.toJson(),
        'signature': catalog.progressSignature,
      });
    }
  });

  test('an authored match requires an explicit chapter stage and two active residents', () {
    final doc = append(StoryDuelStage.firstFlag);
    final cast = doc['episodes'].last['duel'];
    cast['opponent'] = cast['player'];
    expect(() => parse(jsonEncode(doc)), throwsFormatException);
    cast['opponent'] = 'does_not_exist';
    expect(() => parse(jsonEncode(doc)), throwsFormatException);
    cast['opponent'] = '038_lion_lady';
    doc['chapters'].last['duelStage'] = 'typo';
    expect(() => parse(jsonEncode(doc)), throwsFormatException);
    doc['chapters'].last.remove('duelStage');
    expect(() => parse(jsonEncode(doc)), throwsFormatException);
  });

  testWidgets('a new cast takes its own NPC turn on the story screen', (
    tester,
  ) async {
    const stage = StoryDuelStage.firstFlag;
    const match = StoryDuel.authored(
      StorySpeaker.local(TownResident.shiba),
      StorySpeaker.local(TownResident.rabbit),
      stage,
    );
    var game = SudokuDuel.story(stage.puzzle, stage.solution, [], stage: stage);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (context, refresh) => SudokuDuelView.story(
                match: match,
                position: game,
                onMove: (cell, digit) =>
                    refresh(() => game = game.play(cell, digit)!),
                onFinish: () {},
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining(stage.objective), findsOneWidget);
    final cell = game.legalCells.first;
    await tester.tap(find.byKey(ValueKey('duel-cell-$cell')));
    await tester.pump();
    final digit = find.byKey(ValueKey('duel-digit-${stage.solution[cell]}'));
    await tester.ensureVisible(digit);
    await tester.tap(digit);
    await tester.pump();
    expect(game.turn, DuelPlayer.second);
    await tester.pump(const Duration(seconds: 1));
    expect(game.turn, DuelPlayer.first);
  });
}
