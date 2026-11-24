import 'dart:convert';
import 'dart:math' as math;

import 'resident_collection.dart';
import 'story_duel_stage.dart';
import 'sudoku_duel.dart';
import 'town_areas.dart';

const storyTitle = 'ことほぎのまちの数独ものがたり';
const storyPlazaArt = 'assets/story/story_001_plaza_mystery.webp';
const storyParkArt = 'assets/story/story_002_park_tree.webp';
const storyShoppingArt = 'assets/story/story_003_shopping_clue.webp';

class StoryCatalog {
  const StoryCatalog({
    required this.title,
    required this.episodes,
    required this.chapters,
    this.coverImage,
    this.baseUri,
  });

  final String title;
  final List<StoryEpisode> episodes;
  final List<StoryChapter> chapters;
  final String? coverImage;

  int chapterIndexForEpisode(int episodeIndex) {
    if (episodeIndex < 0 || episodeIndex >= episodes.length || chapters.isEmpty) {
      throw RangeError('Invalid story chapter episode index: $episodeIndex');
    }
    for (var index = chapters.length - 1; index >= 0; index--) {
      if (episodeIndex >= chapters[index].startIndex) return index;
    }
    throw StateError('Story chapters do not cover episode $episodeIndex');
  }
  final Uri? baseUri;

  /// Fingerprint of save-relevant structure, not dialogue text or artwork.
  /// A structural edit starts a new story; text edits keep progress.
  String get progressSignature => storyProgressSignature(episodes);
}

class StoryChapter {
  const StoryChapter({
    required this.id,
    required this.title,
    required this.startIndex,
    this.duelStage,
  });

  final String id;
  final String title;
  final int startIndex;
  final StoryDuelStage? duelStage;
}

/// Chapter labels and boundaries are excluded from the saved episode signature.
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
        if (episode.duel?.stage case final stage?)
          [stage.name, stage.opening, stage.firstTo, stage.doubleRoom, stage.lookAhead],
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

extension DuelResident on DuelRival {
  TownResident get resident => switch (this) {
    DuelRival.mosaedo => TownResident.c036_mosa,
    DuelRival.oshisho => TownResident.c031_kimono_fox,
    DuelRival.pomupomu => TownResident.c052_pome,
    DuelRival.patissier => TownResident.c047_patisie,
  };
}

class StoryDuel {
  static const shibapome = StoryDuel._(_shiba, _pomu, DuelRival.pomupomu);
  static const dojo = StoryDuel._(_mosa, _oshisho, DuelRival.oshisho);
  static const cakeShop = StoryDuel._(_wife, _pastry, DuelRival.patissier);

  const StoryDuel._(this.player, this.opponent, this.rival) : stage = null;
  const StoryDuel.authored(this.player, this.opponent, StoryDuelStage this.stage)
      : rival = null;

  final StorySpeaker player;
  final StorySpeaker opponent;
  final DuelRival? rival;
  final StoryDuelStage? stage;
  String get title => '${player.label} VS ${opponent.label}';
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
    this.authoredDuel,
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
  final StoryDuel? authoredDuel;

  // Episode IDs are shared by the bundled story and its hosted edition.
  StoryDuel? get duel => authoredDuel ?? switch (id) {
    'episode_02' => StoryDuel.shibapome,
    'episode_04' => StoryDuel.dojo,
    'episode_07' => StoryDuel.cakeShop,
    _ => null,
  };

  // Tune the flag openings for these published puzzles. A replacement puzzle
  // from the CMS uses its own givens, and solo saves keep the catalog puzzle.
  String get duelPuzzle => duelPuzzleFor(DuelDifficulty.normal);

  String duelPuzzleFor(DuelDifficulty difficulty) {
    final (easy, normal, hard) = switch ((duel, puzzle)) {
      (StoryDuel.shibapome, '3100201310340001') =>
        ('3002001310344020', '3000201310344001', '3000001310340001'),
      (StoryDuel.dojo, '0021200304101200') =>
        ('0021010334121000', '0021000304101200', '0020000304101000'),
      (StoryDuel.cakeShop, '3410003401400021') =>
        ('3012003021430020', '3010003421400021', '3000000420000021'),
      _ => (puzzle, puzzle, puzzle),
    };
    return switch (difficulty) {
      DuelDifficulty.easy => easy,
      DuelDifficulty.normal => normal,
      DuelDifficulty.hard => hard,
    };
  }

  String? get clueImage => resultImage ?? (destination == null ? image : null);

