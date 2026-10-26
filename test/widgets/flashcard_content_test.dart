import 'package:flashquest_drill/app_theme.dart';
import 'package:flashquest_drill/widgets/flashcard_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/visual_capture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);

  Future<ScrollController> showContent(
    WidgetTester tester, {
    required String text,
    required Size size,
    double scale = 1,
  }) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: FlashcardContent(text: text, controller: controller),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  for (final sample in [
    (name: 'single line', text: 'ATP', width: 360.0, fontSize: 26.0),
    (
      name: 'multiple lines',
      text: 'Energy\nfor living cells',
      width: 312.0,
      fontSize: 24.0,
    ),
    (
      name: 'narrow screen',
      text: 'Energy\nfor living cells',
      width: 232.0,
      fontSize: 22.0,
    ),
  ]) {
    testWidgets('${sample.name} is bold and centered in both axes', (
      tester,
    ) async {
      final controller = await showContent(
        tester,
        text: sample.text,
        size: Size(sample.width, 240),
      );
      final text = tester.widget<Text>(find.text(sample.text));
      expect(text.style!.fontWeight, FontWeight.bold);
      expect(text.style!.fontSize, sample.fontSize);
      expect(text.textAlign, TextAlign.center);
      final viewport = tester.getRect(find.byType(FlashcardContent));
      final textRect = tester.getRect(find.text(sample.text));
      expect(textRect.center.dx, closeTo(viewport.center.dx, 0.1));
      expect(textRect.center.dy, closeTo(viewport.center.dy, 0.1));
      expect(
        textRect.left - viewport.left,
        closeTo(viewport.right - textRect.right, 0.1),
      );
      expect(controller.position.maxScrollExtent, 0);
      expect(tester.takeException(), isNull);
    });
  }

  for (final configuration in [
    (name: 'small', size: const Size(232, 132), scale: 1.0),
    (name: 'large text', size: const Size(232, 132), scale: 2.0),
    (name: 'wide', size: const Size(520, 160), scale: 1.8),
  ]) {
    testWidgets(
      'long ${configuration.name} content can scroll from start to end',
      (tester) async {
        final content =
            '${List.filled(30, 'Explain how energy moves through a living cell.').join(' ')} END';
        final controller = await showContent(
          tester,
          text: content,
          size: configuration.size,
          scale: configuration.scale,
        );
        final text = tester.widget<Text>(find.text(content));
        expect(text.textAlign, TextAlign.center);
        expect(text.style!.fontWeight, FontWeight.bold);
        expect(text.style!.fontSize, 22);
        expect(text.maxLines, isNull);
        expect(text.overflow, isNull);
        final viewport = tester.getRect(find.byType(FlashcardContent));
        final start = tester.getRect(find.text(content));
        expect(start.top, closeTo(viewport.top, 0.1));
        expect(start.center.dx, closeTo(viewport.center.dx, 0.1));
        expect(start.left, greaterThanOrEqualTo(viewport.left + 12));
        expect(start.right, lessThanOrEqualTo(viewport.right - 12));
        expect(controller.position.maxScrollExtent, greaterThan(0));
        controller.jumpTo(controller.position.maxScrollExtent);
        await tester.pumpAndSettle();
        expect(
          tester.getBottomRight(find.text(content)).dy,
          closeTo(viewport.bottom, 0.1),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
