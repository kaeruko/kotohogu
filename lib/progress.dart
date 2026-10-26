import 'oyasumi_club.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'dev_tools.dart';
import 'resident_collection.dart';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const defaultPlayerName = 'ハル';
const maxPlayerNameLength = 12;

bool isValidPlayerName(String name) =>
    name.isNotEmpty &&
    name == name.trim() &&
    name.runes.length <= maxPlayerNameLength &&
    !RegExp(r'[\x00-\x1F\x7F]').hasMatch(name);

enum MissionPeriod { daily, weekly, monthly }

enum Mission {
  // Keep existing identifiers stable for older saved progress.
  strength('筋力を使った', '自分のペースで、体を動かせたら。', MissionPeriod.daily),
  outside('外に出た・歩いた', '少しの外出も、今日の一歩。', MissionPeriod.daily),
  conversation('人と話した', 'ひと言のやりとりも、大切なつながり。', MissionPeriod.daily),
  movement('身体を動かした', '自分のペースで、今日身体を動かせたら。', MissionPeriod.daily),
  sittingBreak('座りっぱなしを途中でやめた', '長く座ったら、途中で立ち上がるだけでも。', MissionPeriod.daily),
  food('食事をひとつ整えた', '食事に野菜を足すなど、できる工夫を。', MissionPeriod.daily),
  hobby('趣味や学びを楽しんだ', '好きなことや好奇心を大切に。', MissionPeriod.daily),
  weeklyStrength('筋トレをした', '今週、無理のない筋力づくりに取り組んだ。', MissionPeriod.weekly),
  weeklyActive('息が弾む運動を楽しんだ', '体調に合わせて取り組めたら。', MissionPeriod.weekly),
  weeklyTogether('誰かと一緒に活動した', '外出や趣味など、どんな活動でも。', MissionPeriod.weekly),
  weeklyLearn('新しいことを学んだ・試した', '小さな挑戦も大切な一歩。', MissionPeriod.weekly),
  monthlyCommunity('地域の活動に参加した', '参加できたときだけ、言祝ぎましょう。', MissionPeriod.monthly),
  monthlyHabit('健康習慣をひとつ工夫した', '今の暮らしに合う工夫を見つけた。', MissionPeriod.monthly),
  monthlyReview('今月の言祝ぎを振り返った', 'できたことを、あたたかく振り返る。', MissionPeriod.monthly);

  const Mission(this.title, this.description, this.period);
  final String title;
  final String description;
  final MissionPeriod period;

  static List<Mission> forPeriod(MissionPeriod period) => [
    for (final mission in values)
      if (mission.period == period) mission,
  ];
}