  int get size => switch (puzzle.length) {
    16 => 4,
    36 => 6,
    81 => 9,
    final length => throw FormatException('Invalid puzzle size $length in $id'),
  };
  int get boxWidth => size == 9 ? 3 : size ~/ 2;
  int get boxHeight => size ~/ boxWidth;
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
        (row ~/ boxHeight == otherRow ~/ boxHeight &&
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
const _mosa = StorySpeaker.local(TownResident.c036_mosa);
const _frog = StorySpeaker.local(TownResident.c029_office_worker);
const _oyasumi = StorySpeaker.local(TownResident.c027_daydreamer);
const _genba = StorySpeaker.local(TownResident.c032_miner);
const _oshisho = StorySpeaker.local(TownResident.c031_kimono_fox);
const _wife = StorySpeaker.local(TownResident.rabbit);
const _pastry = StorySpeaker.local(TownResident.c047_patisie);
const _advisor = StorySpeaker.local(TownResident.c048_advicer);

const storyChapters = <StoryChapter>[
  StoryChapter(id: 'shibapome', title: 'しばぽめ', startIndex: 0),
  StoryChapter(id: 'mosaedo', title: 'モサエド', startIndex: 3),
  StoryChapter(id: 'oyomesan', title: 'およめさん', startIndex: 5),
  StoryChapter(id: 'oyasumi_club', title: 'おやすみクラブ', startIndex: 8),
];

const bundledStory = StoryCatalog(
  title: storyTitle,
  episodes: storyEpisodes,
  chapters: storyChapters,
);

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
      (_shiba, 'いち、に、わん、わん！ ……あれ？ なにか落ちてるわん。たいそうのはんこカードわん？'),
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
      (_pomu, 'よーし！ しばいぬと勝負ぽむ！ 特別なはんこ、いっしょに見つけるぽむ！'),
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

  StoryEpisode(
    id: 'episode_03',
    title: '数独道場破りでござる！',
    area: TownArea.plaza,
    unlockAt: 150,
    dialogue: [
      (_frog, 'おやすみくん、ここは3じゃないかな？'),
      (_oyasumi, 'むむむ……むずかしいもふ〜'),
      (_frog, 'あっ、そこはもう数字が入ってるよ'),
      (_oyasumi, 'ぼく、数独にはむいてないもふ。引退するもふ〜'),
      (_mosa, 'むむっ！ 何やら勝負の気配！'),
      (_frog, 'あ、モサエドさん。数独やってるんだよ'),
      (_mosa, '数独！ 近頃まちで噂の、数字の陣取り合戦でござるな！'),
      (_frog, 'いや、陣取り合戦では……'),
      (_mosa, '問答無用！ 拙者も挑戦するでござる！ あおんあおん！'),
    ],
    puzzle: '1004300220034320',
    solution: '1234341221434321',
    clue: 'おししょうからの挑戦！',
    result: '公民館で数独を解いたモサエドに、おししょうが勝負を持ちかけた。次はいよいよおししょうとの一局！',
    resultDialogue: [
      (_mosa, '勝ったでござる！ あおんあおん！'),
      (_frog, 'おお、すごい！ 初めてなのに解けちゃった！'),
      (_oyasumi, 'ぼく、引退してよかったもふ〜'),
      (_oshisho, 'ほほほ。威勢のええお侍さんどすなぁ'),
      (_mosa, 'むむっ！ 何奴！'),
      (_oshisho, 'そないに自信がおありなら……'),
      (_oshisho, 'うちに勝てはりますやろか？'),
    ],
  ),

  StoryEpisode(
    id: 'episode_04',
    title: 'おししょうの一局',
    area: TownArea.plaza,
    unlockAt: 180,
    dialogue: [
      (_oshisho, 'ほほほ。ほな、うちから一問、お出ししまひょ'),
      (_mosa, '望むところでござる！ いざ、勝負！'),
      (_frog, 'おししょう、数独も得意なんですね'),
      (_oshisho, 'お花も数独も、よう見て、あわてへんことどす'),
      (_oyasumi, 'ぼくは、見てるだけが得意もふ〜'),
      (_mosa, 'むむっ、余裕の構え……拙者も負けぬでござる！ あおんあおん！'),
    ],
    puzzle: '0021200304101200',
    solution: '4321214334121234',
    clue: '白い熊のうわさ',
    result: 'おししょうとの一局を終えたモサエドは、強者に白い熊から数独が届くという噂を耳にした。本当かどうかは、まだ誰も知らない。',
    resultDialogue: [
      (_mosa, 'おししょう、お手合わせ感謝でござる！ あおんあおん！'),
      (_oshisho, 'ほほ、おおきに。また一局、お相手しておくれやす'),
      (_mosa, 'むむむ……旗を取るだけではいかぬのでござるな！'),
      (_frog, '次に相手がどの部屋に送られるかも考えるんだね'),
      (_oshisho, 'そうどす。目の前の旗ばかり見てたらあきまへんえ'),
      (_oyasumi, 'ぼくは見てただけなのに楽しかったもふ〜'),
      (_mosa, 'むむっ！ 奥が深いでござる。もっと修行するでござる！'),
      (_oshisho, 'そうそう。ほんまの強者には、白い熊から数独が届く……なんて噂もありますえ'),
      (_mosa, 'し、白き熊！？ いずれお手合わせ願うでござる！ あおんあおん！'),
    ],
  ),
  StoryEpisode(
    id: 'episode_05',
    title: '帳簿と数独',
    area: TownArea.shopping,
    unlockAt: 210,
    dialogue: [
      (_wife, 'あら、ケーキは売れているのに、今月はあまりお金が残っていないわ'),
      (_pastry, 'バターも包み紙も、前より高くなっちゃったからねえ'),
      (_wife, '……あれ？ 帳簿の間に数字がぎっしりの紙があるわ'),
      (_pastry, 'あ、それはぼくの数独！ 休憩中に解きかけたままだった'),
      (_wife, 'ふふ。帳簿の続きはあとで、わたしも一局やってみようかしら'),
    ],
    puzzle: '2140402002303010',
    solution: '2143432112343412',
    clue: 'あしたは試食の日！',
    result: 'ケーキは売れているのに利益が少ない理由は、まだ調べることに。パティシエは明日の試食のお知らせを作る。',
    resultDialogue: [
      (_wife, 'あら、解けた！ 帳簿より先にこっちが片づいちゃった'),
      (_pastry, 'すごい！ ぼくは途中で止まってたのに'),
      (_wife, 'でも、お店のお金のことも二人で考えなくちゃね'),
      (_pastry, 'そうだ、明日はケーキの試食を出そう！ 看板も作るよ'),
    ],
  ),
  StoryEpisode(
    id: 'episode_06',
    title: 'ケーキ無料！？',
    area: TownArea.shopping,
    unlockAt: 240,
    dialogue: [
      (_pastry, 'わあ、お店の前に長い行列が！'),
      (_wife, '昨日の試食のお知らせを見てくれたのかしら'),
      (_advisor, 'お二人とも、あの看板をご覧ください'),
      (_wife, '「ケーキ 無料！」……ええっ！？'),
      (_pastry, '「試食」の札が風で飛んじゃった！ これじゃ全部無料に見えるよ！'),
      (_wife, '急いでお客さんに説明して、看板を直しましょう！'),
      (_pastry, 'ふう、みなさんに伝わったね。ひと休みして数独でもやろうか'),
    ],
    puzzle: '2104400200433001',
    solution: '2134431212433421',
    clue: '消えた「試食」の札',
    result: '看板の「試食」の札が風で飛び、「ケーキ 無料！」に見えていた。お客さんに事情を説明して看板を直し、試食の費用も帳簿に記録することに。通常のケーキはもちろん有料のまま。',
    resultDialogue: [
      (_wife, 'あら、解けた！ 数独をしていると落ち着くわね'),
      (_pastry, '看板を直せてよかった。無料なのは試食だけだもんね'),
      (_advisor, '試食に使った材料費も、別に記録しておくといいですよ'),
      (_wife, 'ええ。気に入って買ってくれたお客さんもいたし、続け方を考えましょう'),
      (_pastry, '今度は「試食」の札をしっかり留めておくよ！'),
    ],
  ),
  StoryEpisode(
    id: 'episode_07',
    title: 'ふたりの休憩時間',
    area: TownArea.shopping,
    unlockAt: 270,
    dialogue: [
      (_pastry, '今日は看板の「試食」、飛ばないようにしっかり留めたよ'),
      (_wife, 'ふふ。今日はちゃんと試食のご案内ができたわね'),
      (_pastry, '味見して気に入って、ケーキを買ってくれたお客さんもいたよ'),
      (_wife, '帳簿には試食の材料費も書いたし、少しずつ工夫していきましょう'),
      (_pastry, 'お店も閉めたし、お茶にしよう。今日は数独もあるよ'),
      (_wife, 'いいわね。今日はわたしと一局、勝負しない？'),
    ],
    puzzle: '3410003401400021',
    solution: '3412123421434321',
    clue: '数独は無料でどうぞ！',
    result: 'ケーキ屋さんの「無料」騒動は無事に解決。試食の案内も伝わり、閉店後は夫婦でお茶を飲みながら数独を楽しんだ。',
    resultDialogue: [
      (_wife, 'いい勝負だったわね。お店の数字も、また二人で考えましょう'),
      (_pastry, 'そうだね。「無料」の看板はもうこりごりだけど……'),
      (_wife, 'ふふ。じゃあ、次の数独は？'),
      (_pastry, 'もちろん、無料でどうぞ！'),
      (_wife, 'あら、よかった！ また一緒に遊びましょう'),
    ],
  ),

  StoryEpisode(
    id: 'episode_08',
    title: 'むかしのおしごと',
    area: TownArea.plaza,
    unlockAt: 300,
    dialogue: [
      (_frog, 'おやすみくん、向こうの道で工事してるね。なんだかにぎやかだなあ'),
      (_oyasumi, 'あの音、なつかしいもふ〜。ぼくもむかし、工事現場ではたらいてたもふ'),
      (_frog, 'えっ！ おやすみくん、ヘルメットかぶってたの！？'),
      (_oyasumi, 'かぶってたもふ〜。あつい日は、かげでひとやすみしたもふ'),
      (_frog, 'ほかにも覚えてることある？'),
      (_oyasumi, '休けい時間に、数字のパズルもやってたもふ。……これ、いっしょにとくもふ？'),
    ],
    puzzle: '0014402020301300',
    solution: '3214412324311342',
    clue: 'げんばくんに、また会いたいもふ',
    result: '数独をしながら、工事現場で道具の数を確かめていたころを思い出すおやすみくん。いっしょに働いていた「げんばくん」の名前が出てきた。',
    resultDialogue: [
      (_frog, 'できた！ そういえば、現場ではどんなことをしてたの？'),
      (_oyasumi, '道に印をつけたり、道具の数をかぞえたりしてたもふ〜'),
      (_frog, 'へえ！ 数を確かめるの、得意だったんだね'),
      (_oyasumi, 'げんばくんと、いっしょにはたらいてたもふ〜'),
      (_frog, 'げんばくん？'),
      (_oyasumi, 'むかしのなかまもふ。ひさしぶりに会いたいなぁ'),
    ],
  ),
  StoryEpisode(
    id: 'episode_09',
    title: 'ひさしぶりの同僚',
    area: TownArea.park,
    unlockAt: 330,
    dialogue: [
      (_frog, 'あっ、工事の人だ。今日は公園の道を直しているんですか？'),
      (_genba, 'そうだよ！ ……あれっ、おやすみくんじゃないか！'),
      (_oyasumi, 'げんばくん！ ひさしぶりもふ〜'),
      (_frog, 'えっ、二人は知り合いなの？'),
      (_genba, '昔、同じ工事現場で働いてたんだ。道具が一本足りないのに気づいたのも、おやすみくんだったよ！'),
      (_oyasumi, 'なくしものすると、さがすのたいへんもふ〜'),
      (_genba, 'あはは、そうだったね！ ちょうど休けい中なんだ。三人で数独やらない？'),
    ],
    puzzle: '4001014004101200',
    solution: '4321214334121234',
    clue: 'ゆっくりでも、しっかり確認',
    result: '公園の工事に来ていたげんばくんは、おやすみくんの元同僚だった。道具の数を確かめてくれた思い出を語り、三人で休けい中の数独を楽しんだ。',
    resultDialogue: [
      (_genba, '解けた！ 数独は間違えてもやり直せるから気楽だね'),
      (_frog, 'おやすみくん、そういうの得意だったんだね！'),
      (_oyasumi, 'もふ〜。ぼく、けっこうがんばってたもふ'),
      (_genba, 'あのときは助かったよ！ また一緒に遊ぼうね'),
      (_oyasumi, 'うん。げんばくん、またね〜'),
    ],
  ),
  StoryEpisode(
    id: 'episode_10',
    title: 'まだまだこれから',
    area: TownArea.plaza,
    unlockAt: 360,
    dialogue: [
      (_frog, 'げんばくんに会えてよかったね'),
      (_oyasumi, 'うん。むかしのこと、たくさんおもいだしたもふ〜'),
      (_frog, '今はお休み中だけど、これからやってみたいことってある？'),
      (_oyasumi, 'もふ〜。まだきめてないもふ'),
      (_frog, 'そっか。急いで決めなくてもいいよ'),
      (_oyasumi, 'でもね、きょうはじぶんで数独をといてみたいもふ〜'),
      (_frog, 'いいね！ ぼくは隣で応援するよ'),
    ],
    puzzle: '0140402010043400',
    solution: '2143432112343412',
    clue: 'ぼくはまだまだこれからなんだ〜',
    result: '昔は工事現場で働き、今はお休み中のおやすみくん。これからのことはまだ決まっていないけれど、今日は自分で数独を一局解けた。二人のおやすみクラブは、明日も続く。',
    resultDialogue: [
      (_oyasumi, '……とけたもふ！ ひとりでさいごまでできたもふ〜'),
      (_frog, 'すごい！ 前は途中で引退しちゃったのに！'),
      (_oyasumi, 'ふふ。きょうは、もうちょっとやってみたくなったもふ'),
      (_frog, '明日も一局やってみる？'),
      (_oyasumi, 'あしたのことは、あしたかんがえるもふ〜'),
      (_frog, 'あはは、おやすみくんらしいね'),
      (_oyasumi, 'ぼくはまだまだこれからなんだ〜'),
    ],
  ),
];
