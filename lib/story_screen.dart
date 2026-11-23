import 'package:flutter/material.dart';

import 'progress.dart';
import 'story_data.dart';
import 'story_remote_config.dart' show storyImagePath;
import 'town_areas.dart';

const _paper = Color(0xFFFFF9ED);
const _ink = Color(0xFF63351F);
const _rule = Color(0xFF8B694D);

class StoryScreen extends StatelessWidget {
  const StoryScreen({
    super.key,
    required this.controller,
    required this.catalog,
    required this.onSelfCare,
    required this.onVisitDestination,
  });

  final ProgressController controller;
  final StoryCatalog catalog;
  final VoidCallback onSelfCare;
  final ValueChanged<TownArea> onVisitDestination;

  void _openEpisode(BuildContext context, int index) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _EpisodeScreen(
          controller: controller,
          catalog: catalog,
          index: index,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      if (controller.failure != null) return const _StorySaveError();
      final progress = controller.progress!;
      final story = progress.story;
      final episodes = catalog.episodes;
      final nextIndex = story.resumeIndex;
      final next = nextIndex < episodes.length ? episodes[nextIndex] : null;
      final playable =
          next != null &&
          (story.unreadClue || next.isAvailable(progress.points));
      final cleared = story.completed > 0 ? story.completed - 1 : 0;
      final lastDestination = episodes
          .take(story.unreadClue ? story.completed - 1 : story.completed)
          .map((episode) => episode.destination)
          .nonNulls
          .lastOrNull;
      return _StoryPage(
        title: 'ストーリー',
        children: [
          if (!story.hasStarted)
            _SceneArt(storyPlazaArt, _imageUri(catalog, catalog.coverImage)),
          Text(catalog.title, style: Theme.of(context).textTheme.headlineSmall),
          Text('暗号 $cleared / ${episodes.length - 1}'),
          LinearProgressIndicator(value: cleared / (episodes.length - 1)),
          if (next != null)
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(story.unreadClue ? 'クリアしたお話' : '次のお話'),
                    const SizedBox(height: 4),
                    Text(
                      next.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      story.unreadClue
                          ? '数独を解きました。手がかりを確かめよう。'
                          : nextIndex == 0
                          ? '中央ひろばで、4×4の数独をれんしゅうします。'
                          : '${next.area.label}で${next.size}×${next.size}の暗号に挑戦。'
                                '${next.destination == null ? '紙にかくれたことば' : '次の行き先'}がわかります。',
                    ),
                    const SizedBox(height: 12),
                    if (playable)
                      FilledButton.icon(
                        key: const ValueKey('story-open-episode'),
                        onPressed: () => _openEpisode(context, nextIndex),
                        icon: Icon(
                          story.unreadClue
                              ? Icons.auto_awesome
                              : Icons.menu_book_outlined,
                        ),
                        label: Text(
                          story.unreadClue
                              ? '手がかりを見る'
                              : story.dialogueTurns > 0
                              ? 'つづきから'
                              : 'お話をはじめる',
                        ),
                      )
                    else ...[
                      Text(
                        'あと${(next.pointsNeeded(progress.points) + 9) ~/ 10}回、'
                        'セルフケアを記録すると開きます。',
                      ),
                      OutlinedButton(
                        onPressed: onSelfCare,
                        child: const Text('セルフケアへ'),
                      ),
                    ],
                  ],
                ),
              ),
            )
          else
            const Text('今回の暗号はすべて解けました。手がかり帳で旅を振り返れます。'),
          if (lastDestination != null &&
              lastDestination.isUnlocked(progress.points))
            OutlinedButton.icon(
              onPressed: () => onVisitDestination(lastDestination),
              icon: const Icon(Icons.place_outlined),
              label: Text('${lastDestination.label}へ行く'),
            ),
          if (story.completed > 0) ...[
            Text('手がかり帳', style: Theme.of(context).textTheme.titleLarge),
            for (var index = story.completed - 1; index >= 0; index--)
              if (!(story.unreadClue && index == story.completed - 1))
                Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    leading: const Icon(Icons.check_circle_outline),
                    title: Text(episodes[index].title),
                    subtitle: Text(episodes[index].clue),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openEpisode(context, index),
                  ),
                ),
          ],
        ],
      );
    },
  );
}

class _EpisodeScreen extends StatefulWidget {
  const _EpisodeScreen({
    required this.controller,
    required this.catalog,
    required this.index,
  });

  final ProgressController controller;
  final StoryCatalog catalog;
  final int index;

  @override
  State<_EpisodeScreen> createState() => _EpisodeScreenState();
}

class _EpisodeScreenState extends State<_EpisodeScreen> {
  int? _selected;
  int _replayResultTurn = 0;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      if (controller.failure != null) return const _StorySaveError();
      final story = controller.progress!.story;
      final index = widget.index;
      final catalog = widget.catalog;
      final episodes = catalog.episodes;
      final episode = episodes[index];
      final busy = controller.busy;

