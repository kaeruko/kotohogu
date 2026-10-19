import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:future_lift/game_home.dart';
import 'package:future_lift/home_skin.dart';
import 'package:future_lift/progress.dart';

void main() {
  for (final size in <Size>[const Size(360, 720), const Size(680, 950)]) {
    testWidgets('home shows matching nameplate beside points at ${size.width}',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final progress = Progress.empty(DateTime(2026, 10, 12));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GameHome(
              progress: progress,
              onMissions: () {},
              onTown: () {},
              onResident: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final profile = find.byKey(const ValueKey('gacha-player-nameplate'));
      final points = find.byKey(const ValueKey('kotohogi-bar-art'));
      expect(profile, findsOneWidget);
      expect(points, findsOneWidget);

      final image = tester.widget<Image>(profile);
      expect((image.image as AssetImage).assetName,
          'assets/kotohogi_hud/player_nameplate.png');
      expect(image.fit, BoxFit.contain);
      expect(find.text('今日も一歩ずつ'), findsNothing);
      expect(find.text('自分を言祝ごう'), findsNothing);
      expect(find.text('ハル'), findsOneWidget);
      expect(find.byKey(const ValueKey('player-display-name')), findsOneWidget);
      expect(tester.widget<Text>(
        find.byKey(const ValueKey('player-display-name')),
      ).maxLines, 1);
      expect(tester.widget<KotohogiBar>(find.byType(KotohogiBar)).points,
          progress.points);

      final nameRect = tester.getRect(profile);
      final pointRect = tester.getRect(points);
      expect(nameRect.right, lessThan(pointRect.left));
      expect((nameRect.width / nameRect.height), closeTo(788 / 209, .01));
      expect(find.text('FutureLift'), findsNothing);
      expect(find.text('みんなのまち'), findsNothing);
      final scenery = find.byKey(const ValueKey('open-town-scenery'));
      expect(scenery, findsOneWidget);
      expect(tester.getRect(scenery).top, greaterThan(nameRect.bottom));
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('tapping the scenery opens town without swallowing resident taps',
      (tester) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var townVisits = 0;
    var missionVisits = 0;
    var residentVisits = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GameHome(
          progress: Progress.empty(DateTime(2026, 10, 12)),
          onMissions: () => missionVisits++,
          onTown: () => townVisits++,
          onResident: (_) => residentVisits++,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('FutureLift'), findsNothing);
    expect(find.text('みんなのまち'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('open-town-scenery')));
    expect(townVisits, 1);
    expect(missionVisits, 0);
    expect(residentVisits, 0);

    await tester.tap(find.byKey(const ValueKey('home-resident-sprite-001_shiba')));
    expect(townVisits, 1);
    expect(residentVisits, 1);

    await tester.ensureVisible(find.byKey(const ValueKey('open-town')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-town')));
    expect(townVisits, 2);
    expect(missionVisits, 0);

    await tester.tap(find.byKey(const ValueKey('open-missions')));
    expect(missionVisits, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  // Regression: the home action cards and footer must be visible on the
  // first frame, without scrolling, on standard phone viewports.
  for (final screen in <Size>[
    const Size(320, 720),
    const Size(360, 720),
    const Size(402, 874),
  ]) {
    testWidgets('home first viewport contains both signs at $screen',
        (tester) async {
      tester.view.physicalSize = screen;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: GameHome(
                  progress: Progress.empty(DateTime(2026, 10, 12)),
                  onMissions: () {},
                  onTown: () {},
                  onResident: (_) {},
                ),
              ),
            ),
          ),
          bottomNavigationBar: const SizedBox(height: 104),
        ),
      ));
      await tester.pumpAndSettle();

      final viewport = tester.getRect(find.byType(ListView));
      final mission = tester.getRect(
        find.byKey(const ValueKey('open-missions')),
      );
      final town = tester.getRect(
        find.byKey(const ValueKey('open-town')),
      );
      final footer = tester.getRect(
        find.byKey(const ValueKey('home-footer-message')),
      );
      final resident = tester.getRect(
        find.byKey(const ValueKey('home-resident-sprite-001_shiba')),
      );

      expect(mission.top, greaterThan(resident.bottom));
      expect(town.top, greaterThan(resident.bottom));
      expect(mission.bottom, lessThan(footer.top));
      expect(town.bottom, lessThan(footer.top));
      expect(footer.bottom, lessThanOrEqualTo(viewport.bottom));
      expect(mission.top, greaterThanOrEqualTo(viewport.top));
      expect(town.top, greaterThanOrEqualTo(viewport.top));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  // The actual app wraps GameHome in SafeArea > Center > ConstrainedBox.
  // This supplies loose constraints, unlike a directly mounted Scaffold body.
  // Regression: without a non-positioned expanding child, both GameHome and
  // the fixed HUD measured width zero; the bottom signs then requested -29px.
  for (final screen in <Size>[
    const Size(280, 640),
    const Size(320, 720),
    const Size(360, 720),
    const Size(402, 874),
  ]) {
    testWidgets('home fits its actual centered app wrapper at $screen',
        (tester) async {
      tester.view.physicalSize = screen;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final progress = Progress.empty(DateTime(2026, 10, 12));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: GameHome(
                  progress: progress,
                  onMissions: () {},
                  onTown: () {},
                  onResident: (_) {},
                ),
              ),
            ),
          ),
          bottomNavigationBar: const SizedBox(height: 104),
        ),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final nameplate = find.byKey(const ValueKey('gacha-player-nameplate'));
      final points = find.byKey(const ValueKey('kotohogi-bar-art'));
      expect(nameplate, findsOneWidget);
      expect(points, findsOneWidget);
      expect(find.byKey(const ValueKey('home-header-ticket-counter')),
          findsNothing);
      expect(tester.getSize(nameplate).width, greaterThan(0));
      expect(tester.getSize(points).width,
          greaterThan(tester.getSize(nameplate).width));
      expect(find.byKey(const ValueKey('kotohogi-bar-label')), findsNothing);
      expect(find.byKey(const ValueKey('open-missions')), findsOneWidget);
      final leftRect = tester.getRect(find.byKey(const ValueKey('open-missions')));
      final rightRect = tester.getRect(find.byKey(const ValueKey('open-town')));
      expect(leftRect.width, greaterThan(0));
      expect(rightRect.width, greaterThan(0));
      expect(leftRect.right, lessThan(rightRect.left));
      expect(leftRect.left, greaterThanOrEqualTo(0));
      expect(rightRect.right, lessThanOrEqualTo(screen.width));
      await tester.drag(find.byType(ListView), const Offset(0, -250));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
