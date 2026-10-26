import '../../core/view_model.dart';
import '../../models/flashcard.dart';
import '../../repositories/flashcard_repository.dart';

final class FlashcardEditorViewModel extends ViewModel {
  FlashcardEditorViewModel(
    this._repository, {
    required this.deckId,
    this.initialCard,
  });

  final FlashcardRepository _repository;
  final int deckId;
  final Flashcard? initialCard;
  bool isSaving = false;
  bool isSaved = false;
  String? questionError;
  String? answerError;
  String? error;

  Future<bool> save({required String question, required String answer}) async {
    if (isSaving || isSaved || isDisposed) return false;
    questionError = question.trim().isEmpty
        ? 'Enter a question for this flashcard.'
        : null;
    answerError = answer.trim().isEmpty
        ? 'Enter an answer for this flashcard.'
        : null;
    error = null;
    if (questionError != null || answerError != null) {
      publish();
      return false;
    }
    isSaving = true;
    publish();
    try {
      final original = initialCard;
      if (original == null) {
        await _repository.create(
          deckId: deckId,
          question: question,
          answer: answer,
        );
      } else {
        await _repository.updateContent(
          id: original.id,
          question: question,
          answer: answer,
        );
      }
      isSaved = true;
      return true;
    } catch (failure) {
      error = messageFor(
        failure,
        'We couldn’t save this flashcard. Please try again.',
      );
      return false;
    } finally {
      isSaving = false;
      publish();
    }
  }

  void clearQuestionError() {
    if (questionError == null) return;
    questionError = null;
    publish();
  }

  void clearAnswerError() {
    if (answerError == null) return;
    answerError = null;
    publish();
  }
}