      if (index < story.completed) {
        final reveal = story.unreadClue && index == story.completed - 1;
        // Unread scenes resume from saved progress; older chapters can be
        // replayed from the beginning without mutating the save.
        final turnIndex = reveal
            ? story.resultDialogueTurns
            : _replayResultTurn;
        final resultTurns = episode.resultDialogue;
        final hasMoreDialogue = turnIndex < resultTurns.length;
        final reduceMotion = MediaQuery.disableAnimationsOf(context);
        return _StoryPage(
          contentKey: const ValueKey('story-clue'),
          title: index == 0 ? 'れんしゅう' : '見つけた手がかり',
          children: [
            _SceneArt(episode.resultArt, _imageUri(catalog, episode.clueImage)),
            if (hasMoreDialogue) ...[
              _StoryDialogueCard(
                key: const ValueKey('story-result-dialogue'),
                speaker: resultTurns[turnIndex].$1,
                line: resultTurns[turnIndex].$2,
              ),
              Text(
                '${turnIndex + 1} / ${resultTurns.length}',
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.labelSmall,
              ),
              FilledButton(
                key: const ValueKey('story-advance-result-dialogue'),
                onPressed: busy
                    ? null
                    : () {
                        if (reveal) {
                          controller.updateStory(
                            (story, _) => story.advanceResultDialogue(
                              index,
                              episodes: episodes,
                            ),
                          );
                        } else {
                          setState(() => _replayResultTurn++);
                        }
                      },
                child: Text(
                  turnIndex == resultTurns.length - 1
                      ? '手がかりを見る'
                      : 'つぎへ',
                ),
              ),
            ] else ...[
              Semantics(
                liveRegion: reveal,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(
                    begin: reveal && !reduceMotion ? 0 : 1,
                    end: 1,
                  ),
                  duration: const Duration(milliseconds: 450),
                  builder: (context, opacity, child) =>
                      Opacity(opacity: opacity, child: child),
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            episode.clue,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 10),
                          Text(episode.result, textAlign: TextAlign.center),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              FilledButton(
                key: const ValueKey('story-finish-clue'),
                onPressed: busy
                    ? null
                    : () async {
                        if (reveal &&
                            !await controller.updateStory(
                              (story, _) => story.readClue(
                                index,
                                episodes: episodes,
                              ),
                            )) {
                          return;
                        }
                        if (context.mounted) Navigator.of(context).pop();
                      },
                child: const Text('お話の一覧へ'),
              ),
            ],
          ],
        );
      }
      if (story.dialogueTurns < episode.dialogue.length) {
        final (speaker, line) = episode.dialogue[story.dialogueTurns];
        final last = story.dialogueTurns == episode.dialogue.length - 1;
        return _StoryPage(
          contentKey: const ValueKey('story-dialogue'),
          title: episode.title,
          children: [
            _SceneArt(episode.art, _imageUri(catalog, episode.image)),
            _StoryDialogueCard(speaker: speaker, line: line),
            FilledButton(
              key: const ValueKey('story-advance-dialogue'),
              onPressed: busy
                  ? null
                  : () => controller.updateStory(
                      (story, points) => story.advanceDialogue(
                        index,
                        points,
                        episodes: episodes,
                      ),
                    ),
              child: Text(last ? '数独をはじめる' : 'つぎへ'),
            ),
          ],
        );
      }

      final board = story.board ?? episode.initialBoard();
      final selected = _selected;
      final conflicts = {
        for (var i = 0; i < board.length; i++)
          if (episode.hasConflict(board, i)) i,
      };
      void enter(int number) {
        if (selected != null) {
          controller.updateStory(
            (story, points) => story.enterNumber(
              index,
              points,
              selected,
              number,
              episodes: episodes,
            ),
          );
        }
      }

      return _StoryPage(
        contentKey: const ValueKey('story-puzzle'),
        title: episode.title,
        children: [
          Text(
            '${episode.size}×${episode.size} 数独',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text(
            '空いているマスを選び、数字を入れます。たて・よこ・太い線の四角で、'
            '1から${episode.size}までの数字をひとつずつ使います。',
          ),
          _PuzzleBoard(
            episode: episode,
            board: board,
            selected: selected,
            conflicts: conflicts,
            onSelect: busy ? null : (cell) => setState(() => _selected = cell),
          ),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 4,
            runSpacing: 4,
            children: [
              for (var number = 1; number <= episode.size; number++)
                FilledButton.tonal(
                  key: ValueKey('story-number-$number'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(44, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: busy || selected == null
                      ? null
                      : () => enter(number),
                  child: Text('$number'),
                ),
            ],
          ),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: busy || selected == null || board[selected] == 0
                    ? null
                    : () => enter(0),
                icon: const Icon(Icons.backspace_outlined),
                label: const Text('消す'),
              ),
              TextButton.icon(
                key: const ValueKey('story-hint'),
                onPressed: busy
                    ? null
                    : () => controller.updateStory(
                        (story, points) => story.useHint(
                          index,
                          points,
                          selected,
                          episodes: episodes,
                        ),
                      ),
                icon: const Icon(Icons.lightbulb_outline),
                label: const Text('ヒントで1マスうめる'),
              ),
            ],
          ),
          if (conflicts.isNotEmpty)
            Semantics(
              liveRegion: true,
              child: const Text('同じ数字が重なっているマスがあります。'),
            ),
        ],
      );
    },
  );
}

