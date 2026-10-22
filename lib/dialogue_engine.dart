import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'progress.dart';
import 'resident_collection.dart';

const dialogueSites = {'roster', 'town', 'salon', 'bakery', 'community_center'};

class DialogueCatalog {
  DialogueCatalog._(this.entries);
  static const assetPath = 'assets/dialogues/dialogues.json';
  final List<DialogueEntry> entries;

  static Future<DialogueCatalog> load() async =>
      fromJson(await rootBundle.loadString(assetPath));

  static DialogueCatalog fromJson(String source) {
    final root = _object(jsonDecode(source), 'root');
    _keys(root, {'version', 'dialogues'}, 'root');
    if (root['version'] != 1 || root['dialogues'] is! List) {
      throw const FormatException('Invalid dialogue document version');
    }
    final entries = <DialogueEntry>[];
    final ids = <String>{};
    for (final row in root['dialogues'] as List) {
      final entry = DialogueEntry.parse(row);
      if (!ids.add(entry.id)) throw FormatException('Duplicate dialogue id: ${entry.id}');
      entries.add(entry);
    }
    final introductions = <String>{};
    for (final entry in entries.where((entry) => entry.firstGreeting)) {
      if (!introductions.add(entry.residentId)) {
        throw FormatException('Duplicate first greeting for: ${entry.residentId}');
      }
    }
    // Dialogue IDs are global, regardless of who speaks them.
    for (final entry in entries) {
      for (final condition in entry.conditions) {
        if (condition.fields['type'] == 'seenDialogue') {
          final prerequisite = condition.fields['dialogueId'] as String;
          if (!ids.contains(prerequisite) || prerequisite == entry.id) {
            throw FormatException(
              'Invalid prerequisite dialogue for ${entry.id}: $prerequisite');
          }
        }
      }
    }
    for (final resident in TownResident.values) {
      if (!entries.any((e) => e.residentId == resident.id &&
          e.conditions.isEmpty && !e.once)) {
        throw FormatException('Missing unconditional dialogue: ${resident.id}');
      }
    }
    return DialogueCatalog._(List.unmodifiable(entries));
  }

  DialogueEntry select({
    required TownResident resident,
    required Progress progress,
    required DateTime now,
    Set<String> townResidentIds = const {},
    String site = 'roster',
    math.Random? random,
  }) {
    if (!dialogueSites.contains(site)) {
      throw ArgumentError.value(site, 'site', 'Unknown dialogue site');
    }
    // -1000 is reserved for explicit facility conversations, never a random draw.
    final available = entries.where((entry) =>
      entry.residentId == resident.id &&
      entry.priority != -1000 &&
      (!entry.once || !progress.seenDialogues.contains(entry.id)) &&
      entry.matches(progress, now, townResidentIds, site)).toList();
    if (available.isEmpty) throw StateError('No dialogue: ${resident.id}');

    // A first greeting outranks achievements, stories and weighted chatter.
    final greetings = available.where((entry) => entry.firstGreeting).toList();
    if (greetings.isNotEmpty) return greetings.single;

    final generator = random ?? math.Random();
    // Keep first-time stories and achievements ahead of repeatable chatter,
    // and preserve the author's priority order for these one-time events.
    final firstTime = available.where((entry) => entry.once).toList();
    if (firstTime.isNotEmpty) {
      final highest = firstTime.map((entry) => entry.priority).reduce(math.max);
      final top = firstTime.where((entry) => entry.priority == highest).toList();
      return top[generator.nextInt(top.length)];
    }

    // Initial greetings and one-time stories take precedence; then prefer local chatter.
    final local = available.where((entry) => entry.conditions.any(
        (condition) => condition.fields['type'] == 'site')).toList();
    final repeatable = local.isNotEmpty ? local : available;
    // Every eligible repeatable line retains a nonzero chance to be selected.
    // Priority adds one ticket per ten points; consecutive repeats are allowed.
    final weights = [
      for (final entry in repeatable)
        1 + (math.max(0, entry.priority) ~/ 10),
    ];
    final total = weights.fold<int>(0, (sum, weight) => sum + weight);
    var ticket = generator.nextInt(total);
    for (var i = 0; i < repeatable.length; i++) {
      if (ticket < weights[i]) return repeatable[i];
      ticket -= weights[i];
    }
    throw StateError('Dialogue draw exceeded total weight: ${resident.id}');
  }

