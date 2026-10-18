import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:future_lift/local_content_preview.dart';
import 'package:future_lift/resident_conversation_dialog.dart';

void main() {
  const frog = RemoteResident(
    id: '029_office_worker',
    label: 'かえる',
    artFolder: '029_office_worker',
    homeAreaId: 'plaza',
    profile: '',
  );
  final baseUri = localServerUri('http://10.0.2.2:8765');

  Future<void> openRemote(
    WidgetTester tester,
    String text, {
    double fontScale = 1,
  }) async {
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(fontScale),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(builder: (context) => TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (context) => RemoteVisitorConversationDialog(
              speaker: frog,
              dialogue: RemoteDialogue(
                'frog_remote', frog.id, text, 0, 0, false,
              ),
              baseUri: baseUri,
            ),
          ),
          child: const Text('配信会話を開く'),
        )),
      ),
    ));
    await tester.tap(find.text('配信会話を開く'));
    await tester.pumpAndSettle();
  }

  testWidgets('long CMS visitor speech is paginated without losing words',
      (tester) async {
    tester.view.physicalSize = const Size(330, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const text = 'このあいだ、一晩眠れなかったんだ……。'
        'そしたら次の日も「今日も眠れなかったらどうしよう」って'
        '不安になって、余計に眠れなくなっちゃった。\n\n'
        'でもね、「眠れない夜もあるよね」って思うようにしたら、'
        '少し気持ちが楽になったんだ。'
        '眠れないことより、眠れなかったらどうしようって考えるのが、'
        'つらかったのかもしれない……。';
    await openRemote(tester, text, fontScale: 1.2);

    expect(find.byType(RemoteVisitorConversationDialog), findsOneWidget);
    expect(find.text('配信テストの来訪者'), findsOneWidget);
    expect(find.text('かえる'), findsOneWidget);
    expect(find.byKey(const ValueKey('dialogue-page-count')), findsOneWidget);
    expect(find.text(text), findsNothing);
    expect(
      tester.widget<Text>(
        find.byKey(const ValueKey('dialogue-visible-line')),
      ).style!.fontSize, 20,
    );

    final seen = StringBuffer();
    final firstHeight = tester.getSize(find.byType(AlertDialog)).height;
    var advanced = 0;
    while (find.text('つぎへ').evaluate().isNotEmpty) {
      seen.write(tester.widget<Text>(
        find.byKey(const ValueKey('dialogue-visible-line')),
      ).data);
      await tester.tap(find.byKey(const ValueKey('dialogue-next-button')));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(AlertDialog)).height, firstHeight);
      advanced++;
      expect(advanced, lessThan(30));
    }
    expect(advanced, greaterThan(0));
    seen.write(tester.widget<Text>(
      find.byKey(const ValueKey('dialogue-visible-line')),
    ).data);
    expect(seen.toString(), text);
    await tester.tap(find.text('また話そう'));
    await tester.pumpAndSettle();
    expect(find.byType(RemoteVisitorConversationDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('short remote greeting remains one page', (tester) async {
    await openRemote(tester, 'こんにちは、かえるだよ！');
    expect(find.text('こんにちは、かえるだよ！'), findsOneWidget);
    expect(find.byKey(const ValueKey('dialogue-page-count')), findsNothing);
    expect(find.text('また話そう'), findsOneWidget);
    await tester.tap(find.text('また話そう'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
