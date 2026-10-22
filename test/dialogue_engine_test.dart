import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:future_lift/dialogue_engine.dart';
import 'package:future_lift/progress.dart';
import 'package:future_lift/oyasumi_club.dart';
import 'package:future_lift/resident_collection.dart';

Map<String, Object> row(String id, String resident, String text, {
  int priority = 0,
  bool once = false,
  bool firstGreeting = false,
  String logic = 'all',
  List<Map<String, Object>> conditions = const [],
  Map<String, Object>? reply,
}) => {
  'id': id,
  'residentId': resident,
  'text': text,
  'priority': priority,
  'once': once,
  if (firstGreeting) 'firstGreeting': true,
  'logic': logic,
  'conditions': conditions,
  'reply': ?reply,
};

DialogueCatalog catalog(List<Map<String, Object>> additions) {
  final defaults = [
    for (final r in TownResident.values)
      row('${r.id}_default', r.id, '通常の雑談'),
  ];
  return DialogueCatalog.fromJson(jsonEncode({
    'version': 1,
    'dialogues': [...defaults, ...additions],
  }));
}

Progress completed(List<Mission> missions) {
  var p = Progress.empty(DateTime(2026, 10, 13));
  for (final mission in missions) {
    p = p.complete(mission);
  }
  return p;
}

// Inject boundary draws so selection tests remain deterministic.
class FixedRoll implements math.Random {
  const FixedRoll({this.last = true});
  final bool last;

  @override
  int nextInt(int max) {
    if (max <= 0) throw RangeError.value(max, 'max');
    return last ? max - 1 : 0;
  }

  @override
  bool nextBool() => throw UnimplementedError('Only nextInt is used');
  @override
  double nextDouble() => throw UnimplementedError('Only nextInt is used');
}

