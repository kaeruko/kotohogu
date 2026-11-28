import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dojo_puzzle.dart';
import 'duel_move_effect.dart';
import 'resident_collection.dart';
import 'sudoku_duel.dart';
import 'sudoku_duel_view.dart';
import 'sudoku_ui.dart';

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

  void _selectMode(_Mode mode) {
    if (_playing || _mode == mode) return;
    setState(() {
      _mode = mode;
      _records = _load(mode);
    });
  }

  Widget _modeTab(_Mode mode, String label) {
    final selected = _mode == mode;
    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: Colors.transparent,
          child: Ink(
            decoration: BoxDecoration(
              image: DecorationImage(
                image: AssetImage(
                  'assets/kotohoggle/dojo_tab_${selected ? 'selected' : 'normal'}.webp',
                ),
                fit: BoxFit.fill,
              ),
            ),
            child: InkWell(
              key: ValueKey('dojo-mode-${mode.name}'),
              borderRadius: BorderRadius.circular(12),
              onTap: _playing ? null : () => _selectMode(mode),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (selected) ...[
                      const Icon(Icons.check_rounded, size: 19, color: sudokuInk),
                      const SizedBox(width: 3),
                    ],
                    Flexible(
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: sudokuInk,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // The enum values are save keys. Keep them unchanged; only map the
  // filenames for the last two icons (mountain and oni) explicitly.
  String _levelIcon(DojoLevel level) => switch (level) {
    DojoLevel.entry => 'entry',
    DojoLevel.beginner => 'beginner',
    DojoLevel.intermediate => 'intermediate',
    DojoLevel.advanced => 'advanced',
    DojoLevel.master => 'expert',
    DojoLevel.oni => 'master',
  };

  Widget _levelCard(DojoLevel level, (int, int) record) {
    final (count, best) = record;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: AssetImage('assets/kotohoggle/dojo_level_panel.webp'),
              fit: BoxFit.fill,
            ),
          ),
          child: InkWell(
            key: ValueKey('dojo-level-${level.name}'),
            borderRadius: BorderRadius.circular(12),
            onTap: _playing ? null : () => _play(level),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(19, 12, 15, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          level.label,
                          style: const TextStyle(
                            fontSize: 23,
                            height: 1.15,
                            fontWeight: FontWeight.w900,
                            color: sudokuInk,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          level.description,
                          style: const TextStyle(
                            fontSize: 13,
                            color: sudokuInk,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${_mode == _Mode.solo ? 'クリア' : '勝利'} $count回'
                          '${count == 0 ? '' : '　最速 ${_time(best)}'}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: sudokuInk,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 5),
                  Image.asset(
                    'assets/kotohoggle/dojo_level_${_levelIcon(level)}.webp',
                    width: 40,
                    height: 40,
                    fit: BoxFit.contain,
                    excludeFromSemantics: true,
                  ),
                  const SizedBox(width: 5),
                  Opacity(
                    opacity: _playing ? .45 : 1,
                    child: Image.asset(
                      'assets/kotohoggle/dojo_play_button.webp',
                      width: 44,
                      height: 44,
                      fit: BoxFit.contain,
                      excludeFromSemantics: true,
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: sudokuAppBar(context, 'コトホグル道場'),
    body: SudokuPaperBackground(
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 16),
              children: [
                Row(
                  children: [
                    Image.asset(
                      TownResident.c031_kimono_fox.idleAsset,
                      width: 62,
                      height: 72,
                      fit: BoxFit.contain,
                      excludeFromSemantics: true,
                    ),
                    const SizedBox(width: 2),
                    const Expanded(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          image: DecorationImage(
                            image: AssetImage('assets/kotohoggle/dojo_speech_panel.webp'),
                            fit: BoxFit.fill,
                          ),
                        ),
                        child: Padding(
                          // Keep text inside the inner border, clear of the tail
                          // and the ornamental corners of the speech artwork.
                          padding: EdgeInsets.fromLTRB(36, 22, 26, 24),
                          child: Text(
                            'ほほほ。今日はどんな稽古にしまひょ？\nむずかしいのも、やさしいのも、好きに選んでおくれやす。',
                            style: TextStyle(
                              color: sudokuInk,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _modeTab(_Mode.solo, 'ひとり数独'),
                    const SizedBox(width: 3),
                    _modeTab(_Mode.duel, '旗取り対戦'),
                  ],
                ),
                const SizedBox(height: 9),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    _mode == _Mode.solo
                        ? 'すべての空欄を埋めよう。候補のメモも使えます。'
                        : 'おししょうとの旗取り。数字で相手を送り、部屋の最後のマスを埋めて旗を取ろう。',
                    style: const TextStyle(
                      fontSize: 14,
                      color: sudokuInk,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
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
                          _levelCard(level, records[level]!),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
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
    final hasNotes = value == 0 && notes.isNotEmpty;
    const line = sudokuRule;
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
            ? sudokuGiven : sudokuPaper,
        child: InkWell(
          onTap: fixed || _complete ? null : () => setState(() => _selected = cell),
          child: Container(
            decoration: BoxDecoration(border: Border(
              right: BorderSide(color: line, width: (cell % size.side + 1) % size.boxColumns == 0 ? 2 : .5),
              bottom: BorderSide(color: line, width: (cell ~/ size.side + 1) % size.boxRows == 0 ? 2 : .5),
            )),
            alignment: Alignment.center,
            padding: EdgeInsets.all(hasNotes ? 0.5 : 2),
            child: hasNotes
                ? _CandidateNotes(digits: notes)
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
      SudokuProgressBar(
        completed: [for (var i = 0; i < _board.length; i++) if (_board[i] == widget.puzzle.answer[i]) i].length,
        total: _board.length,
      ),
      const SizedBox(height: 4),
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 496),
          child: SudokuBoardFrame(child: AspectRatio(
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
          )),
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
                  style: sudokuDigitStyle(),
                  onPressed: _selected == null ? null : () => _enter(digit),
                  child: SudokuDigitFace(digit: digit, enabled: _selected != null),
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
    appBar: sudokuAppBar(context, '道場・${widget.puzzle.level.label}'),
    body: SudokuPaperBackground(child: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
        child: widget._mode == _Mode.solo ? _solo() : SudokuDuelView.dojo(
          position: _duel,
          onDojoEnded: _watch.stop,
          onDojoFinish: (game) {
            final won = game.score(DuelPlayer.first) > game.score(DuelPlayer.second);
            Navigator.of(context).pop(won ? _watch.elapsed.inSeconds : null);
          },
        ),
      ),
    )),
  );
}

/// Pack only the entered candidates, rather than reserving a slot for every
/// possible digit. FittedBox keeps each glyph inside its share of the cell.
class _CandidateNotes extends StatelessWidget {
  const _CandidateNotes({required this.digits});

  final List<int> digits;

  @override
  Widget build(BuildContext context) {
    final count = digits.length;
    final columns = count == 1 ? 1 : count <= 4 ? 2 : 3;
    final rows = (count + columns - 1) ~/ columns;
    final fontSize = count == 1 ? 22.0 : count == 2 ? 20.0 : count <= 4 ? 18.0 : 16.0;
    return Column(
      children: [
        for (var row = 0; row < rows; row++)
          Expanded(
            child: Row(
              children: [
                for (var column = 0; column < columns; column++)
                  Expanded(
                    child: row * columns + column < count
                        ? Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                '${digits[row * columns + column]}',
                                key: ValueKey(
                                  'dojo-note-${digits[row * columns + column]}',
                                ),
                                style: TextStyle(
                                  fontSize: fontSize,
                                  height: 1,
                                  letterSpacing: 0,
                                  color: const Color(0xFF37475B),
                                  fontWeight: FontWeight.w600,
                                  decoration: count == 1
                                      ? TextDecoration.underline
                                      : TextDecoration.none,
                                ),
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
