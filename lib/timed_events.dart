import 'resident_collection.dart';
import 'timed_events_config.g.dart';
import 'town_areas.dart';
import 'town_walk.dart';

/// Local half-open time interval; overnight weekday belongs to its starting day.
class EventTimeWindow {
  EventTimeWindow({required this.startMinute, required this.endMinute,
    required Iterable<int> weekdays}) : weekdays = Set.unmodifiable(weekdays) {
    if (startMinute < 0 || startMinute >= 1440 || endMinute < 0 ||
        endMinute >= 1440 || startMinute == endMinute ||
        this.weekdays.any((v) => v < 1 || v > 7)) {
      throw const FormatException('Invalid event time window');
    }
  }
  factory EventTimeWindow.fromHours(int start, int end) =>
      EventTimeWindow(startMinute: start * 60, endMinute: end * 60, weekdays: const []);
  factory EventTimeWindow.fromJson(Map<String, dynamic> data) {
    if (data.keys.toSet().difference({'start', 'end', 'weekdays'}).isNotEmpty ||
        data.length != 3) {
      throw const FormatException('Invalid event schedule');
    }
    return EventTimeWindow(startMinute: _clock(data['start']),
        endMinute: _clock(data['end']),
        weekdays: (data['weekdays'] as List).cast<int>());
  }
  final int startMinute;
  final int endMinute;
  final Set<int> weekdays;
  static int _clock(dynamic value) {
    if (value is! String ||
        !RegExp(r'^([01][0-9]|2[0-3]):[0-5][0-9]$').hasMatch(value)) {
      throw FormatException('Invalid HH:mm: $value');
    }
    return int.parse(value.substring(0, 2)) * 60 +
        int.parse(value.substring(3));
  }
  DateTime occurrenceDay(DateTime value) {
    final local = value.toLocal();
    final minute = local.hour * 60 + local.minute;
    return DateTime(local.year, local.month,
        local.day - (startMinute > endMinute && minute < endMinute ? 1 : 0));
  }
  bool includes(DateTime value) {
    final local = value.toLocal();
    final minute = local.hour * 60 + local.minute;
    final active = startMinute < endMinute
        ? minute >= startMinute && minute < endMinute
        : minute >= startMinute || minute < endMinute;
    return active && (weekdays.isEmpty ||
        weekdays.contains(occurrenceDay(local).weekday));
  }
}

class TimedEventParticipant {
  TimedEventParticipant.fromJson(dynamic source) {
    final data = source as Map<String, dynamic>;
    if ((data.length != 4 && data.length != 5) ||
        data.keys.toSet().difference({
          'residentId', 'x', 'y', 'stay', 'stepInPlace'}).isNotEmpty) {
      throw const FormatException('Invalid timed event participant');
    }
    resident = TownResident.fromId(data['residentId'] as String);
    x = (data['x'] as num).toDouble();
    y = (data['y'] as num).toDouble();
    stay = data['stay'] as bool;
    stepInPlace = data.containsKey('stepInPlace')
        ? data['stepInPlace'] as bool : false;
    if (stepInPlace && !stay) {
      throw FormatException('Stepping participant must stay: ${resident.id}');
    }
    if (!x.isFinite || !y.isFinite || x < 0 || x > .82 || y < 0 || y > .82) {
      throw FormatException('Invalid position for ${resident.id}');
    }
  }
  late final TownResident resident;
  late final double x;
  late final double y;
  late final bool stay;
  late final bool stepInPlace;
  TownWalkRoute get route => TownWalkRoute(x, y, stay: stay);
}

class TimedEventDefinition {
  TimedEventDefinition.fromJson(dynamic source) {
    final data = source as Map<String, dynamic>;
    if ((data.length != 7 && data.length != 8) ||
        data.keys.toSet().difference({
          'id', 'label', 'areaId', 'schedule', 'mode', 'requiresOwned',
          'residents', 'hostResidentId',
        }).isNotEmpty) {
      throw const FormatException('Invalid timed event definition');
    }
    id = data['id'] as String;
    label = data['label'] as String;
    if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(id) ||
        label.trim().isEmpty) {
      throw FormatException('Invalid event ID/label: $id');
    }
    area = TownArea.fromId(data['areaId'] as String);
    schedule = EventTimeWindow.fromJson(data['schedule'] as Map<String, dynamic>);
    mode = data['mode'] as String;
    if (!const {'replace', 'add', 'exclude'}.contains(mode)) {
      throw FormatException('Unknown timed event mode: $mode');
    }
    requiresOwned = data['requiresOwned'] as bool;
    participants = List.unmodifiable(
        (data['residents'] as List).map(TimedEventParticipant.fromJson));
    if (participants.isEmpty ||
        participants.map((p) => p.resident).toSet().length != participants.length) {
      throw FormatException('Missing or duplicate event participants: $id');
    }
    hostResident = data.containsKey('hostResidentId')
        ? TownResident.fromId(data['hostResidentId'] as String) : null;
    if (hostResident != null &&
        (mode == 'exclude' ||
            !participants.any((p) => p.resident == hostResident))) {
      throw FormatException('Invalid event host: $id');
    }
  }
  late final String id;
  late final String label;
  late final TownArea area;
  late final EventTimeWindow schedule;
  late final String mode;
  late final bool requiresOwned;
  late final List<TimedEventParticipant> participants;
  late final TownResident? hostResident;
  List<TownResident> get cast => [for (final p in participants) p.resident];
}