  /// Explicit conversation target (e.g. a facility counter), independent of
  /// the probability-based strolling dialogue selector.
  /// A missing, mismatched, or ineligible entry is an error, not a fallback.
  DialogueEntry selectById({
    required String id,
    required TownResident resident,
    required Progress progress,
    required DateTime now,
    Set<String> townResidentIds = const {},
    String site = 'roster',
  }) {
    if (!dialogueSites.contains(site)) {
      throw ArgumentError.value(site, 'site', 'Unknown dialogue site');
    }
    final found = entries.where((entry) => entry.id == id).toList();
    if (found.length != 1) {
      throw StateError('Expected one dialogue for $id, found ${found.length}');
    }
    final line = found.single;
    if (line.residentId != resident.id ||
        (line.once && progress.seenDialogues.contains(line.id)) ||
        !line.matches(progress, now, townResidentIds, site)) {
      throw StateError('Dialogue $id is not available for ${resident.id}');
    }
    return line;
  }
}

class DialogueEntry {
  DialogueEntry._(this.id, this.residentId, this.text, this.priority,
      this.once, this.logic, this.conditions, this.reply, this.firstGreeting);
  final String id;
  final String residentId;
  final String text;
  final int priority;
  final bool once;
  final String logic;
  final List<DialogueCondition> conditions;
  final DialogueReply? reply;
  final bool firstGreeting;

  factory DialogueEntry.parse(Object? source) {
    final data = _object(source, 'dialogue');
    _keys(data, {'id', 'residentId', 'text', 'priority', 'once', 'logic',
      'conditions'}, 'dialogue', optional: {'reply', 'firstGreeting'});
    final id = data['id'];
    final resident = data['residentId'];
    final message = data['text'];
    final priority = data['priority'];
    final once = data['once'];
    final logic = data['logic'];
    final conditions = data['conditions'];
    final greeting = data['firstGreeting'] ?? false;
    if (id is! String || !RegExp(r'^[A-Za-z0-9_-]{1,80}$').hasMatch(id) ||
        resident is! String ||
        !TownResident.values.any((r) => r.id == resident) ||
        message is! String || message.trim().isEmpty || message.length > 500 ||
        priority is! int || priority < -1000 || priority > 1000 ||
        once is! bool || greeting is! bool || !{'all', 'any'}.contains(logic) ||
        conditions is! List || conditions.length > 8) {
      throw const FormatException('Invalid dialogue entry');
    }
    if (greeting && (!once || priority == -1000 || conditions.isNotEmpty ||
        data.containsKey('reply'))) {
      throw FormatException('First greeting must be unconditional, once-only and without a reply: $id');
    }
    final parsedConditions = List<DialogueCondition>.unmodifiable(
      conditions.map(DialogueCondition.parse));
    if (logic != 'all' && parsedConditions.any(
        (condition) => condition.fields['type'] == 'site')) {
      throw FormatException('Location-specific dialogue requires AND conditions: $id');
    }
    for (final condition in parsedConditions) {
      if (condition.fields['type'] == 'townTogether' &&
          condition.fields['otherResidentId'] == resident) {
        throw FormatException('Town companion cannot be the speaker: $id');
      }
    }
    DialogueReply? reply;
    if (data.containsKey('reply')) {
      reply = DialogueReply.parse(data['reply']);
      if (reply.residentId == resident ||
          logic != 'all' ||
          !parsedConditions.any((condition) =>
              condition.fields['type'] == 'townTogether' &&
              condition.fields['otherResidentId'] == reply!.residentId)) {
        throw FormatException('Dialogue reply needs a matching AND town companion: $id');
      }
    }
    return DialogueEntry._(id, resident, message, priority, once, logic,
      parsedConditions, reply, greeting);
  }

  bool matches(Progress progress, DateTime now, Set<String> townResidentIds,
      [String site = 'roster']) {
    if (conditions.isEmpty) return true;
    return logic == 'all'
        ? conditions.every((c) => c.matches(
            progress, now, townResidentIds, residentId, site))
        : conditions.any((c) => c.matches(
            progress, now, townResidentIds, residentId, site));
  }
}

class DialogueReply {
  DialogueReply._(this.residentId, this.text);
  final String residentId;
  final String text;

