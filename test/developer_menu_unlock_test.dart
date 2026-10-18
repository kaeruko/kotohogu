import 'package:flutter_test/flutter_test.dart';
import 'package:future_lift/dev_tools.dart';

void main() {
  test('seven quick history taps unlock developer menu', () {
    final sequence = DeveloperMenuUnlockSequence();
    final start = DateTime(2026, 10, 19);
    for (var tap = 0; tap < 6; tap++) {
      expect(sequence.registerHistoryTap(
        start.add(Duration(milliseconds: 700 * tap)),
      ), isFalse);
    }
    expect(sequence.registerHistoryTap(start.add(
      const Duration(milliseconds: 4200),
    )), isTrue);
  });

  test('a long pause or leaving History resets the gesture', () {
    final sequence = DeveloperMenuUnlockSequence();
    final start = DateTime(2026, 10, 19);
    for (var tap = 0; tap < 6; tap++) {
      expect(sequence.registerHistoryTap(
        start.add(Duration(milliseconds: 500 * tap)),
      ), isFalse);
    }

    // More than eight seconds after the last tap starts a new sequence.
    expect(sequence.registerHistoryTap(start.add(
      const Duration(seconds: 11),
    )), isFalse);
    sequence.reset();

    for (var tap = 0; tap < 6; tap++) {
      expect(sequence.registerHistoryTap(
        start.add(Duration(seconds: 12 + tap)),
      ), isFalse);
    }
    expect(sequence.registerHistoryTap(start.add(
      const Duration(seconds: 18),
    )), isTrue);
  });
}
