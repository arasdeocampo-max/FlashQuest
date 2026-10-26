import 'package:flutter/widgets.dart';

/// Bound display text by grapheme clusters, preserving emoji and combining marks.
String questionPreview(String question) {
  final text = question.replaceAll(RegExp(r'\s+'), ' ').trim();
  final characters = text.characters;
  return characters.length > 120 ? '${characters.take(120)}…' : text;
}
