import 'package:flutter/material.dart';

import 'dev_tools.dart';

int get ownedResidentLimit => TownResident.values.length > 8 ? TownResident.values.length : 8;
/// All enabled residents can appear in their assigned town area.
/// A debug-only override may include unowned/hidden residents without saving them.
/// An empty override deliberately shows no residents.
List<TownResident> visibleTownResidents(
  Iterable<TownResident> residents, {
  List<TownResident>? debugOverride,
}) {
  if (debugOverride != null) {
    if (debugOverride.toSet().length != debugOverride.length) {
      throw ArgumentError.value(
        debugOverride,
        'debugOverride',
        'Each resident may be selected only once',
      );
    }
    return List<TownResident>.unmodifiable(debugOverride);
  }
  return List<TownResident>.unmodifiable(
    residents.where((resident) => resident.walkInTown && resident.homeAreaId != 'salon'),
  );
}
/// Only obtaining the salon owner through gacha unlocks the building.
/// The fox is a resident of the salon, not its unlocking condition.
bool isSalonUnlocked(Iterable<TownResident> owned) =>
    owned.contains(TownResident.c035_beaty);

/// Temporary debug preview, never part of saved progress.
enum SalonUnlockDebugMode { normal, forceOpen, forceClosed }

bool isSalonAccessible(
  Iterable<TownResident> owned, {
  SalonUnlockDebugMode debugMode = SalonUnlockDebugMode.normal,
}) {
  final ownedOwner = isSalonUnlocked(owned);
  if (!developerToolsAvailable) return ownedOwner;
  return switch (debugMode) {
    SalonUnlockDebugMode.normal => ownedOwner,
    SalonUnlockDebugMode.forceOpen => true,
    SalonUnlockDebugMode.forceClosed => false,
  };
}

/// Salon occupants are separate from outdoor walkers.
/// Every gacha resident must be acquired before appearing in the salon.
List<TownResident> salonResidents(
  Iterable<TownResident> owned, {
  bool previewUnowned = false,
}) {
  if (previewUnowned && !developerToolsAvailable) {
    throw StateError('Salon preview of unowned residents requires debug mode');
  }
  final ownedSet = owned.toSet();
  final occupants = TownResident.values.where((resident) =>
      resident.homeAreaId == 'salon' &&
      (previewUnowned || !resident.inGacha || ownedSet.contains(resident))).toList();
  const owner = TownResident.c035_beaty;
  const fox = TownResident.c031_kimono_fox;
  return List<TownResident>.unmodifiable([
    if (occupants.contains(owner)) owner,
    if (occupants.contains(fox)) fox,
    for (final resident in occupants)
      if (resident != owner && resident != fox) resident,
  ]);
}

const applauseResidentLimit = 8;

/// Maximum spendable kotohogi; contribution totals keep growing.
const maxSpendableKotohogi = 999;

enum WalkDirection { front, back, left, right }

