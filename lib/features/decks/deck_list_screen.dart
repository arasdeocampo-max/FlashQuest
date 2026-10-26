import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/mastery_percentage.dart';
import '../../models/deck.dart';
import '../../models/mastery_stats.dart';
import '../../repositories/deck_repository.dart';
import '../../repositories/flashcard_repository.dart';
import '../../widgets/app_states.dart';
import '../../widgets/delete_confirmation.dart';
import '../../widgets/management_menu.dart';
import 'deck_detail_screen.dart';
import 'deck_editor_screen.dart';
import 'deck_list_view_model.dart';

class DeckListScreen extends StatefulWidget {
  const DeckListScreen({
    super.key,
    required this.deckRepository,
    required this.flashcardRepository,
  });
  final DeckRepository deckRepository;
  final FlashcardRepository flashcardRepository;

  @override
  State<DeckListScreen> createState() => _DeckListScreenState();
}

class _DeckListScreenState extends State<DeckListScreen> {
  late final DeckListViewModel _model;
  bool _navigationPending = false;

  @override
  void initState() {
    super.initState();
    _model = DeckListViewModel(widget.deckRepository);
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
      await Navigator.of(context)
          .push<bool>(MaterialPageRoute(builder: (_) => screen));
      if (mounted) await _model.load();
    } finally {
      _navigationPending = false;
    }
  }

  Future<void> _delete(Deck deck) async {
    if (_navigationPending || _model.isBusy) return;
    _navigationPending = true;
    try {
      final confirmed = await confirmDeletion(
        context,
        title: deck.title,
        isDeck: true,
      );
      if (!confirmed || !mounted) return;
      final deleted = await _model.deleteDeck(deck.id);
      if (!deleted && mounted && _model.deletionError != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_model.deletionError!)));
      }
      if (deleted && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Deck deleted.')));
      }
    } finally {
      _navigationPending = false;
    }
  }

  void _manage(Deck deck, ManagementAction action) {
    switch (action) {
      case ManagementAction.edit:
        unawaited(
          _open(
            DeckEditorScreen(repository: widget.deckRepository, deck: deck),
          ),
        );
      case ManagementAction.delete:
        unawaited(_delete(deck));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Icon(
            Icons.style_rounded,
            color: theme.colorScheme.primary,
            size: 30,
          ),
        ),
        title: const Text('FlashQuest'),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListenableBuilder(
              listenable: _model,
              builder: (context, _) => RefreshIndicator(
                onRefresh: _model.load,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Semantics(
                              header: true,
                              child: Text(
                                'Your decks',
                                style: theme.textTheme.headlineLarge,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _model.decks.isEmpty
                                  ? 'Everything you’re learning, in one place.'
                                  : '${_model.decks.length} ${_model.decks.length == 1 ? 'deck' : 'decks'} · ${_model.totalCards} ${_model.totalCards == 1 ? 'flashcard' : 'flashcards'}',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                key: const ValueKey('create-deck'),
                                onPressed: _model.isBusy
                                    ? null
                                    : () => _open(
                                        DeckEditorScreen(
                                          repository: widget.deckRepository,
                                        ),
                                      ),
                                icon: const Icon(Icons.add_rounded),
                                label: const Text('Create deck'),
                              ),
                            ),
                            if (_model.deletionError != null) ...[
                              const SizedBox(height: 16),
                              ReloadError(
                                message: _model.deletionError!,
                                label: 'Reload decks',
                                onReload: _model.load,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (_model.isLoading)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: LoadingState(message: 'Loading your decks…'),
                      )
                    else if (_model.error != null)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: ErrorState(
                          message: _model.error!,
                          onRetry: _model.load,
                          actionLabel: 'Reload decks',
                        ),
                      )
                    else if (_model.decks.isEmpty)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: EmptyState(
                          icon: Icons.auto_stories_outlined,
                          title: 'Your first deck starts here',
                          message: 'Create a deck for a subject or topic, then add the questions you want to remember.',
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                        sliver: SliverList.separated(
                          itemCount: _model.decks.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 16),
                          itemBuilder: (context, index) {
                            final deck = _model.decks[index];
                            return _DeckCard(
                              deck: deck,
                              stats:
                                  _model.mastery[deck.id] ??
                                  MasteryStats(total: 0, known: 0),
                              enabled: !_model.isBusy,
                              onOpen: () => _open(
                                DeckDetailScreen(
                                  deckId: deck.id,
                                  deckRepository: widget.deckRepository,
                                  flashcardRepository:
                                      widget.flashcardRepository,
                                ),
                              ),
                              onManage: (action) => _manage(deck, action),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DeckCard extends StatelessWidget {
  const _DeckCard({
    required this.deck,
    required this.stats,
    required this.enabled,
    required this.onOpen,
    required this.onManage,
  });
  final Deck deck;
  final MasteryStats stats;
  final bool enabled;
  final VoidCallback onOpen;
  final ValueChanged<ManagementAction> onManage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: ValueKey('deck-${deck.id}'),
      child: InkWell(
        onTap: enabled ? onOpen : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 12, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.layers_outlined,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          deck.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${stats.total} ${stats.total == 1 ? 'flashcard' : 'flashcards'}',
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ManagementMenu(
                    subject: 'deck',
                    tooltip: 'Options for ${deck.title}',
                    enabled: enabled,
                    onSelected: onManage,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        Text(
                          '${formatMasteryPercentage(stats)} mastered',
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${stats.known} of ${stats.total} Known',
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: stats.percentage / 100,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(6),
                      backgroundColor: theme.colorScheme.primaryContainer,
                      semanticsLabel: '${deck.title} mastery',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
