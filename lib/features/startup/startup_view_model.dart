import '../../core/view_model.dart';

typedef AppInitializer = Future<void> Function();

enum StartupState { loading, error, ready }

/// Owns one initialization attempt at a time. Retry uses the same injected
/// initializer, and a completed startup is never run again on resume/rebuild.
final class StartupViewModel extends ViewModel {
  StartupViewModel(this._initialize);

  final AppInitializer _initialize;
  Future<void>? _pending;
  StartupState state = StartupState.loading;
  String? error;

  Future<void> initialize() {
    if (isDisposed || state == StartupState.ready) return Future.value();
    // Assign the shared future before publishing, including for listeners that
    // request initialization reentrantly in response to the loading state.
    return _pending ??= Future<void>.microtask(_run)
        .whenComplete(() => _pending = null);
  }

  Future<void> _run() async {
    if (isDisposed) return;
    state = StartupState.loading;
    error = null;
    publish();
    try {
      await _initialize();
      if (isDisposed) return;
      state = StartupState.ready;
    } catch (_) {
      if (isDisposed) return;
      state = StartupState.error;
      error = 'We couldn’t open your saved flashcards. Please try again.';
    }
    publish();
  }
}
