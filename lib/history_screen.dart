import 'package:flutter/material.dart';

import 'missions_screen.dart';
import 'progress.dart';

/// A celebration journal, never an attendance or streak tracker.
class HistoryScreen extends StatefulWidget {
  /// Keep the standalone journal and the shared-header version in sync.
  static const backgroundAsset = MissionsScreen.backgroundAsset;

  const HistoryScreen({
    super.key,
    required this.progress,
    required this.busy,
    required this.onClear,
    this.drawBackground = true,
  });

  final bool drawBackground;
  final Progress progress;
  final bool busy;
  final Future<void> Function() onClear;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  static const brown = Color(0xFF63351F);
  static const gold = Color(0xFFD79539);
  static const cream = Color(0xFFFFF5DE);

  late DateTime _month;
  String? _selectedDay;

  @override
  void initState() {
    super.initState();
    final today = DateTime.parse(widget.progress.day);
    _month = DateTime(today.year, today.month);
    _selectedDay = _latestInMonth(_month);
  }

  String _key(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  String? _latestInMonth(DateTime month) {
    final prefix =
        '${month.year.toString().padLeft(4, '0')}-'
        '${month.month.toString().padLeft(2, '0')}-';
    final dates = widget.progress.history.keys
        .where((date) => date.startsWith(prefix))
        .toList()..sort();
    return dates.isEmpty ? null : dates.last;
  }

  void _changeMonth(int step) {
    setState(() {
      _month = DateTime(_month.year, _month.month + step);
      _selectedDay = _latestInMonth(_month);
    });
  }

  Future<void> _confirmDelete() async {
    if (widget.busy || widget.progress.history.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('すべての履歴を削除しますか？'),
        content: const Text(
          '言祝ぎの履歴は元に戻せません。\n'
          '累計ことほぎと今日の達成状態は、そのまま残ります。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('やめる'),
          ),
          FilledButton(
            key: const ValueKey('confirm-clear-history'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB94729),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('履歴を削除する'),
          ),
        ],
      ),
    );
    if (!mounted || confirm != true) return;
    await widget.onClear();
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.progress;
    final today = DateTime.parse(progress.day);
    final oldest = progress.history.isEmpty
        ? progress.day
        : (progress.history.keys.toList()..sort()).first;
    final oldestMonth = oldest.substring(0, 7);
    final currentMonth = progress.day.substring(0, 7);
    final shown = _key(_month).substring(0, 7);
    final entries = progress.history.entries.where(
      (entry) => entry.key.startsWith('$shown-'),
    ).toList();
    final monthDays = entries.length;
    final monthActions = entries.fold<int>(
      0, (total, entry) => total + entry.value.length,
    );
    final start30 = _key(DateTime(today.year, today.month, today.day - 29));
    final recent = progress.history.entries.where(
      (entry) => entry.key.compareTo(start30) >= 0 &&
          entry.key.compareTo(progress.day) <= 0,
    ).toList();
    final recentActions = recent.fold<int>(
      0, (total, entry) => total + entry.value.length,
    );
    final recentSorted = [...recent]
      ..sort((a, b) => b.key.compareTo(a.key));
    final selected = progress.history[_selectedDay];
    final chosenDate = selected == null ? null : DateTime.parse(_selectedDay!);

    final first = DateTime(_month.year, _month.month);
    final offset = first.weekday - 1; // Monday starts the week.
    final count = DateTime(_month.year, _month.month + 1, 0).day;
    final cells = offset + count;
    final scale = MediaQuery.textScalerOf(context);