String localDay(DateTime time) {
  final date = time.toLocal();
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

String weekStart(String day) {
  final date = DateTime.parse(day);
  return localDay(date.subtract(Duration(days: date.weekday - 1)));
}

String monthKey(String day) => day.substring(0, 7);

class Progress {
  Progress({
    required this.day,
    required this.lastCompletedDay,
    required this.points,
    this.playerName = defaultPlayerName,
    ResidentCollection? residents,
    required Set<Mission> completed,
    Map<String, Set<Mission>> history = const {},
    Set<Mission> weeklyCompleted = const {},
    Set<Mission> monthlyCompleted = const {},
    Map<MissionPeriod, String> debugResets = const {},
    Map<Mission, int>? missionCounts,
    Set<String> seenDialogues = const {},
    this.oyasumi = const OyasumiProgress(),
  }) : residents = residents ?? ResidentCollection.initial(points),
       completed = Set.unmodifiable(completed),
       history = Map.unmodifiable({
         for (final entry in history.entries)
           entry.key: Set<Mission>.unmodifiable(entry.value),
       }),
       weeklyCompleted = Set.unmodifiable(weeklyCompleted),
       monthlyCompleted = Set.unmodifiable(monthlyCompleted),
       debugResets = Map.unmodifiable(debugResets),
       missionCounts = Map.unmodifiable(missionCounts ?? {
         for (final mission in Mission.values)
           if (history.values.any((events) => events.contains(mission)))
             mission: history.values.where((events) => events.contains(mission)).length,
       }),
       seenDialogues = Set.unmodifiable(seenDialogues);

  factory Progress.empty(DateTime now) => Progress(
    day: localDay(now),
    lastCompletedDay: null,
    points: 0,
    completed: {},
  );

  final OyasumiProgress oyasumi;
  final String day;
  final String? lastCompletedDay;
  final int points;
  final String playerName;
  final ResidentCollection residents;
  final Set<Mission> completed;
  final Map<String, Set<Mission>> history;
  final Set<Mission> weeklyCompleted;
  final Set<Mission> monthlyCompleted;

  /// Period markers permit intentional debug resets without erasing past history.
  final Map<MissionPeriod, String> debugResets;
  /// Durable counters survive journal deletion. Legacy migration is a known lower bound.
  final Map<Mission, int> missionCounts;
  final Set<String> seenDialogues;
  int countFor(String missionId) {
    if (missionId == 'all') return points ~/ 10;
    final mission = Mission.values.singleWhere(
      (m) => m.name == missionId,
      orElse: () => throw ArgumentError.value(missionId, 'missionId'),
    );
    return missionCounts[mission] ?? 0;
  }

  Set<Mission> completedFor(MissionPeriod period) => switch (period) {
    MissionPeriod.daily => completed,
    MissionPeriod.weekly => weeklyCompleted,
    MissionPeriod.monthly => monthlyCompleted,
  };

  Progress onDay(DateTime now) {
    final today = localDay(now);
    if (today.compareTo(day) < 0) {
      throw StateError('Device date $today is earlier than saved date $day.');
    }
    if (today == day) return this;
    return Progress(
      playerName: playerName,
      day: today,
      lastCompletedDay: lastCompletedDay,
      points: points,
      residents: residents,
      completed: {},
      weeklyCompleted: weekStart(today) == weekStart(day)
          ? weeklyCompleted
          : {},
      monthlyCompleted: monthKey(today) == monthKey(day)
          ? monthlyCompleted
          : {},
      history: history,
      missionCounts: missionCounts,
      seenDialogues: seenDialogues,
      oyasumi: oyasumi,
      debugResets: {
        if (weekStart(today) == weekStart(day) &&
            debugResets.containsKey(MissionPeriod.weekly))
          MissionPeriod.weekly: debugResets[MissionPeriod.weekly]!,
        if (monthKey(today) == monthKey(day) &&
            debugResets.containsKey(MissionPeriod.monthly))
          MissionPeriod.monthly: debugResets[MissionPeriod.monthly]!,
      },
    );
  }

  Progress complete(Mission mission) {
    if (completedFor(mission.period).contains(mission)) return this;
    return Progress(
      playerName: playerName,
      day: day,
      lastCompletedDay: day,
      points: points + 10,
      residents: residents.withKotohogiCap(points + 10),
      completed: mission.period == MissionPeriod.daily
          ? {...completed, mission}
          : completed,
      weeklyCompleted: mission.period == MissionPeriod.weekly
          ? {...weeklyCompleted, mission}
          : weeklyCompleted,
      monthlyCompleted: mission.period == MissionPeriod.monthly
          ? {...monthlyCompleted, mission}
          : monthlyCompleted,
      history: {
        ...history,
        day: {...?history[day], mission},
      },
      missionCounts: {...missionCounts, mission: (missionCounts[mission] ?? 0) + 1},
      seenDialogues: seenDialogues,
      oyasumi: oyasumi,
      debugResets: debugResets,
    );
  }

  /// Restore all mission buttons without deleting points or the journal.
  /// Re-completing a mission in this debug state earns another 10 points.
  Progress resetMissionsForDebug() => Progress(
      playerName: playerName,
    day: day,
    lastCompletedDay: lastCompletedDay,
    points: points,
    residents: residents,
    completed: {},
    weeklyCompleted: {},
    monthlyCompleted: {},
    history: history,
    missionCounts: missionCounts,
    seenDialogues: seenDialogues,
    oyasumi: oyasumi,
    debugResets: {
      MissionPeriod.daily: day,
      MissionPeriod.weekly: weekStart(day),
      MissionPeriod.monthly: monthKey(day),
    },
  );

  /// Remove the journal only; keep points and current-period completion flags.
  Progress clearHistory() => Progress(
      playerName: playerName,
    day: day,
    lastCompletedDay: lastCompletedDay,
    points: points,
    residents: residents,
    completed: completed,
    weeklyCompleted: weeklyCompleted,
    monthlyCompleted: monthlyCompleted,
    missionCounts: missionCounts,
    seenDialogues: seenDialogues,
    oyasumi: oyasumi,
    debugResets: debugResets,
  );

  /// Add test-only gacha tickets without changing contributions or history.
  Progress grantTicketsForDebug(int amount) => Progress(
      playerName: playerName,
    day: day,
    lastCompletedDay: lastCompletedDay,
    points: points,
    residents: residents.grantTicketsForDebug(amount),
    completed: completed,
    weeklyCompleted: weeklyCompleted,
    monthlyCompleted: monthlyCompleted,
    history: history,
    missionCounts: missionCounts,
    seenDialogues: seenDialogues,
    oyasumi: oyasumi,
    debugResets: debugResets,
  );

  Progress acquireResident(TownResident resident) => Progress(
      playerName: playerName,
    day: day,
    lastCompletedDay: lastCompletedDay,
    points: points,
    residents: residents.acquire(resident, points),
    completed: completed,
    weeklyCompleted: weeklyCompleted,
    monthlyCompleted: monthlyCompleted,
    history: history,
    missionCounts: missionCounts,
    seenDialogues: seenDialogues,
    oyasumi: oyasumi,
    debugResets: debugResets,
  );

  /// One durable transaction for ten tickets and eleven residents.
  Progress acquireResidentsTenPlusOne(List<TownResident> results) => Progress(
      playerName: playerName,
    day: day,
    lastCompletedDay: lastCompletedDay,
    points: points,
    residents: residents.acquireTenPlusOne(results, points),
    completed: completed,
    weeklyCompleted: weeklyCompleted,
    monthlyCompleted: monthlyCompleted,
    history: history,
    missionCounts: missionCounts,
    seenDialogues: seenDialogues,
    oyasumi: oyasumi,
    debugResets: debugResets,
  );

  Progress markDialogueSeen(String id) {
    if (id.isEmpty) throw ArgumentError.value(id, 'id');
    if (seenDialogues.contains(id)) return this;
    return Progress(
      playerName: playerName,
      day: day,
      lastCompletedDay: lastCompletedDay,
      points: points,
      residents: residents,
      completed: completed,
      weeklyCompleted: weeklyCompleted,
      monthlyCompleted: monthlyCompleted,
      history: history,
      missionCounts: missionCounts,
      seenDialogues: {...seenDialogues, id},
      oyasumi: oyasumi,
      debugResets: debugResets,
    );
  }

  Progress withOyasumi(OyasumiProgress value) => Progress(
      playerName: playerName,
    day: day, lastCompletedDay: lastCompletedDay, points: points,
    residents: residents, completed: completed, history: history,
    weeklyCompleted: weeklyCompleted, monthlyCompleted: monthlyCompleted,
    debugResets: debugResets, missionCounts: missionCounts,
    seenDialogues: seenDialogues, oyasumi: value,
  );

  Progress withPlayerName(String name) {
    if (!isValidPlayerName(name)) {
      throw ArgumentError.value(name, 'name', 'Invalid player name (1-$maxPlayerNameLength characters).');
    }
    if (name == playerName) return this;
    return Progress(
      day: day,
      lastCompletedDay: lastCompletedDay,
      points: points,
      playerName: name,
      residents: residents,
      completed: completed,
      weeklyCompleted: weeklyCompleted,
      monthlyCompleted: monthlyCompleted,
      history: history,
      missionCounts: missionCounts,
      seenDialogues: seenDialogues,
      oyasumi: oyasumi,
      debugResets: debugResets,
    );
  }

  String encode() => jsonEncode({
    'version': 5,
    'playerName': playerName,
    if (oyasumi.completed > 0) 'oyasumi': oyasumi.toJson(),
    'residents': residents.encode(),
    'missionCounts': {
      for (final mission in Mission.values)
        if ((missionCounts[mission] ?? 0) > 0)
          mission.name: missionCounts[mission],
    },
    'seenDialogues': (seenDialogues.toList()..sort()),
    'day': day,
    'lastCompletedDay': lastCompletedDay,
    'points': points,
    'completed': _encodeMissions(completed),
    'weeklyCompleted': _encodeMissions(weeklyCompleted),
    'monthlyCompleted': _encodeMissions(monthlyCompleted),
    if (debugResets.isNotEmpty)
      'debugResets': {
        for (final period in MissionPeriod.values)
          if (debugResets.containsKey(period)) period.name: debugResets[period],
      },
    'history': {
      for (final date in (history.keys.toList()..sort()))
        date: _encodeMissions(history[date]!),
    },
  });

  static List<String> _encodeMissions(Set<Mission> missions) => [
    for (final mission in Mission.values)
      if (missions.contains(mission)) mission.name,
  ];

  /// Older records are strictly validated before migration into v5.
  static Progress decode(String raw, {int? expectedVersion}) {
    final data = jsonDecode(raw);
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Invalid FutureLift save schema.');
    }
    final version = data['version'];
    if (version is! int ||
        ![1, 2, 3, 4, 5].contains(version) ||
        (expectedVersion != null && expectedVersion != version)) {
      throw FormatException('Unsupported FutureLift save version: $version');
    }
    final keys = {
      if (version >= 5 && data.containsKey('oyasumi')) 'oyasumi',
      if (version >= 5 && data.containsKey('playerName')) 'playerName',
      if (version >= 4) 'residents',
      if (version >= 5) ...['missionCounts', 'seenDialogues'],
      'version',
      'day',
      'lastCompletedDay',
      'points',
      'completed',
      if (version >= 2) 'history',
      if (version >= 3) ...['weeklyCompleted', 'monthlyCompleted'],
      if (version >= 3 && data.containsKey('debugResets')) 'debugResets',
    };
    if (data.keys.toSet().difference(keys).isNotEmpty ||
        data.length != keys.length ||
        !_validDay(data['day']) ||
        (data['lastCompletedDay'] != null &&
            !_validDay(data['lastCompletedDay'])) ||
        data['points'] is! int) {
      throw const FormatException('Invalid FutureLift save schema.');
    }
    if (data.containsKey('playerName') &&
        (version < 5 ||
            data['playerName'] is! String ||
            !isValidPlayerName(data['playerName'] as String))) {
      throw const FormatException('Invalid player name.');
    }
    final day = data['day'] as String;
    final last = data['lastCompletedDay'] as String?;
    final points = data['points'] as int;
    final residents = version >= 4
        ? ResidentCollection.decode(data['residents'], points)
        : ResidentCollection.initial(points);
    final completed = _missions(
      data['completed'],
      'completed',
      MissionPeriod.daily,
    );
    final weekly = version >= 3
        ? _missions(
            data['weeklyCompleted'],
            'weeklyCompleted',
            MissionPeriod.weekly,
          )
        : <Mission>{};
    final monthly = version >= 3
        ? _missions(
            data['monthlyCompleted'],
            'monthlyCompleted',
            MissionPeriod.monthly,
          )
        : <Mission>{};
    final history = <String, Set<Mission>>{};
    final debugResets = <MissionPeriod, String>{};
    if (version >= 3 && data.containsKey('debugResets')) {
      final raw = data['debugResets'];
      if (raw is! Map<String, dynamic> || raw.isEmpty) {
        throw const FormatException('Invalid debug reset markers.');
      }
      for (final entry in raw.entries) {
        final period = switch (entry.key) {
          'daily' => MissionPeriod.daily,
          'weekly' => MissionPeriod.weekly,
          'monthly' => MissionPeriod.monthly,
          _ => throw FormatException(
            'Unknown debug reset period: ${entry.key}',
          ),
        };
        final expected = switch (period) {
          MissionPeriod.daily => day,
          MissionPeriod.weekly => weekStart(day),
          MissionPeriod.monthly => monthKey(day),
        };
        if (entry.value != expected) {
          throw FormatException('Invalid debug reset marker: ${entry.key}');
        }
        debugResets[period] = expected;
      }
    }

    if (version == 1) {
      // Only today's IDs exist in v1; older days cannot be reconstructed.
      if (completed.isNotEmpty) history[day] = completed;
    } else {
      final rawHistory = data['history'];
      if (rawHistory is! Map<String, dynamic>) {
        throw const FormatException('Invalid FutureLift history map.');
      }
      for (final entry in rawHistory.entries) {
        final date = entry.key;
        if (!_validDay(date) ||
            date.compareTo(day) > 0 ||
            last == null ||
            date.compareTo(last) > 0) {
          throw FormatException('Invalid history date: $date');
        }
        final missions = _missions(
          entry.value,
          'history[$date]',
          version == 2 ? MissionPeriod.daily : null,
        );
        if (missions.isEmpty) {
          throw FormatException('Empty history entry: $date');
        }
        history[date] = missions;
      }
    }

    final todayHistory = history[day] ?? <Mission>{};
    final weekHistory = history.entries
        .where((entry) => weekStart(entry.key) == weekStart(day))
        .expand((entry) => entry.value)
        .where((mission) => mission.period == MissionPeriod.weekly)
        .toSet();
    final monthHistory = history.entries
        .where((entry) => monthKey(entry.key) == monthKey(day))
        .expand((entry) => entry.value)
        .where((mission) => mission.period == MissionPeriod.monthly)
        .toSet();

    if (points < 0 ||
        points % 10 != 0 ||
        points < completed.length * 10 ||
        (points == 0) != (last == null) ||
        (last != null && last.compareTo(day) > 0) ||
        (completed.isNotEmpty && last != day) ||
        (version <= 2 && completed.isEmpty && last == day) ||
        (debugResets[MissionPeriod.daily] != day &&
            todayHistory
                .where((m) => m.period == MissionPeriod.daily)
                .any((m) => !completed.contains(m))) ||
        (debugResets[MissionPeriod.weekly] != weekStart(day) &&
            !weekly.containsAll(weekHistory)) ||
        (debugResets[MissionPeriod.monthly] != monthKey(day) &&
            !monthly.containsAll(monthHistory)) ||
        history.values.fold<int>(0, (sum, events) => sum + events.length) * 10 >
            points) {
      throw const FormatException('Inconsistent FutureLift progress values.');
    }
    final knownCounts = <Mission, int>{};
    if (version >= 5) {
      final rawCounts = data['missionCounts'];
      final rawSeen = data['seenDialogues'];
      if (rawCounts is! Map<String, dynamic> || rawSeen is! List ||
          rawSeen.any((id) => id is! String || id.isEmpty) ||
          rawSeen.toSet().length != rawSeen.length) {
        throw const FormatException('Invalid dialogue/mission counters schema.');
      }
      for (final entry in rawCounts.entries) {
        final matches = Mission.values.where((m) => m.name == entry.key);
        if (matches.length != 1 || entry.value is! int || entry.value <= 0) {
          throw FormatException('Invalid mission counter: ${entry.key}');
        }
        knownCounts[matches.single] = entry.value as int;
      }
      if (knownCounts.values.fold<int>(0, (a, b) => a + b) > points ~/ 10) {
        throw const FormatException('Mission counts exceed earned points.');
      }
      for (final mission in Mission.values) {
        final observed = history.values.where((e) => e.contains(mission)).length;
        if ((knownCounts[mission] ?? 0) < observed) {
          throw FormatException('Mission counter is below journal: ${mission.name}');
        }
      }
    } else {
      // Historical unique entries are an observed minimum, never invented events.
      for (final mission in Mission.values) {
        final observed = history.values.where((e) => e.contains(mission)).length;
        if (observed > 0) knownCounts[mission] = observed;
      }
    }
    return Progress(
      day: day,
      lastCompletedDay: last,
      points: points,
      playerName: version >= 5 && data.containsKey('playerName')
          ? data['playerName'] as String : defaultPlayerName,
      residents: residents,
      completed: completed,
      weeklyCompleted: weekly,
      monthlyCompleted: monthly,
      history: history,
      missionCounts: knownCounts,
      oyasumi: data.containsKey('oyasumi') ? OyasumiProgress.fromJson(data['oyasumi']) : const OyasumiProgress(),
      seenDialogues: version >= 5 ? Set<String>.from(data['seenDialogues'] as List) : {},
      debugResets: debugResets,
    );
  }

  static Set<Mission> _missions(
    dynamic raw,
    String field,
    MissionPeriod? expected,
  ) {
    if (raw is! List) throw FormatException('Invalid mission list: $field');
    final result = <Mission>{};
    for (final name in raw) {
      if (name is! String || !Mission.values.any((m) => m.name == name)) {
        throw FormatException('Unknown mission ID in $field: $name');
      }
      final mission = Mission.values.singleWhere((m) => m.name == name);
      if (expected != null && mission.period != expected) {
        throw FormatException('Unexpected period for $name in $field');
      }
      if (!result.add(mission)) {
        throw FormatException('Duplicate mission ID in $field: $name');
      }
    }
    return result;
  }

  static bool _validDay(dynamic value) {
    if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      return false;
    }
    final parsed = DateTime.tryParse(value);
    return parsed != null && localDay(parsed) == value;
  }
}

