import 'facility_layout.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import 'resident_collection.dart';

/// An interior reached by tapping the door of the right-hand village house.
/// Route navigation preserves the selected village and resident positions.
/// The owner unlocks entry through gacha; room occupants are CMS placements.
/// The flower-arranging teacher now teaches at the community center.
class SalonRoom extends StatefulWidget {
  const SalonRoom({
    super.key,
    this.onResident,
    this.ownedResidents = const [],
    this.previewUnownedResidents = false,
  });

  static const backgroundAsset = 'assets/kotohogu/salon_background_001.jpg';
  static const host = TownResident.c035_beaty;

  /// Uses the same CMS-backed conversations and seen-ID tracking as town NPCs.
  final Future<void> Function(TownResident)? onResident;
  final List<TownResident> ownedResidents;
  /// Debug-only visual preview; does not grant ownership.
  final bool previewUnownedResidents;

  @override
  State<SalonRoom> createState() => _SalonRoomState();
}

class _SalonRoomState extends State<SalonRoom> {
  static const _frameDuration = Duration(milliseconds: 200);
  static const _cycleFrames = 40;
  Rect _stationFor(TownResident resident) {
    final placement = facilityPlacement('salon', resident.id);
    return Rect.fromLTWH(placement.x, placement.y, placement.size, placement.size);
  }
  Timer? _ticker;
  int _ticks = 0;
  bool _talking = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final enabled = TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context);
    if (enabled && _ticker == null) {
      _ticker = Timer.periodic(_frameDuration, (_) {
        if (mounted && !_talking) setState(() => _ticks++);
      });
    } else if (!enabled) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _spriteAsset(BuildContext context, TownResident resident, int index) {
    if (_talking ||
        MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      return resident.idleAsset;
    }
    // Offset the animation per resident to avoid synchronized steps.
    final frame = (_ticks + index * 5) % _cycleFrames;
    if (frame < 4) return resident.idleAsset;
    if (frame < 32) {
      return resident.walkAsset(WalkDirection.front, (frame - 4) % 4);
    }
    return resident.clapAssets[((frame - 32) ~/ 2) % 2];
  }

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

  Widget _salonResident(BuildContext context, TownResident resident, int index) {
    if (index >= facilityPlacements('salon').length) {
      throw StateError('Salon supports at most 7 visible residents');
    }
    final station = _stationFor(resident);
    return Positioned(
      left: station.left,
      top: station.top,
      width: station.width,
      height: station.height,
      child: Semantics(
        button: widget.onResident != null,
        label: '${resident.label}のおはなし',
        child: Tooltip(
          message: resident.label,
          child: InkWell(
            key: ValueKey('salon-resident-${resident.id}'),
            borderRadius: BorderRadius.circular(36),
            onTap: widget.onResident == null ? null : () => _talk(resident),
            child: Image.asset(
              _spriteAsset(context, resident, index),
              key: ValueKey('salon-sprite-${resident.id}'),
              fit: BoxFit.contain,
              gaplessPlayback: true,
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
              // Keep the salon artwork and NPC in the same coordinate space,
              // including on tall and narrow phone displays.
              width: 941,
              height: 1672,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Image.asset(
                      SalonRoom.backgroundAsset,
                      key: const ValueKey('salon-background'),
                      fit: BoxFit.cover,
                      excludeFromSemantics: true,
                    ),
                  ),
                  for (final (index, resident) in
                      salonResidents(
                        widget.ownedResidents,
                        previewUnowned: widget.previewUnownedResidents,
                      ).indexed)
                    _salonResident(context, resident, index),
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
                key: const ValueKey('salon-return-village'),
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back),
                label: const Text('里山にもどる'),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
