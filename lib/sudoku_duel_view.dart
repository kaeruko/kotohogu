import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'resident_collection.dart';
import 'sudoku_duel.dart';

const _roomMarks = ['', '①', '②', '③', '④', '⑤', '⑥', '⑦', '⑧', '⑨'];
const _ink = Color(0xFF593A28);
const _green = Color(0xFF21685B);
const _rust = Color(0xFF96482D);
const _line = Color(0xFFB8A78C);
const _parchment = Color(0xFFF4EAD7);

extension _RivalProfile on DuelRival {
  TownResident get resident => switch (this) {
    DuelRival.mosaedo => TownResident.c036_mosa,
    DuelRival.oshisho => TownResident.c031_kimono_fox,
  };
  String get style => switch (this) {
    DuelRival.mosaedo => '旗を狙い、あなたの次の一手を読む',
    DuelRival.oshisho => '4×4は最後まで、9×9は三手先まで読む',
  };
  String get greeting => switch (this) {
    DuelRival.mosaedo => 'いざ、旗の取り合いでござる！',
    DuelRival.oshisho => 'ほな、ゆっくり一局しまひょ。',
  };

  String farewell(int playerFlags, int npcFlags) =>
      switch ((this, npcFlags.compareTo(playerFlags))) {
        (DuelRival.mosaedo, > 0) => '拙者の勝利！ あおんあおん！',
        (DuelRival.mosaedo, < 0) => 'むむっ、その送り先までは読めなんだ。お見事でござる！',
        (DuelRival.mosaedo, _) => '旗は半分ずつ。よき勝負でござった！',
        (DuelRival.oshisho, > 0) => 'ほほほ。うちにええ旗が集まりましたえ。',
        (DuelRival.oshisho, < 0) => 'あの部屋に送りはるとは。お見事どす。',
        (DuelRival.oshisho, _) => '旗も仲よう半分こどすなぁ。',
      };
}

class SudokuDuelView extends StatefulWidget {
  const SudokuDuelView({super.key});

  @override
  State<SudokuDuelView> createState() => _SudokuDuelViewState();
}

class _SudokuDuelViewState extends State<SudokuDuelView> {
  final _random = Random();
  final _playedSizes = <DuelSize>{};
  DuelSize _size = DuelSize.mini;
  DuelRival? _rival;
  SudokuDuel? _game;
  int? _selected;
  int? _wrongDigit;
  Timer? _computerTurn;

  @override
  void dispose() {
    _computerTurn?.cancel();
    super.dispose();
  }

  String _name(DuelPlayer player) {
    if (_rival == null) return player == DuelPlayer.first ? '先手' : '後手';
    return player == DuelPlayer.first ? 'あなた' : _rival!.resident.label;
  }

  void _start(DuelRival? rival) {
    _computerTurn?.cancel();
    setState(() {
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
    final game = _game;
    final selected = _selected;
    if (game == null || selected == null || !game.canPlay(selected)) return;
    if (_rival != null && game.turn == DuelPlayer.second) return;
    final next = game.play(selected, digit);
    if (next == null) {
      setState(() => _wrongDigit = digit);
      return;
    }
    setState(() {
      _game = next;
      _selected = null;
      _wrongDigit = null;
    });
    final rival = _rival;
    if (rival != null && !next.isOver) {
      _computerTurn = Timer(const Duration(milliseconds: 750), () {
        setState(() => _game = next.computerMove(rival, _random));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final game = _game;
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
      for (final rival in DuelRival.values)
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
      };
    }
    return '${_name(game.turn.other)}が$placedを置きました。${flag ? ' 旗を獲得！' : ''}';
  }

  Widget _match(BuildContext context, SudokuDuel game) {
    final first = game.score(DuelPlayer.first);
    final second = game.score(DuelPlayer.second);
    final ended = game.isOver;
    final thinking = !ended && _rival != null && game.turn == DuelPlayer.second;
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
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                if (_rival case final rival?) ...[
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
                              '${_name(player)}　${game.score(player)}本',
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
        _DuelBoard(
          game: game,
          selected: selected,
          playerName: _name,
          onSelect: thinking || ended
              ? null
              : (cell) => setState(() {
                  _selected = cell;
                  _wrongDigit = null;
                }),
        ),
        const SizedBox(height: 8),
        if (ended) ...[
          FilledButton.icon(
            onPressed: () => _start(_rival),
            icon: const Icon(Icons.replay),
            label: const Text('もう一局'),
          ),
          TextButton(
            onPressed: () => setState(() => _game = null),
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
                    style: FilledButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: selected == null || thinking
                        ? null
                        : () => _enter(digit),
                    child: Text('$digit', style: const TextStyle(fontSize: 22)),
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
      child: Column(
        children: [
          for (var band = 0; band < game.size.boxSide; band++)
            Row(
              children: [
                for (var stack = 0; stack < game.size.boxSide; stack++)
                  Expanded(child: _room(band, stack)),
              ],
            ),
        ],
      ),
    ),
  );

  Widget _room(int band, int stack) {
    final box = game.size.boxSide;
    final side = game.size.side;
    final room = band * box + stack + 1;
    final owner = game.flagAt(room);
    final active =
        !game.isOver &&
        owner == null &&
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
            color: highlighted ? color : _parchment,
            alignment: Alignment.center,
            child: Semantics(
              label:
                  '$room番の部屋${owner == null ? '' : '、${playerName(owner)}の旗'}',
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
                      '${_roomMarks[room]}${owner == null ? '' : ' ${playerName(owner)}'}',
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
          for (var y = 0; y < box; y++)
            Row(
              children: [
                for (var x = 0; x < box; x++)
                  Expanded(
                    child: _cell(
                      (band * box + y) * side + stack * box + x,
                      active,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _cell(int cell, bool activeRoom) {
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
            : Colors.white,
        child: InkWell(
          onTap: tap,
          child: Container(
            height: side == 4 ? 50 : 36,
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