abstract interface class ProgressStore {
  Future<Progress?> load();
  Future<void> save(Progress progress);
}

class LocalProgressStore implements ProgressStore {
  LocalProgressStore(this.preferences);
  final SharedPreferencesAsync preferences;
  static const key = 'future_lift.progress.v5';
  static const v4Key = 'future_lift.progress.v4';
  static const v3Key = 'future_lift.progress.v3';
  static const previousKey = 'future_lift.progress.v2';
  static const legacyKey = 'future_lift.progress.v1';

  @override
  Future<Progress?> load() async {
    final current = await preferences.getString(key);
    if (current != null) return Progress.decode(current, expectedVersion: 5);
    // Explicit migrations only. Invalid newer data never falls back to older data.
    for (final entry in [(v4Key, 4), (v3Key, 3), (previousKey, 2), (legacyKey, 1)]) {
      final raw = await preferences.getString(entry.$1);
      if (raw == null) continue;
      final migrated = Progress.decode(raw, expectedVersion: entry.$2);
      await save(migrated);
      return migrated;
    }
    return null;
  }

  @override
  Future<void> save(Progress progress) =>
      preferences.setString(key, progress.encode());
}

class ProgressFailure {
  const ProgressFailure(this.operation, this.error, this.stackTrace);
  final String operation;
  final Object error;
  final StackTrace stackTrace;
  String get diagnostics =>
      '$operation\n${LocalProgressStore.key} / ${LocalProgressStore.v4Key} / ${LocalProgressStore.v3Key} / ${LocalProgressStore.previousKey} / ${LocalProgressStore.legacyKey}\n$error\n$stackTrace';
}

