import 'dart:convert';

import 'local_content_preview.dart';
import 'story_data.dart';
import 'town_areas.dart';

const storyJsonPath = 'api/runtime/story-v2';
const storyImagePath = 'api/runtime/story-images/';
const maxStoryJsonBytes = 256 * 1024;
final _imageName = RegExp(r'^[a-z0-9][a-z0-9_-]{0,79}\.png$');
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

  for (final (index, raw) in rows.indexed) {
    final field = 'story episodes[$index]';
    final row = objectOf(raw, field);
    requireFields(
      row,
      {
        'id',
        'title',
        'area',
        'unlockAt',
        'image',
        'dialogue',
        'puzzle',
        'solution',
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
      puzzle: nonempty(row['puzzle'], '$field.puzzle'),
      solution: nonempty(row['solution'], '$field.solution'),
      clue: nonempty(row['clue'], '$field.clue'),
      result: nonempty(row['result'], '$field.result'),
      resultDialogue: turns(
        row['resultDialogue'],
        '$field.resultDialogue',
        allowEmpty: true,
      ),
    );
    _validatePuzzle(episode);
    episodes.add(episode);
  }
  return StoryCatalog(
    title: nonempty(root['title'], 'story title'),
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
