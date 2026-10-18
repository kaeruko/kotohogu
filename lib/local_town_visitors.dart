import 'local_content_preview.dart';
import 'resident_collection.dart';
import 'town_areas.dart';

/// Preview-only HTTP visitors. Never add unowned characters to normal play.
/// The caller must opt in explicitly from a debug-only control.
List<RemoteResident> localVisitorsForArea(
  RemoteContentCatalog catalog,
  TownArea area, {
  required int lifetimePoints,
  required TownVisit visit,
  required Iterable<TownResident> owned,
  bool debugTownSelectionActive = false,
  bool debugRemotePreviewEnabled = false,
}) {
  // Fail closed: even live CMS content must not make unowned visitors appear.
  if (!debugRemotePreviewEnabled || debugTownSelectionActive) return const [];
  final ownedIds = owned.map((resident) => resident.id).toSet();
  final builtInIds = TownResident.values.map((resident) => resident.id).toSet();
  final candidates = catalog.characters.where((resident) {
    // Salon residents belong inside, even when the CMS walking flag is true.
    if (!resident.walkInTown || resident.homeAreaId == 'salon' ||
        ownedIds.contains(resident.id)) {
      return false;
    }
    final current = visit.destinationFor(
      residentId: resident.id,
      walkInTown: resident.walkInTown,
      homeAreaId: resident.homeAreaId,
      lifetimePoints: lifetimePoints,
    );
    return current == area;
  }).toList();

  // Every truly new resident appears. Showcase two recent unowned built-ins
  // too, including a newly generated enum entry after a local Flutter rebuild.
  final newResidents = candidates.where(
    (resident) => !builtInIds.contains(resident.id),
  );
  final showcase = candidates.reversed.where(
    (resident) => builtInIds.contains(resident.id),
  ).take(2);
  return List<RemoteResident>.unmodifiable([...newResidents, ...showcase]);
}

RemoteDialogue visitorGreeting(RemoteContentCatalog catalog, String residentId) {
  final greetings = catalog.linesFor(residentId)
      .where((line) => line.conditionCount == 0 && !line.once)
      .toList();
  if (greetings.isEmpty) {
    throw StateError('No unconditional visitor greeting: $residentId');
  }
  greetings.sort((a, b) => b.priority.compareTo(a.priority));
  return greetings.first;
}
