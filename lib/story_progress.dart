import 'story_data.dart';
import 'sudoku_duel.dart';

/// The completed episodes form a prefix. Only the next episode needs a board
/// and a dialogue position. Availability is derived from lifetime points.
class StoryProgress {
  const StoryProgress.empty() : this._();

  const StoryProgress._({
    this.completed = 0,
    this.dialogueTurns = 0,
    this.board,
    this.duelMoves,
    this.unreadClue = false,
    this.resultDialogueTurns = 0,
    this.signature,
  });

  final int completed;
  final int dialogueTurns;
  final List<int>? board;
  /// Ordered cells reconstruct both players' turns, flags and next room.
  final List<int>? duelMoves;
  final bool unreadClue;
  /// Read position in the post-sudoku scene, saved for resume.
  final int resultDialogueTurns;
  final String? signature;

  /// Appending chapters preserves the position within the published prefix.
  StoryProgress forCatalog(StoryCatalog catalog) {
    final next = catalog.progressSignature;
    if (signature == next) return this;
    if (signature != null && hasStarted) {
      final minimumLength = completed + (dialogueTurns > 0 ? 1 : 0);
      for (var end = catalog.episodes.length - 1; end >= minimumLength; end--) {
        final prefix = catalog.episodes.sublist(0, end);
        if (storyProgressSignature(prefix) == signature) {
          return StoryProgress._(
            completed: completed,
            dialogueTurns: dialogueTurns,
            board: board,
            duelMoves: duelMoves,
            unreadClue: unreadClue,
            resultDialogueTurns: resultDialogueTurns,
            signature: next,
          );
        }
      }
    }
    return StoryProgress._(signature: next);
  }

  int get resumeIndex => unreadClue ? completed - 1 : completed;
  bool get hasStarted => completed != 0 || dialogueTurns != 0;

  bool _canPlay(int index, int points, List<StoryEpisode> episodes) =>
      !unreadClue &&
      index == completed &&
      index < episodes.length &&
      episodes[index].isAvailable(points);

  StoryProgress advanceDialogue(
    int index,
    int points, {
    List<StoryEpisode> episodes = storyEpisodes,
  }) {
    if (!_canPlay(index, points, episodes) ||
        dialogueTurns >= episodes[index].dialogue.length) {
      return this;
    }
    return StoryProgress._(
      completed: completed,
      signature: signature,
      dialogueTurns: dialogueTurns + 1,
    );
  }

  StoryProgress enterNumber(
    int index,
    int points,
    int cell,
    int number, {
    List<StoryEpisode> episodes = storyEpisodes,
  }) {
    if (!_canPlay(index, points, episodes)) return this;
    final episode = episodes[index];
    if (episode.duel != null ||
        dialogueTurns != episode.dialogue.length ||
        cell < 0 ||
        cell >= episode.puzzle.length ||
        episode.givenAt(cell) != 0 ||
        number < 0 ||
        number > episode.size) {
      return this;
    }
    final next = board?.toList() ?? episode.initialBoard();
    if (next[cell] == number) return this;
    next[cell] = number;
    if (episode.isSolved(next)) {
      return StoryProgress._(
        completed: completed + 1, unreadClue: true, signature: signature,
      );
    }
    return StoryProgress._(
      completed: completed,
      signature: signature,
      dialogueTurns: dialogueTurns,
      board: List.unmodifiable(next),
    );
  }

  bool _canDuel(int index, int points, List<StoryEpisode> episodes) =>
      _canPlay(index, points, episodes) &&
      episodes[index].duel != null &&
      dialogueTurns == episodes[index].dialogue.length &&
      board == null;

  SudokuDuel duelPosition(StoryEpisode episode) {
    return SudokuDuel.story(
      episode.duelPuzzle,
      episode.solution,
      duelMoves ?? const [],
      stage: episode.duel?.stage,
    );
  }

  StoryProgress playDuelMove(int index, int points, int cell, int digit, {
    List<StoryEpisode> episodes = storyEpisodes,
  }) {
    if (!_canDuel(index, points, episodes)) return this;
    final episode = episodes[index];
    if (cell < 0 || cell >= episode.puzzle.length ||
        digit != episode.answerAt(cell)) {
      return this;
    }
    if (!duelPosition(episode).canPlay(cell)) return this;
    return StoryProgress._(
      completed: completed,
      signature: signature,
      dialogueTurns: dialogueTurns,
      duelMoves: List.unmodifiable([...?duelMoves, cell]),
    );
  }

  StoryProgress finishDuel(int index, int points, {
    List<StoryEpisode> episodes = storyEpisodes,
  }) {
    if (!_canDuel(index, points, episodes) ||
        !duelPosition(episodes[index]).isOver) {
      return this;
    }
    return StoryProgress._(
      completed: completed + 1, unreadClue: true, signature: signature,
    );
  }

  StoryProgress useHint(
    int index,
    int points,
    int? selectedCell, {
    List<StoryEpisode> episodes = storyEpisodes,
  }) {
    if (!_canPlay(index, points, episodes)) return this;
    final episode = episodes[index];
    final current = board ?? episode.initialBoard();
    bool needsNumber(int cell) => current[cell] != episode.answerAt(cell);
    final cell =
        selectedCell != null &&
            selectedCell >= 0 &&
            selectedCell < current.length &&
            needsNumber(selectedCell)
        ? selectedCell
        : current.asMap().keys.firstWhere(needsNumber, orElse: () => -1);
    if (cell == -1) return this;
    return enterNumber(
      index,
      points,
      cell,
      episode.answerAt(cell),
      episodes: episodes,
    );
  }

