import 'package:flutter/material.dart';

import 'progress.dart';
import 'resident_collection.dart';
import 'home_skin.dart';
import 'gacha_screen.dart';

/// Inline panel keeps save failures visible on the main diagnostic screen.
class ResidentGacha extends StatefulWidget {
  const ResidentGacha({super.key, required this.controller, this.onTown});
  final VoidCallback? onTown;
  final ProgressController controller;
  @override
  State<ResidentGacha> createState() => _ResidentGachaState();
}

class _ResidentGachaState extends State<ResidentGacha> {
  static const int _consultationCost = 30;
  bool _revealing = false;

  Future<void> _openShrine() async {
    final progress = widget.controller.progress;
    if (_revealing ||
        widget.controller.busy ||
        progress == null ||
        progress.residents.availableKotohogi(progress.points) < _consultationCost) {
      return;
    }
    setState(() => _revealing = true);
    final town = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => GachaScreen(
          controller: widget.controller,
          autoStart: true,
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _revealing = false);
    if (town == true) widget.onTown?.call();
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.controller.progress!;
    final collection = progress.residents;
    final balance = collection.availableKotohogi(progress.points);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: parchment(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'まちの仲間 ${collection.owned.length}/$ownedResidentLimit人',
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Expanded(
                child: Text(
                  '移住相談会の開催費',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF63351F),
                  ),
                ),
              ),
              Text(
                '$_consultationCostことほぎ',
                key: const ValueKey('consultation-cost'),
                style: const TextStyle(
                  color: Color(0xFF63351F),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          Text(
            balance >= _consultationCost
                ? '$_consultationCostことほぎで移住相談会を1回開けます。'
                : 'あと${_consultationCost - balance}ことほぎで移住相談会を開けます。',
          ),
          const SizedBox(height: 12),
          Center(
            child: Semantics(
              button: true,
              enabled: !_revealing && !widget.controller.busy && balance >= _consultationCost,
              label: '移住相談会へ',
              child: Tooltip(
                message: '移住相談会へ',
                child: TextButton(
                  key: const ValueKey('draw-resident'),
                  onPressed:
                      _revealing || widget.controller.busy || balance < _consultationCost
                      ? null
                      : _openShrine,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(200, 72),
                  ),
                  child: Opacity(
                    opacity:
                        _revealing || widget.controller.busy || balance < _consultationCost
                        ? .45
                        : 1,
                    child: Image.asset(
                      'assets/gacya/button_resident.png',
                      width: 320,
                      height: 98,
                      fit: BoxFit.contain,
                      excludeFromSemantics: true,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '住民との出会いは同じ確率です。\n同じ住民と再会することもあります。',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              for (final resident in collection.owned)
                SizedBox(
                  width: 92,
                  child: Column(
                    children: [
                      TownResidentAvatar(resident: resident, size: 60),
                      Text(resident.label, textAlign: TextAlign.center),
                      Text(
                        '累計${collection.counts[resident.id]}回',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
