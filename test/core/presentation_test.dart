import 'dart:math' as math;

import 'package:flashquest_drill/app_theme.dart';
import 'package:flashquest_drill/core/mastery_percentage.dart';
import 'package:flashquest_drill/core/text_preview.dart';
import 'package:flashquest_drill/models/mastery_stats.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('empty decks show zero mastery', () {
    expect(formatMasteryPercentage(MasteryStats(total: 0, known: 0)), '0%');
  });

  test('only fully Known decks show 100 percent', () {
    for (final total in [1, 200, 10000]) {
      expect(
        formatMasteryPercentage(MasteryStats(total: total, known: total)),
        '100%',
      );
      expect(
        formatMasteryPercentage(MasteryStats(total: total, known: total - 1)),
        isNot('100%'),
      );
    }
    expect(
      formatMasteryPercentage(MasteryStats(total: 200, known: 199)),
      '99%',
    );
  });

  test(
    'whole percentages round down without changing underlying precision',
    () {
      final stats = MasteryStats(total: 3, known: 2);
      expect(formatMasteryPercentage(stats), '66%');
      expect(stats.percentage, closeTo(66.6666666667, 0.000001));
      expect(stats.known, 2);
      expect(stats.review, 1);
      expect(formatMasteryPercentage(MasteryStats(total: 201, known: 1)), '0%');
    },
  );

  test(
    'question previews normalize whitespace and preserve short questions',
    () {
      expect(questionPreview('  What\n is\t ATP?  '), 'What is ATP?');
      expect(questionPreview('Why?'), 'Why?');
    },
  );

  test('question previews truncate complete graphemes, including emoji', () {
    const emoji = '👩🏽‍🔬';
    final question = List.filled(121, emoji).join();
    final preview = questionPreview(question);
    expect(preview, '${List.filled(120, emoji).join()}…');
    expect(preview.characters.length, 121);
  });

  test(
    'enabled, focused, and error field borders contrast with both surfaces',
    () {
      final theme = buildAppTheme();
      final decoration = theme.inputDecorationTheme;
      for (final border in [
        decoration.enabledBorder,
        decoration.focusedBorder,
        decoration.errorBorder,
      ]) {
        for (final background in [
          theme.colorScheme.surface,
          theme.scaffoldBackgroundColor,
        ]) {
          final foregroundLuminance = border!.borderSide.color
              .computeLuminance();
          final backgroundLuminance = background.computeLuminance();
          final ratio =
              (math.max(foregroundLuminance, backgroundLuminance) + 0.05) /
              (math.min(foregroundLuminance, backgroundLuminance) + 0.05);
          expect(ratio, greaterThanOrEqualTo(3));
        }
      }
    },
  );
}
