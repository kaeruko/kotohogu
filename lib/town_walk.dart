import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'resident_collection.dart';

/// A normalized, non-persistent position for a resident's gentle stroll.
@immutable
class TownWalkPose {
  const TownWalkPose({
    required this.x,
    required this.y,
    required this.direction,
    required this.frame,
  });

  final double x;
  final double y;
  /// Null means the resident is taking a break (idle sprite).
  final WalkDirection? direction;
  final int frame;
  bool get walking => direction != null;
}

/// A local strolling route, specified in background-relative coordinates.
/// The character's bottom-center foot anchor is offset by half its base sprite
/// size in TownScene; keep the route just outside the painted furniture.
/// "stay" renders an idle sprite, even when animations are enabled.
@immutable
class TownWalkRoute {
  const TownWalkRoute(this.x, this.y, {
    this.width = .02,
    this.height = .01,
    this.stay = false,
  });

  final double x;
  final double y;
  final double width;
  final double height;
  final bool stay;
}

/// Standing spots on the open floor of the clinic's upper two rooms.
/// Coordinates are relative to hospital_background_001.png and use the
/// same foot anchors as other town sprites, keeping furniture unobstructed.
const hospitalStaffRoutes = <String, TownWalkRoute>{
  '004_neko': TownWalkRoute(.20, .22, stay: true), // upper-left exam room
  '024_nurse': TownWalkRoute(.69, .22, stay: true), // upper-right treatment room
};

/// Favorite spots on the *playground version* of the park illustration.
/// Stable resident IDs, not displayed slot numbers, choose the favorite spot.
/// These are on the dirt paths next to equipment, not on top of the benches.
/// The routes can be refined without changing resident data or saved progress.
const parkResidentRoutes = <String, TownWalkRoute>{
  '002_usagi': TownWalkRoute(.39, .46, width: .020, height: .010), // slide
  '005_risu': TownWalkRoute(.30, .54, width: .025), // flowerbed/sign
  '026_farmer': TownWalkRoute(.45, .55, width: .020), // fountain
  '027_daydreamer': TownWalkRoute(.60, .63, stay: true), // right bench
  '037_tora': TownWalkRoute(.63, .45, width: .025), // swings
};

/// Spare places along the open central path for other park residents.
/// They are deliberately away from the equipment, shrine steps, river,
/// bins and foreground benches.
const _parkSpareRoutes = <TownWalkRoute>[
  TownWalkRoute(.43, .49),
  TownWalkRoute(.54, .53),
  TownWalkRoute(.36, .62),
  TownWalkRoute(.48, .69),
  TownWalkRoute(.55, .64),
  TownWalkRoute(.39, .57),
  TownWalkRoute(.56, .47),
  TownWalkRoute(.34, .69),
];

/// Returns a resident-specific favorite or a defined open-path position.
/// No implicit substitution takes place for invalid slot/count arguments.
TownWalkRoute parkWalkRoute(
  String residentId,
  int slot, {
  required int totalSlots,
}) {
  // Retain the same strict validation as the standard strolling route.
  townWalkOrigin(slot, totalSlots: totalSlots);
  final favorite = parkResidentRoutes[residentId];
  if (favorite != null) return favorite;
  if (totalSlots <= _parkSpareRoutes.length) {
    return _parkSpareRoutes[slot];
  }
  // Handle crowded/debug scenes without reusing one of eight coordinates.
  final columns = math.sqrt(totalSlots * 1.3).ceil();
  final rows = (totalSlots + columns - 1) ~/ columns;
  return TownWalkRoute(
    .32 + (columns == 1 ? 0 : (slot % columns) * .29 / (columns - 1)),
    .48 + (rows == 1 ? 0 : (slot ~/ columns) * .20 / (rows - 1)),
    width: .006,
    height: .004,
  );
}

/// The first eight positions retain the original arrangement (not a headcount
/// limit). Positions leave room for sprites in the clipped town viewport.
const townWalkSlots = <(double, double)>[
  (.10, .51),
  (.63, .49),
  (.33, .65),
  (.72, .73),
  (.03, .76),
  (.48, .47),
  (.28, .43),
  (.50, .76),
];

