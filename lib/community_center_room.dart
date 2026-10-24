import 'dart:async';

import 'package:flutter/material.dart';

import 'facility_layout.dart';
import 'resident_collection.dart';
import 'town_areas.dart';

/// The public community center, reached from the shopping street after
/// earning 240 lifetime kotohogi points. The resident placements follow the
/// uploaded 941x1672 artwork, not the screen's pixel coordinates.
class CommunityCenterRoom extends StatefulWidget {
  const CommunityCenterRoom({
    super.key,
    this.onResident,
    this.hideShoppingMother = false,
  });

  static const backgroundAsset =
      'assets/kotohogu/community_center_background_001.png';

  /// A room-only animation variant of the existing 051_dog_aunt resident.
  static const kneeExerciseSpriteFolder =
      'assets/characters/051_dog_aunt_knee_exercise';

  final Future<void> Function(TownResident)? onResident;
  final bool hideShoppingMother;

  @override
  State<CommunityCenterRoom> createState() => _CommunityCenterRoomState();
}

class _CommunityCenterRoomState extends State<CommunityCenterRoom> {
  static const _frameDuration = Duration(milliseconds: 150);
  Timer? _exerciseTicker;
  int _exerciseTicks = 0;
  bool _animationsEnabled = false;
  bool _talking = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animationsEnabled = !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled;
    if (_animationsEnabled && _exerciseTicker == null) {
      _exerciseTicker = Timer.periodic(_frameDuration, (_) {
        if (mounted) {
          setState(() => _exerciseTicks++);
        }
      });
    } else if (!_animationsEnabled) {
      _exerciseTicker?.cancel();
      _exerciseTicker = null;
    }
  }

  @override
  void dispose() {
    _exerciseTicker?.cancel();
    super.dispose();
  }

  String _spriteAsset(TownResident resident) {
    final isAttendee = resident == TownResident.c051_dog_aunt;
    final isCoach = resident == TownResident.c037_tora;
    if (!isAttendee && !isCoach) {
      return resident.idleAsset;
    }

    // A conversation or reduced-motion setting keeps everyone still.
    if (!_animationsEnabled || _talking) {
      return isAttendee
          ? '${CommunityCenterRoom.kneeExerciseSpriteFolder}/idle_front_01.png'
          : resident.idleAsset;
    }

    // Four gentle exercise poses, with feet anchored at the CMS placement.
    final frame = (_exerciseTicks ~/ 3) % 4;
    if (isAttendee) {
      final number = (frame + 1).toString().padLeft(2, '0');
      return '${CommunityCenterRoom.kneeExerciseSpriteFolder}/walk_front_$number.png';
    }
    return resident.walkAsset(WalkDirection.front, frame);
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
              _spriteAsset(resident),
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
                    if (!widget.hideShoppingMother ||
                        resident != familyOutingMother)
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
