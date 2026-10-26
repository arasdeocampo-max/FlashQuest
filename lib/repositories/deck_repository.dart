import '../models/deck.dart';
import '../models/mastery_stats.dart';

/// Persistent deck operations. Invalid text throws [ArgumentError]; storage
/// failures and missing mutation targets throw RepositoryException subtypes.
abstract interface class DeckRepository {
  /// Returns decks alphabetically, with IDs breaking title ties.
  Future<List<Deck>> getAll();

  Future<Deck?> getById(int id);

  Future<Deck> create({required String title});

  Future<Deck> update({required int id, required String title});

  /// Deletes the deck and its cards. Returns false if already deleted.
  /// The caller must obtain user confirmation before calling this method.
  Future<bool> delete(int id);

  /// Atomically resets all Known cards in this deck to Review. Decks, card
  /// content and IDs are preserved. Requires explicit user confirmation.
  Future<void> resetMastery(int deckId);

  /// Includes unseen cards in Review; throws if the deck does not exist.
  Future<MasteryStats> getMasteryStats(int deckId);

  /// Calculates every deck's mastery in one query, including empty decks.
  Future<Map<int, MasteryStats>> getAllMasteryStats();
}
