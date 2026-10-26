import 'package:flashquest_drill/app_theme.dart';
import 'package:flashquest_drill/features/study/widgets/flippable_flashcard.dart';
import 'package:flashquest_drill/widgets/flashcard_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/visual_capture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);
  const question = 'What is ATP?';
  const answer = 'An energy carrier in living cells.';
  late int reveals;
  late GlobalKey preview;

  setUp(() {
    reveals = 0;
    preview = GlobalKey();
  });

  Future<void> start(
    WidgetTester tester, {
    String front = question,
    String back = answer,
    Size size = const Size(360, 420),
    bool enabled = true,
  }) async {
    await tester.pumpWidget(
      RepaintBoundary(
        key: preview,
        child: MaterialApp(
            debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 80),
              child: Center(
                child: SizedBox(
                  width: size.width,
                  height: size.height,
                  child: FlippableFlashcard(
                    question: front,
                    answer: back,
                    enabled: enabled,
                    onRevealed: () => reveals++,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final surface = find.byKey(const ValueKey('reveal-card'));

  testWidgets('text, edges, padding, labels, and empty areas flip both ways', (
    tester,
  ) async {
    await start(tester);
    final rect = tester.getRect(surface);
    final content = tester.getRect(find.byType(FlashcardContent));
    final points = [
      rect.topCenter + const Offset(0, 2),
      rect.bottomCenter - const Offset(0, 2),
      rect.centerLeft + const Offset(2, 0),
      rect.centerRight - const Offset(2, 0),
      rect.topLeft + const Offset(10, 10),
      rect.bottomRight - const Offset(10, 10),
      tester.getCenter(find.text(question)),
      tester.getCenter(find.text('QUESTION')),
      tester.getCenter(find.text('Tap to reveal the answer')),
      content.topLeft + const Offset(3, 8),
      content.bottomRight - const Offset(3, 8),
    ];
    for (final point in points) {
      await tester.tapAt(point);
      await tester.pumpAndSettle();
      expect(find.text(answer), findsOneWidget);
      expect(find.text(question), findsNothing);
      await tester.tapAt(point);
      await tester.pumpAndSettle();
      expect(find.text(question), findsOneWidget);
      expect(find.text(answer), findsNothing);
    }
    expect(reveals, points.length);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rapid taps cannot queue forward or reverse animations', (
    tester,
  ) async {
    await start(tester);
    for (final answerSide in [true, false]) {
      final point = tester.getTopLeft(surface) + const Offset(20, 20);
      for (var tap = 0; tap < 4; tap++) {
        await tester.tapAt(point);
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(tester.widget<InkWell>(surface).onTap, isNull);
      await tester.pumpAndSettle();
      expect(find.text(answerSide ? answer : question), findsOneWidget);
      expect(reveals, 1);
    }
  });

  testWidgets(
    'both face palettes and secondary text have accessible contrast',
    (tester) async {
      final previousShadows = debugDisableShadows;
      debugDisableShadows = false;
      try {
        await start(tester);
        for (final answerSide in [false, true]) {
          if (answerSide) {
            await tester.tap(surface);
            await tester.pumpAndSettle();
          }
          final background = answerSide
              ? const Color(0xFFEDE4FF)
              : const Color(0xFF7655BA);
          final foreground = answerSide
              ? const Color(0xFF38235D)
              : Colors.white;
          final card = tester.widget<Card>(find.byType(Card));
          expect(card.color, background);
          expect(card.surfaceTintColor, Colors.transparent);
          final texts = [
            find.text(answerSide ? answer : question),
            find.text(answerSide ? 'ANSWER' : 'QUESTION'),
            find.text(
              answerSide ? 'Tap to show question' : 'Tap to reveal the answer',
            ),
          ];
          for (final finder in texts) {
            final color = tester.widget<Text>(finder).style!.color!;
            expect(color, foreground);
            final light = color.computeLuminance();
            final dark = background.computeLuminance();
            final ratio = light > dark
                ? (light + .05) / (dark + .05)
                : (dark + .05) / (light + .05);
            expect(ratio, greaterThanOrEqualTo(4.5));
          }
          await capturePreview(
            tester,
            preview,
            answerSide ? '02-answer' : '01-question',
            outputDirectory: 'build/surface-preview',
          );
        }
      } finally {
        debugDisableShadows = previousShadows;
      }
    },
  );

  testWidgets('scrolling long content does not flip and both ends stay readable', (
    tester,
  ) async {
    final front =
        '${List.filled(35, 'Explain how a cell uses energy.').join(' ')} QUESTION END';
    final back =
        '${List.filled(35, 'Cells transfer energy through chemical reactions.').join(' ')} ANSWER END';
    await start(tester, front: front, back: back);
    for (final answerSide in [false, true]) {
      if (answerSide) {
        await tester.tapAt(tester.getTopLeft(surface) + const Offset(20, 20));
        await tester.pumpAndSettle();
      }
      final scroll = find.byKey(
        ValueKey(answerSide ? 'answer-scroll' : 'question-scroll'),
      );
      await tester.drag(scroll, const Offset(0, -120));
      await tester.pumpAndSettle();
      final position = tester
          .state<ScrollableState>(
            find.descendant(of: scroll, matching: find.byType(Scrollable)),
          )
          .position;
      expect(position.pixels, greaterThan(0));
      expect(find.text(answerSide ? back : front), findsOneWidget);
      expect(reveals, answerSide ? 1 : 0);
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(
        tester.getBottomRight(find.text(answerSide ? back : front)).dy,
        closeTo(tester.getBottomRight(scroll).dy, .1),
      );
      expect(tester.takeException(), isNull);
    }
  });

  for (final setting in {
    'disabled animation': const FakeAccessibilityFeatures(
      disableAnimations: true,
    ),
    'accessible navigation': const FakeAccessibilityFeatures(
      accessibleNavigation: true,
    ),
  }.entries) {
    testWidgets('full-surface flips respect ${setting.key}', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = setting.value;
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await start(tester);
      for (final answerSide in [true, false]) {
        await tester.tapAt(tester.getTopLeft(surface) + const Offset(20, 20));
        await tester.pump();
        expect(find.text(answerSide ? answer : question), findsOneWidget);
      }
      expect(reveals, 1);
    });
  }

  testWidgets('keyboard activation flips the focused card in both directions', (
    tester,
  ) async {
    await start(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text(answer), findsOneWidget);
    // The flip temporarily disables the card. Focus it again after motion,
    // as with other Material controls that become disabled during an action.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.text(question), findsOneWidget);
    expect(reveals, 1);
  });

  for (final width in [360.0, 720.0]) {
    testWidgets(
      'turning a $width wide card leaves horizontal room for its shadow',
      (tester) async {
        await start(tester, size: Size(width, 420));
        final viewport = tester.getRect(
          find.byType(SingleChildScrollView).first,
        );
        await tester.tapAt(tester.getTopLeft(surface) + const Offset(20, 20));
        await tester.pump();
        for (var step = 0; step < 8; step++) {
          await tester.pump(const Duration(milliseconds: 40));
          final box = tester.renderObject<RenderBox>(find.byType(Card));
          for (final corner in [
            Offset.zero,
            Offset(box.size.width, 0),
            Offset(0, box.size.height),
            box.size.bottomRight(Offset.zero),
          ]) {
            final point = box.localToGlobal(corner);
            expect(point.dx, greaterThanOrEqualTo(viewport.left + 10));
            expect(point.dx, lessThanOrEqualTo(viewport.right - 10));
          }
        }
        expect(find.text(answer), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
