import 'dart:math' as math;

import 'resident_collection.dart';
import 'town_areas.dart';

const storyTitle = 'ことほぎのまちのナゾの暗号';
const storyPlazaArt = 'assets/story/story_001_plaza_mystery.png';
const storyParkArt = 'assets/story/story_002_park_tree.png';
const storyShoppingArt = 'assets/story/story_003_shopping_clue.png';

class StoryEpisode {
  const StoryEpisode({
    required this.title,
    required this.area,
    required this.unlockAt,
    required this.dialogue,
    required this.puzzle,
    required this.solution,
    required this.clue,
    required this.result,
    this.destination,
  });

  final String title;
  final TownArea area;
  final int unlockAt;
  final List<(TownResident, String)> dialogue;
  final String puzzle;
  final String solution;
  final String clue;
  final String result;
  final TownArea? destination;

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

const _shiba = TownResident.shiba;
const _pomu = TownResident.c052_pome;

// Save data uses the order of these episodes. Keep released puzzles and
// dialogue turn counts stable, and append new episodes at the end.
const storyEpisodes = <StoryEpisode>[
  StoryEpisode(
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
  ),
  StoryEpisode(
    title: '広場のふしぎな紙',
    area: TownArea.plaza,
    unlockAt: 30,
    dialogue: [
      (_pomu, 'しばちゃん！ なぞのかみをひろったぽむ！'),
      (_shiba, 'なんだろう？ 数字がいっぱいだね。あ、さっき練習した数独だ。'),
      (_pomu, 'すうどく……？ どくがあるぽむ！？'),
      (_shiba, 'ふふ、大丈夫。数字をうめたら、裏のうすい文字が読めるかもしれないよ。'),
    ],
    puzzle: '0234040241032300',
    solution: '1234341241232341',
    clue: 'おおきな',
    result: '数字をうめると、紙の裏に最初のことばが浮かび上がった。',
  ),
  StoryEpisode(
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
  ),
  StoryEpisode(
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
    destination: TownArea.park,
  ),
  StoryEpisode(
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
  ),
  StoryEpisode(
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
  ),
  StoryEpisode(
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
    destination: TownArea.shopping,
  ),
  StoryEpisode(
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
  ),
  StoryEpisode(
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
  ),
  StoryEpisode(
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
  ),
  StoryEpisode(
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
    destination: TownArea.village,
  ),
];
