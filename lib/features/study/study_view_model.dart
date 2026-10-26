import '../../core/view_model.dart';
import '../../models/deck.dart';
import '../../models/flashcard.dart';
import '../../models/mastery_stats.dart';
import '../../repositories/deck_repository.dart';
import '../../repositories/flashcard_repository.dart';
import '../../repositories/repository_exception.dart';
import 'study_session.dart';

enum StudyState {
  initial,
  loading,
  studying,
  roundSummary,
  empty,
  finishing,
  complete,
  loadError,
  completionError,
}

final class StudyViewModel extends ViewModel {
  StudyViewModel({
    required this.deckId,
    required DeckRepository deckRepository,
    required FlashcardRepository flashcardRepository,
  }) : _decks = deckRepository,
       _cards = flashcardRepository;

  final int deckId;
  final DeckRepository _decks;
  final FlashcardRepository _cards;
  StudySession? _session;
  Map<int, Flashcard> _contents = const {};
  Deck? _deck;
  StudyState _state = StudyState.initial;
  bool _isSaving = false;
  bool _isSkipping = false;
  bool _isRevealed = false;
  String? _error;
  StudyGrade? _failedGrade;
  MasteryStats? _finalMastery;
  Future<void>? _startFuture;

  StudyState get state => _state;
  String get deckTitle => _deck?.title ?? 'Your deck';
  Flashcard? get currentCard => _contents[_session?.currentCardId];
  int get turn => _session?.turn ?? 0;
  int get round => _session?.round ?? 0;
  int get totalCards => _session?.totalCards ?? 0;
  int get knownCount => _session?.knownCount ?? 0;
  int get remainingInRound => _session?.remainingInRound ?? 0;
  int get remainingCards => _session?.remainingCards ?? 0;
  int get reviewCount => _session?.reviewCount ?? 0;
  int get skippedCount => _session?.skippedCount ?? 0;
  bool get isSaving => _isSaving;
  bool get isSkipping => _isSkipping;
  bool get isRevealed => _isRevealed;
  bool get canSkip =>
      !isDisposed &&
      _state == StudyState.studying &&
      !_isSaving &&
      !_isSkipping;
  bool get canGrade => canSkip && _isRevealed;
  bool get canRetryGrade => canGrade && _failedGrade != null;
  String? get error => _error;
  MasteryStats? get finalMastery => _finalMastery;

  /// Loading retries are allowed; a loaded session is never restarted in place.
  Future<void> start() {
    if (isDisposed || _session != null) return Future.value();
    return _startFuture ??= _load().whenComplete(() => _startFuture = null);
  }

  Future<void> _load() async {
    _state = StudyState.loading;
    _error = null;
    publish();
    try {
      final deck = await _decks.getById(deckId);
      if (isDisposed) return;
      if (deck == null) throw RecordNotFoundException('Deck', deckId);
      // Intentionally unfiltered: even an already-mastered deck starts fresh.
      final cards = await _cards.getByDeck(deckId);
      if (isDisposed) return;
      _deck = deck;
      _session = StudySession(cards.map((card) => card.id));
      _contents = Map.unmodifiable({for (final card in cards) card.id: card});
      _state = cards.isEmpty ? StudyState.empty : StudyState.studying;
    } catch (failure) {
      if (isDisposed) return;
      _state = StudyState.loadError;
      _error = messageFor(
        failure,
        'We couldn’t start this session. Please try again.',
      );
    } finally {
      publish();
    }
  }

  /// The card calls this after its reveal animation has actually finished.
  void revealAnswer(int expectedTurn) {
    if (isDisposed ||
        _state != StudyState.studying ||
        _isSaving ||
        _isSkipping ||
        expectedTurn != turn ||
        _isRevealed) {
      return;
    }
    _isRevealed = true;
    publish();
  }

  Future<bool> grade(StudyGrade choice, {required int expectedTurn}) async {
    if (!canGrade || expectedTurn != turn) return false;
    final session = _session!;
    final cardId = session.currentCardId!;
    _isSaving = true;
    _error = null;
    _failedGrade = null;
    publish();
    try {
      await _cards.setMasteryStatus(
        id: cardId,
        status: choice == StudyGrade.known
            ? MasteryStatus.known
            : MasteryStatus.review,
      );
      if (isDisposed) return true;
      session.recordGrade(expectedTurn: expectedTurn, grade: choice);
      _isRevealed = false;
      if (session.isComplete) {
        await _loadCompletion();
      } else if (session.isRoundComplete) {
        _state = StudyState.roundSummary;
      }
      return true;
    } catch (failure) {
      if (isDisposed) return false;
      _failedGrade = choice;
      _error = messageFor(failure, 'Couldn’t save. This card hasn’t moved.');
      return false;
    } finally {
      _isSaving = false;
      publish();
    }
  }

  /// Reserve the current turn while the card slides out. This also locks
  /// grading, so a button press cannot race the skip animation.
  bool beginSkip(int expectedTurn) {
    if (!canSkip || expectedTurn != turn) return false;
    _isSkipping = true;
    publish();
    return true;
  }

  /// Skip never calls a repository, even for a card saved as Known.
  bool skip({required int expectedTurn}) {
    if (isDisposed ||
        _state != StudyState.studying ||
        _isSaving ||
        expectedTurn != turn) {
      return false;
    }
    _session!.skip(expectedTurn: expectedTurn);
    _isSkipping = false;
    _isRevealed = false;
    _failedGrade = null;
    _error = null;
    if (_session!.isRoundComplete) _state = StudyState.roundSummary;
    publish();
    return true;
  }

  bool retryRemaining({required int expectedRound}) {
    if (isDisposed || _state != StudyState.roundSummary || _isSaving) {
      return false;
    }
    if (!_session!.retryRemaining(expectedRound: expectedRound)) return false;
    _isRevealed = false;
    _state = StudyState.studying;
    publish();
    return true;
  }

  Future<bool> retryGrade() {
    final choice = _failedGrade;
    if (!canRetryGrade || choice == null) return Future.value(false);
    return grade(choice, expectedTurn: turn);
  }

  /// A failed final read retries only that query, never the successful grade.
  Future<void> retryCompletion() async {
    if (isDisposed || _state != StudyState.completionError || _isSaving) return;
    await _loadCompletion();
  }

  Future<void> _loadCompletion() async {
    _state = StudyState.finishing;
    _error = null;
    publish();
    try {
      final savedStats = await _decks.getMasteryStats(deckId);
      if (isDisposed) return;
      _finalMastery = savedStats;
      _state = StudyState.complete;
    } catch (failure) {
      if (isDisposed) return;
      _state = StudyState.completionError;
      _error = messageFor(
        failure,
        'Your choices were saved, but we couldn’t load final mastery. Please try again.',
      );
    } finally {
      publish();
    }
  }
}