/// The same single-turn picture-book dialogue card is used before and
/// after a puzzle. It never appends previous lines to the screen.
class _StoryDialogueCard extends StatelessWidget {
  const _StoryDialogueCard({
    super.key,
    required this.speaker,
    required this.line,
  });

  final StorySpeaker speaker;
  final String line;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StoryPortrait(speaker),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  speaker.label,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    line,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _PuzzleBoard extends StatelessWidget {
  const _PuzzleBoard({
    required this.episode,
    required this.board,
    required this.selected,
    required this.conflicts,
    required this.onSelect,
  });

  final StoryEpisode episode;
  final List<int> board;
  final int? selected;
  final Set<int> conflicts;
  final ValueChanged<int>? onSelect;

  @override
  Widget build(BuildContext context) {
    final size = episode.size;
    return Align(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 384),
        child: AspectRatio(
          aspectRatio: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: _rule, width: 2),
            ),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: GridView.count(
                primary: false,
                padding: EdgeInsets.zero,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: size,
                children: [
                  for (var cell = 0; cell < board.length; cell++)
                    _cell(context, cell),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cell(BuildContext context, int cell) {
    final size = episode.size;
    final row = cell ~/ size;
    final column = cell % size;
    final fixed = episode.givenAt(cell) != 0;
    final value = board[cell];
    final active = cell == selected;
    final conflict = conflicts.contains(cell);
    final color = conflict
        ? const Color(0xFFFFDFD9)
        : active
        ? const Color(0xFFC8E8E0)
        : fixed
        ? const Color(0xFFF4E5C9)
        : Colors.white;
    final border = Border(
      right: column == size - 1
          ? BorderSide.none
          : BorderSide(
              color: _rule,
              width: (column + 1) % episode.boxWidth == 0 ? 2 : .6,
            ),
      bottom: row == size - 1
          ? BorderSide.none
          : BorderSide(color: _rule, width: (row + 1) % 2 == 0 ? 2 : .6),
    );
    final select = onSelect;
    final VoidCallback? onTap = fixed || select == null
        ? null
        : () => select(cell);
    return Semantics(
      key: ValueKey('story-cell-$cell'),
      button: !fixed,
      selected: active,
      label:
          '${row + 1}行 ${column + 1}列、${value == 0 ? '空き' : value}'
          '${fixed ? '、最初からある数字' : ''}${conflict ? '、重複' : ''}',
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: color,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(border: border),
            padding: const EdgeInsets.all(4),
            alignment: Alignment.center,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value == 0 ? '' : '$value',
                style: TextStyle(
                  fontSize: 25,
                  fontWeight: fixed ? FontWeight.w800 : FontWeight.w500,
                  color: conflict
                      ? const Color(0xFF9B2119)
                      : fixed
                      ? _ink
                      : Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Uri? _imageUri(StoryCatalog catalog, String? image) =>
    image == null ? null : catalog.baseUri!.resolve('$storyImagePath$image');

class _StoryPortrait extends StatelessWidget {
  const _StoryPortrait(this.speaker);
  final StorySpeaker speaker;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 80,
    height: 80,
    child: switch (speaker.portrait) {
      final uri? => _StoryImage(uri, fit: BoxFit.contain),
      null => Image.asset(
        speaker.localPortrait,
        fit: BoxFit.contain,
        excludeFromSemantics: true,
      ),
    },
  );
}

class _StoryImage extends StatelessWidget {
  const _StoryImage(this.uri, {required this.fit});
  final Uri uri;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) => Image.network(
    uri.toString(),
    fit: fit,
    excludeFromSemantics: true,
    errorBuilder: (context, error, stack) => const Center(
      child: Tooltip(
        message: 'ストーリー画像を読み込めませんでした',
        child: Icon(Icons.broken_image_outlined),
      ),
    ),
  );
}

class _SceneArt extends StatelessWidget {
  const _SceneArt(this.asset, this.uri);
  final String asset;
  final Uri? uri;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(16),
    child: AspectRatio(
      aspectRatio: 4 / 3,
      child: uri == null
          ? Image.asset(asset, fit: BoxFit.cover, excludeFromSemantics: true)
          : _StoryImage(uri!, fit: BoxFit.cover),
    ),
  );
}

class _StoryPage extends StatelessWidget {
  const _StoryPage({
    required this.title,
    required this.children,
    this.contentKey,
  });

  final String title;
  final List<Widget> children;
  final Key? contentKey;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _paper,
    appBar: AppBar(title: Text(title), backgroundColor: _paper),
    body: SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            key: contentKey,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
            children: [
              for (final (index, child) in children.indexed) ...[
                if (index != 0) const SizedBox(height: 12),
                child,
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class _StorySaveError extends StatelessWidget {
  const _StorySaveError();

  @override
  Widget build(BuildContext context) => const _StoryPage(
    title: 'ストーリー',
    children: [Text('記録を保存できませんでした。前の画面から診断情報を確認できます。')],
  );
}
