import 'package:flutter/material.dart';

import 'dev_tools.dart';
import 'home_skin.dart';
import 'progress.dart';
import 'resident_collection.dart';

/// Debug-only controls for testing celebrations, currency and resets.
class DebugMenuScreen extends StatelessWidget {
  const DebugMenuScreen({
    super.key,
    required this.progress,
    required this.selectedMission,
    required this.onMissionChanged,
    required this.onPreview,
    required this.onReplayTutorial,
    required this.onResetAll,
    required this.onAddTickets,
    required this.debugTownResidents,
    required this.onDebugTownEnabled,
    required this.onDebugTownResidentChanged,
    this.showUnownedPreviewVisitors = false,
    this.onUnownedPreviewVisitorsChanged,
    required this.salonUnlockMode,
    required this.onSalonUnlockModeChanged,
    required this.busy,
    this.drawBackground = true,
  });

  final bool drawBackground;
  final Progress progress;
  final Mission selectedMission;
  final ValueChanged<Mission> onMissionChanged;
  final VoidCallback onPreview;
  final VoidCallback onReplayTutorial;
  final Future<bool> Function() onResetAll;
  final Future<bool> Function(int) onAddTickets;
  /// Null means the normal owned-resident display is used.
  final List<TownResident>? debugTownResidents;
  final ValueChanged<bool> onDebugTownEnabled;
  final void Function(TownResident, bool) onDebugTownResidentChanged;
  /// Debug-only, off by default; never affects saved collection.
  final bool showUnownedPreviewVisitors;
  final ValueChanged<bool>? onUnownedPreviewVisitorsChanged;
  final SalonUnlockDebugMode salonUnlockMode;
  final ValueChanged<SalonUnlockDebugMode> onSalonUnlockModeChanged;
  final bool busy;

