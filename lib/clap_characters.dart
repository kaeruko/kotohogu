import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'resident_collection.dart';

/// Supplied two-frame sprites. Keep every frame mounted to avoid flicker.
class ClapCharacters extends StatelessWidget {
  const ClapCharacters({
    super.key,
    required this.phase,
    required this.reduced,
    this.residents = TownResident.values,
  });

  final List<TownResident> residents;
  final double phase;
  final bool reduced;

  @override
  Widget build(BuildContext context) {
    final visible = residents
        .where((resident) => !resident.archived)
        .take(applauseResidentLimit)
        .toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var start = 0; start < visible.length; start += 4)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = start; i < math.min(start + 4, visible.length); i++)
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 150),
                    child: _character(visible[i], i),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _character(TownResident resident, int index) {
    final id = resident.id;
    final name = resident.label;
    final time = (phase + index * .07) % 1;
    final frame = reduced ? 1 : [0, 1, 0, 1][(time * 4).floor()];
    return Semantics(
      label: '$nameが拍手しています',
      image: true,
      child: Transform.translate(
        offset: Offset(0, reduced ? 0 : -8 * math.sin(time * math.pi).abs()),
        child: AspectRatio(
          aspectRatio: 1,
          child: IndexedStack(
            key: ValueKey('clap-$id'),
            index: frame,
            sizing: StackFit.expand,
            children: [
              for (final asset in resident.clapAssets)
                Image.asset(
                  asset,
                  fit: BoxFit.contain,
                  excludeFromSemantics: true,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
