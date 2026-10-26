/// A saved collection of flashcards. Contains no study-session state.
final class Deck {
  const Deck({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;

  @override
  bool operator ==(Object other) =>
      other is Deck &&
      id == other.id &&
      title == other.title &&
      createdAt == other.createdAt &&
      updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(id, title, createdAt, updatedAt);
}
