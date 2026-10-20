import 'package:flutter/material.dart';

import 'consultation_scene.dart';
import 'gacha_hud.dart';
import 'gacha_reveal.dart';
import 'progress.dart';
import 'resident_collection.dart';

/// One consultation meeting welcomes one resident. The old bundle save
/// schema stays readable, but the ten-draw option is no longer offered.
class GachaScreen extends StatefulWidget {
  const GachaScreen({
    super.key,
    required this.controller,
    this.autoStart = false,
  });

  final ProgressController controller;
  /// True only for the resident-welcome entry point. Manual entry is retained
  /// for previews and explicit consultation-screen navigation.
  final bool autoStart;

  @override
  State<GachaScreen> createState() => _GachaScreenState();
}

class _GachaScreenState extends State<GachaScreen> {
  bool _drawing = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoStart) {
      // Exactly once per entrance. The first frame has already mounted the
      // route, so the saved resident can transition straight into the reveal.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _draw();
      });
    }
  }

  Future<void> _draw() async {
    final progress = widget.controller.progress;
    if (_drawing ||
        widget.controller.busy ||
        progress == null ||
        progress.residents.availableKotohogi(progress.points) < 30) {
      return;
    }
    setState(() => _drawing = true);
    final existing = Map<String, int>.of(progress.residents.counts);
    try {
      final result = await widget.controller.drawResident();
      if (!mounted || result == null) return;
      final town = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => GachaReveal(
            controller: widget.controller,
            resident: result,
            isNew: !existing.containsKey(result.id),
          ),
        ),
      );
      if (mounted && town == true) Navigator.of(context).pop(true);
    } finally {
      if (mounted) {
        if (widget.controller.failure != null) {
          // Do not conceal the controller's original save error.
          Navigator.of(context).pop(false);
        } else {
          setState(() => _drawing = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final progress = widget.controller.progress!;
      final balance = progress.residents.availableKotohogi(progress.points);
      final enabled = !_drawing &&
          !widget.controller.busy &&
          progress.residents.availableKotohogi(progress.points) >= 30;
      final safe = MediaQuery.paddingOf(context);
      return PopScope(
        canPop: !_drawing,
        child: Scaffold(
          backgroundColor: const Color(0xFFFBE9C8),
          body: Stack(
            children: [
              const Positioned.fill(child: ConsultationBackground()),
              Positioned(
                left: 10,
                right: 10,
                bottom: safe.bottom + 6,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _drawing
                          ? '住民をお迎えしています…'
                          : enabled
                              ? '開催費：30ことほぎ'
                              : '開催には30ことほぎが必要です',
                      key: const ValueKey('consultation-cost'),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF5A2D1D),
                        shadows: [
                          Shadow(color: Color(0xFFFFF8E8), blurRadius: 5),
                        ],
                      ),
                    ),
                    ConsultationActions(
                      onResidents: () => showResidentCollection(
                        context,
                        progress.residents,
                      ),
                      onAgain: enabled ? _draw : null,
                      againLabel: '移住相談会を開く（30ことほぎ）',
                      againKey: const ValueKey('gacha-draw-one'),
                    ),
                    const SizedBox(height: 2),
                    ConsultationTownBackButton(
                      onPressed: _drawing
                          ? null
                          : () => Navigator.of(context).pop(true),
                    ),
                  ],
                ),
              ),
              // Draw the same pinned header above this scene.
              Positioned.fill(child: GameHeaderOverlay(points: balance, displayName: progress.playerName)),
            ],
          ),
        ),
      );
    },
  );
}

/// Ten-ticket bundle: all eleven results are visible and persisted at once.
class GachaBundleReveal extends StatelessWidget {
  const GachaBundleReveal({
    super.key,
    required this.controller,
    required this.residents,
    required this.firstAppearance,
  }) : assert(residents.length == 11),
       assert(firstAppearance.length == 11);

  final ProgressController controller;
  final List<TownResident> residents;
  final List<bool> firstAppearance;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFFFE8AE),
    body: Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/gacya/bg.png',
            fit: BoxFit.cover,
            excludeFromSemantics: true,
          ),
        ),
        SafeArea(
          child: PinnedGachaHud(
            displayName: controller.progress!.playerName,
            points: controller.progress!.residents.availableKotohogi(
              controller.progress!.points,
            ),
            contentBuilder: (context, availableHeight) => Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: Column(
                  children: [
                    const SizedBox(height: 6),
                    Image.asset(
                      'assets/gacya/gacha_title.png',
                      height: 108,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 10),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xEEFFF1D4),
                        border: Border.all(
                          color: const Color(0xFFC78B36),
                          width: 3,
                        ),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          const Text('11人との出会い！',
                            key: ValueKey('gacha-bundle-title'),
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 24,
                              color: Color(0xFF67371F),
                            )),
                          const Text('300ことほぎで10回分＋1回おまけ',
                            style: TextStyle(color: Color(0xFF67371F))),
                          const SizedBox(height: 14),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            runSpacing: 14,
                            children: [
                              for (var i = 0; i < residents.length; i++)
                                SizedBox(
                                  key: ValueKey('gacha-result-$i'),
                                  width: 88,
                                  child: Column(
                                    children: [
                                      TownResidentAvatar(
                                        resident: residents[i], size: 75,
                                      ),
                                      Text(
                                        residents[i].label,
                                        style: const TextStyle(fontSize: 13,
                                          fontWeight: FontWeight.bold),
                                      ),
                                      Text(firstAppearance[i] ? 'NEW!' : 'また会えた',
                                        style: const TextStyle(fontSize: 11)),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      key: const ValueKey('gacha-bundle-town'),
                      onPressed: () => Navigator.of(context).pop(true),
                      icon: const Icon(Icons.home_outlined),
                      label: const Text('まちへ'),
                    ),
                    TextButton(
                      key: const ValueKey('gacha-bundle-again'),
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('ガチャ画面へ戻る'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          ),
        ),
      ],
    ),
  );
}