  StoryProgress advanceResultDialogue(
    int index, {
    List<StoryEpisode> episodes = storyEpisodes,
  }) {
    if (!unreadClue ||
        index != completed - 1 ||
        index < 0 ||
        index >= episodes.length ||
        resultDialogueTurns >= episodes[index].resultDialogue.length) {
      return this;
    }
    return StoryProgress._(
      completed: completed,
      signature: signature,
      unreadClue: true,
      resultDialogueTurns: resultDialogueTurns + 1,
    );
  }

  /// Do not mark the clue read before the final story line is shown.
  StoryProgress readClue(
    int index, {
    List<StoryEpisode> episodes = storyEpisodes,
  }) => unreadClue &&
          index == completed - 1 &&
          index >= 0 &&
          index < episodes.length &&
          resultDialogueTurns == episodes[index].resultDialogue.length
      ? StoryProgress._(completed: completed, signature: signature)
      : this;

  Map<String, Object> toJson() => {
    'completed': completed,
    'dialogueTurns': dialogueTurns,
    'unreadClue': unreadClue,
    ...((signature == null)
        ? const <String, Object>{}
        : <String, Object>{'signature': signature!}),
    if (resultDialogueTurns != 0) 'resultDialogueTurns': resultDialogueTurns,
    if (board != null) 'board': board!.join(),
    'duelMoves': ?duelMoves,
  };

  factory StoryProgress.fromJson(Object? raw) {
    if (raw is! Map<String, dynamic> ||
        raw.keys.any(
          (key) => !const {
            'completed',
            'dialogueTurns',
            'unreadClue',
            'resultDialogueTurns',
            'signature',
            'board',
            'duelMoves',
          }.contains(key),
        )) {
      throw const FormatException('Invalid story save schema');
    }
    final completed = raw['completed'];
    final dialogueTurns = raw['dialogueTurns'];
    final unreadClue = raw['unreadClue'];
    final resultDialogueTurns = raw.containsKey('resultDialogueTurns')
        ? raw['resultDialogueTurns']
        : 0;
    final signature = raw['signature'];
    if (completed is! int ||
        completed < 0 ||
        dialogueTurns is! int ||
        dialogueTurns < 0 ||
        unreadClue is! bool ||
        resultDialogueTurns is! int ||
        resultDialogueTurns < 0 ||
        (signature != null && (signature is! String ||
            !RegExp(r'^[0-9a-f]{16}$').hasMatch(signature))) ||
        (resultDialogueTurns > 0 && !unreadClue) ||
        (unreadClue && (completed == 0 || dialogueTurns != 0))) {
      throw const FormatException('Invalid story progress');
    }
    List<int>? board;
    if (raw.containsKey('board')) {
      final cells = raw['board'];
      if (dialogueTurns == 0 ||
          cells is! String ||
          !RegExp(r'^(?:[0-4]{16}|[0-6]{36})$').hasMatch(cells)) {
        throw const FormatException('Invalid story board');
      }
      board = cells.codeUnits.map((unit) => unit - 48).toList();
    }
    List<int>? duelMoves;
    if (raw.containsKey('duelMoves')) {
      final moves = raw['duelMoves'];
      const maxCells = 81;
      if (board != null || dialogueTurns == 0 || unreadClue || moves is! List ||
          moves.isEmpty || moves.length > maxCells ||
          moves.any((cell) => cell is! int || cell < 0 || cell >= maxCells)) {
        throw const FormatException('Invalid story duel move list');
      }
      duelMoves = List<int>.unmodifiable(moves);
    }
    return StoryProgress._(
      completed: completed,
      dialogueTurns: dialogueTurns,
      unreadClue: unreadClue,
      resultDialogueTurns: resultDialogueTurns,
      signature: signature as String?,
      board: board == null ? null : List.unmodifiable(board),
      duelMoves: duelMoves,
    );
  }

  /// Validate against the pinned catalog after it loads. A new episode may
  /// have been released after the app was built, so decoding is catalog-free.
  void validateFor(StoryCatalog catalog, int points) {
    final episodes = catalog.episodes;
    if (signature != null && signature != catalog.progressSignature) {
      throw const FormatException('Story progress belongs to another edition');
    }
    if (completed > episodes.length ||
        (completed > 0 && episodes[completed - 1].unlockAt > points)) {
      throw const FormatException(
        'Story progress is outside the loaded catalog',
      );
    }
    if (resultDialogueTurns > 0 &&
        (!unreadClue ||
            completed == 0 ||
            completed > episodes.length ||
            resultDialogueTurns >
                episodes[completed - 1].resultDialogue.length)) {
      throw const FormatException('Invalid story result dialogue position');
    }
    if (dialogueTurns == 0) return;
    final episode = completed == episodes.length ? null : episodes[completed];
    if (episode == null ||
        episode.unlockAt > points ||
        dialogueTurns > episode.dialogue.length) {
      throw const FormatException('Invalid story dialogue position');
    }
    if (duelMoves != null) {
      if (episode.duel == null || dialogueTurns != episode.dialogue.length) {
        throw const FormatException('Duel data outside a story match');
      }
      duelPosition(episode);
    }
    final cells = board;
    if (cells == null) return;
    if (episode.duel != null || dialogueTurns != episode.dialogue.length ||
        cells.length != episode.puzzle.length) {
      throw const FormatException('Invalid story board');
    }
    for (var cell = 0; cell < cells.length; cell++) {
      final given = episode.givenAt(cell);
      if (given != 0 && cells[cell] != given) {
        throw const FormatException('Invalid digit in story board');
      }
    }
    if (episode.isSolved(cells)) {
      throw const FormatException('Solved story board must award its clue');
    }
  }
}
