import 'dart:math' as math;

import 'marche.dart';
import 'resident_collection.dart';

/// Each neighborhood owns its independently sourced artwork.
/// The user's selected area is UI-only; no progress save migration is required.
enum TownArea {
  // BEGIN CMS TOWN AREAS
  plaza("plaza", "中央ひろば", "みんなが集まるまちの中心。", 0, "assets/kotohogu/town_background_001.jpg", 768, 1376),
  park("park", "ふれあい公園", "お散歩やおしゃべりを楽しむ場所。", 90, "assets/kotohogu/park_background_001.png", 768, 1376),
  shopping("shopping", "ことほぎ商店街", "お店と仕事の話が聞こえてくる通り。", 180, "assets/kotohogu/street_background_001.png", 768, 1376),
  village("village", "のんびり里", "畑とおうちで、それぞれのペースで暮らす場所。", 300, "assets/kotohogu/village_background_001.png", 941, 1672),
  hospital("hospital", "びょういん", "せんせいがみんなを迎える、花に囲まれた動物病院。", 0, "assets/kotohogu/hospital_background_001.png", 768, 1376);
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

  bool isUnlocked(int lifetimePoints, {Iterable<TownResident> owned = const []}) =>
      this == TownArea.hospital
          ? owned.contains(TownResident.cat)
          : lifetimePoints >= unlockAt;

  static TownArea fromId(String id) => values.firstWhere(
    (area) => area.id == id,
    orElse: () => throw FormatException('Unknown town area ID: $id'),
  );
}

/// Areas counted in the town-page indicator, based solely on actual
/// lifetime-point unlocks. Debug navigation must not increase the total.
List<TownArea> unlockedTownAreas(int lifetimePoints,
    {Iterable<TownResident> owned = const []}) =>
    List<TownArea>.unmodifiable(
      TownArea.values.where((area) => area.isUnlocked(lifetimePoints, owned: owned)),
    );

/// The salon daughter joins her mother only on occasional shopping outings.
/// IDs and persisted gacha ownership remain unchanged.
const familyOutingMother = TownResident.c051_dog_aunt;
const familyOutingDaughter = TownResident.c050_nailist;

/// One in-memory outing, shared by rendering and conversation conditions.
/// Each walker draws once from the actually unlocked areas. New walkers can
/// join without redrawing existing destinations. Re-entering town creates a
/// new visit; area navigation, rebuilds and conversations keep this instance.
class TownVisit {
  TownVisit({math.Random? random, this.familyOutingOverride})
      : _random = random ?? math.Random();

  final math.Random _random;
  /// Deterministic override for tests. Production draws once per eligible visit.
  final bool? familyOutingOverride;
  final Map<String, TownArea> _destinations = {};
  bool? _familyOuting;
  final Map<String, int> _familyConversations = {};

  /// No save migration: each new visit has a 1-in-4 chance of a family outing
  /// once the shopping street is unlocked and both family members are owned.
  /// The result stays fixed across area changes, dialogue and rebuilds.
  bool isFamilyOuting(Iterable<TownResident> owned, int lifetimePoints) {
    if (_familyOuting != null) return _familyOuting!;
    final family = owned.toSet();
    if (!TownArea.shopping.isUnlocked(lifetimePoints) ||
        !family.contains(familyOutingMother) ||
        !family.contains(familyOutingDaughter)) {
      return false;
    }
    return _familyOuting = familyOutingOverride ?? _random.nextInt(4) == 0;
  }

  /// Dedicated two-voice CMS lines cycle independently for mother and daughter.
  String nextFamilyOutingDialogueId(TownResident speaker) {
    final options = switch (speaker) {
      familyOutingMother => const ['051_dog_aunt_020', '051_dog_aunt_021'],
      familyOutingDaughter => const ['050_nailist_028', '050_nailist_029'],
      _ => throw ArgumentError.value(speaker, 'speaker'),
    };
    final count = _familyConversations[speaker.id] ?? 0;
    _familyConversations[speaker.id] = count + 1;
    return options[count % options.length];
  }

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
    if (residentId == TownResident.cat.id) return TownArea.hospital;
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
  final familyOuting = debugOverride == null &&
      visit.isFamilyOuting(owned, lifetimePoints);
  return List<TownResident>.unmodifiable([
    for (final resident in candidates)
      if (!(familyOuting && resident == familyOutingMother) &&
          (debugOverride != null
              // Debug-only selections retain legacy area assignments.
              ? resident.walkInTown && resident.homeAreaId == area.id
              : residentCurrentArea(
                  resident, lifetimePoints, visit: visit,
                  marcheOpen: marcheOpen) == area))
        resident,
    if (familyOuting && area == TownArea.shopping)
      familyOutingMother,
    if (familyOuting && area == TownArea.shopping)
      familyOutingDaughter,
  ]);
}
