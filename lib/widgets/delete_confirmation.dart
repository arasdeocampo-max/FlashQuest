import 'package:flutter/material.dart';

import '../core/text_preview.dart';

Future<bool> confirmDeletion(
  BuildContext context, {
  required String title,
  required bool isDeck,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: Icon(
        Icons.delete_outline_rounded,
        color: Theme.of(context).colorScheme.error,
      ),
      title: Text(isDeck ? 'Delete deck?' : 'Delete flashcard?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!isDeck) ...[
              Text(
                questionPreview(title),
                key: const ValueKey('delete-question-preview'),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
                semanticsLabel: 'Flashcard question: ${questionPreview(title)}',
              ),
              const SizedBox(height: 16),
            ],
            Text(
              isDeck
                  ? '“$title” and all its flashcards will be permanently deleted from this device. This can’t be undone.'
                  : 'This flashcard will be permanently deleted from this deck. This can’t be undone.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('confirm-delete'),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: Text(isDeck ? 'Delete deck' : 'Delete flashcard'),
        ),
      ],
    ),
  );
  return result ?? false;
}
