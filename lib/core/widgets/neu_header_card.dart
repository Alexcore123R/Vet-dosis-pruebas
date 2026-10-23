import 'package:flutter/material.dart';
import 'workspace_panel.dart';

class NeuHeaderCard extends StatelessWidget {
  const NeuHeaderCard({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
    required this.child,
    this.onTap,
    this.trailing,
  });
  final String title;
  final IconData icon;
  final Color color;
  final Widget child;
  final Widget? trailing;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return WorkspacePanel(
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              color: color.withValues(alpha: dark ? .25 : .20),
              child: Row(
                children: [
                  Icon(icon),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  ?trailing,
                ],
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}
