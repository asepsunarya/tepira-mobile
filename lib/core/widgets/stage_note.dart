import 'package:flutter/material.dart';

import '../theme.dart';

/// Yellow note for building-stage hints and deadline catch-up advice.
class StageNote extends StatelessWidget {
  const StageNote({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.catatan,
        borderRadius: BorderRadius.circular(VillageRadius.note),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Text(
          text,
          style: villageText(fontSize: 12, color: c.ink, height: 1.45),
        ),
      ),
    );
  }
}
