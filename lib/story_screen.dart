import 'package:flutter/material.dart';

import 'progress.dart';
import 'story_data.dart';
import 'story_remote_config.dart' show storyImagePath;
import 'sudoku_duel_view.dart';
import 'sudoku_ui.dart';
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
      final cleared = story.unreadClue ? story.completed - 1 : story.completed;
      final currentChapter = next == null
          ? null
          : catalog.chapters[catalog.chapterIndexForEpisode(nextIndex)];
      final lastDestination = episodes
          .take(story.unreadClue ? story.completed - 1 : story.completed)
          .map((episode) => episode.destination)
          .nonNulls
          .lastOrNull;
      return _StoryPage(
        title: 'ストーリー',
        children: [
          _StoryTitleBanner(title: catalog.title),
          _StoryProgressMeter(completed: cleared, total: episodes.length),
          if (currentChapter != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '第${catalog.chapterIndexForEpisode(nextIndex) + 1}章　${currentChapter.title}',
                key: const ValueKey('story-current-chapter'),
                style: const TextStyle(
                  fontSize: 19, fontWeight: FontWeight.w900, color: _ink,
                ),
              ),
            ),
          if (next != null)
            _StoryNextEpisodeCard(
              title: next.title,
              eyebrow: story.unreadClue ? 'クリアしたお話:' : '次のお話:',
              description: story.unreadClue
                  ? '数独を解きました。手がかりを確かめよう。'
                  : next.duel != null && story.board == null
                  ? 'おくりマス数独　${next.duel!.title}'
                  : nextIndex == 0
                  ? '朝の体操で見つけたふしぎな紙を、数独で調べます。'
                  : '${next.area.label}で${next.size}×${next.size}の暗号に挑戦。'
                    '${next.destination == null ? '紙にかくれたことば' : '次の行き先'}がわかります。',
              buttonLabel: story.unreadClue
                  ? '手がかりを見る'
                  : story.dialogueTurns > 0
                  ? 'つづきから'
                  : 'お話をはじめる',
              buttonIcon: story.unreadClue
                  ? Icons.auto_awesome : Icons.menu_book_outlined,
              playable: playable,
              remainingCare: (next.pointsNeeded(progress.points) + 9) ~/ 10,
              onOpen: () => _openEpisode(context, nextIndex),
              onSelfCare: onSelfCare,
            )
          else
            Text('全${episodes.length}話、クリアおめでとう！ 手がかり帳から何度でも読み返せます。'),
          if (lastDestination != null &&
              lastDestination.isUnlocked(progress.points))
            OutlinedButton.icon(
              onPressed: () => onVisitDestination(lastDestination),
              icon: const Icon(Icons.place_outlined),
              label: Text('${lastDestination.label}へ行く'),
            ),
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'お話一覧・手がかり帳',
              style: TextStyle(
                fontSize: 24, fontWeight: FontWeight.w900, color: _ink,
              ),
            ),
          ),
          for (var chapterIndex = 0;
              chapterIndex < catalog.chapters.length;
              chapterIndex++) ...[
            _StoryChapterHeader(
              chapterNumber: chapterIndex + 1,
              title: catalog.chapters[chapterIndex].title,
              total: (chapterIndex + 1 < catalog.chapters.length
                      ? catalog.chapters[chapterIndex + 1].startIndex
                      : episodes.length) -
                  catalog.chapters[chapterIndex].startIndex,
              completed: List.generate(
                (chapterIndex + 1 < catalog.chapters.length
                        ? catalog.chapters[chapterIndex + 1].startIndex
                        : episodes.length) -
                    catalog.chapters[chapterIndex].startIndex,
                (i) => catalog.chapters[chapterIndex].startIndex + i,
              ).where((i) => i < cleared).length,
            ),
            for (var index = catalog.chapters[chapterIndex].startIndex;
                index <
                    (chapterIndex + 1 < catalog.chapters.length
                        ? catalog.chapters[chapterIndex + 1].startIndex
                        : episodes.length);
                index++)
              if (index < cleared)
                _StoryClueRow(
                  title: episodes[index].title,
                  clue: episodes[index].clue,
                  onTap: () => _openEpisode(context, index),
                )
              else
                _StoryChapterEpisodeRow(
                  title: episodes[index].title,
                  chapterEpisodeNumber:
                      index - catalog.chapters[chapterIndex].startIndex + 1,
                  status: index == nextIndex
                      ? story.unreadClue
                          ? 'クリア！ お話の続きを読もう'
                          : playable
                          ? 'このお話から始めよう'
                          : 'あと${(episodes[index].pointsNeeded(progress.points) + 9) ~/ 10}回で開放'
                      : 'これからのお話',
                  onTap: index == nextIndex && playable
                      ? () => _openEpisode(context, index)
                      : null,
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
      final match = episode.duel;

      final readyForPuzzle = index == story.completed &&
          story.dialogueTurns == episode.dialogue.length;
      if (match != null && readyForPuzzle) {
        return _StoryPage(
          contentKey: const ValueKey('story-duel'),
          title: episode.title,
          showStoryListButton: true,
          navigationBusy: busy,
          children: [
            SudokuDuelView.story(
              match: match,
              position: story.duelPosition(episode),
              busy: busy,
              onMove: (cell, digit) => controller.updateStory(
                (saved, points) => saved.playDuelMove(
                  index, points, cell, digit, episodes: episodes,
                ),
              ),
              onFinish: () => controller.updateStory(
                (saved, points) =>
                    saved.finishDuel(index, points, episodes: episodes),
              ),
            ),
          ],
        );
      }

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
          title: '見つけた手がかり',
          showStoryListButton: hasMoreDialogue,
          navigationBusy: busy,
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
          showStoryListButton: true,
          navigationBusy: busy,
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
              child: Text(!last ? 'つぎへ' : match == null
                  ? '数独をはじめる' : '${match.opponent.label}と対戦する'),
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
        showStoryListButton: true,
        navigationBusy: busy,
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


/// Illustrated story index elements; actions remain Flutter controls.
class _StoryTitleBanner extends StatelessWidget {
  const _StoryTitleBanner({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 88,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Positioned.fill(child: Image.asset(
          'assets/story/kotohogu_story_ui/story_title_ornament.png',
          fit: BoxFit.fill, excludeFromSemantics: true,
        )),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: _ink,
                shadows: [
                  Shadow(color: Color(0xFFFFE9BD), offset: Offset(-2, -2)),
                  Shadow(color: Color(0xFFFFE9BD), offset: Offset(2, -2)),
                  Shadow(color: Color(0xFFFFE9BD), offset: Offset(-2, 2)),
                  Shadow(color: Color(0xFFFFE9BD), offset: Offset(2, 2)),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _StoryProgressMeter extends StatelessWidget {
  const _StoryProgressMeter({required this.completed, required this.total});
  final int completed;
  final int total;

  @override
  Widget build(BuildContext context) {
    final fraction = total == 0
        ? 0.0 : (completed / total).clamp(0.0, 1.0).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('暗号 $completed / $total', style: const TextStyle(
          fontSize: 18, fontWeight: FontWeight.w900, color: _ink,
        )),
        const SizedBox(height: 6),
        SizedBox(
          height: 30,
          child: LayoutBuilder(
            builder: (context, constraints) => Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 0, right: 0, top: 8,
                  child: Container(
                    height: 14, clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: const Color(0xFF855842),
                      border: Border.all(
                        color: const Color(0xFF3C1E17), width: 2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: fraction,
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [
                            Color(0xFFF07FA7), Color(0xFFF9B56D),
                            Color(0xFFF5DC71), Color(0xFF96CB7E),
                            Color(0xFF83D2D9),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: (constraints.maxWidth - 28) * fraction, top: 0,
                  child: Image.asset('assets/story/kotohogu_story_ui/story_progress_leaf.png',
                    width: 28, height: 30, excludeFromSemantics: true),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StoryChapterHeader extends StatelessWidget {
  const _StoryChapterHeader({
    required this.chapterNumber,
    required this.title,
    required this.completed,
    required this.total,
  });
  final int chapterNumber;
  final String title;
  final int completed;
  final int total;

  @override
  Widget build(BuildContext context) => Container(
    key: ValueKey('story-chapter-$chapterNumber'),
    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
    decoration: BoxDecoration(
      color: const Color(0xFFF6E8CB),
      border: Border.all(color: _rule),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            '第$chapterNumber章　$title',
            style: const TextStyle(
              fontSize: 19, fontWeight: FontWeight.w900, color: _ink,
            ),
          ),
        ),
        Text('$completed / $total 話',
          style: const TextStyle(fontWeight: FontWeight.w700, color: _ink)),
      ],
    ),
  );
}

class _StoryChapterEpisodeRow extends StatelessWidget {
  const _StoryChapterEpisodeRow({
    required this.title,
    required this.chapterEpisodeNumber,
    required this.status,
    required this.onTap,
  });
  final String title;
  final int chapterEpisodeNumber;
  final String status;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
    color: const Color(0xFFFFF9EF),
    child: ListTile(
      leading: Icon(
        onTap == null ? Icons.lock_outline : Icons.menu_book_outlined,
        color: _ink,
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text('第$chapterEpisodeNumber話　$status'),
      onTap: onTap,
      enabled: onTap != null,
    ),
  );
}

class _StoryNextEpisodeCard extends StatelessWidget {
  const _StoryNextEpisodeCard({
    required this.title, required this.eyebrow, required this.description,
    required this.buttonLabel, required this.buttonIcon,
    required this.playable, required this.remainingCare,
    required this.onOpen, required this.onSelfCare,
  });
  final String title;
  final String eyebrow;
  final String description;
  final String buttonLabel;
  final IconData buttonIcon;
  final bool playable;
  final int remainingCare;
  final VoidCallback onOpen;
  final VoidCallback onSelfCare;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(28, 24, 28, 27),
    decoration: const BoxDecoration(
      image: DecorationImage(
        image: AssetImage('assets/story/kotohogu_story_ui/story_episode_card.png'),
        fit: BoxFit.fill,
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(eyebrow, style: const TextStyle(
                    color: _ink, fontWeight: FontWeight.w800, fontSize: 14,
                  )),
                  const SizedBox(height: 3),
                  Text(title, style: const TextStyle(
                    color: _ink, fontWeight: FontWeight.w900,
                    fontSize: 21, height: 1.2,
                  )),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Image.asset('assets/story/kotohogu_story_ui/story_tree.png',
              width: 70, height: 54, fit: BoxFit.contain,
              excludeFromSemantics: true),
          ],
        ),
        const Divider(
          color: Color(0xFFB88E68), height: 18, thickness: 1.2),
        Text(description, style: const TextStyle(
          color: _ink, fontSize: 14, height: 1.4,
          fontWeight: FontWeight.w600,
        )),
        const SizedBox(height: 12),
        if (playable)
          SizedBox(
            height: 57,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset('assets/story/kotohogu_story_ui/story_button_green.png',
                  fit: BoxFit.fill, excludeFromSemantics: true),
                TextButton.icon(
                  key: const ValueKey('story-open-episode'),
                  onPressed: onOpen,
                  icon: Icon(buttonIcon, size: 23),
                  label: Text(buttonLabel),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w900,
                      shadows: [
                        Shadow(
                          color: Color(0xFF20452B), blurRadius: 3,
                          offset: Offset(1, 2),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          )
        else ...[
          Text('あと$remainingCare回、セルフケアを記録すると開きます。',
            style: const TextStyle(color: _ink)),
          const SizedBox(height: 6),
          OutlinedButton(
            onPressed: onSelfCare, child: const Text('セルフケアへ')),
        ],
      ],
    ),
  );
}

class _StoryClueRow extends StatelessWidget {
  const _StoryClueRow({
    required this.title, required this.clue, required this.onTap,
  });
  final String title;
  final String clue;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 66),
    decoration: const BoxDecoration(
      image: DecorationImage(
        image: AssetImage('assets/story/kotohogu_story_ui/story_clue_row.png'),
        fit: BoxFit.fill,
      ),
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(13, 10, 13, 10),
          child: Row(
            children: [
              Image.asset('assets/story/kotohogu_story_ui/story_check_stamp.png',
                width: 43, height: 43, excludeFromSemantics: true),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _ink, fontWeight: FontWeight.w900,
                        fontSize: 16, height: 1.15,
                      )),
                    const SizedBox(height: 2),
                    Text(clue, maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _ink, fontWeight: FontWeight.w700,
                        fontSize: 12,
                      )),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, color: _ink, size: 27),
            ],
          ),
        ),
      ),
    ),
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
    this.showStoryListButton = false,
    this.navigationBusy = false,
  });
  final String title;
  final List<Widget> children;
  final Key? contentKey;
  final bool showStoryListButton;
  final bool navigationBusy;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _paper,
    appBar: contentKey == const ValueKey('story-duel')
        ? sudokuAppBar(context, title)
        : AppBar(
      toolbarHeight: 70,
      titleSpacing: 0,
      leadingWidth: 68,
      elevation: 0,
      backgroundColor: const Color(0xFF87482D),
      flexibleSpace: const DecoratedBox(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/story/kotohogu_story_ui/story_header_wood.png'),
            fit: BoxFit.fill,
          ),
        ),
      ),
      leading: IconButton(
        tooltip: 'もどる',
        onPressed: () => Navigator.of(context).maybePop(),
        icon: Image.asset('assets/story/kotohogu_story_ui/story_back_arrow.png',
          width: 52, height: 44, excludeFromSemantics: true),
      ),
      title: Text(title, style: const TextStyle(
        color: Colors.white,
        fontSize: 24,
        fontWeight: FontWeight.w900,
        shadows: [
          Shadow(
            offset: Offset(2, 3), blurRadius: 2,
            color: Color(0xFF3A1A0F),
          ),
        ],
      )),
    ),
    body: DecoratedBox(
      decoration: contentKey == const ValueKey('story-duel')
          ? sudokuBackground
          : const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/story/kotohogu_story_ui/story_paper_tile.png'),
                fit: BoxFit.none,
                repeat: ImageRepeat.repeat,
              ),
            ),
      child: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              key: contentKey,
              padding: contentKey == const ValueKey('story-duel')
                  ? const EdgeInsets.fromLTRB(4, 8, 4, 24)
                  : const EdgeInsets.fromLTRB(16, 10, 16, 24),
              children: [
                for (final (index, child) in children.indexed) ...[
                  if (index != 0) const SizedBox(height: 12),
                  child,
                ],
                if (showStoryListButton) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const ValueKey('story-view-list'),
                    onPressed: navigationBusy
                        ? null
                        : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.menu_book_outlined),
                    label: const Text('お話一覧へ'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF006C61),
                      backgroundColor: _paper,
                      side: const BorderSide(
                        color: Color(0xFF006C61),
                        width: 1.5,
                      ),
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ],
              ],
            ),
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
