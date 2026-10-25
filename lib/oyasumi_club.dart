import 'resident_collection.dart';
import 'town_areas.dart';
import 'town_walk.dart';
import 'timed_events.dart';
import 'oyasumi_config.g.dart';

// Three mission completions (10 kotohogi each) advance one story day.
// This is lifetime earned kotohogi, not the spendable gacha balance.
const int kotohogiPerStoryDay = 30;

/// One selectable event conversation may contain multiple speaking residents.
/// The CMS stores a plain string for a single voice, or a list of speaker turns.
class OyasumiDialogueTurn {
  const OyasumiDialogueTurn(this.resident, this.text);
  final TownResident resident;
  final String text;
}

class OyasumiDialogue {
  const OyasumiDialogue(this.id, this.turns);
  final String id;
  final List<OyasumiDialogueTurn> turns;
  String get text => turns.first.text;
}

/// Only completed story beats are saved. The visible stage is derived.
class OyasumiProgress {
  const OyasumiProgress({
    this.completed = 0,
    this.lastNight,
    this.lastKotohogi,
  });
  final int completed;
  // Kept for saved-game compatibility and the date of the last conversation;
  // calendar days no longer unlock the next story beat.
  final String? lastNight;
  // Lifetime kotohogi when the last story introduction was read.
  // null in an older save, whose already-earned progress stays unlocked.
  final int? lastKotohogi;
  Map<String, dynamic> toJson() => {
    'completed': completed,
    'lastNight': lastNight,
    'lastKotohogi': lastKotohogi,
  };
  factory OyasumiProgress.fromJson(dynamic data) {
    if (data is! Map ||
        (data.length != 2 && data.length != 3) ||
        !data.containsKey("completed") ||
        !data.containsKey("lastNight") ||
        (data.length == 3 && !data.containsKey('lastKotohogi')) ||
        data['completed'] is! int ||
        data['completed'] < 0 ||
        data['completed'] > 3) {
      throw const FormatException('Invalid club progress');
    }
    final date = data['lastNight'];
    if ((data['completed'] == 0) != (date == null) ||
        (date != null &&
            (date is! String ||
                !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
                DateTime.tryParse(date)?.toIso8601String().substring(0, 10) !=
                    date))) {
      throw const FormatException('Invalid club night');
    }
    final atKotohogi = data['lastKotohogi'];
    if (atKotohogi != null &&
        (atKotohogi is! int || atKotohogi < 0 ||
            atKotohogi % 10 != 0 || data['completed'] == 0)) {
      throw const FormatException('Invalid club kotohogi milestone');
    }
    return OyasumiProgress(
      completed: data['completed'],
      lastNight: date,
      lastKotohogi: atKotohogi,
    );
  }
}

