import 'dart:convert';
import 'dart:math' as math;

import 'resident_collection.dart';
import 'town_areas.dart';

const storyTitle = 'たいそうのはんこカードのなぞ';
const storyPlazaArt = 'assets/story/story_001_plaza_mystery.png';
const storyParkArt = 'assets/story/story_002_park_tree.png';
const storyShoppingArt = 'assets/story/story_003_shopping_clue.png';

class StoryCatalog {
  const StoryCatalog({
    required this.title,
    required this.episodes,
    this.coverImage,
    this.baseUri,
  });

  final String title;
  final List<StoryEpisode> episodes;
  final String? coverImage;
  final Uri? baseUri;

  /// Fingerprint of save-relevant structure, not dialogue text or artwork.
  /// A structural edit starts a new story; text edits keep progress.
  String get progressSignature => storyProgressSignature(episodes);
}

/// Deterministic structural identity without changing the hosted JSON schema.
String storyProgressSignature(List<StoryEpisode> episodes) {
  final structure = jsonEncode([
    for (final episode in episodes)
      [
        episode.id,
        episode.area.id,
        episode.destination?.id,
        episode.unlockAt,
        episode.puzzle,
        episode.solution,
        episode.dialogue.length,
        episode.resultDialogue.length,
      ],
  ]);
  // Two 32-bit accumulators; content identity, not an authentication token.
  var hashA = 0x811c9dc5;
  var hashB = 0x9e3779b9;
  for (final value in structure.codeUnits) {
    hashA = ((hashA ^ value) * 0x01000193) & 0xffffffff;
    hashB = ((hashB + value) * 0x27d4eb2d) & 0xffffffff;
  }
  return "${hashA.toRadixString(16).padLeft(8, '0')}"
      "${hashB.toRadixString(16).padLeft(8, '0')}";
}


class StorySpeaker {
  const StorySpeaker.local(TownResident resident)
    : _resident = resident,
      _label = null,
      portrait = null;
  const StorySpeaker.hosted(String label, Uri uri)
    : _label = label,
      _resident = null,
      portrait = uri;

  final TownResident? _resident;
  final String? _label;
  final Uri? portrait;
  String get label => _label ?? _resident!.label;
  String get localPortrait => _resident!.idleAsset;
}

class StoryEpisode {
  const StoryEpisode({
    required this.id,
    required this.title,
    required this.area,
    required this.unlockAt,
    required this.dialogue,
    required this.puzzle,
    required this.solution,
    required this.clue,
    required this.result,
    this.resultDialogue = const [],
    this.destination,
    this.image,
    this.resultImage,
  });

  final String id;
  final String title;
  final TownArea area;
  final int unlockAt;
  final List<(StorySpeaker, String)> dialogue;
  final String puzzle;
  final String solution;
  final String clue;
  final String result;

  /// Conversations after solving. Saved dialogue positions remain unchanged.
  final List<(StorySpeaker, String)> resultDialogue;
  final TownArea? destination;
  final String? image;
  final String? resultImage;

  String? get clueImage => resultImage ?? (destination == null ? image : null);

  int get size => puzzle.length == 16 ? 4 : 6;
  int get boxWidth => size ~/ 2;
  String get art => artFor(area);
  String get resultArt => artFor(destination ?? area);

  bool isAvailable(int points) =>
      points >= unlockAt &&
      area.isUnlocked(points) &&
      (destination?.isUnlocked(points) ?? true);

  int pointsNeeded(int points) => math.max(
    0,
    math.max(unlockAt, math.max(area.unlockAt, destination?.unlockAt ?? 0)) -
        points,
  );

  static String artFor(TownArea area) => switch (area) {
    TownArea.plaza => storyPlazaArt,
    TownArea.park => storyParkArt,
    TownArea.shopping => storyShoppingArt,
    _ => area.backgroundAsset!,
  };

  int givenAt(int cell) => puzzle.codeUnitAt(cell) - 48;
  int answerAt(int cell) => solution.codeUnitAt(cell) - 48;
  List<int> initialBoard() => List.generate(puzzle.length, givenAt);

  bool sharesGroup(int a, int b) {
    final row = a ~/ size;
    final column = a % size;
    final otherRow = b ~/ size;
    final otherColumn = b % size;
    return row == otherRow ||
        column == otherColumn ||
        (row ~/ 2 == otherRow ~/ 2 &&
            column ~/ boxWidth == otherColumn ~/ boxWidth);
  }

  bool hasConflict(List<int> board, int cell) =>
      board[cell] != 0 &&
      board.asMap().entries.any(
        (entry) =>
            entry.key != cell &&
            entry.value == board[cell] &&
            sharesGroup(cell, entry.key),
      );

  bool isSolved(List<int> board) =>
      board.length == puzzle.length &&
      board.asMap().entries.every(
        (entry) => entry.value == answerAt(entry.key),
      );
}

