import 'dart:convert';

import 'local_content_preview.dart';
import 'story_data.dart';
import 'story_duel_stage.dart';
import 'town_areas.dart';

const storyJsonPath = 'api/runtime/story';
const storyImagePath = 'api/runtime/story-images/';
const maxStoryJsonBytes = 256 * 1024;
final _imageName = RegExp(r'^[a-z0-9][a-z0-9_-]{0,79}\.(?:png|webp)$');
final _episodeId = RegExp(r'^[a-z][a-z0-9_]{0,47}$');

StoryCatalog parseHostedStory(
  String source,
  Uri baseUri,
  RemoteContentCatalog residents,
) {
  final root = objectOf(jsonDecode(source), storyJsonPath);
  requireFields(root, {
    'version',
    'title',
    'coverImage',
    'episodes',
    'chapters',
  }, storyJsonPath);
  if (root['version'] is! int || root['version'] != 1) {
    throw const FormatException('Unsupported story version');
  }
  final rows = arrayOf(root['episodes'], 'story episodes');
  if (rows.isEmpty || rows.length > 128) {
    throw const FormatException('Invalid story episode count');
  }
  final speakers = {
    for (final resident in residents.characters)
      resident.id: StorySpeaker.hosted(
        resident.label,
        remoteSpriteUri(baseUri, resident, 'idle_front_01.png'),
      ),
  };
  final ids = <String>{};
  final episodes = <StoryEpisode>[];

  String image(Object? raw, String field) {
    if (raw is! String || !_imageName.hasMatch(raw)) {
      throw FormatException('Invalid story image name: $field');
    }
    return raw;
  }

  TownArea area(Object? raw, String field) {
    final area = TownArea.fromId(nonempty(raw, field));
    if (area == TownArea.hospital) {
      throw FormatException('Story area must unlock with points: $field');
    }
    return area;
  }

  List<(StorySpeaker, String)> turns(
    Object? raw,
    String field, {
    bool allowEmpty = false,
  }) {
    final entries = arrayOf(raw, field);
    if ((!allowEmpty && entries.isEmpty) || entries.length > 20) {
      throw FormatException('Invalid number of turns: $field');
    }
    return List.unmodifiable(
      entries.map((entry) {
        final turn = objectOf(entry, field);
        requireFields(turn, {'speaker', 'text'}, field);
        final speaker = speakers[turn['speaker']];
        if (speaker == null) {
          throw FormatException('Unknown story speaker: ${turn['speaker']}');
        }
        return (speaker, nonempty(turn['text'], field));
      }),
    );
  }

  final rowIds = [
    for (final row in rows)
      nonempty(objectOf(row, 'story episode')['id'], 'episode.id'),
  ];
  final chapterRows = arrayOf(root['chapters'], 'story chapters');
  if (chapterRows.isEmpty || chapterRows.length > rows.length) {
    throw const FormatException('Invalid story chapter count');
  }
  final chapterIds = <String>{};
  final chapters = <StoryChapter>[];
  for (final (chapterNumber, raw) in chapterRows.indexed) {
    final field = 'story chapters[$chapterNumber]';
    final chapter = objectOf(raw, field);
    requireFields(
      chapter,
      {'id', 'title', 'startEpisodeId'},
      field,
      optional: {'duelStage'},
    );
    final id = nonempty(chapter['id'], '$field.id');
    final firstEpisodeId = nonempty(
      chapter['startEpisodeId'],
      '$field.startEpisodeId',
    );
    final startIndex = rowIds.indexOf(firstEpisodeId);
    if (!_episodeId.hasMatch(id) ||
        !chapterIds.add(id) ||
        startIndex < 0 ||
        (chapterNumber == 0
            ? startIndex != 0
            : startIndex <= chapters.last.startIndex)) {
      throw FormatException('Invalid story chapter boundary: $field');
    }
    StoryDuelStage? stage;
    if (chapter.containsKey('duelStage')) {
      stage = StoryDuelStage.values.asNameMap()[chapter['duelStage']];
      if (stage == null) {
        throw FormatException(
          'Unknown duel stage in $id: ${chapter['duelStage']}',
        );
      }
    }
    chapters.add(
      StoryChapter(
        id: id,
        title: nonempty(chapter['title'], '$field.title'),
        startIndex: startIndex,
        duelStage: stage,
      ),
    );
  }
  var chapterIndex = 0;
  var duelVariant = 0;
  for (final (index, raw) in rows.indexed) {
    final field = 'story episodes[$index]';
    final row = objectOf(raw, field);
    final isDuel = row.containsKey('duel');
    requireFields(
      row,
      {
        'id',
        'title',
        'area',
        'unlockAt',
        'image',
        'dialogue',
        if (isDuel) 'duel' else ...{'puzzle', 'solution'},
        'clue',
        'result',
        'resultDialogue',
      },
      field,
      optional: {'destination', 'resultImage'},
    );
    final id = nonempty(row['id'], '$field.id');
    final unlockAt = row['unlockAt'];
    final scene = area(row['area'], '$field.area');
    final destination = row.containsKey('destination')
        ? area(row['destination'], '$field.destination')
        : null;
    if (!_episodeId.hasMatch(id) ||
        !ids.add(id) ||
        unlockAt is! int ||
        unlockAt < scene.unlockAt ||
        unlockAt < (destination?.unlockAt ?? 0) ||
        (index == 0 ? unlockAt != 0 : unlockAt <= episodes.last.unlockAt) ||
        unlockAt % 10 != 0) {
      throw FormatException(
        'Invalid story episode ID or unlock threshold: $field',
      );
    }
    if (chapterIndex + 1 < chapters.length &&
        chapters[chapterIndex + 1].startIndex == index) {
      chapterIndex++;
      duelVariant = 0;
    }
    StoryDuel? match;
    if (isDuel) {
      final stage = chapters[chapterIndex].duelStage;
      final cast = objectOf(row['duel'], '$field.duel');
      requireFields(cast, {'player', 'opponent'}, '$field.duel');
      final player = speakers[cast['player']];
      final opponent = speakers[cast['opponent']];
      if (stage == null) {
        throw FormatException('Duel $id requires a chapter stage');
      }
      if (player == null || opponent == null || player == opponent) {
        throw FormatException(
          'Invalid duel cast for $id: ${cast['player']} VS ${cast['opponent']}',
        );
      }
      match = StoryDuel.authored(player, opponent, stage, variant: duelVariant++);
    }
    final board = match?.stage!.boardForVariant(match.variant);
    final episode = StoryEpisode(
      id: id,
      title: nonempty(row['title'], '$field.title'),
      area: scene,
      destination: destination,
      unlockAt: unlockAt,
      image: image(row['image'], '$field.image'),
      resultImage: row.containsKey('resultImage')
          ? image(row['resultImage'], '$field.resultImage')
          : null,
      dialogue: turns(row['dialogue'], '$field.dialogue'),
      authoredDuel: match,
      puzzle: board == null
          ? nonempty(row['puzzle'], '$field.puzzle')
          : board.puzzle,
      solution: board == null
          ? nonempty(row['solution'], '$field.solution')
          : board.solution,
      clue: nonempty(row['clue'], '$field.clue'),
      result: nonempty(row['result'], '$field.result'),
      resultDialogue: turns(
        row['resultDialogue'],
        '$field.resultDialogue',
        allowEmpty: true,
      ),
    );
    if (!isDuel) _validatePuzzle(episode);
    episodes.add(episode);
  }
  return StoryCatalog(
    title: nonempty(root['title'], 'story title'),
    chapters: List.unmodifiable(chapters),
    coverImage: image(root['coverImage'], 'story cover'),
    episodes: List.unmodifiable(episodes),
    baseUri: baseUri,
  );
}

void _validatePuzzle(StoryEpisode episode) {
  final length = episode.puzzle.length;
  if ((length != 16 && length != 36) ||
      episode.solution.length != length ||
      !episode.puzzle.contains('0')) {
    throw FormatException('Invalid story puzzle dimensions: ${episode.id}');
  }
  final solution = List.generate(length, episode.answerAt);
  for (var cell = 0; cell < length; cell++) {
    final given = episode.givenAt(cell);
    if (solution[cell] < 1 ||
        solution[cell] > episode.size ||
        (given != 0 && given != solution[cell]) ||
        episode.hasConflict(solution, cell)) {
      throw FormatException('Invalid story puzzle solution: ${episode.id}');
    }
  }
}