class ProgressController extends ChangeNotifier {
  ProgressController(this.store, {DateTime Function()? clock, Random? random})
    : clock = clock ?? DateTime.now,
      random = random ?? Random();
  final Random random;
  final ProgressStore store;
  final DateTime Function() clock;
  Progress? progress;
  ProgressFailure? failure;
  bool busy = false;
  bool _dayRefreshPending = false;

  void _finishOperation() {
    busy = false;
    notifyListeners();
    if (_dayRefreshPending) {
      _dayRefreshPending = false;
      unawaited(refreshDay());
    }
  }

  Future<void> initialize() async {
    if (busy || failure != null || progress != null) return;
    busy = true;
    notifyListeners();
    try {
      final saved = await store.load();
      final current = saved?.onDay(clock()) ?? Progress.empty(clock());
      if (saved != null && !identical(current, saved)) {
        await store.save(current);
      }
      progress = current;
    } catch (error, stack) {
      failure = ProgressFailure('端末内データの読み込み・日付更新', error, stack);
    } finally {
      _finishOperation();
    }
  }

  Future<void> refreshDay() async {
    if (failure != null) return;
    if (busy) {
      _dayRefreshPending = true;
      return;
    }
    if (progress == null) return;
    busy = true;
    try {
      final current = progress!.onDay(clock());
      if (!identical(current, progress)) {
        await store.save(current);
        progress = current;
      }
    } catch (error, stack) {
      failure = ProgressFailure('日付更新の保存', error, stack);
    } finally {
      _finishOperation();
    }
  }

