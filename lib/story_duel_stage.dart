const _four = '1234341221434321';
const _six = '123456456123234561561234345612612345';
const _nine =
    '534678912672195348198342567859761423426853791713924856961537284287419635345286179';
const _nineGivens =
    '534600912070195340098342067009761420426850791710024806961037280280419635040280079';

/// An authored position, independent of its chapter number and cast.
/// Opening moves are legal turns from the givens; only later moves are saved.
enum StoryDuelStage {
  firstFlag('一本勝負', '最初の旗を取った方が勝ち。', '1004041000034021', _four, 1, firstTo: 1),
  safeSend(
    '送り先の稽古',
    '最初の旗で勝負。相手をどこへ送るか考えよう。',
    '1030040220004320',
    _four,
    1,
    firstTo: 1,
  ),
  berryFlag(
    'いちごの旗',
    '④のいちごの旗は2点。最後に点が多い方が勝ち。',
    '1004040001430301',
    _four,
    2,
    doubleRoom: 4,
  ),
  flagOrder(
    '旗を取る順番',
    '今取れる旗はふたつ。取ったあと、相手はどこへ行くかな？',
    '0200300201034321',
    _four,
    2,
    opening: [5, 10],
  ),
  doubleCapture(
    '旗の二連取り',
    '次の自分の番にも旗を取れる送り先を探そう。',
    '103450450123204561001204345012000345',
    _six,
    2,
    opening: [8, 27, 13, 19],
  ),
  endgame(
    'あと2本の終盤戦',
    '旗は3対3。あと2本を先に取ろう。',
    _nineGivens,
    _nine,
    3,
    opening: [11, 4, 72, 17, 77, 52, 41, 24, 48, 62, 28, 18, 9, 35, 57, 5],
  ),
  readAhead(
    '4×4の読み切り',
    '相手がどちらに返しても旗が取れる一手を探そう。',
    '0004340201004321',
    _four,
    16,
  ),
  sacrifice(
    '旗を譲る一局',
    '旗は1対1。今見えている旗をいつ取るか考えよう。',
    '000456456103030060500204345012010305',
    _six,
    7,
    opening: [0, 1, 10, 30, 27, 34, 22, 12],
  ),
  fiveFlags('9×9の五本先取', '9つの部屋の旗を、先に5本集めよう。', _nineGivens, _nine, 4);

  const StoryDuelStage(
    this.label,
    this.objective,
    this.puzzle,
    this.solution,
    this.lookAhead, {
    this.firstTo,
    this.doubleRoom,
    this.opening = const [],
  });

  final String label;
  final String objective;
  final String puzzle;
  final String solution;
  final int lookAhead;
  final int? firstTo;
  final int? doubleRoom;
  final List<int> opening;
}
