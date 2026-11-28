import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'duel_move_effect.dart';
import 'story_data.dart';
import 'sudoku_duel.dart';
import 'sudoku_ui.dart';

const _roomMarks = ['', '①', '②', '③', '④', '⑤', '⑥', '⑦', '⑧', '⑨'];
const _ink = Color(0xFF593A28);
const _green = Color(0xFF21685B);
const _rust = Color(0xFF96482D);
const _line = sudokuRule;
const _parchment = sudokuGiven;

extension _RivalProfile on DuelRival {
  String get style => switch (this) {
    DuelRival.mosaedo => '旗を狙い、あなたの次の一手を読む',
    DuelRival.oshisho => '4×4は最後まで、9×9は三手先まで読む',
    DuelRival.pomupomu => '見つけた旗を取りにいく',
    DuelRival.patissier => '次に取られそうな旗も確かめる',
  };
  String get greeting => switch (this) {
    DuelRival.mosaedo => 'いざ、旗の取り合いでござる！',
    DuelRival.oshisho => 'ほな、ゆっくり一局しまひょ。',
    DuelRival.pomupomu => 'しばいぬ、旗をいっぱい集めるぽむよ！',
    DuelRival.patissier => 'お茶の用意もできたよ。さあ、一局やろう！',
  };

  String farewell(int playerFlags, int npcFlags) =>
      switch ((this, npcFlags.compareTo(playerFlags))) {
        (DuelRival.mosaedo, > 0) => '拙者の勝利！ あおんあおん！',
        (DuelRival.mosaedo, < 0) => 'むむっ、その送り先までは読めなんだ。お見事でござる！',
        (DuelRival.mosaedo, _) => '旗は半分ずつ。よき勝負でござった！',
        (DuelRival.oshisho, > 0) => 'ほほほ。うちにええ旗が集まりましたえ。',
        (DuelRival.oshisho, < 0) => 'あの部屋に送りはるとは。お見事どす。',
        (DuelRival.oshisho, _) => '旗も仲よう半分こどすなぁ。',
        (DuelRival.pomupomu, > 0) => 'やったぽむ！ ぽむの旗、見て見てぽむ！',
        (DuelRival.pomupomu, < 0) => 'しばいぬ、じょうずぽむ〜！',
        (DuelRival.pomupomu, _) => 'おそろいの数ぽむ〜！',
        (DuelRival.patissier, > 0) => '最後までどきどきしたよ。次はお茶にしようか。',
        (DuelRival.patissier, < 0) => '参ったなあ。その部屋に送られるとは思わなかったよ。',
        (DuelRival.patissier, _) => 'きれいに半分ずつ。ケーキも半分こしよう。',
      };
}

class SudokuDuelView extends StatefulWidget {
  const SudokuDuelView({super.key})
    : match = null,
      position = null,
      onMove = null,
      onFinish = null,
      onDojoFinish = null,
      onDojoEnded = null,
      busy = false;
  const SudokuDuelView.story({
    super.key,
    required StoryDuel this.match,
    required SudokuDuel this.position,
    required VoidCallback this.onFinish,
    this.onMove,
    this.busy = false,
  }) : onDojoFinish = null, onDojoEnded = null;

  const SudokuDuelView.dojo({
    super.key,
    required SudokuDuel this.position,
    required ValueChanged<SudokuDuel> this.onDojoFinish,
    required VoidCallback this.onDojoEnded,
  }) : match = null, onMove = null, onFinish = null, busy = false;

  final StoryDuel? match;
  final SudokuDuel? position;
  final void Function(int cell, int digit)? onMove;
  final VoidCallback? onFinish;
  final ValueChanged<SudokuDuel>? onDojoFinish;
  final VoidCallback? onDojoEnded;
  final bool busy;

  @override
  State<SudokuDuelView> createState() => _SudokuDuelViewState();
}