/// CMS-configured timed overlays. Scripted stories retain independent progress.
class TownTimedEvents {
  TownTimedEvents({required DateTime now, required Iterable<TownResident> owned,
      this.enabled = true, Map<String, dynamic>? config})
      : now = now.toLocal(), owned = Set.unmodifiable(owned),
        definitions = _parse(config ?? timedEventsConfig);
  final DateTime now;
  final Set<TownResident> owned;
  final bool enabled;
  final List<TimedEventDefinition> definitions;

  static List<TimedEventDefinition> _parse(Map<String, dynamic> config) {
    if (config.length != 2 || config['version'] != 1 ||
        config['events'] is! List) {
      throw const FormatException('Invalid timed events catalog');
    }
    final result = (config['events'] as List)
        .map(TimedEventDefinition.fromJson).toList();
    if (result.map((e) => e.id).toSet().length != result.length) {
      throw const FormatException('Duplicate timed event ID');
    }
    return List.unmodifiable(result);
  }
  List<TimedEventDefinition> get _active => enabled
      ? definitions.where((event) => event.schedule.includes(now) &&
          (!event.requiresOwned || owned.containsAll(event.cast))).toList()
      : const [];
  TimedEventDefinition? eventFor(TownArea area) {
    final matches = _active.where((event) => event.area == area).toList();
    if (matches.length > 1) {
      throw StateError('Overlapping events in ${area.id}');
    }
    return matches.isEmpty ? null : matches.single;
  }
  bool takesOver(TownArea area) => eventFor(area)?.mode == 'replace';

  // A scheduled event can take over an area even when its host is unowned.
  // The host gates the optional participants, without granting ownership.
  List<TownResident> _ownedCast(TimedEventDefinition event) {
    if (event.hostResident != null && !owned.contains(event.hostResident)) {
      return const [];
    }
    return event.cast.where(owned.contains).toList(growable: false);
  }
  List<TownResident> residents(TownArea area, Iterable<TownResident> ordinary,
      {bool scriptedEventActive = false}) {
    final event = eventFor(area);
    if (scriptedEventActive && event != null) {
      throw StateError('Scripted event overlaps with timed event in ${area.id}');
    }
    final elsewhere = <TownResident>{
      for (final other in _active)
        if (other.area != area && other.mode != 'exclude') ..._ownedCast(other),
    };
    final normal = ordinary.where((resident) => !elsewhere.contains(resident)).toList();
    if (event == null) return List.unmodifiable(normal);
    if (event.mode == 'replace') return List.unmodifiable(_ownedCast(event));
    if (event.mode == 'exclude') {
      return List.unmodifiable(normal.where((r) => !event.cast.contains(r)));
    }
    return List.unmodifiable({...normal, ..._ownedCast(event)});
  }
  TownWalkRoute? route(TownArea area, TownResident resident) {
    final event = eventFor(area);
    if (event == null || event.mode == 'exclude' || !owned.contains(resident) ||
        (event.hostResident != null && !owned.contains(event.hostResident))) {
      return null;
    }
    for (final person in event.participants) {
      if (person.resident == resident) return person.route;
    }
    return null;
  }

  // During morning exercises, only these CMS lines may be selected.
  // Ordinary first greetings, missions and chatter resume after the event.
  static const morningExerciseDialogueIds = <TownResident, List<String>>{
    TownResident.c042_senior_dog: [
      '042_senior_dog_025', '042_senior_dog_026',
    ],
    TownResident.shiba: ['001_shiba_007', '001_shiba_008'],
    TownResident.c052_pome: ['052_pome_003', '052_pome_004'],
  };

  List<String>? exclusiveDialogueIds(TownArea area, TownResident resident) {
    final event = eventFor(area);
    if (event?.id != 'morning_exercises' ||
        !_ownedCast(event!).contains(resident)) {
      return null;
    }
    final ids = morningExerciseDialogueIds[resident];
    if (ids == null || ids.isEmpty) {
      throw StateError(
        'Missing exercise dialogue IDs for event ${event.id}, ${resident.id}',
      );
    }
    return ids;
  }

  bool stepsInPlace(TownArea area, TownResident resident) {
    final event = eventFor(area);
    if (event == null || event.mode == 'exclude' || !owned.contains(resident) ||
        (event.hostResident != null && !owned.contains(event.hostResident))) {
      return false;
    }
    return event.participants.any(
        (person) => person.resident == resident && person.stepInPlace);
  }
}
