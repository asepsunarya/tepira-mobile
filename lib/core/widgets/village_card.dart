import 'package:flutter/material.dart';

import '../theme.dart';

/// Cream card with a white 2px border and soft pink-brown shadow.
class VillageCard extends StatelessWidget {
  const VillageCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = VillageColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.kartu.withValues(alpha: 0.88),
        border: Border.all(color: colors.putih, width: 2),
        borderRadius: BorderRadius.circular(VillageRadius.card),
        boxShadow: [
          BoxShadow(
            color: colors.shadow,
            offset: const Offset(0, 10),
            blurRadius: 30,
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}
