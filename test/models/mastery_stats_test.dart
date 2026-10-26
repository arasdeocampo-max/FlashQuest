import 'package:flashquest_drill/models/mastery_stats.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MasteryStats', () {
    test('an empty deck has no Review cards and zero percent mastery', () {
      final stats = MasteryStats(total: 0, known: 0);

      expect(stats.review, 0);
      expect(stats.percentage, 0);
    });

    test('calculates Review count and percentage from saved totals', () {
      final stats = MasteryStats(total: 4, known: 3);

      expect(stats.review, 1);
      expect(stats.percentage, 75);
    });

    test('retains precision so display rounding stays in the UI', () {
      expect(
        MasteryStats(total: 3, known: 1).percentage,
        closeTo(33.333333, 0.000001),
      );
    });

    test('all Review cards yield zero mastery', () {
      final stats = MasteryStats(total: 5, known: 0);

      expect(stats.review, 5);
      expect(stats.percentage, 0);
    });

    test('all Known cards yield full mastery', () {
      final stats = MasteryStats(total: 5, known: 5);

      expect(stats.review, 0);
      expect(stats.percentage, 100);
    });

    test('rejects negative totals', () {
      expect(() => MasteryStats(total: -1, known: 0), throwsArgumentError);
    });

    test('rejects negative Known counts', () {
      expect(() => MasteryStats(total: 1, known: -1), throwsArgumentError);
    });

    test('rejects Known counts exceeding the deck total', () {
      expect(() => MasteryStats(total: 1, known: 2), throwsArgumentError);
    });
  });
}
