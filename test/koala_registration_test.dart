import 'package:flutter_test/flutter_test.dart';
import 'package:future_lift/resident_collection.dart';

void main() {
  test('Koala is a registered gacha resident with sprite paths', () {
    const koala = TownResident.c049_koara;
    expect(TownResident.fromId('049_koara'), koala);
    expect(koala.label, 'コアラちゃん');
    expect(koala.artFolder, '049_koara');
    expect(koala.homeAreaId, 'park');
    expect(koala.walkInTown, isTrue);
    expect(koala.inGacha, isTrue);
    expect(TownResident.gachaPool, contains(koala));
    expect(koala.idleAsset, 'assets/characters/049_koara/idle_front_01.png');
    expect(koala.clapAssets, [
      'assets/characters/049_koara/clap_front_01.png',
      'assets/characters/049_koara/clap_front_02.png',
    ]);
    expect(koala.walkAsset(WalkDirection.right, 0),
        'assets/characters/049_koara/walk_right_01.png');
  });
}
