import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:future_lift/progress.dart';
import 'package:future_lift/resident_collection.dart';
import 'package:future_lift/clap_characters.dart';
import 'package:future_lift/celebration.dart';
import 'package:future_lift/main.dart';
import 'package:future_lift/dialogue_engine.dart';
import 'package:future_lift/town.dart';
import 'package:future_lift/gacha_screen.dart';

import 'progress_test.dart' show MemoryStore;

class FixedRandom implements Random {
  FixedRandom(this.index);
  final int index;
  int calls = 0;
  @override
  int nextInt(int max) {
    calls++;
    return index;
  }

  @override
  bool nextBool() => throw UnimplementedError();
  @override
  double nextDouble() => throw UnimplementedError();
}

Progress funded({int points = 30}) => Progress(
  day: '2026-10-11',
  lastCompletedDay: '2026-10-11',
  points: points,
  completed: {},
  residents: ResidentCollection.initial(0),
);

void main() {
  test('spendable kotohogi stops at 999 without stopping lifetime progress', () {
    var progress = funded(points: 990);
    expect(progress.residents.availableKotohogi(progress.points), 990);

    progress = progress.complete(Mission.strength);
    expect(progress.points, 1000);
    expect(progress.residents.availableKotohogi(progress.points), 999);
    expect(progress.residents.expiredKotohogi, 1);
    expect(progress.completed, contains(Mission.strength));
    expect(progress.townLevel, 3);

    progress = progress.complete(Mission.outside);
    expect(progress.points, 1010);
    expect(progress.residents.availableKotohogi(progress.points), 999);
    expect(progress.residents.expiredKotohogi, 11);
    expect(progress.residents.tickets(progress.points), 33);

    final persisted = Progress.decode(progress.encode(), expectedVersion: 5);
    expect(persisted.points, 1010);
    expect(persisted.residents.expiredKotohogi, 11);
    expect(persisted.residents.availableKotohogi(persisted.points), 999);
    expect(persisted.completed, {Mission.strength, Mission.outside});

    // Spending restores room in the wallet; the next mission can earn again.
    progress = persisted.acquireResident(TownResident.shiba);
    expect(progress.residents.availableKotohogi(progress.points), 969);
    progress = progress.complete(Mission.conversation);
    expect(progress.points, 1020);
    expect(progress.residents.availableKotohogi(progress.points), 979);
    expect(Progress.decode(progress.encode()).residents.availableKotohogi(
      progress.points,
    ), 979);
  });

  test('legacy wallets and invalid expired balances are handled safely', () {
    final old = funded(points: 1000);
    final oldData = jsonDecode(old.encode()) as Map<String, dynamic>;
    final restored = Progress.decode(jsonEncode(oldData));
    expect(restored.points, 1000);
    // Never truncate a pre-existing wallet just because the app updated.
    expect(restored.residents.availableKotohogi(restored.points), 1000);
    expect(restored.residents.expiredKotohogi, 0);

    final next = restored.complete(Mission.strength);
    expect(next.residents.availableKotohogi(next.points), 999);

    final ledger = Map<String, dynamic>.from(oldData['residents'] as Map);
    for (final bad in [-1, '2', 1001]) {
      final invalid = {
        ...oldData,
        'residents': {...ledger, 'expiredKotohogi': bad},
      };
      expect(() => Progress.decode(jsonEncode(invalid)),
          throwsFormatException);
    }
  });

  test('tickets every 30 new points; duplicates do not add town residents', () {
    var progress = Progress.empty(DateTime(2026, 10, 11));
    expect(progress.residents.owned, [TownResident.shiba, TownResident.rabbit]);
    progress = progress.complete(Mission.strength).complete(Mission.outside);
    expect(progress.residents.tickets(progress.points), 0);
    progress = progress.complete(Mission.conversation);
    expect(progress.residents.tickets(progress.points), 1);
    final duplicate = progress.acquireResident(TownResident.shiba);
    expect(duplicate.residents.owned.length, 2);
    expect(duplicate.residents.counts['001_shiba'], 2);
    expect(duplicate.points, 30);
    expect(duplicate.residents.tickets(30), 0);
    expect(
      () => duplicate.acquireResident(TownResident.penguin),
      throwsStateError,
    );
    final restored = Progress.decode(duplicate.encode());
    expect(restored.residents.counts, duplicate.residents.counts);
    for (final preserved in [
      restored.onDay(DateTime(2026, 10, 12)),
      restored.clearHistory(),
      restored.resetMissionsForDebug(),
    ]) {
      expect(preserved.residents.encode(), restored.residents.encode());
    }
  });

  test('debug grant is separate, persistent and consumed by ordinary draws', () {
    final original = Progress.empty(DateTime(2026, 10, 11));
    final granted = original.grantTicketsForDebug(11);
    expect(granted.points, 0);
    expect(granted.history, isEmpty);
    expect(granted.completed, isEmpty);
    expect(granted.residents.earnedTickets(0), 0);
    expect(granted.residents.debugTicketsGranted, 11);
    expect(granted.residents.tickets(0), 11);
    final restored = Progress.decode(granted.encode(), expectedVersion: 5);
    expect(restored.residents.tickets(0), 11);
    final after = restored.acquireResident(TownResident.cat);
    expect(after.residents.tickets(0), 10);
    expect(after.residents.debugTicketsGranted, 11);
    expect(
      after.onDay(DateTime(2026, 10, 12)).residents.tickets(0),
      10,
    );
    expect(Progress.decode(after.encode()).residents.tickets(0), 10);
    expect(() => original.grantTicketsForDebug(0), throwsArgumentError);
    expect(() => original.grantTicketsForDebug(-1), throwsArgumentError);
  });

  test('legacy ticket records remain valid; malformed bonus fails fast', () {
    final raw = jsonDecode(funded().encode()) as Map<String, dynamic>;
    final record = raw['residents'] as Map<String, dynamic>;
    expect(Progress.decode(jsonEncode(raw)).residents.debugTicketsGranted, 0);
    for (final invalid in [0, -2, 1.5, '10', null]) {
      expect(
        () => Progress.decode(jsonEncode({
          ...raw,
          'residents': {...record, 'debugTicketsGranted': invalid},
        })),
        throwsFormatException,
      );
    }
    expect(
      () => Progress.decode(jsonEncode({
        ...raw,
        'residents': {...record, 'notATicketField': 2},
      })),
      throwsFormatException,
    );
  });

  test('debug controller saves once, rejects concurrent grants and keeps errors', () async {
    final store = MemoryStore();
    final controller = ProgressController(
      store,
      clock: () => DateTime(2026, 10, 11),
    );
    await controller.initialize();
    store.gate = Completer<void>();
    final first = controller.grantTicketsForDebug(1);
    expect(controller.busy, isTrue);
    expect(await controller.grantTicketsForDebug(10), isFalse);
    expect(controller.progress!.residents.tickets(0), 0);
    store.gate!.complete();
    expect(await first, isTrue);
    expect(store.writes, 1);
    expect(controller.progress!.residents.tickets(0), 1);
    expect(Progress.decode(store.raw!).residents.tickets(0), 1);

    final error = StateError('debug ticket save failed');
    store.saveError = error;
    expect(await controller.grantTicketsForDebug(10), isFalse);
    expect(controller.failure!.error, same(error));
    expect(controller.failure!.stackTrace.toString(), isNotEmpty);
    expect(controller.progress!.residents.tickets(0), 1);
    expect(await controller.grantTicketsForDebug(1), isFalse);
  });

  test('all registered residents never stop draws or ticket earning', () {
    // One ticket for each new resident plus one for the repeat draw.
    final drawPoints = (TownResident.values.length - 1) * 30;
    var progress = funded(points: drawPoints);
    for (final resident in TownResident.values.skip(2)) {
      progress = progress.acquireResident(resident);
    }
    expect(progress.residents.owned.length, TownResident.values.length);
    progress = progress.acquireResident(TownResident.penguin);
    expect(progress.residents.owned.length, TownResident.values.length);
    expect(progress.residents.counts['003_penguin'], 2);
    // The repeated penguin draw also costs one ticket.
    expect(progress.residents.tickets(drawPoints), 0);
    progress = progress
        .complete(Mission.strength)
        .complete(Mission.outside)
        .complete(Mission.conversation);
    expect(progress.residents.tickets(drawPoints + 30), 1);
    expect(Progress.decode(progress.encode()).residents.owned.length,
        TownResident.values.length);
  });

  test(
    'v3 migration preserves points and starts tickets at migration baseline',
    () {
      final raw =
          jsonDecode(funded(points: 100).encode()) as Map<String, dynamic>;
      raw['version'] = 3;
      raw.remove('residents');
      raw.remove('missionCounts');
      raw.remove('seenDialogues');
      final migrated = Progress.decode(jsonEncode(raw), expectedVersion: 3);
      expect(migrated.points, 100);
      expect(migrated.residents.baselinePoints, 100);
      expect(migrated.residents.tickets(100), 0);
      final next = migrated
          .complete(Mission.strength)
          .complete(Mission.outside)
          .complete(Mission.conversation);
      expect(next.residents.tickets(130), 1);
      expect(Progress.decode(next.encode(), expectedVersion: 5).points, 130);
    },
  );

  test(
    'bad resident IDs, counts, missing fields and overspent tickets fail',
    () {
      final raw = jsonDecode(funded().encode()) as Map<String, dynamic>;
      for (final invalid in [
        null,
        {
          'baselinePoints': 40,
          'counts': {'001_shiba': 1, '002_usagi': 1},
        },
        {
          'baselinePoints': 0,
          'counts': {'001_shiba': 1, '002_usagi': 1, 'unknown': 1},
        },
        {
          'baselinePoints': 0,
          'counts': {'001_shiba': 1, '002_usagi': 0},
        },
        {
          'baselinePoints': 0,
          'counts': {'001_shiba': 1, '002_usagi': 1.0},
        },
        {
          'baselinePoints': 0,
          'counts': {'001_shiba': 3, '002_usagi': 1},
        },
        {
          'baselinePoints': 0,
          'counts': {'001_shiba': 1},
        },
      ]) {
        expect(
          () => Progress.decode(jsonEncode({...raw, 'residents': invalid})),
          throwsFormatException,
        );
      }
      raw.remove('residents');
      expect(() => Progress.decode(jsonEncode(raw)), throwsFormatException);
    },
  );

  test(
    'draw commits once before publishing; saving failure retains diagnostics',
    () async {
      final random = FixedRandom(2);
      final store = MemoryStore()..raw = funded().encode();
      final controller = ProgressController(
        store,
        clock: () => DateTime(2026, 10, 11),
        random: random,
      );
      await controller.initialize();
      store.gate = Completer<void>();
      final draw = controller.drawResident();
      expect(controller.progress!.residents.owned.length, 2);
      expect(await controller.drawResident(), isNull);
      store.gate!.complete();
      expect(await draw, TownResident.penguin);
      expect(random.calls, 1);
      expect(store.writes, 1);
      expect(controller.progress!.residents.owned.length, 3);
      expect(Progress.decode(store.raw!).residents.owned.length, 3);

      final error = StateError('disk full');
      final failedStore = MemoryStore()
        ..raw = funded().encode()
        ..saveError = error;
      final failed = ProgressController(
        failedStore,
        clock: () => DateTime(2026, 10, 11),
        random: random,
      );
      await failed.initialize();
      expect(await failed.drawResident(), isNull);
      expect(failed.failure!.error, same(error));
      expect(failed.failure!.stackTrace.toString(), isNotEmpty);
      expect(failed.progress!.residents.tickets(30), 1);
      expect(failed.progress!.residents.owned.length, 2);
      expect(await failed.drawResident(), isNull);
      expect(failedStore.writes, 1);
    },
  );

  test('ten tickets give eleven residents with one persisted bonus', () {
    final initial = Progress.empty(DateTime(2026, 10, 11))
        .grantTicketsForDebug(11);
    final batch = List<TownResident>.filled(11, TownResident.cat);
    final next = initial.acquireResidentsTenPlusOne(batch);
    expect(next.residents.tickets(0), 1);
    expect(next.residents.bonusDraws, 1);
    expect(next.residents.counts[TownResident.cat.id], 11);
    final restored = Progress.decode(next.encode());
    expect(restored.residents.tickets(0), 1);
    expect(restored.residents.bonusDraws, 1);
    expect(restored.residents.counts[TownResident.cat.id], 11);
    expect(restored.residents.owned,
        [TownResident.shiba, TownResident.rabbit, TownResident.cat]);
    final single = restored.acquireResident(TownResident.cat);
    expect(single.residents.tickets(0), 0);
    expect(single.residents.bonusDraws, 1);
    expect(() => initial.acquireResidentsTenPlusOne(batch.take(10).toList()),
        throwsArgumentError);
    expect(
      () => Progress.empty(DateTime(2026, 10, 11))
          .grantTicketsForDebug(9).acquireResidentsTenPlusOne(batch),
      throwsStateError,
    );
    final raw = jsonDecode(next.encode()) as Map<String, dynamic>;
    for (final invalid in [-1, 0, 2, '1', null]) {
      final residentRecord = raw['residents'] as Map<String, dynamic>;
      expect(() => Progress.decode(jsonEncode({
        ...raw,
        'residents': {...residentRecord, 'bonusDraws': invalid},
      })), throwsFormatException);
    }
  });

  test('bundle draw persists once, rejects concurrent taps and save errors', () async {
    final random = FixedRandom(3);
    final store = MemoryStore()
      ..raw = Progress.empty(DateTime(2026, 10, 11))
          .grantTicketsForDebug(10).encode();
    final controller = ProgressController(store,
      clock: () => DateTime(2026, 10, 11), random: random);
    await controller.initialize();
    store.gate = Completer<void>();
    final pending = controller.drawResidentsTenPlusOne();
    expect(controller.busy, isTrue);
    expect(await controller.drawResidentsTenPlusOne(), isNull);
    expect(controller.progress!.residents.tickets(0), 10);
    store.gate!.complete();
    final results = await pending;
    expect(results, List<TownResident>.filled(11, TownResident.cat));
    expect(random.calls, 11);
    expect(store.writes, 1);
    expect(controller.progress!.residents.tickets(0), 0);
    expect(controller.progress!.residents.bonusDraws, 1);
    expect(Progress.decode(store.raw!).residents.bonusDraws, 1);

    final failure = StateError('bundle storage is unavailable');
    final failedStore = MemoryStore()
      ..raw = Progress.empty(DateTime(2026, 10, 11))
          .grantTicketsForDebug(10).encode()
      ..saveError = failure;
    final failed = ProgressController(failedStore,
      clock: () => DateTime(2026, 10, 11), random: FixedRandom(3));
    await failed.initialize();
    expect(await failed.drawResidentsTenPlusOne(), isNull);
    expect(failed.failure!.error, same(failure));
    expect(failed.progress!.residents.tickets(0), 10);
    expect(failed.progress!.residents.bonusDraws, 0);
    expect(await failed.drawResidentsTenPlusOne(), isNull);
  });

  testWidgets('consultation hall does not offer the legacy bundle action',
      (tester) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = MemoryStore()
      ..raw = Progress.empty(DateTime(2026, 10, 11))
          .grantTicketsForDebug(10).encode();
    final controller = ProgressController(store,
      clock: () => DateTime(2026, 10, 11),
      random: FixedRandom(3));
    await controller.initialize();
    await tester.pumpWidget(MaterialApp(
      home: GachaScreen(controller: controller),
    ));
    await tester.pump();
    expect(find.byKey(const ValueKey('gacha-shrine-bg')), findsOneWidget);
    expect(find.byKey(const ValueKey('gacha-scroll-stand')), findsNothing);
    expect(find.byKey(const ValueKey('gacha-draw-ten')), findsNothing);
    expect(find.byKey(const ValueKey('gacha-draw-one')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'new resident appears in town, applause and restored collection',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final store = MemoryStore()..raw = funded().encode();
      final controller = ProgressController(
        store,
        clock: () => DateTime(2026, 10, 11),
        random: FixedRandom(2),
      );
      final catalog = await tester.runAsync(DialogueCatalog.load);
      if (catalog == null) throw StateError('Dialogue asset did not load');
      await tester.pumpWidget(FutureLiftApp(
        controller: controller,
        dialogueCatalog: catalog,
        enableTutorial: false,
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('footer-town')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TownScene>(find.byType(TownScene)).residents.length,
        2,
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('draw-resident')),
        180,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('draw-resident')));
      await tester.pumpAndSettle();
      // The home button now performs the one draw automatically, rather than
      // requiring a second tap on the consultation screen.
      expect(find.byKey(const ValueKey('gacha-shrine-bg')), findsOneWidget);
      expect(find.byKey(const ValueKey('consultation-walker-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('gacha-stage-resident')), findsOneWidget);
      expect(find.byKey(const ValueKey('resident-arrival-banner')), findsOneWidget);
      expect(find.byKey(const ValueKey('gacha-draw-one')), findsNothing);
      expect(
        tester.widget<Semantics>(
          find.byKey(const ValueKey('gacha-result')),
        ).properties.label,
        '${TownResident.penguin.label}が、まちにやってきました！',
      );
      expect(controller.progress!.residents.tickets(30), 0);
      await tester.tap(find.byKey(const ValueKey('consultation-town-back')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byType(TownScene), -180);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TownScene>(find.byType(TownScene)).residents.length,
        3,
      );
      await tester.tap(find.byKey(const ValueKey('footer-missions')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('complete-strength')),
        180,
      );
      await tester.tap(find.byKey(const ValueKey('complete-strength')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.byType(Celebration), findsOneWidget);
      expect(
        tester.widget<ClapCharacters>(find.byType(ClapCharacters)).residents,
        [TownResident.shiba, TownResident.rabbit, TownResident.penguin],
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      expect(Progress.decode(store.raw!).residents.owned.length, 3);
    },
  );
}
