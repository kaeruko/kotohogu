import 'dart:convert';
import 'dart:math' as math;

import 'resident_collection.dart';
import 'town_areas.dart';

const storyTitle = 'ことほぎのまちの数独ものがたり';
const storyPlazaArt = 'assets/story/story_001_plaza_mystery.png';
const storyParkArt = 'assets/story/story_002_park_tree.png';
const storyShoppingArt = 'assets/story/story_003_shopping_clue.png';

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
  });

  final String id;
  final String title;
  final int startIndex;
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
const _mosa = StorySpeaker.local(TownResident.c036_mosa);
const _frog = StorySpeaker.local(TownResident.c029_office_worker);
const _oyasumi = StorySpeaker.local(TownResident.c027_daydreamer);
const _oshisho = StorySpeaker.local(TownResident.c031_kimono_fox);
const _wife = StorySpeaker.local(TownResident.rabbit);
const _pastry = StorySpeaker.local(TownResident.c047_patisie);
const _advisor = StorySpeaker.local(TownResident.c048_advicer);

const storyChapters = <StoryChapter>[
  StoryChapter(id: 'shibapome', title: 'しばぽめ', startIndex: 0),
  StoryChapter(id: 'mosaedo', title: 'モサエド', startIndex: 3),
  StoryChapter(id: 'oyomesan', title: 'およめさん', startIndex: 5),
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
      (_mosa, 'とけたでござる！ これぞ拙者の勝利！'),
      (_oshisho, 'ほほ、お見事。うちも先ほど解けましたえ'),
      (_mosa, 'なっ……いつの間に！'),
      (_frog, 'おししょう、速いなあ'),
      (_oshisho, '速さを競うより、楽しむことが一番どすえ'),
      (_oyasumi, 'ぼくは見てただけなのに楽しかったもふ〜'),
      (_mosa, '拙者、まだまだ修行が足りぬでござる！'),
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
      (_wife, 'あら、今月の材料費、ちょっと増えてるわね'),
      (_pastry, 'バターも包み紙も、前より高くなっちゃってね'),
      (_wife, '……あれ？ 帳簿の間に、数字のマスがあるわ'),
      (_pastry, 'あ、それは休憩中に解いてた数独だよ。まだ途中なんだ'),
      (_wife, 'ふふ、帳簿の続きかと思っちゃった。わたしもやってみようかしら'),
    ],
    puzzle: '2140402002303010',
    solution: '2143432112343412',
    clue: 'はじめての一局！',
    result: '帳簿に挟まっていたのは、パティシエが休憩中に遊んでいた数独。およめさんもすっかり夢中に。',
    resultDialogue: [
      (_wife, 'あら、解けたわ！ なんだかすっきりした'),
      (_pastry, 'ぼくが途中で止まってたところまで解けちゃったね'),
      (_wife, 'じゃあ、帳簿の続きも一緒に見ましょうか'),
      (_pastry, 'うん。お店の数字は二人で考えよう'),
    ],
  ),
  StoryEpisode(
    id: 'episode_06',
    title: '売れているのに？',
    area: TownArea.shopping,
    unlockAt: 240,
    dialogue: [
      (_pastry, '今月はお客さんが増えたんだ。うれしいな'),
      (_wife, 'そうね。でも、思ったほどお金が残っていないみたい'),
      (_pastry, '材料費だけじゃなくて、包み紙や光熱費もあるからね'),
      (_advisor, '売上と利益は別の数字です。何にどれくらいかかっているか、一緒に整理しましょう'),
      (_wife, 'なるほど……今日はここまでにして、ひと休みしましょう'),
      (_pastry, '数独、もう一問持ってきたよ'),
      (_wife, 'ふふ。今度はわたしが先に解いちゃうかも'),
    ],
    puzzle: '2104400200433001',
    solution: '2134431212433421',
    clue: 'お店の数字も整理しよう',
    result: 'しんだんしと支出を整理し、仕入れと売れ残りを見直すことに。数独は二人の楽しい休憩時間。',
    resultDialogue: [
      (_pastry, 'ぼく、最後の二マスで迷っちゃった'),
      (_wife, 'ふふ、こっちはきれいに答えが決まるのね'),
      (_advisor, 'お店の数字は、答えを一つに決めるより、続けられる方法を探すことが大事ですね'),
      (_wife, 'ええ。明日から、仕入れと売れ残りも少しずつ記録してみるわ'),
      (_pastry, 'ぼくも一緒にやるよ'),
    ],
  ),
  StoryEpisode(
    id: 'episode_07',
    title: 'ふたりの休憩時間',
    area: TownArea.shopping,
    unlockAt: 270,
    dialogue: [
      (_pastry, '今週は、材料の発注を少し見直してみたよ'),
      (_wife, '売れ残りも前より減ったみたい。無理なく続けたいわね'),
      (_pastry, '今日はお店も片づいたし、お茶にしようか'),
      (_wife, 'ええ。あ、今日の数独も持ってきたの？'),
      (_pastry, 'もちろん。今度こそ先に解きたいな'),
      (_wife, 'ふふ、負けないわよ'),
    ],
    puzzle: '3410003401400021',
    solution: '3412123421434321',
    clue: 'ふたりの休憩時間',
    result: '帳簿は二人で相談しながら、数独は楽しい真剣勝負。小さなケーキ屋さんの一日は穏やかに終わった。',
    resultDialogue: [
      (_wife, 'できた！ 今日はわたしのほうが早かったみたい'),
      (_pastry, 'あれ？ ぼく、まだ一マス残ってる……'),
      (_wife, 'お店の数字は二人で考えて、数独はわたしの勝ちね'),
      (_pastry, '参ったなあ。次は頑張るよ'),
      (_wife, 'ふふ。明日も一緒に遊びましょう'),
    ],
  ),
];
