import 'facility_layout.dart';
import 'package:flutter/material.dart';

import 'resident_collection.dart';

/// The pastry shop interior, reached from the shopping-street doorway.
class BakeryRoom extends StatefulWidget {
  const BakeryRoom({super.key, this.onResident, this.ownedResidents = const []});

  final List<TownResident> ownedResidents;

  static const backgroundAsset = 'assets/kotohogu/backaly_background_001.png';
  final Future<void> Function(TownResident)? onResident;

  @override
  State<BakeryRoom> createState() => _BakeryRoomState();
}

class _BakeryRoomState extends State<BakeryRoom> {
  bool _talking = false;

  Future<void> _talk(TownResident resident) async {
    if (_talking || widget.onResident == null) return;
    setState(() => _talking = true);
    try {
      await widget.onResident!(resident);
    } finally {
      if (mounted) setState(() => _talking = false);
    }
  }

  Widget _resident(TownResident resident) {
    final placement = facilityPlacement('bakery', resident.id);
    return Positioned(
      left: placement.x, top: placement.y,
      width: placement.size, height: placement.size,
      child: Semantics(
        button: widget.onResident != null,
        label: '${resident.label}のおはなし',
        child: Tooltip(
          message: resident.label,
          child: InkWell(
            key: ValueKey(resident == TownResident.c047_patisie
                ? 'bakery-patissier' : 'bakery-resident-${resident.id}'),
            onTap: _talking || widget.onResident == null ? null : () => _talk(resident),
            child: Image.asset(resident.idleAsset,
              fit: BoxFit.contain, excludeFromSemantics: true),
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
              width: 937,
              height: 1679,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Image.asset(
                      BakeryRoom.backgroundAsset,
                      key: const ValueKey('bakery-background'),
                      fit: BoxFit.cover,
                      excludeFromSemantics: true,
                    ),
                  ),
                  for (final resident in bakeryResidents(widget.ownedResidents))
                    _resident(resident),
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
                key: const ValueKey('bakery-return-shopping'),
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
