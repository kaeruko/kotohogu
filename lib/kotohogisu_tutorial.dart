import 'package:flutter/material.dart';

import 'home_skin.dart';

/// Intro text is kept independent from the dialogue CMS; completion is
/// persisted by the parent through Progress.seenDialogues.
class KotohogisuTutorial extends StatefulWidget {
  const KotohogisuTutorial({
    super.key,
    required this.onSkip,
    required this.onFinish,
    this.saving = false,
  });

  final VoidCallback onSkip;
  final VoidCallback onFinish;
  final bool saving;

  @override
  State<KotohogisuTutorial> createState() => _KotohogisuTutorialState();
}

class _KotohogisuTutorialState extends State<KotohogisuTutorial> {
  static const _lines = [
    'ちゅん、ちゅん！\nぼくはコトホギス。\nここは、あなたの「できた！」をお祝いするまちだよ。',
    '今日できたことがあったら、\n画面下の「セルフケア」を押して教えてね。\n小さな一歩も、ことほぎになるよ。',
    'ことほぎがたまると、まちが育つよ。\n新しい住民との出会いも楽しみにね。\nあなたのペースで、のんびりいこう！',
  ];
  int _step = 0;

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return Stack(
      key: const ValueKey('kotohogisu-tutorial'),
      children: [
        const Positioned.fill(
          child: ModalBarrier(color: Color(0x660B251D), dismissible: false),
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: SingleChildScrollView(
              reverse: true,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Container(
                  decoration: parchment(),
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: 1, end: 0),
                            duration: reducedMotion
                                ? Duration.zero
                                : const Duration(milliseconds: 850),
                            curve: Curves.easeOutCubic,
                            builder: (context, distance, _) {
                              const base =
                                  'assets/characters/013_kotohogisu/';
                              // Approaching from the right: face left while
                              // moving, then turn toward the player to talk.
                              final String sprite;
                              if (!reducedMotion && distance > 0.01) {
                                final frame = ((1 - distance) * 4)
                                        .floor()
                                        .clamp(0, 3) +
                                    1;
                                final suffix =
                                    frame.toString().padLeft(2, '0');
                                sprite = '${base}walk_left_$suffix.png';
                              } else {
                                sprite = switch (_step) {
                                  0 => '${base}idle_front_01.png',
                                  1 => '${base}clap_front_01.png',
                                  _ => '${base}clap_front_02.png',
                                };
                              }
                              return Transform.translate(
                                offset: Offset(distance * 220, -distance * 65),
                                child: Semantics(
                                  label: 'コトホギスが飛んできました',
                                  child: Image.asset(
                                    sprite,
                                    key: const ValueKey('kotohogisu-sprite'),
                                    width: 84,
                                    height: 84,
                                    fit: BoxFit.contain,
                                    gaplessPlayback: true,
                                    excludeFromSemantics: true,
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'コトホギス',
                              style: TextStyle(
                                fontSize: 23,
                                fontWeight: FontWeight.w900,
                                color: wood,
                              ),
                            ),
                          ),
                          Text(
                            '${_step + 1}/${_lines.length}',
                            style: const TextStyle(
                              color: wood,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      AnimatedSwitcher(
                        duration: reducedMotion
                            ? Duration.zero
                            : const Duration(milliseconds: 180),
                        child: Text(
                          _lines[_step],
                          key: ValueKey('kotohogisu-line-$_step'),
                          style: const TextStyle(
                            fontSize: 17,
                            height: 1.7,
                            fontWeight: FontWeight.w600,
                            color: wood,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          TextButton(
                            key: const ValueKey('kotohogisu-skip'),
                            onPressed: widget.saving ? null : widget.onSkip,
                            child: const Text('スキップ'),
                          ),
                          const Spacer(),
                          FilledButton(
                            key: const ValueKey('kotohogisu-next'),
                            onPressed: widget.saving
                                ? null
                                : _step == _lines.length - 1
                                ? widget.onFinish
                                : () => setState(() => _step++),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF277A70),
                            ),
                            child: Text(
                              widget.saving
                                  ? '保存中…'
                                  : _step == _lines.length - 1
                                  ? 'セルフケアを見に行く'
                                  : 'つぎへ',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