enum TownResident {
  // BEGIN CMS RESIDENTS
  shiba("001_shiba", "しばいぬ", "001_shiba", true, true, "", "plaza", archived: false),
  rabbit("002_usagi", "うさぎ", "002_usagi", true, true, "", "park", archived: false),
  penguin("003_penguin", "まちの案内係", "003_penguin", true, true, "", "plaza", archived: false),
  cat("004_neko", "せんせい", "004_neko", true, true, "ことほぎのまちで長く診療を続けてきた、少し年配のかかりつけ医。病名や年齢だけで決めつけず、その人が望む暮らしを大切にしている。必要なときは専門医やほかの医療職と協力する。自身も緑内障で片目がほとんど見えなくなり、もう片方の目も眼科で定期的に診てもらっている。見え方に合う工夫をしながら、住民と同じように日々を暮らす。穏やかで聞き上手だが、言うべきことはきちんと伝える。患者さんには休息を勧める一方、自分はつい働きすぎてしまう、少しお茶目な先生。", "shopping", archived: false),
  squirrel("005_risu", "ドライバー", "005_risu", true, true, "ことほぎのまちで生まれ育った配達員。まちの道や住民のおうちに詳しいけれど、配達の仕事はまだ新人。好奇心旺盛でつい寄り道してしまうが、預かった荷物は大切に届ける。住民たちとおしゃべりしたり、道ばたの季節の変化を見つけたりするのが好き。お届け先の秘密は決して言いふらさない。", "park", archived: false),
  bear("006_kuma", "だいくさん", "006_kuma", true, true, "まちの家やお店を建て、家具やベンチを直す大工。腕はいいが口下手で、頼まれなくても壊れたものをそっと修理する。完成した建物が手を離れるのは少し寂しいけれど、そこで誰かの暮らしが始まることを喜んでいる。", "village", archived: false),
  // ignore: constant_identifier_names
  c009_chef("009_chef", "シェフ", "009_chef", true, true, "", "shopping", archived: false),
  // ignore: constant_identifier_names
  c026_farmer("026_farmer", "やすぞう", "026_farmer", true, true, "本名：多賀　康三。健康を意識している中年男性。", "park", archived: false),
  // ignore: constant_identifier_names
  c027_daydreamer("027_daydreamer", "おやすみくん", "027_daydreamer", true, true, "おしごともべんきょうもおやすみ中の子。ぼくはまだまだこれからなんだ～", "park", archived: false),
  // ignore: constant_identifier_names
  c032_miner("032_miner", "もぐた", "032_miner", true, true, "道路や公園など、まちの土台をつくる土木工事の職人。元気いっぱいで、まちづくりが大好きな子。", "shopping", archived: false),
  // ignore: constant_identifier_names
  c036_mosa("036_mosa", "モサエド", "036_mosa", true, true, "拙者、猛者江戸（モサエド）と申す！", "plaza", archived: false),
  // ignore: constant_identifier_names
  c035_beaty("035_beaty", "つやこ", "035_beaty", true, false, "美容家", "salon", archived: false),
  // ignore: constant_identifier_names
  c031_kimono_fox("031_kimono_fox", "きものぎつね", "031_kimono_fox", true, false, "桜の美容室の看板娘。和装が好きで、みんなを笑顔で迎える。", "salon", archived: false),
  // ignore: constant_identifier_names
  c037_tora("037_tora", "とらお", "037_tora", true, true, "", "park", archived: false),
  // ignore: constant_identifier_names
  c029_office_worker("029_office_worker", "かえる", "029_office_worker", true, true, "", "plaza", archived: false),
  // ignore: constant_identifier_names
  c038_lion_lady("038_lion_lady", "リオコ", "038_lion_lady", true, true, "", "salon", archived: false),
  // ignore: constant_identifier_names
  c034_artist("034_artist", "くまりん", "034_artist", true, true, "絵を描くのが大好きな女の子。自分の描きたい絵と、みんなに喜んでもらえる絵の間で悩みながら、少しずつ自分らしい表現を探している。", "village", archived: false),
  // ignore: constant_identifier_names
  c015_office_worker("015_office_worker", "ぶちょう", "015_office_worker", true, true, "", "plaza", archived: false),
  // ignore: constant_identifier_names
  c028_caregiver("028_caregiver", "ぱんこ先生", "028_caregiver", true, true, "", "shopping", archived: false),
  // ignore: constant_identifier_names
  c041_pig_middle("041_pig_middle", "とんこ", "041_pig_middle", true, true, "", "village", archived: false),
  // ignore: constant_identifier_names
  c042_senior_dog("042_senior_dog", "ごんすけ", "042_senior_dog", true, true, "", "park", archived: false),
  // ignore: constant_identifier_names
  c007_hitsuji("007_hitsuji", "めりぃ", "007_hitsuji", true, true, "", "plaza", archived: false)
  // END CMS RESIDENTS
  ;

