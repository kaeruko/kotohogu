import 'dart:convert';

import 'resident_collection.dart';

/// Validates the exact event JSON from the same immutable CloudFront release
/// as the town catalog. Unknown formats and residents fail before rendering.
Map<String, dynamic> parseHostedOyasumi(String source) {
  Map<String, dynamic> object(dynamic value, String name) {
    if (value is! Map<String, dynamic>) {
      throw FormatException('$name must be a JSON object');
    }
    return value;
  }

  List<dynamic> array(dynamic value, String name) {
    if (value is! List<dynamic>) {
      throw FormatException('$name must be a JSON array');
    }
    return value;
  }

  void fields(Map<String, dynamic> value, Set<String> keys, String name) {
    if (value.keys.toSet().difference(keys).isNotEmpty ||
        keys.difference(value.keys.toSet()).isNotEmpty) {
      throw FormatException('$name has unexpected or missing fields');
    }
  }

  void string(dynamic value, String name, {int max = 500}) {
    if (value is! String || value.trim().isEmpty || value.length > max) {
      throw FormatException('$name must contain 1–$max characters');
    }
  }

  void resident(dynamic id, String name) {
    string(id, name, max: 80);
    try {
      TownResident.fromId(id as String);
    } on FormatException catch (error) {
      throw FormatException('$name: ${error.message}');
    }
  }

  void turns(dynamic value, String name, Set<String> cast,
      {int max = 16, String? first}) {
    final list = array(value, name);
    if (list.isEmpty || list.length > max) {
      throw FormatException('$name must have 1–$max turns');
    }
    for (var i = 0; i < list.length; i++) {
      final turn = object(list[i], '$name[$i]');
      fields(turn, {'speaker', 'text'}, '$name[$i]');
      if (turn['speaker'] is! String ||
          !cast.contains(turn['speaker']) ||
          (i == 0 && first != null && turn['speaker'] != first)) {
        throw FormatException('$name[$i] has an invalid speaker');
      }
      string(turn['text'], '$name[$i].text');
    }
  }

  void chatter(dynamic value, String name, String speaker, Set<String> cast) {
    final list = array(value, name);
    if (list.length < 3 || list.length > 5) {
      throw FormatException('$name must have 3–5 conversations');
    }
    for (var i = 0; i < list.length; i++) {
      final item = list[i];
      if (item is String) {
        string(item, '$name[$i]');
      } else {
        final exchange = object(item, '$name[$i]');
        fields(exchange, {'turns'}, '$name[$i]');
        turns(exchange['turns'], '$name[$i].turns', cast,
            max: 8, first: speaker);
      }
    }
  }

  final doc = object(jsonDecode(source), 'oyasumi');
  fields(doc, {
    'version', 'id', 'label', 'background', 'night', 'stages',
    'followupChapters', 'restingDialogue', 'cleanerDialogue',
    'nightPatrol', 'teaVisit',
  }, 'oyasumi');
  if (doc['version'] != 1 || doc['id'] != 'oyasumi_club' ||
      doc['background'] != 'assets/kotohogu/town_background_night.jpg') {
    throw const FormatException('Unsupported Oyasumi Club configuration');
  }
  string(doc['label'], 'label');
  final night = object(doc['night'], 'night');
  fields(night, {'startHour', 'endHour'}, 'night');
  if (night['startHour'] is! int || night['endHour'] is! int ||
      (night['startHour'] as int) < 12 || night['startHour'] > 23 ||
      (night['endHour'] as int) < 1 || night['endHour'] > 11) {
    throw const FormatException('Invalid club night hours');
  }
  final chapters = array(doc['followupChapters'], 'followupChapters');
  if (chapters.length < 2 || chapters.length > 32) {
    throw const FormatException('Expected 2–32 follow-up chapters');
  }
  final stages = object(doc['stages'], 'stages');
  const base = ['solo', 'watching', 'joining', 'joined'];
  final names = <String>[...base];
  for (var i = 0; i < chapters.length; i++) {
    final chapter = object(chapters[i], 'followupChapters[$i]');
    fields(chapter, {
      'stage', 'requiredSeenDialogues', 'requiredOwned',
      'kotohogiAfterPrevious',
    }, 'followupChapters[$i]');
    final stage = chapter['stage'];
    if (stage is! String ||
        !RegExp(r'^[a-z][a-z0-9_]{0,49}$').hasMatch(stage) ||
        names.contains(stage)) {
      throw FormatException('Invalid follow-up chapter ID: $stage');
    }
    names.add(stage);
    final delay = chapter['kotohogiAfterPrevious'];
    if (delay is! int || delay < 0 || delay > 3000 || delay % 10 != 0) {
      throw FormatException('Invalid follow-up delay: $stage');
    }
    final requiredOwned =
        array(chapter['requiredOwned'], '$stage.requiredOwned');
    if (requiredOwned.toSet().length != requiredOwned.length) {
      throw FormatException('Duplicate owned residents: $stage');
    }
    for (final id in requiredOwned) {
      resident(id, '$stage.requiredOwned');
    }
    final seen = array(
        chapter['requiredSeenDialogues'], '$stage.requiredSeenDialogues');
    if (seen.length > 8 || seen.toSet().length != seen.length) {
      throw FormatException('Invalid required dialogues: $stage');
    }
    for (final id in seen) {
      string(id, '$stage.requiredSeenDialogues', max: 100);
    }
  }
  if (chapters[0]['stage'] != 'settling' ||
      chapters[1]['stage'] != 'koala' ||
      (chapters[0]['requiredSeenDialogues'] as List).single !=
          'frog_park_cleaner_started' ||
      (chapters[0]['requiredOwned'] as List).isNotEmpty ||
      chapters[0]['kotohogiAfterPrevious'] != 0 ||
      (chapters[1]['requiredOwned'] as List).length != 1 ||
      (chapters[1]['requiredOwned'] as List).single != '049_koara') {
    throw const FormatException('Existing chapter progression was modified');
  }
  // The publisher intentionally sorts JSON object keys. The ordered
  // followupChapters array, not the stages object order, drives progression.
  if (stages.length != names.length ||
      !stages.keys.toSet().containsAll(names)) {
    throw const FormatException('Stages differ from follow-up chapters');
  }
  for (final name in names) {
    final stage = object(stages[name], 'stages.$name');
    final keys = {'label', 'positions', 'intro', 'chatter'};
    if (name == 'joined') {
      keys.addAll({
        'resignationConversation', 'parkCleanerConversation',
        'rumorConversation', 'specialConversation',
      });
    }
    fields(stage, keys, 'stages.$name');
    string(stage['label'], 'stages.$name.label');
    final positions = object(stage['positions'], '$name.positions');
    final lines = object(stage['chatter'], '$name.chatter');
    final cast = positions.keys.toSet();
    if (cast.isEmpty || cast != lines.keys.toSet() ||
        !cast.contains('027_daydreamer') ||
        (name != 'solo' && !cast.contains('029_office_worker'))) {
      throw FormatException('Invalid cast for stage $name');
    }
    if (name == 'koala' && !cast.contains('049_koara')) {
      throw const FormatException('Koala must be in her introduction');
    }
    for (final entry in positions.entries) {
      resident(entry.key, '$name.cast');
      final xy = array(entry.value, '$name.positions.${entry.key}');
      if (xy.length != 2 ||
          xy.any((n) => n is! num || !n.isFinite || n < .1 || n > .85)) {
        throw FormatException('Invalid position for ${entry.key} in $name');
      }
      chatter(lines[entry.key], '$name.chatter.${entry.key}',
          entry.key, cast);
    }
    final intro = stage['intro'];
    if (name == 'joined') {
      if (intro != null) {
        throw const FormatException('Joined stage must not have an intro');
      }
    } else {
      final opening = object(intro, '$name.intro');
      if (opening['speaker'] != (name == 'solo'
          ? '027_daydreamer' : '029_office_worker')) {
        throw FormatException('Invalid introductory speaker for $name');
      }
      if (opening.containsKey('turns')) {
        fields(opening, {'speaker', 'turns'}, '$name.intro');
        turns(opening['turns'], '$name.intro.turns', cast,
            first: opening['speaker'] as String);
      } else {
        fields(opening, {'speaker', 'text'}, '$name.intro');
        string(opening['text'], '$name.intro.text');
      }
    }
  }
  for (final key in ['restingDialogue', 'cleanerDialogue']) {
    final items = array(doc[key], key);
    if (items.length < 3 || items.length > 8) {
      throw FormatException('Invalid $key count');
    }
    final supported = TownResident.values.map((r) => r.id).toSet();
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (item is String) {
        string(item, '$key[$i]');
      } else {
        final obj = object(item, '$key[$i]');
        fields(obj, {'turns'}, '$key[$i]');
        turns(obj['turns'], '$key[$i].turns', supported,
            max: 8, first: '029_office_worker');
      }
    }
  }
  final joined = object(stages['joined'], 'joined');
  for (final key in [
    'resignationConversation', 'parkCleanerConversation',
    'rumorConversation', 'specialConversation',
  ]) {
    final special = object(joined[key], 'joined.$key');
    fields(special, {'id', 'unlockAfterKotohogi', 'turns'}, 'joined.$key');
    string(special['id'], 'joined.$key.id', max: 100);
    final threshold = special['unlockAfterKotohogi'];
    if (threshold is! int || threshold < 10 || threshold > 3000 ||
        threshold % 10 != 0) {
      throw FormatException('Invalid threshold for $key');
    }
    turns(special['turns'], 'joined.$key.turns',
        {'027_daydreamer', '029_office_worker'},
        max: 8, first: '029_office_worker');
  }
  // The publisher validates these legacy sections fully; require their
  // presence and shape in the client so corrupt transfers fail immediately.
  final patrol = object(doc['nightPatrol'], 'nightPatrol');
  fields(patrol, {'residentId', 'route', 'dialogues'}, 'nightPatrol');
  if (patrol['residentId'] != '036_mosa') {
    throw const FormatException('Invalid patrol speaker');
  }
  final tea = object(doc['teaVisit'], 'teaVisit');
  fields(tea, {
    'label', 'residentId', 'intervalNights', 'position', 'turns',
    'extraDialogue',
  }, 'teaVisit');
  if (tea['residentId'] != '041_pig_middle') {
    throw const FormatException('Invalid tea visitor');
  }
  return Map<String, dynamic>.unmodifiable(doc);
}
