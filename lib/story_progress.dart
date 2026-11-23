import 'story_data.dart';

/// The completed episodes form a prefix. Only the next episode needs a board
/// and a dialogue position. Availability is derived from lifetime points.
class StoryProgress {
  const StoryProgress.empty() : this._();

  const StoryProgress._({
    this.completed = 0,
    this.dialogueTurns = 0,
    this.board,
    this.unreadClue = false,
  });

  final int completed;
  final int dialogueTurns;
  final List<int>? board;
  final bool unreadClue;

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
    if (dialogueTurns != episode.dialogue.length ||
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
      return StoryProgress._(completed: completed + 1, unreadClue: true);
    }
    return StoryProgress._(
      completed: completed,
      dialogueTurns: dialogueTurns,
      board: List.unmodifiable(next),
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

  StoryProgress readClue(int index) => unreadClue && index == completed - 1
      ? StoryProgress._(completed: completed)
      : this;

  Map<String, Object> toJson() => {
    'completed': completed,
    'dialogueTurns': dialogueTurns,
    'unreadClue': unreadClue,
    if (board != null) 'board': board!.join(),
  };

  factory StoryProgress.fromJson(Object? raw) {
    if (raw is! Map<String, dynamic> ||
        raw.keys.any(
          (key) => !const {
            'completed',
            'dialogueTurns',
            'unreadClue',
            'board',
          }.contains(key),
        )) {
      throw const FormatException('Invalid story save schema');
    }
    final completed = raw['completed'];
    final dialogueTurns = raw['dialogueTurns'];
    final unreadClue = raw['unreadClue'];
    if (completed is! int ||
        completed < 0 ||
        dialogueTurns is! int ||
        dialogueTurns < 0 ||
        unreadClue is! bool ||
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
    return StoryProgress._(
      completed: completed,
      dialogueTurns: dialogueTurns,
      unreadClue: unreadClue,
      board: board == null ? null : List.unmodifiable(board),
    );
  }

  /// Validate against the pinned catalog after it loads. A new episode may
  /// have been released after the app was built, so decoding is catalog-free.
  void validateFor(StoryCatalog catalog, int points) {
    final episodes = catalog.episodes;
    if (completed > episodes.length ||
        (completed > 0 && episodes[completed - 1].unlockAt > points)) {
      throw const FormatException(
        'Story progress is outside the loaded catalog',
      );
    }
    if (dialogueTurns == 0) return;
    final episode = completed == episodes.length ? null : episodes[completed];
    if (episode == null ||
        episode.unlockAt > points ||
        dialogueTurns > episode.dialogue.length) {
      throw const FormatException('Invalid story dialogue position');
    }
    final cells = board;
    if (cells == null) return;
    if (dialogueTurns != episode.dialogue.length ||
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
