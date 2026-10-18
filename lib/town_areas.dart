import 'dart:math' as math;

import 'marche.dart';
import 'resident_collection.dart';

/// Each neighborhood owns its independently sourced artwork.
/// The user's selected area is UI-only; no progress save migration is required.
enum TownArea {
  // BEGIN CMS TOWN AREAS
  plaza("plaza", "中央ひろば", "みんなが集まるまちの中心。", 0, "assets/kotohogu/town_background_001.jpg", 768, 1376),
  park("park", "ふれあい公園", "お散歩やおしゃべりを楽しむ場所。", 90, "assets/kotohogu/park_background_001.png", 937, 1679),
  shopping("shopping", "ことほぎ商店街", "お店と仕事の話が聞こえてくる通り。", 180, "assets/kotohogu/street_background_001.png", 937, 1679),
  village("village", "のんびり里", "畑とおうちで、それぞれのペースで暮らす場所。", 300, "assets/kotohogu/village_background_001.png", 941, 1672);
  // END CMS TOWN AREAS

  const TownArea(this.id, this.label, this.description, this.unlockAt,
      this.backgroundAsset, this.sourceWidth, this.sourceHeight);

  final String id;
  final String label;
  final String description;
  /// Earned lifetime mission points, never the spendable currency balance.
  final int unlockAt;
  /// No fallback to another area's artwork when this is null.
  final String? backgroundAsset;
  /// Intrinsic pixels for the matching background asset, not a shared canvas.
  /// The artwork and its walkers must share this source coordinate system.
  final int? sourceWidth;
  final int? sourceHeight;

  bool isUnlocked(int lifetimePoints) => lifetimePoints >= unlockAt;

  static TownArea fromId(String id) => values.firstWhere(
    (area) => area.id == id,
    orElse: () => throw FormatException('Unknown town area ID: $id'),
  );
}

/// Areas counted in the town-page indicator, based solely on actual
/// lifetime-point unlocks. Debug navigation must not increase the total.
List<TownArea> unlockedTownAreas(int lifetimePoints) =>
    List<TownArea>.unmodifiable(
      TownArea.values.where((area) => area.isUnlocked(lifetimePoints)),
    );

/// One in-memory outing, shared by rendering and conversation conditions.
/// Each walker draws once from the actually unlocked areas. New walkers can
/// join without redrawing existing destinations. Re-entering town creates a
/// new visit; area navigation, rebuilds and conversations keep this instance.
class TownVisit {
  TownVisit({math.Random? random}) : _random = random ?? math.Random();

  final math.Random _random;
  final Map<String, TownArea> _destinations = {};

  TownArea? destinationFor({
    required String residentId,
    required bool walkInTown,
    required String homeAreaId,
    required int lifetimePoints,
    bool marcheOpen = false,
  }) {
    if (residentId.isEmpty) throw ArgumentError('Resident ID must not be empty');
    if (lifetimePoints < 0) {
      throw RangeError.value(lifetimePoints, 'lifetimePoints', 'Must be >= 0');
    }
    if (homeAreaId == 'salon') return null;
    // Legacy outdoor home IDs are validated for compatibility, but do not
    // constrain or weight random outings. Only 'salon' means indoor-only.
    TownArea.fromId(homeAreaId);
    if (!walkInTown) return null;
    if (marcheOpen && residentId == tonkoMarcheOwner.id) {
      return TownArea.plaza;
    }
    final destination = _destinations.putIfAbsent(residentId, () {
      final unlocked = unlockedTownAreas(lifetimePoints);
      if (unlocked.isEmpty) throw StateError('No unlocked town area');
      return unlocked[_random.nextInt(unlocked.length)];
    });
    if (!destination.isUnlocked(lifetimePoints)) {
      throw StateError(
        'Town visit destination is locked: $residentId, '
        '${destination.id}, lifetimePoints=$lifetimePoints',
      );
    }
    return destination;
  }
}

/// Indoor residents never move outdoors; an open stall fixes Tonko at work.
TownArea? residentCurrentArea(
  TownResident resident,
  int lifetimePoints, {
  required TownVisit visit,
  bool marcheOpen = false,
}) => visit.destinationFor(
  residentId: resident.id,
  walkInTown: resident.walkInTown,
  homeAreaId: resident.homeAreaId,
  lifetimePoints: lifetimePoints,
  marcheOpen: marcheOpen,
);

/// Allocate each owned walker to exactly one currently accessible area.
/// The debug cast is deliberately different: it previews residents in their
/// legacy catalog area for deterministic manual preview, even when locked.
List<TownResident> areaResidents(
  Iterable<TownResident> owned,
  TownArea area, {
  required int lifetimePoints,
  required TownVisit visit,
  List<TownResident>? debugOverride,
  bool marcheOpen = false,
}) {
  final candidates = visibleTownResidents(owned, debugOverride: debugOverride);
  return List<TownResident>.unmodifiable(
    candidates.where((resident) {
      // Debug-only selections retain legacy area assignments for old tests.
      if (debugOverride != null) {
        return resident.walkInTown && resident.homeAreaId == area.id;
      }
      return residentCurrentArea(
        resident, lifetimePoints, visit: visit, marcheOpen: marcheOpen) == area;
    }),
  );
}
