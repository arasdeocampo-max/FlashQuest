import 'dart:ui' as ui;

import 'package:flashquest_drill/app.dart';
import 'package:flashquest_drill/widgets/flashcard_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/controlled_repositories.dart';
import '../support/memory_repositories.dart';
import '../support/visual_capture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);

  testWidgets(
    'outer shadow paints beyond the card clip in both screens and during flips',
    (tester) async {
      final previousShadows = debugDisableShadows;
      debugDisableShadows = false;
      try {
        tester.view.physicalSize = const Size(412, 892);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = MemoryStore();
        final decks = MemoryDeckRepository(store);
        final cards = ControlledFlashcardRepository(
          MemoryFlashcardRepository(store),
        );
        final deck = await decks.create(title: 'Biology essentials');
        final card = await cards.delegate.create(
          deckId: deck.id,
          question: 'What is ATP?',
          answer: 'An energy carrier in living cells.',
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
        await tester.tap(find.byKey(ValueKey('deck-${deck.id}')));
        await tester.pumpAndSettle();

        Future<void> verifyPaint(Finder face, {bool flipping = false}) async {
          final box = tester.renderObject<RenderBox>(face);
          // Sample outside the clipped Material. Wider cards now have 20dp
          // gutters; far blur-tail samples only apply inside the device window.
          final samples = [
            Offset(flipping ? -8 : -16, box.size.height / 2),
            Offset(box.size.width + (flipping ? 8 : 16), box.size.height / 2),
            if (!flipping) Offset(-28, box.size.height / 2),
            if (!flipping) Offset(box.size.width + 28, box.size.height / 2),
            Offset(box.size.width / 2, -8),
            Offset(box.size.width / 2, box.size.height + 24),
          ].map(box.localToGlobal).toList();
          final boundary =
              preview.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final pixels = (await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 1);
            try {
              final data = (await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              ))!;
              return (bytes: data, width: image.width, height: image.height);
            } finally {
              image.dispose();
            }
          }))!;
          final visibleSamples = samples
              .where(
                (point) =>
                    point.dx >= 0 &&
                    point.dx < pixels.width &&
                    point.dy >= 0 &&
                    point.dy < pixels.height,
              )
              .toList();
          expect(visibleSamples.length, greaterThanOrEqualTo(4));
          for (final point in visibleSamples) {
            final x = point.dx.round();
            final y = point.dy.round();
            expect(x, inInclusiveRange(0, pixels.width - 1));
            expect(y, inInclusiveRange(0, pixels.height - 1));
            final index = (y * pixels.width + x) * 4;
            final red = pixels.bytes.getUint8(index);
            final green = pixels.bytes.getUint8(index + 1);
            final blue = pixels.bytes.getUint8(index + 2);
            expect(pixels.bytes.getUint8(index + 3), 255);
            // The page is #FAF9FD. A visible purple-gray blur must darken it.
            expect(
              (250 - red) + (249 - green) + (253 - blue),
              greaterThanOrEqualTo(1),
              reason: 'Shadow missing at $point',
            );
          }
        }

        for (final study in [false, true]) {
          if (study) {
            await tester.tap(find.byKey(const ValueKey('study-button')));
            await tester.pumpAndSettle();
          }
          final face = find.byKey(
            ValueKey(study ? 'reveal-card' : 'flip-flashcard-${card.id}'),
          );
          await Scrollable.ensureVisible(tester.element(face), alignment: .5);
          await tester.pumpAndSettle();
          final faceRect = tester.getRect(face);
          final shadow = tester.widget<DecoratedBox>(
            find.byKey(const ValueKey('flashcard-outer-shadow')),
          );
          final decoration = shadow.decoration as BoxDecoration;
          expect(decoration.boxShadow, hasLength(1));
          final material = tester.widget<Card>(find.byType(Card).last);
          expect(material.elevation, 0);
          expect(material.clipBehavior, Clip.antiAlias);
          expect(material.color, FlashcardSurface.questionBackground);
          await verifyPaint(face);
          await capturePreview(
            tester,
            preview,
            study ? '04-study-question' : '02-deck-question',
            outputDirectory: 'build/redesign-preview',
          );

          await tester.tapAt(faceRect.topCenter + const Offset(0, 2));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          await capturePreview(
            tester,
            preview,
            study ? '07-study-flipping' : '06-deck-flipping',
            outputDirectory: 'build/redesign-preview',
            settle: false,
          );
          await verifyPaint(face, flipping: true);
          await tester.pumpAndSettle();
          expect(find.text(card.answer), findsOneWidget);
          expect(
            tester.widget<Card>(find.byType(Card).last).color,
            FlashcardSurface.answerBackground,
          );
          await verifyPaint(face);
          await capturePreview(
            tester,
            preview,
            study ? '05-study-answer' : '03-deck-answer',
            outputDirectory: 'build/redesign-preview',
          );

          await tester.tapAt(
            tester.getRect(face).centerLeft + const Offset(2, 0),
          );
          await tester.pumpAndSettle();
          expect(find.text(card.question), findsOneWidget);
          expect(cards.gradeCalls, 0);
          expect(cards.updateCalls, 0);
          expect(cards.deleteCalls, 0);
        }
        expect(tester.takeException(), isNull);
      } finally {
        debugDisableShadows = previousShadows;
      }
    },
  );
}
