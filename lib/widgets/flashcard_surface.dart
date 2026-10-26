import 'package:flutter/material.dart';

/// Shared face colors, shape, shadow, and full-surface interaction. InkWell's
/// opaque hit testing includes empty space; nested menu buttons win their own
/// gestures without invoking the card's tap callback.
class FlashcardSurface extends StatelessWidget {
  const FlashcardSurface({
    super.key,
    required this.answerSide,
    required this.onFlip,
    required this.child,
    this.tapKey,
  });

  static const questionBackground = Color(0xFF7655BA);
  static const questionForeground = Color(0xFFFFFFFF);
  static const answerBackground = Color(0xFFEDE4FF);
  static const answerForeground = Color(0xFF38235D);
  // The pages already provide 20dp horizontal gutters. Reserve vertical space
  // for the stronger shadow without narrowing the card a second time.
  static const shadowPadding = EdgeInsets.fromLTRB(0, 24, 0, 40);

  static Color foreground(bool answerSide) =>
      answerSide ? answerForeground : questionForeground;

  final bool answerSide;
  final VoidCallback? onFlip;
  final Widget child;
  final Key? tapKey;

  @override
  Widget build(BuildContext context) {
    final foregroundColor = foreground(answerSide);
    // Reserve external room for the blur. Only the inner Material clips its
    // contents; the one outer box shadow remains outside the rounded clip.
    return Padding(
      padding: shadowPadding,
      child: DecoratedBox(
        key: const ValueKey('flashcard-outer-shadow'),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Color(0x55715AA6),
              blurRadius: 22,
              spreadRadius: 2,
              offset: Offset(0, 9),
            ),
          ],
        ),
        child: Card(
          color: answerSide ? answerBackground : questionBackground,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          shadowColor: Colors.transparent,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: tapKey,
            onTap: onFlip,
            excludeFromSemantics: true,
            // Avoid a press sparkle obscuring the face during the 3D turn.
            // InkWell still supplies keyboard focus and opaque tap handling.
            splashFactory: NoSplash.splashFactory,
            highlightColor: Colors.transparent,
            child: ScrollbarTheme(
              data: ScrollbarTheme.of(context).copyWith(
                thumbColor: WidgetStatePropertyAll(
                  foregroundColor.withValues(alpha: 0.8),
                ),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
