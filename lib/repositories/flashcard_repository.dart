import '../models/flashcard.dart';

/// Persistent cards only. Session queues, rounds, and flip state belong elsewhere.
abstract interface class FlashcardRepository {
  /// Returns ALL cards in creation order, regardless of saved mastery. A new
  /// study session must use this unfiltered list. A missing deck returns [].
  Future<List<Flashcard>> getByDeck(int deckId);

  Future<Flashcard?> getById(int id);

  /// New cards always start in Review. Text is trimmed and must be nonempty.
  Future<Flashcard> create({
    required int deckId,
    required String question,
    required String answer,
  });

  /// Resets mastery to Review only when the normalized content changes.
  /// The future editor must explain this reset before the user saves.
  Future<Flashcard> updateContent({
    required int id,
    required String question,
    required String answer,
  });

  /// Saves an explicit classification. Completes only after the write commits;
  /// callers must await success before advancing a study session.
  Future<Flashcard> setMasteryStatus({
    required int id,
    required MasteryStatus status,
  });

  /// Returns false if already deleted. The caller must first obtain confirmation.
  Future<bool> delete(int id);
}