const _shiba = StorySpeaker.local(TownResident.shiba);
const _pomu = StorySpeaker.local(TownResident.c052_pome);
const _gonsuke = StorySpeaker.local(TownResident.c042_senior_dog);

const bundledStory = StoryCatalog(title: storyTitle, episodes: storyEpisodes);

// Bundled story mirrors the current CMS story for offline and UI tests.
// The legacy hosted endpoint is separately frozen for older app releases.
const storyEpisodes = <StoryEpisode>[
  StoryEpisode(
    id: 'episode_00',
    title: 'たいそうのはんこカード？',
    area: TownArea.plaza,
    unlockAt: 0,
    dialogue: [
      (_pomu, 'いち、に、ぽむ、ぽむ！ あさのたいそう、きもちいいぽむ〜！'),
      (_shiba, 'いち、に、さん、し！ ……あれ？ なにか落ちてるわん。たいそうのはんこカードわん？'),
      (_pomu, 'ぽむもはんこほしいぽむ〜！ ……あれ？ はんこのかわりに数字が書いてあるぽむ。これはなにぽむ？'),
    ],
    puzzle: '3204412300301342',
    solution: '3214412324311342',
    clue: 'おおきな きのした',
    result: '数字をうめると、紙に「おおきな きのした」と文字が浮かんだ。ふれあい公園の大きな木のことかな？',
    resultDialogue: [
      (_pomu, 'とけたぽむ！\n「おおきな きのした」……おおきなおやつがあるぽむ！？'),
      (_shiba, 'すごいわん！\nふれあい公園の大きな木かもしれないわん！'),
      (_pomu, 'ぽむ、木の下を見にいきたいぽむ〜！'),
      (_shiba, 'いっしょに探しにいくわん！'),
    ],
  ),
  StoryEpisode(
    id: 'episode_01',
    title: '木の下になにがある？',
    area: TownArea.park,
    unlockAt: 90,
    dialogue: [
      (_pomu, 'おおきな木、みつけたぽむ〜！ おやつはどこぽむ？'),
      (_shiba, 'あっ！ 木の根っこのあいだに、小さな箱があるわん！'),
      (_pomu, 'たからばこぽむ！？ ……あれ？ ふたに数字のマスがあるぽむ。'),
      (_shiba, '鍵のかわりに数独を解くんだわん！ いっしょにやってみるわん！'),
    ],
    puzzle: '0234040241032300',
    solution: '1234341241232341',
    clue: 'ほんとうにはんこカード！',
    result: '箱の中には朝の体操のはんこカードがいっぱい！「最後の数独を解いた子に、特別なはんこをあげます」と書いてある。',
    resultDialogue: [
      (_pomu, 'とけたぽむ！\nふたが開いたぽむ！ ……はんこカードがいっぱいぽむ！？'),
      (_shiba, 'すごいわん！\nほんとうにたいそうのはんこカードだったわん！'),
      (_pomu, 'ごほうびのはんこもほしいぽむ〜！'),
      (_shiba, '箱の底にもう一問あるわん。これが最後みたいだわん！'),
    ],
  ),
  StoryEpisode(
    id: 'episode_02',
    title: 'ひみつのごほうび',
    area: TownArea.park,
    unlockAt: 120,
    dialogue: [
      (_pomu, 'はんこカード、いっぱいあるぽむ！ 特別なはんこはどこぽむ？'),
      (_shiba, '箱の底に最後の数独があるわん。解いたら持ち主がわかるかもしれないわん！'),
      (_pomu, 'よーし！ ぽむ、がんばるぽむ！'),
    ],
    puzzle: '3100201310340001',
    solution: '3142241312344321',
    clue: 'さくらのはんこ 🌸',
    result: '3話完結！ 朝の体操を楽しくしたかったごんすけさんから、さくらのはんこをもらったよ。10こ集めたごほうびは……「朝の体操第二」！',
    resultDialogue: [
      (_pomu, 'とけたぽむ！\nさいごの数独もできたぽむ〜！'),
      (_shiba, 'すごいわん！\nあれ？ 木の向こうからだれか来るわん！'),
      (_gonsuke, 'おお、見つけたか！ 朝の体操を楽しくしたくて、わしが用意したんじゃ！'),
      (_pomu, 'ごんすけさん！ ごほうびのおやつあるぽむ？'),
      (_gonsuke, '特別なさくらのはんこじゃ！ ぽんっ！'),
      (_pomu, 'やったぽむ！ 10こ集めたら何がもらえるぽむ？'),
      (_gonsuke, 'とっておきの、朝の体操第二じゃ！'),
      (_pomu, '…………おやつじゃないぽむ〜！？'),
      (_shiba, 'ふふっ。あしたの体操も楽しみだわん！'),
    ],
  ),
];