  Future<bool> setPlayerName(String name) async {
    if (!isValidPlayerName(name)) {
      throw ArgumentError.value(name, 'name', 'Invalid player name.');
    }
    if (busy || failure != null || progress == null) return false;
    busy = true;
    notifyListeners();
    try {
      final next = progress!.withPlayerName(name);
      if (!identical(next, progress)) {
        await store.save(next);
        progress = next;
      }
      return true;
    } catch (error, stack) {
      failure = ProgressFailure('名前の保存', error, stack);
      return false;
    } finally {
      _finishOperation();
    }
  }

  Future<bool> complete(Mission mission) async {
    if (busy || failure != null || progress == null) return false;
    busy = true;
    notifyListeners();
    try {
      final today = progress!.onDay(clock());
      final next = today.complete(mission);
      if (identical(next, progress)) return false;
      // Commit the whole snapshot before publishing points or celebration.
      await store.save(next);
      progress = next;
      return !identical(next, today);
    } catch (error, stack) {
      failure = ProgressFailure('ミッション ${mission.name} の達成保存', error, stack);
      return false;
    } finally {
      _finishOperation();
    }
  }

  Future<TownResident?> drawResident() async {
    if (busy ||
        failure != null ||
        progress == null ||
        progress!.residents.availableKotohogi(progress!.points) < 30) {
      return null;
    }
    busy = true;
    notifyListeners();
    try {
      final pool = TownResident.gachaPool;
      if (pool.isEmpty) throw StateError('Resident gacha pool is empty');
      final resident = pool[random.nextInt(pool.length)];
      final next = progress!.onDay(clock()).acquireResident(resident);
      await store.save(next);
      progress = next;
      return resident;
    } catch (error, stack) {
      failure = ProgressFailure('移住相談会の抽選・保存', error, stack);
      return null;
    } finally {
      _finishOperation();
    }
  }

