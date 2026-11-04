import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/brands.dart';
import '../../../core/theme.dart';

/// The square tile in front of a wallet: its brand logo when the name names a
/// known brand (`lib/core/brands.dart`), else a short mark for its type on a
/// tinted tile (artboards Dompet and TambahDompet).
class WalletLogo extends StatelessWidget {
  const WalletLogo({
    super.key,
    required this.name,
    required this.type,
    required this.isDebt,
    this.size = 44,
  });

  final String name;
  final String type;
  final bool isDebt;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    final brand = brandForWalletName(name);
    final (Color fill, Color ink) = switch (type) {
      _ when brand != null => (c.putih, c.ink),
      _ when isDebt => (c.merahSoft, c.merah),
      'cash' || 'e-wallet' => (c.mintSoft, c.mintText),
      'bank' => (c.langit, c.ink),
      _ => (c.kuningSoft, c.kuningText),
    };
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(size * 0.14),
        decoration: BoxDecoration(
          color: fill,
          border: Border.all(
            color: isDebt ? c.merahBorder : c.tileBorder,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(VillageRadius.tile),
        ),
        alignment: Alignment.center,
        child: brand != null
            ? SvgPicture.asset(brand.asset, fit: BoxFit.contain)
            : FittedBox(
                child: Text(
                  _initials(type, name),
                  style: villageText(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: ink,
                  ),
                ),
              ),
      ),
    );
  }
}

/// The type's initials, or the name's first letter for other types.
String _initials(String type, String name) {
  final trimmed = name.trim();
  return switch (type) {
    'bank' => 'B',
    'e-wallet' => 'EW',
    'cash' => 'Rp',
    'investment' => 'IV',
    'credit' => 'KK',
    'paylater' => 'PL',
    _ when trimmed.isEmpty => '?',
    _ => trimmed.characters.first.toUpperCase(),
  };
}
