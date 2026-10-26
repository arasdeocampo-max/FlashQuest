import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'features/decks/deck_list_screen.dart';
import 'features/startup/startup_screen.dart';
import 'features/startup/startup_view_model.dart';
import 'repositories/deck_repository.dart';
import 'repositories/flashcard_repository.dart';

class FlashQuestApp extends StatelessWidget {
  const FlashQuestApp({
    super.key,
    required this.deckRepository,
    required this.flashcardRepository,
    this.initialize,
  });

  final DeckRepository deckRepository;
  final FlashcardRepository flashcardRepository;

  /// Production opens the shared SQLite connection here. Injected repositories
  /// may already be ready, in which case no additional initialization is needed.
  final AppInitializer? initialize;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'FlashQuest',
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    home: StartupScreen(
      initialize: initialize ?? _alreadyInitialized,
      dashboard: DeckListScreen(
        deckRepository: deckRepository,
        flashcardRepository: flashcardRepository,
      ),
    ),
  );
}

Future<void> _alreadyInitialized() async {}
