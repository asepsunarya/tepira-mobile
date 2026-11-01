import 'package:flutter/material.dart';

import '../theme.dart';

/// Status tone of a [Pill]: on track, close to the limit, overdue, or accent.
enum PillTone { success, warning, danger, accent }

/// Small non-interactive status badge, e.g. "Aman", "Lewat", "Lv 5".
class Pill extends StatelessWidget {
  const Pill({super.key, required this.label, this.tone = PillTone.accent});

  final String label;
  final PillTone tone;

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    final (background, foreground) = switch (tone) {
      PillTone.success => (c.mintSoft, c.mintText),
      PillTone.warning => (c.kuningSoft, c.kuningText),
      PillTone.danger => (c.merahSoft, c.merah),
      PillTone.accent => (c.pinkSoft, c.pinkText),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(VillageRadius.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          label,
          style: villageText(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: foreground,
          ),
        ),
      ),
    );
  }
}
