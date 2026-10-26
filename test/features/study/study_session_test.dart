import 'package:flashquest_drill/features/study/study_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  void grade(StudySession session, StudyGrade grade) =>
      session.recordGrade(expectedTurn: session.turn, grade: grade);

  test('an empty session is not a completed study session', () {
    final session = StudySession([]);
    expect(session.isEmpty, isTrue);
    expect(session.isComplete, isFalse);
    expect(session.currentCardId, isNull);
    expect(session.round, 0);
    expect(session.remainingCards, 0);
    expect(() => grade(session, StudyGrade.known), throwsStateError);
  });

  test('a single Known card completes exactly once', () {
    final session = StudySession([10]);
    expect(session.round, 1);
    expect(session.currentCardId, 10);
    grade(session, StudyGrade.known);
    expect(session.isComplete, isTrue);
    expect(session.knownCount, 1);
    expect(session.reviewCount, 0);
    expect(session.remainingCards, 0);
    expect(session.remainingInRound, 0);
    expect(session.currentCardId, isNull);
    expect(() => grade(session, StudyGrade.known), throwsStateError);
  });

  test(
    'one Review card can repeat for multiple rounds before becoming Known',
    () {
      final session = StudySession([7]);
      for (var round = 1; round <= 3; round++) {
        expect(session.round, round);
        expect(session.currentCardId, 7);
        expect(session.remainingInRound, 1);
        grade(session, StudyGrade.review);
        expect(session.isComplete, isFalse);
        expect(session.reviewCount, 1);
        expect(session.remainingCards, 1);
        expect(session.currentCardId, isNull);
        expect(session.retryRemaining(expectedRound: round), isTrue);
      }
      grade(session, StudyGrade.known);
      expect(session.round, 4);
      expect(session.isComplete, isTrue);
      expect(session.reviewCount, 0);
    },
  );

  test(
    'all-Known cards retain their original order and finish in round one',
    () {
      final session = StudySession([4, 2, 9]);
      for (final id in [4, 2, 9]) {
        expect(session.currentCardId, id);
        expect(session.round, 1);
        grade(session, StudyGrade.known);
      }
      expect(session.isComplete, isTrue);
      expect(session.totalCards, 3);
      expect(session.knownCount, 3);
    },
  );

  test('only Review cards repeat, once each per round, without shuffling', () {
    final session = StudySession([1, 2, 3, 4]);
    grade(session, StudyGrade.review);
    grade(session, StudyGrade.known);
    grade(session, StudyGrade.review);
    grade(session, StudyGrade.known);
    expect(session.isRoundComplete, isTrue);
    expect(session.retryRemaining(expectedRound: 1), isTrue);
    expect(session.round, 2);
    expect(session.currentCardId, 1);
    expect(session.reviewCount, 2);
    expect(session.remainingInRound, 2);
    expect(session.remainingCards, 2);
    grade(session, StudyGrade.known);
    expect(session.currentCardId, 3);
    expect(session.reviewCount, 1);
    grade(session, StudyGrade.review);
    expect(session.retryRemaining(expectedRound: 2), isTrue);
    expect(session.round, 3);
    expect(session.currentCardId, 3);
    expect(session.remainingInRound, 1);
    grade(session, StudyGrade.known);
    expect(session.isComplete, isTrue);
  });

  test('Review does not replay a card before the rest of its round', () {
    final session = StudySession([1, 2, 3]);
    grade(session, StudyGrade.review);
    expect(session.currentCardId, 2);
    expect(session.remainingInRound, 2);
    expect(session.reviewCount, 1);
    grade(session, StudyGrade.review);
    expect(session.currentCardId, 3);
    expect(session.round, 1);
    grade(session, StudyGrade.review);
    expect(session.currentCardId, isNull);
    expect(session.retryRemaining(expectedRound: 1), isTrue);
    expect(session.currentCardId, 1);
    expect(session.round, 2);
    expect(session.reviewCount, 3);
  });

  test('unseen cards are still outstanding when the Review Pile is empty', () {
    final session = StudySession([1, 2]);
    grade(session, StudyGrade.known);
    expect(session.reviewCount, 0);
    expect(session.isComplete, isFalse);
    expect(session.remainingCards, 1);
    expect(session.currentCardId, 2);
  });

  test('stale turn tokens cannot grade the next card', () {
    final session = StudySession([1, 2]);
    final oldTurn = session.turn;
    grade(session, StudyGrade.known);
    expect(
      () => session.recordGrade(expectedTurn: oldTurn, grade: StudyGrade.known),
      throwsStateError,
    );
    expect(session.currentCardId, 2);
    expect(session.knownCount, 1);
  });

  test('stale turn tokens cannot double-grade the same ID in a new round', () {
    final session = StudySession([1]);
    final oldTurn = session.turn;
    grade(session, StudyGrade.review);
    expect(session.retryRemaining(expectedRound: 1), isTrue);
    expect(
      () => session.recordGrade(expectedTurn: oldTurn, grade: StudyGrade.known),
      throwsStateError,
    );
    expect(session.round, 2);
    expect(session.knownCount, 0);
    expect(session.reviewCount, 1);
  });

  test('future turn tokens cannot skip cards', () {
    final session = StudySession([1, 2]);
    expect(
      () => session.recordGrade(expectedTurn: 99, grade: StudyGrade.known),
      throwsStateError,
    );
    expect(session.turn, 0);
    expect(session.currentCardId, 1);
  });

  test('duplicate IDs are rejected rather than repeated in a round', () {
    expect(() => StudySession([1, 1]), throwsArgumentError);
  });

  test('a session owns a copy of its initial order', () {
    final ids = [1, 2];
    final session = StudySession(ids);
    ids.clear();
    expect(session.totalCards, 2);
    grade(session, StudyGrade.known);
    expect(session.currentCardId, 2);
  });

  test('mixed skips and grades retry only remaining cards in deck order', () {
    final session = StudySession([4, 2, 9, 7]);
    session.skip(expectedTurn: session.turn);
    grade(session, StudyGrade.known);
    grade(session, StudyGrade.review);
    session.skip(expectedTurn: session.turn);
    expect(session.isRoundComplete, isTrue);
    expect(session.isComplete, isFalse);
    expect(session.currentCardId, isNull);
    expect(session.remainingInRound, 0);
    expect(session.knownCount, 1);
    expect(session.reviewCount, 1);
    expect(session.skippedCount, 2);
    expect(session.remainingCards, 3);
    expect(session.retryRemaining(expectedRound: 99), isFalse);
    expect(session.retryRemaining(expectedRound: 1), isTrue);
    expect(session.retryRemaining(expectedRound: 1), isFalse);
    expect(session.currentCardId, 4);
    grade(session, StudyGrade.review); // Previously skipped.
    expect(session.currentCardId, 9);
    session.skip(expectedTurn: session.turn); // Previously Review.
    expect(session.currentCardId, 7);
    grade(session, StudyGrade.known);
    expect(session.knownCount, 2);
    expect(session.reviewCount, 1);
    expect(session.skippedCount, 1);
    expect(session.retryRemaining(expectedRound: 1), isFalse);
    expect(session.retryRemaining(expectedRound: 2), isTrue);
    expect(session.currentCardId, 4);
    grade(session, StudyGrade.known);
    expect(session.currentCardId, 9);
    grade(session, StudyGrade.known);
    expect(session.isComplete, isTrue);
    expect(session.isRoundComplete, isFalse);
    expect(session.reviewCount, 0);
    expect(session.skippedCount, 0);
    expect(session.retryRemaining(expectedRound: 3), isFalse);
  });

  test('all-skipped passes wait for retry and reject stale actions', () {
    final session = StudySession([1, 2]);
    expect(session.retryRemaining(expectedRound: 1), isFalse);
    session.skip(expectedTurn: 0);
    expect(() => session.skip(expectedTurn: 0), throwsStateError);
    session.skip(expectedTurn: 1);
    expect(session.round, 1);
    expect(session.isRoundComplete, isTrue);
    expect(session.knownCount, 0);
    expect(session.skippedCount, 2);
    expect(session.remainingCards, 2);
    expect(() => session.skip(expectedTurn: 2), throwsStateError);
    expect(session.retryRemaining(expectedRound: 1), isTrue);
    session.skip(expectedTurn: 2);
    session.skip(expectedTurn: 3);
    expect(session.round, 2);
    expect(session.currentCardId, isNull);
    expect(session.skippedCount, 2);
  });
}
