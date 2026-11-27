import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dojo_puzzle.dart';
import 'duel_move_effect.dart';
import 'resident_collection.dart';
import 'sudoku_duel.dart';
import 'sudoku_duel_view.dart';

enum _Mode { solo, duel }

class KotohoguruDojo extends StatefulWidget {
  const KotohoguruDojo({super.key});

  @override
  State<KotohoguruDojo> createState() => _KotohoguruDojoState();
}

class _KotohoguruDojoState extends State<KotohoguruDojo> {
  final _random = Random();
  final _preferences = SharedPreferencesAsync();
  late Future<Map<DojoLevel, (int, int)>> _records;
  _Mode _mode = _Mode.solo;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _records = _load(_mode);
  }

  String _key(_Mode mode, DojoLevel level) =>
      'kotohoguru.dojo.v1.${mode.name}.${level.name}';

  Future<(int, int)> _read(_Mode mode, DojoLevel level) async {
    final raw = await _preferences.getString(_key(mode, level));
    if (raw == null) return (0, 0);
    final data = jsonDecode(raw) as List<dynamic>;
    if (data.length != 2 || data[0] is! int || data[1] is! int ||
        (data[0] as int) < 1 || (data[1] as int) < 0) {
      throw FormatException('Invalid dojo record: ${mode.name}/${level.name}', raw);
    }
    return (data[0] as int, data[1] as int);
  }

  Future<Map<DojoLevel, (int, int)>> _load(_Mode mode) async => {
    for (final level in DojoLevel.values) level: await _read(mode, level),
  };

  String _time(int seconds) =>
      '${seconds ~/ 60}分${(seconds % 60).toString().padLeft(2, '0')}秒';

  Future<void> _play(DojoLevel level) async {
    if (_playing) return;
    final mode = _mode;
    final puzzle = DojoPuzzle.generate(level, _random);
    setState(() => _playing = true);
    try {
      final seconds = await Navigator.of(context).push<int>(
        MaterialPageRoute<int>(
          builder: (_) => mode == _Mode.solo
              ? DojoPracticePage.solo(puzzle: puzzle)
              : DojoPracticePage.duel(puzzle: puzzle),
        ),
      );
      if (!mounted) return;
      if (seconds != null) {
        final (count, best) = await _read(mode, level);
        await _preferences.setString(
          _key(mode, level),
          jsonEncode([count + 1, count == 0 ? seconds : min(best, seconds)]),
        );
        if (mounted) setState(() => _records = _load(mode));
      }
    } finally {
      if (mounted) setState(() => _playing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('コトホグル道場')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Image.asset(TownResident.c031_kimono_fox.idleAsset,
                  width: 70, height: 70, excludeFromSemantics: true),
              const SizedBox(width: 12),
              const Expanded(child: Text('ほほほ。今日はどんな稽古にしまひょ？\nむずかしいのも、やさしいのも、好きに選んでおくれやす。')),
            ],
          ),
          const SizedBox(height: 16),
          SegmentedButton<_Mode>(
            segments: const [
              ButtonSegment(value: _Mode.solo, label: Text('ひとり数独')),
              ButtonSegment(value: _Mode.duel, label: Text('旗取り対戦')),
            ],
            selected: {_mode},
            onSelectionChanged: _playing ? null : (selection) => setState(() {
              _mode = selection.single;
              _records = _load(_mode);
            }),
          ),
          const SizedBox(height: 8),
          Text(_mode == _Mode.solo
              ? 'すべての空欄を埋めよう。候補のメモも使えます。'
              : 'おししょうとの旗取り。数字で相手を送り、部屋の最後のマスを埋めて旗を取ろう。'),
          const SizedBox(height: 8),
          FutureBuilder<Map<DojoLevel, (int, int)>>(
            future: _records,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Text('道場の記録を読み込めませんでした。\n${snapshot.error}');
              }
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final records = snapshot.requireData;
              return Column(
                children: [
                  for (final level in DojoLevel.values)
                    Card(
                      child: ListTile(
                        key: ValueKey('dojo-level-${level.name}'),
                        title: Text(level.label, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          '${level.description}\n'
                          '${_mode == _Mode.solo ? 'クリア' : '勝利'} ${records[level]!.$1}回'
                          '${records[level]!.$1 == 0 ? '' : '　最速 ${_time(records[level]!.$2)}'}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _playing ? null : () => _play(level),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    ),
  );
}

class DojoPracticePage extends StatefulWidget {
  const DojoPracticePage.solo({super.key, required this.puzzle}) : _mode = _Mode.solo;
  const DojoPracticePage.duel({super.key, required this.puzzle}) : _mode = _Mode.duel;
  final DojoPuzzle puzzle;
  final _Mode _mode;

  @override
  State<DojoPracticePage> createState() => _PracticePageState();
}

class _PracticePageState extends State<DojoPracticePage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _effectController;
  DuelMoveEffect? _effect;
  final _watch = Stopwatch();
  late final SudokuDuel _duel = widget.puzzle.duel();
  late final List<int> _board = List.of(widget.puzzle.givens);
  late final List<Set<int>> _notes = List.generate(_board.length, (_) => <int>{});
  int? _selected;
  bool _noteMode = false;
  bool _complete = false;

  @override
  void initState() {
    super.initState();
    _watch.start();
    _effectController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    )..addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _effect = null);
      }
    });
  }

  @override
  void dispose() {
    _watch.stop();
    _effectController.dispose();
    super.dispose();
  }

  void _clearEffect() {
    _effectController.stop();
    _effect = null;
  }

  void _showEffect(DuelMoveEffect effect) {
    _clearEffect();
    if (MediaQuery.disableAnimationsOf(context)) return;
    _effect = effect;
    _effectController.forward(from: 0);
  }

  void _enter(int digit) {
    final cell = _selected;
    if (cell == null || _complete || widget.puzzle.givens[cell] != 0) return;
    setState(() {
      _clearEffect();
      if (_noteMode && digit != 0) {
        if (_board[cell] != 0) return;
        if (!_notes[cell].add(digit)) _notes[cell].remove(digit);
        return;
      }
      final changed = _board[cell] != digit;
      _board[cell] = digit;
      _notes[cell].clear();
      if (widget.puzzle.isComplete(_board)) {
        _complete = true;
        _watch.stop();
      }
      if (changed && digit != 0) {
        _showEffect(DuelMoveEffect(
          cell: cell,
          wrong: digit != widget.puzzle.answer[cell],
          victory: _complete,
        ));
      }
    });
  }

  bool _conflict(int cell) {
    final value = _board[cell];
    if (value == 0) return false;
    final size = widget.puzzle.size;
    for (var i = 0; i < _board.length; i++) {
      if (i != cell && _board[i] == value &&
          (i ~/ size.side == cell ~/ size.side ||
           i % size.side == cell % size.side ||
           size.roomOf(i) == size.roomOf(cell))) {
        return true;
      }
    }
    return false;
  }

  Widget _cell(int cell) {
    final size = widget.puzzle.size;
    final fixed = widget.puzzle.givens[cell] != 0;
    final value = _board[cell];
    final selected = _selected == cell;
    final conflict = _conflict(cell);
    final incorrect = !fixed && value != 0 && value != widget.puzzle.answer[cell];
    final error = conflict || incorrect;
    final notes = _notes[cell].toList()..sort();
    const line = Color(0xFF66513C);
    return Semantics(
      key: ValueKey('dojo-cell-$cell'),
      label: '${cell ~/ size.side + 1}行${cell % size.side + 1}列、'
          '${value == 0 ? '空欄' : value}'
          '${fixed ? '、固定' : ''}${incorrect ? '、不正解' : ''}'
          '${notes.isEmpty ? '' : '、候補 ${notes.join(' ')}'}',
      selected: selected,
      button: !fixed && !_complete,
      child: Material(
        color: error ? const Color(0xFFFFDFD9) : selected
            ? const Color(0xFFC8E8E0) : fixed
            ? const Color(0xFFF4E5C9) : Colors.white,
        child: InkWell(
          onTap: fixed || _complete ? null : () => setState(() => _selected = cell),
          child: Container(
            decoration: BoxDecoration(border: Border(
              right: BorderSide(color: line, width: (cell % size.side + 1) % size.boxColumns == 0 ? 2 : .5),
              bottom: BorderSide(color: line, width: (cell ~/ size.side + 1) % size.boxRows == 0 ? 2 : .5),
            )),
            alignment: Alignment.center,
            padding: const EdgeInsets.all(2),
            child: value == 0 && notes.isNotEmpty
                ? Column(
                    children: [
                      for (var row = 0; row < size.boxRows; row++)
                        Expanded(
                          child: Row(
                            children: [
                              for (var column = 0; column < size.boxColumns; column++)
                                Expanded(
                                  child: Center(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        notes.contains(row * size.boxColumns + column + 1)
                                            ? '${row * size.boxColumns + column + 1}' : '',
                                        style: const TextStyle(fontSize: 12, color: Color(0xFF21685B)),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  )
                : FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      value == 0 ? '' : '$value',
                      style: TextStyle(
                        fontSize: 25,
                        color: error ? const Color(0xFF9B2119) : fixed
                            ? const Color(0xFF593A28) : const Color(0xFF21685B),
                        fontWeight: fixed ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _solo() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(_complete ? 'お見事どす！ ようできはりましたなぁ。'
          : '行・列・部屋に1〜${widget.puzzle.size.side}をひとつずつ。'),
      const SizedBox(height: 12),
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: AspectRatio(
            aspectRatio: 1,
            child: Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(border: Border.all(color: const Color(0xFF66513C), width: 2)),
                  child: GridView.count(
                    padding: EdgeInsets.zero,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: widget.puzzle.size.side,
                    children: [for (var i = 0; i < _board.length; i++) _cell(i)],
                  ),
                ),
                if (_effect case final effect?)
                  if (!MediaQuery.disableAnimationsOf(context))
                    IgnorePointer(
                      child: ExcludeSemantics(
                        child: CustomPaint(
                          key: ValueKey(effect.wrong ? 'dojo-effect-wrong' : 'dojo-effect-correct'),
                          painter: DuelMoveEffectPainter(
                            boardSize: widget.puzzle.size,
                            effect: effect,
                            progress: _effectController,
                            flatBoard: true,
                          ),
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: 12),
      if (_complete)
        FilledButton(
          key: const ValueKey('dojo-finish-solo'),
          onPressed: () => Navigator.of(context).pop(_watch.elapsed.inSeconds),
          child: const Text('道場にもどる'),
        )
      else ...[
        if (!_board.contains(0))
          const Text('まだ正しくない数字があります。もう一度見直しまひょ。'),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var digit = 1; digit <= widget.puzzle.size.side; digit++)
              SizedBox(
                width: 48,
                child: FilledButton.tonal(
                  key: ValueKey('dojo-digit-$digit'),
                  style: FilledButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(48, 48)),
                  onPressed: _selected == null ? null : () => _enter(digit),
                  child: Text('$digit', style: const TextStyle(fontSize: 22)),
                ),
              ),
          ],
        ),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          children: [
            FilterChip(
              label: const Text('候補メモ'),
              selected: _noteMode,
              onSelected: (value) => setState(() => _noteMode = value),
            ),
            TextButton.icon(
              onPressed: _selected == null ? null : () => _enter(0),
              icon: const Icon(Icons.backspace_outlined),
              label: const Text('消す'),
            ),
          ],
        ),
      ],
    ],
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('道場・${widget.puzzle.level.label}')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: widget._mode == _Mode.solo ? _solo() : SudokuDuelView.dojo(
          position: _duel,
          onDojoEnded: _watch.stop,
          onDojoFinish: (game) {
            final won = game.score(DuelPlayer.first) > game.score(DuelPlayer.second);
            Navigator.of(context).pop(won ? _watch.elapsed.inSeconds : null);
          },
        ),
      ),
    ),
  );
}
