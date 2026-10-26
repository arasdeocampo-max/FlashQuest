import 'package:flutter/material.dart';

import '../../models/deck.dart';
import '../../repositories/deck_repository.dart';
import '../../widgets/editor_layout.dart';
import 'deck_editor_view_model.dart';

class DeckEditorScreen extends StatefulWidget {
  const DeckEditorScreen({super.key, required this.repository, this.deck});
  final DeckRepository repository;
  final Deck? deck;

  @override
  State<DeckEditorScreen> createState() => _DeckEditorScreenState();
}

class _DeckEditorScreenState extends State<DeckEditorScreen> {
  late final DeckEditorViewModel _model;
  late final TextEditingController _title;
  final FocusNode _titleFocus = FocusNode();
  final GlobalKey _titleAnchor = GlobalKey();

  @override
  void initState() {
    super.initState();
    _model = DeckEditorViewModel(widget.repository, initialDeck: widget.deck);
    _title = TextEditingController(text: widget.deck?.title ?? '');
    _title.addListener(_contentChanged);
  }

  void _contentChanged() => setState(() {});

  @override
  void dispose() {
    _title.dispose();
    _titleFocus.dispose();
    _model.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final saved = await _model.save(_title.text);
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context, true);
    } else if (_model.titleError != null) {
      revealEditorField(_titleFocus, _titleAnchor);
    } else if (_model.error != null) {
      FocusScope.of(context).unfocus();
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _model,
    builder: (context, _) => EditorLayout(
      title: widget.deck == null ? 'Create deck' : 'Edit deck',
      isSaving: _model.isSaving,
      isSaved: _model.isSaved,
      hasUnsavedChanges: _title.text != (widget.deck?.title ?? ''),
      error: _model.error,
      invalidFieldKey: _model.titleError == null ? null : _titleAnchor,
      buttonLabel: widget.deck == null ? 'Create deck' : 'Save changes',
      onSave: _save,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.style_rounded,
            color: Theme.of(context).colorScheme.primary,
            size: 40,
          ),
          const SizedBox(height: 20),
          Text(
            widget.deck == null ? 'A home for your ideas' : 'Make it your own',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 10),
          Text(
            'Keep a subject, chapter, or big idea together.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),
          KeyedSubtree(
            key: _titleAnchor,
            child: TextField(
              key: const ValueKey('deck-title'),
              controller: _title,
              focusNode: _titleFocus,
              enabled: !_model.isSaving && !_model.isSaved,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
              onChanged: (_) => _model.clearValidation(),
              decoration: InputDecoration(
                labelText: 'Deck title',
                hintText: 'e.g. Biology · Cell structures',
                errorText: _model.titleError,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