/// For nine or more residents, create unique grid origins rather than reusing
/// one of the first eight slots. All coordinates are image-relative.
(double, double) townWalkOrigin(int slot, {required int totalSlots}) {
  if (totalSlots <= 0) {
    throw RangeError.value(totalSlots, 'totalSlots', 'Must be positive');
  }
  if (slot < 0 || slot >= totalSlots) {
    throw RangeError.range(slot, 0, totalSlots - 1, 'slot');
  }
  if (totalSlots <= townWalkSlots.length) {
    return townWalkSlots[slot];
  }
  final columns = math.sqrt(totalSlots * 1.3).ceil();
  final rows = (totalSlots + columns - 1) ~/ columns;
  final col = slot % columns;
  final row = slot ~/ columns;
  return (
    .05 + (columns == 1 ? 0 : col * .69 / (columns - 1)),
    .40 + (rows == 1 ? 0 : row * .30 / (rows - 1)),
  );
}

const _walkStepMs = 150;
const _horizontalMs = 3000;
const _verticalMs = 1600;
const _restMs = 900;
const _walkCycleMs = 2 * _horizontalMs + 2 * _verticalMs + 4 * _restMs;

/// Deterministic, pause-inclusive 4-direction walk without saved game state.
TownWalkPose townWalkPose(
  int slot,
  Duration elapsed, {
  int? totalSlots,
  TownWalkRoute? route,
}) {
  final count = totalSlots ?? math.max(townWalkSlots.length, slot + 1);
  final defaultStart = townWalkOrigin(slot, totalSlots: count);
  if (route != null && (!route.x.isFinite || !route.y.isFinite ||
      !route.width.isFinite || !route.height.isFinite ||
      route.x < 0 || route.y < 0 ||
      route.width < 0 || route.height < 0 ||
      route.x + route.width > .86 || route.y + route.height > .82)) {
    throw RangeError('Town walking route must stay in the walkable scene');
  }
  final start = route == null ? defaultStart : (route.x, route.y);
  if (route?.stay == true) {
    return TownWalkPose(x: start.$1, y: start.$2,
        direction: null, frame: 0);
  }
  final dense = count > townWalkSlots.length;
  final width = route?.width ?? (dense
      ? math.min(.05, .35 / math.sqrt(count))
      : (slot.isEven ? .080 : .065));
  final height = route?.height ?? (dense
      ? math.min(.026, .20 / math.sqrt(count))
      : (slot.isEven ? .035 : .045));
  // Stagger characters to avoid a synchronized marching formation.
  var time = (elapsed.inMilliseconds + slot * 1640) % _walkCycleMs;
  var x = start.$1;
  var y = start.$2;
  final legs = <(int, double, double, WalkDirection)>[
    (_horizontalMs, width, 0, WalkDirection.right),
    (_verticalMs, 0, height, WalkDirection.front),
    (_horizontalMs, -width, 0, WalkDirection.left),
    (_verticalMs, 0, -height, WalkDirection.back),
  ];
  for (final leg in legs) {
    final duration = leg.$1;
    if (time < duration) {
      final fraction = time / duration;
      return TownWalkPose(
        x: x + leg.$2 * fraction,
        y: y + leg.$3 * fraction,
        direction: leg.$4,
        frame: (time ~/ _walkStepMs) % 4,
      );
    }
    time -= duration;
    x += leg.$2;
    y += leg.$3;
    if (time < _restMs) {
      return TownWalkPose(x: x, y: y, direction: null, frame: 0);
    }
    time -= _restMs;
  }
  throw StateError('Town walk cycle exceeded its duration.');
}


/// A brief sprint away from Yasuzo when he offers Oyasumi-kun farm work.
/// Only the pose changes: no new animation assets or persisted state.
TownWalkPose farmerScarePose(
  TownWalkPose start,
  Duration elapsed, {
  required bool fleeRight,
}) {
  const hesitationMs = 450;
  const sprintMs = 1350;
  final sprintElapsed =
      (elapsed.inMilliseconds - hesitationMs).clamp(0, sprintMs);
  final stride = .22 * sprintElapsed / sprintMs;
  final x = fleeRight
      ? (start.x + stride).clamp(.02, .82).toDouble()
      : (start.x - stride).clamp(.02, .82).toDouble();
  final running = sprintElapsed > 0 && sprintElapsed < sprintMs;
  return TownWalkPose(
    x: x,
    y: start.y,
    direction: running
        ? (fleeRight ? WalkDirection.right : WalkDirection.left)
        : null,
    frame: running ? (sprintElapsed ~/ 75) % 4 : 0,
  );
}
