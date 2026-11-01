import 'package:flutter/material.dart';

import '../model/display_percent.dart';

/// Progress bar for a savings goal. Amounts are whole rupiah.
class GoalProgress extends StatelessWidget {
  const GoalProgress({super.key, required this.saved, required this.target});

  final int saved;
  final int target;

  double get ratio => target <= 0 ? 0.0 : (saved / target).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final percent = displayPercent(saved: saved, target: target);
    return Semantics(
      label: 'Progres $percent%',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(value: ratio, minHeight: 8),
          const SizedBox(height: 4),
          // The label above already announces the percentage; reading the
          // caption too would merge into one duplicated label.
          ExcludeSemantics(child: Text('$percent% dari target')),
        ],
      ),
    );
  }
}
