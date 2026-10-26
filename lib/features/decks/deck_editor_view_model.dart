import '../../core/view_model.dart';
import '../../models/deck.dart';
import '../../repositories/deck_repository.dart';

final class DeckEditorViewModel extends ViewModel {
  DeckEditorViewModel(this._repository, {this.initialDeck});

  final DeckRepository _repository;
  final Deck? initialDeck;
  bool isSaving = false;
  bool isSaved = false;
  String? titleError;
  String? error;

  Future<bool> save(String title) async {
    if (isSaving || isSaved || isDisposed) return false;
    titleError = title.trim().isEmpty ? 'Enter a title for your deck.' : null;
    error = null;
    if (titleError != null) {
      publish();
      return false;
    }
    isSaving = true;
    publish();
    try {
      final original = initialDeck;
      if (original == null) {
        await _repository.create(title: title);
      } else {
        await _repository.update(id: original.id, title: title);
      }
      isSaved = true;
      return true;
    } catch (failure) {
      error = messageFor(
        failure,
        'We couldn’t save your deck. Please try again.',
      );
      return false;
    } finally {
      isSaving = false;
      publish();
    }
  }

  void clearValidation() {
    if (titleError == null) return;
    titleError = null;
    publish();
  }
}
