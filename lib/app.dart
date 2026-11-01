import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/theme.dart';
import 'features/goals/goals_screen.dart';

final _router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (context, state) => const GoalsScreen()),
  ],
);

class TepiraApp extends StatelessWidget {
  const TepiraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'tepira',
      theme: tepiraTheme,
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
    );
  }
}
