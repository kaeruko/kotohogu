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

  bool _canPlay(int index, int points) =>
      !unreadClue &&
      index == completed &&
      index < storyEpisodes.length &&
      storyEpisodes[index].isAvailable(points);

  StoryProgress advanceDialogue(int index, int points) {
    if (!_canPlay(index, points) ||
        dialogueTurns >= storyEpisodes[index].dialogue.length) {
      return this;
    }
    return StoryProgress._(
      completed: completed,
      dialogueTurns: dialogueTurns + 1,
    );
  }

  StoryProgress enterNumber(int index, int points, int cell, int number) {
    if (!_canPlay(index, points)) return this;
    final episode = storyEpisodes[index];
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

  StoryProgress useHint(int index, int points, int? selectedCell) {
    if (!_canPlay(index, points)) return this;
    final episode = storyEpisodes[index];
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
    return enterNumber(index, points, cell, episode.answerAt(cell));
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

  factory StoryProgress.fromJson(Object? raw, int points) {
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
        completed > storyEpisodes.length ||
        dialogueTurns is! int ||
        dialogueTurns < 0 ||
        unreadClue is! bool ||
        (unreadClue && (completed == 0 || dialogueTurns != 0)) ||
        storyEpisodes
            .take(completed)
            .any((episode) => episode.unlockAt > points)) {
      throw const FormatException('Invalid story progress');
    }
    final episode = completed == storyEpisodes.length
        ? null
        : storyEpisodes[completed];
    if (dialogueTurns > 0 &&
        (episode == null ||
            episode.unlockAt > points ||
            dialogueTurns > episode.dialogue.length)) {
      throw const FormatException('Invalid story dialogue position');
    }
    List<int>? board;
    if (raw.containsKey('board')) {
      final cells = raw['board'];
      if (episode == null ||
          dialogueTurns != episode.dialogue.length ||
          cells is! String ||
          cells.length != episode.puzzle.length) {
        throw const FormatException('Invalid story board');
      }
      board = cells.codeUnits.map((unit) => unit - 48).toList();
      for (var cell = 0; cell < board.length; cell++) {
        final given = episode.givenAt(cell);
        if (board[cell] < 0 ||
            board[cell] > episode.size ||
            (given != 0 && board[cell] != given)) {
          throw const FormatException('Invalid digit in story board');
        }
      }
      if (episode.isSolved(board)) {
        throw const FormatException('Solved story board must award its clue');
      }
    }
    return StoryProgress._(
      completed: completed,
      dialogueTurns: dialogueTurns,
      unreadClue: unreadClue,
      board: board == null ? null : List.unmodifiable(board),
    );
  }
}
