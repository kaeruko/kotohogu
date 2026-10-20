import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:future_lift/missions_screen.dart';
import 'package:future_lift/progress.dart';

void main() {
  testWidgets('mission header shows a walking Kotohogisu',
      (tester) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MissionsScreen(
            progress: Progress.empty(DateTime(2026, 10, 13)),
            busy: false,
            period: MissionPeriod.daily,
            onPeriodChanged: (_) {},
            onComplete: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final mascot = find.byKey(const ValueKey('mission-kotohogisu-sprite'));
    String asset() =>
        (tester.widget<Image>(mascot).image as AssetImage).assetName;

    expect(find.byKey(const ValueKey('mission-kotohogisu')), findsOneWidget);
    expect(find.text('セルフケア一覧'), findsWidgets);
    expect(asset(), 'assets/characters/013_kotohogisu/walk_right_01.png');

    final initialPosition = tester.getTopLeft(mascot);
    await tester.pump(const Duration(milliseconds: 190));
    expect(asset(), 'assets/characters/013_kotohogisu/walk_right_02.png');
    expect(tester.getTopLeft(mascot).dx, greaterThan(initialPosition.dx));

    for (var i = 0; i < 7; i++) {
      await tester.pump(const Duration(milliseconds: 190));
    }
    expect(asset(), startsWith('assets/characters/013_kotohogisu/walk_left_'));
    expect(find.byKey(const ValueKey('complete-strength')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('mission mascot stays still with reduced motion',
      (tester) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: MissionsScreen(
              progress: Progress.empty(DateTime(2026, 10, 13)),
              busy: false,
              period: MissionPeriod.daily,
              onPeriodChanged: (_) {},
              onComplete: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final mascot = find.byKey(const ValueKey('mission-kotohogisu-sprite'));
    String asset() =>
        (tester.widget<Image>(mascot).image as AssetImage).assetName;
    expect(asset(), 'assets/characters/013_kotohogisu/idle_front_01.png');
    final initialPosition = tester.getTopLeft(mascot);
    await tester.pump(const Duration(seconds: 3));
    expect(asset(), 'assets/characters/013_kotohogisu/idle_front_01.png');
    expect(tester.getTopLeft(mascot), initialPosition);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
