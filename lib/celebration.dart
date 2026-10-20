import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'clap_characters.dart';
import 'resident_collection.dart';
import 'social_security_estimate.dart';

class Celebration extends StatefulWidget {
  const Celebration({
    super.key,
    required this.missionTitle,
    required this.total,
    this.preview = false,
    required this.residents,
    this.creditedKotohogi = 10,
  });
  final String missionTitle;
  final int total;
  final List<TownResident> residents;
  final int creditedKotohogi;

  /// An animation-only replay that does not award points.
  final bool preview;

  @override
  State<Celebration> createState() => _CelebrationState();
}

class _CelebrationState extends State<Celebration>
    with TickerProviderStateMixin {
  late final _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );
  late final _confetti = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4800),
  );
  late final _applause = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );
  bool? _reduced;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (_reduced == reduced) return;
    _reduced = reduced;
    if (reduced) {
      _entrance.value = 1;
      _confetti.stop();
      _applause.stop();
    } else {
      _entrance.forward();
      _confetti.forward(from: 0);
      _applause.repeat();
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    _confetti.dispose();
    _applause.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    backgroundColor: const Color(0xFFFFF0CF),
    child: Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/kotohogu/park_background_001.png',
            key: const ValueKey('celebration-background'),
            fit: BoxFit.cover,
            excludeFromSemantics: true,
          ),
        ),
        Positioned.fill(child: ColoredBox(color: const Color(0x38FFF4D5))),
        SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ScaleTransition(
                      scale: CurvedAnimation(
                        parent: _entrance,
                        curve: const Interval(0, .7, curve: Curves.elasticOut),
                      ),
                      child: Semantics(
                        label: 'ミッション達成！ あなたの一歩に、ありがとう！',
                        excludeSemantics: true,
                        liveRegion: true,
                        child: const _OutlinedHeadline(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        Positioned.fill(
                          child: Image.asset(
                            'assets/celebration/golden_clouds.png',
                            fit: BoxFit.fill,
                            excludeFromSemantics: true,
                          ),
                        ),
                        AnimatedBuilder(
                          animation: _applause,
                          builder: (context, child) => ClapCharacters(
                            phase: _applause.value,
                            residents: widget.residents,
                            reduced: _reduced!,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xEDFFF8E5),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'みんなの未来にも、うれしい一歩です！',
                            key: ValueKey('social-contribution-message'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFF63351F),
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            '健康づくりや人とのつながりは、'
                            '将来の医療・介護費を抑えることにもつながります。',
                            key: ValueKey('social-contribution-reason'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFF63351F),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '参考試算：研究集団の医療・介護費の差 年間約'
                            '${SocialSecurityStudyIllustration.illustratedYenLabel}円',
                            key: const ValueKey('social-contribution-reference'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFF63351F),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 5),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        SocialSecurityStudyIllustration.methodologyNote,
                        key: const ValueKey('social-contribution-methodology'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF63351F),
                          height: 1.35,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    SlideTransition(
                      position:
                          Tween(
                            begin: const Offset(0, .2),
                            end: Offset.zero,
                          ).animate(
                            CurvedAnimation(
                              parent: _entrance,
                              curve: const Interval(
                                .25,
                                1,
                                curve: Curves.easeOutBack,
                              ),
                            ),
                          ),
                      child: _RewardScroll(
                        title: widget.missionTitle,
                        total: widget.total,
                        creditedKotohogi: widget.creditedKotohogi,
                      ),
                    ),
                    if (widget.preview) ...[
                      const SizedBox(height: 8),
                      const Text(
                        '【デバッグ再生】ことほぎ・履歴の加算はありません',
                        key: ValueKey('debug-preview-label'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF63351F),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        key: const ValueKey('close-celebration'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFB94219),
                          foregroundColor: const Color(0xFFFFF7DD),
                          side: const BorderSide(
                            color: Color(0xFFE8B55C),
                            width: 3,
                          ),
                          minimumSize: const Size(0, 60),
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text(
                          'ありがとうを受け取る',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _confetti,
              builder: (context, child) => CustomPaint(
                painter: _ConfettiPainter(_reduced! ? 1.0 : _confetti.value),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// Hide the supplied canvas margins at layout time; keep PNG originals intact.
class _CroppedArtwork extends StatelessWidget {
  const _CroppedArtwork(this.name, {required this.heightFactor});
  final String name;
  final double heightFactor;

  @override
  Widget build(BuildContext context) => ClipRect(
    child: Align(
      heightFactor: heightFactor,
      child: Image.asset(
        'assets/celebration/$name.png',
        width: double.infinity,
        excludeFromSemantics: true,
      ),
    ),
  );
}

class _OutlinedHeadline extends StatelessWidget {
  const _OutlinedHeadline();

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    child: Stack(
      children: [
        ExcludeSemantics(
          child: Text(
            '🎊 あなたの一歩に、ありがとう！ 🎊',
            style: TextStyle(
              fontSize: 33,
              fontWeight: FontWeight.w900,
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 7
                ..color = const Color(0xFF63351F),
            ),
          ),
        ),
        const Text(
          '🎊 あなたの一歩に、ありがとう！ 🎊',
          style: TextStyle(
            fontSize: 33,
            fontWeight: FontWeight.w900,
            color: Color(0xFFFFF5D5),
          ),
        ),
      ],
    ),
  );
}

class _RewardScroll extends StatelessWidget {
  const _RewardScroll({
    required this.title,
    required this.total,
    required this.creditedKotohogi,
  });
  final String title;
  final int total;
  final int creditedKotohogi;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Stack(
      alignment: Alignment.center,
      children: [
        // Stretch only the displayed parchment, without modifying the PNG.
        Positioned.fill(
          child: FittedBox(
            fit: BoxFit.fill,
            child: SizedBox(
              width: 1448,
              child: const _CroppedArtwork('reward_scroll', heightFactor: .74),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: constraints.maxWidth * .12,
            vertical: 48,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF63351F),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Image.asset(
                    'assets/celebration/achievement_stamp.png',
                    width: 62,
                    semanticLabel: '達成！',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                creditedKotohogi > 0
                    ? 'ことほぎ +$creditedKotohogi'
                    : 'ことほぎは上限999',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF9C351C),
                ),
              ),
              const SizedBox(height: 6),
              // The decorative scroll asset may contain mock lettering.
              // Opaque paper behind the live balance prevents stale artwork
              // numerals from being mistaken for the saved wallet.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFECD3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '所持ことほぎ  $total',
                  key: const ValueKey('celebration-spendable-balance'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF63351F),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Each particle starts at its own delay, but all finish by timeline 1.0.
/// A varied exponent keeps the fall speeds visually different without freezing
/// slow confetti in mid-air when the animation controller completes.
@visibleForTesting
double confettiFallFraction(double timeline, double delay, double exponent) {
  assert(delay >= 0 && delay < 1);
  assert(exponent > 0);
  if (timeline <= delay) return 0;
  final elapsed = ((timeline - delay) / (1 - delay)).clamp(0.0, 1.0);
  return math.pow(elapsed, exponent).toDouble();
}

/// Screen-space fall position shared by the painter and regression tests.
@visibleForTesting
double confettiFallY(
  double timeline,
  double delay,
  double exponent,
  double height,
) => -30 + confettiFallFraction(timeline, delay, exponent) * (height + 100);

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.time);
  final double time;
  static const colors = [
    Color(0xFFFFDC7E),
    Color(0xFFFF99B0),
    Color(0xFF8DD9D2),
    Color(0xFFBAA7EE),
    Colors.white,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(31);
    final paint = Paint()..isAntiAlias = true;
    for (var i = 0; i < 110; i++) {
      final startX = random.nextDouble();
      final delay = random.nextDouble() * .38;
      final fallExponent = .7 + random.nextDouble() * .65;
      final drift = random.nextDouble() * 2 - 1;
      final t = time - delay;
      if (t < 0) continue;
      final x = startX * size.width + math.sin(t * 8 + i) * 30 + drift * t * 50;
      // Even the latest, slowest particle has cleared the screen at time 1.
      final y = confettiFallY(time, delay, fallExponent, size.height);
      if (y > size.height + 35) continue;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(i + t * drift * 12);
      paint.color = colors[i % colors.length];
      if (i % 3 == 0) {
        canvas.drawCircle(Offset.zero, 3.5, paint);
      } else {
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset.zero,
            width: 5 + 4 * math.sin(t * 14 + i).abs(),
            height: 13,
          ),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter oldDelegate) => oldDelegate.time != time;
}
