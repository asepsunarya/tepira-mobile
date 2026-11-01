import 'package:flutter/material.dart';

import '../../core/theme.dart';

import 'widgets/goal_progress.dart';

/// Placeholder home screen. Replace with the real goal list once the
/// goals repository exists (see tasks/ after running /spec and /plan).
class GoalsScreen extends StatelessWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('tepira')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Teu pira, tapi konsisten.',
              style: villageText(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            const GoalProgress(saved: 250000, target: 1000000),
          ],
        ),
      ),
    );
  }
}