  Future<void> _addTickets(BuildContext context, int amount) async {
    if (busy) return;
    final succeeded = await onAddTickets(amount);
    if (!context.mounted || !succeeded) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('テスト用ことほぎを${amount * 30}追加しました')),
    );
  }

  Future<void> _confirmReset(BuildContext context) async {
    if (busy) return;
    final shouldReset = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('全ミッションをリセットしますか？'),
        content: const Text(
          'デイリー・ウィークリー・マンスリーの達成状態を'
          'すべて未達成に戻します。\n\n'
          'ことほぎと達成履歴は残ります。'
          'もう一度「できた！」を押すと、ことほぎが再び加算されます。'
          '\n\n※ 開発・動作確認用の機能です。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            key: const ValueKey('debug-confirm-reset-missions'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('全ミッションをリセット'),
          ),
        ],
      ),
    );
    if (!context.mounted || shouldReset != true) return;
    final succeeded = await onResetAll();
    if (!context.mounted || !succeeded) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('全ミッションの達成状態をリセットしました')),
    );
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      if (drawBackground)
        Positioned.fill(
          child: Image.asset(
            'assets/kotohogu/town_background.png',
            fit: BoxFit.cover,
            excludeFromSemantics: true,
          ),
        ),
      ListView(
        key: const ValueKey('debug-menu-scroll'),
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 36),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: parchment(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    uiPart('21_nav_menu', width: 55, height: 55),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'メニュー',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: wood,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Text(
                  '開発用・お祝い演出の確認',
                  style: TextStyle(
                    color: wood,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 9),
                const Text(
                  '拍手と「ありがとうを受け取る」を何度でも試せます。'
                  '\nことほぎ・達成状況・履歴は変わりません。',
                  style: TextStyle(color: wood, height: 1.65),
                ),
                const SizedBox(height: 18),
                const Text(
                  'チュートリアルの確認',
                  style: TextStyle(
                    color: wood,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'コトホギスの案内を最初から再生します。'
                  '\n閲覧記録やことほぎ、ミッションの達成状況は変わりません。',
                  style: TextStyle(color: wood, height: 1.65),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    key: const ValueKey('debug-replay-tutorial'),
                    onPressed: busy ? null : onReplayTutorial,
                    icon: const Icon(Icons.replay_rounded),
                    label: const Text('チュートリアルをもう一度見る'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF277A70),
                      minimumSize: const Size(0, 52),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 8),
                const Text(
                  '表示するミッション',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: wood,
                  ),
                ),
                const SizedBox(height: 8),
                InputDecorator(
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFFFFFAEE),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<Mission>(
                      key: const ValueKey('debug-preview-mission'),
                      isExpanded: true,
                      value: selectedMission,
                      onChanged: busy
                          ? null
                          : (mission) {
                              if (mission != null) onMissionChanged(mission);
                            },
                      items: [
                        for (final mission in Mission.values)
                          DropdownMenuItem<Mission>(
                            value: mission,
                            child: Text(
                              mission.title,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const ValueKey('debug-replay-celebration'),
                    onPressed: busy ? null : onPreview,
                    icon: const Icon(Icons.celebration_rounded),
                    label: const Text('もう一度ありがとうを受け取る'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFB94219),
                      foregroundColor: const Color(0xFFFFF7DD),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 8),
                const Text(
                  'まちに出す住民（デバッグ）',
                  style: TextStyle(
                    color: wood,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '未所持の住民も人数制限なく選べます。ホームとまちに反映され、'
                  '所持状況やガチャの結果は変わりません。'
                  '\nアプリを終了すると設定は消えます。',
                  style: TextStyle(color: wood, height: 1.6),
                ),
                SwitchListTile(
                  key: const ValueKey('debug-town-enable'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('好きな住民を表示する'),
                  subtitle: const Text('OFFで通常の所持キャラ表示に戻す'),
                  value: debugTownResidents != null,
                  onChanged: busy ? null : onDebugTownEnabled,
                ),
                if (debugTownResidents case final selected?) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '選択中：${selected.length} 匹',
                      key: const ValueKey('debug-town-count'),
                      style: const TextStyle(
                        color: wood,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  for (final resident in TownResident.values)
                    CheckboxListTile(
                      key: ValueKey('debug-town-resident-${resident.id}'),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      secondary: TownResidentAvatar(resident: resident, size: 48),
                      title: Text(resident.label),
                      subtitle: Text(resident.id),
                      value: selected.contains(resident),
                      onChanged: busy ? null : (checked) {
                              if (checked != null) {
                                onDebugTownResidentChanged(resident, checked);
                              }
                            },
                    ),
                ],
                if (developerToolsAvailable &&
                    onUnownedPreviewVisitorsChanged != null) ...[
                  const SizedBox(height: 14),
                  SwitchListTile(
                    key: const ValueKey('debug-unowned-preview-enable'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('未所持の配信住民をお試し表示'),
                    subtitle: const Text(
                      'OFFが通常表示（仲間だけ）。ONは開発テスト専用で、'
                      'ガチャの所持状況は変わりません。'
                      '\n「好きな住民を表示する」とは同時に使えません。',
                    ),
                    value: showUnownedPreviewVisitors,
                    onChanged: busy ? null : onUnownedPreviewVisitorsChanged,
                  ),
                ],
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 8),
                if (developerToolsAvailable) ...[
                  const Text('施設の開放テスト',
                      style: TextStyle(color: wood, fontSize: 20,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('💇 桜の美容室',
                      style: TextStyle(color: wood,
                          fontWeight: FontWeight.bold)),
                  Text(
                    '通常の状態：${isSalonUnlocked(progress.residents.owned) ? "開放" : "未開放"}'
                    '（おしゃれさんの所持で判定）',
                    key: const ValueKey('debug-salon-actual-status'),
                    style: const TextStyle(color: wood),
                  ),
                  RadioGroup<SalonUnlockDebugMode>(
                    groupValue: salonUnlockMode,
                    onChanged: (value) {
                      if (value != null && !busy) {
                        onSalonUnlockModeChanged(value);
                      }
                    },
                    child: Column(
                      children: [
                        for (final (mode, title) in [
                          (SalonUnlockDebugMode.normal, '通常の開放条件で判定'),
                          (SalonUnlockDebugMode.forceOpen, '強制開放してテスト'),
                          (SalonUnlockDebugMode.forceClosed, '強制未開放でテスト'),
                        ])
                          RadioListTile<SalonUnlockDebugMode>(
                            key: ValueKey('debug-salon-mode-${mode.name}'),
                            contentPadding: EdgeInsets.zero,
                            title: Text(title),
                            value: mode,
                            enabled: !busy,
                          ),
                      ],
                    ),
                  ),
                  Text(
                    'テスト中の状態：${isSalonAccessible(progress.residents.owned, debugMode: salonUnlockMode) ? "開放" : "未開放"}',
                    key: const ValueKey('debug-salon-effective-status'),
                    style: const TextStyle(color: wood,
                        fontWeight: FontWeight.bold),
                  ),
                  const Text(
                    '所持キャラ・ガチャ結果・既読記録は変更しません。'
                    '強制開放中は2人を仮表示して会話も試せます。'
                    '里山にも一時的に入れます。アプリ再起動で通常に戻ります。',
                    style: TextStyle(color: wood, fontSize: 12, height: 1.6),
                  ),
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 8),
                ],
                const Text(
                  'テスト用ことほぎの追加',
                  style: TextStyle(
                    color: wood,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '所持ことほぎ：${progress.residents.availableKotohogi(progress.points)}',
                  key: const ValueKey('debug-ticket-count'),
                  style: const TextStyle(color: wood),
                ),
                const SizedBox(height: 6),
                const Text(
                  '動作確認用です。達成履歴は変わりません。',
                  style: TextStyle(color: wood, fontSize: 12, height: 1.6),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      key: const ValueKey('debug-add-ticket-1'),
                      onPressed: busy ? null : () => _addTickets(context, 1),
                      icon: const Icon(Icons.confirmation_number_outlined),
                      label: const Text('ことほぎ +30'),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('debug-add-ticket-10'),
                      onPressed: busy ? null : () => _addTickets(context, 10),
                      icon: const Icon(Icons.confirmation_number_outlined),
                      label: const Text('ことほぎ +300'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 8),
                const Text(
                  'ミッション達成状態のリセット',
                  style: TextStyle(
                    color: wood,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '今日・今週・今月の達成を未達成に戻します。'
                  '\nことほぎやこれまでの履歴は残ります。',
                  style: TextStyle(color: wood, height: 1.6),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    key: const ValueKey('debug-reset-all-missions'),
                    onPressed: busy ? null : () => _confirmReset(context),
                    icon: const Icon(Icons.restart_alt_rounded),
                    label: const Text('全ミッションをリセット'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF9C351C),
                      side: const BorderSide(color: Color(0xFF9C351C)),
                      minimumSize: const Size(0, 52),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '所持ことほぎ：${progress.residents.availableKotohogi(progress.points)}（再生しても加算されません）',
                  key: const ValueKey('debug-current-points'),
                  style: const TextStyle(color: wood, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    ],
  );
}
