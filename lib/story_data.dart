import 'dart:math' as math;

import 'resident_collection.dart';
import 'town_areas.dart';

const storyTitle = 'ことほぎのまちのナゾの暗号';
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

const bundledStory = StoryCatalog(title: storyTitle, episodes: storyEpisodes);

// Original app content retained for compatibility checks and offline tests.
// Edit assets/story/story.json to publish new story content.
const storyEpisodes = <StoryEpisode>[
  StoryEpisode(
    id: 'episode_00',
    title: 'しばちゃんと数独のれんしゅう',
    area: TownArea.plaza,
    unlockAt: 0,
    dialogue: [
      (_pomu, 'しばちゃん！ この数字の遊び、いっしょに見てほしいぽむ。'),
      (_shiba, '数独だね。まずは4×4。1から4までの数字を、たて・よこ・太い線で囲まれた四角に、ひとつずつ入れるんだ。'),
      (_pomu, '数字がひとつだけ足りないところから探してみるぽむ！'),
    ],
    puzzle: '3204412300301342',
    solution: '3214412324311342',
    clue: 'れんしゅうクリア！',
    result: '数字を入れるコツがわかったね。累計30ことほぎで、広場の新しいお話が開くよ。',
    resultDialogue: [
      (_pomu, 'とけたぽむ！\nこれはなにぽむ！？ 広場のすみに、ふしぎな紙が落ちてるぽむ！'),
      (_shiba, 'すごいわん！\nほんとだ。数字が書いてあるね。'),
      (_pomu, 'だれが書いたぽむ？'),
      (_shiba, 'なんだろうね。ちょっと調べてみようか。'),
    ],
  ),
  StoryEpisode(
    id: 'episode_01',
    title: '広場のふしぎな紙',
    area: TownArea.plaza,
    unlockAt: 30,
    dialogue: [
      (_pomu, 'しばちゃん！ このあいだ見つけた紙を、ひろってきたぽむ！'),
      (_shiba, '数字がいっぱいだね。これも数独だよ。紙の裏に、うすく文字が見えるね。'),
      (_pomu, 'すうどく……？ どくがあるぽむ！？'),
      (_shiba, 'ふふ、大丈夫。数字をうめたら、裏のうすい文字が読めるかもしれないよ。'),
    ],
    puzzle: '0234040241032300',
    solution: '1234341241232341',
    clue: 'おおきな',
    result: '数字をうめると、紙の裏に最初のことばが浮かび上がった。',
    resultDialogue: [
      (_pomu, 'とけたぽむ！\n「おおきな」……なにが大きいぽむ？'),
      (_shiba, 'すごいわん！\nまだ途中のことばみたい。折り目の向こうに、何かかくれてるよ。'),
    ],
  ),
  StoryEpisode(
    id: 'episode_02',
    title: '折り目の向こう',
    area: TownArea.plaza,
    unlockAt: 60,
    dialogue: [
      (_pomu, '「おおきな」……おやつかな？'),
      (_shiba, '紙をひらいてみて。折り目の内側に、もう一問かくれてるよ。'),
    ],
    puzzle: '3100201310340001',
    solution: '3142241312344321',
    clue: 'きのした',
    result: '「おおきな」「きのした」。どこにある木だろう？',
    resultDialogue: [
      (_pomu, 'とけたぽむ！\n「きのした」！ おおきな木の下ぽむ！'),
      (_shiba, 'すごいわん！\nどこの木だろう？ まちには何本もあるよ。もうひとつ手がかりがほしいね。'),
    ],
  ),
  StoryEpisode(
    id: 'episode_03',
    title: '大きな木はどこ？',
    area: TownArea.plaza,
    unlockAt: 90,
    dialogue: [
      (_shiba, '紙のすみに、最後の数独がある。ここに場所の名前が出るかも。'),
      (_pomu, '木の下に何があるか、見にいきたいぽむ！'),
    ],
    puzzle: '1420000100002130',
    solution: '1423324143122134',
    clue: 'こうえん',
    result: '3つのことばがそろった！ 次は、ふれあい公園の大きな木の下へ。',
    resultDialogue: [
      (_pomu, 'とけたぽむ！\n「こうえん」！ 公園の大きな木ぽむ！？'),
      (_shiba, 'すごいわん！\nきっと、ふれあい公園のあの木だよ。根もとを探しにいってみよう！'),
      (_pomu, 'たからものがあるかもしれないぽむ！ わくわくするぽむ！'),
    ],
    destination: TownArea.park,
  ),
  StoryEpisode(
    id: 'episode_04',
    title: '木の根もとの封筒',
    area: TownArea.park,
    unlockAt: 120,
    dialogue: [
      (_pomu, '木の下に、はっぱ色の封筒があるぽむ！'),
      (_shiba, '今度は6×6だ。1から6までをひとつずつ。太い線の四角は、たて2マス、よこ3マスだよ。'),
    ],
    puzzle: '120063063104045600001245406012002456',
    solution: '124563563124245631631245456312312456',
    clue: 'あかい',
    result: '封筒の内側に、赤い色鉛筆の線と短いことばが現れた。',
    resultDialogue: [
      (_pomu, 'とけたぽむ！\n「あかい」……なにが赤いぽむ？'),
      (_shiba, 'すごいわん！\n赤い何かが目じるしなのかな。封筒にまだ続きがあるよ。'),
    ],
  ),
  StoryEpisode(
    id: 'episode_05',
    title: '風にゆれるもの',
    area: TownArea.park,
    unlockAt: 150,
    dialogue: [
      (_shiba, '赤い線をたどると、紙の端に小さな数独がある。'),
      (_pomu, '紙が風で飛ばないように、ぽむが持ってるね。'),
    ],
    puzzle: '045013132060003401010026000605356140',
    solution: '645213132564263451514326421635356142',
    clue: 'のれん',
    result: '「あかい のれん」。お店が並んでいる場所なら、見つかるかもしれない。',
    resultDialogue: [
      (_pomu, 'とけたぽむ！\nのれん！ 「あかい のれん」ぽむ！'),
      (_shiba, 'すごいわん！\nのれんなら、お店にありそうだね。場所も書いてあるかな？'),
    ],
  ),
  StoryEpisode(
    id: 'episode_06',
    title: '赤いのれんを探して',
    area: TownArea.park,
    unlockAt: 180,
    dialogue: [
      (_pomu, '赤いのれん、どこかで見た気がするぽむ。'),
      (_shiba, '封筒に残っている数独を解いて、場所を確かめよう。'),
    ],
    puzzle: '062043000600005360034015206501300406',
    solution: '562143413652125364634215246531351426',
    clue: 'しょうてんがい',
    result: '次の目的地は、ことほぎ商店街。風にゆれる赤いのれんを探そう。',
    resultDialogue: [
      (_pomu, 'とけたぽむ！\nしょうてんがい！ あまいおやつのお店もあるぽむ！？'),
      (_shiba, 'すごいわん！\nふふ、今日は赤いのれんを探すんだよ。行ってみよう！'),
    ],
    destination: TownArea.shopping,
  ),
  StoryEpisode(
    id: 'episode_07',
    title: 'のれんのそばの包み',
    area: TownArea.shopping,
    unlockAt: 210,
    dialogue: [
      (_pomu, 'あった！ 赤いのれんのそばに、小さな包みがあるぽむ。'),
      (_shiba, '葉っぱの絵が描いてある。中にはまた数独だね。'),
    ],
    puzzle: '250006000523610234004000000301400052',
    solution: '253416146523615234324165562341431652',
    clue: 'はたけ',
    result: '包みの中には、数独と小さな種が入っていた。',
    resultDialogue: [
      (_pomu, 'とけたぽむ！\nはたけ……？ 包みには、たねも入ってるぽむ！'),
      (_shiba, 'すごいわん！\nだれかが畑に届けてほしいのかもしれないね。'),
    ],
  ),
  StoryEpisode(
    id: 'episode_08',
    title: '種と小さな絵',
    area: TownArea.shopping,
    unlockAt: 240,
    dialogue: [
      (_shiba, '種の袋の裏に、柵の絵がある。となりにもう一問あるよ。'),
      (_pomu, 'この種、どんな花が咲くのかな。'),
    ],
    puzzle: '301600400200040005006401054100603002',
    solution: '321654465213142365536421254136613542',
    clue: 'はたけのそば',
    result: '畑のそばに何かありそう。包みには、まだ続きがある。',
    resultDialogue: [
      (_pomu, 'とけたぽむ！\nはたけのそば……この種をまくぽむ？'),
      (_shiba, 'すごいわん！\nもう少し読んでみよう。どこの畑かわからないと、届けられないもの。'),
    ],
  ),
  StoryEpisode(
    id: 'episode_09',
    title: '歩いていく目じるし',
    area: TownArea.shopping,
    unlockAt: 270,
    dialogue: [
      (_pomu, '柵のそばに、白い四角が描いてあるぽむ。'),
      (_shiba, 'この数独が、白い四角の正体を教えてくれるかも。'),
    ],
    puzzle: '030405000000042010000006403651150300',
    solution: '231465564132642513315246423651156324',
    clue: 'しろいふだ',
    result: '探すのは「畑のそばの白い札」。包みの底に、行き先を示す最後の暗号がある。',
    resultDialogue: [
      (_pomu, 'とけたぽむ！\nしろいふだ！ ぽむ、白い札を探すぽむ！'),
      (_shiba, 'すごいわん！\n畑のそばだね。あとひとつで場所がわかりそう！'),
    ],
  ),
  StoryEpisode(
    id: 'episode_10',
    title: '畑へつづく道',
    area: TownArea.shopping,
    unlockAt: 300,
    dialogue: [
      (_shiba, 'ここまでの手がかりを持って、種を届けにいこう。'),
      (_pomu, 'うん。この最後の暗号で、畑の場所がわかるぽむ！'),
    ],
    puzzle: '301002400000060000510306600000002063',
    solution: '351642426135263451514326635214142563',
    clue: 'のんびりざと',
    result: 'のんびり里の畑のそばに、白い札が立っていた。「種を見つけてくれてありがとう」。暗号を置いたのは、誰だろう？',
    resultDialogue: [
      (_pomu, 'とけたぽむ！\nのんびりざと！ 白い札を見つけたぽむ！'),
      (_shiba, 'すごいわん！\nだれかが、ここに種を届けてほしかったんだね。暗号を書いたのはだれだろう？'),
    ],
    destination: TownArea.village,
  ),
];
