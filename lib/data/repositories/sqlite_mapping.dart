import '../../models/deck.dart';
import '../../models/flashcard.dart';
import '../../models/mastery_stats.dart';

String requireText(String value, String name) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(value, name, 'Must not be empty.');
  }
  return trimmed;
}

Deck deckFromRow(Map<String, Object?> row) => Deck(
  id: row['id'] as int,
  title: row['title'] as String,
  createdAt: _date(row['created_at']),
  updatedAt: _date(row['updated_at']),
);

Flashcard flashcardFromRow(Map<String, Object?> row) => Flashcard(
  id: row['id'] as int,
  deckId: row['deck_id'] as int,
  question: row['question'] as String,
  answer: row['answer'] as String,
  status: MasteryStatus.values.byName(row['status'] as String),
  createdAt: _date(row['created_at']),
  updatedAt: _date(row['updated_at']),
);

MasteryStats masteryFromRow(Map<String, Object?> row) =>
    MasteryStats(total: row['total'] as int, known: row['known'] as int);

DateTime _date(Object? milliseconds) =>
    DateTime.fromMillisecondsSinceEpoch(milliseconds as int, isUtc: true);
