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
        '01_shiba': 1,
        '02_rabbit': 1,
        '03_penguin': 1,
        '04_cat': 1,
        '05_squirrel': 1,
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
  await target.writeAsString('$message\n', flush: true);
  debugPrint('Kotohogu screenshot: $message; marker=${target.path}');
}

Future<void> _writeReadyFile(String page) async {
  // Wait for assets and the first frame to settle, not just process launch.
  await Future<void>.delayed(const Duration(seconds: 4));
  await _writeCaptureStatus('ready:$page');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!storeScreenshotMode) {
    throw StateError('Screenshot entrypoint requires '
        '--dart-define=KOTOHOGU_STORE_SCREENSHOTS=true');
  }

  // simctl launch passes child environment variables without recompiling.
  final page = Platform.environment['KOTOHOGU_CAPTURE_SCREEN'];
  await _writeCaptureStatus('booting:${page ?? "<missing>"}');
  final selectedPage = screenshotPageIndex(page);
  final now = DateTime.now().toLocal();
  final controller = ProgressController(
    _ScreenshotStore(buildStoreScreenshotProgress(now)),
    clock: () => now,
    random: math.Random(7),
  );
  await controller.initialize();

  runApp(application.FutureLiftApp(
    controller: controller,
    enableTutorial: false,
    initialPage: selectedPage,
    townRandom: math.Random(7),
    // No network loader: screenshots work offline and never include errors
    // from Google Drive / CloudFront or the user's private save file.
  ));
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_writeReadyFile(page!));
  });
}
