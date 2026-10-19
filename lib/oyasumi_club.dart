import 'resident_collection.dart';
import 'dialogue_engine.dart';
import 'town_areas.dart';
import 'town_walk.dart';
import 'oyasumi_config.g.dart';

/// Only completed story beats are saved. The visible stage is derived.
class OyasumiProgress {
  const OyasumiProgress({this.completed = 0, this.lastNight});
  final int completed;
  final String? lastNight;
  Map<String, dynamic> toJson() => {
    'completed': completed,
    'lastNight': lastNight,
  };
  factory OyasumiProgress.fromJson(dynamic data) {
    if (data is! Map ||
        data.length != 2 ||
        !data.containsKey("completed") ||
        !data.containsKey("lastNight") ||
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
    return OyasumiProgress(completed: data['completed'], lastNight: date);
  }
}

class OyasumiScene {
  OyasumiScene({
    required this.saved,
    required Iterable<TownResident> owned,
    required DateTime now,
    this.enabled = true,
  }) : owned = Set.of(owned),
       now = now.toLocal();
  final OyasumiProgress saved;
  final Set<TownResident> owned;
  final DateTime now;
  final bool enabled;
  static const host = TownResident.c027_daydreamer;
  static const frog = TownResident.c029_office_worker;
  int get startHour => oyasumiConfig['night']['startHour'] as int;
  int get endHour => oyasumiConfig['night']['endHour'] as int;
  bool get night => now.hour >= startHour || now.hour < endHour;
  String get nightKey {
    final date = DateTime(
      now.year,
      now.month,
      now.day - (now.hour < endHour ? 1 : 0),
    );
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  bool get active => enabled && night && owned.contains(host);
  bool get frogResting =>
      enabled && saved.completed == 3 && owned.contains(frog);
  bool get laterNight =>
      saved.lastNight == null || nightKey.compareTo(saved.lastNight!) > 0;
  int get step {
    if (!owned.contains(frog)) return 1;
    if (saved.completed == 3) return 4;
    if (saved.completed == 2) return laterNight ? 3 : 2;
    if (saved.completed == 1) return laterNight ? 2 : 1;
    return 1;
  }

  String get stage => ['solo', 'watching', 'joining', 'joined'][step - 1];
  Map<String, dynamic> get definition =>
      oyasumiConfig['stages'][stage] as Map<String, dynamic>;
  List<TownResident> get cast =>
      !active ? [] : [host, if (step > 1 && owned.contains(frog)) frog];
  String? background(TownArea area) => active && area == TownArea.plaza
      ? oyasumiConfig['background'] as String
      : null;
  List<TownResident> residents(
    TownArea area,
    Iterable<TownResident> ordinary,
  ) => !active
      ? ordinary.toList()
      : [
          ...ordinary.where((r) => r != host && r != frog),
          if (area == TownArea.plaza) ...cast,
        ];
  TownWalkRoute? route(TownArea area, TownResident resident) {
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
  DialogueEntry dialogue(TownResident resident, String group, int rotation) {
    final intro = introduction(resident, group);
    final lines = group == 'resting'
        ? oyasumiConfig['restingDialogue'] as List
        : definition['chatter'][resident.id] as List;
    final text = intro
        ? definition['intro']['text']
        : lines[rotation % lines.length];
    return DialogueEntry.parse({
      'id':
          'oyasumi_${group}_${resident.id}_${intro ? 'intro' : rotation % lines.length}',
      'residentId': resident.id,
      'text': text,
      'priority': -1000,
      'once': false,
      'logic': 'all',
      'conditions': <dynamic>[],
    });
  }

  OyasumiProgress completeIntroduction(TownResident resident, String group) {
    if (!introduction(resident, group) || !laterNight) return saved;
    return OyasumiProgress(completed: step, lastNight: nightKey);
  }
}