class OyasumiScene {
  OyasumiScene({
    required this.saved,
    required Iterable<TownResident> owned,
    required DateTime now,
    this.earnedKotohogi = 0,
    this.enabled = true,
    this.parkCleanerStarted = false,
    this.marcheOpen = false,
    Iterable<String> seenDialogues = const [],
  }) : owned = Set.of(owned),
       seenDialogues = Set.of(seenDialogues),
       now = now.toLocal();
  final OyasumiProgress saved;
  final Set<TownResident> owned;
  final Set<String> seenDialogues;
  final DateTime now;
  final int earnedKotohogi;
  final bool enabled;
  /// Set only when the park-cleaning job announcement was read in full.
  final bool parkCleanerStarted;
  /// Set from the actual tea-stall unlock, not from debug resident previews.
  final bool marcheOpen;
  static const parkCleanerUnlockId = 'frog_park_cleaner_started';
  static const host = TownResident.c027_daydreamer;
  static const frog = TownResident.c029_office_worker;
  static const nightPatroller = TownResident.c036_mosa;
  static const teaVisitor = TownResident.c041_pig_middle;
  static const teaVisitGroup = 'teaVisit';
  Map<String, dynamic> get teaVisitDefinition =>
      oyasumiConfig['teaVisit'] as Map<String, dynamic>;
  String get teaVisitLabel => teaVisitDefinition['label'] as String;
  Map<String, dynamic> get teaVisitExtraDialogue =>
      teaVisitDefinition['extraDialogue'] as Map<String, dynamic>;
  String teaVisitBadge(String dialogueId) =>
      dialogueId == teaVisitExtraDialogue['id']
          ? teaVisitExtraDialogue['label'] as String
          : teaVisitLabel;
  // The guest's visit count survives an app restart because it depends on
  // saved lifetime kotohogi, not on a transient local dialogue counter.
  int get teaVisitNumber {
    final days = saved.lastKotohogi == null
        ? earnedKotohogi ~/ kotohogiPerStoryDay
        : storyDaysSinceLastIntroduction;
    final interval = teaVisitDefinition['intervalNights'] as int;
    return days <= 0 ? 0 : (days - 1) ~/ interval;
  }
  int get startHour => oyasumiConfig['night']['startHour'] as int;
  int get endHour => oyasumiConfig['night']['endHour'] as int;
  EventTimeWindow get schedule => EventTimeWindow.fromHours(startHour, endHour);
  bool get night => schedule.includes(now);
  String get nightKey {
    final date = schedule.occurrenceDay(now);
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  bool get active => enabled && night && owned.contains(host);
  // Finished story progress stays true even when the developer tools
  // suppress live night events. Previewing residents must not resurrect
  // the frog's old office-worker conversations.
  bool get frogResting =>
      saved.completed == 3 && owned.contains(frog);
  // A night passing by itself never advances the story. A completed
  // introduction starts a fresh 30-kotohogi interval. Old saves without a
  // recorded milestone keep the next chapter accessible (no progress loss).
  int get storyDaysSinceLastIntroduction {
    final at = saved.lastKotohogi;
    if (at == null) return 0;
    final earned = earnedKotohogi - at;
    return earned <= 0 ? 0 : earned ~/ kotohogiPerStoryDay;
  }
  bool get nextStoryDayReached =>
      saved.lastKotohogi == null || storyDaysSinceLastIntroduction >= 1;
  int get step {
    if (!owned.contains(frog)) return 1;
    if (saved.completed == 3) return 4;
    if (saved.completed == 2) return nextStoryDayReached ? 3 : 2;
    if (saved.completed == 1) return nextStoryDayReached ? 2 : 1;
    return 1;
  }

  String get stage => ['solo', 'watching', 'joining', 'joined'][step - 1];

  // One-time chapter, unlocked by earned lifetime kotohogi since joining.
  // Older saves without a joining milestone use their lifetime total,
  // never a calendar-day estimate.
  Map<String, dynamic> get parkCleanerDefinition =>
      oyasumiConfig['stages']['joined']['parkCleanerConversation'] as Map<String, dynamic>;
  Map<String, dynamic> get wishDefinition =>
      oyasumiConfig['stages']['joined']['specialConversation'] as Map<String, dynamic>;
  String get wishDialogueId => wishDefinition['id'] as String;
  Map<String, dynamic> get rumorDefinition =>
      oyasumiConfig['stages']['joined']['rumorConversation'] as Map<String, dynamic>;
  String get rumorDialogueId => rumorDefinition['id'] as String;

  int get earnedSinceJoining {
    final milestone = saved.lastKotohogi;
    final difference = milestone == null
        ? earnedKotohogi : earnedKotohogi - milestone;
    return difference < 0 ? 0 : difference;
  }
  bool get parkCleanerDialogueAvailable =>
      active && saved.completed == 3 && owned.contains(frog) &&
      earnedSinceJoining >=
          (parkCleanerDefinition['unlockAfterKotohogi'] as int) &&
      !parkCleanerStarted &&
      !seenDialogues.contains(parkCleanerUnlockId);

  bool get rumorDialogueAvailable =>
      active && saved.completed == 3 && owned.contains(frog) &&
      earnedSinceJoining >= (rumorDefinition['unlockAfterKotohogi'] as int) &&
      !seenDialogues.contains(rumorDialogueId);

  bool get wishDialogueAvailable =>
      active && saved.completed == 3 && owned.contains(frog) &&
      earnedSinceJoining >= (wishDefinition['unlockAfterKotohogi'] as int) &&
      !seenDialogues.contains(wishDialogueId);

  Map<String, dynamic> get definition =>
      oyasumiConfig['stages'][stage] as Map<String, dynamic>;
  List<TownResident> get cast =>
      !active ? [] : [host, if (step > 1 && owned.contains(frog)) frog];

  // A passing night watchman is never part of the club story or its progress.
  bool get nightPatrolVisible => active && owned.contains(nightPatroller);
  /// The first delivery follows another 30 lifetime kotohogi earned after
  /// joining. Repeats every N *story* days; no calendar-night requirement.
  /// Tonko remains a guest, not a club member or saved story stage.
  bool get teaVisitorVisible {
    if (!active || step != 4 || saved.completed != 3 ||
        !owned.contains(frog) || !owned.contains(teaVisitor) ||
        !marcheOpen) {
      return false;
    }
    // Older saves did not record a kotohogi milestone. Use the lifetime
    // total as their origin rather than falling back to the calendar.
    final elapsed = saved.lastKotohogi == null
        ? earnedKotohogi ~/ kotohogiPerStoryDay
        : storyDaysSinceLastIntroduction;
    final interval = teaVisitDefinition['intervalNights'] as int;
    return elapsed >= 1 && (elapsed - 1) % interval == 0;
  }

  List<TownResident> get passersby => [
        if (nightPatrolVisible) nightPatroller,
        if (teaVisitorVisible) teaVisitor,
      ];

  /// During the event, the night plaza hosts the scripted cast and one
  /// optional passerby. Other neighborhoods continue their ordinary routines.
  bool takesOver(TownArea area) => active && area == TownArea.plaza;

  String? background(TownArea area) => takesOver(area)
      ? oyasumiConfig['background'] as String
      : null;

  List<TownResident> residents(
    TownArea area,
    Iterable<TownResident> ordinary,
  ) {
    if (!active) return ordinary.toList();
    if (takesOver(area)) return [...cast, ...passersby];
    // A visiting resident cannot also walk in another neighborhood.
    return ordinary.where((r) => r != host && r != frog &&
        !(nightPatrolVisible && r == nightPatroller) &&
        !(teaVisitorVisible && r == teaVisitor)).toList();
  }
  TownWalkRoute? route(TownArea area, TownResident resident) {
    if (takesOver(area) && teaVisitorVisible && resident == teaVisitor) {
      final point = teaVisitDefinition['position'] as List;
      return TownWalkRoute(
        (point[0] as num).toDouble(),
        (point[1] as num).toDouble(),
        stay: true,
      );
    }
    if (takesOver(area) && nightPatrolVisible && resident == nightPatroller) {
      final values = oyasumiConfig['nightPatrol']['route'] as Map;
      return TownWalkRoute(
        (values['x'] as num).toDouble(), (values['y'] as num).toDouble(),
        width: (values['width'] as num).toDouble(),
        height: (values['height'] as num).toDouble(),
      );
    }
    if (frogResting && !active && resident == frog) {
      return const TownWalkRoute(.58, .64, stay: true);
    }
    if (!active || area != TownArea.plaza || !cast.contains(resident)) {
      return null;
    }
    final point = definition['positions'][resident.id] as List;
    return TownWalkRoute(
      (point[0] as num).toDouble(),
      (point[1] as num).toDouble(),
      stay: true,
    );
  }

  String? group(TownResident resident, {required bool inPlaza}) {
    if (inPlaza && teaVisitorVisible && resident == teaVisitor) {
      return teaVisitGroup;
    }
    if (active && inPlaza && nightPatrolVisible && resident == nightPatroller) {
      return 'patrol';
    }
    if (active && inPlaza && cast.contains(resident)) return stage;
    if (frogResting && resident == frog) return 'resting';
    return null;
  }

  bool introduction(TownResident resident, String group) =>
      group == stage &&
      active &&
      step <= 3 &&
      saved.completed < step &&
      definition['intro']['speaker'] == resident.id;
  List<OyasumiDialogueTurn> _dialogueTurns(dynamic item, TownResident speaker) {
    if (item is String) return [OyasumiDialogueTurn(speaker, item)];
    if (item is! Map || item['turns'] is! List) {
      throw StateError('Invalid oyasumi event dialogue');
    }
    return [
      for (final dynamic part in item['turns'] as List)
        OyasumiDialogueTurn(
          TownResident.fromId(part['speaker'] as String),
          part['text'] as String,
        ),
    ];
  }

  /// Partners in a post-club daytime exchange must actually be present in
  /// the conversation site. If absent, fall back to solo dialogue variants.
  OyasumiDialogue dialogue(
    TownResident resident,
    String group,
    int rotation, {
    Set<String>? availableResidentIds,
  }) {
    if (group == teaVisitGroup) {
      if (!teaVisitorVisible || resident != teaVisitor) {
        throw StateError('Tea visit is not available for ${resident.id}');
      }
      final foodFriends = (teaVisitNumber + rotation) % 2 == 1;
      final turns = foodFriends
          ? teaVisitExtraDialogue['turns'] as List
          : teaVisitDefinition['turns'] as List;
      return OyasumiDialogue(
        foodFriends
            ? teaVisitExtraDialogue['id'] as String
            : 'oyasumi_tea_visit_${resident.id}',
        [
          for (final turn in turns)
            OyasumiDialogueTurn(
              TownResident.fromId(turn['speaker'] as String),
              turn['text'] as String,
            ),
        ],
      );
    }
    // A backlog plays in story order, even if enough kotohogi were earned
    // to unlock several scenes before visiting the club.
    if (group == 'joined' && resident == frog &&
        parkCleanerDialogueAvailable) {
      return OyasumiDialogue(
        parkCleanerUnlockId,
        [
          for (final turn in parkCleanerDefinition['turns'] as List)
            OyasumiDialogueTurn(
              TownResident.fromId(turn['speaker'] as String),
              turn['text'] as String,
            ),
        ],
      );
    }
    if (group == 'joined' && resident == frog && rumorDialogueAvailable) {
      return OyasumiDialogue(
        rumorDialogueId,
        [
          for (final turn in rumorDefinition['turns'] as List)
            OyasumiDialogueTurn(
              TownResident.fromId(turn['speaker'] as String),
              turn['text'] as String,
            ),
        ],
      );
    }
    if (group == 'joined' && resident == frog && wishDialogueAvailable) {
      return OyasumiDialogue(
        wishDialogueId,
        [
          for (final turn in wishDefinition['turns'] as List)
            OyasumiDialogueTurn(
              TownResident.fromId(turn['speaker'] as String),
              turn['text'] as String,
            ),
        ],
      );
    }
    final intro = introduction(resident, group);
    if (intro) {
      final text = definition['intro']['text'] as String;
      return OyasumiDialogue(
        'oyasumi_${group}_${resident.id}_intro',
        [OyasumiDialogueTurn(resident, text)],
      );
    }
    final options = group == 'resting'
        ? oyasumiConfig['restingDialogue'] as List
        : group == 'patrol' && nightPatrolVisible && resident == nightPatroller
            ? oyasumiConfig['nightPatrol']['dialogues'] as List
            : definition['chatter'][resident.id] as List;
    final peers = group == 'resting'
        ? (availableResidentIds ?? {resident.id})
        : group == 'patrol'
            ? {nightPatroller.id} // Solo lines, never club back-and-forth.
            : cast.map((character) => character.id).toSet();
    final eligible = [
      for (final item in options)
        if ((item is! Map ||
                item['requires'] == null ||
                (item['requires'] == 'parkCleaner' && parkCleanerStarted)) &&
            _dialogueTurns(item, resident).every(
              (turn) => peers.contains(turn.resident.id),
            ))
          item,
    ];
    if (eligible.isEmpty) {
      throw StateError('No eligible oyasumi conversation: $group / ${resident.id}');
    }
    final slot = rotation % eligible.length;
    return OyasumiDialogue(
      'oyasumi_${group}_${resident.id}_$slot',
      _dialogueTurns(eligible[slot], resident),
    );
  }

  OyasumiProgress completeIntroduction(TownResident resident, String group) {
    if (!introduction(resident, group)) return saved;
    return OyasumiProgress(
      completed: step,
      lastNight: nightKey,
      lastKotohogi: earnedKotohogi,
    );
  }
}
