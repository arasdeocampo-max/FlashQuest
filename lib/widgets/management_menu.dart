import 'package:flutter/material.dart';

enum ManagementAction { edit, delete }

enum _MenuAction { studyAgain, edit, delete }

class ManagementMenu extends StatefulWidget {
  const ManagementMenu({
    super.key,
    required this.subject,
    required this.tooltip,
    required this.onSelected,
    this.enabled = true,
    this.iconColor,
    this.onStudyAgain,
  });
  final String subject;
  final String tooltip;
  final bool enabled;
  final Color? iconColor;
  final ValueChanged<ManagementAction> onSelected;
  final VoidCallback? onStudyAgain;

  @override
  State<ManagementMenu> createState() => _ManagementMenuState();
}

class _ManagementMenuState extends State<ManagementMenu> {
  ModalRoute<dynamic>? _menuRoute;

  Future<void> _select(_MenuAction action) async {
    if (action == _MenuAction.studyAgain) {
      // PopupMenuButton reports a selection as the route starts popping.
      // Wait until its reverse transition and overlay have fully finished.
      await _menuRoute?.completed;
      if (mounted) widget.onStudyAgain?.call();
    } else {
      widget.onSelected(
        action == _MenuAction.edit
            ? ManagementAction.edit
            : ManagementAction.delete,
      );
    }
  }

  @override
  Widget build(BuildContext context) => PopupMenuButton<_MenuAction>(
    tooltip: widget.tooltip,
    enabled: widget.enabled,
    iconColor: widget.iconColor,
    onSelected: _select,
    icon: const Icon(Icons.more_horiz_rounded),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    itemBuilder: (context) => [
      if (widget.onStudyAgain != null)
        PopupMenuItem(
          key: const ValueKey('study-again-menu-item'),
          value: _MenuAction.studyAgain,
          child: Builder(
            builder: (menuContext) {
              _menuRoute = ModalRoute.of(menuContext);
              return const Row(
                children: [
                  Icon(Icons.restart_alt_rounded, size: 20),
                  SizedBox(width: 12),
                  Expanded(child: Text('Study Again')),
                ],
              );
            },
          ),
        ),
      PopupMenuItem(
        value: _MenuAction.edit,
        child: Row(
          children: [
            const Icon(Icons.edit_outlined, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text('Edit ${widget.subject}')),
          ],
        ),
      ),
      PopupMenuItem(
        value: _MenuAction.delete,
        child: Row(
          children: [
            Icon(
              Icons.delete_outline_rounded,
              size: 20,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Delete ${widget.subject}',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
