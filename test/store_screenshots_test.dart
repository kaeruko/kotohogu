import 'package:flutter_test/flutter_test.dart';
import 'package:future_lift/store_screenshots.dart';
import 'package:future_lift/progress.dart';

void main() {
  test('screenshot pages map to actual four navigation destinations', () {
    expect(screenshotPageNames, ['home', 'missions', 'town', 'history']);
    for (var i = 0; i < screenshotPageNames.length; i++) {
      expect(screenshotPageIndex(screenshotPageNames[i]), i);
    }
    expect(() => screenshotPageIndex('developer'), throwsArgumentError);
    expect(() => screenshotPageIndex(null), throwsArgumentError);
  });

  test('sample capture content has believable missions and town residents', () {
    final snapshot = buildStoreScreenshotProgress(DateTime(2026, 10, 19, 12));
    expect(snapshot.day, '2026-10-19');
    expect(snapshot.lastCompletedDay, snapshot.day);
    expect(snapshot.points, greaterThanOrEqualTo(180));
    expect(snapshot.residents.owned.length, greaterThan(4));
    expect(snapshot.residents.availableKotohogi(snapshot.points), greaterThan(0));
    expect(snapshot.completed, containsAll([Mission.outside, Mission.food]));
    expect(snapshot.history.length, greaterThanOrEqualTo(3));
    expect(snapshot.seenDialogues, contains('tutorial_kotohogisu_v1'));
    expect(snapshot.townLevel, greaterThanOrEqualTo(2));
    final decoded = Progress.decode(snapshot.encode(), expectedVersion: 5);
    expect(decoded.points, snapshot.points);
    expect(decoded.residents.owned, snapshot.residents.owned);
    expect(decoded.history, snapshot.history);
  });
}
