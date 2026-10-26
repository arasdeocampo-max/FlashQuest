import 'package:flashquest_drill/models/deck.dart';
import 'package:flashquest_drill/models/flashcard.dart';
import 'package:flashquest_drill/models/mastery_stats.dart';
import 'package:flashquest_drill/repositories/deck_repository.dart';
import 'package:flashquest_drill/repositories/flashcard_repository.dart';
import 'package:flashquest_drill/repositories/repository_exception.dart';

/// Real repositories with controllable latency and failures at the UI boundary.
class ControlledDeckRepository implements DeckRepository {
  ControlledDeckRepository(this.delegate);
  final DeckRepository delegate;
  Future<void>? readGate;
  Future<void>? writeGate;
  bool failReads = false;
  bool failWrites = false;
  int loadCalls = 0;
  int createCalls = 0;
  int updateCalls = 0;
  int deleteCalls = 0;
  int resetCalls = 0;

  Future<void> _read() async {
    await readGate;
    if (failReads) {
      throw const StorageException('Private database diagnostics');
    }
  }

  Future<void> _write() async {
    await writeGate;
    if (failWrites) {
      throw const StorageException('Private database diagnostics');
    }
  }

  @override
  Future<List<Deck>> getAll() async {
    loadCalls++;
    await _read();
    return delegate.getAll();
  }

  @override
  Future<Deck?> getById(int id) async {
    await _read();
    return delegate.getById(id);
  }

  @override
  Future<Deck> create({required String title}) async {
    createCalls++;
    await _write();
    return delegate.create(title: title);
  }

  @override
  Future<Deck> update({required int id, required String title}) async {
    updateCalls++;
    await _write();
    return delegate.update(id: id, title: title);
  }

  @override
  Future<bool> delete(int id) async {
    deleteCalls++;
    await _write();
    return delegate.delete(id);
  }

  @override
  Future<void> resetMastery(int deckId) async {
    resetCalls++;
    await _write();
    await delegate.resetMastery(deckId);
  }

  @override
  Future<MasteryStats> getMasteryStats(int deckId) async {
    await _read();
    return delegate.getMasteryStats(deckId);
  }

  @override
  Future<Map<int, MasteryStats>> getAllMasteryStats() async {
    await _read();
    return delegate.getAllMasteryStats();
  }
}

class ControlledFlashcardRepository implements FlashcardRepository {
  ControlledFlashcardRepository(this.delegate);
  final FlashcardRepository delegate;
  Future<void>? readGate;
  Future<void>? writeGate;
  bool failReads = false;
  bool failWrites = false;
  int createCalls = 0;
  int updateCalls = 0;
  int deleteCalls = 0;
  int gradeCalls = 0;
  int cardLoadCalls = 0;

  Future<void> _read() async {
    await readGate;
    if (failReads) {
      throw const StorageException('Private database diagnostics');
    }
  }

  Future<void> _write() async {
    await writeGate;
    if (failWrites) {
      throw const StorageException('Private database diagnostics');
    }
  }

  @override
  Future<List<Flashcard>> getByDeck(int deckId) async {
    cardLoadCalls++;
    await _read();
    return delegate.getByDeck(deckId);
  }

  @override
  Future<Flashcard?> getById(int id) async {
    await _read();
    return delegate.getById(id);
  }

  @override
  Future<Flashcard> create({
    required int deckId,
    required String question,
    required String answer,
  }) async {
    createCalls++;
    await _write();
    return delegate.create(deckId: deckId, question: question, answer: answer);
  }

  @override
  Future<Flashcard> updateContent({
    required int id,
    required String question,
    required String answer,
  }) async {
    updateCalls++;
    await _write();
    return delegate.updateContent(id: id, question: question, answer: answer);
  }

  @override
  Future<Flashcard> setMasteryStatus({
    required int id,
    required MasteryStatus status,
  }) async {
    gradeCalls++;
    await _write();
    return delegate.setMasteryStatus(id: id, status: status);
  }

  @override
  Future<bool> delete(int id) async {
    deleteCalls++;
    await _write();
    return delegate.delete(id);
  }
}