  const TownResident(this.id, this.label, this.artFolder, this.inGacha, this.walkInTown, this.profile, this.homeAreaId, {required this.archived});
  final String id;
  final String label;
  final String artFolder;
  final bool inGacha;
  final bool walkInTown;
  /// Archived residents retain their saved identity, but do not join applause.
  final bool archived;
  final String profile;
  /// Legacy catalog field: 'salon' means indoor-only. Other values are kept
  /// for compatibility and debug views, but do not affect random outings.
  final String homeAreaId;
  static List<TownResident> get gachaPool =>
      values.where((resident) => !resident.archived && resident.inGacha).toList(growable: false);
  String get idleAsset => 'assets/characters/$artFolder/idle_front_01.png';
  List<String> get clapAssets => [
    for (final frame in ['01', '02'])
      'assets/characters/$artFolder/clap_front_$frame.png',
  ];
  /// Walking assets use four real poses per direction.
  /// Shiba's left-facing frames were never supplied; mirror its right poses.
  String walkAsset(WalkDirection direction, int frame) {
    if (frame < 0 || frame >= 4) {
      throw RangeError.range(frame, 0, 3, 'frame');
    }
    final side = direction == WalkDirection.left && this == TownResident.shiba
        ? WalkDirection.right : direction;
    final number = (frame + 1).toString().padLeft(2, '0');
    return 'assets/characters/$artFolder/walk_${side.name}_$number.png';
  }

  bool mirrorWalk(WalkDirection direction) =>
      this == TownResident.shiba && direction == WalkDirection.left;

  static TownResident fromId(String id) => values.firstWhere(
    (resident) => resident.id == id,
    orElse: () => throw FormatException('Unknown resident ID: $id'),
  );
}

class TownResidentAvatar extends StatelessWidget {
  const TownResidentAvatar({super.key, required this.resident, this.size = 80});
  final TownResident resident;
  final double size;
  @override
  Widget build(BuildContext context) => Image.asset(
    resident.idleAsset,
    width: size,
    height: size,
    fit: BoxFit.contain,
    excludeFromSemantics: true,
  );
}

/// Counts retain insertion order, so existing residents keep their town slots.
class ResidentCollection {
  ResidentCollection({
    required this.baselinePoints,
    required Map<String, int> counts,
    this.debugTicketsGranted = 0,
    this.bonusDraws = 0,
    this.expiredKotohogi = 0,
  }) : counts = Map.unmodifiable(counts);
  factory ResidentCollection.initial(int points) => ResidentCollection(
    baselinePoints: points,
    counts: const {'001_shiba': 1, '002_usagi': 1},
  );
  final int baselinePoints;
  final Map<String, int> counts;
  /// Extra test tickets, separate from mission-earned tickets.
  final int debugTicketsGranted;
  /// Free eleventh draws from ten-ticket bundles; not paid with tickets.
  final int bonusDraws;
  /// Credits forfeited because the balance would exceed 999.
  final int expiredKotohogi;
  List<TownResident> get owned => counts.keys.map(TownResident.fromId).toList();
  int get draws => counts.values.fold(0, (a, b) => a + b) - 2 - bonusDraws;
  /// Spendable kotohogi derived from the legacy ticket ledger.
  ///
  /// Each saved draw costs 30; previously earned partial amounts remain.
  /// No persistent schema migration or implicit currency conversion occurs.
  int availableKotohogi(int points) =>
      points - baselinePoints - expiredKotohogi +
      (debugTicketsGranted - draws) * 30;

  int earnedTickets(int points) =>
      (points - baselinePoints - expiredKotohogi) ~/ 30;
  int tickets(int points) => earnedTickets(points) + debugTicketsGranted - draws;
  int untilNextTicket(int points) =>
      30 - (points - baselinePoints - expiredKotohogi) % 30;

  /// Preserve lifetime contribution history while limiting unspent credits.
  ResidentCollection withKotohogiCap(int nextPoints) {
    final excess = availableKotohogi(nextPoints) - maxSpendableKotohogi;
    if (excess <= 0) return this;
    return ResidentCollection(
      baselinePoints: baselinePoints,
      counts: counts,
      debugTicketsGranted: debugTicketsGranted,
      bonusDraws: bonusDraws,
      expiredKotohogi: expiredKotohogi + excess,
    );
  }
  ResidentCollection acquire(TownResident resident, int points) {
    if (tickets(points) <= 0) {
      throw StateError('No resident tickets available.');
    }
    return ResidentCollection(
      baselinePoints: baselinePoints,
      counts: {...counts, resident.id: (counts[resident.id] ?? 0) + 1},
      debugTicketsGranted: debugTicketsGranted,
      bonusDraws: bonusDraws,
      expiredKotohogi: expiredKotohogi,
    );
  }

