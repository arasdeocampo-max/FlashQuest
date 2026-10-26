import '../models/mastery_stats.dart';

/// Whole percentages round down. Only a nonempty, fully Known deck shows 100%.
/// This is presentation only; the saved-status calculation remains unchanged.
String formatMasteryPercentage(MasteryStats stats) {
  if (stats.total > 0 && stats.known == stats.total) return '100%';
  return '${stats.percentage.floor().clamp(0, 99)}%';
}
