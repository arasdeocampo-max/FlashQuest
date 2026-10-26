/// The last saved classification, independent of any temporary study session.
enum MasteryStatus { review, known }

final class Flashcard {
  const Flashcard({
    required this.id,
    required this.deckId,
    required this.question,
    required this.answer,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final int deckId;
  final String question;
  final String answer;
  final MasteryStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  @override
  bool operator ==(Object other) =>
      other is Flashcard &&
      id == other.id &&
      deckId == other.deckId &&
      question == other.question &&
      answer == other.answer &&
      status == other.status &&
      createdAt == other.createdAt &&
      updatedAt == other.updatedAt;

  @override
  int get hashCode =>
      Object.hash(id, deckId, question, answer, status, createdAt, updatedAt);
}
