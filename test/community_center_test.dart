import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:future_lift/community_center_room.dart';
import 'package:future_lift/facility_layout.dart';
import 'package:future_lift/resident_collection.dart';
import 'package:future_lift/town_area_navigator.dart';
import 'package:future_lift/town_areas.dart';

void main() {
  test('community center opens at 240 earned points, not gacha ownership', () {
    expect(isCommunityCenterUnlocked(239), isFalse);
    expect(isCommunityCenterUnlocked(240), isTrue);
    expect(isCommunityCenterUnlocked(300), isTrue);
    expect(communityCenterResidents(),
        [TownResident.c031_kimono_fox, TownResident.c037_tora,
         TownResident.c051_dog_aunt, TownResident.shiba,
         TownResident.c042_senior_dog]);
    final flower = facilityPlacement('community_center', '031_kimono_fox');
    final exercise = facilityPlacement('community_center', '037_tora');
    final attendee = facilityPlacement('community_center', '051_dog_aunt');
    expect(attendee.y, greaterThan(exercise.y));
    expect(attendee.x + attendee.size, lessThanOrEqualTo(941));
    expect(facilityPlacement('community_center', '001_shiba').y,
        lessThan(flower.y));
    expect(facilityPlacement('community_center', '042_senior_dog').y,
        lessThan(exercise.y));
    expect(flower.x + flower.size, lessThan(exercise.x));
    expect(flower.y + flower.size, lessThan(1000));
    expect(exercise.y + exercise.size, lessThan(1000));
    expect(CommunityCenterRoom.backgroundAsset,
        'assets/kotohogu/community_center_background_001.png');
    expect(File(CommunityCenterRoom.backgroundAsset).existsSync(), isTrue);
  });

  testWidgets('shopping street only reveals community center when opened',
      (tester) async {
    tester.view.physicalSize = const Size(430, 930);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Widget app(int points) => MaterialApp(
      home: Scaffold(body: TownAreaNavigator(
        area: TownArea.shopping,
        onAreaChanged: (_) {},
        lifetimePoints: points,
        residents: const [],
      )),
    );
    const entry = ValueKey('shopping-community-center-entrance');
    await tester.pumpWidget(app(239));
    expect(find.byKey(entry), findsNothing);
    await tester.pumpWidget(app(240));
    expect(find.byKey(entry), findsOneWidget);
    await tester.tap(find.byKey(entry));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(CommunityCenterRoom), findsOneWidget);
    expect(find.byKey(const ValueKey('community-center-background')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('community-center-resident-031_kimono_fox')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('community-center-resident-037_tora')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('community-center-resident-051_dog_aunt')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('community-center-resident-001_shiba')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('community-center-resident-042_senior_dog')),
        findsOneWidget);
    await tester.tap(find.byKey(
        const ValueKey('community-center-return-shopping')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 650));
    await tester.pump();
    expect(find.byType(CommunityCenterRoom), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('instructors and attendees can be spoken to regardless of ownership',
      (tester) async {
    tester.view.physicalSize = const Size(430, 930);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final spoken = <TownResident>[];
    await tester.pumpWidget(MaterialApp(
      home: CommunityCenterRoom(onResident: (resident) async {
        spoken.add(resident);
      }),
    ));
    final flower = find.byKey(
        const ValueKey('community-center-resident-031_kimono_fox'));
    final exercise = find.byKey(
        const ValueKey('community-center-resident-037_tora'));
    expect(flower, findsOneWidget);
    final attendee = find.byKey(
        const ValueKey('community-center-resident-051_dog_aunt'));
    expect(exercise, findsOneWidget);
    expect(attendee, findsOneWidget);
    expect(tester.getRect(flower).overlaps(tester.getRect(exercise)), isFalse);
    expect(tester.getRect(exercise).center.dy,
        lessThan(tester.getRect(attendee).center.dy));
    await tester.tap(flower);
    await tester.pump();
    await tester.tap(exercise);
    await tester.pump();
    await tester.tap(attendee);
    await tester.pump();
    expect(spoken, [TownResident.c031_kimono_fox, TownResident.c037_tora,
      TownResident.c051_dog_aunt]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('community center animates only the exercise class',
      (tester) async {
    tester.view.physicalSize = const Size(430, 930);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    String displayedAsset(TownResident resident) {
      final image = tester.widget<Image>(find.descendant(
        of: find.byKey(
            ValueKey('community-center-resident-${resident.id}')),
        matching: find.byType(Image),
      ));
      return (image.image as AssetImage).assetName;
    }

    for (var frame = 1; frame <= 4; frame++) {
      final number = frame.toString().padLeft(2, '0');
      expect(
        File(
          '${CommunityCenterRoom.kneeExerciseSpriteFolder}/walk_front_$number.png',
        ).existsSync(),
        isTrue,
      );
    }

    await tester.pumpWidget(const MaterialApp(home: CommunityCenterRoom()));
    expect(
      displayedAsset(TownResident.c051_dog_aunt),
      '${CommunityCenterRoom.kneeExerciseSpriteFolder}/walk_front_01.png',
    );
    expect(
      displayedAsset(TownResident.c037_tora),
      TownResident.c037_tora.walkAsset(WalkDirection.front, 0),
    );
    expect(
      displayedAsset(TownResident.c031_kimono_fox),
      TownResident.c031_kimono_fox.idleAsset,
    );
    expect(
      displayedAsset(TownResident.shiba),
      TownResident.shiba.idleAsset,
    );
    await tester.pump(const Duration(milliseconds: 450));
    expect(
      displayedAsset(TownResident.c051_dog_aunt),
      '${CommunityCenterRoom.kneeExerciseSpriteFolder}/walk_front_02.png',
    );
    expect(
      displayedAsset(TownResident.c037_tora),
      TownResident.c037_tora.walkAsset(WalkDirection.front, 1),
    );

    // The system's reduced-motion preference disables both animations.
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData.fromView(tester.view).copyWith(
          disableAnimations: true,
        ),
        child: const CommunityCenterRoom(),
      ),
    ));
    expect(
      displayedAsset(TownResident.c051_dog_aunt),
      '${CommunityCenterRoom.kneeExerciseSpriteFolder}/idle_front_01.png',
    );
    expect(
      displayedAsset(TownResident.c037_tora),
      TownResident.c037_tora.idleAsset,
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(
      displayedAsset(TownResident.c051_dog_aunt),
      '${CommunityCenterRoom.kneeExerciseSpriteFolder}/idle_front_01.png',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('exercise animation pauses during a resident conversation',
      (tester) async {
    tester.view.physicalSize = const Size(430, 930);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final conversation = Completer<void>();
    await tester.pumpWidget(MaterialApp(
      home: CommunityCenterRoom(onResident: (resident) {
        expect(resident, TownResident.c051_dog_aunt);
        return conversation.future;
      }),
    ));
    final attendee = find.byKey(
      const ValueKey('community-center-resident-051_dog_aunt'),
    );
    String displayedAsset() {
      final image = tester.widget<Image>(find.descendant(
        of: attendee,
        matching: find.byType(Image),
      ));
      return (image.image as AssetImage).assetName;
    }

    expect(displayedAsset(), contains('walk_front_01.png'));
    await tester.tap(attendee);
    await tester.pump();
    expect(displayedAsset(), contains('idle_front_01.png'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(displayedAsset(), contains('idle_front_01.png'));

    conversation.complete();
    await tester.pump();
    expect(displayedAsset(), contains('/walk_front_'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