  /// Legacy 10-draw bundle costs 300 kotohogi and grants a bonus draw.
  Future<List<TownResident>?> drawResidentsTenPlusOne() async {
    if (busy ||
        failure != null ||
        progress == null ||
        progress!.residents.availableKotohogi(progress!.points) < 300) {
      return null;
    }
    busy = true;
    notifyListeners();
    try {
      final pool = TownResident.gachaPool;
      if (pool.isEmpty) throw StateError('Resident gacha pool is empty');
      final results = List<TownResident>.generate(
        11,
        (_) => pool[random.nextInt(pool.length)],
      );
      final next = progress!.onDay(clock()).acquireResidentsTenPlusOne(results);
      await store.save(next);
      progress = next;
      return results;
    } catch (error, stack) {
      failure = ProgressFailure('移住相談会10回分の抽選・保存', error, stack);
      return null;
    } finally {
      _finishOperation();
    }
  }

  /// Grant extra tickets only in debug builds. Commit before publishing.
  Future<bool> grantTicketsForDebug(int amount) async {
    if (!developerToolsAvailable) {
      throw StateError('Ticket grants are available only in debug builds.');
    }
    if (amount <= 0) {
      throw ArgumentError.value(amount, 'amount', 'Must be positive.');
    }
    if (busy || failure != null || progress == null) return false;
    busy = true;
    notifyListeners();
    try {
      final today = progress!.onDay(clock());
      final next = today.grantTicketsForDebug(amount);
      await store.save(next);
      progress = next;
      return true;
    } catch (error, stack) {
      failure = ProgressFailure('デバッグ用ガチャ券 $amount 枚の追加保存', error, stack);
      return false;
    } finally {
      _finishOperation();
    }
  }

