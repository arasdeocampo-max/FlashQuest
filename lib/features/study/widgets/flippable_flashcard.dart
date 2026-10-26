import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../../widgets/flashcard_content.dart';
import '../../../widgets/flashcard_flip.dart';
import '../../../widgets/flashcard_surface.dart';

/// One presentation of a card. Key by study turn, including when a one-card
/// Review round returns to the same ID, to reset animation and scroll position.
class FlippableFlashcard extends StatefulWidget {
  const FlippableFlashcard({
    super.key,
    required this.question,
    required this.answer,
    required this.onRevealed,
    this.onSkipStarted,
    this.onSkipped,
    this.enabled = true,
  });

  final String question;
  final String answer;
  final VoidCallback onRevealed;
  final bool Function()? onSkipStarted;
  final VoidCallback? onSkipped;
  final bool enabled;

  @override
  State<FlippableFlashcard> createState() => _FlippableFlashcardState();
}

class _FlippableFlashcardState extends State<FlippableFlashcard>
    with SingleTickerProviderStateMixin {
  final ScrollController _questionScroll = ScrollController();
  final ScrollController _answerScroll = ScrollController();
  late final AnimationController _slide;
  double _offset = 0;
  double _from = 0;
  double _to = 0;
  bool _dragging = false;
  bool _settling = false;
  bool _leaving = false;

  bool get _reducedMotion =>
      MediaQuery.disableAnimationsOf(context) ||
      MediaQuery.accessibleNavigationOf(context);
  bool get _canSkip =>
      widget.enabled && widget.onSkipped != null && !_settling && !_leaving;

  @override
  void initState() {
    super.initState();
    _slide =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 220),
        )..addListener(() {
          setState(() {
            _offset =
                _from +
                (_to - _from) * Curves.easeOutCubic.transform(_slide.value);
          });
        });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reducedMotion && _slide.isAnimating) _slide.value = 1;
  }

  Future<void> _moveTo(double target) async {
    _from = _offset;
    _to = target;
    if (_reducedMotion) {
      setState(() => _offset = target);
    } else {
      await _slide.forward(from: 0).orCancel;
    }
  }

  Future<void> _skip() async {
    if (!_canSkip || !(widget.onSkipStarted?.call() ?? true)) return;
    setState(() {
      _leaving = true;
      _dragging = false;
    });
    try {
      // Translate the whole surface, including its existing outer shadow.
      if (!_reducedMotion) await _moveTo(-MediaQuery.sizeOf(context).width);
      if (mounted) widget.onSkipped!();
    } on TickerCanceled {
      // Leaving the screen during a slide must not advance a disposed session.
    }
  }

  Future<void> _resetDrag() async {
    setState(() {
      _dragging = false;
      _settling = true;
    });
    try {
      await _moveTo(0);
      if (mounted) setState(() => _settling = false);
    } on TickerCanceled {
      // The card can be removed while returning to its starting position.
    }
  }

  @override
  void dispose() {
    _slide.dispose();
    _questionScroll.dispose();
    _answerScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final face = _buildFace(context);
    if (widget.onSkipped == null) return face;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(
          LogicalKeyboardKey.arrowLeft,
          includeRepeats: false,
        ): () =>
            unawaited(_skip()),
      },
      child: Focus(
        autofocus: true,
        includeSemantics: false,
        child: LayoutBuilder(
          builder: (context, constraints) => GestureDetector(
            key: const ValueKey('skip-card-gesture'),
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            dragStartBehavior: DragStartBehavior.down,
            onHorizontalDragStart: _canSkip
                ? (_) => setState(() => _dragging = true)
                : null,
            onHorizontalDragUpdate: _canSkip
                ? (details) {
                    if (!_dragging) return;
                    setState(() {
                      _offset = (_offset + details.delta.dx).clamp(
                        -constraints.maxWidth,
                        0,
                      );
                    });
                  }
                : null,
            onHorizontalDragEnd: _canSkip
                ? (_) {
                    if (!_dragging) return;
                    // Distance, not velocity, determines intent. Short flicks
                    // and right swipes never skip or become taps.
                    final threshold = (constraints.maxWidth * .28).clamp(
                      96.0,
                      160.0,
                    );
                    unawaited(_offset <= -threshold ? _skip() : _resetDrag());
                  }
                : null,
            onHorizontalDragCancel: _canSkip
                ? () {
                    if (_dragging) unawaited(_resetDrag());
                  }
                : null,
            child: Transform.translate(
              key: const ValueKey('skip-card-translation'),
              offset: Offset(_reducedMotion ? 0 : _offset, 0),
              child: face,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFace(BuildContext context) => FlashcardFlip(
    onRevealed: widget.onRevealed,
    allowFlipBack: true,
    enabled: widget.enabled && !_dragging && !_settling && !_leaving,
    customSemanticsActions: _canSkip
        ? {
            const CustomSemanticsAction(label: 'Skip card'): () =>
                unawaited(_skip()),
          }
        : null,
    additionalHint: widget.onSkipped == null
        ? null
        : 'Skip card action available. Left arrow key to skip',
    builder: (context, answerSide, onFlip) {
      final scroll = answerSide ? _answerScroll : _questionScroll;
      final theme = Theme.of(context);
      final foreground = FlashcardSurface.foreground(answerSide);
      return FlashcardSurface(
        answerSide: answerSide,
        onFlip: onFlip,
        tapKey: const ValueKey('reveal-card'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    answerSide
                        ? Icons.lightbulb_outline_rounded
                        : Icons.help_outline_rounded,
                    size: 22,
                    color: foreground,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      answerSide ? 'ANSWER' : 'QUESTION',
                      style: TextStyle(
                        fontSize: 12,
                        letterSpacing: 1.3,
                        fontWeight: FontWeight.w700,
                        color: foreground,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Expanded(
                child: FlashcardContent(
                  text: answerSide ? widget.answer : widget.question,
                  controller: scroll,
                  textColor: foreground,
                  scrollKey: ValueKey(
                    answerSide ? 'answer-scroll' : 'question-scroll',
                  ),
                  textKey: ValueKey(
                    answerSide ? 'study-answer' : 'study-question',
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                answerSide
                    ? 'Tap to show question'
                    : 'Tap to reveal the answer',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: foreground),
              ),
            ],
          ),
        ),
      );
    },
  );
}
