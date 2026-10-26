import 'package:flutter/foundation.dart';

import '../repositories/repository_exception.dart';

/// Screens own their view models. Late async completions cannot notify a
/// disposed screen, and callers can stop starting work after disposal.
abstract class ViewModel extends ChangeNotifier {
  bool _disposed = false;
  bool get isDisposed => _disposed;

  void publish() {
    if (!_disposed) notifyListeners();
  }

  String messageFor(Object error, String fallback) {
    if (error is RecordNotFoundException) {
      return 'This ${error.entity.toLowerCase()} no longer exists. Go back and refresh.';
    }
    return fallback;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
