import 'dart:io';

import 'package:flashquest_drill/data/local/app_database.dart';
import 'package:flashquest_drill/data/repositories/sqlite_deck_repository.dart';
import 'package:flashquest_drill/data/repositories/sqlite_flashcard_repository.dart';
import 'package:flashquest_drill/features/startup/startup_view_model.dart';
import 'package:flashquest_drill/models/flashcard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  late Directory directory;
  late String databasePath;
  late AppDatabase database;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'flashquest_startup_test_',
    );
    databasePath = p.join(directory.path, AppDatabase.fileName);
    database = AppDatabase(
      factory: databaseFactoryFfiNoIsolate,
      path: databasePath,
    );
  });

  tearDown(() async {
    await database.close();
    // Only delete the unique, verified temporary directory owned by this test.
    expect(
      p.isWithin(Directory.systemTemp.absolute.path, directory.absolute.path),
      isTrue,
    );
    expect(p.basename(directory.path), startsWith('flashquest_startup_test_'));
    await directory.delete(recursive: true);
  });

  test(
    'startup reopens existing SQLite records, mastery and schema unchanged',
    () async {
      final deck = await SqliteDeckRepository(database)
          .create(title: 'Saved biology');
      final cards = SqliteFlashcardRepository(database);
      final created = await cards.create(
        deckId: deck.id,
        question: 'ATP?',
        answer: 'Energy carrier',
      );
      final known = await cards.setMasteryStatus(
        id: created.id,
        status: MasteryStatus.known,
      );
      await database.close();
      database = AppDatabase(
        factory: databaseFactoryFfiNoIsolate,
        path: databasePath,
      );
      final model = StartupViewModel(() async {
        await database.database;
      });
      addTearDown(model.dispose);
      await model.initialize();
      expect(model.state, StartupState.ready);
      expect(await SqliteDeckRepository(database).getAll(), [deck]);
      expect(
        await SqliteFlashcardRepository(database).getById(known.id),
        known,
      );
      expect(
        await (await database.database).getVersion(),
        AppDatabase.schemaVersion,
      );
      expect(
        (await SqliteDeckRepository(database).getMasteryStats(deck.id))
            .percentage,
        100,
      );
    },
  );

  test('failed SQLite open can retry using the same database owner', () async {
    final blocker = await Directory(databasePath).create();
    final model = StartupViewModel(() async {
      await database.database;
    });
    addTearDown(model.dispose);
    await model.initialize();
    expect(model.state, StartupState.error);
    await blocker.delete();
    await model.initialize();
    expect(model.state, StartupState.ready);
    expect(await SqliteDeckRepository(database).getAll(), isEmpty);
  });

  test('startup failures and retries never recreate a database with a newer schema', () async {
    final future = await databaseFactoryFfiNoIsolate.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: AppDatabase.schemaVersion + 1,
        singleInstance: false,
        onCreate: (db, version) async {
          await db.execute('CREATE TABLE future_data (value TEXT)');
          await db.insert('future_data', {'value': 'Preserve this record'});
        },
      ),
    );
    await future.close();
    final model = StartupViewModel(() async {
      await database.database;
    });
    addTearDown(model.dispose);
    await model.initialize();
    await model.initialize();
    expect(model.state, StartupState.error);
    final unchanged = await databaseFactoryFfiNoIsolate.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    try {
      expect(await unchanged.getVersion(), AppDatabase.schemaVersion + 1);
      expect(
        (await unchanged.query('future_data')).single['value'],
        'Preserve this record',
      );
    } finally {
      await unchanged.close();
    }
  });
}
