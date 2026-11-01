import 'package:flutter/material.dart';

import '../theme.dart';

enum VillageButtonVariant { primary, ghost, soft, danger }

/// Pill-shaped button from the component catalog. Primary and ghost are the
/// 56px main actions; soft and danger are 44px secondary actions.
/// A null [onPressed] renders the disabled style.
class VillageButton extends StatelessWidget {
  const VillageButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = VillageButtonVariant.primary,
  });

  final String label;
  final VoidCallback? onPressed;
  final VillageButtonVariant variant;

  bool get _isLarge =>
      variant == VillageButtonVariant.primary ||
      variant == VillageButtonVariant.ghost;

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    final enabled = onPressed != null;
    final radius = BorderRadius.circular(VillageRadius.pill);

    final (Color? fill, Gradient? gradient, Color? border, Color text) =
        switch (variant) {
      _ when !enabled => (c.disabled, null, null, Colors.white),
      VillageButtonVariant.primary => (
          null,
          LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [c.cta, c.ctaEnd],
          ),
          null,
          Colors.white,
        ),
      VillageButtonVariant.ghost => (
          Colors.white.withValues(alpha: 0.86),
          null,
          c.garis,
          c.ink,
        ),
      VillageButtonVariant.soft => (c.pinkSoft, null, null, c.pinkText),
      VillageButtonVariant.danger => (
          c.merahSoft,
          null,
          c.merahBorder,
          c.merah,
        ),
    };

    return Semantics(
      button: true,
      enabled: enabled,
      child: SizedBox(
        height: _isLarge ? 56 : 44,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: fill,
            gradient: gradient,
            borderRadius: radius,
            border: border == null ? null : Border.all(color: border, width: 2),
            boxShadow: enabled && variant == VillageButtonVariant.primary
                ? [
                    BoxShadow(
                      color: c.ctaEnd.withValues(alpha: 0.7),
                      offset: const Offset(0, 14),
                      blurRadius: 26,
                      spreadRadius: -12,
                    ),
                  ]
                : null,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onPressed,
              borderRadius: radius,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Center(
                  widthFactor: 1,
                  child: Text(
                    label,
                    style: villageText(
                      fontSize: _isLarge ? 16 : 14,
                      fontWeight: FontWeight.w900,
                      color: text,
                    ),
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
