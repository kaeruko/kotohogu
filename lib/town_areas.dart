import 'marche.dart';
import 'resident_collection.dart';

/// Each neighborhood owns its residents and its independently sourced artwork.
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

/// Outdoor residents temporarily meet at the plaza until their assigned
/// neighborhood opens. Indoor residents (including salon staff) never move
/// outdoors. Unknown outdoor area IDs are errors, not implicit fallbacks.
TownArea? residentCurrentArea(
  TownResident resident,
  int lifetimePoints, {
  bool marcheOpen = false,
}) {
  // Indoor residents never participate in outdoor placement.
  if (!resident.walkInTown || resident.homeAreaId == 'salon') return null;
  // A story-triggered work location overrides Tonko's ordinary CMS home.
  if (marcheOpen && resident == tonkoMarcheOwner) return TownArea.plaza;
  final home = TownArea.fromId(resident.homeAreaId);
  return home.isUnlocked(lifetimePoints) ? home : TownArea.plaza;
}

/// Allocate each owned walker to exactly one currently accessible area.
/// The debug cast is deliberately different: it previews residents in their
/// original CMS-assigned area, even if that area has not opened yet.
List<TownResident> areaResidents(
  Iterable<TownResident> owned,
  TownArea area, {
  required int lifetimePoints,
  List<TownResident>? debugOverride,
  bool marcheOpen = false,
}) {
  final candidates = visibleTownResidents(owned, debugOverride: debugOverride);
  return List<TownResident>.unmodifiable(
    candidates.where((resident) {
      // Temporary preview selections keep the CMS-assigned home.
      if (debugOverride != null) {
        return resident.walkInTown && resident.homeAreaId == area.id;
      }
      return residentCurrentArea(
        resident, lifetimePoints, marcheOpen: marcheOpen) == area;
    }),
  );
}
