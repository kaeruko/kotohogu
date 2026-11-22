import 'oyasumi_club.dart';
import 'progress.dart';
import 'resident_collection.dart';
import 'town_areas.dart';

/// A change caused by this mission, not a list of all previously unlocked areas.
class CelebrationUpdate {
  const CelebrationUpdate({
    required this.id,
    required this.symbol,
    required this.title,
    required this.detail,
  });

  final String id;
  final String symbol;
  final String title;
  final String detail;
}

/// Compare the saved snapshot immediately before and after one successful
/// mission. Town unlocks use lifetime points, never the spendable gacha balance.
/// The club uses the same runtime stage resolver as the town, including the
/// published CMS chapter requirements. Merely earning points does not mark
/// any club dialogue as read.
List<CelebrationUpdate> celebrationUpdates({
  required Progress before,
  required Progress after,
  required Map<String, dynamic> clubConfig,
  required DateTime now,
}) {
  if (after.points < before.points) {
    throw StateError('Mission celebration cannot decrease lifetime points');
  }

  final updates = <CelebrationUpdate>[];
  for (final area in TownArea.values) {
    final wasOpen = area.isUnlocked(
      before.points,
      owned: before.residents.owned,
    );
    final isOpen = area.isUnlocked(
      after.points,
      owned: after.residents.owned,
    );
    if (!wasOpen && isOpen) {
      updates.add(CelebrationUpdate(
        id: 'area-${area.id}',
        symbol: '🗺️',
        title: '${area.label}が開放されました！',
        detail: 'ことほぎのまちで、新しい場所に行けるようになりました。',
      ));
    }
  }

  if (!isCommunityCenterUnlocked(before.points) &&
      isCommunityCenterUnlocked(after.points)) {
    updates.add(const CelebrationUpdate(
      id: 'community-center',
      symbol: '🏠',
      title: '公民館が開放されました！',
      detail: 'ことほぎ商店街から入れるようになりました。',
    ));
  }

  OyasumiScene scene(Progress progress) => OyasumiScene(
    config: clubConfig,
    saved: progress.oyasumi,
    owned: progress.residents.owned,
    now: now,
    earnedKotohogi: progress.points,
    seenDialogues: progress.seenDialogues,
    parkCleanerStarted: progress.seenDialogues.contains(
      OyasumiScene.parkCleanerUnlockId,
    ),
  );
  final previousClub = scene(before);
  final currentClub = scene(after);
  if (currentClub.owned.contains(OyasumiScene.host) &&
      currentClub.step > previousClub.step) {
    final stageLabel = currentClub.definition['label'] as String;
    updates.add(CelebrationUpdate(
      id: 'oyasumi-club',
      symbol: '🌙',
      title: 'おやすみクラブに新しいお話！',
      detail: '「$stageLabel」へ進めるようになりました。'
          '夜の中央ひろばで続きを見てみよう。',
    ));
  }

  return List<CelebrationUpdate>.unmodifiable(updates);
}
