import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'home_skin.dart';
import 'gacha_hud.dart';
import 'progress.dart';
import 'resident_collection.dart';

/// The town lobby links to the daily mission board.
class GameHome extends StatefulWidget {
  const GameHome({
    super.key,
    required this.progress,
    required this.onMissions,
    required this.onTown,
    required this.onResident,
    this.debugTownResidents,
  });
  final Progress progress;
  final VoidCallback onMissions;

  final VoidCallback onTown;
  final ValueChanged<TownResident> onResident;
  /// A temporary debug-only selection; null uses owned residents.
  final List<TownResident>? debugTownResidents;

  @override
  State<GameHome> createState() => _GameHomeState();
}

class _GameHomeState extends State<GameHome> {
  static const _stepInterval = Duration(milliseconds: 170);

  final _scroll = ScrollController();
  final _stepFrame = ValueNotifier<int>(0);
  Timer? _stepTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shouldAnimate = !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled;
    if (shouldAnimate && _stepTimer == null) {
      // A timer avoids continuously scheduling animation frames while allowing
      // the existing widget tests to pumpAndSettle normally.
      _stepTimer = Timer.periodic(_stepInterval, (_) {
        if (mounted) _stepFrame.value = (_stepFrame.value + 1) % 4;
      });
    } else if (!shouldAnimate) {
      _stepTimer?.cancel();
      _stepTimer = null;
    }
  }

  @override
  void dispose() {
    _stepTimer?.cancel();
    _stepFrame.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(1);
      // The app's centered wrapper supplies loose constraints. Explicitly
      // fill the viewport rather than letting the Stack choose zero width.
      return SizedBox.expand(
        child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/kotohogu/town_background.png',
              fit: BoxFit.cover,
              excludeFromSemantics: true,
            ),
          ),
          PinnedGachaHud(
            points: widget.progress.residents.availableKotohogi(widget.progress.points),
            contentBuilder: (context, availableHeight) {
              // Fit the scene to the actual space below the pinned HUD and
              // above the bottom navigation. Only short displays / enlarged
              // text need the scrollable minimum height.
              final sceneHeight =
                  math.max(availableHeight, 440.0) +
                  math.max(0, scale - 1) * 300;
              return ListView(
        controller: _scroll,
        padding: EdgeInsets.zero,
        children: [
          SizedBox(
            height: sceneHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // The painted town itself is the entry point; no floating
                // title or button should cover the cherry-blossom scenery.
                // Limit the hotspot to the upper town so resident Tips and
                // the mission/town signs remain independently tappable.
                Positioned(
                  top: sceneHeight * .05,
                  left: 0,
                  right: 0,
                  height: sceneHeight * .33,
                  child: Semantics(
                    key: const ValueKey('open-town-scenery'),
                    button: true,
                    label: 'まちの景色をタップして、みんなのまちへ',
                    onTap: widget.onTown,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      excludeFromSemantics: true,
                      onTap: widget.onTown,
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
                Positioned(
                  top: sceneHeight * .31,
                  left: 22,
                  right: 22,
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xF5FFF5DA),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: gold, width: 2),
                        ),
                        child: const Text(
                          '今日の小さな行動を、みんなで祝おう。',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: wood,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: constraints.maxWidth * .10,
                        ),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minWidth: constraints.maxWidth * .80,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                            for (final (index, resident)
                                in visibleTownResidents(
                                  widget.progress.residents.owned,
                                  debugOverride: widget.debugTownResidents,
                                ).indexed)
                              SizedBox(
                                width: (constraints.maxWidth * .15).clamp(44, 80) + 6,
                                child: Semantics(
                                  button: true,
                                  label: '${resident.label}のおはなし',
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(30),
                                    onTap: () => widget.onResident(resident),
                                    child: Padding(
                                      padding: const EdgeInsets.all(3),
                                      child: ValueListenableBuilder<int>(
                                        valueListenable: _stepFrame,
                                        builder: (context, frame, _) {
                                          final still = MediaQuery.disableAnimationsOf(
                                                context,
                                              ) ||
                                              !TickerMode.valuesOf(context).enabled;
                                          final asset = still
                                              ? resident.idleAsset
                                              : resident.walkAsset(
                                                  WalkDirection.front,
                                                  (frame + (index.isOdd ? 2 : 0)) % 4,
                                                );
                                          return Image.asset(
                                            asset,
                                            key: ValueKey(
                                              'home-resident-sprite-${resident.id}',
                                            ),
                                            width: (constraints.maxWidth * .15)
                                                .clamp(44, 80),
                                            height: (constraints.maxWidth * .15)
                                                .clamp(44, 80),
                                            fit: BoxFit.contain,
                                            gaplessPlayback: true,
                                            excludeFromSemantics: true,
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  bottom: 18,
                  left: 14,
                  right: 14,
                  child: Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Align(
                              alignment: Alignment.bottomLeft,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 175),
                                child: _LobbySign(
                                  key: const ValueKey('open-missions'),
                                  asset: '10_nav_quest',
                                  title: '今日のセルフケア',
                                  detail:
                                      '${widget.progress.completed.length} / ${Mission.forPeriod(MissionPeriod.daily).length} 達成',
                                  onTap: widget.onMissions,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Align(
                              alignment: Alignment.bottomRight,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 175),
                                child: _LobbySign(
                                  key: const ValueKey('open-town'),
                                  asset: '11_nav_town',
                                  title: 'みんなのまちへ',
                                  detail: 'LEVEL ${widget.progress.townLevel}',
                                  onTap: widget.onTown,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        key: const ValueKey('home-footer-message'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xF5FFF4DA),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Text(
                          'あなたのペースで、できたことをひとつずつ。',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: wood,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      );
            },
          ),
        ],
        ),
      );
    },
  );
}

class _LobbySign extends StatelessWidget {
  const _LobbySign({
    super.key,
    required this.asset,
    required this.title,
    required this.detail,
    required this.onTap,
  });
  final String asset;
  final String title;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(23),
        child: Ink(
          decoration: parchment(),
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              uiPart(asset, height: 52),
              const SizedBox(height: 5),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: wood,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: wood,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Text(
                  detail,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFFFE6AD),
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
