import 'package:flutter/material.dart';

import '../format.dart';
import '../theme.dart';

enum StatTone { save, spend }

/// Small white tile with an uppercase label and a rupiah amount.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.amount,
    this.tone = StatTone.save,
  });

  final String label;

  /// Whole rupiah.
  final int amount;
  final StatTone tone;

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    final (border, valueColor) = switch (tone) {
      StatTone.save => (c.mintBorder, c.mintText),
      StatTone.spend => (c.merahBorder, c.merah),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: border, width: 2),
        borderRadius: BorderRadius.circular(VillageRadius.tile),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label.toUpperCase(),
              style: villageText(fontSize: 10, color: c.redup),
            ),
            const SizedBox(height: 2),
            Text(
              formatRupiah(amount),
              style: villageText(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: valueColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
