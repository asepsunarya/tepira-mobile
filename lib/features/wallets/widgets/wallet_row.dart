import 'package:flutter/material.dart';

import '../../../core/format.dart';
import '../../../core/theme.dart';
import '../model/wallet.dart';
import '../model/wallet_type_label.dart';
import 'wallet_logo.dart';

/// One wallet in the Dompet list (artboard Dompet): logo, name, type and
/// this month's spending, and the balance the server displays. Debt is
/// shown negative in red; a reserved wallet carries a "Dicadangkan" tag.
class WalletRow extends StatelessWidget {
  const WalletRow({super.key, required this.wallet, this.onTap});

  final Wallet wallet;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    final debt = wallet.kind == WalletKind.debt;
    final reserved = wallet.kind == WalletKind.reserved;
    final balance = formatRupiah(wallet.displayBalance);
    final spent = formatRupiah(wallet.spentThisMonth);
    final type = walletTypeLabel(wallet.type);
    final subtitle = [
      if (debt) 'Utang · $type' else type,
      if (reserved) 'Dicadangkan',
      'jajan bulan ini $spent',
    ].join(' · ');
    final radius = BorderRadius.circular(VillageRadius.tile + 4);
    return Semantics(
      container: true,
      button: onTap != null,
      label: '${wallet.name}, $subtitle, saldo $balance',
      child: ExcludeSemantics(
        child: Material(
          color: c.putih,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(
              color: debt ? c.merahBorder : c.tileBorder,
              width: 2,
            ),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    WalletLogo(
                      name: wallet.name,
                      type: wallet.type,
                      isDebt: debt,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            wallet.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: villageText(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: c.ink,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: villageText(fontSize: 11, color: c.redup),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      balance,
                      key: const Key('wallet-balance'),
                      style: villageText(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: debt ? c.merah : c.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
