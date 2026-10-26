import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/text_preview.dart';
import '../../models/flashcard.dart';
import '../../repositories/deck_repository.dart';
import '../../repositories/flashcard_repository.dart';
import '../../widgets/app_states.dart';
import '../../widgets/delete_confirmation.dart';
import '../../widgets/flashcard_content.dart';
import '../../widgets/flashcard_flip.dart';
import '../../widgets/flashcard_surface.dart';
import '../../widgets/management_menu.dart';
import '../../widgets/mastery_summary.dart';
import '../../widgets/mastery_reset_confirmation.dart';
import '../flashcards/flashcard_editor_screen.dart';
import '../study/study_screen.dart';
import 'deck_detail_view_model.dart';
import 'deck_editor_screen.dart';

class DeckDetailScreen extends StatefulWidget {
  const DeckDetailScreen({
    super.key,
    required this.deckId,
    required this.deckRepository,
    required this.flashcardRepository,
  });
  final int deckId;
  final DeckRepository deckRepository;
  final FlashcardRepository flashcardRepository;

  @override
  State<DeckDetailScreen> createState() => _DeckDetailScreenState();
}

class _DeckDetailScreenState extends State<DeckDetailScreen> {
  late final DeckDetailViewModel _model;
  bool _navigationPending = false;

