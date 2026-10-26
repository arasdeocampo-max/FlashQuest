/// A session's choice, independent of saved card mastery and Flutter.
enum StudyGrade { known, review }

/// Deterministic, temporary round state. This class never reads saved mastery,
/// performs I/O, or mutates flashcards. Supply every card ID in deck order.
final class StudySession {
  StudySession(Iterable<int> cardIds) : _roundCards = List.of(cardIds) {
    if (_roundCards.toSet().length != _roundCards.length) {
      throw ArgumentError('A session cannot contain duplicate card IDs.');
    }
    _totalCards = _roundCards.length;
    _round = isEmpty ? 0 : 1;
  }

  late final int _totalCards;
  late int _round;
  List<int> _roundCards;
  final List<int> _nextRound = [];
  final Set<int> _reviewPile = {};
  final Set<int> _skipped = {};
  int _position = 0;
  int _knownCount = 0;
  int _turn = 0;

  int get totalCards => _totalCards;
  bool get isEmpty => _totalCards == 0;
  bool get isComplete => !isEmpty && _knownCount == _totalCards;
  bool get isRoundComplete => !isEmpty && !isComplete && currentCardId == null;
  int get round => _round;
  int get turn => _turn;
  int get knownCount => _knownCount;
  int get remainingCards => _totalCards - _knownCount;
  int get remainingInRound => _roundCards.length - _position;

  /// Cards whose latest action in this session was Review.
  /// Unseen cards are not yet part of this temporary pile.
  int get reviewCount => _reviewPile.length;
  int get skippedCount => _skipped.length;

  int? get currentCardId =>
      _position < _roundCards.length ? _roundCards[_position] : null;

  /// Call only after persistence succeeds. A turn token also rejects a stale
  /// grade when a one-card Review round returns to the very same card ID.
  void recordGrade({required int expectedTurn, required StudyGrade grade}) {
    final id = currentCardId;
    if (id == null || expectedTurn != _turn) {
      throw StateError('This study turn is no longer active.');
    }
    switch (grade) {
      case StudyGrade.known:
        _knownCount++;
        _reviewPile.remove(id);
        _skipped.remove(id);
      case StudyGrade.review:
        _nextRound.add(id);
        _reviewPile.add(id);
        _skipped.remove(id);
    }
    _advance();
  }

  /// A temporary action only. The latest action partitions remaining cards
  /// into Review or Skipped, without changing their saved mastery status.
  void skip({required int expectedTurn}) {
    final id = currentCardId;
    if (id == null || expectedTurn != _turn) {
      throw StateError('This study turn is no longer active.');
    }
    _nextRound.add(id);
    _reviewPile.remove(id);
    _skipped.add(id);
    _advance();
  }

  void _advance() {
    _turn++;
    _position++;
  }

  /// Wait for an explicit retry, including when every card was skipped.
  /// The round token prevents a stale retry callback from starting a later pass.
  bool retryRemaining({required int expectedRound}) {
    if (!isRoundComplete || expectedRound != _round) return false;
    _roundCards = List.of(_nextRound);
    _nextRound.clear();
    _position = 0;
    _round++;
    return true;
  }
}
