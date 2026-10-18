import 'package:flutter/foundation.dart' show kDebugMode;

/// Developer tools are available in local debug runs by default.
///
/// Signed TestFlight builds can opt in explicitly with:
/// --dart-define=KOTOHOGU_ENABLE_DEV_TOOLS=true
///
/// Never enable this flag in a build submitted to the App Store or Google Play:
/// it permits local mission resets, test currency grants and facility previews.
/// The hidden gesture is discoverability only, NOT authentication.
// Screenshot builds run in debug mode on Simulator, but should look like
// customer-facing releases. This flag is never set by production workflows.
const bool storeScreenshotMode =
    bool.fromEnvironment('KOTOHOGU_STORE_SCREENSHOTS', defaultValue: false);

const bool developerToolsAvailable =
    !storeScreenshotMode &&
    (kDebugMode ||
        bool.fromEnvironment('KOTOHOGU_ENABLE_DEV_TOOLS', defaultValue: false));

/// Session-only unlock sequence. The build flag, not this gesture, controls
/// whether signed releases even contain operational developer features.
class DeveloperMenuUnlockSequence {
  int _count = 0;
  DateTime? _firstTap;

  bool registerHistoryTap(DateTime now) {
    final start = _firstTap;
    if (start == null ||
        now.isBefore(start) ||
        now.difference(start) > const Duration(seconds: 8)) {
      _firstTap = now;
      _count = 1;
    } else {
      _count++;
    }
    return _count >= 7;
  }

  void reset() {
    _count = 0;
    _firstTap = null;
  }
}
