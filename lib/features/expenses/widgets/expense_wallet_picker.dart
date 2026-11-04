import 'package:flutter/material.dart';

import '../../../core/format.dart';
import '../../../core/theme.dart';
import '../../wallets/model/wallet.dart';

/// How a wallet reads in the Jajan form: its balance, "terutang" for debt
/// with the hint that spending adds to it, and the "Dicadangkan" tag.
String expenseWalletNote(Wallet wallet) => switch (wallet.kind) {
      WalletKind.normal => formatRupiah(wallet.displayBalance),
      WalletKind.debt =>
        'terutang ${formatRupiah(wallet.displayBalance.abs())} · '
            'Jajan menambah utang',
      WalletKind.reserved =>
        'Dicadangkan · ${formatRupiah(wallet.displayBalance)}',
    };

/// "Bayar dari" field of the Jajan form: the chosen wallet, a prompt to pick
/// one, or the wallet list's loading and error states.
class ExpenseWalletField extends StatelessWidget {
  const ExpenseWalletField({
    super.key,
    required this.name,
    required this.note,
    required this.warn,
    required this.onTap,
    required this.retry,
  });

  final String name;
  final String? note;

  /// Shows [note] in red (a load failure).
  final bool warn;
  final VoidCallback? onTap;

  /// Shows a reload icon instead of the dropdown arrow.
  final bool retry;

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    final radius = BorderRadius.circular(16);
    final note = this.note;
    return Material(
      color: c.putih,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: c.tileBorder, width: 2),
      ),
      child: InkWell(
        key: const Key('wallet-picker'),
        borderRadius: radius,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DOMPET',
                      style: villageText(fontSize: 10, color: c.redup),
                    ),
                    Text(
                      name,
                      key: const Key('wallet-name'),
                      style: villageText(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: c.ink,
                      ),
                    ),
                    if (note != null)
                      Text(
                        note,
                        style: villageText(
                          fontSize: 12,
                          color: warn ? c.merah : c.redup,
                        ),
                      ),
                  ],
                ),
              ),
              Icon(
                retry ? Icons.refresh_rounded : Icons.expand_more_rounded,
                color: c.redup,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet listing the wallets to pay from: ordinary wallets, then
/// debt wallets, then reserved wallets in their own "Dicadangkan" section.
class ExpenseWalletSheet extends StatelessWidget {
  const ExpenseWalletSheet({super.key, required this.wallets});

  final List<Wallet> wallets;

  static const _sections = [
    (WalletKind.normal, 'Dompet'),
    (WalletKind.debt, 'Kartu Kredit & Cicilan'),
    (WalletKind.reserved, 'Dicadangkan'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          for (final (kind, title) in _sections)
            if (wallets.any((w) => w.kind == kind)) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(
                  title.toUpperCase(),
                  key: Key('wallet-section-${kind.name}'),
                  style: villageText(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: c.redup,
                  ),
                ),
              ),
              for (final wallet in wallets.where((w) => w.kind == kind))
                ListTile(
                  key: Key('pick-wallet-${wallet.id}'),
                  title: Text(wallet.name),
                  subtitle: Text(
                    expenseWalletNote(wallet),
                    style: villageText(
                      fontSize: 12,
                      color: kind == WalletKind.debt ? c.merah : c.redup,
                    ),
                  ),
                  onTap: () => Navigator.of(context).pop(wallet),
                ),
            ],
        ],
      ),
    );
  }
}
