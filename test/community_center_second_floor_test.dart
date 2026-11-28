import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:future_lift/community_center_room.dart';
import 'package:future_lift/community_center_second_floor.dart';
import 'package:future_lift/online_duel_page.dart';

void main() {
  test('second floor uses the renamed balcony artwork', () {
    expect(CommunityCenterSecondFloor.backgroundAsset,
        'assets/kotohogu/community_center_2f_background.png');
    expect(File(CommunityCenterSecondFloor.backgroundAsset).existsSync(), isTrue);
  });

  testWidgets('visit second floor, inspect rooms and return by stairs',
      (tester) async {
    tester.view.physicalSize = const Size(345, 742);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: CommunityCenterRoom()));
    Finder key(String value) => find.byKey(ValueKey(value));
    Future<void> tap(String value) async {
      await tester.tap(key(value));
      await tester.pumpAndSettle();
    }

    await tap('community-center-open-second-floor');
    expect(find.byType(CommunityCenterSecondFloor), findsOneWidget);
    expect(key('community-center-2f-background'), findsOneWidget);

    await tap('community-center-2f-meeting');
    expect(find.text('待ち合わせ広場'), findsOneWidget);
    expect(find.byType(OnlineDuelPage), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tap('community-center-2f-battle');
    expect(key('community-center-2f-open-online'), findsOneWidget);
    expect(key('community-center-2f-open-dojo'), findsOneWidget);
    await tester.tap(find.text('とじる'));
    await tester.pumpAndSettle();

    await tap('community-center-2f-ranking');
    expect(find.textContaining('オンラインランキングは準備中'), findsOneWidget);
    await tester.tap(find.text('とじる'));
    await tester.pumpAndSettle();

    await tap('community-center-2f-stairs');
    expect(find.byType(CommunityCenterSecondFloor), findsNothing);
    expect(key('community-center-background'), findsOneWidget);
    await tap('community-center-open-second-floor');
    await tap('community-center-2f-return');
    expect(find.byType(CommunityCenterSecondFloor), findsNothing);
    expect(key('community-center-background'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
