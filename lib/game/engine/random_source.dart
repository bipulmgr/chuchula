import 'dart:math';

/// Injectable randomness so shuffles are secure in production and
/// reproducible in tests.
abstract class RandomSource {
  /// Uniform integer in `[0, max)`.
  int nextInt(int max);

  /// Fisher-Yates shuffle returning a new list.
  List<T> shuffled<T>(List<T> items) {
    final list = List<T>.of(items);
    for (var i = list.length - 1; i > 0; i--) {
      final j = nextInt(i + 1);
      final tmp = list[i];
      list[i] = list[j];
      list[j] = tmp;
    }
    return list;
  }
}

/// Cryptographically secure randomness (`Random.secure`).
class SecureRandomSource extends RandomSource {
  SecureRandomSource() : _random = Random.secure();
  final Random _random;

  @override
  int nextInt(int max) => _random.nextInt(max);
}

/// Deterministic randomness for tests, replays and bot simulations.
class SeededRandomSource extends RandomSource {
  SeededRandomSource(int seed) : _random = Random(seed);
  final Random _random;

  @override
  int nextInt(int max) => _random.nextInt(max);
}

/// Returns a fixed, pre-arranged deck order. `nextInt` is not used for
/// dealing by [FixedDeckRandomSource]; the engine asks for [deck] directly.
class FixedDeckRandomSource extends RandomSource {
  FixedDeckRandomSource(this.decks, {int seed = 0}) : _fallback = Random(seed);

  /// Deck orders to deal, one per round. When exhausted, falls back to a
  /// seeded shuffle.
  final List<List<int>> decks;
  final Random _fallback;
  int _next = 0;

  List<int>? takeDeck() => _next < decks.length ? decks[_next++] : null;

  @override
  int nextInt(int max) => _fallback.nextInt(max);
}
