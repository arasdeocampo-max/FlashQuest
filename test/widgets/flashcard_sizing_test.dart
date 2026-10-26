import 'package:flashquest_drill/app.dart';
import 'package:flashquest_drill/widgets/flashcard_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/controlled_repositories.dart';
import '../support/memory_repositories.dart';
import '../support/visual_capture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);

  for (final layout in [
    (name: 'portrait', size: const Size(412, 892), scale: 1.0, long: false),
    (name: 'medium', size: const Size(412, 740), scale: 1.0, long: false),
    (
      name: 'small-large-text',
      size: const Size(320, 640),
      scale: 1.8,
      long: true,
    ),
    (name: 'landscape', size: const Size(640, 360), scale: 1.8, long: true),
  ]) {
    testWidgets(
      'larger cards retain width, stable faces, and grading in ${layout.name}',
      (tester) async {
        final previousShadows = debugDisableShadows;
        debugDisableShadows = false;
        try {
          tester.view.physicalSize = layout.size;
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = layout.scale;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final store = MemoryStore();
          final decks = MemoryDeckRepository(store);
          final cards = ControlledFlashcardRepository(
            MemoryFlashcardRepository(store),
          );
          final deck = await decks.create(title: 'Biology essentials');
          final question = layout.long
              ? '${List.filled(25, 'Explain how a cell uses energy.').join(' ')} QUESTION END'
              : 'What is ATP?';
          final answer = layout.long
              ? '${List.filled(30, 'Cells transfer energy through chemical reactions.').join(' ')} ANSWER END'
              : 'An energy carrier in living cells.';
          final card = await cards.delegate.create(
            deckId: deck.id,
            question: question,
            answer: answer,
          );
          final preview = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(
              key: preview,
              child: FlashQuestApp(
                deckRepository: decks,
                flashcardRepository: cards,
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.byKey(ValueKey('deck-${deck.id}')));
          await tester.pumpAndSettle();
          final dashboardCard = tester.getRect(
            find.byKey(ValueKey('deck-${deck.id}')),
          );
          final dashboardViewport = tester.getRect(
            find.byType(CustomScrollView),
          );
          await tester.tapAt(dashboardCard.intersect(dashboardViewport).center);
          await tester.pumpAndSettle();

          for (final study in [false, true]) {
            if (study) {
              await tester.tap(find.byKey(const ValueKey('study-button')));
              await tester.pumpAndSettle();
            }
            final face = find.byKey(
              ValueKey(study ? 'reveal-card' : 'flip-flashcard-${card.id}'),
            );
            final page = study
                ? find.byKey(const ValueKey('study-page-0'))
                : find.byType(CustomScrollView);
            if (!study) {
              await tester.scrollUntilVisible(
                face,
                180,
                scrollable: find
                    .descendant(of: page, matching: find.byType(Scrollable))
                    .first,
              );
            }
            await Scrollable.ensureVisible(tester.element(face), alignment: .4);
            await tester.pumpAndSettle();
            final frontSize = tester.getSize(face);
            expect(frontSize.width, closeTo(layout.size.width - 40, .1));
            final frontRect = tester.getRect(face);
            expect(frontRect.left, closeTo(20, .1));
            expect(layout.size.width - frontRect.right, closeTo(20, .1));

            if (study) {
              final body = find
                  .ancestor(of: page, matching: find.byType(LayoutBuilder))
                  .first;
              final minimum = 200 + 14 * layout.scale * 8;
              final previous = (tester.getSize(body).height - 190).clamp(
                minimum,
                minimum > 480 ? minimum : 480.0,
              );
              expect(frontSize.height / previous, closeTo(1.18, .001));
            } else {
              final previous = 236 + 14 * layout.scale * 3;
              final growth = layout.size.height < 500 ? 1.15 : 1.18;
              expect(frontSize.height / previous, closeTo(growth, .001));
            }

            for (final answerSide in [false, true]) {
              if (answerSide) {
                await Scrollable.ensureVisible(
                  tester.element(face),
                  alignment: .4,
                );
                await tester.pumpAndSettle();
                final visible = tester
                    .getRect(face)
                    .intersect(tester.getRect(page));
                expect(visible.isEmpty, isFalse);
                await tester.tapAt(visible.center);
                await tester.pumpAndSettle();
              }
              expect(tester.getSize(face), frontSize);
              final text = tester.widget<Text>(
                find.text(answerSide ? answer : question),
              );
              expect(text.textAlign, TextAlign.center);
              expect(text.style!.fontWeight, FontWeight.bold);
              expect(text.style!.fontSize, greaterThanOrEqualTo(22));
              expect(text.maxLines, isNull);
              final content = find.descendant(
                of: find.byType(FlashcardContent),
                matching: find.byType(Scrollable),
              );
              final position = tester.state<ScrollableState>(content).position;
              if (layout.long) {
                expect(position.maxScrollExtent, greaterThan(0));
                position.jumpTo(position.maxScrollExtent);
                await tester.pumpAndSettle();
                expect(position.extentAfter, 0);
              }
              expect(tester.takeException(), isNull);
              await capturePreview(
                tester,
                preview,
                '${layout.name}-${study ? 'study' : 'deck'}-${answerSide ? 'answer' : 'question'}',
                outputDirectory: 'build/native-size-preview',
              );
            }
            expect(cards.gradeCalls, 0);
            if (study) {
              expect(
                find.byKey(const ValueKey('grade-known')).hitTestable(),
                findsOneWidget,
              );
              expect(
                find.byKey(const ValueKey('grade-review')).hitTestable(),
                findsOneWidget,
              );
            }
          }

          await tester.tap(find.byKey(const ValueKey('grade-review')));
          await tester.pumpAndSettle();
          expect(find.text('Round 1 complete'), findsOneWidget);
          await tester.tap(find.byKey(const ValueKey('retry-remaining')));
          await tester.pumpAndSettle();
          expect(find.text('Round 2'), findsOneWidget);
          expect(find.text('1 Review this session'), findsOneWidget);
          final next = find.byKey(const ValueKey('reveal-card'));
          final nextPage = find.byKey(const ValueKey('study-page-1'));
          await Scrollable.ensureVisible(tester.element(next), alignment: .4);
          await tester.pumpAndSettle();
          await tester.tapAt(
            tester.getRect(next).intersect(tester.getRect(nextPage)).center,
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('grade-known')));
          await tester.pumpAndSettle();
          expect(cards.gradeCalls, 2);
          expect(find.text('Session complete'), findsOneWidget);
          expect(find.text('100%'), findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          debugDisableShadows = previousShadows;
        }
      },
    );
  }
}
