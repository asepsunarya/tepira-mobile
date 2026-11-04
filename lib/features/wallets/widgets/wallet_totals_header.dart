import 'package:flutter/material.dart';

import '../../../core/format.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/village_card.dart';
import '../model/wallet.dart';

/// Head of the Dompet screen: "Total saldo" (every non-debt wallet), the
/// "Uang bebas" left after reserved funds and debt, the "Dana dicadangkan"
/// and the debt. Every number is the server's `totals`; none is recomputed
/// here (SPEC-v2 §7).
class WalletTotalsHeader extends StatelessWidget {
  const WalletTotalsHeader({super.key, required this.totals});

  final WalletTotals totals;

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    return VillageCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TOTAL SALDO',
            style: villageText(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: c.redup,
              letterSpacing: 0.5,
            ),
          ),
          Text(
            formatRupiah(totals.assets),
            key: const Key('total-assets'),
            style: villageText(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: c.ink,
            ),
          ),
          if (totals.debts != 0)
            Text(
              'Utang ${formatRupiah(totals.debts)}',
              key: const Key('total-debts'),
              style: villageText(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: c.merah,
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _Figure(
                  key: const Key('total-free'),
                  label: 'Uang bebas',
                  amount: totals.free,
                  border: c.mintBorder,
                  color: totals.free < 0 ? c.merah : c.mintText,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Figure(
                  key: const Key('total-reserved'),
                  label: 'Dana dicadangkan',
                  amount: totals.reserved,
                  border: c.tileBorder,
                  color: c.kuningText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Uang bebas = total saldo tanpa dana dicadangkan, dikurangi utang.',
            style: villageText(fontSize: 11, color: c.redup, height: 1.3),
          ),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({
    super.key,
    required this.label,
    required this.amount,
    required this.border,
    required this.color,
  });

  final String label;
  final int amount;
  final Color border;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    return Semantics(
      container: true,
      label: '$label ${formatRupiah(amount)}',
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.putih,
            border: Border.all(color: border, width: 2),
            borderRadius: BorderRadius.circular(VillageRadius.tile),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: villageText(fontSize: 10, color: c.redup),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    formatRupiah(amount),
                    style: villageText(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
