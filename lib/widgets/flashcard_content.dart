import 'package:flutter/material.dart';

/// The readable area between a flashcard's label and its instructions. Short
/// content is centered in the available space; longer content scrolls in full.
class FlashcardContent extends StatelessWidget {
  const FlashcardContent({
    super.key,
    required this.text,
    required this.controller,
    this.scrollKey,
    this.textKey,
    this.textColor,
  });

  final String text;
  final ScrollController controller;
  final Key? scrollKey;
  final Key? textKey;
  final Color? textColor;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const horizontalPadding = 12.0;
      final textWidth = (constraints.maxWidth - horizontalPadding * 2).clamp(
        0.0,
        double.infinity,
      );
      var fontSize = textWidth < 260
          ? 22.0
          : textWidth < 320
          ? 24.0
          : 26.0;
      final baseStyle = Theme.of(context).textTheme.titleLarge!
          .copyWith(fontWeight: FontWeight.bold, height: 1.4, color: textColor);

      // Respect the user's text scaling. Keep long content at a readable 22sp
      // instead of shrinking it to fit or imposing a line limit.
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: baseStyle.copyWith(fontSize: fontSize),
        ),
        textAlign: TextAlign.center,
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        locale: Localizations.maybeLocaleOf(context),
      );
      try {
        painter.layout(maxWidth: textWidth);
        if (painter.height > constraints.maxHeight) fontSize = 22;
      } finally {
        painter.dispose();
      }

      return Scrollbar(
        controller: controller,
        child: SingleChildScrollView(
          key: scrollKey,
          controller: controller,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: horizontalPadding,
              ),
              child: Center(
                child: Text(
                  text,
                  key: textKey,
                  textAlign: TextAlign.center,
                  style: baseStyle.copyWith(fontSize: fontSize),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