void main() {
  // rootBundle in an ordinary async test requires an initialized binding.
  // A widget test would run in fake async and leave this load pending.
  TestWidgetsFlutterBinding.ensureInitialized();
  test('bundled JSON loads and every character has an ordinary line', () async {
    final live = await DialogueCatalog.load();
    expect(live.entries.length, greaterThanOrEqualTo(24));
    final p = Progress.empty(DateTime(2026, 10, 13));
    for (final resident in TownResident.values) {
      expect(live.select(resident: resident, progress: p,
        now: DateTime.utc(2026, 10, 12, 15)), isA<DialogueEntry>());
    }
  });

  test('frog stops referring to Nailist as his girlfriend when club completes', () async {
    final live = await DialogueCatalog.load();
    const frog = TownResident.c029_office_worker;
    final now = DateTime.utc(2026, 10, 22);
    final before = Progress.empty(now);
    final during = before.withOyasumi(
      const OyasumiProgress(completed: 2, lastNight: '2026-10-21'));
    final after = before.withOyasumi(
      const OyasumiProgress(completed: 3, lastNight: '2026-10-22'));
    for (final progress in [before, during]) {
      expect(live.selectById(
        id: '029_office_worker_002', resident: frog,
        progress: progress, now: now).text, contains('つきあってる'));
    }
    expect(() => live.selectById(
      id: '029_office_worker_002', resident: frog,
      progress: after, now: now), throwsStateError);
    // No new breakup event or dialogue is required at the story threshold.
    expect(live.select(
      resident: frog, progress: after, now: now), isA<DialogueEntry>());
  });

  test('oyasumi club condition rejects malformed values', () {
    final bad = row('invalidClub', '001_shiba', 'test',
      conditions: [{'type': 'oyasumiClub', 'completed': 'yes'}]);
    expect(() => catalog([bad]), throwsFormatException);
  });

  test('Oshaberi-san has an introduction and same-day mission chatter', () async {
    final live = await DialogueCatalog.load();
    const resident = TownResident.c051_dog_aunt;
    final today = DateTime.utc(2026, 10, 21, 2);
    final nextDay = DateTime.utc(2026, 10, 22, 2);
    final progress = Progress.empty(DateTime(2026, 10, 21));
    final intro = live.select(resident: resident, progress: progress,
        now: today, random: const FixedRoll(last: false));
    expect(intro.id, '051_dog_aunt_001');
    expect(intro.firstGreeting, isTrue);

    final greeted = progress.markDialogueSeen(intro.id);
    expect(live.selectById(id: '051_dog_aunt_010',
        resident: resident, progress: greeted, now: today).once, isFalse);
    final missions = [
      (Mission.movement, '051_dog_aunt_017'),
      (Mission.conversation, '051_dog_aunt_018'),
      (Mission.monthlyCommunity, '051_dog_aunt_019'),
    ];
    for (final (mission, id) in missions) {
      expect(() => live.selectById(id: id, resident: resident,
          progress: greeted, now: today), throwsStateError);
      final completed = greeted.complete(mission);
      expect(live.selectById(id: id, resident: resident,
          progress: completed, now: today).id, id);
      expect(() => live.selectById(id: id, resident: resident,
          progress: completed, now: nextDay), throwsStateError);
    }
  });

  test('patissier calls his wife およめちゃん in their joint dialogue',
      () async {
    final catalog = await DialogueCatalog.load();
    final conversation = catalog.entries.singleWhere(
      (entry) => entry.id == '047_patisie_019',
    );
    expect(conversation.residentId, TownResident.c047_patisie.id);
    expect(conversation.text, startsWith('およめちゃん、家計のことも'));
    expect(conversation.reply?.residentId, TownResident.rabbit.id);
  });

  test('designated introductions always come before one-time stories', () {
    final c = catalog([
      row('intro', '001_shiba', 'はじめまして！',
          once: true, firstGreeting: true, priority: 0),
      row('special', '001_shiba', 'ミッションおめでとう',
          once: true, priority: 900),
      row('tip', '001_shiba', '普段のお話', priority: 500),
    ]);
    final now = DateTime.utc(2026, 10, 13);
    final progress = completed([]);
    for (final roll in [const FixedRoll(last: false), const FixedRoll()]) {
      expect(c.select(resident: TownResident.shiba,
          progress: progress, now: now, random: roll).id, 'intro');
    }
    final greeted = progress.markDialogueSeen('intro');
    expect(c.select(resident: TownResident.shiba, progress: greeted,
        now: now, random: const FixedRoll()).id, 'special');
    final seenBoth = greeted.markDialogueSeen('special');
    expect(c.select(resident: TownResident.shiba, progress: seenBoth,
        now: now, random: const FixedRoll()).id, 'tip');
  });

  test('invalid or duplicate first introductions are rejected', () {
    expect(() => catalog([
      row('first1', '001_shiba', '初回1', once: true, firstGreeting: true),
      row('first2', '001_shiba', '初回2', once: true, firstGreeting: true),
    ]), throwsFormatException);
    expect(() => catalog([
      row('bad', '001_shiba', '何度も出る初対面', firstGreeting: true),
    ]), throwsFormatException);
    expect(() => catalog([
      row('bad', '001_shiba', '条件つき初対面',
          once: true, firstGreeting: true,
          conditions: [{'type': 'mission', 'missionId': 'all', 'minCount': 1}]),
    ]), throwsFormatException);
  });

  test('bundled first introductions are available once for every resident', () async {
    final live = await DialogueCatalog.load();
    final p = completed([]);
    for (final resident in TownResident.values) {
      final selected = live.select(
        resident: resident, progress: p, now: DateTime.utc(2026, 10, 18),
        random: const FixedRoll(last: false),
      );
      expect(selected.firstGreeting, isTrue, reason: resident.id);
      expect(selected.once, isTrue);
      final seen = p.markDialogueSeen(selected.id);
      expect(live.select(resident: resident, progress: seen,
          now: DateTime.utc(2026, 10, 18)).id, isNot(selected.id));
    }
  });

  test('carpenter keeps stable ID and greets before his two-part story', () async {
    const carpenter = TownResident.bear;
    expect(carpenter.id, '006_kuma');
    expect(carpenter.label, 'だいくさん');
    expect(carpenter.profile, contains('大工'));
    expect(TownResident.c032_miner.profile, contains('土木工事'));
    final catalog = await DialogueCatalog.load();
    final now = DateTime.utc(2026, 10, 19, 2);
    var progress = Progress.empty(DateTime(2026, 10, 19));
    DialogueEntry next() => catalog.select(
      resident: carpenter, progress: progress, now: now,
      random: const FixedRoll(last: false),
    );
    expect(next().id, '006_kuma_001');
    progress = progress.markDialogueSeen('006_kuma_001');
    expect(next().id, '006_kuma_004');
    progress = progress.markDialogueSeen('006_kuma_004');
    expect(next().id, '006_kuma_005');
    progress = progress.markDialogueSeen('006_kuma_005');
    expect(next().once, isFalse);
    final restored = Progress.decode(progress.encode(), expectedVersion: 5);
    expect(catalog.select(
      resident: carpenter, progress: restored, now: now,
      random: const FixedRoll(last: false),
    ).once, isFalse);
  });

  test('carpenter and Moguta talk only when both are in the same scene', () async {
    final catalog = await DialogueCatalog.load();
    final now = DateTime.utc(2026, 10, 19, 2);
    final progress = Progress.empty(DateTime(2026, 10, 19));
    DialogueEntry paired(Set<String> residents) => catalog.selectById(
      id: '006_kuma_008', resident: TownResident.bear,
      progress: progress, now: now, townResidentIds: residents,
    );
    expect(() => paired({}), throwsStateError);
    expect(() => paired({'006_kuma'}), throwsStateError);
    expect(() => paired({'032_miner'}), throwsStateError);
    final line = paired({'006_kuma', '032_miner'});
    expect(line.reply?.residentId, '032_miner');
    expect(line.reply?.text, contains('一緒に公園'));
  });

  test('carpenter mission celebrations appear only that day and once', () async {
    final catalog = await DialogueCatalog.load();
    const carpenter = TownResident.bear;
    final today = DateTime.utc(2026, 10, 19, 2);
    final tomorrow = DateTime.utc(2026, 10, 19, 15);
    var progress = Progress.empty(DateTime(2026, 10, 19))
      .markDialogueSeen('006_kuma_001')
      .markDialogueSeen('006_kuma_004')
      .markDialogueSeen('006_kuma_005');
    DialogueEntry select(String id, DateTime now) => catalog.selectById(
      id: id, resident: carpenter, progress: progress, now: now,
    );
    for (final id in ['006_kuma_009', '006_kuma_010', '006_kuma_011']) {
      expect(() => select(id, today), throwsStateError);
    }
    progress = progress.complete(Mission.strength);
    expect(catalog.select(
      resident: carpenter, progress: progress, now: today,
      random: const FixedRoll(last: false),
    ).id, '006_kuma_009');
    expect(select('006_kuma_009', today).once, isTrue);
    expect(() => select('006_kuma_009', tomorrow), throwsStateError);
    progress = progress.markDialogueSeen('006_kuma_009');
    expect(() => select('006_kuma_009', today), throwsStateError);
    progress = progress.complete(Mission.sittingBreak).complete(Mission.hobby);
    expect(select('006_kuma_010', today).once, isTrue);
    expect(select('006_kuma_011', today).once, isTrue);
    expect(() => select('006_kuma_010', tomorrow), throwsStateError);
    expect(() => select('006_kuma_011', tomorrow), throwsStateError);
  });

  test('Merry keeps her first greeting and celebrates only on completion day', () async {
    final live = await DialogueCatalog.load();
    const merry = TownResident.c007_hitsuji;
    final firstMeeting = Progress.empty(DateTime(2026, 10, 19));
    final today = DateTime.utc(2026, 10, 19, 2);
    final tomorrow = DateTime.utc(2026, 10, 19, 15);
    final intro = live.select(
      resident: merry, progress: firstMeeting, now: today,
      random: const FixedRoll(last: false),
    );
    expect(intro.id, '007_hitsuji_002');
    expect(intro.firstGreeting, isTrue);

    DialogueEntry byId(String id, Progress progress, DateTime now) =>
      live.selectById(id: id, resident: merry, progress: progress, now: now);
    var progress = firstMeeting.markDialogueSeen(intro.id);
    for (var number = 3; number <= 7; number++) {
      final id = '007_hitsuji_${number.toString().padLeft(3, '0')}';
      expect(byId(id, progress, today).once, isFalse, reason: id);
    }
    for (final id in ['007_hitsuji_008', '007_hitsuji_009', '007_hitsuji_010']) {
      expect(() => byId(id, progress, today), throwsStateError,
          reason: 'No mission completed yet: $id');
    }

    progress = progress.complete(Mission.outside);
    expect(live.select(
      resident: merry, progress: progress, now: today,
      random: const FixedRoll(last: false),
    ).id, '007_hitsuji_008');
    expect(byId('007_hitsuji_008', progress, today).once, isTrue);
    expect(() => byId('007_hitsuji_008', progress, tomorrow), throwsStateError);
    progress = progress.markDialogueSeen('007_hitsuji_008');
    expect(() => byId('007_hitsuji_008', progress, today), throwsStateError);

    progress = progress.complete(Mission.hobby).complete(Mission.conversation);
    expect(byId('007_hitsuji_009', progress, today).once, isTrue);
    expect(byId('007_hitsuji_010', progress, today).once, isTrue);
    expect(() => byId('007_hitsuji_009', progress, tomorrow), throwsStateError);
    expect(() => byId('007_hitsuji_010', progress, tomorrow), throwsStateError);
    // Celebration content is editable CMS data, and the save format is unchanged.
    final restored = Progress.decode(progress.encode(), expectedVersion: 5);
    expect(byId('007_hitsuji_009', restored, today).id, '007_hitsuji_009');
  });

  test('guide rumors react to salon ownership, not dialogue history', () async {
    final live = await DialogueCatalog.load();
    final now = DateTime.utc(2026, 10, 19);
    final before = Progress.empty(now).markDialogueSeen('035_beaty_001');
    DialogueEntry pick(String id, Progress progress) => live.selectById(
      id: id, resident: TownResident.penguin, progress: progress, now: now);
    expect(pick('003_penguin_002', before).id, '003_penguin_002');
    expect(() => pick('003_penguin_003', before), throwsStateError);
    expect(() => pick('003_penguin_004', before), throwsStateError);

    final after = before.grantTicketsForDebug(1)
        .acquireResident(TownResident.c035_beaty);
    expect(() => pick('003_penguin_002', after), throwsStateError);
    expect(pick('003_penguin_003', after).id, '003_penguin_003');
    expect(pick('003_penguin_004', after).id, '003_penguin_004');
    expect(() => pick('003_penguin_009', after), throwsStateError);
    expect(() => pick('003_penguin_010', after), throwsStateError);

    final withArtist = after.grantTicketsForDebug(1)
        .acquireResident(TownResident.c034_artist);
    expect(pick('003_penguin_009', withArtist).id, '003_penguin_009');
    expect(pick('003_penguin_010',
        withArtist.markDialogueSeen('041_pig_middle_033')).id,
        '003_penguin_010');
  });

  test('ownership condition rejects unknown resident and nonbool status', () {
    for (final fields in [
      <String, Object>{'type':'residentOwned','residentId':'unknown','owned':true},
      <String, Object>{'type':'residentOwned','residentId':'035_beaty','owned':'yes'},
    ]) {
      expect(() => catalog([
        row('bad_owner', '003_penguin', '不正な所持条件',
            conditions: [fields]),
      ]), throwsFormatException);
    }
  });

  test('weighted repeatable selection includes greetings and allows repeats', () {
    final c = catalog([row('tip', '001_shiba', '豆知識', priority: 20)]);
    final p = completed([]);
    DialogueEntry pick(math.Random random) => c.select(
      resident: TownResident.shiba, progress: p,
      now: DateTime.utc(2026, 10, 13), random: random,
    );
    expect(pick(const FixedRoll(last: false)).id, '001_shiba_default');
    expect(pick(const FixedRoll()).id, 'tip');
    // There is no consecutive-repeat exclusion.
    expect(pick(const FixedRoll()).id, 'tip');
  });

  test('one-time stories precede random everyday lines in reading order', () {
    final c = catalog([
      row('first', '001_shiba', '第一話', priority: 35, once: true),
      row('second', '001_shiba', '第二話', priority: 36, once: true,
        conditions: [{'type': 'seenDialogue', 'dialogueId': 'first'}]),
      row('tip', '001_shiba', '豆知識', priority: 100),
    ]);
    final now = DateTime.utc(2026, 10, 13);
    var p = completed([]);
    DialogueEntry pick(math.Random random) => c.select(
      resident: TownResident.shiba, progress: p, now: now, random: random,
    );
    expect(pick(const FixedRoll(last: false)).id, 'first');
    p = p.markDialogueSeen('first');
    expect(pick(const FixedRoll(last: false)).id, 'second');
    p = p.markDialogueSeen('second');
    expect(pick(const FixedRoll(last: false)).id, '001_shiba_default');
    expect(pick(const FixedRoll()).id, 'tip');
  });

  test('facility-only dialogue is excluded from everyday draws', () {
    final c = catalog([
      row('facility', '001_shiba', '施設会話', priority: -1000),
    ]);
    final p = completed([]);
    final now = DateTime.utc(2026, 10, 13);
    for (final random in [const FixedRoll(last: false), const FixedRoll()]) {
      expect(c.select(resident: TownResident.shiba,
        progress: p, now: now, random: random).id, '001_shiba_default');
    }
    expect(c.selectById(id: 'facility', resident: TownResident.shiba,
      progress: p, now: now).id, 'facility');
  });

  test('explicit facility dialogue respects owner, conditions and once', () {
    final c = catalog([
      row('counter', '041_pig_middle', 'いらっしゃいませ',
          conditions: [
            {'type': 'seenDialogue', 'dialogueId': 'story'},
          ]),
      row('story', '041_pig_middle', 'お店を始めよう', once: true),
      row('limited', '041_pig_middle', '一度だけ', once: true),
    ]);
    final now = DateTime.utc(2026, 10, 17);
    final initial = completed([]);
    DialogueEntry pick(String id, Progress p,
        {TownResident resident = TownResident.c041_pig_middle}) =>
      c.selectById(id: id, resident: resident, progress: p, now: now);
    expect(() => pick('counter', initial), throwsStateError);
    final afterStory = initial.markDialogueSeen('story');
    expect(pick('counter', afterStory).text, 'いらっしゃいませ');
    expect(() => pick('counter', afterStory,
        resident: TownResident.shiba), throwsStateError);
    expect(() => pick('missing', afterStory), throwsStateError);
    expect(pick('limited', initial).id, 'limited');
    expect(() => pick('limited', initial.markDialogueSeen('limited')),
        throwsStateError);
  });

  test('annual range, new year wrap, weekday, and exact date use JST', () {
    final conditions = [
      {'type':'date', 'mode':'annual_range','start':'12-20','end':'01-05'},
    ];
    final c = catalog([
      row('winter', '001_shiba', '冬だね', priority: 10, conditions: conditions),
      row('weekday', '002_usagi', '月曜日', priority: 10, conditions: [
        {'type':'date', 'mode':'weekday','days':[1]},
      ]),
      row('one_day', '003_penguin', '今日だけ', priority: 10, conditions: [
        {'type':'date', 'mode':'exact','date':'2026-12-25'},
      ]),
    ]);
    final p = completed([]);
    DialogueEntry pick(TownResident r, DateTime utc) =>
      c.select(resident:r,progress:p,now:utc,random:const FixedRoll());
    expect(pick(TownResident.shiba,DateTime.utc(2026,12,24,15)).id, 'winter');
    expect(pick(TownResident.shiba,DateTime.utc(2027,1,4,15)).id, 'winter');
    expect(pick(TownResident.shiba,DateTime.utc(2027,1,6,15)).text, '通常の雑談');
    expect(pick(TownResident.rabbit,DateTime.utc(2026,10,11,15)).id,'weekday');
    expect(pick(TownResident.rabbit,DateTime.utc(2026,10,12,15)).text,'通常の雑談');
    expect(pick(TownResident.penguin,DateTime.utc(2026,12,24,15)).id,'one_day');
    expect(pick(TownResident.penguin,DateTime.utc(2026,12,25,15)).text,'通常の雑談');
  });

  test('AND/OR mission conditions, priorities and once shown persistence', () {
    final c=catalog([
      row('and','001_shiba','散歩と学び',priority:20,once:true,conditions:[
        {'type':'mission','missionId':'outside','minCount':1},
        {'type':'mission','missionId':'hobby','minCount':1},
      ]),
      row('or','001_shiba','どちらか達成',priority:10,logic:'any',conditions:[
        {'type':'mission','missionId':'outside','minCount':1},
        {'type':'kotohogi','min':100},
      ]),
    ]);
    const date = '2026-10-13';
    expect(date, isNotEmpty);
    final now=DateTime.utc(2026,10,12,15);
    var p=completed([Mission.outside]);
    expect(c.select(resident:TownResident.shiba,progress:p,now:now,random:const FixedRoll()).id,'or');
    p=p.complete(Mission.hobby);
    expect(c.select(resident:TownResident.shiba,progress:p,now:now,random:const FixedRoll()).id,'and');
    p=p.markDialogueSeen('and');
    expect(c.select(resident:TownResident.shiba,progress:p,now:now,random:const FixedRoll()).id,'or');
    final restored=Progress.decode(p.encode(), expectedVersion:5);
    expect(restored.seenDialogues,contains('and'));
    expect(restored.countFor('outside'),1);
  });

  test('mission celebration is valid on the completion day only in JST', () {
    final c = catalog([
      row('today_sitting', '001_shiba', '今日ひと休みしたね',
        priority: 20, once: true,
        conditions: [
          {'type': 'mission', 'missionId': 'sittingBreak',
            'minCount': 1, 'withinDays': 1},
        ]),
    ]);
    DialogueEntry pick(Progress p, DateTime now) =>
        c.select(resident: TownResident.shiba, progress: p, now: now);
    final oct13Morning = DateTime.utc(2026, 10, 13, 0);
    final oct13Late = DateTime.utc(2026, 10, 13, 14, 59);
    final oct14Midnight = DateTime.utc(2026, 10, 13, 15);
    var p = completed([]);
    expect(pick(p, oct13Morning).text, '通常の雑談');
    p = p.complete(Mission.sittingBreak);
    expect(pick(p, oct13Morning).id, 'today_sitting');
    expect(pick(Progress.decode(p.encode(), expectedVersion: 5),
        oct13Late).id, 'today_sitting');
    expect(pick(p, oct14Midnight).text, '通常の雑談');
    expect(pick(p.clearHistory(), oct13Morning).text, '通常の雑談');
    expect(pick(p.markDialogueSeen('today_sitting'), oct13Morning).text,
        '通常の雑談');
  });

  test('two residents visible in town unlock a paired conversation', () {
    final c = catalog([
      row('friends', '001_shiba', '雲を見てみようよ', priority: 20,
        conditions: [
          {'type':'townTogether', 'otherResidentId':'002_usagi'},
        ],
        reply: {'residentId':'002_usagi', 'text':'あの雲、描いてみたい！'}),
    ]);
    final now = DateTime.utc(2026, 10, 15, 0);
    final progress = completed([]);
    DialogueEntry pick(Set<String> town) =>
        c.select(resident: TownResident.shiba, progress: progress,
          now: now, townResidentIds: town, random: const FixedRoll());
    expect(pick({}).text, '通常の雑談');
    expect(pick({'001_shiba'}).text, '通常の雑談');
    expect(pick({'002_usagi'}).text, '通常の雑談');
    final selected = pick({'001_shiba', '002_usagi'});
    expect(selected.id, 'friends');
    expect(selected.reply?.residentId, '002_usagi');
    expect(selected.reply?.text, 'あの雲、描いてみたい！');
  });

  test('bundled farmer and daydreamer conversation wins when together', () {
    // Inspect the actual checked-in fixture directly, without widget clock
    // or asynchronous bundle loading.
    final live = DialogueCatalog.fromJson(
      File('assets/dialogues/dialogues.json').readAsStringSync(),
    );
    // First meeting has already happened; verify subsequent companionship.
    final progress = Progress.empty(DateTime(2026, 10, 15))
        .markDialogueSeen('026_farmer_003');
    final now = DateTime.utc(2026, 10, 15, 0);
    DialogueEntry pick(Set<String> town) => live.select(
      resident: TownResident.c026_farmer,
      progress: progress,
      now: now,
      townResidentIds: town,
      random: const FixedRoll(),
    );

    expect(pick({'026_farmer'}).id, '026_farmer_001');
    expect(pick({'027_daydreamer'}).id, '026_farmer_001');

    final together = pick({'026_farmer', '027_daydreamer'});
    expect(together.id, '026_farmer_002');
    expect(together.text, 'おやすみくん。農業をやらんかね。');
    expect(together.reply?.residentId, '027_daydreamer');
    expect(together.reply?.text, 'もふ？おひるねできる？');
  });

  test('town companion works with AND/OR and enforces speaker presence', () {
    final c = catalog([
      row('pair_or_date', '001_shiba', '特別な会話', priority: 20,
        logic: 'any', conditions: [
          {'type':'townTogether','otherResidentId':'002_usagi'},
          {'type':'date','mode':'exact','date':'2026-12-25'},
        ]),
    ]);
    final progress = completed([]);
    final jstChristmas = DateTime.utc(2026, 12, 24, 15);
    expect(c.select(resident: TownResident.shiba, progress: progress,
      now: DateTime.utc(2026, 10, 15), townResidentIds: {'001_shiba'}).text,
      '通常の雑談');
    expect(c.select(resident: TownResident.shiba, progress: progress,
      now: jstChristmas, townResidentIds: {}, random: const FixedRoll()).id, 'pair_or_date');
  });

  test('invalid town pair and reply definitions fail fast', () {
    final valid = {'type':'townTogether','otherResidentId':'002_usagi'};
    for (final invalid in [
      {'type':'townTogether','otherResidentId':'unknown'},
      {'type':'townTogether','otherResidentId':'001_shiba'},
      {'type':'townTogether','otherResidentId':42},
    ]) {
      expect(() => catalog([
        row('bad_pair','001_shiba','無効',conditions:[invalid]),
      ]), throwsFormatException, reason: invalid.toString());
    }
    for (final entry in [
      row('bad_reply','001_shiba','無効',
        reply: {'residentId':'002_usagi','text':'こんにちは'}),
      row('bad_or','001_shiba','無効',logic:'any',
        conditions:[valid], reply:{'residentId':'002_usagi','text':'こんにちは'}),
      row('wrong_partner','001_shiba','無効',
        conditions:[valid], reply:{'residentId':'003_penguin','text':'こんにちは'}),
      row('blank_reply','001_shiba','無効',
        conditions:[valid], reply:{'residentId':'002_usagi','text':' '}),
    ]) {
      expect(() => catalog([entry]), throwsFormatException,
        reason: entry.toString());
    }
  });

  test('a seen dialogue from a different character unlocks a two-person conversation', () {
    final c = catalog([
      row('001_shiba_997', '001_shiba', '前のお話', priority: 10),
      row('003_penguin_998', '003_penguin', '続きのお話', priority: 20,
        conditions: [
          {'type': 'seenDialogue', 'dialogueId': '001_shiba_997'},
          {'type': 'townTogether', 'otherResidentId': '004_neko'},
        ], reply: {'residentId': '004_neko', 'text': '聞かせて！'}),
    ]);
    final now = DateTime.utc(2026, 10, 15, 0);
    final before = completed([]);
    final visible = <String>{'003_penguin', '004_neko'};
    expect(c.select(resident: TownResident.penguin,
      progress: before, now: now, townResidentIds: visible).text, '通常の雑談');

    // The trigger is not an "only once" dialogue; its read state is durable.
    final restored = Progress.decode(
      before.markDialogueSeen('001_shiba_997').encode(), expectedVersion: 5);
    expect(restored.seenDialogues, contains('001_shiba_997'));
    final followup = c.select(resident: TownResident.penguin,
      progress: restored, now: now, townResidentIds: visible,
      random: const FixedRoll());
    expect(followup.id, '003_penguin_998');
    expect(followup.reply?.text, '聞かせて！');
    expect(c.select(resident: TownResident.penguin,
      progress: restored, now: now, townResidentIds: {'003_penguin'}).text,
      '通常の雑談');
  });

  test('invalid global seen-dialogue references fail fast', () {
    final before = row('001_shiba_997', '001_shiba', '前のお話');
    for (final reference in ['missing', '003_penguin_998', 10, '']) {
      expect(() => catalog([
        before,
        row('003_penguin_998', '003_penguin', '次の話', conditions: [
          {'type': 'seenDialogue', 'dialogueId': reference},
        ]),
      ]), throwsFormatException, reason: reference.toString());
    }
    expect(() => catalog([
      row('bad', '001_shiba', '参照先がない', conditions: [
        {'type': 'seenDialogue'},
      ]),
    ]), throwsFormatException);
  });

  test('mission counters survive journal deletion, rollovers and debug resets', () {
    var p=completed([Mission.outside, Mission.hobby]);
    p=p.clearHistory().onDay(DateTime(2026,10,14)).complete(Mission.outside);
    expect(p.countFor('outside'),2);
    expect(p.countFor('all'),3);
    expect(p.history.length,1);
    final restored=Progress.decode(p.encode(), expectedVersion:5);
    expect(restored.countFor('outside'),2);
    expect(restored.resetMissionsForDebug().countFor('outside'),2);
    expect(restored.markDialogueSeen('hello').seenDialogues,contains('hello'));
  });

  test('legacy data migrates observed counts only, without inventing history', () {
    final original = completed([Mission.outside, Mission.hobby]);
    final raw=jsonDecode(original.encode()) as Map<String,dynamic>;
    raw['version']=4;
    raw.remove('missionCounts');
    raw.remove('seenDialogues');
    raw.remove('playerName');
    final old=Progress.decode(jsonEncode(raw),expectedVersion:4);
    expect(old.countFor('outside'),1);
    expect(old.countFor('hobby'),1);
    expect(old.countFor('all'),2);

    final cleared=Map<String,dynamic>.of(raw);
    cleared['history']={};
    // Current period completion flags remain consistent with a cleared journal.
    final migrated=Progress.decode(jsonEncode(cleared),expectedVersion:4);
    expect(migrated.countFor('outside'),0);
    expect(migrated.countFor('all'),2);
    expect(Progress.decode(migrated.encode()).countFor('outside'),0);
  });

  test('invalid catalogs and save counters fail instead of silently falling back', () {
    expect(() => DialogueCatalog.fromJson('{"version":1,"dialogues":[]}' ),
      throwsFormatException);
    final root=jsonDecode(jsonEncode({
      'version':1,
      'dialogues':[for(final r in TownResident.values)
        row('${r.id}_default',r.id,'普通')],
    })) as Map<String,dynamic>;
    for(final invalid in [
      {'type':'date','mode':'exact','date':'2026-02-30'},
      {'type':'date','mode':'annual_range','start':'00-01','end':'04-10'},
      {'type':'date','mode':'weekday','days':[0]},
      {'type':'mission','missionId':'unknown','minCount':3},
      {'type':'mission','missionId':'outside','minCount':1,'withinDays':0},
      {'type':'mission','missionId':'outside','minCount':1,'withinDays':2},
      {'type':'mission','missionId':'outside','minCount':1,'withinDays':3},
      {'type':'mission','missionId':'outside','minCount':1,'withinDays':true},
      {'type':'mission','missionId':'outside','minCount':1,'withinDays':'3'},
      {'type':'kotohogi','min':-1},
    ]) {
      final changed=jsonDecode(jsonEncode(root)) as Map<String,dynamic>;
      final entries=changed['dialogues'] as List;
      (entries[0] as Map<String,dynamic>)['conditions']=[invalid];
      expect(()=>DialogueCatalog.fromJson(jsonEncode(changed)),throwsFormatException,
        reason:invalid.toString());
    }
    final base=jsonDecode(completed([Mission.outside]).encode()) as Map<String,dynamic>;
    for(final counts in [
      {'outside':2},
      {'unknown':1},
      {'outside':-1},
      {'outside':1.2},
    ]) {
      expect(()=>Progress.decode(jsonEncode({...base,'missionCounts':counts})),
        throwsFormatException,reason:counts.toString());
    }
    expect(()=>Progress.decode(jsonEncode({...base,'seenDialogues':['a','a']})),
      throwsFormatException);
  });
}
