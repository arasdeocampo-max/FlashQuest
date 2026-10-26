import 'package:flashquest_drill/models/deck.dart';
import 'package:flashquest_drill/models/flashcard.dart';
import 'package:flashquest_drill/models/mastery_stats.dart';
import 'package:flashquest_drill/repositories/deck_repository.dart';
import 'package:flashquest_drill/repositories/flashcard_repository.dart';
import 'package:flashquest_drill/repositories/repository_exception.dart';

/// Deterministic widget fixtures. Real SQLite is covered by data and view-model
/// tests; these avoid native I/O inside Flutter's simulated animation clock.
class MemoryStore {
  final decks = <int, Deck>{};
  final cards = <int, Flashcard>{};
  int nextDeck = 1;
  int nextCard = 1;
}

class MemoryDeckRepository implements DeckRepository {
  MemoryDeckRepository(this.store);
  final MemoryStore store;

  @override
  Future<List<Deck>> getAll() async => store.decks.values.toList()
    ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

  @override
  Future<Deck?> getById(int id) async => store.decks[id];

  @override
  Future<Deck> create({required String title}) async {
    final now = DateTime.now().toUtc();
    final deck = Deck(
      id: store.nextDeck++,
      title: title.trim(),
      createdAt: now,
      updatedAt: now,
    );
    store.decks[deck.id] = deck;
    return deck;
  }

  @override
  Future<Deck> update({required int id, required String title}) async {
    final previous = store.decks[id];
    if (previous == null) throw RecordNotFoundException('Deck', id);
    final deck = Deck(
      id: id,
      title: title.trim(),
      createdAt: previous.createdAt,
      updatedAt: DateTime.now().toUtc(),
    );
    store.decks[id] = deck;
    return deck;
  }

  @override
  Future<bool> delete(int id) async {
    store.cards.removeWhere((_, card) => card.deckId == id);
    return store.decks.remove(id) != null;
  }

  @override
  Future<void> resetMastery(int deckId) async {
    if (!store.decks.containsKey(deckId)) {
      throw RecordNotFoundException('Deck', deckId);
    }
    final now = DateTime.now().toUtc();
    for (final card in store.cards.values.toList()) {
      if (card.deckId != deckId || card.status != MasteryStatus.known) continue;
      store.cards[card.id] = Flashcard(
        id: card.id,
        deckId: card.deckId,
        question: card.question,
        answer: card.answer,
        status: MasteryStatus.review,
        createdAt: card.createdAt,
        updatedAt: now,
      );
    }
  }

  @override
  Future<MasteryStats> getMasteryStats(int deckId) async {
    if (!store.decks.containsKey(deckId)) {
      throw RecordNotFoundException('Deck', deckId);
    }
    final cards = store.cards.values.where((card) => card.deckId == deckId);
    return MasteryStats(
      total: cards.length,
      known: cards.where((card) => card.status == MasteryStatus.known).length,
    );
  }

  @override
  Future<Map<int, MasteryStats>> getAllMasteryStats() async => {
    for (final id in store.decks.keys) id: await getMasteryStats(id),
  };
}

class MemoryFlashcardRepository implements FlashcardRepository {
  MemoryFlashcardRepository(this.store);
  final MemoryStore store;

  @override
  Future<List<Flashcard>> getByDeck(int deckId) async =>
      store.cards.values.where((card) => card.deckId == deckId).toList();

  @override
  Future<Flashcard?> getById(int id) async => store.cards[id];

  @override
  Future<Flashcard> create({
    required int deckId,
    required String question,
    required String answer,
  }) async {
    if (!store.decks.containsKey(deckId)) {
      throw RecordNotFoundException('Deck', deckId);
    }
    final now = DateTime.now().toUtc();
    final card = Flashcard(
      id: store.nextCard++,
      deckId: deckId,
      question: question.trim(),
      answer: answer.trim(),
      status: MasteryStatus.review,
      createdAt: now,
      updatedAt: now,
    );
    store.cards[card.id] = card;
    return card;
  }

  @override
  Future<Flashcard> updateContent({
    required int id,
    required String question,
    required String answer,
  }) async {
    final previous = store.cards[id];
    if (previous == null) throw RecordNotFoundException('Flashcard', id);
    final changed =
        question.trim() != previous.question ||
        answer.trim() != previous.answer;
    final card = Flashcard(
      id: id,
      deckId: previous.deckId,
      question: question.trim(),
      answer: answer.trim(),
      status: changed ? MasteryStatus.review : previous.status,
      createdAt: previous.createdAt,
      updatedAt: DateTime.now().toUtc(),
    );
    store.cards[id] = card;
    return card;
  }

  @override
  Future<Flashcard> setMasteryStatus({
    required int id,
    required MasteryStatus status,
  }) async {
    final previous = store.cards[id];
    if (previous == null) throw RecordNotFoundException('Flashcard', id);
    final card = Flashcard(
      id: id,
      deckId: previous.deckId,
      question: previous.question,
      answer: previous.answer,
      status: status,
      createdAt: previous.createdAt,
      updatedAt: DateTime.now().toUtc(),
    );
    store.cards[id] = card;
    return card;
  }

  @override
  Future<bool> delete(int id) async => store.cards.remove(id) != null;
}
