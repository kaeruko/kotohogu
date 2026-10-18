import 'dart:math' as math;

/// An exact sequence makes unexpected redraws fail instead of hiding them.
class ScriptedTownRandom implements math.Random {
  ScriptedTownRandom(this.values);

  final List<int> values;
  int calls = 0;

  @override
  int nextInt(int max) {
    if (calls >= values.length) {
      throw StateError('Unexpected town draw: call=$calls, max=$max');
    }
    final value = values[calls++];
    if (value < 0 || value >= max) {
      throw RangeError.range(value, 0, max - 1, 'scripted town destination');
    }
    return value;
  }

  @override
  bool nextBool() => throw UnsupportedError('Only town destinations are scripted');

  @override
  double nextDouble() =>
      throw UnsupportedError('Only town destinations are scripted');
}
