import 'dart:async';

import 'package:flashquest_drill/data/local/app_database.dart';
import 'package:flashquest_drill/data/repositories/sqlite_deck_repository.dart';
import 'package:flashquest_drill/data/repositories/sqlite_flashcard_repository.dart';
import 'package:flashquest_drill/features/decks/deck_detail_view_model.dart';
import 'package:flashquest_drill/features/decks/deck_editor_view_model.dart';
import 'package:flashquest_drill/features/decks/deck_list_view_model.dart';
import 'package:flashquest_drill/features/flashcards/flashcard_editor_view_model.dart';
import 'package:flashquest_drill/models/deck.dart';
import 'package:flashquest_drill/models/flashcard.dart';
import 'package:flashquest_drill/models/mastery_stats.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/controlled_repositories.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  late AppDatabase database;
  late ControlledDeckRepository decks;
  late ControlledFlashcardRepository cards;
  late Deck deck;
  late Flashcard known;

  setUp(() async {
    database = AppDatabase(
      factory: databaseFactoryFfiNoIsolate,
      path: inMemoryDatabasePath,
    );
    decks = ControlledDeckRepository(SqliteDeckRepository(database));
    cards = ControlledFlashcardRepository(SqliteFlashcardRepository(database));
    deck = await decks.delegate.create(title: 'Biology');
    final first = await cards.delegate.create(
      deckId: deck.id,
      question: 'Cell boundary?',
      answer: 'Membrane',
    );
    known = await cards.delegate.setMasteryStatus(
      id: first.id,
      status: MasteryStatus.known,
    );
    await cards.delegate.create(
      deckId: deck.id,
      question: 'Genetic material?',
      answer: 'DNA',
    );
  });

  tearDown(() => database.close());

  DeckDetailViewModel detailModel({int? deckId}) => DeckDetailViewModel(
    deckId: deckId ?? deck.id,
    deckRepository: decks,
    flashcardRepository: cards,
  );

  group('Dashboard view model', () {
    test('loads persisted decks, counts, and mastery', () async {
      final model = DeckListViewModel(decks);
      addTearDown(model.dispose);

      await model.load();

      expect(model.decks, [deck]);
      expect(model.mastery[deck.id], MasteryStats(total: 2, known: 1));
      expect(model.totalCards, 2);
      expect(model.isBusy, isFalse);
      expect(model.error, isNull);
    });

    test('coalesces overlapping refresh requests', () async {
      final model = DeckListViewModel(decks);
      addTearDown(model.dispose);
      final gate = Completer<void>();
      decks.readGate = gate.future;

      final first = model.load();
      final second = model.load();
      expect(identical(first, second), isTrue);
      expect(model.isLoading, isTrue);
      expect(decks.loadCalls, 1);
      gate.complete();
      await Future.wait([first, second]);
      expect(model.decks, [deck]);
    });

    test('load failure is readable and retry recovers', () async {
      final model = DeckListViewModel(decks);
      addTearDown(model.dispose);
      decks.failReads = true;
      await model.load();
      expect(model.error, contains('try again'));
      expect(model.error, isNot(contains('Private database')));
      expect(model.isLoading, isFalse);

      decks.failReads = false;
      await model.load();
      expect(model.error, isNull);
      expect(model.decks, [deck]);
    });

    test('deletes once while pending and refreshes saved data', () async {
      final model = DeckListViewModel(decks);
      addTearDown(model.dispose);
      await model.load();
      final gate = Completer<void>();
      decks.writeGate = gate.future;

      final pending = model.deleteDeck(deck.id);
      expect(await model.deleteDeck(deck.id), isFalse);
      expect(decks.deleteCalls, 1);
      await model.load();
      expect(decks.loadCalls, 1);
      gate.complete();
      expect(await pending, isTrue);
      expect(model.decks, isEmpty);
      expect(model.mastery, isEmpty);
      expect(decks.loadCalls, 2);
    });

    test('failed deletion preserves data and clears busy state', () async {
      final model = DeckListViewModel(decks);
      addTearDown(model.dispose);
      await model.load();
      decks.failWrites = true;

      expect(await model.deleteDeck(deck.id), isFalse);
      expect(await decks.delegate.getById(deck.id), deck);
      expect(model.error, isNull);
      expect(model.deletionError, contains('delete this deck'));
      expect(model.isBusy, isFalse);
    });

    test('late refresh completion never notifies a disposed model', () async {
      final model = DeckListViewModel(decks);
      final gate = Completer<void>();
      decks.readGate = gate.future;
      var notifications = 0;
      model.addListener(() => notifications++);
      final pending = model.load();
      expect(notifications, 1);
      model.dispose();
      gate.complete();
      await pending;
      expect(notifications, 1);
      await model.load();
      expect(decks.loadCalls, 1);
    });
  });

  group('Deck details view model', () {
    test('reset refreshes mastery and preserves the entire deck', () async {
      final model = detailModel();
      addTearDown(model.dispose);
      await model.load();
      expect(model.canStudyAgain, isTrue);
      expect(await model.resetMastery(), isTrue);
      expect(decks.resetCalls, 1);
      expect(model.mastery, MasteryStats(total: 2, known: 0));
      expect(model.cards, hasLength(2));
      expect(model.deck, deck);
      expect(model.canStudyAgain, isFalse);
      expect(model.isBusy, isFalse);
    });

    test(
      'pending reset blocks duplicate resets, deletes and stale reloads',
      () async {
        final model = detailModel();
        addTearDown(model.dispose);
        await model.load();
        final gate = Completer<void>();
        decks.writeGate = gate.future;
        final pending = model.resetMastery();
        expect(model.isResetting, isTrue);
        expect(model.mastery!.known, 1);
        expect(await model.resetMastery(), isFalse);
        expect(await model.deleteDeck(), isFalse);
        expect(await model.deleteCard(known.id), isFalse);
        await model.load();
        expect(decks.resetCalls, 1);
        expect(decks.deleteCalls, 0);
        expect(cards.deleteCalls, 0);
        gate.complete();
        expect(await pending, isTrue);
        expect(model.mastery!.known, 0);
      },
    );

    test(
      'failed reset retains all progress and permits an explicit retry',
      () async {
        final model = detailModel();
        addTearDown(model.dispose);
        await model.load();
        final before = model.cards;
        decks.failWrites = true;
        expect(await model.resetMastery(), isFalse);
        expect(model.resetError, contains('progress is unchanged'));
        expect(model.cards, before);
        expect(model.mastery!.known, 1);
        expect(await cards.delegate.getById(known.id), known);
        expect(model.canStudyAgain, isTrue);
        decks.failWrites = false;
        expect(await model.resetMastery(), isTrue);
      },
    );

    test('no-progress and empty decks cannot request a reset', () async {
      await decks.delegate.resetMastery(deck.id);
      final model = detailModel();
      addTearDown(model.dispose);
      await model.load();
      expect(model.canStudyAgain, isFalse);
      expect(await model.resetMastery(), isFalse);
      final empty = await decks.delegate.create(title: 'Empty');
      final emptyModel = detailModel(deckId: empty.id);
      addTearDown(emptyModel.dispose);
      await emptyModel.load();
      expect(emptyModel.canStudyAgain, isFalse);
      expect(await emptyModel.resetMastery(), isFalse);
      expect(decks.resetCalls, 0);
    });

    test('disposing during reset preserves its commit without navigation permission', () async {
      final model = detailModel();
      await model.load();
      final gate = Completer<void>();
      decks.writeGate = gate.future;
      final pending = model.resetMastery();
      model.dispose();
      gate.complete();
      expect(await pending, isFalse);
      expect(
        await decks.delegate.getMasteryStats(deck.id),
        MasteryStats(total: 2, known: 0),
      );
    });

    test('loads all cards independently of saved mastery', () async {
      final model = detailModel();
      addTearDown(model.dispose);
      await model.load();

      expect(model.deck, deck);
      expect(model.cards.map((card) => card.status), [
        MasteryStatus.known,
        MasteryStatus.review,
      ]);
      expect(model.mastery, MasteryStats(total: 2, known: 1));
    });

    test('deleting a card refreshes cards and saved mastery', () async {
      final model = detailModel();
      addTearDown(model.dispose);
      await model.load();

      expect(await model.deleteCard(known.id), isTrue);
      expect(model.cards, hasLength(1));
      expect(model.mastery, MasteryStats(total: 1, known: 0));
    });

    test('rejects duplicate pending card deletions', () async {
      final model = detailModel();
      addTearDown(model.dispose);
      await model.load();
      final gate = Completer<void>();
      cards.writeGate = gate.future;

      final pending = model.deleteCard(known.id);
      expect(await model.deleteCard(known.id), isFalse);
      expect(cards.deleteCalls, 1);
      gate.complete();
      expect(await pending, isTrue);
    });

    test('reports failed deletion without changing saved content', () async {
      final model = detailModel();
      addTearDown(model.dispose);
      await model.load();
      cards.failWrites = true;

      expect(await model.deleteCard(known.id), isFalse);
      expect(await cards.delegate.getById(known.id), known);
      expect(model.error, isNull);
      expect(model.deletionError, contains('delete this flashcard'));
      expect(model.isBusy, isFalse);
    });

    test('missing decks give a recovery message', () async {
      final model = detailModel(deckId: 999);
      addTearDown(model.dispose);
      await model.load();

      expect(model.deck, isNull);
      expect(model.error, contains('no longer exists'));
      expect(model.isLoading, isFalse);
    });

    test(
      'deck deletion is guarded and cascades through repositories',
      () async {
        final model = detailModel();
        addTearDown(model.dispose);
        await model.load();
        final gate = Completer<void>();
        decks.writeGate = gate.future;
        final pending = model.deleteDeck();
        expect(await model.deleteDeck(), isFalse);
        expect(decks.deleteCalls, 1);
        gate.complete();

        expect(await pending, isTrue);
        expect(await cards.getByDeck(deck.id), isEmpty);
      },
    );

    test('failed deck deletion is recoverable', () async {
      final model = detailModel();
      addTearDown(model.dispose);
      decks.failWrites = true;
      expect(await model.deleteDeck(), isFalse);
      expect(model.isBusy, isFalse);
      expect(model.error, isNull);
      expect(model.deletionError, isNotNull);
      expect(await decks.delegate.getById(deck.id), deck);
    });

    test('disposal during a load is safe', () async {
      final model = detailModel();
      final gate = Completer<void>();
      cards.readGate = gate.future;
      final pending = model.load();
      model.dispose();
      gate.complete();
      await pending;
      expect(model.deck, isNull);
    });
  });

  group('Deck editor view model', () {
    test('validation blocks blank titles before a repository call', () async {
      final model = DeckEditorViewModel(decks);
      addTearDown(model.dispose);
      expect(await model.save(' \n '), isFalse);
      expect(model.titleError, isNotNull);
      expect(decks.createCalls, 0);
      expect(model.isSaving, isFalse);
    });

    test(
      'pending and completed submissions cannot create duplicates',
      () async {
        final model = DeckEditorViewModel(decks);
        addTearDown(model.dispose);
        final gate = Completer<void>();
        decks.writeGate = gate.future;
        final pending = model.save('Chemistry');

        expect(model.isSaving, isTrue);
        expect(await model.save('Chemistry'), isFalse);
        gate.complete();
        expect(await pending, isTrue);
        expect(await model.save('Chemistry'), isFalse);
        expect(decks.createCalls, 1);
      },
    );

    test('editing updates the existing deck instead of creating one', () async {
      final model = DeckEditorViewModel(decks, initialDeck: deck);
      addTearDown(model.dispose);
      expect(await model.save('Science'), isTrue);
      expect(decks.updateCalls, 1);
      expect(decks.createCalls, 0);
      expect((await decks.getById(deck.id))!.title, 'Science');
    });

    test('save failures allow retry without leaking SQL diagnostics', () async {
      final model = DeckEditorViewModel(decks);
      addTearDown(model.dispose);
      decks.failWrites = true;
      expect(await model.save('Chemistry'), isFalse);
      expect(model.isSaving, isFalse);
      expect(model.error, isNot(contains('Private database')));
      decks.failWrites = false;
      expect(await model.save('Chemistry'), isTrue);
    });

    test('disposing during a save prevents late notifications', () async {
      final model = DeckEditorViewModel(decks);
      final gate = Completer<void>();
      decks.writeGate = gate.future;
      final pending = model.save('Chemistry');
      model.dispose();
      gate.complete();
      expect(await pending, isTrue);
      expect(await model.save('More'), isFalse);
    });
  });

  group('Flashcard editor view model', () {
    test('validates both required fields', () async {
      final model = FlashcardEditorViewModel(cards, deckId: deck.id);
      addTearDown(model.dispose);
      expect(await model.save(question: ' ', answer: '\n'), isFalse);
      expect(model.questionError, isNotNull);
      expect(model.answerError, isNotNull);
      expect(cards.createCalls, 0);
    });

    test('new cards save to the selected deck in Review', () async {
      final model = FlashcardEditorViewModel(cards, deckId: deck.id);
      addTearDown(model.dispose);
      expect(
        await model.save(question: ' ATP? ', answer: ' Energy carrier '),
        isTrue,
      );
      final saved = (await cards.getByDeck(deck.id)).last;
      expect(saved.question, 'ATP?');
      expect(saved.status, MasteryStatus.review);
    });

    test(
      'editing content resets saved mastery through the repository',
      () async {
        final model = FlashcardEditorViewModel(
          cards,
          deckId: deck.id,
          initialCard: known,
        );
        addTearDown(model.dispose);
        expect(
          await model.save(question: 'Changed question', answer: known.answer),
          isTrue,
        );
        expect(cards.updateCalls, 1);
        expect(cards.createCalls, 0);
        expect((await cards.getById(known.id))!.status, MasteryStatus.review);
      },
    );

    test('unchanged saves preserve the existing classification', () async {
      final model = FlashcardEditorViewModel(
        cards,
        deckId: deck.id,
        initialCard: known,
      );
      addTearDown(model.dispose);
      expect(
        await model.save(question: known.question, answer: known.answer),
        isTrue,
      );
      expect((await cards.getById(known.id))!.status, MasteryStatus.known);
    });

    test('pending and completed saves cannot create duplicate cards', () async {
      final model = FlashcardEditorViewModel(cards, deckId: deck.id);
      addTearDown(model.dispose);
      final gate = Completer<void>();
      cards.writeGate = gate.future;
      final pending = model.save(question: 'Q', answer: 'A');
      expect(await model.save(question: 'Q', answer: 'A'), isFalse);
      gate.complete();
      expect(await pending, isTrue);
      expect(await model.save(question: 'Q', answer: 'A'), isFalse);
      expect(cards.createCalls, 1);
    });

    test('write failures are recoverable', () async {
      final model = FlashcardEditorViewModel(cards, deckId: deck.id);
      addTearDown(model.dispose);
      cards.failWrites = true;
      expect(await model.save(question: 'Q', answer: 'A'), isFalse);
      expect(model.isSaving, isFalse);
      expect(model.error, contains('try again'));
      cards.failWrites = false;
      expect(await model.save(question: 'Q', answer: 'A'), isTrue);
    });

    test('saving a deleted card gives a useful missing-card message', () async {
      final model = FlashcardEditorViewModel(
        cards,
        deckId: deck.id,
        initialCard: known,
      );
      addTearDown(model.dispose);
      await cards.delegate.delete(known.id);
      expect(await model.save(question: 'Q', answer: 'A'), isFalse);
      expect(model.error, contains('no longer exists'));
    });

    test('disposing during a save is safe', () async {
      final model = FlashcardEditorViewModel(cards, deckId: deck.id);
      final gate = Completer<void>();
      cards.writeGate = gate.future;
      final pending = model.save(question: 'Q', answer: 'A');
      model.dispose();
      gate.complete();
      expect(await pending, isTrue);
    });
  });
}