  /// Debug-only persistence of reset mission buttons. Never delete history.
  Future<bool> resetAllMissionsForDebug() async {
    if (!developerToolsAvailable) {
      throw StateError('Mission reset is available only in debug builds.');
    }
    if (busy || failure != null || progress == null) return false;
    busy = true;
    notifyListeners();
    try {
      final today = progress!.onDay(clock());
      final next = today.resetMissionsForDebug();
      await store.save(next);
      progress = next;
      return true;
    } catch (error, stack) {
      failure = ProgressFailure('デバッグ用ミッション全リセット', error, stack);
      return false;
    } finally {
      _finishOperation();
    }
  }

  /// Skip exactly one club introduction for development previews.
  ///
  /// Debug skips do not award kotohogi; an unset milestone deliberately
  /// lets the next stage be inspected with no additional missions.
  Future<bool> advanceOyasumiForDebug() async {
    if (!developerToolsAvailable) {
      throw StateError('Oyasumi debug progression is unavailable in release builds.');
    }
    if (busy || failure != null || progress == null) return false;
    final completed = progress!.oyasumi.completed;
    if (completed < 0 || completed >= 3) {
      throw StateError('No further Oyasumi Club stage: $completed');
    }
    busy = true;
    notifyListeners();
    try {
      final today = progress!.onDay(clock());
      final scene = OyasumiScene(
        saved: today.oyasumi,
        owned: today.residents.owned,
        now: clock(),
        earnedKotohogi: today.points,
      );
      final currentNight = DateTime.parse(scene.nightKey);
      final previousNight = DateTime.utc(
        currentNight.year, currentNight.month, currentNight.day - 1);
      final date = '${previousNight.year.toString().padLeft(4, '0')}-'
          '${previousNight.month.toString().padLeft(2, '0')}-'
          '${previousNight.day.toString().padLeft(2, '0')}';
      final next = today.withOyasumi(OyasumiProgress(
        completed: completed + 1, lastNight: date));
      await store.save(next);
      progress = next;
      return true;
    } catch (error, stack) {
      failure = ProgressFailure('デバッグ用おやすみクラブ進行保存', error, stack);
      return false;
    } finally {
      _finishOperation();
    }
  }