    return Stack(
      children: [
        if (widget.drawBackground)
          Positioned.fill(
            child: Image.asset(
              HistoryScreen.backgroundAsset,
              key: const ValueKey('history-background'),
              fit: BoxFit.cover,
              excludeFromSemantics: true,
            ),
          ),
        ListView(
          key: const ValueKey('history-scroll'),
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 36),
          children: [
            _panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.auto_stories_rounded, color: brown, size: 30),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'これまで言祝がれた日々',
                          style: TextStyle(
                            color: brown,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'できた日のことを、いつでも思い出せます。',
                    style: TextStyle(color: brown),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    '直近30日は ${recent.length}日、'
                    '$recentActions個の行動を言祝ぎました。',
                    key: const ValueKey('history-last-30'),
                    style: const TextStyle(
                      color: brown, fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (recentSorted.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text(
                      '最近の言祝ぎ（タップして振り返る）',
                      style: TextStyle(color: brown, fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 5,
                      children: [
                        for (final entry in recentSorted)
                          ActionChip(
                            key: ValueKey('recent-history-${entry.key}'),
                            label: Text(
                              '${DateTime.parse(entry.key).month}/'
                              '${DateTime.parse(entry.key).day} 祝',
                            ),
                            onPressed: () {
                              final date = DateTime.parse(entry.key);
                              setState(() {
                                _month = DateTime(date.year, date.month);
                                _selectedDay = entry.key;
                              });
                            },
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            _panel(
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        key: const ValueKey('previous-history-month'),
                        tooltip: '前の月',
                        onPressed: shown.compareTo(oldestMonth) <= 0
                            ? null : () => _changeMonth(-1),
                        icon: const Icon(Icons.chevron_left_rounded),
                        color: brown,
                      ),
                      Expanded(
                        child: Text(
                          '${_month.year}年${_month.month}月',
                          key: const ValueKey('history-month-title'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: brown, fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('next-history-month'),
                        tooltip: '次の月',
                        onPressed: shown.compareTo(currentMonth) >= 0
                            ? null : () => _changeMonth(1),
                        icon: const Icon(Icons.chevron_right_rounded),
                        color: brown,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (final weekday in ['月', '火', '水', '木', '金', '土', '日'])
                        Expanded(
                          child: Center(
                            child: Text(
                              weekday,
                              style: const TextStyle(
                                color: brown, fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      mainAxisSpacing: 4,
                      crossAxisSpacing: 3,
                      childAspectRatio: scale.scale(1) > 1.3 ? .62 : .75,
                    ),
                    itemCount: cells,
                    itemBuilder: (context, index) {
                      if (index < offset) return const SizedBox.shrink();
                      final day = index - offset + 1;
                      final date = _key(DateTime(_month.year, _month.month, day));
                      final celebrated = progress.history[date]?.isNotEmpty ?? false;
                      final active = _selectedDay == date && celebrated;
                      return Semantics(
                        label: celebrated ? '$day日、祝' : '$day日',
                        button: celebrated,
                        child: InkWell(
                          key: ValueKey('history-day-$day'),
                          borderRadius: BorderRadius.circular(12),
                          onTap: celebrated
                              ? () => setState(() => _selectedDay = date)
                              : null,
                          child: Container(
                            decoration: BoxDecoration(
                              color: active ? const Color(0xFFFFE1A2) :
                                  celebrated ? const Color(0xFFFFF0C8) :
                                  Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                              border: active
                                  ? Border.all(color: gold, width: 2)
                                  : null,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  '$day',
                                  style: TextStyle(
                                    color: brown,
                                    fontSize: 13,
                                    fontWeight: celebrated
                                        ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                                if (celebrated)
                                  const Text(
                                    '祝',
                                    style: TextStyle(
                                      color: Color(0xFFC24D27),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '今月は$monthDays日、$monthActions個の行動を言祝ぎました。',
                    key: const ValueKey('history-month-summary'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: brown, fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _panel(
              child: selected == null || chosenDate == null
                  ? const Text(
                      '言祝ぎのある日を選ぶと、できたことが見られます。\n'
                      '記録のない日も、ただの大切な一日です。',
                      style: TextStyle(color: brown, height: 1.8),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${chosenDate.month}月${chosenDate.day}日',
                          key: const ValueKey('history-selected-date'),
                          style: const TextStyle(
                            fontSize: 21, fontWeight: FontWeight.w900,
                            color: brown,
                          ),
                        ),
                        const SizedBox(height: 12),
                        for (final mission in Mission.values)
                          if (selected.contains(mission))
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 5),
                              child: Row(
                                children: [
                                  const Icon(Icons.favorite, size: 18,
                                      color: Color(0xFFCC6656)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      mission.title,
                                      style: const TextStyle(color: brown),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        const SizedBox(height: 10),
                        Text(
                          'この日は${selected.length}つの行動を言祝ぎました。',
                          style: const TextStyle(
                            color: brown, fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 20),
            TextButton.icon(
              key: const ValueKey('clear-history'),
              onPressed: widget.busy || progress.history.isEmpty
                  ? null : _confirmDelete,
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('すべての履歴を削除'),
              style: TextButton.styleFrom(foregroundColor: brown),
            ),
            const Text(
              '記録はこの端末内に保存されます。\n'
              '履歴を消しても、累計ことほぎと今日の達成は消えません。',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: brown, fontSize: 12, height: 1.7,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _panel({required Widget child}) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: cream,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: gold, width: 2),
      boxShadow: const [
        BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 3)),
      ],
    ),
    child: child,
  );
}