  /// Draw eleven residents using ten tickets, preserving the bonus across saves.
  ResidentCollection acquireTenPlusOne(List<TownResident> results, int points) {
    if (results.length != 11) throw ArgumentError.value(results.length, 'results');
    if (tickets(points) < 10) throw StateError('Not enough resident tickets.');
    final next = Map<String, int>.of(counts);
    for (final resident in results) {
      next[resident.id] = (next[resident.id] ?? 0) + 1;
    }
    return ResidentCollection(
      baselinePoints: baselinePoints,
      counts: next,
      debugTicketsGranted: debugTicketsGranted,
      bonusDraws: bonusDraws + 1,
      expiredKotohogi: expiredKotohogi,
    );
  }

  ResidentCollection grantTicketsForDebug(int amount) {
    if (amount <= 0) {
      throw ArgumentError.value(amount, 'amount', 'Must be positive.');
    }
    return ResidentCollection(
      baselinePoints: baselinePoints,
      counts: counts,
      debugTicketsGranted: debugTicketsGranted + amount,
      bonusDraws: bonusDraws,
      expiredKotohogi: expiredKotohogi,
    );
  }

  Map<String, Object> encode() => {
    'baselinePoints': baselinePoints,
    'counts': counts,
    if (debugTicketsGranted > 0) 'debugTicketsGranted': debugTicketsGranted,
    if (bonusDraws > 0) 'bonusDraws': bonusDraws,
    if (expiredKotohogi > 0) 'expiredKotohogi': expiredKotohogi,
  };
  static ResidentCollection decode(dynamic raw, int points) {
    if (raw is! Map<String, dynamic> ||
        raw.keys.toSet().difference({
          'baselinePoints', 'counts', 'debugTicketsGranted', 'bonusDraws',
          'expiredKotohogi',
        }).isNotEmpty ||
        raw.length != 2 +
            (raw.containsKey('debugTicketsGranted') ? 1 : 0) +
            (raw.containsKey('bonusDraws') ? 1 : 0) +
            (raw.containsKey('expiredKotohogi') ? 1 : 0) ||
        raw['baselinePoints'] is! int ||
        raw['counts'] is! Map<String, dynamic> ||
        (raw.containsKey('debugTicketsGranted') &&
            (raw['debugTicketsGranted'] is! int ||
                (raw['debugTicketsGranted'] as int) <= 0)) ||
        (raw.containsKey('bonusDraws') &&
            (raw['bonusDraws'] is! int ||
                (raw['bonusDraws'] as int) <= 0)) ||
        (raw.containsKey('expiredKotohogi') &&
            (raw['expiredKotohogi'] is! int ||
                (raw['expiredKotohogi'] as int) <= 0))) {
      throw const FormatException('Invalid resident collection schema.');
    }
    final baseline = raw['baselinePoints'] as int;
    final entries = raw['counts'] as Map<String, dynamic>;
    final extras = raw.containsKey('debugTicketsGranted')
        ? raw['debugTicketsGranted'] as int : 0;
    final free = raw.containsKey('bonusDraws') ? raw['bonusDraws'] as int : 0;
    final expired = raw.containsKey('expiredKotohogi')
        ? raw['expiredKotohogi'] as int
        : 0;
    if (expired > points - baseline || baseline < 0 ||
        baseline > points ||
        baseline % 10 != 0 ||
        entries.length > ownedResidentLimit ||
        !entries.containsKey('001_shiba') ||
        !entries.containsKey('002_usagi')) {
      throw const FormatException('Invalid resident collection values.');
    }
    final counts = <String, int>{};
    for (final entry in entries.entries) {
      TownResident.fromId(entry.key);
      if (entry.value is! int || entry.value < 1) {
        throw FormatException('Invalid resident count: ${entry.key}');
      }
      counts[entry.key] = entry.value as int;
    }
    final total = counts.values.fold<int>(0, (a, b) => a + b) - 2;
    if (free > total ~/ 11 || free > total || total < 0) {
      throw const FormatException('Invalid free draw count.');
    }
    final result = ResidentCollection(
      baselinePoints: baseline,
      counts: counts,
      debugTicketsGranted: extras,
      bonusDraws: free,
      expiredKotohogi: expired,
    );
    if (result.tickets(points) < 0) {
      throw const FormatException('Too many resident draws.');
    }
    return result;
  }
}
