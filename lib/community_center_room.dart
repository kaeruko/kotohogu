import 'package:flutter/material.dart';

import 'facility_layout.dart';
import 'resident_collection.dart';

/// The public community center, reached from the shopping street after
/// earning 240 lifetime kotohogi points. The resident placements follow the
/// uploaded 941x1672 artwork, not the screen's pixel coordinates.
class CommunityCenterRoom extends StatefulWidget {
  const CommunityCenterRoom({super.key, this.onResident});

  static const backgroundAsset =
      'assets/kotohogu/community_center_background_001.png';

  final Future<void> Function(TownResident)? onResident;

  @override
  State<CommunityCenterRoom> createState() => _CommunityCenterRoomState();
}

class _CommunityCenterRoomState extends State<CommunityCenterRoom> {
  bool _talking = false;

  Future<void> _talk(TownResident resident) async {
    final callback = widget.onResident;
    if (callback == null || _talking) return;
    setState(() => _talking = true);
    try {
      await callback(resident);
    } finally {
      if (mounted) setState(() => _talking = false);
    }
  }

  Widget _instructor(TownResident resident) {
    final station = facilityPlacement('community_center', resident.id);
    return Positioned(
      left: station.x,
      top: station.y,
      width: station.size,
      height: station.size,
      child: Semantics(
        button: widget.onResident != null,
        label: '${resident.label}のおはなし',
        child: Tooltip(
          message: resident.label,
          child: InkWell(
            key: ValueKey('community-center-resident-${resident.id}'),
            onTap: _talking || widget.onResident == null
                ? null : () => _talk(resident),
            child: Image.asset(
              resident.idleAsset,
              fit: BoxFit.contain,
              excludeFromSemantics: true,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFFFF3DC),
    body: Stack(
      fit: StackFit.expand,
      children: [
        ClipRect(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: 941,
              height: 1672,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Image.asset(
                      CommunityCenterRoom.backgroundAsset,
                      key: const ValueKey('community-center-background'),
                      fit: BoxFit.cover,
                      excludeFromSemantics: true,
                    ),
                  ),
                  for (final resident in communityCenterResidents())
                    _instructor(resident),
                ],
              ),
            ),
          ),
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: FilledButton.tonalIcon(
                key: const ValueKey('community-center-return-shopping'),
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back),
                label: const Text('商店街にもどる'),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
