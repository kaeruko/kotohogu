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
  Iterable<String> ownedRemoteIds = const [],
}) {
  // Debug residents intentionally replace the standard cast.
  if (debugTownSelectionActive) return const [];
  final ownedIds = {
    ...owned.map((resident) => resident.id), ...ownedRemoteIds,
  };
  final builtInIds = TownResident.values.map((resident) => resident.id).toSet();
  final remoteOwned = ownedRemoteIds.toSet();
  final acquired = catalog.characters.where((resident) {
    if (!remoteOwned.contains(resident.id) ||
        builtInIds.contains(resident.id)) {
      return false;
    }
    if (!resident.walkInTown || resident.homeAreaId == 'salon') {
      return false;
    }
    return visit.destinationFor(
      residentId: resident.id,
      walkInTown: resident.walkInTown,
      homeAreaId: resident.homeAreaId,
      lifetimePoints: lifetimePoints,
    ) == area;
  }).toList();
  if (!debugRemotePreviewEnabled) return List.unmodifiable(acquired);
  final candidates = catalog.characters.where((resident) {
    if (!resident.walkInTown || resident.homeAreaId == 'salon' ||
        ownedIds.contains(resident.id)) {
      return false;
    }
    return visit.destinationFor(
      residentId: resident.id,
      walkInTown: resident.walkInTown,
      homeAreaId: resident.homeAreaId,
      lifetimePoints: lifetimePoints,
    ) == area;
  }).toList();
  final newResidents = candidates.where(
    (resident) => !builtInIds.contains(resident.id));
  final showcase = candidates.reversed.where(
    (resident) => builtInIds.contains(resident.id)).take(2);
  return List<RemoteResident>.unmodifiable(
      [...acquired, ...newResidents, ...showcase]);
}

/// Show a genuine first encounter once, then the resident's usual words.
RemoteDialogue residentGreeting(RemoteContentCatalog catalog, String residentId,
    Set<String> seenDialogues) {
  final first = catalog.linesFor(residentId).where(
      (line) => line.firstGreeting && !seenDialogues.contains(line.id)).toList();
  if (first.length > 1) {
    throw StateError('Multiple unread first greetings for $residentId');
  }
  return first.isEmpty ? visitorGreeting(catalog, residentId) : first.single;
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
