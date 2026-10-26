import 'dart:async';

import 'package:flutter/material.dart';

import '../../repositories/deck_repository.dart';
import '../../repositories/flashcard_repository.dart';
import '../../widgets/app_states.dart';
import '../../widgets/flashcard_surface.dart';
import '../../widgets/mastery_summary.dart';
import 'study_session.dart';
import 'study_view_model.dart';
import 'widgets/flippable_flashcard.dart';

class StudyScreen extends StatefulWidget {
  const StudyScreen({
    super.key,
    required this.deckId,
    required this.deckRepository,
    required this.flashcardRepository,
  });
  final int deckId;
  final DeckRepository deckRepository;
  final FlashcardRepository flashcardRepository;

  @override
  State<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends State<StudyScreen> {
  late final StudyViewModel _model;
  bool _leaving = false;
  (Size, TextScaler, EdgeInsets)? _cardLayout;
  double? _cardHeight;

  @override
  void initState() {
    super.initState();
    _model = StudyViewModel(
      deckId: widget.deckId,
      deckRepository: widget.deckRepository,
      flashcardRepository: widget.flashcardRepository,
    );
    unawaited(_model.start());
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  void _leave() {
    if (_leaving || _model.isSaving) return;
    _leaving = true;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _model,
    builder: (context, _) => PopScope<bool>(
      canPop: !_model.isSaving,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Study'),
          leading: IconButton(
            tooltip: 'Return to deck',
            onPressed: _model.isSaving ? null : _leave,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
        ),
        body: SafeArea(
          top: false,
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: _body(context),
            ),
          ),
        ),
        bottomNavigationBar: _bottomBar(context),
      ),
    ),
  );

  Widget _body(BuildContext context) {
    final theme = Theme.of(context);
    switch (_model.state) {
      case StudyState.initial:
      case StudyState.loading:
        return const SingleChildScrollView(
          child: LoadingState(message: 'Getting your flashcards ready…'),
        );
      case StudyState.loadError:
        return SingleChildScrollView(
          child: ErrorState(message: _model.error!, onRetry: _model.start),
        );
      case StudyState.empty:
        return const SingleChildScrollView(
          child: EmptyState(
            icon: Icons.note_add_outlined,
            title: 'No flashcards to study yet',
            message: 'Return to this deck and add a question and answer to get started.',
          ),
        );
      case StudyState.finishing:
        return const SingleChildScrollView(
          child: LoadingState(message: 'Loading your final mastery…'),
        );
      case StudyState.completionError:
        return SingleChildScrollView(
          child: ErrorState(
            message: _model.error!,
            onRetry: _model.retryCompletion,
          ),
        );
      case StudyState.roundSummary:
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                liveRegion: true,
                child: Text(
                  'Round ${_model.round} complete',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Retry the cards you marked Review or skipped when you’re ready.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _RoundCount(
                        label: 'Cards mastered',
                        count: _model.knownCount,
                      ),
                      const SizedBox(height: 16),
                      _RoundCount(
                        label: 'Cards needing review',
                        count: _model.reviewCount,
                      ),
                      const SizedBox(height: 16),
                      _RoundCount(
                        label: 'Skipped cards',
                        count: _model.skippedCount,
                      ),
                      const Divider(height: 32),
                      _RoundCount(
                        label: 'Total cards remaining',
                        count: _model.remainingCards,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Mastered counts reflect this session. Skipping leaves saved mastery unchanged.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
      case StudyState.complete:
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Icon(
                    Icons.check_rounded,
                    size: 44,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Semantics(
                header: true,
                liveRegion: true,
                child: Text(
                  'Session complete',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'You marked all ${_model.totalCards} ${_model.totalCards == 1 ? 'card' : 'cards'} Known in this session.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 28),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 16,
                    children: [
                      Text('Cards studied', style: theme.textTheme.titleMedium),
                      Text(
                        '${_model.totalCards}',
                        style: theme.textTheme.headlineMedium,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              MasterySummary(stats: _model.finalMastery!),
            ],
          ),
        );
      case StudyState.studying:
        final card = _model.currentCard!;
        final turn = _model.turn;
        return LayoutBuilder(
          builder: (context, constraints) {
            // Leave readable text space after labels and instructions grow
            // with accessibility text scaling. The page itself can scroll.
            final minimumHeight =
                200 + MediaQuery.textScalerOf(context).scale(14) * 8;
            final layout = (
              MediaQuery.sizeOf(context),
              MediaQuery.textScalerOf(context),
              MediaQuery.paddingOf(context),
            );
            // Recalculate when the window or accessibility settings change.
            // Keep the same face size when grading controls replace the reveal
            // prompt, so flipping does not resize the question and answer.
            if (_cardLayout != layout) {
              final previousHeight = (constraints.maxHeight - 190).clamp(
                minimumHeight,
                minimumHeight > 480 ? minimumHeight : 480.0,
              );
              _cardHeight = previousHeight * 1.18;
              _cardLayout = layout;
            }
            final height = _cardHeight!;
            return SingleChildScrollView(
              key: ValueKey('study-page-$turn'),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _model.deckTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Semantics(
                        liveRegion: true,
                        child: _SessionLabel(
                          text: 'Round ${_model.round}',
                          emphasized: true,
                        ),
                      ),
                      _SessionLabel(
                        text: '${_model.remainingInRound} left this round',
                      ),
                      _SessionLabel(
                        text: '${_model.reviewCount} Review this session',
                      ),
                      _SessionLabel(
                        text: '${_model.skippedCount} Skipped this session',
                      ),
                    ],
                  ),
                  if (_model.round > 1) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Only Review and skipped cards from the previous round repeat.',
                      key: const ValueKey('review-round-message'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Text(
                    '${_model.knownCount} of ${_model.totalCards} cards Known this session',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  LinearProgressIndicator(
                    value: _model.knownCount / _model.totalCards,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(6),
                    backgroundColor: theme.colorScheme.primaryContainer,
                    semanticsLabel: 'Cards Known in this session',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Swipe left to skip',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: height + FlashcardSurface.shadowPadding.vertical,
                    child: FlippableFlashcard(
                      key: ValueKey('study-turn-$turn'),
                      question: card.question,
                      answer: card.answer,
                      onRevealed: () => _model.revealAnswer(turn),
                      onSkipStarted: () => _model.beginSkip(turn),
                      onSkipped: () => _model.skip(expectedTurn: turn),
                      enabled: !_model.isSaving && !_model.isSkipping,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Known and Review choices are saved as you go.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            );
          },
        );
    }
  }

  Widget _bottomBar(BuildContext context) {
    final studying = _model.state == StudyState.studying;
    final summary = _model.state == StudyState.roundSummary;
    final hasReturn =
        _model.state == StudyState.complete ||
        _model.state == StudyState.empty ||
        _model.state == StudyState.completionError;
    if (!studying && !hasReturn && !summary) return const SizedBox.shrink();
    final saveFailed = studying && _model.error != null;
    final Widget actions;
    if (summary) {
      final round = _model.round;
      actions = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton(
            key: const ValueKey('retry-remaining'),
            onPressed: () => _model.retryRemaining(expectedRound: round),
            child: const Text('Retry Remaining Cards'),
          ),
          const SizedBox(height: 8),
          TextButton(
            key: const ValueKey('return-to-deck'),
            onPressed: _leave,
            child: const Text('Return to deck'),
          ),
        ],
      );
    } else if (hasReturn) {
      actions = FilledButton(
        key: const ValueKey('return-to-deck'),
        onPressed: _leave,
        child: const Text('Return to deck'),
      );
    } else if (saveFailed) {
      actions = FilledButton.icon(
        key: const ValueKey('retry-grade'),
        onPressed: _model.canRetryGrade ? _model.retryGrade : null,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Retry save'),
      );
    } else if (!_model.isRevealed) {
      actions = Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'Reveal the answer to choose Known or Review.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    } else if (_model.isSaving) {
      actions = const Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Flexible(child: Text('Saving your choice…')),
          ],
        ),
      );
    } else {
      actions = _gradeActions(context);
    }
    return SafeArea(
      top: false,
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Keep failed-save feedback and retry visible beside the actions,
                // including when a long card has been scrolled.
                if (saveFailed) ...[
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * 0.3,
                    ),
                    child: SingleChildScrollView(
                      child: InlineError(message: _model.error!),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                actions,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _gradeActions(BuildContext context) {
    final turn = _model.turn;
    return LayoutBuilder(
      builder: (context, constraints) {
        final review = OutlinedButton.icon(
          key: const ValueKey('grade-review'),
          onPressed: _model.canGrade
              ? () => _model.grade(StudyGrade.review, expectedTurn: turn)
              : null,
          icon: const Icon(Icons.replay_rounded),
          label: const Text('Review'),
        );
        final known = FilledButton.icon(
          key: const ValueKey('grade-known'),
          onPressed: _model.canGrade
              ? () => _model.grade(StudyGrade.known, expectedTurn: turn)
              : null,
          icon: const Icon(Icons.check_rounded),
          label: const Text('Known'),
        );
        if (constraints.maxWidth < 300 ||
            MediaQuery.textScalerOf(context).scale(16) > 20) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [known, const SizedBox(height: 10), review],
          );
        }
        return Row(
          children: [
            Expanded(child: review),
            const SizedBox(width: 12),
            Expanded(child: known),
          ],
        );
      },
    );
  }
}

class _RoundCount extends StatelessWidget {
  const _RoundCount({required this.label, required this.count});
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label: $count',
    excludeSemantics: true,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.titleMedium),
        ),
        const SizedBox(width: 16),
        Text(
          '$count',
          key: ValueKey('summary-$label'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ],
    ),
  );
}

class _SessionLabel extends StatelessWidget {
  const _SessionLabel({required this.text, this.emphasized = false});
  final String text;
  final bool emphasized;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: emphasized
          ? Theme.of(context).colorScheme.primaryContainer
          : Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 13,
        color: emphasized
            ? Theme.of(context).colorScheme.onPrimaryContainer
            : Theme.of(context).colorScheme.onSurfaceVariant,
        fontWeight: emphasized ? FontWeight.w600 : FontWeight.w400,
      ),
    ),
  );
}
