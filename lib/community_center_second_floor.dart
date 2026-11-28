import 'package:flutter/material.dart';

import 'kotohoguru_dojo.dart';
import 'online_duel_page.dart';

/// Public hall's second floor. The hotspots follow the original 941×1672
/// artwork, not device pixels. Rankings are not yet connected.
class CommunityCenterSecondFloor extends StatelessWidget {
  const CommunityCenterSecondFloor({super.key});

  static const backgroundAsset =
      'assets/kotohogu/community_center_2f_background.png';

  Future<void> _notice(
    BuildContext context, String title, String message,
  ) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('とじる'),
        ),
      ],
    ),
  );

  Widget _spot({
    required String id,
    required String label,
    required double x,
    required double y,
    required VoidCallback onPressed,
  }) => Positioned(
    left: x,
    top: y,
    width: 300,
    height: 108,
    child: FilledButton.tonal(
      key: ValueKey('community-center-2f-$id'),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        textStyle: const TextStyle(fontSize: 38, fontWeight: FontWeight.w600),
      ),
      onPressed: onPressed,
      child: Text(label, textAlign: TextAlign.center),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFFFF3DC),
    appBar: AppBar(
      title: const Text('コトホグル対戦会館'),
      leading: IconButton(
        key: const ValueKey('community-center-2f-return'),
        tooltip: '1階にもどる',
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(Icons.arrow_back),
      ),
    ),
    body: SafeArea(
      child: Center(
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: 941,
            height: 1672,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Image.asset(
                    backgroundAsset,
                    key: const ValueKey('community-center-2f-background'),
                    fit: BoxFit.fill,
                    excludeFromSemantics: true,
                  ),
                ),
                _spot(
                  id: 'stairs',
                  label: '1階へ',
                  x: 230,
                  y: 235,
                  onPressed: () => Navigator.of(context).pop(),
                ),
                _spot(
                  id: 'meeting',
                  label: '待ち合わせ',
                  x: 65,
                  y: 935,
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const OnlineDuelPage(),
                    ),
                  ),
                ),
                _spot(
                  id: 'battle',
                  label: '対戦室',
                  x: 540,
                  y: 675,
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('対戦室'),
                      content: const Text(
                        'ともだちと対戦するか、道場でお稽古できます。\n'
                        '待ち合わせ番号で参加・再開できます。',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          child: const Text('とじる'),
                        ),
                        FilledButton(
                          key: const ValueKey('community-center-2f-open-online'),
                          onPressed: () {
                            Navigator.of(dialogContext).pop();
                            Navigator.of(context).push<void>(
                              MaterialPageRoute<void>(
                                builder: (_) => const OnlineDuelPage(),
                              ),
                            );
                          },
                          child: const Text('ともだちと対戦'),
                        ),
                        FilledButton(
                          key: const ValueKey('community-center-2f-open-dojo'),
                          onPressed: () {
                            Navigator.of(dialogContext).pop();
                            Navigator.of(context).push<void>(
                              MaterialPageRoute<void>(
                                builder: (_) => const KotohoguruDojo(),
                              ),
                            );
                          },
                          child: const Text('道場へ'),
                        ),
                      ],
                    ),
                  ),
                ),
                _spot(
                  id: 'ranking',
                  label: '掲示板',
                  x: 540,
                  y: 1140,
                  onPressed: () => _notice(
                    context,
                    'ランキング・お知らせ',
                    'みんなの対戦記録やお知らせを掲示する場所です。\n'
                    'オンラインランキングは準備中です。',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