  factory DialogueReply.parse(Object? source) {
    final data = _object(source, 'dialogue reply');
    _keys(data, {'residentId', 'text'}, 'dialogue reply');
    final speaker = data['residentId'];
    final message = data['text'];
    if (speaker is! String ||
        !TownResident.values.any((r) => r.id == speaker) ||
        message is! String || message.trim().isEmpty || message.length > 500) {
      throw const FormatException('Invalid dialogue reply');
    }
    return DialogueReply._(speaker, message);
  }
}

class DialogueCondition {
  DialogueCondition._(this.fields);
  final Map<String, dynamic> fields;

  factory DialogueCondition.parse(Object? source) {
    final data = _object(source, 'condition');
    if (data['type'] == 'mission') {
      _keys(data, {'type', 'missionId', 'minCount'}, 'mission condition',
          optional: {'withinDays'});
      final id = data['missionId'];
      final threshold = data['minCount'];
      if (id is! String || (id != 'all' &&
          !Mission.values.any((m) => m.name == id)) ||
          threshold is! int || threshold < 1 || threshold > 1000000 ||
          (data.containsKey('withinDays') && data['withinDays'] != 1)) {
        throw const FormatException('Invalid mission condition');
      }
    } else if (data['type'] == 'site') {
      _keys(data, {'type', 'siteId'}, 'conversation site');
      if (data['siteId'] is! String || !dialogueSites.contains(data['siteId'])) {
        throw const FormatException('Invalid conversation site');
      }
    } else if (data['type'] == 'seenDialogue') {
      _keys(data, {'type', 'dialogueId'}, 'seen dialogue condition');
      final prerequisite = data['dialogueId'];
      if (prerequisite is! String ||
          !RegExp(r'^[A-Za-z0-9_-]{1,80}$').hasMatch(prerequisite)) {
        throw const FormatException('Invalid prerequisite dialogue ID');
      }
    } else if (data['type'] == 'oyasumiClub') {
      _keys(data, {'type', 'completed'}, 'oyasumi club progress');
      if (data['completed'] is! bool) {
        throw const FormatException('Invalid oyasumi club completion condition');
      }
    } else if (data['type'] == 'residentOwned') {
      _keys(data, {'type', 'residentId', 'owned'}, 'resident ownership');
      final resident = data['residentId'];
      if (resident is! String ||
          !TownResident.values.any((item) => item.id == resident) ||
          data['owned'] is! bool) {
        throw const FormatException('Invalid resident ownership condition');
      }
    } else if (data['type'] == 'townTogether') {
      _keys(data, {'type', 'otherResidentId'}, 'town companion');
      final companion = data['otherResidentId'];
      if (companion is! String ||
          !TownResident.values.any((resident) => resident.id == companion)) {
        throw const FormatException('Invalid town companion');
      }
    } else if (data['type'] == 'kotohogi') {
      _keys(data, {'type', 'min'}, 'kotohogi condition');
      final minimum = data['min'];
      if (minimum is! int || minimum < 0 || minimum > 10000000) {
        throw const FormatException('Invalid kotohogi condition');
      }
    } else if (data['type'] == 'date') {
      final mode = data['mode'];
      if (mode == 'exact') {
        _keys(data, {'type', 'mode', 'date'}, 'exact date');
        _fullDay(data['date']);
      } else if (mode == 'range') {
        _keys(data, {'type', 'mode', 'start', 'end'}, 'date range');
        final start = _fullDay(data['start']);
        final end = _fullDay(data['end']);
        if (start.compareTo(end) > 0) throw const FormatException('Reversed date range');
      } else if (mode == 'annual') {
        _keys(data, {'type', 'mode', 'date'}, 'annual date');
        _monthDay(data['date']);
      } else if (mode == 'annual_range') {
        _keys(data, {'type', 'mode', 'start', 'end'}, 'annual range');
        _monthDay(data['start']);
        _monthDay(data['end']);
      } else if (mode == 'weekday') {
        _keys(data, {'type', 'mode', 'days'}, 'weekday');
        final days = data['days'];
        if (days is! List || days.isEmpty ||
            days.any((d) => d is! int || d < 1 || d > 7) ||
            days.toSet().length != days.length) {
          throw const FormatException('Invalid weekday condition');
        }
      } else {
        throw const FormatException('Unknown date mode');
      }
    } else {
      throw const FormatException('Unknown condition type');
    }
    return DialogueCondition._(Map.unmodifiable(data));
  }

