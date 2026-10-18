import 'package:flutter/foundation.dart' show kDebugMode;

/// Developer tools are available in local debug runs by default.
///
/// Signed TestFlight builds can opt in explicitly with:
/// --dart-define=KOTOHOGU_ENABLE_DEV_TOOLS=true
///
/// Never enable this flag in a build submitted to the App Store or Google Play:
/// it permits local mission resets, test currency grants and facility previews.
/// The hidden gesture is discoverability only, NOT authentication.
const bool developerToolsAvailable =
    kDebugMode ||
    bool.fromEnvironment('KOTOHOGU_ENABLE_DEV_TOOLS', defaultValue: false);

/// Session-only unlock sequence. The build flag, not this gesture, controls
/// whether signed releases even contain operational developer features.
class DeveloperMenuUnlockSequence {
  int _count = 0;
  DateTime? _lastTap;

  bool registerHistoryTap(DateTime now) {
    final previous = _lastTap;
    if (previous == null ||
        now.isBefore(previous) ||
        now.difference(previous) > const Duration(seconds: 8)) {
      _count = 1;
    } else {
      _count++;
    }
    _lastTap = now;
    return _count >= 7;
  }

  void reset() {
    _count = 0;
    _lastTap = null;
  }
}
