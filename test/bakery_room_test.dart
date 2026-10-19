import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:future_lift/bakery_room.dart';
import 'package:future_lift/resident_collection.dart';
import 'package:future_lift/town_area_navigator.dart';
import 'package:future_lift/town_areas.dart';

void main() {
  testWidgets('ownership gates the doorway; owner can talk and return', (tester) async {
    tester.view.physicalSize = const Size(430, 930);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final spoken = <TownResident>[];
    Future<void> show(List<TownResident> owned) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(
        body: TownAreaNavigator(
          area: TownArea.shopping,
          onAreaChanged: (_) {},
          level: 3,
          lifetimePoints: 300,
          residents: owned,
          onBakeryResident: (resident) async { spoken.add(resident); },
        ),
      )));
      await tester.pump();
    }
    await show([TownResident.c035_beaty]);
    expect(find.byKey(const ValueKey('shopping-bakery-open-marker')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('shopping-bakery-entrance')));
    await tester.pump();
    expect(find.text('パティシエをガチャでお迎えすると、洋菓子店に入れるよ'), findsOneWidget);
    expect(find.byType(BakeryRoom), findsNothing);
    await show([TownResident.c047_patisie]);
    expect(find.byKey(const ValueKey('shopping-bakery-open-marker')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('shopping-bakery-open-marker')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('bakery-background')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('bakery-patissier')));
    await tester.pump();
    expect(spoken, [TownResident.c047_patisie]);
    await tester.tap(find.byKey(const ValueKey('bakery-return-shopping')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(BakeryRoom), findsNothing);
    expect(find.byKey(const ValueKey('shopping-bakery-entrance')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('shop fits a narrow phone and renders its supplied artwork', (tester) async {
    tester.view.physicalSize = const Size(430, 930);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final boundary = GlobalKey();
    await tester.pumpWidget(MaterialApp(home: RepaintBoundary(
      key: boundary, child: const BakeryRoom(ownedResidents: [TownResident.c047_patisie]),
    )));
    await tester.runAsync(() async {
      await precacheImage(const AssetImage(BakeryRoom.backgroundAsset), boundary.currentContext!);
      await precacheImage(AssetImage(TownResident.c047_patisie.idleAsset), boundary.currentContext!);
    });
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final image = await (boundary.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final output = File('build/bakery-preview.png');
      await output.parent.create(recursive: true);
      await output.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  });
}
