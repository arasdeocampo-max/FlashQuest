import 'dart:async';
import 'dart:ui' as ui;

import 'package:flashquest_drill/app.dart';
import 'package:flashquest_drill/app_theme.dart';
import 'package:flashquest_drill/features/study/study_screen.dart';
import 'package:flashquest_drill/models/deck.dart';
import 'package:flashquest_drill/models/flashcard.dart';
import 'package:flashquest_drill/widgets/flashcard_content.dart';
import 'package:flashquest_drill/widgets/flashcard_flip.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/controlled_repositories.dart';
import '../../support/memory_repositories.dart';
import '../../support/visual_capture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPreviewFonts);
  late ControlledDeckRepository decks;
  late ControlledFlashcardRepository cards;
  late GlobalKey preview;
  late Deck deck;
  late List<Flashcard> initial;

  setUp(() async {
    final store = MemoryStore();
    decks = ControlledDeckRepository(MemoryDeckRepository(store));
    cards = ControlledFlashcardRepository(MemoryFlashcardRepository(store));
    preview = GlobalKey();
    deck = await decks.delegate.create(title: 'Biology essentials');
    initial = [];
    initial.add(
      await cards.delegate.create(
        deckId: deck.id,
        question: 'What is the powerhouse of the cell?',
        answer: 'The mitochondrion produces most of the energy a cell needs.',
      ),
    );
    initial.add(
      await cards.delegate.create(
        deckId: deck.id,
        question: 'What carries genetic information?',
        answer: 'DNA stores the instructions for living organisms.',
      ),
    );
  });

  Future<void> start(
    WidgetTester tester, {
    Size size = const Size(412, 892),
    double textScale = 1,
    bool direct = false,
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
        key: preview,
        child: direct
            ? MaterialApp(
                theme: buildAppTheme(),
                home: StudyScreen(
                  deckId: deck.id,
                  deckRepository: decks,
                  flashcardRepository: cards,
                ),
              )
            : FlashQuestApp(deckRepository: decks, flashcardRepository: cards),
      ),
    );
    if (!settle) return;
    await tester.pumpAndSettle();
    if (!direct) {
      await tester.ensureVisible(find.byKey(ValueKey('deck-${deck.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('deck-${deck.id}')));
      await tester.pumpAndSettle();
    }
  }

  Future<void> begin(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('study-button')));
    await tester.pumpAndSettle();
  }

  Future<void> retryRemaining(WidgetTester tester) async {
    expect(find.text('Retry Remaining Cards'), findsOneWidget);
    expect(find.text('Session complete'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('retry-remaining')));
    await tester.pumpAndSettle();
  }

  Future<void> skip(WidgetTester tester) async {
    await tester.drag(
      find.byKey(const ValueKey('reveal-card')),
      const Offset(-210, 0),
    );
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester) async {
    if (find.byKey(const ValueKey('study-answer')).evaluate().isNotEmpty) {
      return;
    }
    await tester.ensureVisible(find.byKey(const ValueKey('reveal-card')));
    await tester.pumpAndSettle();
    // On a short landscape viewport the card is taller than the visible page.
    // Tap its visible area, as a user would, rather than its offscreen center.
    final page = find.byWidgetPredicate(
      (widget) =>
          widget is SingleChildScrollView &&
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith('study-page-'),
    );
    final visible = tester
        .getRect(find.byKey(const ValueKey('reveal-card')))
        .intersect(tester.getRect(page));
    expect(visible.isEmpty, isFalse);
    await tester.tapAt(visible.center);
    await tester.pumpAndSettle();
  }

  Future<void> grade(WidgetTester tester, {bool known = true}) async {
    await reveal(tester);
    await tester.tap(
      find.byKey(ValueKey(known ? 'grade-known' : 'grade-review')),
    );
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) => capturePreview(
    tester,
    preview,
    name,
    outputDirectory: 'build/phase3-preview',
  );

  testWidgets(
    'both Study faces are bold and centered without resizing the card',
    (tester) async {
      await start(tester);
      await begin(tester);
      final card = find.byKey(const ValueKey('reveal-card'));
      final size = tester.getSize(card);
      for (final answerSide in [false, true]) {
        if (answerSide) await reveal(tester);
        final textFinder = find.byKey(
          ValueKey(answerSide ? 'study-answer' : 'study-question'),
        );
        final text = tester.widget<Text>(textFinder);
        expect(text.style!.fontWeight, FontWeight.bold);
        expect(text.style!.fontSize, inInclusiveRange(22, 26));
        expect(text.textAlign, TextAlign.center);
        final viewport = tester.getRect(find.byType(FlashcardContent));
        final textRect = tester.getRect(textFinder);
        expect(textRect.center.dx, closeTo(viewport.center.dx, 0.1));
        expect(textRect.center.dy, closeTo(viewport.center.dy, 0.1));
        expect(tester.getSize(card), size);
        expect(find.text(answerSide ? 'ANSWER' : 'QUESTION'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await capturePreview(
          tester,
          preview,
          answerSide ? '02-study-answer' : '01-study-question',
          outputDirectory: 'build/centered-text-preview',
        );
      }
      expect(find.byKey(const ValueKey('grade-known')), findsOneWidget);
      expect(find.byKey(const ValueKey('grade-review')), findsOneWidget);
    },
  );

  testWidgets(
    'Study starts once, including saved Known cards, on the question',
    (tester) async {
      await cards.delegate.setMasteryStatus(
        id: initial.first.id,
        status: MasteryStatus.known,
      );
      await start(tester);
      final button = find.byKey(const ValueKey('study-button'));
      final startStudy = tester.widget<FilledButton>(button).onPressed!;
      startStudy();
      startStudy();
      await tester.pumpAndSettle();
      expect(cards.cardLoadCalls, 2); // Details and one study session.
      expect(find.byKey(const ValueKey('study-question')), findsOneWidget);
      expect(find.text(initial.first.question), findsOneWidget);
      expect(find.byKey(const ValueKey('study-answer')), findsNothing);
      expect(find.byKey(const ValueKey('grade-known')), findsNothing);
      expect(find.text('Round 1'), findsOneWidget);
      expect(find.text('2 left this round'), findsOneWidget);
      expect(find.text('0 Review this session'), findsOneWidget);
      expect(find.text('0 of 2 cards Known this session'), findsOneWidget);
      await capture(tester, '01-question');
    },
  );

  testWidgets(
    'grading appears after the flip finishes and the next card resets',
    (tester) async {
      await start(tester);
      await begin(tester);
      await tester.tap(find.byKey(const ValueKey('reveal-card')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('grade-known')), findsNothing);
      await tester.pumpAndSettle();
      expect(find.text(initial.first.answer), findsOneWidget);
      expect(find.byKey(const ValueKey('grade-review')), findsOneWidget);
      await capture(tester, '02-answer');
      await tester.tap(find.byKey(const ValueKey('grade-known')));
      await tester.pumpAndSettle();
      expect(find.text(initial[1].question), findsOneWidget);
      expect(find.byKey(const ValueKey('study-answer')), findsNothing);
      expect(find.byKey(const ValueKey('grade-known')), findsNothing);
      expect(find.text('1 left this round'), findsOneWidget);
      expect(
        (await cards.delegate.getById(initial.first.id))!.status,
        MasteryStatus.known,
      );
    },
  );

  testWidgets('multiple Review rounds finish only when all cards are Known', (
    tester,
  ) async {
    await start(tester);
    await begin(tester);
    await grade(tester, known: false);
    expect(find.text('1 Review this session'), findsOneWidget);
    expect(find.text('Round 1'), findsOneWidget);
    await grade(tester);
    await retryRemaining(tester);
    expect(find.text('Round 2'), findsOneWidget);
    expect(find.text(initial.first.question), findsOneWidget);
    expect(find.text('1 Review this session'), findsOneWidget);
    expect(find.text('Session complete'), findsNothing);
    await capture(tester, '03-review-round');
    await grade(tester, known: false);
    await retryRemaining(tester);
    expect(find.text('Round 3'), findsOneWidget);
    expect(find.text('Session complete'), findsNothing);
    await grade(tester);
    expect(find.text('Session complete'), findsOneWidget);
    expect(find.text('Cards studied'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    await capture(tester, '04-completion');
    await tester.tap(find.byKey(const ValueKey('return-to-deck')));
    await tester.pumpAndSettle();
    expect(find.text('Deck details'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('100% mastered'), findsOneWidget);
  });

  testWidgets(
    'a single card resets its flip and cannot skip repeated Review rounds',
    (tester) async {
      await cards.delegate.delete(initial.last.id);
      await start(tester);
      await begin(tester);
      await grade(tester, known: false);
      await retryRemaining(tester);
      expect(find.text('Round 2'), findsOneWidget);
      expect(find.byKey(const ValueKey('study-question')), findsOneWidget);
      expect(find.byKey(const ValueKey('study-answer')), findsNothing);
      expect(find.byKey(const ValueKey('grade-known')), findsNothing);
      await grade(tester, known: false);
      await retryRemaining(tester);
      expect(find.text('Round 3'), findsOneWidget);
      await grade(tester);
      expect(
        find.text('You marked all 1 card Known in this session.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('failed grading keeps the answer and offers a visible retry', (
    tester,
  ) async {
    await start(tester);
    await begin(tester);
    await reveal(tester);
    cards.failWrites = true;
    await tester.tap(find.byKey(const ValueKey('grade-known')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('study-turn-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('study-answer')), findsOneWidget);
    expect(find.textContaining('hasn’t moved'), findsOneWidget);
    expect(find.byKey(const ValueKey('retry-grade')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('retry-grade')).hitTestable(),
      findsOneWidget,
    );
    expect(
      (await cards.delegate.getById(initial.first.id))!.status,
      MasteryStatus.review,
    );
    cards.failWrites = false;
    await tester.tap(find.byKey(const ValueKey('retry-grade')));
    await tester.pumpAndSettle();
    expect(find.text(initial.last.question), findsOneWidget);
    expect(cards.gradeCalls, 2);
    expect(find.textContaining('hasn’t moved'), findsNothing);
  });

  testWidgets('repeated grade taps and back cannot interrupt a pending write', (
    tester,
  ) async {
    await start(tester);
    await begin(tester);
    await reveal(tester);
    final gate = Completer<void>();
    cards.writeGate = gate.future;
    final action = tester
        .widget<FilledButton>(find.byKey(const ValueKey('grade-known')))
        .onPressed!;
    action();
    action();
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(cards.gradeCalls, 1);
    expect(find.text('Saving your choice…'), findsOneWidget);
    expect(
      tester.widget<InkWell>(find.byKey(const ValueKey('reveal-card'))).onTap,
      isNull,
    );
    expect(find.byKey(const ValueKey('study-turn-0')), findsOneWidget);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text(initial.last.question), findsOneWidget);
    expect(find.text('Deck details'), findsNothing);
  });

  testWidgets(
    'flipping back does not grade, and grading advances only the current card',
    (tester) async {
      await start(tester);
      await begin(tester);
      await reveal(tester);
      await tester.tap(find.byKey(const ValueKey('reveal-card')));
      await tester.pumpAndSettle();
      expect(find.text(initial.first.question), findsOneWidget);
      expect(cards.gradeCalls, 0);
      await reveal(tester);
      await tester.tap(find.byKey(const ValueKey('grade-review')));
      await tester.pumpAndSettle();
      expect(cards.gradeCalls, 1);
      expect(find.text(initial.last.question), findsOneWidget);
      expect(find.text('1 Review this session'), findsOneWidget);
      expect(find.text('1 left this round'), findsOneWidget);
      expect(find.byKey(const ValueKey('study-answer')), findsNothing);
    },
  );

  testWidgets(
    'exiting early refreshes saved mastery and restarting uses all cards',
    (tester) async {
      await start(tester);
      await begin(tester);
      await grade(tester);
      await tester.tap(find.byTooltip('Return to deck'));
      await tester.pumpAndSettle();
      expect(find.text('50%'), findsOneWidget);
      await begin(tester);
      expect(find.text(initial.first.question), findsOneWidget);
      expect(find.text('Round 1'), findsOneWidget);
      expect(find.text('2 left this round'), findsOneWidget);
      expect(find.text('0 of 2 cards Known this session'), findsOneWidget);
    },
  );

  testWidgets('an all-Known saved deck still requires a full session', (
    tester,
  ) async {
    for (final card in initial) {
      await cards.delegate.setMasteryStatus(
        id: card.id,
        status: MasteryStatus.known,
      );
    }
    await start(tester);
    await begin(tester);
    expect(find.text('Session complete'), findsNothing);
    await grade(tester);
    expect(find.text('Session complete'), findsNothing);
    await grade(tester);
    expect(find.text('Session complete'), findsOneWidget);
  });

  testWidgets('empty decks never show a misleading completion', (tester) async {
    for (final card in initial) {
      await cards.delegate.delete(card.id);
    }
    await start(tester, direct: true);
    expect(find.text('No flashcards to study yet'), findsOneWidget);
    expect(find.text('Session complete'), findsNothing);
    expect(find.byKey(const ValueKey('grade-known')), findsNothing);
  });

  testWidgets('loading failure can retry without opening another session', (
    tester,
  ) async {
    cards.failReads = true;
    await start(tester, direct: true);
    expect(find.textContaining('couldn’t start this session'), findsOneWidget);
    cards.failReads = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text(initial.first.question), findsOneWidget);
  });

  testWidgets(
    'final mastery failure retries only the read after saved grading',
    (tester) async {
      await start(tester);
      await begin(tester);
      await grade(tester);
      decks.failReads = true;
      await grade(tester);
      expect(find.text('Session complete'), findsNothing);
      expect(find.textContaining('choices were saved'), findsOneWidget);
      expect(cards.gradeCalls, 2);
      decks.failReads = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Session complete'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
      expect(cards.gradeCalls, 2);
    },
  );

  for (final setting in {
    'disabled animations': const FakeAccessibilityFeatures(
      disableAnimations: true,
    ),
    'accessible navigation': const FakeAccessibilityFeatures(
      accessibleNavigation: true,
    ),
  }.entries) {
    testWidgets('reduced motion reveals immediately with ${setting.key}', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = setting.value;
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await start(tester);
      await begin(tester);
      await tester.tap(find.byKey(const ValueKey('reveal-card')));
      await tester.pump();
      expect(find.byKey(const ValueKey('grade-known')), findsOneWidget);
      expect(find.byKey(const ValueKey('study-answer')), findsOneWidget);
    });
  }

  testWidgets('disposing during loading and during a flip is safe', (
    tester,
  ) async {
    final gate = Completer<void>();
    cards.readGate = gate.future;
    await start(tester, direct: true, settle: false);
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    gate.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    cards.readGate = null;
    await start(tester, direct: true);
    await tester.tap(find.byKey(const ValueKey('reveal-card')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'disposing during a grade preserves a successful write without navigation',
    (tester) async {
      await start(tester);
      await begin(tester);
      await reveal(tester);
      final gate = Completer<void>();
      cards.writeGate = gate.future;
      await tester.tap(find.byKey(const ValueKey('grade-known')));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      gate.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        (await cards.delegate.getById(initial.first.id))!.status,
        MasteryStatus.known,
      );
    },
  );

  for (final scale in [1.0, 1.8]) {
    testWidgets(
      'landscape long cards, Review rounds and save recovery at $scale',
      (tester) async {
        await cards.delegate.updateContent(
          id: initial.first.id,
          question: List.filled(
            30,
            'Explain how a cell produces energy.',
          ).join(' '),
          answer: List.filled(
            35,
            'Chemical reactions transfer energy.',
          ).join(' '),
        );
        await start(tester, size: const Size(640, 360), textScale: scale);
        await begin(tester);
        expect(
          find.byKey(const ValueKey('review-round-message')),
          findsNothing,
        );
        await grade(tester, known: false);
        await grade(tester);
        await retryRemaining(tester);
        expect(find.text('Round 2'), findsOneWidget);
        expect(find.text('1 Review this session'), findsOneWidget);
        expect(
          find.text(
            'Only Review and skipped cards from the previous round repeat.',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await capturePreview(
          tester,
          preview,
          '07-study-landscape-$scale',
          outputDirectory: 'build/phase4b-preview',
        );
        await reveal(tester);
        cards.failWrites = true;
        await tester.tap(find.byKey(const ValueKey('grade-known')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('retry-grade')).hitTestable(),
          findsOneWidget,
        );
        expect(find.text('Session complete'), findsNothing);
        expect(tester.takeException(), isNull);
        cards.failWrites = false;
        await tester.tap(find.byKey(const ValueKey('retry-grade')));
        await tester.pumpAndSettle();
        expect(find.text('Session complete'), findsOneWidget);
        tester.view.physicalSize = const Size(320, 640);
        await tester.pumpAndSettle();
        expect(find.text('100%'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('return-to-deck')).hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'long question and answer remain scrollable on a small phone at $scale',
      (tester) async {
        final question =
            '${List.filled(25, 'Explain how energy flows through a living cell.').join(' ')} QUESTION END';
        final answer =
            '${List.filled(30, 'Energy is transferred through chemical reactions in the cell.').join(' ')} ANSWER END';
        await cards.delegate.updateContent(
          id: initial.first.id,
          question: question,
          answer: answer,
        );
        await start(tester, size: const Size(320, 640), textScale: scale);
        await begin(tester);
        expect(tester.takeException(), isNull);
        final questionView = tester.state<ScrollableState>(
          find
              .descendant(
                of: find.byKey(const ValueKey('question-scroll')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(questionView.position.maxScrollExtent, greaterThan(0));
        questionView.position.jumpTo(questionView.position.maxScrollExtent);
        await tester.pumpAndSettle();
        await reveal(tester);
        final answerView = tester.state<ScrollableState>(
          find
              .descendant(
                of: find.byKey(const ValueKey('answer-scroll')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(answerView.position.pixels, 0);
        expect(answerView.position.maxScrollExtent, greaterThan(0));
        answerView.position.jumpTo(answerView.position.maxScrollExtent);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        cards.failWrites = true;
        await tester.tap(find.byKey(const ValueKey('grade-known')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('retry-grade')).hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'question, answer and subsequent rounds expose accessible live updates',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await start(tester);
        await begin(tester);
        expect(
          tester.getSemantics(find.byType(FlashcardFlip)),
          isSemantics(isLiveRegion: true),
        );
        await reveal(tester);
        expect(
          tester.getSemantics(find.byType(FlashcardFlip)),
          isSemantics(isLiveRegion: true),
        );
        await tester.tap(find.byKey(const ValueKey('grade-review')));
        await tester.pumpAndSettle();
        await grade(tester);
        await retryRemaining(tester);
        expect(
          tester.getSemantics(find.text('Round 2')),
          isSemantics(isLiveRegion: true),
        );
        expect(
          find.text(
            'Only Review and skipped cards from the previous round repeat.',
          ),
          findsOneWidget,
        );
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('study and completion meet Android accessibility guidelines', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await start(tester);
      await begin(tester);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await reveal(tester);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await grade(tester);
      await grade(tester);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('left swipe skips from either face without grading or flipping', (
    tester,
  ) async {
    await start(tester, direct: true);
    expect(find.text('Swipe left to skip'), findsOneWidget);
    expect(find.text('Swipe left to skip').hitTestable(), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Skip'), findsNothing);
    for (final displacement in [const Offset(-50, 0), const Offset(210, 0)]) {
      await tester.drag(
        find.byKey(const ValueKey('reveal-card')),
        displacement,
      );
      await tester.pumpAndSettle();
      expect(find.text(initial.first.question), findsOneWidget);
      expect(find.byKey(const ValueKey('study-answer')), findsNothing);
    }
    await skip(tester);
    expect(find.text(initial.last.question), findsOneWidget);
    expect(find.byKey(const ValueKey('grade-known')), findsNothing);
    expect(find.text('1 Skipped this session'), findsOneWidget);
    expect(cards.gradeCalls, 0);
    await reveal(tester);
    await skip(tester);
    expect(find.text('Round 1 complete'), findsOneWidget);
    expect(cards.gradeCalls, 0);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Round 1 complete'), findsOneWidget);
    expect(find.text('Session complete'), findsNothing);
    expect(find.text('100%'), findsNothing);
    await capture(tester, '05-all-skipped-summary');
    await retryRemaining(tester);
    expect(find.text('Round 2'), findsOneWidget);
    expect(find.text(initial.first.question), findsOneWidget);
    expect(find.byKey(const ValueKey('study-answer')), findsNothing);
  });

  testWidgets(
    'summary counts and retry exclude Known and retain Review and Skip',
    (tester) async {
      final third = await cards.delegate.create(
        deckId: deck.id,
        question: 'Third question',
        answer: 'Third answer',
      );
      await start(tester, direct: true);
      await grade(tester);
      await grade(tester, known: false);
      await skip(tester);
      for (final entry in {
        'Cards mastered': 1,
        'Cards needing review': 1,
        'Skipped cards': 1,
        'Total cards remaining': 2,
      }.entries) {
        expect(
          tester
              .widget<Text>(find.byKey(ValueKey('summary-${entry.key}')))
              .data,
          '${entry.value}',
        );
      }
      await capture(tester, '06-mixed-summary');
      final retry = tester
          .widget<FilledButton>(find.byKey(const ValueKey('retry-remaining')))
          .onPressed!;
      retry();
      retry();
      await tester.pumpAndSettle();
      expect(find.text(initial.last.question), findsOneWidget);
      expect(find.text('2 left this round'), findsOneWidget);
      await grade(tester);
      expect(find.text(third.question), findsOneWidget);
      await skip(tester);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('summary-Cards mastered')))
            .data,
        '2',
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('summary-Total cards remaining')),
            )
            .data,
        '1',
      );
      await retryRemaining(tester);
      expect(find.text(third.question), findsOneWidget);
      await grade(tester);
      expect(find.text('Session complete'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
      expect(cards.gradeCalls, 4);
    },
  );

  testWidgets(
    'sliding left locks rapid swipes, taps and stale grading callbacks',
    (tester) async {
      await start(tester, direct: true);
      await reveal(tester);
      final gradeKnown = tester
          .widget<FilledButton>(find.byKey(const ValueKey('grade-known')))
          .onPressed!;
      final surface = find.byKey(const ValueKey('reveal-card'));
      final startPoint = tester.getCenter(surface);
      final first = await tester.startGesture(startPoint, pointer: 1);
      final second = await tester.startGesture(
        startPoint + const Offset(0, 10),
        pointer: 2,
      );
      await first.moveBy(const Offset(-210, 0));
      await first.up();
      await second.moveBy(const Offset(-210, 0));
      await second.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final translation = tester.widget<Transform>(
        find.byKey(const ValueKey('skip-card-translation')),
      );
      expect(translation.transform.storage[12], lessThan(-210));
      gradeKnown();
      await tester.dragFrom(startPoint, const Offset(-210, 0));
      await tester.tapAt(startPoint);
      await tester.pumpAndSettle();
      expect(find.text(initial.last.question), findsOneWidget);
      expect(find.byKey(const ValueKey('study-turn-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('study-answer')), findsNothing);
      expect(cards.gradeCalls, 0);
    },
  );

  testWidgets('pending writes block swipes and disposing a slide is safe', (
    tester,
  ) async {
    await start(tester, direct: true);
    await reveal(tester);
    final gate = Completer<void>();
    cards.writeGate = gate.future;
    await tester.tap(find.byKey(const ValueKey('grade-known')));
    await tester.pump();
    await tester.drag(
      find.byKey(const ValueKey('reveal-card')),
      const Offset(-210, 0),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('study-turn-0')), findsOneWidget);
    expect(cards.gradeCalls, 1);
    gate.complete();
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('reveal-card')),
      const Offset(-210, 0),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(cards.gradeCalls, 1);
  });

  testWidgets('long content scroll gestures do not skip or flip', (
    tester,
  ) async {
    await cards.delegate.updateContent(
      id: initial.first.id,
      question: List.filled(50, 'Long question text.').join(' '),
      answer: List.filled(50, 'Long answer text.').join(' '),
    );
    await start(tester, direct: true);
    for (final side in ['question', 'answer']) {
      if (side == 'answer') await reveal(tester);
      final scroll = find.byKey(ValueKey('$side-scroll'));
      final position = tester
          .state<ScrollableState>(
            find
                .descendant(of: scroll, matching: find.byType(Scrollable))
                .first,
          )
          .position;
      await tester.drag(scroll, const Offset(0, -160));
      await tester.pumpAndSettle();
      expect(position.pixels, greaterThan(0));
      expect(find.byKey(ValueKey('study-$side')), findsOneWidget);
      expect(find.byKey(const ValueKey('study-turn-0')), findsOneWidget);
    }
    expect(cards.gradeCalls, 0);
    await skip(tester);
    expect(find.text(initial.last.question), findsOneWidget);
  });

  testWidgets('holding the left arrow cannot skip the next card', (
    tester,
  ) async {
    await start(tester, direct: true);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.text(initial.last.question), findsOneWidget);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.text(initial.last.question), findsOneWidget);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.text('Round 1 complete'), findsOneWidget);
    expect(cards.gradeCalls, 0);
  });

  for (final setting in {
    'disabled animations': const FakeAccessibilityFeatures(
      disableAnimations: true,
    ),
    'accessible navigation': const FakeAccessibilityFeatures(
      accessibleNavigation: true,
    ),
  }.entries) {
    testWidgets('nonvisual Skip action and keyboard work with ${setting.key}', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            setting.value;
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        await start(tester, direct: true);
        final node = tester.getSemantics(find.byType(FlashcardFlip));
        final action = node
            .getSemanticsData()
            .customSemanticsActionIds!
            .singleWhere(
              (id) => CustomSemanticsAction.getAction(id)!.label == 'Skip card',
            );
        node.owner!.performAction(
          node.id,
          ui.SemanticsAction.customAction,
          action,
        );
        node.owner!.performAction(
          node.id,
          ui.SemanticsAction.customAction,
          action,
        );
        await tester.pump();
        expect(find.text(initial.last.question), findsOneWidget);
        await tester.pumpAndSettle();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump();
        expect(find.text('Round 1 complete'), findsOneWidget);
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowLeft);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pumpAndSettle();
        expect(cards.gradeCalls, 0);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await retryRemaining(tester);
        await skip(tester);
        expect(find.text(initial.last.question), findsOneWidget);
      } finally {
        semantics.dispose();
      }
    });
  }
}
