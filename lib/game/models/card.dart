/// Playing-card primitives for a standard 52-card deck (no jokers).
library;

/// Suits ordered from lowest to highest for tie-breaking:
/// clubs < diamonds < hearts < spades.
enum Suit {
  clubs('C', '♣'),
  diamonds('D', '♦'),
  hearts('H', '♥'),
  spades('S', '♠');

  const Suit(this.code, this.symbol);

  final String code;
  final String symbol;

  bool get isRed => this == Suit.diamonds || this == Suit.hearts;

  static Suit fromCode(String code) =>
      Suit.values.firstWhere((s) => s.code == code,
          orElse: () => throw FormatException('Unknown suit "$code"'));
}

/// Card ranks. [value] runs 2..14 with the ace high (14).
enum Rank {
  two(2, '2'),
  three(3, '3'),
  four(4, '4'),
  five(5, '5'),
  six(6, '6'),
  seven(7, '7'),
  eight(8, '8'),
  nine(9, '9'),
  ten(10, '10'),
  jack(11, 'J'),
  queen(12, 'Q'),
  king(13, 'K'),
  ace(14, 'A');

  const Rank(this.value, this.label);

  final int value;
  final String label;

  static Rank fromValue(int value) => Rank.values[value - 2];

  static Rank fromLabel(String label) =>
      Rank.values.firstWhere((r) => r.label == label,
          orElse: () => throw FormatException('Unknown rank "$label"'));
}

/// An immutable playing card. Every card in a deck has a unique [id] 0..51.
class PlayingCard implements Comparable<PlayingCard> {
  const PlayingCard(this.rank, this.suit);

  factory PlayingCard.fromId(int id) {
    if (id < 0 || id >= 52) {
      throw RangeError.range(id, 0, 51, 'id');
    }
    return PlayingCard(Rank.values[id % 13], Suit.values[id ~/ 13]);
  }

  /// Parses codes like `AS`, `10H`, `2C`.
  factory PlayingCard.parse(String code) {
    final trimmed = code.trim().toUpperCase();
    if (trimmed.length < 2) throw FormatException('Bad card "$code"');
    final suit = Suit.fromCode(trimmed.substring(trimmed.length - 1));
    final rank = Rank.fromLabel(trimmed.substring(0, trimmed.length - 1));
    return PlayingCard(rank, suit);
  }

  final Rank rank;
  final Suit suit;

  int get id => suit.index * 13 + rank.index;

  String get code => '${rank.label}${suit.code}';

  @override
  bool operator ==(Object other) =>
      other is PlayingCard && other.rank == rank && other.suit == suit;

  @override
  int get hashCode => id;

  /// Orders by rank, then suit (used for sorting hands for display).
  @override
  int compareTo(PlayingCard other) {
    final byRank = rank.value.compareTo(other.rank.value);
    return byRank != 0 ? byRank : suit.index.compareTo(other.suit.index);
  }

  @override
  String toString() => code;
}

/// Parses a space separated list of card codes, e.g. `"AS KS QS"`.
List<PlayingCard> parseCards(String codes) => codes
    .split(RegExp(r'[\s,]+'))
    .where((s) => s.isNotEmpty)
    .map(PlayingCard.parse)
    .toList();

/// The 52 cards of a fresh, ordered deck.
List<PlayingCard> fullDeck() =>
    List<PlayingCard>.generate(52, PlayingCard.fromId, growable: false);
