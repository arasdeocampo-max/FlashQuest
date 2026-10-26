import '../../core/view_model.dart';
import '../../models/deck.dart';
import '../../models/mastery_stats.dart';
import '../../repositories/deck_repository.dart';

final class DeckListViewModel extends ViewModel {
  DeckListViewModel(this._repository);

  final DeckRepository _repository;
  List<Deck> decks = const [];
  Map<int, MasteryStats> mastery = const {};
  bool isLoading = false;
  int? deletingId;
  String? error;
  String? deletionError;
  Future<void>? _loadFuture;

  bool get isBusy => isLoading || deletingId != null;
  int get totalCards =>
      mastery.values.fold(0, (sum, stats) => sum + stats.total);

  Future<void> load() {
    // A mutation performs its own refresh after committing. A pull-to-refresh
    // during that write must not read and then display a pre-delete snapshot.
    if (isDisposed || deletingId != null) return Future.value();
    return _loadFuture ??= _load().whenComplete(() => _loadFuture = null);
  }

  Future<void> _load() async {
    isLoading = true;
    error = null;
    deletionError = null;
    publish();
    try {
      final loadedDecks = await _repository.getAll();
      final loadedMastery = await _repository.getAllMasteryStats();
      if (isDisposed) return;
      decks = List.unmodifiable(loadedDecks);
      mastery = Map.unmodifiable(loadedMastery);
    } catch (failure) {
      error = messageFor(
        failure,
        'We couldn’t load your decks. Please try again.',
      );
    } finally {
      isLoading = false;
      publish();
    }
  }

  Future<bool> deleteDeck(int id) async {
    if (isBusy || isDisposed) return false;
    deletingId = id;
    deletionError = null;
    publish();
    try {
      await _repository.delete(id);
      if (isDisposed) return false;
      await _load();
      return true;
    } catch (failure) {
      deletionError = messageFor(
        failure,
        'We couldn’t delete this deck. Reload to check the saved data.',
      );
      return false;
    } finally {
      deletingId = null;
      publish();
    }
  }
}
