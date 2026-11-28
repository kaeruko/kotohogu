import 'package:flutter/material.dart';

import 'kotohoguru_dojo.dart';
import 'online_duel_page.dart';
import 'resident_collection.dart';

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

  // The hall staff are fixed here, independent of the player's gacha collection.
  Widget _resident({
    required String id,
    required String label,
    required TownResident resident,
    required double x,
    required double y,
    required VoidCallback onPressed,
  }) => Positioned(
    left: x,
    top: y,
    width: 240,
    height: 230,
    child: Semantics(
      button: true,
      label: '${resident.label}、$label',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey('community-center-2f-$id'),
          borderRadius: BorderRadius.circular(20),
          onTap: onPressed,
          child: Column(
            children: [
              Expanded(
                child: Image.asset(
                  resident.idleAsset,
                  fit: BoxFit.contain,
                  excludeFromSemantics: true,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEAC6),
                  border: Border.all(color: const Color(0xFF9A6039), width: 3),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 31,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF593A28),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Future<void> _meeting(BuildContext context) async {
    final open = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('たびじろう'),
        content: const Text(
          'おともだちと待ち合わせかい？\\n'
          '待ち合わせ番号があれば、ここから行けるよ。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('とじる'),
          ),
          FilledButton(
            key: const ValueKey('community-center-2f-open-meeting'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('待ち合わせ広場へ'),
          ),
        ],
      ),
    );
    if (open != true || !context.mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const OnlineDuelPage()),
    );
  }

  Widget _stairs(BuildContext context) => Positioned(
    left: 295,
    top: 55,
    width: 175,
    height: 220,
    child: Semantics(
      button: true,
      label: '1階へ',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const ValueKey('community-center-2f-stairs'),
          onTap: () => Navigator.of(context).pop(),
        ),
      ),
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
                _stairs(context),
                _resident(
                  id: 'meeting',
                  label: '待ち合わせ',
                  resident: TownResident.c055_traveler,
                  x: 95,
                  y: 790,
                  onPressed: () => _meeting(context),
                ),
                _resident(
                  id: 'battle',
                  label: '対戦室',
                  resident: TownResident.c032_miner,
                  x: 585,
                  y: 550,
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('げんばくん'),
                      content: const Text(
                        'よーし、勝負の準備はできてるよ！\n'
                        'ともだちと対戦する？ それとも道場でお稽古する？\n'
                        '待ち合わせ番号で参加・再開できるよ。',
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
                _resident(
                  id: 'ranking',
                  label: '掲示板',
                  resident: TownResident.c048_advicer,
                  x: 585,
                  y: 1010,
                  onPressed: () => _notice(
                    context,
                    'しんだんし',
                    'ここは対戦記録やお知らせの掲示板です。\n'
                    '勝った回数だけでなく、続けた回数にも価値がありますよ。\n'
                    'オンラインランキングは準備中です。',
                  ),
                ),
                _resident(
                  id: 'rest',
                  label: 'ひと休み',
                  resident: TownResident.c053_penguin_lady,
                  x: 350,
                  y: 1265,
                  onPressed: () => _notice(
                    context,
                    'はるまちさん',
                    'あら、今日もにぎやかね。\n'
                    '勝負の前にも後にも、ひと息ついていってね。',
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
