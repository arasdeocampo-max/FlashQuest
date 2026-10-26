import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../repositories/repository_exception.dart';

/// Own one instance for the app and inject it into both SQLite repositories.
/// Opening is lazy and shared by concurrent callers. No network is involved.
final class AppDatabase {
  AppDatabase({DatabaseFactory? factory, String? path})
    : _factory = factory ?? databaseFactory,
      _pathOverride = path;

  static const schemaVersion = 1;
  static const fileName = 'flashquest_drill.db';

  final DatabaseFactory _factory;
  final String? _pathOverride;
  Future<Database>? _opening;
  Future<void>? _closing;
  bool _isClosed = false;

  Future<Database> get database async {
    if (_isClosed) {
      throw const StorageException('The local database has been closed.');
    }
    final opening = _opening ??= _open();
    try {
      return await opening;
    } catch (_) {
      // An unsuccessful open must not permanently cache a failed Future.
      if (identical(_opening, opening)) _opening = null;
      rethrow;
    }
  }

  Future<Database> _open() async {
    try {
      final path =
          _pathOverride ?? p.join(await _factory.getDatabasesPath(), fileName);
      return await _factory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: schemaVersion,
          // This object owns its connection; avoid a hidden global connection.
          singleInstance: false,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, version) => _migrate(db, 0, version),
          onUpgrade: _migrate,
          onDowngrade: (db, oldVersion, newVersion) async {
            throw StorageException(
              'The local database requires a newer version of FlashQuest Drill.',
            );
          },
        ),
      );
    } on RepositoryException {
      rethrow;
    } on Exception catch (error) {
      throw StorageException(
        'Could not open the local database.',
        cause: error,
      );
    }
  }

  // sqflite already runs creation and upgrade callbacks inside a transaction.
  static Future<void> _migrate(Database db, int from, int to) async {
    for (var version = from + 1; version <= to; version++) {
      switch (version) {
        case 1:
          await db.execute('''
            CREATE TABLE decks (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              title TEXT NOT NULL CHECK(length(trim(title)) > 0),
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE flashcards (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              deck_id INTEGER NOT NULL REFERENCES decks(id) ON DELETE CASCADE,
              question TEXT NOT NULL CHECK(length(trim(question)) > 0),
              answer TEXT NOT NULL CHECK(length(trim(answer)) > 0),
              status TEXT NOT NULL DEFAULT 'review'
                CHECK(status IN ('review', 'known')),
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE INDEX idx_decks_title ON decks(title COLLATE NOCASE, id)
          ''');
          await db.execute('''
            CREATE INDEX idx_flashcards_deck_status
              ON flashcards(deck_id, status)
          ''');
        default:
          throw StorageException('Missing local database migration $version.');
      }
    }
  }

  /// Keeps platform/SQL details out of the repository's error contract.
  Future<T> run<T>(
    String operation,
    Future<T> Function(Database db) action,
  ) async {
    try {
      return await action(await database);
    } on DatabaseException catch (error) {
      throw StorageException('Could not $operation.', cause: error);
    } on PlatformException catch (error) {
      throw StorageException('Could not $operation.', cause: error);
    }
  }

  /// Idempotent. Create a new AppDatabase instance to reopen after closing.
  Future<void> close() {
    _isClosed = true;
    return _closing ??= _close();
  }

  Future<void> _close() async {
    final opening = _opening;
    if (opening == null) return;
    try {
      final db = await opening;
      await db.close();
    } on RepositoryException {
      rethrow;
    } on Exception catch (error) {
      throw StorageException(
        'Could not close the local database.',
        cause: error,
      );
    }
  }
}
