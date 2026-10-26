import 'package:flashquest_drill/data/local/app_database.dart';
import 'package:flashquest_drill/data/repositories/sqlite_deck_repository.dart';
import 'package:flashquest_drill/data/repositories/sqlite_flashcard_repository.dart';
import 'package:flashquest_drill/models/deck.dart';
import 'package:flashquest_drill/models/flashcard.dart';
import 'package:flashquest_drill/models/mastery_stats.dart';
import 'package:flashquest_drill/repositories/deck_repository.dart';
import 'package:flashquest_drill/repositories/flashcard_repository.dart';
import 'package:flashquest_drill/repositories/repository_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late AppDatabase database;
  late DeckRepository decks;
  late FlashcardRepository cards;
  late Deck deck;

  setUp(() async {
    database = AppDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    decks = SqliteDeckRepository(database);
    cards = SqliteFlashcardRepository(database);
    deck = await decks.create(title: 'Biology');
  });

  tearDown(() => database.close());

  Future<Flashcard> createCard({int? deckId}) => cards.create(
    deckId: deckId ?? deck.id,
    question: 'What carries genetic information?',
    answer: 'DNA',
  );

  group('Deck mastery reset', () {
    test(
      'resets only selected mastery and preserves decks and card content',
      () async {
        final first = await createCard();
        await cards.setMasteryStatus(id: first.id, status: MasteryStatus.known);
        final review = await createCard();
        final otherDeck = await decks.create(title: 'Other');
        final other = await createCard(deckId: otherDeck.id);
        final otherKnown = await cards.setMasteryStatus(
          id: other.id,
          status: MasteryStatus.known,
        );
        final before = await cards.getByDeck(deck.id);

        await decks.resetMastery(deck.id);

        final after = await cards.getByDeck(deck.id);
        expect(
          after.map((card) => card.status),
          everyElement(MasteryStatus.review),
        );
        expect(
          await decks.getMasteryStats(deck.id),
          MasteryStats(total: 2, known: 0),
        );
        expect(await decks.getById(deck.id), deck);
        expect(await cards.getById(other.id), otherKnown);
        expect(await cards.getById(review.id), review);
        for (var index = 0; index < before.length; index++) {
          expect(after[index].id, before[index].id);
          expect(after[index].deckId, before[index].deckId);
          expect(after[index].question, before[index].question);
          expect(after[index].answer, before[index].answer);
          expect(after[index].createdAt, before[index].createdAt);
        }
        await decks.resetMastery(deck.id);
        expect(await cards.getByDeck(deck.id), after);
        expect(await decks.getAll(), hasLength(2));
      },
    );

    test('any failed row update rolls back the entire reset', () async {
      final first = await createCard();
      final second = await createCard();
      for (final card in [first, second]) {
        await cards.setMasteryStatus(id: card.id, status: MasteryStatus.known);
      }
      final before = await cards.getByDeck(deck.id);
      final db = await database.database;
      await db.execute('''
        CREATE TRIGGER reject_mastery_reset BEFORE UPDATE ON flashcards
        WHEN OLD.id = ${second.id}
        BEGIN SELECT RAISE(ABORT, 'Simulated reset failure'); END
      ''');

      await expectLater(
        decks.resetMastery(deck.id),
        throwsA(isA<StorageException>()),
      );

      expect(await cards.getByDeck(deck.id), before);
      expect(await decks.getById(deck.id), deck);
      expect(
        await decks.getMasteryStats(deck.id),
        MasteryStats(total: 2, known: 2),
      );
    });

    test('empty decks are safe and missing decks report not found', () async {
      await decks.resetMastery(deck.id);
      expect(await decks.getById(deck.id), deck);
      expect(
        await decks.getMasteryStats(deck.id),
        MasteryStats(total: 0, known: 0),
      );
      await expectLater(
        decks.resetMastery(99999),
        throwsA(isA<RecordNotFoundException>()),
      );
    });
  });

  group('Deck CRUD', () {
    test('creates, trims, retrieves, and alphabetically lists decks', () async {
      final second = await decks.create(title: '  algebra  ');

      expect(second.id, isNot(deck.id));
      expect(second.title, 'algebra');
      expect(second.createdAt.isUtc, isTrue);
      expect(second.updatedAt, second.createdAt);
      expect(await decks.getById(second.id), second);
      expect(await decks.getAll(), [second, deck]);
      expect(await decks.getById(9999), isNull);
    });

    test('renaming preserves creation time and card mastery', () async {
      final card = await createCard();
      await cards.setMasteryStatus(id: card.id, status: MasteryStatus.known);

      final renamed = await decks.update(id: deck.id, title: '  Science  ');

      expect(renamed.id, deck.id);
      expect(renamed.title, 'Science');
      expect(renamed.createdAt, deck.createdAt);
      expect(renamed.updatedAt.isBefore(deck.updatedAt), isFalse);
      expect(await decks.getById(deck.id), renamed);
      expect((await cards.getById(card.id))!.status, MasteryStatus.known);
    });

    test('rejects blank titles without changing data', () async {
      await expectLater(decks.create(title: '\n\t '), throwsArgumentError);
      await expectLater(
        decks.update(id: deck.id, title: ' '),
        throwsArgumentError,
      );

      expect(await decks.getAll(), [deck]);
    });

    test('updating a missing deck reports not found', () async {
      await expectLater(
        decks.update(id: 9999, title: 'Missing'),
        throwsA(isA<RecordNotFoundException>()),
      );
    });

    test('deleting a deck cascades only to its own cards', () async {
      final card = await createCard();
      final otherDeck = await decks.create(title: 'Other');
      final otherCard = await createCard(deckId: otherDeck.id);

      expect(await decks.delete(deck.id), isTrue);

      expect(await decks.getById(deck.id), isNull);
      expect(await cards.getById(card.id), isNull);
      expect(await cards.getByDeck(deck.id), isEmpty);
      expect(await cards.getById(otherCard.id), otherCard);
      expect(await decks.delete(deck.id), isFalse);
    });

    test('a failed cascade rolls back both deck and card deletion', () async {
      final card = await createCard();
      final db = await database.database;
      await db.execute('''
        CREATE TRIGGER reject_card_deletion BEFORE DELETE ON flashcards
        BEGIN SELECT RAISE(ABORT, 'Simulated delete failure'); END
      ''');

      await expectLater(
        decks.delete(deck.id),
        throwsA(isA<StorageException>()),
      );

      expect(await decks.getById(deck.id), deck);
      expect(await cards.getById(card.id), card);
    });

    test('IDs are not reused after deleting a deck', () async {
      await decks.delete(deck.id);
      final replacement = await decks.create(title: 'Replacement');

      expect(replacement.id, greaterThan(deck.id));
    });
  });

  group('Flashcard CRUD', () {
    test('new cards are trimmed, saved in Review, and readable', () async {
      final card = await cards.create(
        deckId: deck.id,
        question: '  Question?\nMore detail  ',
        answer: '  Answer  ',
      );

      expect(card.deckId, deck.id);
      expect(card.question, 'Question?\nMore detail');
      expect(card.answer, 'Answer');
      expect(card.status, MasteryStatus.review);
      expect(card.createdAt.isUtc, isTrue);
      expect(card.updatedAt, card.createdAt);
      expect(await cards.getById(card.id), card);
      expect(await cards.getById(9999), isNull);
    });

    test(
      'retrieval includes Known and Review cards in creation order',
      () async {
        final first = await createCard();
        final second = await createCard();
        final known = await cards.setMasteryStatus(
          id: first.id,
          status: MasteryStatus.known,
        );
        final otherDeck = await decks.create(title: 'Other');
        await createCard(deckId: otherDeck.id);

        expect(await cards.getByDeck(deck.id), [known, second]);
        expect(await cards.getByDeck(9999), isEmpty);
      },
    );

    test('rejects cards belonging to a missing deck', () async {
      await expectLater(
        createCard(deckId: 9999),
        throwsA(isA<RecordNotFoundException>()),
      );

      expect(await cards.getByDeck(deck.id), isEmpty);
    });

    test('rejects empty questions and answers on create and edit', () async {
      final card = await createCard();
      for (final content in [
        (question: ' \n\t', answer: 'Answer'),
        (question: 'Question', answer: ' '),
      ]) {
        await expectLater(
          cards.create(
            deckId: deck.id,
            question: content.question,
            answer: content.answer,
          ),
          throwsArgumentError,
        );
        await expectLater(
          cards.updateContent(
            id: card.id,
            question: content.question,
            answer: content.answer,
          ),
          throwsArgumentError,
        );
      }

      expect(await cards.getByDeck(deck.id), [card]);
    });

    for (final changeQuestion in [true, false]) {
      test(
        'changing ${changeQuestion ? 'question' : 'answer'} resets Known to Review',
        () async {
          final card = await createCard();
          await cards.setMasteryStatus(
            id: card.id,
            status: MasteryStatus.known,
          );

          final edited = await cards.updateContent(
            id: card.id,
            question: changeQuestion ? 'Edited question' : card.question,
            answer: changeQuestion ? card.answer : 'Edited answer',
          );

          expect(edited.status, MasteryStatus.review);
          expect(edited.createdAt, card.createdAt);
          expect(edited.deckId, card.deckId);
          expect(await cards.getById(card.id), edited);
          expect(
            await decks.getMasteryStats(deck.id),
            MasteryStats(total: 1, known: 0),
          );
        },
      );
    }

    test('saving unchanged normalized content preserves mastery', () async {
      final card = await createCard();
      final known = await cards.setMasteryStatus(
        id: card.id,
        status: MasteryStatus.known,
      );

      final unchanged = await cards.updateContent(
        id: card.id,
        question: ' ${card.question} ',
        answer: '\n${card.answer}\t',
      );

      expect(unchanged, known);
      expect(await cards.getById(card.id), known);
    });

    test('saves explicit Known and Review classifications', () async {
      final card = await createCard();
      for (final status in [MasteryStatus.known, MasteryStatus.review]) {
        final graded = await cards.setMasteryStatus(
          id: card.id,
          status: status,
        );

        expect(graded.status, status);
        expect(graded.question, card.question);
        expect(graded.answer, card.answer);
        expect(graded.createdAt, card.createdAt);
        expect(await cards.getById(card.id), graded);
      }
    });

    test('editing and grading missing cards report not found', () async {
      await expectLater(
        cards.updateContent(id: 9999, question: 'Q', answer: 'A'),
        throwsA(isA<RecordNotFoundException>()),
      );
      await expectLater(
        cards.setMasteryStatus(id: 9999, status: MasteryStatus.known),
        throwsA(isA<RecordNotFoundException>()),
      );
    });

    test(
      'failed grading reports storage failure and preserves saved mastery',
      () async {
        final card = await createCard();
        final db = await database.database;
        await db.execute('''
        CREATE TRIGGER reject_grading BEFORE UPDATE OF status ON flashcards
        BEGIN SELECT RAISE(ABORT, 'Simulated write failure'); END
      ''');

        await expectLater(
          cards.setMasteryStatus(id: card.id, status: MasteryStatus.known),
          throwsA(
            isA<StorageException>().having(
              (error) => error.cause,
              'cause',
              isA<DatabaseException>(),
            ),
          ),
        );

        expect(await cards.getById(card.id), card);
        expect(
          await decks.getMasteryStats(deck.id),
          MasteryStats(total: 1, known: 0),
        );
      },
    );

    test(
      'failed editing does not partially update content or mastery',
      () async {
        final card = await createCard();
        final known = await cards.setMasteryStatus(
          id: card.id,
          status: MasteryStatus.known,
        );
        final db = await database.database;
        await db.execute('''
        CREATE TRIGGER reject_editing BEFORE UPDATE ON flashcards
        BEGIN SELECT RAISE(ABORT, 'Simulated edit failure'); END
      ''');

        await expectLater(
          cards.updateContent(
            id: card.id,
            question: 'Changed',
            answer: 'Changed',
          ),
          throwsA(isA<StorageException>()),
        );

        expect(await cards.getById(card.id), known);
      },
    );

    test('deleting a card preserves its deck and siblings', () async {
      final first = await createCard();
      final second = await createCard();

      expect(await cards.delete(first.id), isTrue);

      expect(await cards.getById(first.id), isNull);
      expect(await cards.getByDeck(deck.id), [second]);
      expect(await decks.getById(deck.id), deck);
      expect(await cards.delete(first.id), isFalse);
    });

    test(
      'parameter binding preserves quotes, Unicode, and SQL-like text',
      () async {
        const question = "What's 学習? '; DROP TABLE decks; --";
        final card = await cards.create(
          deckId: deck.id,
          question: question,
          answer: 'Study 🧠',
        );

        expect((await cards.getById(card.id))!.question, question);
        expect((await cards.getById(card.id))!.answer, 'Study 🧠');
        expect(await decks.getById(deck.id), deck);
      },
    );
  });

  group('Mastery queries', () {
    test('empty decks have zero counts and mastery', () async {
      final stats = await decks.getMasteryStats(deck.id);

      expect(stats, MasteryStats(total: 0, known: 0));
      expect(stats.review, 0);
      expect(stats.percentage, 0);
    });

    test('reflect grading, editing, creation, and deletion without cached counters', () async {
      final first = await createCard();
      final second = await createCard();
      await cards.setMasteryStatus(id: first.id, status: MasteryStatus.known);

      expect(
        await decks.getMasteryStats(deck.id),
        MasteryStats(total: 2, known: 1),
      );
      expect((await decks.getMasteryStats(deck.id)).percentage, 50);

      await cards.updateContent(
        id: first.id,
        question: 'Changed',
        answer: first.answer,
      );
      expect(
        await decks.getMasteryStats(deck.id),
        MasteryStats(total: 2, known: 0),
      );

      await cards.setMasteryStatus(id: second.id, status: MasteryStatus.known);
      await cards.delete(first.id);
      expect(
        await decks.getMasteryStats(deck.id),
        MasteryStats(total: 1, known: 1),
      );

      await createCard();
      expect(
        await decks.getMasteryStats(deck.id),
        MasteryStats(total: 2, known: 1),
      );
    });

    test('batch query isolates decks and includes empty decks', () async {
      final card = await createCard();
      await createCard();
      await cards.setMasteryStatus(id: card.id, status: MasteryStatus.known);
      final otherDeck = await decks.create(title: 'Other');
      await createCard(deckId: otherDeck.id);
      final emptyDeck = await decks.create(title: 'Empty');

      expect(await decks.getAllMasteryStats(), {
        deck.id: MasteryStats(total: 2, known: 1),
        otherDeck.id: MasteryStats(total: 1, known: 0),
        emptyDeck.id: MasteryStats(total: 0, known: 0),
      });
      await decks.delete(otherDeck.id);
      expect(await decks.getAllMasteryStats(), isNot(contains(otherDeck.id)));
    });

    test('missing decks report not found rather than empty mastery', () async {
      await expectLater(
        decks.getMasteryStats(9999),
        throwsA(isA<RecordNotFoundException>()),
      );
    });

    test('a database with no decks has an empty mastery map', () async {
      await decks.delete(deck.id);

      expect(await decks.getAll(), isEmpty);
      expect(await decks.getAllMasteryStats(), isEmpty);
    });
  });

  group('Repeated and concurrent operations', () {
    test(
      'rapid identical grading is idempotent and does not toggle mastery',
      () async {
        final card = await createCard();
        for (final status in [MasteryStatus.known, MasteryStatus.review]) {
          final results = await Future.wait(
            List.generate(
              20,
              (_) => cards.setMasteryStatus(id: card.id, status: status),
            ),
          );

          expect(results.every((card) => card.status == status), isTrue);
          expect((await cards.getById(card.id))!.status, status);
          expect(
            await decks.getMasteryStats(deck.id),
            MasteryStats(
              total: 1,
              known: status == MasteryStatus.known ? 1 : 0,
            ),
          );
        }
      },
    );

    test('rapid repeated card deletion succeeds only once', () async {
      final card = await createCard();

      final results = await Future.wait(
        List.generate(20, (_) => cards.delete(card.id)),
      );

      expect(results.where((deleted) => deleted), hasLength(1));
      expect(
        await decks.getMasteryStats(deck.id),
        MasteryStats(total: 0, known: 0),
      );
    });

    test('rapid repeated deck deletion cascades safely once', () async {
      final card = await createCard();

      final results = await Future.wait(
        List.generate(20, (_) => decks.delete(deck.id)),
      );

      expect(results.where((deleted) => deleted), hasLength(1));
      expect(await cards.getById(card.id), isNull);
      expect(await decks.getAllMasteryStats(), isEmpty);
    });

    test('concurrent inserts receive distinct persistent IDs', () async {
      final results = await Future.wait(List.generate(20, (_) => createCard()));

      expect(results.map((card) => card.id).toSet(), hasLength(20));
      expect(await cards.getByDeck(deck.id), hasLength(20));
      expect(
        await decks.getMasteryStats(deck.id),
        MasteryStats(total: 20, known: 0),
      );
    });

    test('repository use after closing yields a typed storage error', () async {
      await database.close();

      await expectLater(decks.getAll(), throwsA(isA<StorageException>()));
      await expectLater(
        cards.getByDeck(deck.id),
        throwsA(isA<StorageException>()),
      );
    });
  });
}
