import 'dart:async';

import 'package:flashquest_drill/app.dart';
import 'package:flashquest_drill/features/decks/deck_detail_screen.dart';
import 'package:flashquest_drill/features/decks/deck_editor_screen.dart';
import 'package:flashquest_drill/features/flashcards/flashcard_editor_screen.dart';
import 'package:flashquest_drill/models/deck.dart';
import 'package:flashquest_drill/models/flashcard.dart';
import 'package:flashquest_drill/widgets/app_states.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/controlled_repositories.dart';
import 'support/memory_repositories.dart';
import 'support/visual_capture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);
  late ControlledDeckRepository decks;
  late ControlledFlashcardRepository cards;
  late Deck deck;
  late Flashcard card;
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
    card = await cards.delegate.setMasteryStatus(
      id: created.id,
      status: MasteryStatus.known,
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
    addTearDown(tester.view.resetViewInsets);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      RepaintBoundary(
        key: preview,
        child: FlashQuestApp(deckRepository: decks, flashcardRepository: cards),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester, Widget screen) async {
    unawaited(
      Navigator.of(tester.element(find.text('Your decks')))
          .push<bool>(MaterialPageRoute(builder: (_) => screen)),
    );
    await tester.pumpAndSettle();
  }

  Widget details([Deck? selected]) => DeckDetailScreen(
    deckId: (selected ?? deck).id,
    deckRepository: decks,
    flashcardRepository: cards,
  );

  Widget cardEditor({bool create = false}) => FlashcardEditorScreen(
    repository: cards,
    deckId: deck.id,
    card: create ? null : card,
  );

  Future<void> enter(WidgetTester tester, String field, String text) async {
    final finder = find.byKey(ValueKey(field));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.enterText(finder, text);
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) => capturePreview(
    tester,
    preview,
    name,
    outputDirectory: 'build/phase4b-preview',
  );

  final save = find.byKey(const ValueKey('save-button'));

  testWidgets(
    'dashboard and detail consistently show 99 percent at 199 of 200',
    (tester) async {
      for (var i = 1; i < 200; i++) {
        final created = await cards.delegate.create(
          deckId: deck.id,
          question: 'Question $i',
          answer: 'Answer $i',
        );
        if (i < 199) {
          await cards.delegate.setMasteryStatus(
            id: created.id,
            status: MasteryStatus.known,
          );
        }
      }
      await start(tester);
      expect(find.text('99% mastered'), findsOneWidget);
      await open(tester, details());
      expect(find.text('99%'), findsOneWidget);
      expect(find.text('100%'), findsNothing);
      final saved = await decks.getMasteryStats(deck.id);
      expect(saved.percentage, 99.5);
      expect(saved.review, 1);
    },
  );

  testWidgets('Study is primary for populated decks and Add for empty decks', (
    tester,
  ) async {
    final empty = await decks.delegate.create(title: 'A fresh subject');
    await start(tester);
    await open(tester, details());
    expect(
      tester.widget(find.byKey(const ValueKey('study-button'))),
      isA<FilledButton>(),
    );
    expect(
      tester.widget(find.byKey(const ValueKey('add-flashcard'))),
      isA<OutlinedButton>(),
    );
    await capture(tester, '01-study-primary');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await open(tester, details(empty));
    expect(
      tester.widget(find.byKey(const ValueKey('add-flashcard'))),
      isA<FilledButton>(),
    );
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const ValueKey('study-button')))
          .onPressed,
      isNull,
    );
    await capture(tester, '02-empty-deck');
  });

  testWidgets('invalid deck title gains focus and is revealed above keyboard', (
    tester,
  ) async {
    await start(tester, size: const Size(320, 640), scale: 1.8);
    await open(tester, DeckEditorScreen(repository: decks));
    await tester.tap(save);
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('deck-title'));
    expect(tester.widget<TextField>(field).focusNode!.hasPrimaryFocus, isTrue);
    expect(tester.getTopLeft(field).dy, greaterThanOrEqualTo(56));
    expect(
      tester.getBottomRight(field).dy,
      lessThan(tester.getTopLeft(save).dy),
    );
    expect(save.hitTestable(), findsOneWidget);
    expect(tester.getBottomRight(save).dy, lessThanOrEqualTo(400));
    expect(decks.createCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'validation focuses the first invalid card field, then the answer',
    (tester) async {
      await start(tester, size: const Size(320, 640));
      await open(tester, cardEditor(create: true));
      tester.view.viewInsets = const FakeViewPadding(bottom: 240);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      final question = find.byKey(const ValueKey('card-question'));
      final answer = find.byKey(const ValueKey('card-answer'));
      expect(
        tester.widget<TextField>(question).focusNode!.hasPrimaryFocus,
        isTrue,
      );
      await enter(
        tester,
        'card-question',
        List.filled(20, 'A long question.').join(' '),
      );
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(answer).focusNode!.hasPrimaryFocus,
        isTrue,
      );
      expect(tester.getTopLeft(answer).dy, greaterThanOrEqualTo(56));
      expect(
        tester.getTopLeft(answer).dy,
        lessThan(tester.getTopLeft(save).dy),
      );
      expect(cards.createCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  for (final editCard in [false, true]) {
    testWidgets(
      '${editCard ? 'card' : 'deck'} editor skips warnings for unchanged and reverted text',
      (tester) async {
        await start(tester);
        await open(
          tester,
          editCard
              ? cardEditor()
              : DeckEditorScreen(repository: decks, deck: deck),
        );
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.text('Discard changes?'), findsNothing);
        expect(find.text('Your decks'), findsOneWidget);
        await open(
          tester,
          editCard
              ? cardEditor()
              : DeckEditorScreen(repository: decks, deck: deck),
        );
        final key = editCard ? 'card-answer' : 'deck-title';
        final original = editCard ? card.answer : deck.title;
        await enter(tester, key, '$original changed');
        await enter(tester, key, original);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.text('Discard changes?'), findsNothing);
        expect(find.text('Your decks'), findsOneWidget);
      },
    );
  }

  testWidgets(
    'dirty deck has one Stay or Discard dialog and never writes on discard',
    (tester) async {
      await start(tester);
      await open(tester, DeckEditorScreen(repository: decks, deck: deck));
      await enter(tester, 'deck-title', 'Unsaved subject');
      final back = tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) => widget is IconButton && widget.tooltip == 'Back',
            ),
          )
          .onPressed!;
      back();
      back();
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(find.text('Stay'));
      await tester.pumpAndSettle();
      expect(find.text('Unsaved subject'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.text('Your decks'), findsOneWidget);
      expect((await decks.delegate.getById(deck.id))!.title, deck.title);
      expect(decks.updateCalls, 0);
    },
  );

  testWidgets('dirty card can Stay and save without a discard prompt', (
    tester,
  ) async {
    await start(tester);
    await open(tester, cardEditor());
    await enter(tester, 'card-answer', 'A clearer explanation.');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stay'));
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsNothing);
    expect(find.text('Your decks'), findsOneWidget);
    final saved = (await cards.delegate.getById(card.id))!;
    expect(saved.answer, 'A clearer explanation.');
    expect(saved.status, MasteryStatus.review);
    expect(cards.updateCalls, 1);
  });

  testWidgets('discarding card edits keeps saved content and Known mastery', (
    tester,
  ) async {
    await start(tester);
    await open(tester, cardEditor());
    await enter(tester, 'card-question', 'An unsaved question');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(await cards.delegate.getById(card.id), card);
    expect(cards.updateCalls, 0);
  });

  testWidgets(
    'dirty card cannot prompt or double submit during a pending save',
    (tester) async {
      await start(tester);
      await open(tester, cardEditor());
      await enter(tester, 'card-answer', 'Updated answer');
      final gate = Completer<void>();
      cards.writeGate = gate.future;
      final submit = tester.widget<FilledButton>(save).onPressed!;
      submit();
      submit();
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('Discard changes?'), findsNothing);
      expect(cards.updateCalls, 1);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Your decks'), findsOneWidget);
      expect(find.text('Discard changes?'), findsNothing);
    },
  );

  for (final layout in [
    (name: 'small', size: const Size(320, 640), scale: 1.0, keyboard: 240.0),
    (
      name: 'large-text',
      size: const Size(320, 640),
      scale: 1.8,
      keyboard: 240.0,
    ),
    (
      name: 'landscape',
      size: const Size(640, 360),
      scale: 1.8,
      keyboard: 140.0,
    ),
  ]) {
    testWidgets(
      'Save, reset notice and save errors remain accessible with ${layout.name} keyboard',
      (tester) async {
        await start(tester, size: layout.size, scale: layout.scale);
        await open(tester, cardEditor());
        await enter(
          tester,
          'card-answer',
          List.filled(50, 'Long explanation.').join(' '),
        );
        tester.view.viewInsets = FakeViewPadding(bottom: layout.keyboard);
        await tester.pumpAndSettle();
        expect(save.hitTestable(), findsOneWidget);
        expect(
          tester.getBottomRight(save).dy,
          lessThanOrEqualTo(layout.size.height - layout.keyboard),
        );
        expect(
          find.byKey(const ValueKey('mastery-reset-notice')),
          findsOneWidget,
        );
        final noticeText = find.text('Content edits reset mastery to Review.');
        final feedbackBounds = tester.getRect(
          find.byKey(const ValueKey('editor-feedback')),
        );
        expect(
          tester.getTopLeft(noticeText).dy,
          greaterThanOrEqualTo(feedbackBounds.top),
        );
        expect(
          tester.getBottomRight(noticeText).dy,
          lessThanOrEqualTo(feedbackBounds.bottom),
        );
        await capture(tester, '03-editor-${layout.name}');
        cards.failWrites = true;
        await tester.tap(save);
        await tester.pumpAndSettle();
        final feedback = find.byKey(const ValueKey('editor-feedback'));
        expect(feedback.hitTestable(), findsOneWidget);
        expect(tester.getTopLeft(feedback).dy, greaterThanOrEqualTo(56));
        expect(
          tester.getBottomRight(feedback).dy,
          lessThanOrEqualTo(tester.getTopLeft(save).dy),
        );
        expect(
          find.textContaining('couldn’t save this flashcard'),
          findsOneWidget,
        );
        expect(save.hitTestable(), findsOneWidget);
        await tester.drag(feedback, const Offset(0, -600));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
        await capture(tester, '04-error-${layout.name}');
        cards.failWrites = false;
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(find.text('Your decks'), findsOneWidget);
      },
    );
  }

  testWidgets(
    'rotation retains draft, then reveals invalid field without overflow',
    (tester) async {
      await start(tester, size: const Size(320, 640), scale: 1.8);
      await open(tester, cardEditor(create: true));
      await enter(tester, 'card-question', 'A draft that survives rotation');
      tester.view.physicalSize = const Size(640, 360);
      tester.view.viewInsets = const FakeViewPadding(bottom: 140);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('card-answer')))
            .focusNode!
            .hasPrimaryFocus,
        isTrue,
      );
      expect(find.text('A draft that survives rotation'), findsOneWidget);
      expect(save.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'flashcard deletion preview is bounded, identifiable and cancellable',
    (tester) async {
      final question =
          'Explain ATP 👩🏽‍🔬\n${List.filled(100, 'and energy').join(' ')}';
      await cards.delegate.updateContent(
        id: card.id,
        question: question,
        answer: card.answer,
      );
      await start(tester, size: const Size(320, 640), scale: 1.8);
      await open(tester, details());
      final menu = find.byTooltip(RegExp('^Options for flashcard:'));
      await tester.scrollUntilVisible(
        menu,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete flashcard'));
      await tester.pumpAndSettle();
      final text = tester.widget<Text>(
        find.byKey(const ValueKey('delete-question-preview')),
      );
      expect(text.data, startsWith('Explain ATP 👩🏽‍🔬'));
      expect(text.data, endsWith('…'));
      expect(text.maxLines, 3);
      expect(text.overflow, TextOverflow.ellipsis);
      expect(text.semanticsLabel, startsWith('Flashcard question:'));
      expect(cards.deleteCalls, 0);
      await capture(tester, '05-delete-confirmation');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(cards.deleteCalls, 0);
      expect(await cards.delegate.getById(card.id), isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'dashboard deletion failure retains cards and reload never deletes',
    (tester) async {
      await start(tester);
      Future<void> requestDelete() async {
        await tester.tap(find.byTooltip('Options for ${deck.title}'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete deck'));
        await tester.pumpAndSettle();
      }

      await requestDelete();
      decks.failWrites = true;
      await tester.tap(find.byKey(const ValueKey('confirm-delete')));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('deck-${deck.id}')), findsOneWidget);
      expect(find.text('100% mastered'), findsOneWidget);
      expect(find.text('Reload decks'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
      await capture(tester, '06-delete-error');
      decks.failWrites = false;
      await tester.tap(find.text('Reload decks'));
      await tester.pumpAndSettle();
      expect(decks.deleteCalls, 1);
      expect(await cards.delegate.getById(card.id), card);
      await requestDelete();
      expect(find.text('Delete deck?'), findsOneWidget);
      expect(decks.deleteCalls, 1);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(decks.deleteCalls, 1);
    },
  );

  testWidgets(
    'empty, loading and error states scroll in a short landscape viewport',
    (tester) async {
      await start(tester, size: const Size(640, 360), scale: 1.8);
      for (final state in [
        const EmptyState(
          icon: Icons.note_add_outlined,
          title: 'No flashcards yet',
          message: 'Add your first question and answer.',
        ),
        const LoadingState(message: 'Loading your flashcards…'),
        ErrorState(
          message:
              'We couldn’t load this deck. Reload to try reading it again.',
          onRetry: () {},
          actionLabel: 'Reload deck',
        ),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: SizedBox(height: 100, child: state)),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(1.8)),
              child: child!,
            ),
          ),
        );
        await tester.pump();
        await tester.drag(
          find.byType(SingleChildScrollView).first,
          const Offset(0, -800),
        );
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull);
        if (state is ErrorState) {
          expect(find.text('Reload deck').hitTestable(), findsOneWidget);
        }
      }
    },
  );

  testWidgets('editors and discard dialog have accessible targets and labels', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await start(tester);
    for (final editor in [DeckEditorScreen(repository: decks), cardEditor()]) {
      await open(tester, editor);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
    await open(tester, DeckEditorScreen(repository: decks));
    await enter(tester, 'deck-title', 'Unsaved');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    semantics.dispose();
  });
}
