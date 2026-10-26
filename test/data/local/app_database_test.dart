import 'dart:io';

import 'package:flashquest_drill/data/local/app_database.dart';
import 'package:flashquest_drill/data/repositories/sqlite_deck_repository.dart';
import 'package:flashquest_drill/data/repositories/sqlite_flashcard_repository.dart';
import 'package:flashquest_drill/models/flashcard.dart';
import 'package:flashquest_drill/models/mastery_stats.dart';
import 'package:flashquest_drill/repositories/repository_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory temporaryDirectory;
  late String databasePath;
  late AppDatabase appDatabase;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'flashquest_drill_database_test_',
    );
    databasePath = p.join(temporaryDirectory.path, AppDatabase.fileName);
    appDatabase = AppDatabase(factory: databaseFactoryFfi, path: databasePath);
  });

  tearDown(() async {
    await appDatabase.close();
    // Only remove the unique temporary directory owned by this test.
    await temporaryDirectory.delete(recursive: true);
  });

  test('initializes version, tables, foreign keys, and indexes', () async {
    final db = await appDatabase.database;

    expect(await db.getVersion(), AppDatabase.schemaVersion);
    expect((await db.rawQuery('PRAGMA foreign_keys')).single.values.single, 1);
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    expect(
      tables.map((row) => row['name']),
      containsAll(['decks', 'flashcards']),
    );
    final indexes = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'index'",
    );
    expect(
      indexes.map((row) => row['name']),
      containsAll(['idx_decks_title', 'idx_flashcards_deck_status']),
    );
    final foreignKeys = await db.rawQuery(
      'PRAGMA foreign_key_list(flashcards)',
    );
    expect(foreignKeys.single['table'], 'decks');
    expect(foreignKeys.single['on_delete'], 'CASCADE');
  });

  test('concurrent initialization shares one connection', () async {
    final databases = await Future.wait(
      List.generate(20, (_) => appDatabase.database),
    );

    expect(databases.every((db) => identical(db, databases.first)), isTrue);
    expect(await databases.first.getVersion(), AppDatabase.schemaVersion);
  });

  test('foreign keys reject orphan cards even outside repositories', () async {
    final db = await appDatabase.database;

    await expectLater(
      db.insert('flashcards', {
        'deck_id': 123,
        'question': 'Question',
        'answer': 'Answer',
        'created_at': 0,
        'updated_at': 0,
      }),
      throwsA(isA<DatabaseException>()),
    );
    expect(await db.query('flashcards'), isEmpty);
  });

  test('schema rejects invalid mastery and empty required text', () async {
    final db = await appDatabase.database;
    final deck = await SqliteDeckRepository(appDatabase).create(title: 'Deck');
    final validCard = <String, Object?>{
      'deck_id': deck.id,
      'question': 'Question',
      'answer': 'Answer',
      'created_at': 0,
      'updated_at': 0,
    };

    for (final invalidValues in [
      {'status': 'unknown'},
      {'question': '  '},
      {'answer': ''},
    ]) {
      await expectLater(
        db.insert('flashcards', {...validCard, ...invalidValues}),
        throwsA(isA<DatabaseException>()),
      );
    }
    await expectLater(
      db.insert('decks', {'title': ' ', 'created_at': 0, 'updated_at': 0}),
      throwsA(isA<DatabaseException>()),
    );
    expect(await db.query('flashcards'), isEmpty);
  });

  test(
    'decks, content, timestamps, and mastery survive closing and reopening',
    () async {
      final decks = SqliteDeckRepository(appDatabase);
      final cards = SqliteFlashcardRepository(appDatabase);
      final deck = await decks.create(title: "Biology's review — 生物");
      final first = await cards.create(
        deckId: deck.id,
        question: "What's ATP?\nExplain.",
        answer: 'Adenosine triphosphate',
      );
      final second = await cards.create(
        deckId: deck.id,
        question: 'Cell boundary?',
        answer: 'Membrane',
      );
      final known = await cards.setMasteryStatus(
        id: first.id,
        status: MasteryStatus.known,
      );
      await appDatabase.close();

      appDatabase = AppDatabase(
        factory: databaseFactoryFfi,
        path: databasePath,
      );
      final reopenedDecks = SqliteDeckRepository(appDatabase);
      final reopenedCards = SqliteFlashcardRepository(appDatabase);

      expect(await reopenedDecks.getById(deck.id), deck);
      expect(await reopenedCards.getByDeck(deck.id), [known, second]);
      expect(
        await reopenedDecks.getMasteryStats(deck.id),
        MasteryStats(total: 2, known: 1),
      );
      expect(await (await appDatabase.database).getVersion(), 1);
      expect(
        (await (await appDatabase.database).rawQuery('PRAGMA foreign_keys'))
            .single
            .values
            .single,
        1,
      );
    },
  );

  test('refuses a newer schema without deleting its data', () async {
    final futureDatabase = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: AppDatabase.schemaVersion + 1,
        singleInstance: false,
        onCreate: (db, version) async {
          await db.execute('CREATE TABLE future_data (value TEXT NOT NULL)');
          await db.insert('future_data', {'value': 'Keep me'});
        },
      ),
    );
    await futureDatabase.close();

    await expectLater(appDatabase.database, throwsA(isA<StorageException>()));

    final unchanged = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    try {
      expect(await unchanged.getVersion(), AppDatabase.schemaVersion + 1);
      expect((await unchanged.query('future_data')).single['value'], 'Keep me');
    } finally {
      await unchanged.close();
    }
  });

  test(
    'a failed initialization can be retried after the cause is fixed',
    () async {
      // A directory cannot be opened as a SQLite file.
      final conflictingDirectory = await Directory(databasePath).create();
      await expectLater(appDatabase.database, throwsA(isA<StorageException>()));
      await conflictingDirectory.delete();

      expect(await (await appDatabase.database).getVersion(), 1);
    },
  );

  test(
    'close is idempotent and use after close reports a storage error',
    () async {
      await appDatabase.database;

      await Future.wait([appDatabase.close(), appDatabase.close()]);

      await expectLater(appDatabase.database, throwsA(isA<StorageException>()));
    },
  );
}
