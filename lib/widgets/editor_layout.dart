import 'dart:async';

import 'package:flutter/material.dart';

import 'app_states.dart';

/// Reveal validation after the error decoration has been laid out. TextField
/// also keeps the focused caret visible as the platform keyboard opens.
void revealEditorField(FocusNode focusNode, GlobalKey fieldKey) {
  focusNode.requestFocus();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final context = fieldKey.currentContext;
    if (context == null) return;
    unawaited(
      Scrollable.ensureVisible(
        context,
        alignment: 0,
        duration:
            MediaQuery.disableAnimationsOf(context) ||
                MediaQuery.accessibleNavigationOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      ),
    );
  });
}

class EditorLayout extends StatefulWidget {
  const EditorLayout({
    super.key,
    required this.title,
    required this.isSaving,
    required this.isSaved,
    required this.hasUnsavedChanges,
    required this.buttonLabel,
    required this.onSave,
    required this.child,
    this.error,
    this.masteryNotice,
    this.invalidFieldKey,
  });
  final String title;
  final bool isSaving;
  final bool isSaved;
  final bool hasUnsavedChanges;
  final String buttonLabel;
  final VoidCallback onSave;
  final Widget child;
  final String? error;
  final String? masteryNotice;
  final GlobalKey? invalidFieldKey;

  @override
  State<EditorLayout> createState() => _EditorLayoutState();
}

class _EditorLayoutState extends State<EditorLayout> {
  final ScrollController _feedbackScroll = ScrollController();
  bool _confirmingExit = false;
  bool _discardApproved = false;
  double? _previousHeight;

  void _keepValidationVisible(double height) {
    if (_previousHeight == height) return;
    _previousHeight = height;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = widget.invalidFieldKey?.currentContext;
      if (target != null) {
        unawaited(Scrollable.ensureVisible(target, alignment: 0));
      }
    });
  }

  @override
  void didUpdateWidget(covariant EditorLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.error != null && widget.error != oldWidget.error) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _feedbackScroll.hasClients) _feedbackScroll.jumpTo(0);
      });
    }
  }

  Future<void> _confirmDiscard() async {
    if (_confirmingExit || widget.isSaving || widget.isSaved) return;
    _confirmingExit = true;
    try {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard changes?'),
          content: const SingleChildScrollView(
            child: Text('Your unsaved changes will be lost.'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Stay'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted || widget.isSaving) return;
      setState(() => _discardApproved = true);
      Navigator.of(context).pop(false);
    } finally {
      _confirmingExit = false;
    }
  }

  @override
  void dispose() {
    _feedbackScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope<bool>(
    canPop:
        !widget.isSaving &&
        (widget.isSaved || !widget.hasUnsavedChanges || _discardApproved),
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop && !widget.isSaving && widget.hasUnsavedChanges) {
        unawaited(_confirmDiscard());
      }
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        leading: IconButton(
          tooltip: 'Back',
          onPressed: widget.isSaving
              ? null
              : () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      // Keep the footer inside the resized body, above the keyboard. Its
      // bounded feedback area scrolls on short screens and with large text.
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: LayoutBuilder(
              builder: (context, constraints) {
                _keepValidationVisible(constraints.maxHeight);
                return Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        key: const ValueKey('editor-scroll'),
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                        child: widget.child,
                      ),
                    ),
                    if (widget.error != null || widget.masteryNotice != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: constraints.maxHeight * 0.35,
                          ),
                          child: Scrollbar(
                            controller: _feedbackScroll,
                            thumbVisibility: true,
                            child: SingleChildScrollView(
                              key: const ValueKey('editor-feedback'),
                              controller: _feedbackScroll,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (widget.error != null)
                                    InlineError(message: widget.error!),
                                  if (widget.error != null &&
                                      widget.masteryNotice != null)
                                    const SizedBox(height: 8),
                                  if (widget.masteryNotice != null)
                                    Container(
                                      key: const ValueKey(
                                        'mastery-reset-notice',
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primaryContainer,
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Text(
                                        widget.masteryNotice!,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onPrimaryContainer,
                                            ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        24,
                        constraints.maxHeight < 180 ? 4 : 12,
                        24,
                        constraints.maxHeight < 180 ? 4 : 16,
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          key: const ValueKey('save-button'),
                          onPressed: widget.isSaving || widget.isSaved
                              ? null
                              : widget.onSave,
                          child: widget.isSaving
                              ? const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        semanticsLabel: 'Saving changes',
                                      ),
                                    ),
                                    SizedBox(width: 12),
                                    Flexible(child: Text('Saving…')),
                                  ],
                                )
                              : Text(widget.buttonLabel),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    ),
  );
}
