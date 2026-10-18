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
