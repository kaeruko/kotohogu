import 'dart:async';

import 'package:flutter/material.dart';

import 'home_skin.dart';
import 'progress.dart';

class MissionsScreen extends StatelessWidget {
  const MissionsScreen({
    super.key,
    required this.progress,
    required this.busy,
    required this.onComplete,
    required this.period,
    required this.onPeriodChanged,
    this.drawBackground = true,
  });
  /// Shared by the standalone preview and the main app's fixed-HUD shell.
  static const backgroundAsset = 'assets/kotohogu/park_background_001.png';

  // The shared app header owns the wallpaper on full navigation pages.
  // Standalone previews continue to paint their usual background.
  final bool drawBackground;
  final Progress progress;
  final bool busy;
  final ValueChanged<Mission> onComplete;
  final MissionPeriod period;
  final ValueChanged<MissionPeriod> onPeriodChanged;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      if (drawBackground)
        Positioned.fill(
          child: Image.asset(
            backgroundAsset,
            key: const ValueKey('mission-background'),
            fit: BoxFit.cover,
            excludeFromSemantics: true,
          ),
        ),
      const Positioned.fill(child: _CornerClouds(top: true)),
      const Positioned.fill(child: _CornerClouds(top: false)),
      ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        children: [
          Row(
            children: [
              const _WalkingMissionKotohogisu(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Stack(
                      children: [
                        ExcludeSemantics(
                          child: Text(
                            'セルフケア一覧',
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w900,
                              foreground: Paint()
                                ..style = PaintingStyle.stroke
                                ..strokeWidth = 6
                                ..color = const Color(0xFFFFF6D6),
                            ),
                          ),
                        ),
                        const Text(
                          'セルフケア一覧',
                          style: TextStyle(
                            color: wood,
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF5DF),
                        border: Border.all(color: wood, width: 2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        switch (period) {
                          MissionPeriod.daily => '今日できたことを、教えてね。',
                          MissionPeriod.weekly => '今週できたことを、教えてね。',
                          MissionPeriod.monthly => '今月できたことを、教えてね。',
                        },
                        style: const TextStyle(
                          color: wood,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xEEFFF5DF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${progress.completedFor(period).length}/${Mission.forPeriod(period).length} 達成',
              key: const ValueKey('mission-period-progress'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: wood, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 12),
          _MissionTabs(period: period, onChanged: onPeriodChanged),
          Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF814E2C), Color(0xFF4B2C1D)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: gold, width: 4),
              borderRadius: BorderRadius.circular(18),
              boxShadow: const [
                BoxShadow(
                  color: Color(0xAA512B16),
                  offset: Offset(0, 4),
                  blurRadius: 5,
                ),
              ],
            ),
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  bottom: 0,
                  child: Image.asset(
                    'assets/quests/20_corner_left.png',
                    width: 56,
                    excludeFromSemantics: true,
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Image.asset(
                    'assets/quests/19_corner_right.png',
                    width: 56,
                    excludeFromSemantics: true,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 14, 10, 42),
                  child: Column(
                    children: [
                      for (final mission in Mission.forPeriod(period))
                        _QuestCard(
                          mission: mission,
                          done: progress.completedFor(period).contains(mission),
                          onComplete: busy ? null : () => onComplete(mission),
                        ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          switch (period) {
                            MissionPeriod.daily =>
                              '量や回数は問いません。\n今日行動したことを、みんなで祝います。',
                            MissionPeriod.weekly =>
                              '今週できたことだけを言祝ぎます。\nできなかったことは気にしなくて大丈夫。',
                            MissionPeriod.monthly =>
                              '今月できたことを振り返りましょう。\n未達成のミッションに罰はありません。',
                          },
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFFFFE6B2),
                            fontSize: 12,
                            height: 1.6,
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
      ),
    ],
  );
}

/// A tiny back-and-forth walk confined to the mission title's avatar slot.
/// Timer-driven frames let widget tests pumpAndSettle without hanging.
class _WalkingMissionKotohogisu extends StatefulWidget {
  const _WalkingMissionKotohogisu();

  @override
  State<_WalkingMissionKotohogisu> createState() =>
      _WalkingMissionKotohogisuState();
}

class _WalkingMissionKotohogisuState extends State<_WalkingMissionKotohogisu> {
  static const _stepInterval = Duration(milliseconds: 180);
  static const _spriteRoot = 'assets/characters/013_kotohogisu/';
  final ValueNotifier<int> _step = ValueNotifier<int>(0);
  Timer? _walkTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animate = !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled;
    if (animate && _walkTimer == null) {
      _walkTimer = Timer.periodic(_stepInterval, (_) {
        if (mounted) _step.value = (_step.value + 1) % 16;
      });
    } else if (!animate) {
      _walkTimer?.cancel();
      _walkTimer = null;
    }
  }

  @override
  void dispose() {
    _walkTimer?.cancel();
    _step.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'コトホギス',
    child: SizedBox(
      key: const ValueKey('mission-kotohogisu'),
      width: 68,
      height: 68,
      child: ValueListenableBuilder<int>(
        valueListenable: _step,
        builder: (context, step, _) {
          final animate = !MediaQuery.disableAnimationsOf(context) &&
              TickerMode.valuesOf(context).enabled;
          final direction = step < 8 ? 'right' : 'left';
          final frame = (step % 4 + 1).toString().padLeft(2, '0');
          final asset = animate
              ? '${_spriteRoot}walk_${direction}_$frame.png'
              : '${_spriteRoot}idle_front_01.png';
          // Reverse after eight steps, with no drift toward the label.
          final position = step < 8 ? step : 15 - step;
          final dx = animate ? (position - 3.5) * 1.6 : 0.0;
          return Transform.translate(
            offset: Offset(dx, 0),
            child: Image.asset(
              asset,
              key: const ValueKey('mission-kotohogisu-sprite'),
              width: 68,
              height: 68,
              fit: BoxFit.contain,
              gaplessPlayback: true,
              excludeFromSemantics: true,
            ),
          );
        },
      ),
    ),
  );
}

/// Fixed decorations never intercept taps or appear in screen-reader output.
class _CornerClouds extends StatelessWidget {
  const _CornerClouds({required this.top});
  final bool top;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = (constraints.maxWidth * (top ? .34 : .48)).clamp(
            0.0,
            top ? 185.0 : 245.0,
          );
          return Stack(
            children: [
              for (final left in [true, false])
                Positioned(
                  left: left ? -8 : null,
                  right: left ? null : -8,
                  top: top ? 80 : null,
                  bottom: top ? null : -8,
                  child: Image.asset(
                    'assets/quests/cloud_${top ? 'top' : 'bottom'}_${left ? 'left' : 'right'}.png',
                    width: size,
                    height: size,
                    fit: BoxFit.contain,
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}

/// Reuse the provided gold and wood frames; render live labels above their
/// baked-in lettering so every period has both selected and unselected states.
class _MissionTabs extends StatelessWidget {
  const _MissionTabs({required this.period, required this.onChanged});
  final MissionPeriod period;
  final ValueChanged<MissionPeriod> onChanged;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(1);
      final tabWidth = (constraints.maxWidth / 3).clamp(
        116 * scale,
        double.infinity,
      );
      return Padding(
        padding: EdgeInsets.zero,
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            for (final candidate in MissionPeriod.values)
              SizedBox(
                width: tabWidth,
                height: 60 * scale,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    2,
                    candidate == period ? 0 : 7,
                    2,
                    0,
                  ),
                  child: _MissionTab(
                    key: ValueKey('mission-tab-${candidate.name}'),
                    selected: candidate == period,
                    label: switch (candidate) {
                      MissionPeriod.daily => 'デイリー',
                      MissionPeriod.weekly => 'ウィークリー',
                      MissionPeriod.monthly => 'マンスリー',
                    },
                    onTap: () => onChanged(candidate),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

class _MissionTab extends StatelessWidget {
  const _MissionTab({
    super.key,
    required this.selected,
    required this.label,
    required this.onTap,
  });
  final bool selected;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/quests/tab_${selected ? 'selected' : 'unselected'}.png',
              fit: BoxFit.fill,
              excludeFromSemantics: true,
            ),
            Positioned.fill(
              left: 12,
              right: 12,
              top: 12,
              bottom: 5,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: selected
                        ? const [Color(0xFFFFE5A0), Color(0xFFF6C96B)]
                        : const [Color(0xFFB57A38), Color(0xFF93531F)],
                  ),
                ),
                child: Center(
                  child: ExcludeSemantics(
                    child: Stack(
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            foreground: Paint()
                              ..style = PaintingStyle.stroke
                              ..strokeWidth = 4
                              ..color = wood,
                          ),
                        ),
                        Text(
                          label,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFFFFF4D6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _QuestCard extends StatelessWidget {
  const _QuestCard({
    required this.mission,
    required this.done,
    required this.onComplete,
  });
  final Mission mission;
  final bool done;
  final VoidCallback? onComplete;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/quests/${mission == Mission.outside ? '13_mission_card_orange_empty_title' : '09_mission_card_gold_empty_title'}.png',
            fit: BoxFit.fill,
            excludeFromSemantics: true,
          ),
        ),
        // The supplied card has baked currency/reward/challenge labels. An opaque
        // content layer preserves its decorative outer frame without showing them.
        Padding(
          padding: const EdgeInsets.all(10),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: mission == Mission.outside
                    ? const [Color(0xFFFFD296), Color(0xFFFFF4D8)]
                    : const [Color(0xFFFFE7A3), Color(0xFFFFF7E4)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      switch (mission) {
                        Mission.strength => Icons.accessibility_new_rounded,
                        Mission.outside => Icons.directions_walk_rounded,
                        Mission.conversation => Icons.forum_rounded,
                        _ => Icons.favorite_rounded,
                      },
                      color: wood,
                      size: 30,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        key: ValueKey('mission-label-${mission.name}'),
                        constraints: const BoxConstraints(minHeight: 56),
                        decoration: const BoxDecoration(
                          image: DecorationImage(
                            image: AssetImage(
                              'assets/quests/10_label_bar_blank.png',
                            ),
                            // Stretch only the quiet middle of the title bar.
                            // The end caps contain blossoms and must keep their
                            // proportions when cards grow wider.
                            centerSlice: Rect.fromLTWH(56, 2, 191, 70),
                            fit: BoxFit.fill,
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 8,
                        ),
                        child: Text(
                          mission.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: wood,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    if (done)
                      Image.asset(
                        'assets/kotohogu/24_badge_clear.png',
                        key: ValueKey('mission-clear-${mission.name}'),
                        width: 60,
                        height: 60,
                        fit: BoxFit.contain,
                        excludeFromSemantics: true,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  mission.description,
                  style: const TextStyle(color: wood, fontSize: 12),
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final reward = Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        uiPart('32_heart_red_1', width: 24, height: 24),
                        const SizedBox(width: 5),
                        const Flexible(
                          child: Text(
                            'ことほぎ +10',
                            style: TextStyle(
                              color: wood,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    );
                    final button = FilledButton(
                      key: ValueKey('complete-${mission.name}'),
                      onPressed: done ? null : onComplete,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFC44220),
                        foregroundColor: const Color(0xFFFFF5DB),
                        disabledBackgroundColor: const Color(0xFFE2D7B9),
                        disabledForegroundColor: wood,
                        minimumSize: const Size(0, 52),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        side: const BorderSide(
                          color: Color(0xFFF5BA57),
                          width: 3,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      child: Text(
                        done ? 'できた！  達成済み' : 'できた！',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: done ? 16 : 23,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    );
                    if (constraints.maxWidth < 340 ||
                        MediaQuery.textScalerOf(context).scale(1) > 1.2) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          reward,
                          const SizedBox(height: 10),
                          SizedBox(width: double.infinity, child: button),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: reward),
                        const SizedBox(width: 8),
                        Expanded(child: button),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
