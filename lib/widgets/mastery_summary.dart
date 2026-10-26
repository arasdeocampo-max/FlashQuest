import 'package:flutter/material.dart';

import '../core/mastery_percentage.dart';
import '../models/mastery_stats.dart';

class MasterySummary extends StatelessWidget {
  const MasterySummary({super.key, required this.stats});
  final MasteryStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            children: [
              Text(
                'Your mastery',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colors.onPrimaryContainer,
                ),
              ),
              Text(
                formatMasteryPercentage(stats),
                style: theme.textTheme.headlineLarge?.copyWith(
                  color: colors.onPrimaryContainer,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: stats.percentage / 100,
            minHeight: 8,
            borderRadius: BorderRadius.circular(8),
            backgroundColor: colors.surface,
            semanticsLabel:
                'Deck mastery, ${stats.known} of ${stats.total} cards Known',
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 20,
            runSpacing: 10,
            children: [
              _Count(count: stats.known, label: 'Known'),
              _Count(count: stats.review, label: 'Review'),
              _Count(count: stats.total, label: 'Total'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.count, required this.label});
  final int count;
  final String label;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      text: '$count ',
      style: TextStyle(
        color: Theme.of(context).colorScheme.onPrimaryContainer,
        fontWeight: FontWeight.w700,
        fontSize: 15,
      ),
      children: [
        TextSpan(
          text: label,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
      ],
    ),
  );
}
