import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

typedef FlashcardFaceBuilder = Widget Function(
  BuildContext context,
  bool answerSide,
  VoidCallback? onFlip,
);

/// Shared flip motion and accessibility. Only the currently visible face is
/// built, so hidden answers are also absent from the semantics tree.
class FlashcardFlip extends StatefulWidget {
  const FlashcardFlip({
    super.key,
    required this.builder,
    this.allowFlipBack = false,
    this.enabled = true,
    this.onRevealed,
    this.customSemanticsActions,
    this.additionalHint,
  });

  final FlashcardFaceBuilder builder;
  final bool allowFlipBack;
  final bool enabled;
  final VoidCallback? onRevealed;
  final Map<CustomSemanticsAction, VoidCallback>? customSemanticsActions;
  final String? additionalHint;

  @override
  State<FlashcardFlip> createState() => _FlashcardFlipState();
}

class _FlashcardFlipState extends State<FlashcardFlip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _answer = false;
  bool _targetAnswer = false;
  bool _flipping = false;

  bool get _reducedMotion =>
      MediaQuery.disableAnimationsOf(context) ||
      MediaQuery.accessibleNavigationOf(context);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    )..addStatusListener(_animationStatus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reducedMotion && _controller.isAnimating) {
      _controller.value = _targetAnswer ? 1 : 0;
    }
  }

  void _animationStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed &&
        status != AnimationStatus.dismissed) {
      return;
    }
    setState(() {
      _flipping = false;
      _answer = status == AnimationStatus.completed;
    });
    if (_answer) widget.onRevealed?.call();
  }

  void _flip() {
    if (!widget.enabled || _flipping || (_answer && !widget.allowFlipBack)) {
      return;
    }
    setState(() {
      _flipping = true;
      _targetAnswer = !_answer;
    });
    if (_reducedMotion) {
      _controller.value = _targetAnswer ? 1 : 0;
    } else if (_targetAnswer) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) {
      // Keep perspective proportional on wide screens, leaving room for the
      // turning surface and its soft shadow inside the page's padding.
      final width = MediaQuery.sizeOf(context).width;
      final perspective = width.isFinite && width > 0
          ? math.min(0.0012, 0.4 / width)
          : 0.0012;
      final angle =
          Curves.easeInOutCubic.transform(_controller.value) * math.pi;
      final answerSide = angle >= math.pi / 2;
      final actionable = !_answer || widget.allowFlipBack;
      final canFlip = widget.enabled && !_flipping && actionable;
      return Semantics(
        container: true,
        liveRegion: true,
        label: answerSide ? 'Flashcard answer' : 'Flashcard question',
        button: actionable,
        enabled: widget.enabled && !_flipping,
        onTap: canFlip ? _flip : null,
        customSemanticsActions: widget.customSemanticsActions,
        hint: !actionable
            ? null
            : [
                answerSide ? 'Show the question' : 'Reveal the answer',
                ?widget.additionalHint,
              ].join('. '),
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, perspective)
            ..rotateY(angle),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.rotationY(answerSide ? math.pi : 0),
            child: widget.builder(context, answerSide, canFlip ? _flip : null),
          ),
        ),
      );
    },
  );
}
