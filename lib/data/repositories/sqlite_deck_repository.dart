import '../../models/deck.dart';
import '../../models/mastery_stats.dart';
import '../../repositories/deck_repository.dart';
import '../../repositories/repository_exception.dart';
import '../local/app_database.dart';
import 'sqlite_mapping.dart';

final class SqliteDeckRepository implements DeckRepository {
  SqliteDeckRepository(this._database);

  final AppDatabase _database;

  // LEFT JOIN preserves empty decks. Only card statuses determine mastery.
  static const _masteryQuery = '''
    SELECT d.id AS deck_id, COUNT(f.id) AS total,
      COALESCE(SUM(CASE WHEN f.status = 'known' THEN 1 ELSE 0 END), 0) AS known
    FROM decks d
    LEFT JOIN flashcards f ON f.deck_id = d.id
  ''';

  @override
  Future<List<Deck>> getAll() => _database.run('load decks', (db) async {
    final rows = await db.query('decks', orderBy: 'title COLLATE NOCASE, id');
    return rows.map(deckFromRow).toList(growable: false);
  });

  @override
  Future<Deck?> getById(int id) => _database.run('load the deck', (db) async {
    final rows = await db.query('decks', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : deckFromRow(rows.single);
  });

  @override
  Future<Deck> create({required String title}) async {
    final normalizedTitle = requireText(title, 'title');
    return _database.run('create the deck', (db) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final values = <String, Object?>{
        'title': normalizedTitle,
        'created_at': now,
        'updated_at': now,
      };
      final id = await db.insert('decks', values);
      return deckFromRow({...values, 'id': id});
    });
  }

  @override
  Future<Deck> update({required int id, required String title}) async {
    final normalizedTitle = requireText(title, 'title');
    return _database.run('update the deck', (db) {
      return db.transaction((txn) async {
        final count = await txn.update(
          'decks',
          {
            'title': normalizedTitle,
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
        if (count == 0) throw RecordNotFoundException('Deck', id);
        final rows = await txn.query('decks', where: 'id = ?', whereArgs: [id]);
        return deckFromRow(rows.single);
      });
    });
  }

  @override
  Future<bool> delete(int id) => _database.run('delete the deck', (db) async {
    // SQLite atomically cascades this statement to all of the deck's cards.
    return await db.delete('decks', where: 'id = ?', whereArgs: [id]) != 0;
  });

  @override
  Future<void> resetMastery(int deckId) =>
      _database.run('reset deck mastery', (db) {
        return db.transaction((txn) async {
          final deck = await txn.query(
            'decks',
            columns: ['id'],
            where: 'id = ?',
            whereArgs: [deckId],
          );
          if (deck.isEmpty) throw RecordNotFoundException('Deck', deckId);
          await txn.update(
            'flashcards',
            {
              'status': 'review',
              'updated_at': DateTime.now().millisecondsSinceEpoch,
            },
            where: 'deck_id = ? AND status = ?',
            whereArgs: [deckId, 'known'],
          );
        });
      });

  @override
  Future<MasteryStats> getMasteryStats(int deckId) =>
      _database.run('load deck mastery', (db) async {
        final rows = await db.rawQuery(
          '$_masteryQuery WHERE d.id = ? GROUP BY d.id',
          [deckId],
        );
        if (rows.isEmpty) throw RecordNotFoundException('Deck', deckId);
        return masteryFromRow(rows.single);
      });

  @override
  Future<Map<int, MasteryStats>> getAllMasteryStats() =>
      _database.run('load deck mastery', (db) async {
        final rows = await db.rawQuery('$_masteryQuery GROUP BY d.id');
        return {
          for (final row in rows) row['deck_id'] as int: masteryFromRow(row),
        };
      });
}
