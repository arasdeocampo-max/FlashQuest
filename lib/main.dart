import 'package:flutter/material.dart';

import 'app.dart';
import 'data/local/app_database.dart';
import 'data/repositories/sqlite_deck_repository.dart';
import 'data/repositories/sqlite_flashcard_repository.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // One connection and the same repositories live for the application process.
  // Render the Flutter splash before opening; failures can retry the same
  // database owner without changing its path or existing records.
  final database = AppDatabase();
  runApp(
    FlashQuestApp(
      initialize: () async {
        await database.database;
      },
      deckRepository: SqliteDeckRepository(database),
      flashcardRepository: SqliteFlashcardRepository(database),
    ),
  );
}
