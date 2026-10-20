import 'facility_config.g.dart';

/// Source-image coordinates, shared with the CMS placement preview.
class FacilityPlacement {
  const FacilityPlacement(this.residentId, this.x, this.y, this.size);
  final String residentId;
  final double x;
  final double y;
  final double size;
}

List<FacilityPlacement> facilityPlacements(String facilityId) {
  final rooms = facilityConfig['facilities'] as List;
  final room = rooms.singleWhere((r) => r['id'] == facilityId);
  final size = (room['spriteSize'] as num).toDouble();
  return List.unmodifiable([
    for (final row in room['placements'] as List)
      FacilityPlacement(row['residentId'] as String,
        (row['x'] as num).toDouble(), (row['y'] as num).toDouble(),
        size),
  ]);
}

FacilityPlacement facilityPlacement(String facilityId, String residentId) =>
    facilityPlacements(facilityId).singleWhere((p) => p.residentId == residentId);