  bool matches(Progress progress, DateTime now,
      Set<String> townResidentIds, String speakerId, String site) {
    final kind = fields['type'];
    if (kind == 'site') return site == fields['siteId'];
    if (kind == 'seenDialogue') {
      return progress.seenDialogues.contains(fields['dialogueId']);
    }
    if (kind == 'oyasumiClub') {
      // The third completed introduction is the existing, saved story ending.
      // No breakup scene, new save flag or forced follow-up is needed.
      return (progress.oyasumi.completed == 3) == fields['completed'];
    }
    if (kind == 'residentOwned') {
      final owned = (progress.residents.counts[fields['residentId']] ?? 0) > 0;
      return owned == fields['owned'];
    }
    if (kind == 'townTogether') {
      return townResidentIds.contains(speakerId) &&
          townResidentIds.contains(fields['otherResidentId']);
    }
    if (kind == 'mission') {
      final missionId = fields['missionId'] as String;
      if (progress.countFor(missionId) < (fields['minCount'] as int)) {
        return false;
      }
      if (!fields.containsKey('withinDays')) return true;
      // A celebration is valid only on the Japanese calendar day it happened.
      // Cumulative counters alone cannot prove today's completion.
      final jst = now.toUtc().add(const Duration(hours: 9));
      final day = '${jst.year.toString().padLeft(4, '0')}-'
          '${jst.month.toString().padLeft(2, '0')}-'
          '${jst.day.toString().padLeft(2, '0')}';
      final completedToday = progress.history[day];
      if (completedToday == null) return false;
      return missionId == 'all'
          ? completedToday.isNotEmpty
          : completedToday.any((mission) => mission.name == missionId);
    }
    if (kind == 'kotohogi') return progress.points >= fields['min'];
    // Convert absolute instant to Japan Standard Time (+09:00).
    final jst = now.toUtc().add(const Duration(hours: 9));
    final year = jst.year.toString().padLeft(4, '0');
    final month = jst.month.toString().padLeft(2, '0');
    final date = jst.day.toString().padLeft(2, '0');
    final day = '$year-$month-$date';
    final md = day.substring(5);
    switch (fields['mode']) {
      case 'exact':
        return day == fields['date'];
      case 'range':
        return day.compareTo(fields['start'] as String) >= 0 &&
            day.compareTo(fields['end'] as String) <= 0;
      case 'annual':
        return md == fields['date'];
      case 'annual_range':
        final start = fields['start'] as String;
        final end = fields['end'] as String;
        return start.compareTo(end) <= 0
            ? md.compareTo(start) >= 0 && md.compareTo(end) <= 0
            : md.compareTo(start) >= 0 || md.compareTo(end) <= 0;
      case 'weekday':
        final weekday = DateTime.utc(jst.year, jst.month, jst.day).weekday;
        return (fields['days'] as List).contains(weekday);
    }
    throw StateError('Unvalidated date condition');
  }
}

Map<String, dynamic> _object(Object? value, String field) {
  if (value is! Map<String, dynamic>) throw FormatException('Expected object: $field');
  return value;
}
void _keys(Map<String, dynamic> data, Set<String> expected, String field,
    {Set<String> optional = const {}}) {
  if (data.keys.toSet().difference({...expected, ...optional}).isNotEmpty ||
      expected.difference(data.keys.toSet()).isNotEmpty) {
    throw FormatException('Invalid fields: $field');
  }
}
String _fullDay(Object? value) {
  if (value is! String ||
      !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    throw const FormatException('Invalid exact date');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw const FormatException('Invalid calendar date');
  final year = parsed.year.toString().padLeft(4, '0');
  final month = parsed.month.toString().padLeft(2, '0');
  final day = parsed.day.toString().padLeft(2, '0');
  if ('$year-$month-$day' != value) {
    throw const FormatException('Invalid calendar date');
  }
  return value;
}
String _monthDay(Object? value) {
  if (value is! String || !RegExp(r'^\d{2}-\d{2}$').hasMatch(value)) {
    throw const FormatException('Invalid annual date');
  }
  _fullDay('2000-$value');
  return value;
}
