import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:future_lift/progress.dart';
import 'package:future_lift/oyasumi_club.dart';

class MemoryStore implements ProgressStore {
  String? raw;
  int writes = 0;
  Object? loadError;
  Object? saveError;
  Completer<void>? gate;

  @override
  Future<Progress?> load() async {
    if (loadError != null) throw loadError!;
    return raw == null ? null : Progress.decode(raw!);
  }

  @override
  Future<void> save(Progress progress) async {
    writes++;
    if (gate != null) await gate!.future;
    if (saveError != null) throw saveError!;
    raw = progress.encode();
  }
}

void main() {
  final today = DateTime(2026, 10, 9, 12);

  test('player name is saved and preserved by progress transitions', () async {
    final store = MemoryStore();
    final controller = ProgressController(store, clock: () => today);
    await controller.initialize();
    expect(controller.progress!.playerName, 'ハル');
    expect(await controller.setPlayerName('もふ'), isTrue);
    expect(Progress.decode(store.raw!).playerName, 'もふ');
    expect(await controller.complete(Mission.strength), isTrue);
    expect(controller.progress!.playerName, 'もふ');
    final restarted = ProgressController(
      store, clock: () => today.add(const Duration(days: 1)),
    );
    await restarted.initialize();
    expect(restarted.progress!.playerName, 'もふ');
    expect(restarted.progress!.day, '2026-10-10');
    expect(restarted.progress!.withOyasumi(const OyasumiProgress()).playerName, 'もふ');
    expect(restarted.progress!.clearHistory().playerName, 'もふ');
    expect(restarted.progress!.resetMissionsForDebug().playerName, 'もふ');
  });

  test('invalid names and corrupted name storage fail fast', () async {
    final store = MemoryStore();
    final controller = ProgressController(store, clock: () => today);
    await controller.initialize();
    for (final name in ['', '  ', ' もふ', 'もふ ', '1234567890123', 'abc\n']) {
      expect(() => controller.setPlayerName(name), throwsArgumentError);
    }
    expect(store.writes, 0);
    final valid = jsonDecode(Progress.empty(today).encode()) as Map<String, dynamic>;
    for (final bad in [null, 42, '', ' もふ', '1234567890123']) {
      expect(() => Progress.decode(jsonEncode({...valid, 'playerName': bad})),
          throwsFormatException);
    }
    final oldV5 = Map<String, dynamic>.from(valid)..remove('playerName');
    expect(Progress.decode(jsonEncode(oldV5)).playerName, 'ハル');
  });

  test('failed name save retains old name and original exception', () async {
    final error = StateError('storage rejected name');
    final store = MemoryStore();
    final controller = ProgressController(store, clock: () => today);
    await controller.initialize();
    store.saveError = error;
    expect(await controller.setPlayerName('もふ'), isFalse);
    expect(controller.progress!.playerName, 'ハル');
    expect(controller.failure!.error, same(error));
    expect(controller.failure!.stackTrace.toString(), contains('MemoryStore.save'));
    expect(await controller.setPlayerName('次'), isFalse);
    expect(store.writes, 1);
  });

  test(
    'midnight refresh waits for an in-flight save without losing earned points',
    () async {
      var now = DateTime(2026, 10, 9, 23, 59);
      final store = MemoryStore()..gate = Completer<void>();
      final controller = ProgressController(store, clock: () => now);
      await controller.initialize();
      final completion = controller.complete(Mission.strength);
      now = DateTime(2026, 10, 10);
      await controller.refreshDay();
      store.gate!.complete();
      expect(await completion, isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(controller.progress!.day, '2026-10-10');
      expect(controller.progress!.completed, isEmpty);
      expect(controller.progress!.points, 10);
      expect(controller.progress!.lastCompletedDay, '2026-10-09');
      expect(Progress.decode(store.raw!).day, '2026-10-10');
      expect(store.writes, 2);
    },
  );

  test(
    'award once per mission per day and restore from serialized storage',
    () async {
      final store = MemoryStore();
      final controller = ProgressController(store, clock: () => today);
      await controller.initialize();
      expect(controller.progress!.points, 0);
      expect(await controller.complete(Mission.strength), isTrue);
      expect(await controller.complete(Mission.strength), isFalse);
      expect(controller.progress!.points, 10);
      expect(store.writes, 1);
      final restarted = ProgressController(store, clock: () => today);
      await restarted.initialize();
      expect(restarted.progress!.completed, {Mission.strength});
      expect(restarted.progress!.lastCompletedDay, '2026-10-09');
      expect(restarted.progress!.points, 10);
      for (final mission in [Mission.outside, Mission.conversation]) {
        expect(await restarted.complete(mission), isTrue);
      }
      expect(restarted.progress!.points, 30);
      expect(restarted.progress!.townLevel, 1);
    },
  );

  test('midnight and absence reset only daily missions, retaining last date and points', () async {
    var now = DateTime(2026, 12, 31, 23, 59);
    final store = MemoryStore();
    final controller = ProgressController(store, clock: () => now);
    await controller.initialize();
    await controller.complete(Mission.outside);
    now = DateTime(2027, 1, 1);
    await controller.refreshDay();
    expect(controller.progress!.day, '2027-01-01');
    expect(controller.progress!.completed, isEmpty);
    expect(controller.progress!.lastCompletedDay, '2026-12-31');
    expect(controller.progress!.points, 10);
    await controller.complete(Mission.outside);
    expect(controller.progress!.points, 20);
    now = DateTime(2027, 3, 1);
    final restarted = ProgressController(store, clock: () => now);
    await restarted.initialize();
    expect(restarted.progress!.completed, isEmpty);
    expect(restarted.progress!.points, 20);
    expect(restarted.progress!.lastCompletedDay, '2027-01-01');
  });

  test(
    'completion checks the current day even before lifecycle refresh',
    () async {
      var now = today;
      final controller = ProgressController(MemoryStore(), clock: () => now);
      await controller.initialize();
      await controller.complete(Mission.conversation);
      now = now.add(const Duration(days: 1));
      expect(await controller.complete(Mission.conversation), isTrue);
      expect(controller.progress!.points, 20);
      expect(controller.progress!.completed, {Mission.conversation});
    },
  );

  test(
    'concurrent taps cannot double award, and nothing publishes before save',
    () async {
      final store = MemoryStore()..gate = Completer<void>();
      final controller = ProgressController(store, clock: () => today);
      await controller.initialize();
      final first = controller.complete(Mission.strength);
      expect(controller.busy, isTrue);
      expect(controller.progress!.points, 0);
      expect(await controller.complete(Mission.strength), isFalse);
      expect(await controller.complete(Mission.outside), isFalse);
      store.gate!.complete();
      expect(await first, isTrue);
      expect(controller.progress!.points, 10);
      expect(store.writes, 1);
    },
  );

  test('save failure preserves original exception/stack, stops awards and never retries', () async {
    final error = StateError('disk unavailable');
    final store = MemoryStore()..saveError = error;
    final controller = ProgressController(store, clock: () => today);
    await controller.initialize();
    expect(await controller.complete(Mission.strength), isFalse);
    expect(controller.failure!.error, same(error));
    expect(
      controller.failure!.stackTrace.toString(),
      contains('MemoryStore.save'),
    );
    expect(controller.progress!.points, 0);
    expect(controller.progress!.completed, isEmpty);
    expect(store.raw, isNull);
    await controller.refreshDay();
    await controller.initialize();
    expect(await controller.complete(Mission.outside), isFalse);
    expect(store.writes, 1);
  });

  test(
    'read and rollover save errors halt without replacing existing data',
    () async {
      final error = StateError('cannot read');
      final store = MemoryStore()..loadError = error;
      final controller = ProgressController(store, clock: () => today);
      await controller.initialize();
      expect(controller.failure!.error, same(error));
      expect(controller.progress, isNull);
      expect(store.writes, 0);
      final saved = Progress.empty(today).complete(Mission.strength).encode();
      store
        ..loadError = null
        ..raw = saved
        ..saveError = error;
      final nextDay = ProgressController(
        store,
        clock: () => today.add(const Duration(days: 1)),
      );
      await nextDay.initialize();
      expect(nextDay.failure!.error, same(error));
      expect(store.raw, saved);
    },
  );

  test(
    'invalid schema, types, dates, IDs and inconsistent values fail fast',
    () {
      final valid =
          jsonDecode(Progress.empty(today).encode()) as Map<String, dynamic>;
      for (final patch in <Map<String, dynamic>>[
        {'version': 2},
        {'version': 1.0},
        {'points': '10'},
        {'points': -10},
        {'points': 1},
        {'day': '2026-02-30'},
        {'day': '2026-1-1'},
        {
          'completed': ['unknown'],
        },
        {
          'completed': ['strength', 'strength'],
        },
        {'points': 10},
        {'lastCompletedDay': '2026-10-10'},
        {
          'completed': ['strength'],
        },
        {'extra': true},
      ]) {
        expect(
          () => Progress.decode(jsonEncode({...valid, ...patch})),
          throwsFormatException,
          reason: patch.toString(),
        );
      }
      expect(() => Progress.decode('broken'), throwsFormatException);
    },
  );

  test(
    'corrupt storage halts instead of initializing an empty profile',
    () async {
      final store = MemoryStore()..raw = '{broken';
      final controller = ProgressController(store, clock: () => today);
      await controller.initialize();
      expect(controller.failure!.error, isA<FormatException>());
      expect(controller.progress, isNull);
      expect(store.raw, '{broken');
      expect(store.writes, 0);
    },
  );

  test(
    'backward device dates stop without silently granting duplicate missions',
    () async {
      final store = MemoryStore()
        ..raw = Progress.empty(today).complete(Mission.strength).encode();
      final controller = ProgressController(
        store,
        clock: () => today.subtract(const Duration(days: 1)),
      );
      await controller.initialize();
      expect(controller.failure!.error, isA<StateError>());
      expect(store.writes, 0);
    },
  );

  test('journal records all dates, survives rollovers, and awards only once', () async {
    var now = DateTime(2026, 10, 9, 12);
    final store = MemoryStore();
    final controller = ProgressController(store, clock: () => now);
    await controller.initialize();
    expect(await controller.complete(Mission.strength), isTrue);
    expect(await controller.complete(Mission.strength), isFalse);
    expect(await controller.complete(Mission.outside), isTrue);

    now = DateTime(2026, 11, 1);
    await controller.refreshDay();
    expect(controller.progress!.history['2026-10-09'],
        {Mission.strength, Mission.outside});
    expect(controller.progress!.completed, isEmpty);
    expect(await controller.complete(Mission.conversation), isTrue);
    expect(controller.progress!.history['2026-11-01'], {Mission.conversation});

    final restarted = ProgressController(store, clock: () => now);
    await restarted.initialize();
    expect(restarted.progress!.points, 30);
    expect(restarted.progress!.history.length, 2);
    expect(restarted.progress!.history['2026-10-09'],
        {Mission.strength, Mission.outside});
    expect(restarted.progress!.history['2026-11-01'],
        {Mission.conversation});
    expect(() => restarted.progress!.history.clear(), throwsUnsupportedError);
    expect(() => restarted.progress!.history['2026-10-09']!.clear(),
        throwsUnsupportedError);
  });

  test('v1 can migrate without inventing older events or dropping points', () {
    final legacy = jsonEncode({
      'version': 1,
      'day': '2026-10-09',
      'lastCompletedDay': '2026-10-09',
      'points': 100,
      'completed': ['strength', 'conversation'],
    });
    final migrated = Progress.decode(legacy, expectedVersion: 1);
    expect(migrated.points, 100);
    expect(migrated.history, {
      '2026-10-09': {Mission.strength, Mission.conversation},
    });
    final serialized = migrated.encode();
    expect(jsonDecode(serialized)['version'], 5);
    expect(Progress.decode(serialized, expectedVersion: 5).points, 100);
    expect(
      Progress.decode(serialized).history['2026-10-09'],
      {Mission.strength, Mission.conversation},
    );
    expect(() => Progress.decode(legacy, expectedVersion: 2),
        throwsFormatException);
    expect(() => Progress.decode(serialized, expectedVersion: 1),
        throwsFormatException);

    final earlierOnly = Progress.decode(jsonEncode({
      'version': 1,
      'day': '2026-10-09',
      'lastCompletedDay': '2026-10-05',
      'points': 30,
      'completed': <String>[],
    }));
    expect(earlierOnly.history, isEmpty);
    expect(earlierOnly.points, 30);
  });

  test('clear history leaves earned points and daily completion untouched', () async {
    final store = MemoryStore();
    final controller = ProgressController(store, clock: () => today);
    await controller.initialize();
    await controller.complete(Mission.strength);
    expect(await controller.clearHistory(), isTrue);
    expect(controller.progress!.history, isEmpty);
    expect(controller.progress!.points, 10);
    expect(controller.progress!.completed, {Mission.strength});
    expect(await controller.complete(Mission.strength), isFalse);
    expect(await controller.complete(Mission.outside), isTrue);
    expect(controller.progress!.points, 20);
    expect(controller.progress!.history['2026-10-09'], {Mission.outside});
    final restored = Progress.decode(store.raw!);
    expect(restored.completed, {Mission.strength, Mission.outside});
    expect(restored.history['2026-10-09'], {Mission.outside});
  });

  test('failed journal deletion stops without publishing altered data', () async {
    final store = MemoryStore();
    final controller = ProgressController(store, clock: () => today);
    await controller.initialize();
    await controller.complete(Mission.outside);
    final saved = store.raw;
    final error = StateError('cannot persist deletion');
    store.saveError = error;
    expect(await controller.clearHistory(), isFalse);
    expect(controller.failure!.error, same(error));
    expect(controller.failure!.operation, '履歴の削除');
    expect(controller.progress!.history['2026-10-09'], {Mission.outside});
    expect(store.raw, saved);
    expect(await controller.clearHistory(), isFalse);
    expect(await controller.complete(Mission.strength), isFalse);
  });

  test('invalid v2 history rejects inconsistent dates and actions', () {
    final valid = jsonDecode(
      Progress.empty(today).complete(Mission.strength).encode(),
    ) as Map<String, dynamic>;
    for (final history in [
      {'2026-10-09': ['strength', 'strength']},
      {'2026-10-09': ['unknown']},
      {'2026-10-09': <String>[]},
      {'2026-10-10': ['strength']},
      {'2026-02-30': ['strength']},
      {'2026-10-09': ['outside']},
      {'2026-10-08': ['strength', 'conversation']},
    ]) {
      expect(
        () => Progress.decode(jsonEncode({...valid, 'history': history})),
        throwsFormatException,
        reason: history.toString(),
      );
    }
    expect(
      () => Progress.decode(jsonEncode({...valid, 'history': []})),
      throwsFormatException,
    );
    expect(
      () => Progress.decode(jsonEncode({...valid, 'history': null})),
      throwsFormatException,
    );
  });

  test('periodic missions award once per week or month and reset on boundaries', () async {
    var now = DateTime(2026, 10, 11, 12); // Sunday
    final store = MemoryStore();
    final controller = ProgressController(store, clock: () => now);
    await controller.initialize();

    expect(Mission.movement.title, '身体を動かした');
    expect(Mission.movement.title, isNot(contains('いつもより')));
    expect(await controller.complete(Mission.movement), isTrue);
    expect(await controller.complete(Mission.weeklyStrength), isTrue);
    expect(await controller.complete(Mission.weeklyStrength), isFalse);
    expect(await controller.complete(Mission.monthlyReview), isTrue);
    expect(await controller.complete(Mission.monthlyReview), isFalse);
    expect(controller.progress!.points, 30);
    expect(controller.progress!.weeklyCompleted, {Mission.weeklyStrength});
    expect(controller.progress!.monthlyCompleted, {Mission.monthlyReview});

    now = DateTime(2026, 10, 12, 9); // next Monday, same month
    await controller.refreshDay();
    expect(controller.progress!.completed, isEmpty);
    expect(controller.progress!.weeklyCompleted, isEmpty);
    expect(controller.progress!.monthlyCompleted, {Mission.monthlyReview});
    expect(await controller.complete(Mission.weeklyStrength), isTrue);
    expect(await controller.complete(Mission.monthlyReview), isFalse);

    now = DateTime(2026, 11, 1);
    await controller.refreshDay();
    expect(controller.progress!.monthlyCompleted, isEmpty);
    expect(await controller.complete(Mission.monthlyReview), isTrue);
    expect(controller.progress!.points, 50);
    expect(controller.progress!.history['2026-10-11'],
        {Mission.movement, Mission.weeklyStrength, Mission.monthlyReview});

    final restarted = ProgressController(store, clock: () => now);
    await restarted.initialize();
    expect(restarted.progress!.points, 50);
    expect(restarted.progress!.history['2026-10-12'],
        {Mission.weeklyStrength});
    expect(restarted.progress!.monthlyCompleted, {Mission.monthlyReview});
    expect(await restarted.complete(Mission.monthlyReview), isFalse);
  });

  test('v2 saves migrate to v5 without changing existing mission IDs', () {
    final raw = jsonEncode({
      'version': 2,
      'day': '2026-10-09',
      'lastCompletedDay': '2026-10-09',
      'points': 30,
      'completed': ['strength', 'conversation'],
      'history': {
        '2026-10-08': ['outside'],
        '2026-10-09': ['strength', 'conversation'],
      },
    });
    final restored = Progress.decode(raw, expectedVersion: 2);
    expect(restored.points, 30);
    expect(restored.completed, {Mission.strength, Mission.conversation});
    expect(restored.history['2026-10-08'], {Mission.outside});
    expect(restored.weeklyCompleted, isEmpty);
    expect(restored.monthlyCompleted, isEmpty);
    final migrated = Progress.decode(restored.encode(), expectedVersion: 5);
    expect(migrated.history, restored.history);
    expect(() => Progress.decode(raw, expectedVersion: 5),
        throwsFormatException);
  });

  test('clearing journal does not allow duplicate weekly/monthly awards', () async {
    final store = MemoryStore();
    final controller = ProgressController(store, clock: () => today);
    await controller.initialize();
    await controller.complete(Mission.weeklyLearn);
    await controller.complete(Mission.monthlyHabit);
    expect(await controller.clearHistory(), isTrue);
    expect(controller.progress!.history, isEmpty);
    expect(controller.progress!.points, 20);
    expect(await controller.complete(Mission.weeklyLearn), isFalse);
    expect(await controller.complete(Mission.monthlyHabit), isFalse);
    expect(Progress.decode(store.raw!).monthlyCompleted,
        {Mission.monthlyHabit});
  });

  test('v3 period data rejects cross-period IDs and malformed history', () {
    final valid = jsonDecode(
      Progress.empty(today).complete(Mission.movement).encode(),
    ) as Map<String, dynamic>;
    for (final patch in [
      {'completed': ['weeklyStrength']},
      {'weeklyCompleted': ['movement']},
      {'monthlyCompleted': ['weeklyStrength']},
      {'weeklyCompleted': ['weeklyStrength', 'weeklyStrength']},
      {'history': {'2026-10-09': ['weeklyLearn']}},
      {'history': {'2026-10-09': ['monthlyReview']}},
      {'history': {'2026-10-09': ['movement', 'movement']}},
    ]) {
      expect(
        () => Progress.decode(jsonEncode({...valid, ...patch})),
        throwsFormatException,
        reason: patch.toString(),
      );
    }
  });

  test('debug reset clears all three periods but keeps points and journal', () async {
    var now = DateTime(2026, 10, 9, 12);
    final store = MemoryStore();
    final controller = ProgressController(store, clock: () => now);
    await controller.initialize();
    for (final mission in [
      Mission.strength,
      Mission.weeklyStrength,
      Mission.monthlyReview,
    ]) {
      expect(await controller.complete(mission), isTrue);
    }
    final originalHistory = controller.progress!.history;
    final points = controller.progress!.points;
    expect(points, 30);

    expect(await controller.resetAllMissionsForDebug(), isTrue);
    expect(controller.progress!.completed, isEmpty);
    expect(controller.progress!.weeklyCompleted, isEmpty);
    expect(controller.progress!.monthlyCompleted, isEmpty);
    expect(controller.progress!.points, points);
    expect(controller.progress!.history, originalHistory);
    expect(controller.progress!.debugResets.length, 3);

    final restarted = ProgressController(store, clock: () => now);
    await restarted.initialize();
    expect(restarted.failure, isNull);
    expect(restarted.progress!.history, originalHistory);
    expect(restarted.progress!.completed, isEmpty);
    expect(restarted.progress!.weeklyCompleted, isEmpty);
    expect(restarted.progress!.monthlyCompleted, isEmpty);
    expect(await restarted.complete(Mission.strength), isTrue);
    expect(await restarted.complete(Mission.weeklyStrength), isTrue);
    expect(await restarted.complete(Mission.monthlyReview), isTrue);
    expect(await restarted.complete(Mission.strength), isFalse);
    expect(restarted.progress!.points, points + 30);
    expect(restarted.progress!.history, originalHistory);

    now = DateTime(2026, 10, 10, 10);
    await restarted.refreshDay();
    expect(restarted.failure, isNull);
    expect(restarted.progress!.debugResets.containsKey(MissionPeriod.daily),
        isFalse);
    expect(restarted.progress!.debugResets[MissionPeriod.weekly],
        weekStart('2026-10-10'));
    expect(restarted.progress!.debugResets[MissionPeriod.monthly], '2026-10');
    final afterRollover = Progress.decode(store.raw!, expectedVersion: 5);
    expect(afterRollover.day, '2026-10-10');
    expect(afterRollover.history, originalHistory);
  });

  test('debug reset save failure does not change saved or published progress', () async {
    final store = MemoryStore();
    final controller = ProgressController(store, clock: () => today);
    await controller.initialize();
    await controller.complete(Mission.strength);
    final before = store.raw;
    final exception = StateError('debug reset save rejected');
    store.saveError = exception;
    expect(await controller.resetAllMissionsForDebug(), isFalse);
    expect(controller.failure?.error, same(exception));
    expect(controller.failure?.operation, 'デバッグ用ミッション全リセット');
    expect(controller.progress!.completed, {Mission.strength});
    expect(store.raw, before);
  });

  test('debug reset markers reject unknown periods, incorrect dates and types', () {
    final valid = Progress.empty(today).complete(Mission.strength);
    final data = jsonDecode(valid.encode()) as Map<String, dynamic>;
    for (final reset in [
      <String, dynamic>{},
      {'daily': '2026-10-08'},
      {'weekly': '2026-10-06'},
      {'monthly': '2026-09'},
      {'unknown': '2026-10-09'},
      {'daily': 9},
      <String, dynamic>{'daily': null},
      <dynamic>[],
    ]) {
      expect(
        () => Progress.decode(
          jsonEncode({...data, 'debugResets': reset}),
          expectedVersion: 5,
        ),
        throwsFormatException,
        reason: reset.toString(),
      );
    }
  });

  test('four town stages use cumulative points and never decay', () {
    for (final (points, level) in [
      (0, 0),
      (20, 0),
      (30, 1),
      (80, 1),
      (90, 2),
      (170, 2),
      (180, 3),
      (9990, 3),
    ]) {
      final progress = Progress(
        day: localDay(today),
        lastCompletedDay: null,
        points: points,
        completed: {},
      );
      expect(progress.townLevel, level);
      expect(progress.onDay(DateTime(2028)).townLevel, level);
    }
  });
}
