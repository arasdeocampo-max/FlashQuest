import '../../models/flashcard.dart';
import '../../repositories/flashcard_repository.dart';
import '../../repositories/repository_exception.dart';
import '../local/app_database.dart';
import 'sqlite_mapping.dart';

final class SqliteFlashcardRepository implements FlashcardRepository {
  SqliteFlashcardRepository(this._database);

  final AppDatabase _database;

  @override
  Future<List<Flashcard>> getByDeck(int deckId) =>
      _database.run('load flashcards', (db) async {
        final rows = await db.query(
          'flashcards',
          where: 'deck_id = ?',
          whereArgs: [deckId],
          orderBy: 'id',
        );
        return rows.map(flashcardFromRow).toList(growable: false);
      });

  @override
  Future<Flashcard?> getById(int id) => _database.run('load the flashcard', (
    db,
  ) async {
    final rows = await db.query('flashcards', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : flashcardFromRow(rows.single);
  });

  @override
  Future<Flashcard> create({
    required int deckId,
    required String question,
    required String answer,
  }) async {
    final normalizedQuestion = requireText(question, 'question');
    final normalizedAnswer = requireText(answer, 'answer');
    return _database.run('create the flashcard', (db) {
      return db.transaction((txn) async {
        final decks = await txn.query(
          'decks',
          columns: ['id'],
          where: 'id = ?',
          whereArgs: [deckId],
        );
        if (decks.isEmpty) throw RecordNotFoundException('Deck', deckId);
        final now = DateTime.now().millisecondsSinceEpoch;
        final values = <String, Object?>{
          'deck_id': deckId,
          'question': normalizedQuestion,
          'answer': normalizedAnswer,
          'status': MasteryStatus.review.name,
          'created_at': now,
          'updated_at': now,
        };
        final id = await txn.insert('flashcards', values);
        return flashcardFromRow({...values, 'id': id});
      });
    });
  }

  @override
  Future<Flashcard> updateContent({
    required int id,
    required String question,
    required String answer,
  }) async {
    final normalizedQuestion = requireText(question, 'question');
    final normalizedAnswer = requireText(answer, 'answer');
    return _database.run('update the flashcard', (db) {
      return db.transaction((txn) async {
        final rows = await txn.query(
          'flashcards',
          where: 'id = ?',
          whereArgs: [id],
        );
        if (rows.isEmpty) throw RecordNotFoundException('Flashcard', id);
        final current = rows.single;
        if (current['question'] == normalizedQuestion &&
            current['answer'] == normalizedAnswer) {
          return flashcardFromRow(current);
        }
        final changes = <String, Object?>{
          'question': normalizedQuestion,
          'answer': normalizedAnswer,
          // Content and mastery change in the same transaction.
          'status': MasteryStatus.review.name,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        };
        await txn.update(
          'flashcards',
          changes,
          where: 'id = ?',
          whereArgs: [id],
        );
        return flashcardFromRow({...current, ...changes});
      });
    });
  }

  @override
  Future<Flashcard> setMasteryStatus({
    required int id,
    required MasteryStatus status,
  }) => _database.run('save flashcard mastery', (db) {
    return db.transaction((txn) async {
      // Set a value, never toggle it: repeated identical calls remain safe.
      final count = await txn.update(
        'flashcards',
        {
          'status': status.name,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      if (count == 0) throw RecordNotFoundException('Flashcard', id);
      final rows = await txn.query(
        'flashcards',
        where: 'id = ?',
        whereArgs: [id],
      );
      return flashcardFromRow(rows.single);
    });
  });

  @override
  Future<bool> delete(int id) => _database.run('delete the flashcard', (
    db,
  ) async {
    return await db.delete('flashcards', where: 'id = ?', whereArgs: [id]) != 0;
  });
}