class _SudokuDuelViewState extends State<SudokuDuelView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _effectController;
  DuelMoveEffect? _effect;
  final _random = Random();
  final _playedSizes = <DuelSize>{};
  DuelSize _size = DuelSize.mini;
  DuelRival? _rival;
  SudokuDuel? _game;
  int? _selected;
  int? _wrongDigit;
  Timer? _computerTurn;
  SudokuDuel? get _position => widget.onMove == null ? _game : widget.position;
  bool get _hasNpc => widget.match != null || _rival != null;

  @override
  void initState() {
    super.initState();
    _effectController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    )..addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _effect = null);
      }
    });
    _rival = widget.onDojoFinish == null ? widget.match?.rival : DuelRival.oshisho;
    _game = widget.position;
    _scheduleComputer();
  }

  @override
  void didUpdateWidget(SudokuDuelView old) {
    super.didUpdateWidget(old);
    final before = old.position;
    final after = widget.position;
    final cell = after?.lastCell;
    if (widget.onMove != null &&
        before != null &&
        after != null &&
        before.size == after.size &&
        cell != null &&
        before.valueAt(cell) == 0 &&
        after.valueAt(cell) != 0) {
      _showMoveEffect(before, after);
    }
    if (widget.onMove != null &&
        (widget.busy != old.busy ||
            widget.position?.lastCell != old.position?.lastCell)) {
      _scheduleComputer();
    }
  }

  @override
  void dispose() {
    _computerTurn?.cancel();
    _effectController.dispose();
    super.dispose();
  }

  String _name(DuelPlayer player) {
    if (widget.match case final match?) {
      return player == DuelPlayer.first
          ? match.player.label
          : match.opponent.label;
    }
    if (_rival == null) return player == DuelPlayer.first ? '先手' : '後手';
    return player == DuelPlayer.first ? 'あなた' : _rival!.resident.label;
  }

  void _start(DuelRival? rival) {
    _computerTurn?.cancel();
    _effectController.stop();
    setState(() {
      _effect = null;
      _rival = rival;
      _game = SudokuDuel.start(
        _size,
        shuffle: _playedSizes.add(_size) ? null : _random,
      );
      _selected = null;
      _wrongDigit = null;
    });
  }

  void _enter(int digit) {
    final game = _position;
    final selected = _selected;
    if (widget.busy ||
        game == null ||
        selected == null ||
        !game.canPlay(selected)) {
      return;
    }
    if (_hasNpc && game.turn == DuelPlayer.second) return;
    final next = game.play(selected, digit);
    if (next == null) {
      setState(() {
        _wrongDigit = digit;
        _showEffect(DuelMoveEffect(cell: selected, wrong: true));
      });
      return;
    }
    _record(next);
  }

  void _showEffect(DuelMoveEffect effect) {
    _effectController.stop();
    _effect = null;
    if (MediaQuery.disableAnimationsOf(context)) return;
    _effect = effect;
    _effectController.forward(from: 0);
  }

  void _showMoveEffect(SudokuDuel before, SudokuDuel after) {
    final cell = after.lastCell!;
    final room = after.size.roomOf(cell);
    final winner = after.score(DuelPlayer.first).compareTo(
      after.score(DuelPlayer.second),
    );
    _showEffect(DuelMoveEffect(
      cell: cell,
      capturedRoom: before.flagAt(room) == null && after.flagAt(room) != null
          ? room
          : null,
      targetRoom: after.isOver ? null : after.targetRoom,
      freeChoice: !after.isOver && after.targetRoom == null,
      victory: after.isOver && (_hasNpc ? winner > 0 : winner != 0),
      opponent: _hasNpc && before.turn == DuelPlayer.second,
    ));
  }

  void _record(SudokuDuel next) {
    final save = widget.onMove;
    final before = _position!;
    setState(() {
      if (save == null) {
        _game = next;
        _showMoveEffect(before, next);
      }
      _selected = null;
      _wrongDigit = null;
    });
    if (next.isOver) widget.onDojoEnded?.call();
    if (save != null) {
      final cell = next.lastCell!;
      save(cell, next.valueAt(cell));
    } else {
      _scheduleComputer();
    }
  }

  void _scheduleComputer() {
    _computerTurn?.cancel();
    final rival = _rival;
    final game = _position;
    if (!widget.busy &&
        _hasNpc &&
        game != null &&
        !game.isOver &&
        game.turn == DuelPlayer.second) {
      _computerTurn = Timer(const Duration(milliseconds: 750), () {
        _record(
          game.computerMove(rival, _random),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final game = _position;
    return game == null ? _lobby(context) : _match(context, game);
  }

  Widget _lobby(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('対戦相手をえらぶ', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      const Text(
        '「2」を入れたら、相手は②の部屋へ。部屋の最後の1マスを埋めると、旗を1本もらえます。送り先が満室なら、次の人は好きな部屋を選べます。',
      ),
      const SizedBox(height: 16),
      SegmentedButton<DuelSize>(
        segments: const [
          ButtonSegment(value: DuelSize.mini, label: Text('4×4')),
          ButtonSegment(value: DuelSize.classic, label: Text('9×9')),
        ],
        selected: {_size},
        onSelectionChanged: (selection) =>
            setState(() => _size = selection.single),
      ),
      const SizedBox(height: 8),
      Text(
        '行・列・部屋に1〜${_size.side}をひとつずつ。\n'
        '${_size == DuelSize.mini ? '4部屋を埋めて、旗が多い方の勝ち。同数は引き分け。' : '9本のうち、先に5本の旗を取ると勝ち。'}',
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 12),
      for (final rival in [DuelRival.mosaedo, DuelRival.oshisho])
        Card(
          child: ListTile(
            key: ValueKey('duel-rival-${rival.name}'),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 6,
            ),
            leading: Image.asset(
              rival.resident.idleAsset,
              width: 48,
              excludeFromSemantics: true,
            ),
            title: Text('${rival.resident.label}と対戦'),
            subtitle: Text(rival.style),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _start(rival),
          ),
        ),
      TextButton.icon(
        onPressed: () => _start(null),
        icon: const Icon(Icons.people_outline),
        label: const Text('同じ端末でふたりで遊ぶ'),
      ),
    ],
  );

  String _lastMove(SudokuDuel game) {
    final cell = game.lastCell;
    if (cell == null) return _rival?.greeting ?? '先手は①の部屋からはじめます。';
    final room = game.size.roomOf(cell);
    final placed = '${_roomMarks[room]}に「${game.valueAt(cell)}」';
    final flag = game.flagAt(room) != null;
    if (game.turn.other == DuelPlayer.second && _rival != null) {
      return switch (_rival!) {
        DuelRival.mosaedo => '$placedでござる！${flag ? ' この旗はいただき！' : ''}',
        DuelRival.oshisho => '$placedどす。${flag ? ' 旗、いただきますえ。' : ''}',
        DuelRival.pomupomu => '$placedぽむ！${flag ? ' 旗、もらったぽむ！' : ''}',
        DuelRival.patissier => '$placedを置くよ。${flag ? ' 旗が取れた！' : ''}',
      };
    }
    return '${_name(game.turn.other)}が$placedを置きました。${flag ? ' 旗を獲得！' : ''}';
  }

  Widget _castPortrait(StorySpeaker speaker, double width) {
    return switch (speaker.portrait) {
      final uri? => Image.network(
        uri.toString(),
        width: width,
        height: 50,
        excludeFromSemantics: true,
      ),
      null => Image.asset(
        speaker.localPortrait,
        width: width,
        height: 50,
        excludeFromSemantics: true,
      ),
    };
  }

  Widget _match(BuildContext context, SudokuDuel game) {
    final first = game.score(DuelPlayer.first);
    final second = game.score(DuelPlayer.second);
    final ended = game.isOver;
    final thinking = !ended && _hasNpc && game.turn == DuelPlayer.second;
    final room = game.targetRoom;
    final heading = ended
        ? first == second
              ? '引き分け！'
              : '${_name(first > second ? DuelPlayer.first : DuelPlayer.second)}の勝ち！'
        : '${_name(game.turn)}の番';
    final selected = _selected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.match case final match?) ...[
          Text(
            match.title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text(
            'あなたは${match.player.label}。書いた数字の部屋へ相手を送り、最後の1マスを埋めて旗を取ろう。送り先が満室なら好きな部屋へ。',
          ),
          if (match.stage case final stage?)
            Text('${stage.label}　${stage.objective}'),
        ],
        SudokuInfoPanel(
          child: Row(
              children: [
                if (widget.match case final match?) ...[
                  _castPortrait(match.player, 44),
                  _castPortrait(match.opponent, 50),
                  const SizedBox(width: 8),
                ] else if (_rival case final rival?) ...[
                  Image.asset(
                    rival.resident.idleAsset,
                    width: 50,
                    height: 56,
                    excludeFromSemantics: true,
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 16,
                        children: [
                          for (final player in DuelPlayer.values)
                            Text(
                              '${_name(player)}　${game.score(player)}${game.stage?.doubleRoom == null ? '本' : '点'}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: player == DuelPlayer.first
                                    ? _green
                                    : _rust,
                              ),
                            ),
                        ],
                      ),
                      Text(
                        ended && _rival != null
                            ? _rival!.farewell(first, second)
                            : _lastMove(game),
                      ),
                    ],
                  ),
                ),
              ],
          ),
        ),
        SudokuProgressBar(
          completed: [for (var room = 1; room <= game.size.side; room++) if (game.flagAt(room) != null) room].length,
          total: game.size.side,
        ),
        const SizedBox(height: 6),
        Semantics(
          liveRegion: true,
          child: Text(
            ended
                ? heading
                : '$heading　${room == null ? '好きな部屋へ' : '${_roomMarks[room]}の部屋へ'}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 496),
            child: SudokuBoardFrame(child: Stack(
              children: [
                _DuelBoard(
                  game: game,
                  selected: selected,
                  playerName: _name,
                  onSelect: thinking || ended || widget.busy
                      ? null
                      : (cell) => setState(() {
                          _selected = cell;
                          _wrongDigit = null;
                          if (_effect?.wrong == true) {
                            _effectController.stop();
                            _effect = null;
                          }
                        }),
                ),
                if (_effect case final effect?)
                  if (!MediaQuery.disableAnimationsOf(context))
                    Positioned.fill(
                      child: IgnorePointer(
                        child: ExcludeSemantics(
                          child: CustomPaint(
                            key: ValueKey(effect.wrong
                                ? 'duel-effect-wrong'
                                : 'duel-effect-correct'),
                            painter: DuelMoveEffectPainter(
                              boardSize: game.size,
                              effect: effect,
                              progress: _effectController,
                            ),
                          ),
                        ),
                      ),
                    ),
              ],
            )),
          ),
        ),
        const SizedBox(height: 8),
        if (ended && widget.onDojoFinish != null)
          FilledButton(
            key: const ValueKey('dojo-finish-duel'),
            onPressed: () => widget.onDojoFinish!(game),
            child: const Text('道場にもどる'),
          )
        else if (ended && widget.onFinish != null)
          FilledButton(
            key: const ValueKey('story-finish-duel'),
            onPressed: widget.busy ? null : widget.onFinish,
            child: const Text('お話のつづきへ'),
          )
        else if (ended) ...[
          FilledButton.icon(
            onPressed: () => _start(_rival),
            icon: const Icon(Icons.replay),
            label: const Text('もう一局'),
          ),
          TextButton(
            onPressed: () => setState(() {
              _effectController.stop();
              _effect = null;
              _game = null;
            }),
            child: const Text('対戦相手・盤面をえらぶ'),
          ),
        ] else ...[
          Semantics(
            liveRegion: true,
            child: Text(
              _wrongDigit != null
                  ? 'ここには「$_wrongDigit」は入りません。もう一度どうぞ。'
                  : thinking
                  ? '${_name(DuelPlayer.second)}が考え中…'
                  : selected == null
                  ? '空きマスを選んでね。'
                  : '${selected ~/ game.size.side + 1}行${selected % game.size.side + 1}列に入れる数字は？',
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var digit = 1; digit <= game.size.side; digit++)
                SizedBox(
                  width: 48,
                  child: FilledButton.tonal(
                    key: ValueKey('duel-digit-$digit'),
                    style: sudokuDigitStyle(),
                    onPressed: selected == null || thinking || widget.busy
                        ? null
                        : () => _enter(digit),
                    child: AnimatedBuilder(
                      animation: _effectController,
                      builder: (context, child) {
                        final shake = _effect?.wrong == true &&
                            _wrongDigit == digit &&
                            !MediaQuery.disableAnimationsOf(context);
                        final t = _effectController.value;
                        return Transform.translate(
                          offset: Offset(
                            shake ? sin(t * pi * 8) * (1 - t) * 5 : 0,
                            0,
                          ),
                          child: child,
                        );
                      },
                      child: SudokuDigitFace(digit: digit, enabled: selected != null && !thinking && !widget.busy),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _DuelBoard extends StatelessWidget {
  const _DuelBoard({
    required this.game,
    required this.selected,
    required this.onSelect,
    required this.playerName,
  });
  final SudokuDuel game;
  final int? selected;
  final ValueChanged<int>? onSelect;
  final String Function(DuelPlayer) playerName;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final side = game.size.side;
          final columns = game.size.boxColumns;
          final across = side ~/ columns;
          // Room margins and borders remain 2 + 2 on each side.
          final cellWidth = (constraints.maxWidth / across - 8) / columns;
          // Keep 9x9 compact enough for the keypad; use spare height for
          // the smaller boards without making existing cells shorter.
          final cellHeight = switch (side) {
            4 => cellWidth.clamp(50.0, 64.0).toDouble(),
            6 => cellWidth.clamp(36.0, 52.0).toDouble(),
            9 => 36.0,
            _ => throw StateError('Unexpected duel board size: $side'),
          };
          return Column(
            children: [
              for (var band = 0; band < side ~/ game.size.boxRows; band++)
                Row(
                  children: [
                    for (var stack = 0; stack < across; stack++)
                      Expanded(child: _room(band, stack, cellHeight)),
                  ],
                ),
            ],
          );
        },
      ),
    ),
  );

  Widget _room(int band, int stack, double cellHeight) {
    final rows = game.size.boxRows;
    final columns = game.size.boxColumns;
    final side = game.size.side;
    final room = band * (side ~/ columns) + stack + 1;
    final owner = game.flagAt(room);
    final bonus = game.bonusRoom == room;
    final active =
        !game.isOver &&
        game.hasSpace(room) &&
        (game.targetRoom == null || game.targetRoom == room);
    final marking = owner ?? game.turn;
    final color = marking == DuelPlayer.first ? _green : _rust;
    final highlighted = active || owner != null;
    return Container(
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        border: Border.all(width: 2, color: highlighted ? color : _line),
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            height: 24,
            color: highlighted ? color : const Color(0xFFDDB98B),
            alignment: Alignment.center,
            child: Semantics(
              label:
                  '$room番の部屋${bonus ? '、いちごの旗2点' : ''}${owner == null ? '' : '、${playerName(owner)}の旗'}',
              excludeSemantics: true,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (owner != null || active)
                      Icon(
                        owner == null ? Icons.arrow_right : Icons.flag,
                        size: 17,
                        color: Colors.white,
                      ),
                    Text(
                      '${_roomMarks[room]}${bonus ? ' 🍓2点' : ''}${owner == null ? '' : ' ${playerName(owner)}'}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: highlighted ? Colors.white : _ink,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          for (var y = 0; y < rows; y++)
            Row(
              children: [
                for (var x = 0; x < columns; x++)
                  Expanded(
                    child: _cell(
                      (band * rows + y) * side + stack * columns + x,
                      active,
                      cellHeight,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _cell(int cell, bool activeRoom, double cellHeight) {
    final side = game.size.side;
    final digit = game.valueAt(cell);
    final active = selected == cell;
    final last = game.lastCell == cell;
    final tap = onSelect != null && activeRoom && digit == 0
        ? () => onSelect!(cell)
        : null;
    return Semantics(
      key: ValueKey('duel-cell-$cell'),
      label:
          '${game.size.roomOf(cell)}番の部屋、${cell ~/ side + 1}行${cell % side + 1}列、${digit == 0 ? '空き' : digit}',
      selected: active,
      button: tap != null,
      onTap: tap,
      excludeSemantics: true,
      child: Material(
        color: active
            ? const Color(0xFFACE0CE)
            : last
            ? const Color(0xFFFFD89B)
            : game.isGiven(cell)
            ? _parchment
            : sudokuPaper,
        child: InkWell(
          onTap: tap,
          child: Container(
            height: cellHeight,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(
                color: active ? _green : _line,
                width: active ? 2 : 0.5,
              ),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                digit == 0 ? '' : '$digit',
                style: TextStyle(
                  fontSize: side == 4 ? 28 : 22,
                  fontWeight: FontWeight.w700,
                  color: last
                      ? (game.turn.other == DuelPlayer.first ? _green : _rust)
                      : _ink,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