  /// Return only the club story to the beginning; preserve other game data.
  Future<bool> resetOyasumiForDebug() async {
    if (!developerToolsAvailable) {
      throw StateError('Oyasumi debug reset is unavailable in release builds.');
    }
    if (busy || failure != null || progress == null ||
        progress!.oyasumi.completed == 0) {
      return false;
    }
    busy = true;
    notifyListeners();
    try {
      final next = progress!.onDay(clock())
          .withOyasumi(const OyasumiProgress());
      await store.save(next);
      progress = next;
      return true;
    } catch (error, stack) {
      failure = ProgressFailure('デバッグ用おやすみクラブ初期化保存', error, stack);
      return false;
    } finally {
      _finishOperation();
    }
  }

  Future<bool> completeOyasumi(OyasumiScene scene, TownResident speaker, String group) async {
    if (busy || failure != null || progress == null ||
        progress!.oyasumi.completed != scene.saved.completed ||
        progress!.oyasumi.lastNight != scene.saved.lastNight ||
        progress!.oyasumi.lastKotohogi != scene.saved.lastKotohogi ||
        progress!.points != scene.earnedKotohogi) {
      return false;
    }
    final value = scene.completeIntroduction(speaker, group);
    if (identical(value, scene.saved)) return true;
    busy = true;
    notifyListeners();
    try {
      final next = progress!.onDay(clock()).withOyasumi(value);
      await store.save(next);
      progress = next;
      return true;
    } catch (error, stack) {
      failure = ProgressFailure('おやすみクラブの進行保存', error, stack);
      return false;
    } finally {
      _finishOperation();
    }
  }

  /// Persist the resignation's earned-kotohogi checkpoint atomically with
  /// its read marker. The cleaning job needs a *new* 30 kotohogi afterward.
  Future<bool> completeOyasumiResignation(OyasumiScene scene) async {
    if (busy || failure != null || progress == null ||
        !scene.resignationDialogueAvailable ||
        progress!.oyasumi.completed != scene.saved.completed ||
        progress!.oyasumi.lastNight != scene.saved.lastNight ||
        progress!.oyasumi.lastKotohogi != scene.saved.lastKotohogi ||
        progress!.oyasumi.resignationAtKotohogi !=
            scene.saved.resignationAtKotohogi ||
        progress!.points != scene.earnedKotohogi ||
        progress!.seenDialogues.contains(OyasumiScene.resignationId)) {
      return false;
    }
    busy = true;
    notifyListeners();
    try {
      final today = progress!.onDay(clock());
      final current = today.oyasumi;
      final next = today.withOyasumi(OyasumiProgress(
        completed: current.completed,
        lastNight: current.lastNight,
        lastKotohogi: current.lastKotohogi,
        resignationAtKotohogi: scene.earnedKotohogi,
      )).markDialogueSeen(OyasumiScene.resignationId);
      await store.save(next);
      progress = next;
      return true;
    } catch (error, stack) {
      failure = ProgressFailure('かえるの退職会話の保存', error, stack);
      return false;
    } finally {
      _finishOperation();
    }
  }

  Future<bool> recordDialogueSeen(String id) async {
    if (busy || failure != null || progress == null) return false;
    busy = true;
    notifyListeners();
    try {
      final today = progress!.onDay(clock());
      final next = today.markDialogueSeen(id);
      if (!identical(next, progress)) {
        await store.save(next);
        progress = next;
      }
      return true;
    } catch (error, stack) {
      failure = ProgressFailure('会話 $id の閲覧記録保存', error, stack);
      return false;
    } finally {
      _finishOperation();
    }
  }

  Future<bool> clearHistory() async {
    if (busy ||
        failure != null ||
        progress == null ||
        progress!.history.isEmpty) {
      return false;
    }
    busy = true;
    notifyListeners();
    try {
      final next = progress!.clearHistory();
      await store.save(next);
      progress = next;
      return true;
    } catch (error, stack) {
      failure = ProgressFailure('履歴の削除', error, stack);
      return false;
    } finally {
      _finishOperation();
    }
  }
}
