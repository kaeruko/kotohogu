import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:future_lift/local_content_preview.dart';
import 'package:future_lift/resident_collection.dart';
import 'package:future_lift/town.dart';
import 'package:future_lift/town_areas.dart';
import 'package:future_lift/town_area_navigator.dart';

void main() {
  const visitor = RemoteResident(
    id: '038_owl', label: 'ふくろう', artFolder: '038_owl',
    homeAreaId: 'park', profile: '新しい友だち',
  );
  final base = localServerUri('http://10.0.2.2:8765');

  testWidgets('town places HTTP visitor beside owned residents', (tester) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var visitorTalks = 0;
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: Scaffold(body: TownScene(
        area: TownArea.plaza, lifetimePoints: 0,
        residents: const [TownResident.shiba],
        remoteVisitors: const [visitor], remoteContentBaseUri: base,
        onRemoteVisitor: (_) async { visitorTalks++; },
      )),
    ));
    await tester.pump();
    expect(find.byKey(const ValueKey('resident-0')), findsOneWidget);
    final remote = find.byKey(const ValueKey('remote-visitor-038_owl'));
    expect(remote, findsOneWidget);
    await tester.tap(remote);
    await tester.pump();
    expect(visitorTalks, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });


  testWidgets('two owned residents plus one visitor do not overrun the owned list',
      (tester) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: Scaffold(body: TownScene(
        area: TownArea.plaza, lifetimePoints: 0,
        residents: const [TownResident.shiba, TownResident.rabbit],
        remoteVisitors: const [visitor], remoteContentBaseUri: base,
      )),
    ));
    await tester.pump();
    expect(find.byKey(const ValueKey('resident-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('resident-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('resident-2')), findsNothing);
    expect(find.byKey(const ValueKey('remote-visitor-038_owl')), findsOneWidget);
    expect(find.byKey(const ValueKey('remote-visitor-sprite-038_owl')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('two visitors can occupy slots without any owned residents',
      (tester) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const second = RemoteResident(
      id: '039_fox', label: 'きつね', artFolder: '039_fox',
      homeAreaId: 'plaza', profile: '',
    );
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: Scaffold(body: TownScene(
        area: TownArea.plaza, lifetimePoints: 0,
        residents: const [],
        remoteVisitors: const [visitor, second], remoteContentBaseUri: base,
      )),
    ));
    await tester.pump();
    expect(find.byKey(const ValueKey('resident-0')), findsNothing);
    expect(find.byKey(const ValueKey('remote-visitor-038_owl')), findsOneWidget);
    expect(find.byKey(const ValueKey('remote-visitor-039_fox')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('navigator passes visitor into town scene', (tester) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: Scaffold(body: TownAreaNavigator(
        area: TownArea.plaza, onAreaChanged: (_) {},
        lifetimePoints: 0,
        residents: const [TownResident.shiba],
        remoteVisitors: const [visitor], remoteContentBaseUri: base,
      )),
    ));
    await tester.pump();
    expect(find.byKey(const ValueKey('remote-visitor-038_owl')),
        findsOneWidget);
    expect(tester.widget<TownScene>(find.byType(TownScene)).remoteVisitors,
        const [visitor]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('missing URL errors instead of falling back to assets',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: TownScene(
        area: TownArea.plaza, lifetimePoints: 0,
        residents: [], remoteVisitors: [visitor],
      )),
    ));
    expect(tester.takeException(), isA<StateError>());
    await tester.pumpWidget(const SizedBox());
  });
}
