/// Failures that a future view model can translate into a user-facing message.
sealed class RepositoryException implements Exception {
  const RepositoryException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// A database failure. The cause is retained for diagnostics, not UI text.
final class StorageException extends RepositoryException {
  const StorageException(super.message, {this.cause});

  final Object? cause;
}

final class RecordNotFoundException extends RepositoryException {
  RecordNotFoundException(this.entity, this.id)
    : super('$entity with ID $id does not exist.');

  final String entity;
  final int id;
}
