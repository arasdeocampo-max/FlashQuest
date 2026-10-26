import 'package:flutter/material.dart';

Future<bool> confirmMasteryReset(
  BuildContext context, {
  required String title,
}) async {
  var responded = false;
  void respond(BuildContext dialogContext, bool confirmed) {
    if (responded || !dialogContext.mounted) return;
    responded = true;
    Navigator.pop(dialogContext, confirmed);
  }

  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          key: const ValueKey('mastery-reset-dialog'),
          icon: const Icon(Icons.restart_alt_rounded),
          title: const Text('Reset mastery and study again?'),
          content: SingleChildScrollView(
            child: Text(
              'All cards in “$title” will return to Review (0% mastery). '
              'Your deck, questions, and answers will be kept. '
              'This mastery reset can’t be undone.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => respond(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('confirm-reset-mastery'),
              onPressed: () => respond(context, true),
              child: const Text('Reset and Study'),
            ),
          ],
        ),
      ) ??
      false;
}
