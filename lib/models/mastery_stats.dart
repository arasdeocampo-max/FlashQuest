/// A snapshot calculated from saved card statuses, never stored as counters.
final class MasteryStats {
  MasteryStats({required this.total, required this.known}) {
    if (total < 0) {
      throw ArgumentError.value(total, 'total', 'Must not be negative.');
    }
    if (known < 0 || known > total) {
      throw ArgumentError.value(known, 'known', 'Must be between 0 and total.');
    }
  }

  final int total;
  final int known;

  int get review => total - known;

  /// A value from 0 to 100; empty decks have zero mastery.
  double get percentage => total == 0 ? 0 : known / total * 100;

  @override
  bool operator ==(Object other) =>
      other is MasteryStats && total == other.total && known == other.known;

  @override
  int get hashCode => Object.hash(total, known);
}
