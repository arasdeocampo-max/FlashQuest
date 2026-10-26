import 'package:flutter/material.dart';

import '../../models/flashcard.dart';
import '../../repositories/flashcard_repository.dart';
import '../../widgets/editor_layout.dart';
import 'flashcard_editor_view_model.dart';

class FlashcardEditorScreen extends StatefulWidget {
  const FlashcardEditorScreen({
    super.key,
    required this.repository,
    required this.deckId,
    this.card,
  });
  final FlashcardRepository repository;
  final int deckId;
  final Flashcard? card;

  @override
  State<FlashcardEditorScreen> createState() => _FlashcardEditorScreenState();
}

class _FlashcardEditorScreenState extends State<FlashcardEditorScreen> {
  late final FlashcardEditorViewModel _model;
  late final TextEditingController _question;
  late final TextEditingController _answer;
  final FocusNode _questionFocus = FocusNode();
  final FocusNode _answerFocus = FocusNode();
  final GlobalKey _questionAnchor = GlobalKey();
  final GlobalKey _answerAnchor = GlobalKey();

  @override
  void initState() {
    super.initState();
    _model = FlashcardEditorViewModel(
      widget.repository,
      deckId: widget.deckId,
      initialCard: widget.card,
    );
    _question = TextEditingController(text: widget.card?.question ?? '');
    _answer = TextEditingController(text: widget.card?.answer ?? '');
    _question.addListener(_contentChanged);
    _answer.addListener(_contentChanged);
  }

  void _contentChanged() => setState(() {});

  @override
  void dispose() {
    _question.dispose();
    _answer.dispose();
    _questionFocus.dispose();
    _answerFocus.dispose();
    _model.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final saved = await _model.save(
      question: _question.text,
      answer: _answer.text,
    );
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context, true);
    } else if (_model.questionError != null) {
      revealEditorField(_questionFocus, _questionAnchor);
    } else if (_model.answerError != null) {
      revealEditorField(_answerFocus, _answerAnchor);
    } else if (_model.error != null) {
      FocusScope.of(context).unfocus();
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _model,
    builder: (context, _) {
      final theme = Theme.of(context);
      return EditorLayout(
        title: widget.card == null ? 'Add flashcard' : 'Edit flashcard',
        isSaving: _model.isSaving,
        isSaved: _model.isSaved,
        hasUnsavedChanges:
            _question.text != (widget.card?.question ?? '') ||
            _answer.text != (widget.card?.answer ?? ''),
        error: _model.error,
        invalidFieldKey: _model.questionError != null
            ? _questionAnchor
            : _model.answerError != null
            ? _answerAnchor
            : null,
        masteryNotice: widget.card == null
            ? null
            : 'Content edits reset mastery to Review.',
        buttonLabel: widget.card == null ? 'Add flashcard' : 'Save changes',
        onSave: _save,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.card == null
                  ? 'One question. One step forward.'
                  : 'Fine-tune your flashcard',
              style: theme.textTheme.headlineMedium,
            ),
            const SizedBox(height: 10),
            Text(
              'Keep it clear, focused, and easy to remember.',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 28),
            KeyedSubtree(
              key: _questionAnchor,
              child: TextField(
                key: const ValueKey('card-question'),
                controller: _question,
                focusNode: _questionFocus,
                enabled: !_model.isSaving && !_model.isSaved,
                minLines: 3,
                maxLines: 8,
                textCapitalization: TextCapitalization.sentences,
                keyboardType: TextInputType.multiline,
                onChanged: (_) => _model.clearQuestionError(),
                decoration: InputDecoration(
                  labelText: 'Question',
                  hintText: 'What would you like to remember?',
                  errorText: _model.questionError,
                ),
              ),
            ),
            const SizedBox(height: 24),
            KeyedSubtree(
              key: _answerAnchor,
              child: TextField(
                key: const ValueKey('card-answer'),
                controller: _answer,
                focusNode: _answerFocus,
                enabled: !_model.isSaving && !_model.isSaved,
                minLines: 4,
                maxLines: 10,
                textCapitalization: TextCapitalization.sentences,
                keyboardType: TextInputType.multiline,
                onChanged: (_) => _model.clearAnswerError(),
                decoration: InputDecoration(
                  labelText: 'Answer',
                  hintText: 'Write the explanation in your own words.',
                  errorText: _model.answerError,
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