  @override
  void initState() {
    super.initState();
    _model = DeckDetailViewModel(
      deckId: widget.deckId,
      deckRepository: widget.deckRepository,
      flashcardRepository: widget.flashcardRepository,
    );
    unawaited(_model.load());
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  Future<void> _open(Widget screen) async {
    if (_navigationPending || _model.isBusy) return;
    _navigationPending = true;
    try {
      await _pushAndReload(screen);
    } finally {
      _navigationPending = false;
    }
  }

  Future<void> _pushAndReload(Widget screen) async {
    await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => screen));
    if (mounted) await _model.load();
  }

  StudyScreen _studyScreen() => StudyScreen(
    deckId: widget.deckId,
    deckRepository: widget.deckRepository,
    flashcardRepository: widget.flashcardRepository,
  );

  Future<void> _studyAgain() async {
    if (_navigationPending || !_model.canStudyAgain) return;
    _navigationPending = true;
    try {
      final confirmed = await confirmMasteryReset(
        context,
        title: _model.deck!.title,
      );
      if (!confirmed || !mounted) return;
      final reset = await _model.resetMastery();
      if (!mounted) return;
      if (!reset) {
        if (_model.resetError != null) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(_model.resetError!)));
        }
        return;
      }
      await _pushAndReload(_studyScreen());
    } finally {
      _navigationPending = false;
    }
  }

  void _editCard([Flashcard? card]) {
    unawaited(
      _open(
        FlashcardEditorScreen(
          repository: widget.flashcardRepository,
          deckId: widget.deckId,
          card: card,
        ),
      ),
    );
  }

  Future<void> _delete({Flashcard? card}) async {
    if (_navigationPending || _model.isBusy) return;
    final deck = _model.deck;
    if (deck == null) return;
    _navigationPending = true;
    try {
      final confirmed = await confirmDeletion(
        context,
        title: card?.question ?? deck.title,
        isDeck: card == null,
      );
      if (!confirmed || !mounted) return;
      final deleted = card == null
          ? await _model.deleteDeck()
          : await _model.deleteCard(card.id);
      if (!mounted) return;
      if (!deleted) {
        if (_model.deletionError != null) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(_model.deletionError!)));
        }
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(card == null ? 'Deck deleted.' : 'Flashcard deleted.'),
        ),
      );
      if (card == null) Navigator.pop(context, true);
    } finally {
      _navigationPending = false;
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _model,
    builder: (context, _) {
      final theme = Theme.of(context);
      final deck = _model.deck;
      final ready = deck != null && _model.error == null;
      return PopScope<bool>(
        canPop: !_model.isDeleting && !_model.isResetting,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Deck details'),
            actions: [
              if (deck != null)
                ManagementMenu(
                  subject: 'Deck',
                  tooltip: 'Deck options',
                  enabled: !_model.isBusy,
                  onStudyAgain: _model.canStudyAgain
                      ? () => unawaited(_studyAgain())
                      : null,
                  onSelected: (action) {
                    if (action == ManagementAction.edit) {
                      unawaited(
                        _open(
                          DeckEditorScreen(
                            repository: widget.deckRepository,
                            deck: deck,
                          ),
                        ),
                      );
                    } else {
                      unawaited(_delete());
                    }
                  },
                ),
              const SizedBox(width: 12),
            ],
          ),
          body: SafeArea(
            top: false,
            bottom: !ready,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: RefreshIndicator(
                  onRefresh: _model.load,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      if (_model.isLoading)
                        const SliverFillRemaining(
                          hasScrollBody: false,
                          child: LoadingState(
                            message: 'Loading your flashcards…',
                          ),
                        )
                      else if (_model.error != null)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: ErrorState(
                            message: _model.error!,
                            onRetry: _model.load,
                            actionLabel: 'Reload deck',
                          ),
                        )
                      else if (deck != null && _model.mastery != null) ...[
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                          sliver: SliverToBoxAdapter(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Semantics(
                                  header: true,
                                  child: Text(
                                    deck.title,
                                    style: theme.textTheme.headlineMedium,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${_model.cards.length} ${_model.cards.length == 1 ? 'flashcard' : 'flashcards'} in this deck',
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                if (_model.deletionError != null) ...[
                                  ReloadError(
                                    message: _model.deletionError!,
                                    label: 'Reload deck',
                                    onReload: _model.load,
                                  ),
                                  const SizedBox(height: 16),
                                ],
                                MasterySummary(stats: _model.mastery!),
                                const SizedBox(height: 28),
                                Semantics(
                                  header: true,
                                  child: Text(
                                    'Flashcards',
                                    style: theme.textTheme.titleLarge,
                                  ),
                                ),
                                if (_model.isDeleting) ...[
                                  const SizedBox(height: 12),
                                  const LinearProgressIndicator(
                                    semanticsLabel: 'Deleting…',
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        if (_model.cards.isEmpty)
                          const SliverFillRemaining(
                            hasScrollBody: false,
                            child: EmptyState(
                              icon: Icons.note_add_outlined,
                              title: 'A fresh start',
                              message: 'Add your first question and answer to build this deck. Your learning starts with one card.',
                            ),
                          )
                        else
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                            sliver: SliverList.separated(
                              itemCount: _model.cards.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 14),
                              itemBuilder: (context, index) {
                                final card = _model.cards[index];
                                return _FlashcardTile(
                                  key: ValueKey('flashcard-${card.id}'),
                                  card: card,
                                  enabled: !_model.isBusy,
                                  onEdit: () => _editCard(card),
                                  onDelete: () => _delete(card: card),
                                );
                              },
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          bottomNavigationBar: ready
              ? SafeArea(
                  top: false,
                  child: Center(
                    heightFactor: 1,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final hasCards = _model.cards.isNotEmpty;
                            final add = !hasCards
                                ? FilledButton.icon(
                                    key: const ValueKey('add-flashcard'),
                                    onPressed: _model.isBusy
                                        ? null
                                        : () => _editCard(),
                                    icon: const Icon(Icons.add_rounded),
                                    label: const Text('Add flashcard'),
                                  )
                                : OutlinedButton.icon(
                                    key: const ValueKey('add-flashcard'),
                                    onPressed: _model.isBusy
                                        ? null
                                        : () => _editCard(),
                                    icon: const Icon(Icons.add_rounded),
                                    label: const Text('Add flashcard'),
                                  );
                            final VoidCallback? startStudy =
                                !hasCards || _model.isBusy
                                ? null
                                : () => _open(_studyScreen());
                            final study = Tooltip(
                              message: _model.cards.isEmpty
                                  ? 'Add a flashcard first'
                                  : 'Study all flashcards in this deck',
                              child: hasCards
                                  ? FilledButton.icon(
                                      key: const ValueKey('study-button'),
                                      onPressed: startStudy,
                                      icon: const Icon(
                                        Icons.play_arrow_rounded,
                                      ),
                                      label: const Text('Study'),
                                    )
                                  : OutlinedButton.icon(
                                      key: const ValueKey('study-button'),
                                      onPressed: null,
                                      icon: const Icon(
                                        Icons.play_arrow_rounded,
                                      ),
                                      label: const Text('Study'),
                                    ),
                            );
                            if (constraints.maxWidth < 340 ||
                                MediaQuery.textScalerOf(context).scale(16) >
                                    20) {
                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (hasCards) study else add,
                                  const SizedBox(height: 10),
                                  if (hasCards) add else study,
                                ],
                              );
                            }
                            return Row(
                              children: [
                                Expanded(child: study),
                                const SizedBox(width: 12),
                                Expanded(child: add),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                )
              : null,
        ),
      );
    },
  );
}

class _FlashcardTile extends StatefulWidget {
  const _FlashcardTile({
    super.key,
    required this.card,
    required this.enabled,
    required this.onEdit,
    required this.onDelete,
  });
  final Flashcard card;
  final bool enabled;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  State<_FlashcardTile> createState() => _FlashcardTileState();
}

class _FlashcardTileState extends State<_FlashcardTile>
    with AutomaticKeepAliveClientMixin {
  final _questionScroll = ScrollController();
  final _answerScroll = ScrollController();

  // Keep each visited card's face and scroll position when it leaves the
  // viewport. These are presentation state only, never saved classifications.
  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _questionScroll.dispose();
    _answerScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final card = widget.card;
    final theme = Theme.of(context);
    final known = card.status == MasteryStatus.known;
    final growth = MediaQuery.sizeOf(context).height < 500 ? 1.15 : 1.18;
    return FlashcardFlip(
      // Editing either side resets to the question. Status-only changes are
      // independent of this temporary presentation state.
      key: ValueKey((card.deckId, card.id, card.question, card.answer)),
      allowFlipBack: true,
      enabled: widget.enabled,
      builder: (context, answerSide, onFlip) {
        final scroll = answerSide ? _answerScroll : _questionScroll;
        final foreground = FlashcardSurface.foreground(answerSide);
        return FlashcardSurface(
          answerSide: answerSide,
          onFlip: onFlip,
          tapKey: ValueKey('flip-flashcard-${card.id}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Menu buttons handle their own gestures. Disable them during
              // motion so their moving hit targets cannot be tapped.
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 12, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: known
                            ? const Color(0xFFE7F3ED)
                            : theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        known ? 'Known' : 'Review',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: known
                              ? const Color(0xFF246449)
                              : theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    ManagementMenu(
                      subject: 'flashcard',
                      iconColor: foreground,
                      tooltip:
                          'Options for flashcard: ${questionPreview(card.question)}',
                      enabled: widget.enabled && onFlip != null,
                      onSelected: (action) => action == ManagementAction.edit
                          ? widget.onEdit()
                          : widget.onDelete(),
                    ),
                  ],
                ),
              ),
              SizedBox(
                // Grow the previous complete face (including its 56dp header)
                // by 15–18%, using less growth on short landscape windows.
                // Content also scales with accessibility settings.
                // The new header takes 60dp; the remaining space is the body.
                height:
                    (236 + MediaQuery.textScalerOf(context).scale(14) * 3) *
                        growth -
                    60,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        answerSide ? 'ANSWER' : 'QUESTION',
                        style: theme.textTheme.labelSmall?.copyWith(
                          letterSpacing: 1.3,
                          fontWeight: FontWeight.w700,
                          color: foreground,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: FlashcardContent(
                          text: answerSide ? card.answer : card.question,
                          controller: scroll,
                          textColor: foreground,
                          scrollKey: ValueKey(
                            'flashcard-${card.id}-${answerSide ? 'answer' : 'question'}-scroll',
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        answerSide
                            ? 'Tap to show question'
                            : 'Tap to reveal answer',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: foreground,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
