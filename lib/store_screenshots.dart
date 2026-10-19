// A separate, simulator-only entrypoint for App Store screenshots.
// Normal iOS and Android release builds always start from lib/main.dart.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'dev_tools.dart';
import 'main.dart' as application;
import 'progress.dart';
import 'resident_collection.dart';

const screenshotPageNames = <String>['home', 'missions', 'town', 'history'];

int screenshotPageIndex(String? name) {
  final index = screenshotPageNames.indexOf(name ?? '');
  if (index < 0) {
    throw ArgumentError.value(name, 'KOTOHOGU_CAPTURE_SCREEN',
        'Expected one of: home, missions, town, history');
  }
  return index;
}

/// Example activity data for screenshots; never read or write real user saves.
Progress buildStoreScreenshotProgress(DateTime now) {
  String day(int offset) => localDay(
        DateTime(now.year, now.month, now.day - offset, 12),
      );

  return Progress(
    day: day(0),
    lastCompletedDay: day(0),
    points: 240,
    residents: ResidentCollection(
      baselinePoints: 0,
      counts: const {
        '001_shiba': 1,
        '002_usagi': 1,
        '003_penguin': 1,
        '004_neko': 1,
        '005_risu': 1,
        '009_chef': 1,
        '032_miner': 1,
        '026_farmer': 1,
      },
    ),
    completed: const {Mission.outside, Mission.conversation, Mission.food},
    weeklyCompleted: const {Mission.weeklyTogether},
    monthlyCompleted: const {Mission.monthlyHabit},
    history: {
      day(0): {Mission.outside, Mission.conversation, Mission.food},
      day(1): {Mission.strength, Mission.hobby},
      day(3): {Mission.outside, Mission.movement},
      day(7): {Mission.food, Mission.conversation},
      day(15): {Mission.outside, Mission.sittingBreak},
    },
    seenDialogues: const {'tutorial_kotohogisu_v1'},
  );
}

class _ScreenshotStore implements ProgressStore {
  _ScreenshotStore(this._progress);
  Progress _progress;

  @override
  Future<Progress?> load() async => _progress;

  @override
  Future<void> save(Progress progress) async {
    _progress = progress;
  }
}

File get _captureStatusFile {
  // On iOS, HOME is the application's data container. Directory.systemTemp
  // can point to a different simulator-wide temporary directory, which the
  // Mac host cannot find with simctl get_app_container.
  final home = Platform.environment['HOME'];
  final root = home == null || home.isEmpty ? Directory.systemTemp.path : '$home/tmp';
  return File('$root/kotohogu-store-ready.txt');
}

Future<void> _writeCaptureStatus(String message) async {
  final target = _captureStatusFile;
  await target.parent.create(recursive: true);
  // An atomic rename prevents the host from reading an empty file midway
  // through writeAsString (observed on iOS 26 Simulator).
  final pending = File('${target.path}.pending');
  await pending.writeAsString('$message\n', flush: true);
  await pending.rename(target.path);
  debugPrint('Kotohogu screenshot: $message; marker=${target.path}');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!storeScreenshotMode) {
    throw StateError('Screenshot entrypoint requires '
        '--dart-define=KOTOHOGU_STORE_SCREENSHOTS=true');
  }

  // iOS 26 Simulator did not pass SIMCTL_CHILD_* variables to Dart.
  // Instead, the host writes the requested page in the app's data container.
  // This works without a debug connection or rebuilding between screens.
  final requests = File('${_captureStatusFile.parent.path}/kotohogu-capture-page.txt');
  await _writeCaptureStatus('waiting');
  final now = DateTime.now().toLocal();
  final controller = ProgressController(
    _ScreenshotStore(buildStoreScreenshotProgress(now)),
    clock: () => now,
    random: math.Random(7),
  );
  await controller.initialize();

  String? previousPage;
  while (true) {
    final requested = await requests.exists() ?
        (await requests.readAsString()).trim() : '';
    if (requested.isNotEmpty && requested != previousPage) {
      try {
        final pageNumber = screenshotPageIndex(requested);
        previousPage = requested;
        await _writeCaptureStatus('booting:$requested');
        // Replacing the keyed root recreates the home state with exactly the
        // requested tab selected. No screenshots or state are persisted.
        runApp(application.FutureLiftApp(
          key: ValueKey('store-screenshot-$requested'),
          controller: controller,
          enableTutorial: false,
          initialPage: pageNumber,
          townRandom: math.Random(7),
        ));
        await WidgetsBinding.instance.endOfFrame;
        await Future<void>.delayed(const Duration(seconds: 4));
        await _writeCaptureStatus('ready:$requested');
      } catch (error, stack) {
        await _writeCaptureStatus('error:$error');
        debugPrint('Screenshot render failed: $error\n$stack');
        rethrow;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
}
