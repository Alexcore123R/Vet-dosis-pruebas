import 'package:flutter/material.dart';
import 'workspace_panel.dart';

/// Shallow raised record with a category accent, matching the directory design.
class NeuRecordCard extends StatelessWidget {
  const NeuRecordCard({super.key, required this.color, required this.child});
  final Color color;
  final Widget child;
  @override
  Widget build(BuildContext context) => WorkspacePanel(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 5,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: child),
          ],
        ),
      ),
    ),
  );
}
