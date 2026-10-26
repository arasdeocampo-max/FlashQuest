import 'dart:async';
import 'dart:io';

import 'package:flashquest_drill/data/local/app_database.dart';
import 'package:flashquest_drill/data/repositories/sqlite_deck_repository.dart';
import 'package:flashquest_drill/data/repositories/sqlite_flashcard_repository.dart';
import 'package:flashquest_drill/features/study/study_session.dart';
import 'package:flashquest_drill/features/study/study_view_model.dart';
import 'package:flashquest_drill/models/deck.dart';
import 'package:flashquest_drill/models/flashcard.dart';
import 'package:flashquest_drill/models/mastery_stats.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/controlled_repositories.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  late AppDatabase database;
  late ControlledDeckRepository decks;
  late ControlledFlashcardRepository cards;
  late Deck deck;
  late List<Flashcard> initialCards;

  setUp(() async {
    database = AppDatabase(
      factory: databaseFactoryFfiNoIsolate,
      path: inMemoryDatabasePath,
    );
    decks = ControlledDeckRepository(SqliteDeckRepository(database));
    cards = ControlledFlashcardRepository(SqliteFlashcardRepository(database));
    deck = await decks.delegate.create(title: 'Biology');
    initialCards = [];
    for (var index = 0; index < 3; index++) {
      initialCards.add(
        await cards.delegate.create(
          deckId: deck.id,
          question: 'Question $index',
          answer: 'Answer $index',
        ),
      );
    }
    initialCards[0] = await cards.delegate.setMasteryStatus(
      id: initialCards[0].id,
      status: MasteryStatus.known,
    );
  });

  tearDown(() => database.close());

  StudyViewModel modelFor([int? deckId]) {
    final model = StudyViewModel(
      deckId: deckId ?? deck.id,
      deckRepository: decks,
      flashcardRepository: cards,
    );
    addTearDown(() {
      if (!model.isDisposed) model.dispose();
    });
    return model;
  }

  Future<bool> choose(StudyViewModel model, StudyGrade grade) {
    model.revealAnswer(model.turn);
    return model.grade(grade, expectedTurn: model.turn);
  }

  test(
    'loads every card, including previously Known, into a fresh session',
    () async {
      final model = modelFor();
      await model.start();
      expect(model.state, StudyState.studying);
      expect(model.currentCard, initialCards.first);
      expect(model.totalCards, 3);
      expect(model.knownCount, 0);
      expect(model.reviewCount, 0);
      expect(model.isRevealed, isFalse);
      expect(cards.gradeCalls, 0);
    },
  );

  test(
    'coalesces pending starts and never restarts an active session',
    () async {
      final model = modelFor();
      final gate = Completer<void>();
      cards.readGate = gate.future;
      final first = model.start();
      final second = model.start();
      expect(identical(first, second), isTrue);
      gate.complete();
      await first;
      await choose(model, StudyGrade.known);
      await model.start();
      expect(cards.cardLoadCalls, 1);
      expect(model.turn, 1);
      expect(model.currentCard!.id, initialCards[1].id);
    },
  );

  test(
    'an entirely saved-Known deck is not an already-completed session',
    () async {
      for (final card in initialCards) {
        await cards.delegate.setMasteryStatus(
          id: card.id,
          status: MasteryStatus.known,
        );
      }
      final model = modelFor();
      await model.start();
      expect(model.state, StudyState.studying);
      expect(model.knownCount, 0);
      expect(model.remainingCards, 3);
      expect(model.finalMastery, isNull);
    },
  );

  test('grading before reveal and stale reveal callbacks do nothing', () async {
    final model = modelFor();
    await model.start();
    expect(await model.grade(StudyGrade.known, expectedTurn: 0), isFalse);
    model.revealAnswer(99);
    expect(model.isRevealed, isFalse);
    expect(cards.gradeCalls, 0);
  });

  test('Known and Review classifications commit before advancing', () async {
    final model = modelFor();
    await model.start();
    await choose(model, StudyGrade.review);
    expect(
      (await cards.delegate.getById(initialCards.first.id))!.status,
      MasteryStatus.review,
    );
    expect(model.currentCard!.id, initialCards[1].id);
    expect(model.isRevealed, isFalse);
    expect(model.reviewCount, 1);
    await choose(model, StudyGrade.known);
    expect(
      (await cards.delegate.getById(initialCards[1].id))!.status,
      MasteryStatus.known,
    );
    expect(model.knownCount, 1);
  });

  test('pending grading cannot advance or double-grade', () async {
    final model = modelFor();
    await model.start();
    model.revealAnswer(0);
    final gate = Completer<void>();
    cards.writeGate = gate.future;
    final pending = model.grade(StudyGrade.review, expectedTurn: 0);
    expect(model.isSaving, isTrue);
    expect(model.currentCard!.id, initialCards.first.id);
    expect(model.turn, 0);
    expect(await model.grade(StudyGrade.known, expectedTurn: 0), isFalse);
    expect(cards.gradeCalls, 1);
    gate.complete();
    expect(await pending, isTrue);
    expect(model.turn, 1);
    expect(model.isRevealed, isFalse);
  });

  test('an old grading callback cannot grade a newly revealed card', () async {
    final model = modelFor();
    await model.start();
    await choose(model, StudyGrade.known);
    model.revealAnswer(model.turn);
    expect(await model.grade(StudyGrade.known, expectedTurn: 0), isFalse);
    expect(cards.gradeCalls, 1);
    expect(model.turn, 1);
  });

  test(
    'failed writes retain the current answer, turn, queue, and saved mastery',
    () async {
      final model = modelFor();
      await model.start();
      cards.failWrites = true;
      expect(await choose(model, StudyGrade.review), isFalse);
      expect(model.turn, 0);
      expect(model.currentCard, initialCards.first);
      expect(model.isRevealed, isTrue);
      expect(model.reviewCount, 0);
      expect(model.isSaving, isFalse);
      expect(model.error, contains('hasn’t moved'));
      expect(model.error, isNot(contains('Private database')));
      expect(
        (await cards.delegate.getById(initialCards.first.id))!.status,
        MasteryStatus.known,
      );
      cards.failWrites = false;
      expect(await model.retryGrade(), isTrue);
      expect(model.turn, 1);
      expect(model.reviewCount, 1);
      expect(model.error, isNull);
      expect(
        (await cards.delegate.getById(initialCards.first.id))!.status,
        MasteryStatus.review,
      );
    },
  );

  test('retry grading is guarded while pending and after success', () async {
    final model = modelFor();
    await model.start();
    expect(await model.retryGrade(), isFalse);
    cards.failWrites = true;
    await choose(model, StudyGrade.known);
    cards.failWrites = false;
    final gate = Completer<void>();
    cards.writeGate = gate.future;
    final retry = model.retryGrade();
    expect(await model.retryGrade(), isFalse);
    gate.complete();
    expect(await retry, isTrue);
    expect(await model.retryGrade(), isFalse);
    expect(cards.gradeCalls, 2);
  });

  test(
    'multiple Review rounds preserve order and finish only when all are Known',
    () async {
      final model = modelFor();
      await model.start();
      await choose(model, StudyGrade.review);
      await choose(model, StudyGrade.known);
      await choose(model, StudyGrade.review);
      expect(model.state, StudyState.roundSummary);
      expect(model.retryRemaining(expectedRound: 1), isTrue);
      expect(model.round, 2);
      expect(model.reviewCount, 2);
      expect(model.currentCard!.id, initialCards[0].id);
      await choose(model, StudyGrade.known);
      expect(model.currentCard!.id, initialCards[2].id);
      await choose(model, StudyGrade.review);
      expect(model.state, StudyState.roundSummary);
      expect(model.retryRemaining(expectedRound: 2), isTrue);
      expect(model.round, 3);
      expect(model.reviewCount, 1);
      expect(model.state, StudyState.studying);
      await choose(model, StudyGrade.known);
      expect(model.state, StudyState.complete);
      expect(model.totalCards, 3);
      expect(model.finalMastery, MasteryStats(total: 3, known: 3));
      expect(model.finalMastery!.percentage, 100);
      expect(model.currentCard, isNull);
    },
  );

  test('empty Review Pile does not complete before ungraded cards', () async {
    final model = modelFor();
    await model.start();
    await choose(model, StudyGrade.known);
    expect(model.reviewCount, 0);
    expect(model.remainingCards, 2);
    expect(model.state, StudyState.studying);
    expect(model.finalMastery, isNull);
  });

  test(
    'skipping never writes SQLite, including previously Known cards',
    () async {
      final model = modelFor();
      await model.start();
      final saved = await cards.delegate.getByDeck(deck.id);
      for (var turn = 0; turn < 3; turn++) {
        expect(model.skip(expectedTurn: turn), isTrue);
      }
      expect(cards.gradeCalls, 0);
      expect(await cards.delegate.getByDeck(deck.id), saved);
      expect(model.state, StudyState.roundSummary);
      expect(model.currentCard, isNull);
      expect(model.knownCount, 0);
      expect(model.reviewCount, 0);
      expect(model.skippedCount, 3);
      expect(model.remainingCards, 3);
      expect(model.finalMastery, isNull);
      expect(model.skip(expectedTurn: 3), isFalse);
      expect(await choose(model, StudyGrade.known), isFalse);
      await model.start();
      expect(model.state, StudyState.roundSummary);
      expect(model.retryRemaining(expectedRound: 1), isTrue);
      expect(model.retryRemaining(expectedRound: 1), isFalse);
      expect(model.currentCard!.id, initialCards.first.id);
      expect(model.isRevealed, isFalse);
      expect(model.skip(expectedTurn: 0), isFalse);
      await choose(model, StudyGrade.known);
      await choose(model, StudyGrade.review);
      model.skip(expectedTurn: model.turn);
      expect(model.state, StudyState.roundSummary);
      expect(model.knownCount, 1);
      expect(model.reviewCount, 1);
      expect(model.skippedCount, 1);
      expect(model.remainingCards, 2);
      expect(model.retryRemaining(expectedRound: 2), isTrue);
      expect(model.currentCard!.id, initialCards[1].id);
      await choose(model, StudyGrade.known);
      expect(model.currentCard!.id, initialCards[2].id);
      await choose(model, StudyGrade.known);
      expect(model.state, StudyState.complete);
      expect(model.finalMastery, MasteryStats(total: 3, known: 3));
    },
  );

  test(
    'skip animation locks grades and rejects duplicate or stale starts',
    () async {
      final model = modelFor();
      await model.start();
      model.revealAnswer(0);
      expect(model.beginSkip(99), isFalse);
      expect(model.beginSkip(0), isTrue);
      expect(model.beginSkip(0), isFalse);
      expect(model.canGrade, isFalse);
      expect(await model.grade(StudyGrade.known, expectedTurn: 0), isFalse);
      expect(model.currentCard!.id, initialCards.first.id);
      expect(model.skip(expectedTurn: 0), isTrue);
      expect(model.skip(expectedTurn: 0), isFalse);
      expect(model.isSkipping, isFalse);
      expect(model.isRevealed, isFalse);
      expect(model.turn, 1);
      expect(cards.gradeCalls, 0);
    },
  );

  test(
    'pending and failed writes cannot be mistaken for a successful skip',
    () async {
      final model = modelFor();
      await model.start();
      final gate = Completer<void>();
      cards.writeGate = gate.future;
      cards.failWrites = true;
      final pending = choose(model, StudyGrade.review);
      expect(model.skip(expectedTurn: 0), isFalse);
      expect(model.beginSkip(0), isFalse);
      gate.complete();
      expect(await pending, isFalse);
      expect(model.turn, 0);
      expect(model.skippedCount, 0);
      expect(model.reviewCount, 0);
      expect(model.skip(expectedTurn: 0), isTrue);
      expect(model.canRetryGrade, isFalse);
      expect(model.error, isNull);
      expect(cards.gradeCalls, 1);
      expect(
        (await cards.delegate.getById(initialCards.first.id))!.status,
        MasteryStatus.known,
      );
    },
  );

  test(
    'exiting during skip does not advance or write after disposal',
    () async {
      final model = modelFor();
      await model.start();
      expect(model.beginSkip(0), isTrue);
      model.dispose();
      expect(model.skip(expectedTurn: 0), isFalse);
      expect(model.turn, 0);
      expect(cards.gradeCalls, 0);
    },
  );

  test(
    'single-card Review rounds reset reveal even though the ID is unchanged',
    () async {
      final single = await decks.delegate.create(title: 'One card');
      final card = await cards.delegate.create(
        deckId: single.id,
        question: 'Q',
        answer: 'A',
      );
      final model = modelFor(single.id);
      await model.start();
      await choose(model, StudyGrade.review);
      expect(model.state, StudyState.roundSummary);
      expect(model.retryRemaining(expectedRound: 1), isTrue);
      expect(model.round, 2);
      expect(model.currentCard!.id, card.id);
      expect(model.isRevealed, isFalse);
      expect(
        await model.grade(StudyGrade.known, expectedTurn: model.turn),
        isFalse,
      );
      await choose(model, StudyGrade.known);
      expect(model.state, StudyState.complete);
      expect(model.totalCards, 1);
    },
  );

  test(
    'final mastery is read from SQLite and read failure never regrades',
    () async {
      final model = modelFor();
      await model.start();
      await choose(model, StudyGrade.known);
      await choose(model, StudyGrade.known);
      decks.failReads = true;
      expect(await choose(model, StudyGrade.known), isTrue);
      expect(model.state, StudyState.completionError);
      expect(model.finalMastery, isNull);
      expect(model.error, contains('choices were saved'));
      expect(await model.retryGrade(), isFalse);
      expect(
        await decks.delegate.getMasteryStats(deck.id),
        MasteryStats(total: 3, known: 3),
      );
      decks.failReads = false;
      await model.retryCompletion();
      expect(model.state, StudyState.complete);
      expect(model.finalMastery, MasteryStats(total: 3, known: 3));
      expect(cards.gradeCalls, 3);
    },
  );

  test('completion waits for the final persisted mastery query', () async {
    final model = modelFor();
    await model.start();
    await choose(model, StudyGrade.known);
    await choose(model, StudyGrade.known);
    final gate = Completer<void>();
    decks.readGate = gate.future;
    final becameFinishing = Completer<void>();
    model.addListener(() {
      if (model.state == StudyState.finishing && !becameFinishing.isCompleted) {
        becameFinishing.complete();
      }
    });
    final finishing = choose(model, StudyGrade.known);
    // Let the real SQL write commit while the final read remains gated.
    await becameFinishing.future.timeout(const Duration(seconds: 5));
    expect(model.finalMastery, isNull);
    expect(model.isSaving, isTrue);
    expect(
      await model.grade(StudyGrade.known, expectedTurn: model.turn),
      isFalse,
    );
    gate.complete();
    await finishing;
    expect(model.state, StudyState.complete);
  });

  test('empty decks show an empty state, never a completion', () async {
    final empty = await decks.delegate.create(title: 'Empty');
    final model = modelFor(empty.id);
    await model.start();
    expect(model.state, StudyState.empty);
    expect(model.totalCards, 0);
    expect(model.finalMastery, isNull);
    expect(await choose(model, StudyGrade.known), isFalse);
  });

  test('missing decks and load failures are recoverable', () async {
    final missing = modelFor(999);
    await missing.start();
    expect(missing.state, StudyState.loadError);
    expect(missing.error, contains('no longer exists'));
    final model = modelFor();
    cards.failReads = true;
    await model.start();
    expect(model.state, StudyState.loadError);
    cards.failReads = false;
    await model.start();
    expect(model.state, StudyState.studying);
  });

  test(
    'early exit preserves choices and a new session includes the full deck',
    () async {
      final first = StudyViewModel(
        deckId: deck.id,
        deckRepository: decks,
        flashcardRepository: cards,
      );
      await first.start();
      await choose(first, StudyGrade.review);
      await choose(first, StudyGrade.known);
      first.dispose();
      expect(
        (await cards.delegate.getById(initialCards[0].id))!.status,
        MasteryStatus.review,
      );
      expect(
        (await cards.delegate.getById(initialCards[1].id))!.status,
        MasteryStatus.known,
      );
      final second = modelFor();
      await second.start();
      expect(second.turn, 0);
      expect(second.round, 1);
      expect(second.totalCards, 3);
      expect(second.currentCard!.id, initialCards.first.id);
      expect(second.knownCount, 0);
    },
  );

  test(
    'disposal during loading does not create or notify a late session',
    () async {
      final model = StudyViewModel(
        deckId: deck.id,
        deckRepository: decks,
        flashcardRepository: cards,
      );
      final gate = Completer<void>();
      cards.readGate = gate.future;
      var notifications = 0;
      model.addListener(() => notifications++);
      final loading = model.start();
      model.dispose();
      gate.complete();
      await loading;
      expect(notifications, 1);
      expect(model.currentCard, isNull);
    },
  );

  test('disposal during a write keeps its successful classification without notifying', () async {
    final model = StudyViewModel(
      deckId: deck.id,
      deckRepository: decks,
      flashcardRepository: cards,
    );
    await model.start();
    model.revealAnswer(model.turn);
    final gate = Completer<void>();
    cards.writeGate = gate.future;
    var notifications = 0;
    model.addListener(() => notifications++);
    final pending = model.grade(StudyGrade.review, expectedTurn: model.turn);
    model.dispose();
    gate.complete();
    expect(await pending, isTrue);
    expect(notifications, 1);
    expect(
      (await cards.delegate.getById(initialCards.first.id))!.status,
      MasteryStatus.review,
    );
  });

  test(
    'early-exit classifications survive closing and reopening the SQLite file',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'flashquest_study_test_',
      );
      final path = p.join(temporary.path, AppDatabase.fileName);
      var persistent = AppDatabase(
        factory: databaseFactoryFfiNoIsolate,
        path: path,
      );
      try {
        final savedDecks = SqliteDeckRepository(persistent);
        final savedCards = SqliteFlashcardRepository(persistent);
        final savedDeck = await savedDecks.create(title: 'Persistent study');
        final first = await savedCards.create(
          deckId: savedDeck.id,
          question: 'Q1',
          answer: 'A1',
        );
        final second = await savedCards.create(
          deckId: savedDeck.id,
          question: 'Q2',
          answer: 'A2',
        );
        final model = StudyViewModel(
          deckId: savedDeck.id,
          deckRepository: savedDecks,
          flashcardRepository: savedCards,
        );
        await model.start();
        await choose(model, StudyGrade.known);
        model.dispose();
        await persistent.close();
        persistent = AppDatabase(
          factory: databaseFactoryFfiNoIsolate,
          path: path,
        );
        final reopenedCards = SqliteFlashcardRepository(persistent);
        expect(
          (await reopenedCards.getById(first.id))!.status,
          MasteryStatus.known,
        );
        expect(
          (await reopenedCards.getById(second.id))!.status,
          MasteryStatus.review,
        );
        final next = StudyViewModel(
          deckId: savedDeck.id,
          deckRepository: SqliteDeckRepository(persistent),
          flashcardRepository: reopenedCards,
        );
        await next.start();
        expect(next.totalCards, 2);
        expect(next.currentCard!.id, first.id);
        expect(next.isRevealed, isFalse);
        next.dispose();
      } finally {
        await persistent.close();
        await temporary.delete(recursive: true);
      }
    },
  );
}
