import '../../core/view_model.dart';
import '../../models/deck.dart';
import '../../models/flashcard.dart';
import '../../models/mastery_stats.dart';
import '../../repositories/deck_repository.dart';
import '../../repositories/flashcard_repository.dart';
import '../../repositories/repository_exception.dart';

final class DeckDetailViewModel extends ViewModel {
  DeckDetailViewModel({
    required this.deckId,
    required DeckRepository deckRepository,
    required FlashcardRepository flashcardRepository,
  }) : _decks = deckRepository,
       _cards = flashcardRepository;

  final int deckId;
  final DeckRepository _decks;
  final FlashcardRepository _cards;
  Deck? deck;
  List<Flashcard> cards = const [];
  MasteryStats? mastery;
  bool isLoading = false;
  bool isDeleting = false;
  bool isResetting = false;
  String? error;
  String? deletionError;
  String? resetError;
  Future<void>? _loadFuture;

  bool get isBusy => isLoading || isDeleting || isResetting;
  bool get canStudyAgain =>
      !isBusy &&
      error == null &&
      deck != null &&
      cards.isNotEmpty &&
      (mastery?.known ?? 0) > 0;

  Future<void> load() {
    if (isDisposed || isDeleting || isResetting) return Future.value();
    return _loadFuture ??= _load().whenComplete(() => _loadFuture = null);
  }

  Future<void> _load() async {
    isLoading = true;
    error = null;
    deletionError = null;
    resetError = null;
    publish();
    try {
      final loadedDeck = await _decks.getById(deckId);
      if (loadedDeck == null) throw RecordNotFoundException('Deck', deckId);
      final loadedCards = await _cards.getByDeck(deckId);
      final loadedMastery = await _decks.getMasteryStats(deckId);
      if (isDisposed) return;
      deck = loadedDeck;
      cards = List.unmodifiable(loadedCards);
      mastery = loadedMastery;
    } catch (failure) {
      error = messageFor(
        failure,
        'We couldn’t load this deck. Please try again.',
      );
    } finally {
      isLoading = false;
      publish();
    }
  }

  /// The screen obtains confirmation before calling this centralized reset.
  /// Navigation is allowed only after the transaction has committed.
  Future<bool> resetMastery() async {
    if (isDisposed || !canStudyAgain) return false;
    isResetting = true;
    resetError = null;
    publish();
    try {
      await _decks.resetMastery(deckId);
      if (isDisposed) return false;
      await _load();
      return true;
    } catch (failure) {
      resetError = messageFor(
        failure,
        'We couldn’t reset mastery. Your progress is unchanged. Please try again.',
      );
      return false;
    } finally {
      isResetting = false;
      publish();
    }
  }

  Future<bool> deleteCard(int id) async {
    if (isBusy || isDisposed) return false;
    isDeleting = true;
    deletionError = null;
    publish();
    try {
      await _cards.delete(id);
      if (isDisposed) return false;
      await _load();
      return true;
    } catch (failure) {
      deletionError = messageFor(
        failure,
        'We couldn’t delete this flashcard. Reload to check the saved data.',
      );
      return false;
    } finally {
      isDeleting = false;
      publish();
    }
  }

  Future<bool> deleteDeck() async {
    if (isBusy || isDisposed) return false;
    isDeleting = true;
    deletionError = null;
    publish();
    try {
      await _decks.delete(deckId);
      return true;
    } catch (failure) {
      deletionError = messageFor(
        failure,
        'We couldn’t delete this deck. Reload to check the saved data.',
      );
      return false;
    } finally {
      isDeleting = false;
      publish();
    }
  }
}
