import 'package:flutter/material.dart';

import 'widgets/goal_progress.dart';

/// Placeholder home screen. Replace with the real goal list once the
/// goals repository exists (see tasks/ after running /spec and /plan).
class GoalsScreen extends StatelessWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('tepira')),
      body: const Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Teu pira, tapi konsisten.',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 16),
            GoalProgress(saved: 250000, target: 1000000),
          ],
        ),
      ),
    );
  }
}
