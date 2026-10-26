import 'dart:async';
import 'dart:ui' as ui;

import 'package:flashquest_drill/app.dart';
import 'package:flashquest_drill/models/deck.dart';
import 'package:flashquest_drill/models/flashcard.dart';
import 'package:flashquest_drill/widgets/flashcard_content.dart';
import 'package:flashquest_drill/widgets/flashcard_flip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/controlled_repositories.dart';
import '../../support/memory_repositories.dart';
import '../../support/visual_capture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);

  late ControlledDeckRepository decks;
  late ControlledFlashcardRepository cards;
  late Deck deck;
  late Flashcard first;
  late Flashcard second;
  late GlobalKey preview;

  setUp(() async {
    final store = MemoryStore();
    decks = ControlledDeckRepository(MemoryDeckRepository(store));
    cards = ControlledFlashcardRepository(MemoryFlashcardRepository(store));
    deck = await decks.delegate.create(title: 'Biology essentials');
    final created = await cards.delegate.create(
      deckId: deck.id,
      question: 'What is ATP?',
      answer: 'An energy carrier in living cells.',
    );
    first = await cards.delegate.setMasteryStatus(
      id: created.id,
      status: MasteryStatus.known,
    );
    second = await cards.delegate.create(
      deckId: deck.id,
      question: 'What carries genetic information?',
      answer: 'DNA stores genetic information.',
    );
    preview = GlobalKey();
  });

  Future<void> start(
    WidgetTester tester, {
    Size size = const Size(412, 892),
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      RepaintBoundary(
        key: preview,
        child: FlashQuestApp(deckRepository: decks, flashcardRepository: cards),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openDeck(WidgetTester tester, Deck selected) async {
    final tile = find.byKey(ValueKey('deck-${selected.id}'));
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pumpAndSettle();
  }

  Future<void> openDeckMenu(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Deck options'));
    await tester.pumpAndSettle();
  }

  Future<void> requestStudyAgain(WidgetTester tester) async {
    await openDeckMenu(tester);
    await tester.tap(find.text('Study Again'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mastery-reset-dialog')), findsOneWidget);
  }

  testWidgets(
    'Study Again appears only in the deck overflow in the requested order',
    (tester) async {
      await start(tester);
      await openDeck(tester, deck);
      expect(find.text('Study Again'), findsNothing);
      expect(find.byKey(const ValueKey('study-button')), findsOneWidget);
      await openDeckMenu(tester);
      final labels = ['Study Again', 'Edit Deck', 'Delete Deck'];
      expect(
        find.byWidgetPredicate((widget) => widget is PopupMenuItem),
        findsNWidgets(3),
      );
      expect(
        tester.getTopLeft(find.text(labels[0])).dy,
        lessThan(tester.getTopLeft(find.text(labels[1])).dy),
      );
      expect(
        tester.getTopLeft(find.text(labels[1])).dy,
        lessThan(tester.getTopLeft(find.text(labels[2])).dy),
      );
      expect(find.byIcon(Icons.restart_alt_rounded), findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
      final destructive = tester.widget<Text>(find.text('Delete Deck'));
      expect(
        destructive.style!.color,
        Theme.of(tester.element(find.text('Delete Deck'))).colorScheme.error,
      );
      await capturePreview(
        tester,
        preview,
        '01-deck-menu',
        outputDirectory: 'build/study-again-preview',
      );
      await tester.tap(find.text('Study Again'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const ValueKey('mastery-reset-dialog')), findsNothing);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('study-again-menu-item')), findsNothing);
      expect(find.text('Edit Deck'), findsNothing);
      expect(
        find.byKey(const ValueKey('mastery-reset-dialog')),
        findsOneWidget,
      );
      expect(decks.resetCalls, 0);
    },
  );

  testWidgets('cancelling Study Again preserves all mastery and content', (
    tester,
  ) async {
    final before = await cards.delegate.getByDeck(deck.id);
    await start(tester);
    await openDeck(tester, deck);
    await requestStudyAgain(tester);
    expect(find.textContaining('0% mastery'), findsOneWidget);
    await capturePreview(
      tester,
      preview,
      '02-confirm-reset',
      outputDirectory: 'build/study-again-preview',
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(decks.resetCalls, 0);
    expect(await cards.delegate.getByDeck(deck.id), before);
    expect(find.text('50%'), findsOneWidget);
    expect(find.text('Deck details'), findsOneWidget);
    expect(find.byKey(const ValueKey('study-question')), findsNothing);
  });

  testWidgets(
    'confirmed reset commits once before entering a full Study session',
    (tester) async {
      final otherDeck = await decks.delegate.create(title: 'Other');
      final otherCard = await cards.delegate.create(
        deckId: otherDeck.id,
        question: 'Other Q',
        answer: 'Other A',
      );
      final otherKnown = await cards.delegate.setMasteryStatus(
        id: otherCard.id,
        status: MasteryStatus.known,
      );
      await start(tester);
      await openDeck(tester, deck);
      await requestStudyAgain(tester);
      final gate = Completer<void>();
      decks.writeGate = gate.future;
      final confirm = tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('confirm-reset-mastery')),
          )
          .onPressed!;
      confirm();
      confirm();
      await tester.pumpAndSettle();
      expect(decks.resetCalls, 1);
      expect(find.text('Deck details'), findsOneWidget);
      expect(find.byKey(const ValueKey('study-question')), findsNothing);
      expect(await cards.delegate.getById(first.id), first);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('study-button')))
            .onPressed,
        isNull,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Deck details'), findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('study-question')), findsOneWidget);
      expect(find.text(first.question), findsOneWidget);
      expect(find.text('2 left this round'), findsOneWidget);
      expect(find.text('0 of 2 cards Known this session'), findsOneWidget);
      expect(
        (await cards.delegate.getByDeck(deck.id)).map((card) => card.status),
        everyElement(MasteryStatus.review),
      );
      expect(await decks.delegate.getById(deck.id), deck);
      expect(await cards.delegate.getById(otherKnown.id), otherKnown);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('0%'), findsOneWidget);
      expect(find.byKey(ValueKey('flashcard-${first.id}')), findsOneWidget);
      await openDeckMenu(tester);
      expect(find.text('Study Again'), findsNothing);
      expect(find.text('Edit Deck'), findsOneWidget);
    },
  );

  testWidgets('failed reset keeps progress and does not navigate to Study', (
    tester,
  ) async {
    await start(tester);
    await openDeck(tester, deck);
    await requestStudyAgain(tester);
    decks.failWrites = true;
    await tester.tap(find.byKey(const ValueKey('confirm-reset-mastery')));
    await tester.pumpAndSettle();
    expect(find.textContaining('progress is unchanged'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
    expect(find.byKey(const ValueKey('study-question')), findsNothing);
    expect(await cards.delegate.getById(first.id), first);
    await openDeckMenu(tester);
    expect(find.text('Study Again'), findsOneWidget);
  });

  testWidgets('Edit Deck does not reset mastery or show reset confirmation', (
    tester,
  ) async {
    await start(tester);
    await openDeck(tester, deck);
    await openDeckMenu(tester);
    await tester.tap(find.text('Edit Deck'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mastery-reset-dialog')), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('deck-title')), 'Renamed');
    await tester.tap(find.byKey(const ValueKey('save-button')));
    await tester.pumpAndSettle();
    expect(find.text('Renamed'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
    expect(decks.resetCalls, 0);
    expect(await cards.delegate.getById(first.id), first);
  });

  for (final empty in [false, true]) {
    testWidgets(
      'Study Again is hidden for ${empty ? 'empty' : 'zero-mastery'} decks',
      (tester) async {
        if (empty) {
          await cards.delegate.delete(first.id);
          await cards.delegate.delete(second.id);
        } else {
          await decks.delegate.resetMastery(deck.id);
        }
        await start(tester);
        await openDeck(tester, deck);
        expect(find.byKey(const ValueKey('study-button')), findsOneWidget);
        await openDeckMenu(tester);
        expect(find.text('Study Again'), findsNothing);
        expect(find.text('Edit Deck'), findsOneWidget);
        expect(find.text('Delete Deck'), findsOneWidget);
        expect(decks.resetCalls, 0);
      },
    );
  }

  testWidgets(
    'primary Study preserves saved mastery without reset confirmation',
    (tester) async {
      await start(tester);
      await openDeck(tester, deck);
      await tester.tap(find.byKey(const ValueKey('study-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('study-question')), findsOneWidget);
      expect(find.byKey(const ValueKey('mastery-reset-dialog')), findsNothing);
      expect(await cards.delegate.getById(first.id), first);
      expect(decks.resetCalls, 0);
    },
  );

  Finder tile(Flashcard card) => find.byKey(ValueKey('flashcard-${card.id}'));
  Finder face(Flashcard card) =>
      find.byKey(ValueKey('flip-flashcard-${card.id}'));
  Finder pageScroll() => find
      .descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      )
      .first;

  Future<void> showFace(WidgetTester tester, Flashcard card) async {
    if (face(card).evaluate().isEmpty) {
      tester.state<ScrollableState>(pageScroll()).position.jumpTo(0);
      await tester.pumpAndSettle();
    }
    await tester.scrollUntilVisible(face(card), 180, scrollable: pageScroll());
    await tester.ensureVisible(face(card));
    await tester.pumpAndSettle();
  }

  Future<void> flip(WidgetTester tester, Flashcard card) async {
    await showFace(tester, card);
    // In short landscape viewports the scrollable card can be taller than the
    // page. Tap its visible area rather than a center hidden by the action bar.
    final visible = tester
        .getRect(face(card))
        .intersect(tester.getRect(find.byType(CustomScrollView)));
    expect(visible.isEmpty, isFalse);
    await tester.tapAt(visible.center);
    await tester.pumpAndSettle();
  }

  void expectSide(Flashcard card, {required bool answer}) {
    expect(
      find.descendant(
        of: tile(card),
        matching: find.text(answer ? card.answer : card.question),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: tile(card),
        matching: find.text(answer ? card.question : card.answer),
      ),
      findsNothing,
    );
  }

  Future<void> manage(
    WidgetTester tester,
    Flashcard card,
    String action,
  ) async {
    await showFace(tester, card);
    final tooltip = find.descendant(
      of: tile(card),
      matching: find.byTooltip(RegExp('^Options for flashcard:')),
    );
    await tester.ensureVisible(tooltip);
    await tester.tap(tooltip);
    await tester.pumpAndSettle();
    expectSide(card, answer: false);
    await tester.tap(find.text(action));
    await tester.pumpAndSettle();
  }

  testWidgets('dashboard has no offline badge, status text, or tooltip', (
    tester,
  ) async {
    await start(tester);
    expect(find.text('FlashQuest'), findsOneWidget);
    expect(
      find.textContaining(RegExp('offline', caseSensitive: false)),
      findsNothing,
    );
    expect(
      find.byTooltip(RegExp('offline', caseSensitive: false)),
      findsNothing,
    );
    expect(find.byIcon(Icons.offline_bolt_outlined), findsNothing);
    expect(find.text('50% mastered'), findsOneWidget);
    await capturePreview(
      tester,
      preview,
      '01-dashboard',
      outputDirectory: 'build/flip-preview',
    );
  });

  testWidgets('tap flips to answer and back, with exactly one visible face', (
    tester,
  ) async {
    await start(tester);
    await openDeck(tester, deck);
    await showFace(tester, first);
    expectSide(first, answer: false);
    final cardSize = tester.getSize(tile(first));
    void expectCenteredContent(String content, {Flashcard? selected}) {
      final text = tester.widget<Text>(find.text(content));
      expect(text.style!.fontWeight, FontWeight.bold);
      expect(text.style!.fontSize, inInclusiveRange(22, 26));
      expect(text.textAlign, TextAlign.center);
      final viewport = tester.getRect(
        find.descendant(
          of: tile(selected ?? first),
          matching: find.byType(FlashcardContent),
        ),
      );
      final textRect = tester.getRect(find.text(content));
      expect(textRect.center.dx, closeTo(viewport.center.dx, 0.1));
      expect(textRect.center.dy, closeTo(viewport.center.dy, 0.1));
      expect(tester.getSize(tile(first)), cardSize);
    }

    expectCenteredContent(first.question);
    expectCenteredContent(second.question, selected: second);
    expect(find.text('Tap to reveal answer'), findsWidgets);
    await capturePreview(
      tester,
      preview,
      '02-question',
      outputDirectory: 'build/flip-preview',
    );

    await tester.tap(face(first));
    await tester.pump();
    for (var step = 0; step < 5; step++) {
      final hasQuestion = find
          .descendant(of: tile(first), matching: find.text(first.question))
          .evaluate()
          .isNotEmpty;
      final hasAnswer = find
          .descendant(of: tile(first), matching: find.text(first.answer))
          .evaluate()
          .isNotEmpty;
      expect(hasQuestion != hasAnswer, isTrue);
      if (step == 1) {
        await capturePreview(
          tester,
          preview,
          '05-flipping',
          outputDirectory: 'build/flip-preview',
          settle: false,
        );
      }
      await tester.pump(const Duration(milliseconds: 80));
    }
    expectSide(first, answer: true);
    expectCenteredContent(first.answer);
    expect(find.text('Tap to show question'), findsOneWidget);
    await capturePreview(
      tester,
      preview,
      '03-answer',
      outputDirectory: 'build/flip-preview',
    );
    await flip(tester, first);
    expectSide(first, answer: false);
    expect(cards.gradeCalls, 0);
    expect(cards.updateCalls, 0);
    expect(await cards.delegate.getById(first.id), first);
    tester.state<ScrollableState>(pageScroll()).position.jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.text('50%'), findsOneWidget);
  });

  testWidgets(
    'cards flip independently and retain their face after scrolling',
    (tester) async {
      await start(tester);
      await openDeck(tester, deck);
      await flip(tester, first);
      await showFace(tester, second);
      expectSide(second, answer: false);
      await flip(tester, second);
      await showFace(tester, first);
      expectSide(first, answer: true);
      await flip(tester, first);
      expectSide(first, answer: false);
      await showFace(tester, second);
      expectSide(second, answer: true);
      expect(cards.gradeCalls, 0);
      expect(cards.updateCalls, 0);
    },
  );

  testWidgets('rapid taps cannot queue extra flips in either direction', (
    tester,
  ) async {
    await start(tester);
    await openDeck(tester, deck);
    await showFace(tester, first);
    for (final answer in [true, false]) {
      final tap = tester.widget<InkWell>(face(first)).onTap!;
      tap();
      tap();
      tap();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(tester.widget<InkWell>(face(first)).onTap, isNull);
      await tester.pumpAndSettle();
      expectSide(first, answer: answer);
    }
  });

  testWidgets(
    'whole Deck Details surface flips, including the header and edges',
    (tester) async {
      await start(tester);
      await openDeck(tester, deck);
      await showFace(tester, first);
      final rect = tester.getRect(face(first));
      final points = [
        rect.topCenter + const Offset(0, 2),
        rect.bottomCenter - const Offset(0, 2),
        rect.centerLeft + const Offset(2, 0),
        rect.centerRight - const Offset(2, 0),
        rect.topLeft + const Offset(10, 10),
        rect.topLeft + Offset(rect.width / 2, 28),
        tester.getCenter(
          find.descendant(of: tile(first), matching: find.text('Known')),
        ),
        tester.getCenter(find.text(first.question)),
      ];
      for (final point in points) {
        await tester.tapAt(point);
        await tester.pumpAndSettle();
        expectSide(first, answer: true);
        await tester.tapAt(point);
        await tester.pumpAndSettle();
        expectSide(first, answer: false);
      }
      expect(cards.gradeCalls, 0);
      expect(cards.updateCalls, 0);
      expect(cards.deleteCalls, 0);
      expect(find.text('Edit flashcard'), findsNothing);
    },
  );

  for (final edit in [
    (field: 'card-question', value: 'What does ATP do?'),
    (
      field: 'card-answer',
      value: 'ATP transfers energy for cellular processes.',
    ),
  ]) {
    testWidgets(
      'edit menu does not flip and editing ${edit.field} resets the face',
      (tester) async {
        await start(tester);
        await openDeck(tester, deck);
        await manage(tester, first, 'Edit flashcard');
        expect(find.text('Edit flashcard'), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        await flip(tester, first);
        expectSide(first, answer: true);
        final tooltip = find.descendant(
          of: tile(first),
          matching: find.byTooltip(RegExp('^Options for flashcard:')),
        );
        await tester.ensureVisible(tooltip);
        await tester.tap(tooltip);
        await tester.pumpAndSettle();
        expectSide(first, answer: true);
        await tester.tap(find.text('Edit flashcard'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(ValueKey(edit.field)), edit.value);
        await tester.ensureVisible(find.byKey(const ValueKey('save-button')));
        await tester.tap(find.byKey(const ValueKey('save-button')));
        await tester.pumpAndSettle();
        final edited = (await cards.delegate.getById(first.id))!;
        await showFace(tester, edited);
        expectSide(edited, answer: false);
        expect(edited.status, MasteryStatus.review);
        tester.state<ScrollableState>(pageScroll()).position.jumpTo(0);
        await tester.pumpAndSettle();
        expect(find.text('0%'), findsOneWidget);
      },
    );
  }

  testWidgets(
    'delete menu does not flip, cancellation and confirmation still work',
    (tester) async {
      await start(tester);
      await openDeck(tester, deck);
      await manage(tester, first, 'Delete flashcard');
      expect(cards.deleteCalls, 0);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expectSide(first, answer: false);
      await manage(tester, first, 'Delete flashcard');
      await tester.tap(find.byKey(const ValueKey('confirm-delete')));
      await tester.pumpAndSettle();
      expect(cards.deleteCalls, 1);
      expect(await cards.delegate.getById(first.id), isNull);
      expect(find.byKey(ValueKey('flashcard-${first.id}')), findsNothing);
    },
  );

  testWidgets('changing decks and reopening a deck starts on questions', (
    tester,
  ) async {
    final other = await decks.delegate.create(title: 'Chemistry');
    final otherCard = await cards.delegate.create(
      deckId: other.id,
      question: 'What is H2O?',
      answer: 'Water.',
    );
    await start(tester);
    await openDeck(tester, deck);
    await flip(tester, first);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await openDeck(tester, other);
    await showFace(tester, otherCard);
    expectSide(otherCard, answer: false);
    await flip(tester, otherCard);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await openDeck(tester, deck);
    await showFace(tester, first);
    expectSide(first, answer: false);
  });

  for (final setting in {
    'disabled animations': const FakeAccessibilityFeatures(
      disableAnimations: true,
    ),
    'accessible navigation': const FakeAccessibilityFeatures(
      accessibleNavigation: true,
    ),
  }.entries) {
    testWidgets('both directions respect ${setting.key}', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = setting.value;
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await start(tester);
      await openDeck(tester, deck);
      await showFace(tester, first);
      await tester.tap(face(first));
      await tester.pump();
      expectSide(first, answer: true);
      await tester.tap(face(first));
      await tester.pump();
      expectSide(first, answer: false);
    });
  }

  testWidgets('enabling reduced motion during a flip finishes it safely', (
    tester,
  ) async {
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await start(tester);
    await openDeck(tester, deck);
    await showFace(tester, first);
    await tester.tap(face(first));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    await tester.pump();
    expectSide(first, answer: true);
    expect(tester.takeException(), isNull);
  });

  testWidgets('accessible labels and actions follow only the visible face', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await start(tester);
      await openDeck(tester, deck);
      await showFace(tester, first);
      final flipWidget = find.descendant(
        of: tile(first),
        matching: find.byType(FlashcardFlip),
      );
      var node = tester.getSemantics(flipWidget);
      expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap), isTrue);
      expect(node.label, contains('Flashcard question'));
      expect(
        tester.getSemantics(find.text(first.question)).label,
        first.question,
      );
      expect(node.label, isNot(contains(first.answer)));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      node.owner!.performAction(node.id, ui.SemanticsAction.tap);
      await tester.pumpAndSettle();
      expectSide(first, answer: true);
      node = tester.getSemantics(flipWidget);
      expect(node.label, contains('Flashcard answer'));
      expect(tester.getSemantics(find.text(first.answer)).label, first.answer);
      expect(node.label, isNot(contains(first.question)));
      expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap), isTrue);
      node.owner!.performAction(node.id, ui.SemanticsAction.tap);
      await tester.pumpAndSettle();
      expectSide(first, answer: false);
    } finally {
      semantics.dispose();
    }
  });

  for (final configuration in [
    (name: 'small', size: const Size(320, 640), scale: 1.0),
    (name: 'large-text', size: const Size(320, 640), scale: 2.0),
    (name: 'landscape', size: const Size(640, 360), scale: 1.8),
  ]) {
    testWidgets('long content scrolls fully in ${configuration.name}', (
      tester,
    ) async {
      final question =
          '${List.filled(35, 'Explain how energy flows through a cell.').join(' ')} QUESTION END';
      final answer =
          '${List.filled(40, 'Chemical reactions transfer energy in living cells.').join(' ')} ANSWER END';
      first = await cards.delegate.updateContent(
        id: first.id,
        question: question,
        answer: answer,
      );
      await start(tester, size: configuration.size, scale: configuration.scale);
      await openDeck(tester, deck);
      await showFace(tester, first);
      for (final answerSide in [false, true]) {
        if (answerSide) await flip(tester, first);
        expectSide(first, answer: answerSide);
        final scroll = tester.state<ScrollableState>(
          find.descendant(
            of: find.byKey(
              ValueKey(
                'flashcard-${first.id}-${answerSide ? 'answer' : 'question'}-scroll',
              ),
            ),
            matching: find.byType(Scrollable),
          ),
        );
        expect(scroll.position.maxScrollExtent, greaterThan(0));
        expect(scroll.position.pixels, 0);
        scroll.position.jumpTo(scroll.position.maxScrollExtent);
        await tester.pumpAndSettle();
        expect(scroll.position.extentAfter, 0);
        // The page may also scroll on short landscape screens. Its footer can
        // be brought into view together with the end of the card's content.
        final instruction = find.descendant(
          of: tile(first),
          matching: find.text(
            answerSide ? 'Tap to show question' : 'Tap to reveal answer',
          ),
        );
        await Scrollable.ensureVisible(
          tester.element(instruction),
          alignment: 1,
        );
        await tester.pumpAndSettle();
        expect(instruction.hitTestable(), findsOneWidget);
        final contentBottom = tester
            .getBottomRight(find.text(answerSide ? answer : question))
            .dy;
        final viewport = tester.getRect(find.byType(CustomScrollView));
        expect(contentBottom, greaterThan(viewport.top));
        expect(contentBottom, lessThanOrEqualTo(viewport.bottom));
        final text = tester.widget<Text>(
          find.text(answerSide ? answer : question),
        );
        expect(text.maxLines, isNull);
        expect(text.overflow, isNull);
        expect(tester.takeException(), isNull);
      }
      await capturePreview(
        tester,
        preview,
        '04-${configuration.name}',
        outputDirectory: 'build/flip-preview',
      );
      tester.view.physicalSize = Size(
        configuration.size.height,
        configuration.size.width,
      );
      await tester.pumpAndSettle();
      await showFace(tester, first);
      expectSide(first, answer: true);
      expect(tester.takeException(), isNull);
      await flip(tester, first);
      expectSide(first, answer: false);
    });
  }

  testWidgets('disposing while flipping in either direction is safe', (
    tester,
  ) async {
    for (final reverse in [false, true]) {
      await start(tester);
      await openDeck(tester, deck);
      if (reverse) await flip(tester, first);
      await showFace(tester, first);
      await tester.tap(face(first));
      await tester.pump(const Duration(milliseconds: 80));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
}
