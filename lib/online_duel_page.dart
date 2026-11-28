import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'online_duel_api.dart';

/// Private mobile trial. One saved match per installation.
class OnlineDuelPage extends StatefulWidget {
  const OnlineDuelPage({super.key, this.api});
  final OnlineDuelApi? api;

  @override
  State<OnlineDuelPage> createState() => _OnlineDuelPageState();
}

class _OnlineDuelPageState extends State<OnlineDuelPage> with WidgetsBindingObserver {
  static const _saveKey = 'kotohoguru.online.session.v1';
  final _prefs = SharedPreferencesAsync();
  final _input = TextEditingController();
  late final OnlineDuelApi _api = widget.api ?? OnlineDuelApi();
  OnlineDuelState? _state;
  String? _code, _token, _error;
  bool _busy = false, _loaded = false, _active = true;
  int? _selected;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (kIsWeb) {
      _loaded = true;
    } else {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    try {
      final raw = await _prefs.getString(_saveKey);
      if (!mounted) return;
      if (raw != null) {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        final code = data['code'] as String;
        final token = data['token'] as String;
        if (!duelCodePattern.hasMatch(code) || !duelTokenPattern.hasMatch(token)) {
          throw const FormatException('保存された対戦情報が不正です');
        }
        _code = code;
        _token = token;
      }
    } catch (error, stack) {
      _report(error, stack);
    } finally {
      if (mounted) setState(() => _loaded = true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (!_active) {
      _poll?.cancel();
    } else if (_state != null && _error == null && !_busy) {
      unawaited(_refresh());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _input.dispose();
    super.dispose();
  }

  void _report(Object error, StackTrace stack) {
    // Do not print request headers, raw JSON, or session credentials.
    final diagnostic = error is FormatException ? error.message : error.toString();
    debugPrint('Online duel: $diagnostic\n$stack');
    if (mounted) setState(() => _error = diagnostic);
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy || !mounted) return;
    _poll?.cancel();
    setState(() { _busy = true; _error = null; });
    try {
      await action();
    } catch (error, stack) {
      _report(error, stack);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _schedule();
      }
    }
  }

  void _schedule() {
    _poll?.cancel();
    final state = _state;
    if (!_active || _error != null || _busy || state == null ||
        state.status == 'finished' || state.myTurn ||
        (state.status == 'choosing_bonus' && state.yourSide == 'second')) return;
    _poll = Timer(const Duration(seconds: 3), () => unawaited(_refresh()));
  }

  void _accept(OnlineDuelState state) {
    if (!mounted) return;
    if (_state != null && (_state!.code != state.code ||
        _state!.yourSide != state.yourSide || _state!.revision > state.revision)) {
      throw const FormatException('対戦状態の不整合');
    }
    setState(() {
      _state = state;
      if (_selected != null && !state.canPlay(_selected!)) _selected = null;
    });
  }

  Future<void> _save(String code, String token) async {
    _code = code;
    _token = token;
    await _prefs.setString(_saveKey, jsonEncode({'code': code, 'token': token}));
  }

  Future<void> _enter({required bool create}) => _run(() async {
    final code = _input.text.trim().toUpperCase();
    if (!create && !duelCodePattern.hasMatch(code)) {
      throw const FormatException('待ち合わせ番号は8文字の英数字です');
    }
    final token = newDuelToken();
    // Store join credentials before the request for explicit recovery.
    if (!create) await _save(code, token);
    final state = create ? await _api.create(token) : await _api.join(code, token);
    await _save(state.code, token);
    _accept(state);
  });

  Future<void> _refresh() => _run(() async {
    _accept(await _api.get(_code!, _token!));
  });

  Future<void> _rejoin() => _run(() async {
    _accept(await _api.join(_code!, _token!));
  });

  Future<void> _forget() => _run(() async {
    await _prefs.remove(_saveKey);
    if (mounted) setState(() {
      _code = _token = null;
      _state = null;
      _selected = null;
      _input.clear();
    });
  });

  Future<bool?> _confirm(String title, String detail, String action) =>
      showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(detail),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('戻る')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(action)),
          ],
        ),
      );

  Future<void> _confirmForget() async {
    final yes = await _confirm('保存した対戦情報を消しますか？',
        'この端末から同じ部屋に戻れなくなります。相手側の部屋は消えません。', '消す');
    if (yes == true && mounted) await _forget();
  }

  Future<void> _resign() async {
    final yes = await _confirm('降参しますか？', '相手の勝ちになります。', '降参する');
    if (yes == true && mounted) {
      await _run(() async => _accept(await _api.resign(_state!, _token!)));
    }
  }

  Widget _lobby() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('ともだちと4×4の旗取り対戦をしよう！'),
      const SizedBox(height: 16),
      if (_code != null) ...[
        Text('保存した部屋：$_code'),
        FilledButton(onPressed: _busy ? null : _refresh, child: const Text('対戦のつづき')),
        OutlinedButton(onPressed: _busy ? null : _rejoin, child: const Text('同じ番号で入室を確認')),
        TextButton(onPressed: _busy ? null : _confirmForget, child: const Text('保存した対戦情報を消す')),
      ] else ...[
        FilledButton.icon(
          key: const ValueKey('online-duel-create'),
          onPressed: _busy || _error != null ? null : () => _enter(create: true),
          icon: const Icon(Icons.add),
          label: const Text('部屋をつくる'),
        ),
        const SizedBox(height: 20),
        TextField(
          key: const ValueKey('online-duel-code'),
          controller: _input,
          enabled: !_busy,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          maxLength: 8,
          decoration: const InputDecoration(labelText: '待ち合わせ番号', border: OutlineInputBorder()),
        ),
        FilledButton.tonal(
          key: const ValueKey('online-duel-join'),
          onPressed: _busy || _error != null ? null : () => _enter(create: false),
          child: const Text('番号で参加する'),
        ),
      ],
    ],
  );

  Widget _board(OnlineDuelState state) => AspectRatio(
    aspectRatio: 1,
    child: GridView.count(
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 4,
      children: [
        for (var cell = 0; cell < 16; cell++) _cell(state, cell),
      ],
    ),
  );

  Widget _cell(OnlineDuelState state, int cell) {
    final room = OnlineDuelState.roomOf(cell);
    final captured = state.flags[room - 1];
    final selected = _selected == cell;
    final available = state.canPlay(cell);
    final color = selected ? Colors.amber.shade300
        : captured == 'first' ? Colors.blue.shade100
        : captured == 'second' ? Colors.pink.shade100
        : available ? Colors.green.shade100 : Colors.grey.shade100;
    return Semantics(
      label: '第$room部屋、${cell ~/ 4 + 1}行${cell % 4 + 1}列、${state.board[cell] == '0' ? '空欄' : state.board[cell]}',
      button: available,
      child: InkWell(
        key: ValueKey('online-duel-cell-$cell'),
        onTap: available && !_busy && _error == null ? () => setState(() => _selected = cell) : null,
        child: Container(
          decoration: BoxDecoration(
            color: color,
            border: Border(
              top: BorderSide(width: cell ~/ 4 % 2 == 0 ? 2 : .5),
              left: BorderSide(width: cell % 2 == 0 ? 2 : .5),
              right: BorderSide(width: cell % 4 == 3 ? 2 : .5),
              bottom: BorderSide(width: cell ~/ 4 == 3 ? 2 : .5),
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Text(state.board[cell] == '0' ? '' : state.board[cell],
                  style: TextStyle(fontSize: 30, color: Colors.black87,
                    fontWeight: state.givens[cell] == '0' ? FontWeight.normal : FontWeight.bold)),
              if (cell ~/ 4 % 2 == 0 && cell % 2 == 0)
                Positioned(top: 2, left: 4, child: Text('$room${state.bonusRoom == room ? '🍓' : ''}',
                    style: const TextStyle(fontSize: 11, color: Colors.black87))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _room(OnlineDuelState state) {
    final enabled = !_busy && _error == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SelectableText('待ち合わせ番号：${state.code}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        OutlinedButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: state.code));
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('番号をコピーしました')));
          },
          icon: const Icon(Icons.copy), label: const Text('番号をコピー'),
        ),
        Text('あなたは${state.yourSide == 'first' ? '先手' : '後手'}　${state.playerCount}/2人'),
        const SizedBox(height: 12),
        if (state.status == 'waiting')
          const Text('相手に番号を伝えてね。入室を待っています。')
        else ...[
          Text('先手 ${state.scores['first']}点　対　後手 ${state.scores['second']}点',
              style: const TextStyle(fontSize: 20)),
          Text(switch (state.status) {
            'choosing_bonus' => state.yourSide == 'second'
                ? '2点のいちごの旗を置く部屋を選んでね。'
                : '後手がいちごの旗を選んでいます。',
            'playing' => state.myTurn
                ? 'あなたの番：${state.targetRoom == null ? '好きな部屋' : '第${state.targetRoom}部屋'}'
                : '相手の番です。',
            'finished' => '${state.winner == state.yourSide ? 'あなたの勝ち！' : '相手の勝ち'}${state.finishReason == 'resigned' ? '（降参）' : ''}',
            _ => throw StateError('Unexpected room status'),
          }, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 8),
          _board(state),
          const SizedBox(height: 12),
          if (state.status == 'choosing_bonus' && state.yourSide == 'second')
            Wrap(spacing: 8, children: [
              for (var room = 1; room <= 4; room++)
                FilledButton.tonal(
                  key: ValueKey('online-duel-bonus-$room'),
                  onPressed: enabled ? () => _run(() async =>
                      _accept(await _api.bonus(state, _token!, room))) : null,
                  child: Text('第$room部屋'),
                ),
            ]),
          if (state.status == 'playing')
            Row(children: [
              for (var digit = 1; digit <= 4; digit++)
                Expanded(child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: FilledButton(
                    key: ValueKey('online-duel-digit-$digit'),
                    onPressed: enabled && _selected != null && state.canPlay(_selected!)
                        ? () => _run(() async => _accept(await _api.move(state, _token!, _selected!, digit))) : null,
                    child: Text('$digit', style: const TextStyle(fontSize: 22)),
                  ),
                )),
            ]),
          if (state.status == 'playing' || state.status == 'choosing_bonus')
            TextButton(onPressed: enabled ? _resign : null, child: const Text('降参')),
          if (state.status == 'finished')
            FilledButton(onPressed: _busy ? null : _forget, child: const Text('新しい対戦へ')),
        ],
        OutlinedButton(onPressed: _busy ? null : _refresh, child: const Text('盤面を更新')),
        TextButton(onPressed: _busy ? null : _confirmForget, child: const Text('保存した対戦情報を消す')),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_state?.status == 'playing' || _state?.status == 'finished' ? '対戦室' : '待ち合わせ広場')),
    body: SafeArea(
      child: kIsWeb ? const Center(child: Text('オンライン対戦は現在スマホ版で試験中です。'))
      : !_loaded ? const Center(child: CircularProgressIndicator())
      : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) ...[
            Text(_error!.contains('wrong_digit') ? '数字が違うよ。盤面を更新してもう一度考えよう。' : '通信・処理エラー：$_error',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
            if (_code == null)
              TextButton(onPressed: _busy ? null : () => setState(() => _error = null), child: const Text('エラーを閉じる')),
          ],
          if (_state == null) _lobby() else _room(_state!),
          const SizedBox(height: 16),
          const Text('試験版・4×4のみ。部屋は作成から24時間有効です。画面を閉じても保存した部屋から再開できます。'),
        ],
      ),
    ),
  );
}
