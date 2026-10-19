import 'package:flutter/material.dart';

import 'resident_collection.dart';

/// The pastry shop interior, reached from the shopping-street doorway.
class BakeryRoom extends StatefulWidget {
  const BakeryRoom({super.key, this.onResident});

  static const backgroundAsset = 'assets/kotohogu/backaly_background_001.png';
  final Future<void> Function(TownResident)? onResident;

  @override
  State<BakeryRoom> createState() => _BakeryRoomState();
}

class _BakeryRoomState extends State<BakeryRoom> {
  bool _talking = false;

  Future<void> _talk() async {
    if (_talking || widget.onResident == null) return;
    setState(() => _talking = true);
    try {
      await widget.onResident!(TownResident.c047_patisie);
    } finally {
      if (mounted) setState(() => _talking = false);
    }
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
                  Positioned(
                    left: 300,
                    top: 760,
                    width: 235,
                    height: 235,
                    child: Semantics(
                      button: true,
                      label: 'パティシエのおはなし',
                      child: InkWell(
                        key: const ValueKey('bakery-patissier'),
                        onTap: _talking ? null : _talk,
                        child: Image.asset(
                          TownResident.c047_patisie.idleAsset,
                          fit: BoxFit.contain,
                          excludeFromSemantics: true,
                        ),
                      ),
                    ),
                  ),
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
