import 'dart:async';

import 'package:flashquest_drill/app.dart';
import 'package:flashquest_drill/models/deck.dart';
import 'package:flashquest_drill/models/flashcard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/controlled_repositories.dart';
import 'support/memory_repositories.dart';
import 'support/visual_capture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadPreviewFonts();
  });

  late ControlledDeckRepository decks;
  late ControlledFlashcardRepository cards;
  late GlobalKey previewKey;

  setUp(() {
    final store = MemoryStore();
    decks = ControlledDeckRepository(MemoryDeckRepository(store));
    cards = ControlledFlashcardRepository(MemoryFlashcardRepository(store));
    previewKey = GlobalKey();
  });

  Future<({Deck deck, Flashcard known})> seed() async {
    final deck = await decks.delegate.create(title: 'Biology essentials');
    final card = await cards.delegate.create(
      deckId: deck.id,
      question: 'What is the powerhouse of the cell?',
      answer: 'The mitochondrion produces most of the energy a cell needs.',
    );
    final known = await cards.delegate.setMasteryStatus(
      id: card.id,
      status: MasteryStatus.known,
    );
    await cards.delegate.create(
      deckId: deck.id,
      question: 'What carries genetic information?',
      answer: 'DNA stores the instructions for living organisms.',
    );
    return (deck: deck, known: known);
  }

  Future<void> start(
    WidgetTester tester, {
    Size size = const Size(412, 892),
    double textScale = 1,
    bool settle = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      RepaintBoundary(
        key: previewKey,
        child: FlashQuestApp(deckRepository: decks, flashcardRepository: cards),
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }

  Future<void> openDeck(WidgetTester tester, Deck deck) async {
    await tester.ensureVisible(find.byKey(ValueKey('deck-${deck.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('deck-${deck.id}')));
    await tester.pumpAndSettle();
  }

  Future<void> chooseCardDelete(WidgetTester tester) async {
    await tester.tap(find.byTooltip(RegExp('^Options for flashcard:')).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete flashcard'));
    await tester.pumpAndSettle();
  }

  testWidgets('empty dashboard validates and creates a saved deck', (
    tester,
  ) async {
    await start(tester);
    expect(find.text('Your first deck starts here'), findsOneWidget);
    await capturePreview(tester, previewKey, '00-empty-dashboard');
    await tester.tap(find.byKey(const ValueKey('create-deck')));
    await tester.pumpAndSettle();
    await capturePreview(tester, previewKey, '03-create-deck');
    await tester.tap(find.byKey(const ValueKey('save-button')));
    await tester.pumpAndSettle();
    expect(find.text('Enter a title for your deck.'), findsOneWidget);
    expect(decks.createCalls, 0);
    await tester.enterText(
      find.byKey(const ValueKey('deck-title')),
      'Chemistry',
    );
    await tester.tap(find.byKey(const ValueKey('save-button')));
    await tester.pumpAndSettle();
    expect(find.text('Chemistry'), findsOneWidget);
    expect(find.text('0 flashcards'), findsOneWidget);
    expect((await decks.delegate.getAll()).single.title, 'Chemistry');
  });

  testWidgets('dashboard and details display saved mastery and open Study', (
    tester,
  ) async {
    final saved = await seed();
    final other = await decks.delegate.create(title: 'World history');
    await cards.delegate.create(
      deckId: other.id,
      question: 'When did the Renaissance begin?',
      answer: 'In the 14th century, in Italy.',
    );
    await start(tester);
    expect(find.text('50% mastered'), findsOneWidget);
    expect(find.text('2 flashcards'), findsOneWidget);
    await capturePreview(tester, previewKey, '01-dashboard');
    await openDeck(tester, saved.deck);
    expect(find.text('50%'), findsOneWidget);
    expect(find.text('Known'), findsOneWidget);
    await capturePreview(tester, previewKey, '02-deck-details');
    await tester.tap(find.byKey(const ValueKey('study-button')));
    await tester.pumpAndSettle();
    expect(find.text('Tap to reveal the answer'), findsOneWidget);
    expect(await cards.delegate.getById(saved.known.id), saved.known);
  });

  testWidgets('empty decks disable Study and can add validated flashcards', (
    tester,
  ) async {
    final deck = await decks.delegate.create(title: 'Math');
    await start(tester);
    await openDeck(tester, deck);
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const ValueKey('study-button')))
          .onPressed,
      isNull,
    );
    expect(find.text('A fresh start'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('add-flashcard')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-button')));
    await tester.pumpAndSettle();
    expect(find.text('Enter a question for this flashcard.'), findsOneWidget);
    expect(find.text('Enter an answer for this flashcard.'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('card-question')),
      'What is 2 + 2?',
    );
    await tester.enterText(find.byKey(const ValueKey('card-answer')), '4');
    await tester.tap(find.byKey(const ValueKey('save-button')));
    await tester.pumpAndSettle();
    expect(find.text('What is 2 + 2?'), findsOneWidget);
    expect(find.text('1 flashcard in this deck'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('study-button')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets(
    'editing a card explains the reset and refreshes details and home',
    (tester) async {
      final saved = await seed();
      await start(tester);
      await openDeck(tester, saved.deck);
      await tester.tap(find.byTooltip(RegExp('^Options for flashcard:')).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit flashcard'));
      await tester.pumpAndSettle();
      expect(find.textContaining('reset mastery to Review'), findsOneWidget);
      await capturePreview(tester, previewKey, '04-edit-flashcard');
      await tester.enterText(
        find.byKey(const ValueKey('card-question')),
        'Which organelle makes ATP?',
      );
      await tester.tap(find.byKey(const ValueKey('save-button')));
      await tester.pumpAndSettle();
      expect(find.text('Which organelle makes ATP?'), findsOneWidget);
      expect(find.text('0%'), findsOneWidget);
      expect(
        (await cards.delegate.getById(saved.known.id))!.status,
        MasteryStatus.review,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('0% mastered'), findsOneWidget);
    },
  );

  testWidgets('renaming a deck refreshes its dashboard title', (tester) async {
    final saved = await seed();
    await start(tester);
    await tester.tap(find.byTooltip('Options for ${saved.deck.title}'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit deck'));
    await tester.pumpAndSettle();
    expect(find.text(saved.deck.title), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('deck-title')),
      'Cell biology',
    );
    await tester.tap(find.byKey(const ValueKey('save-button')));
    await tester.pumpAndSettle();
    expect(find.text('Cell biology'), findsOneWidget);
    expect(find.text('50% mastered'), findsOneWidget);
  });

  testWidgets('flashcard deletion can be cancelled and requires confirmation', (
    tester,
  ) async {
    final saved = await seed();
    await start(tester);
    await openDeck(tester, saved.deck);
    await chooseCardDelete(tester);
    expect(find.text('Delete flashcard?'), findsOneWidget);
    expect(cards.deleteCalls, 0);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await cards.delegate.getByDeck(saved.deck.id), hasLength(2));
    expect(cards.deleteCalls, 0);
    await chooseCardDelete(tester);
    await tester.tap(find.byKey(const ValueKey('confirm-delete')));
    await tester.pumpAndSettle();
    expect(cards.deleteCalls, 1);
    expect(find.text('1 flashcard in this deck'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
  });

  testWidgets(
    'deck deletion warns about all cards, cancels safely, and cascades',
    (tester) async {
      final saved = await seed();
      await start(tester);
      await openDeck(tester, saved.deck);
      Future<void> requestDelete() async {
        await tester.tap(find.byTooltip('Deck options'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete Deck'));
        await tester.pumpAndSettle();
      }

      await requestDelete();
      expect(
        find.textContaining('all its flashcards will be permanently deleted'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(decks.deleteCalls, 0);
      await requestDelete();
      await tester.tap(find.byKey(const ValueKey('confirm-delete')));
      await tester.pumpAndSettle();
      expect(find.text('Your first deck starts here'), findsOneWidget);
      expect(await cards.delegate.getByDeck(saved.deck.id), isEmpty);
    },
  );

  testWidgets('dashboard deck deletion is also protected by confirmation', (
    tester,
  ) async {
    final saved = await seed();
    await start(tester);
    await tester.tap(find.byTooltip('Options for ${saved.deck.title}'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete deck'));
    await tester.pumpAndSettle();
    expect(decks.deleteCalls, 0);
    await tester.tap(find.byKey(const ValueKey('confirm-delete')));
    await tester.pumpAndSettle();
    expect(find.text('Your first deck starts here'), findsOneWidget);
  });

  testWidgets('failed initial loading shows a safe error and retry recovers', (
    tester,
  ) async {
    decks.failReads = true;
    await start(tester);
    expect(find.textContaining('couldn’t load your decks'), findsOneWidget);
    expect(find.textContaining('Private database'), findsNothing);
    decks.failReads = false;
    await tester.tap(find.text('Reload decks'));
    await tester.pumpAndSettle();
    expect(find.text('Your first deck starts here'), findsOneWidget);
  });

  testWidgets(
    'loading indicators finish and late completion after unmount is safe',
    (tester) async {
      final gate = Completer<void>();
      decks.readGate = gate.future;
      await start(tester, settle: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(find.text('Loading your decks…'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      gate.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed saves retain text and allow a successful retry', (
    tester,
  ) async {
    await start(tester);
    await tester.tap(find.byKey(const ValueKey('create-deck')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('deck-title')),
      'Chemistry',
    );
    decks.failWrites = true;
    await tester.tap(find.byKey(const ValueKey('save-button')));
    await tester.pumpAndSettle();
    expect(find.text('Chemistry'), findsOneWidget);
    expect(find.textContaining('couldn’t save your deck'), findsOneWidget);
    decks.failWrites = false;
    await tester.tap(find.byKey(const ValueKey('save-button')));
    await tester.pumpAndSettle();
    expect(find.text('Your decks'), findsOneWidget);
    expect((await decks.delegate.getAll()).single.title, 'Chemistry');
  });

  testWidgets(
    'repeated save taps and back navigation cannot interrupt a pending write',
    (tester) async {
      await start(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('create-deck')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('create-deck')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('deck-title')),
        'Chemistry',
      );
      final gate = Completer<void>();
      decks.writeGate = gate.future;
      await tester.tap(find.byKey(const ValueKey('save-button')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('save-button')));
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(decks.createCalls, 1);
      expect(find.text('Saving…'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('deck-title')))
            .enabled,
        isFalse,
      );
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Your decks'), findsOneWidget);
      expect(await decks.delegate.getAll(), hasLength(1));
    },
  );

  testWidgets('flashcard save failures retain both inputs', (tester) async {
    final saved = await seed();
    await start(tester);
    await openDeck(tester, saved.deck);
    await tester.tap(find.byKey(const ValueKey('add-flashcard')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('card-question')), 'ATP?');
    await tester.enterText(
      find.byKey(const ValueKey('card-answer')),
      'Energy carrier',
    );
    cards.failWrites = true;
    await tester.tap(find.byKey(const ValueKey('save-button')));
    await tester.pumpAndSettle();
    expect(find.text('ATP?'), findsOneWidget);
    expect(find.text('Energy carrier'), findsOneWidget);
    expect(find.textContaining('couldn’t save this flashcard'), findsOneWidget);
  });

  testWidgets('deletion failures keep context and offer a read-only reload', (
    tester,
  ) async {
    final saved = await seed();
    await start(tester);
    await openDeck(tester, saved.deck);
    cards.failWrites = true;
    await chooseCardDelete(tester);
    await tester.tap(find.byKey(const ValueKey('confirm-delete')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('couldn’t delete this flashcard'),
      findsNWidgets(2),
    );
    expect(await cards.delegate.getByDeck(saved.deck.id), hasLength(2));
    expect(find.byKey(ValueKey('flashcard-${saved.known.id}')), findsOneWidget);
    expect(find.byKey(const ValueKey('study-button')), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
    cards.failWrites = false;
    await tester.ensureVisible(find.text('Reload deck'));
    await tester.tap(find.text('Reload deck'));
    await tester.pumpAndSettle();
    expect(find.text('50%'), findsOneWidget);
    expect(cards.deleteCalls, 1);
    expect(await cards.delegate.getByDeck(saved.deck.id), hasLength(2));
  });

  testWidgets(
    'pending deletion blocks back navigation until saved data is refreshed',
    (tester) async {
      final saved = await seed();
      await start(tester);
      await openDeck(tester, saved.deck);
      final gate = Completer<void>();
      cards.writeGate = gate.future;
      await chooseCardDelete(tester);
      await tester.tap(find.byKey(const ValueKey('confirm-delete')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('Deck details'), findsOneWidget);
      expect(cards.deleteCalls, 1);
      gate.complete();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('1 flashcard'), findsOneWidget);
      expect(find.text('0% mastered'), findsOneWidget);
    },
  );

  for (final scale in [1.0, 1.8]) {
    testWidgets('management screens fit a narrow phone at text scale $scale', (
      tester,
    ) async {
      final saved = await seed();
      await start(tester, size: const Size(320, 640), textScale: scale);
      expect(tester.takeException(), isNull);
      await openDeck(tester, saved.deck);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('add-flashcard')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      tester.view.viewInsets = const FakeViewPadding(bottom: 240);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('create-deck')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'dashboard and details meet Android touch-target and labeling guidelines',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final saved = await seed();
        await start(tester);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await openDeck(tester, saved.deck);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
      } finally {
        semantics.dispose();
      }
    },
  );
}
