import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tepira_mobile/core/theme.dart';

/// Pumps [child] inside the village theme and waits for bundled fonts.
Future<void> pumpVillage(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildVillageTheme(),
      home: Scaffold(
        body: Center(
          child: RepaintBoundary(
            key: goldenKey,
            child: Padding(padding: const EdgeInsets.all(16), child: child),
          ),
        ),
      ),
    ),
  );
  await tester.runAsync(GoogleFonts.pendingFonts);
  await tester.pumpAndSettle();
}

const goldenKey = Key('golden');
