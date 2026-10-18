import 'marche.dart';
import 'progress.dart';
import 'resident_collection.dart';
import 'town_areas.dart';

/// Where a conversation was started. This determines which residents may
/// satisfy a `townTogether` dialogue condition.
enum ConversationSite { town, salon, roster }

/// One view of the saved game state shared by town rendering and dialogue.
///
/// No new save fields: facilities are derived from Progress, and outdoor
/// destinations come from the same in-memory visit used by the painted town.
/// A debug cast affects previews only, not the permanent facility unlock.
class TownRules {
  const TownRules(this.progress, {
    required this.visit,
    this.debugTownResidents,
  });

  final Progress progress;
  final TownVisit visit;
  final List<TownResident>? debugTownResidents;

  bool get marcheOpen => isMarcheOpen(progress);
  bool get salonUnlocked => isSalonUnlocked(progress.residents.owned);

  List<TownResident> outdoors(TownArea area) => areaResidents(
    progress.residents.owned,
    area,
    lifetimePoints: progress.points,
    visit: visit,
    debugOverride: debugTownResidents,
    marcheOpen: marcheOpen,
  );

  /// All speakers considered "together" for a particular conversation.
  ///
  /// The roster deliberately retains its original global semantics; only
  /// town conversations require co-location in the selected neighborhood.
  Set<String> conversationPeers(
    ConversationSite site, {
    TownArea? area,
    bool previewSalonUnowned = false,
  }) {
    if ((site == ConversationSite.town) != (area != null)) {
      throw ArgumentError('Town conversations require exactly one area');
    }
    if (previewSalonUnowned && site != ConversationSite.salon) {
      throw ArgumentError('Salon preview is only valid inside the salon');
    }
    final Iterable<TownResident> participants;
    switch (site) {
      case ConversationSite.town:
        participants = outdoors(area!);
      case ConversationSite.salon:
        participants = salonResidents(
          progress.residents.owned,
          previewUnowned: previewSalonUnowned,
        );
      case ConversationSite.roster:
        participants = visibleTownResidents(
          progress.residents.owned,
          debugOverride: debugTownResidents,
        );
    }
    return Set<String>.unmodifiable(participants.map((resident) => resident.id));
  }
}
