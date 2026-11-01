import 'package:flutter/material.dart';

import '../theme.dart';

/// Selectable 36px pill chip, e.g. quick amount choices.
class VillageChip extends StatelessWidget {
  const VillageChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    final radius = BorderRadius.circular(VillageRadius.pill);
    return Semantics(
      button: onTap != null,
      selected: selected,
      child: Material(
        color: selected ? c.pinkSoft : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: selected ? c.pink : c.garis, width: 2),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: SizedBox(
            height: 36,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                widthFactor: 1,
                child: Text(
                  label,
                  style: villageText(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: selected ? c.pinkText : c.ink,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
