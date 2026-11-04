import 'package:flutter/material.dart';

import '../../../core/format.dart';
import '../../../core/theme.dart';
import '../../../core/wib.dart';
import '../model/expense.dart';

/// One expense in the Riwayat list (artboard Riwayat): the WIB time, the
/// note (or the category when there is no note), the category, wallet and
/// place, and the amount in red. A row whose wallet was deleted on the web
/// says "Dompet dihapus".
class ExpenseRow extends StatelessWidget {
  const ExpenseRow({super.key, required this.expense, this.onTap});

  final Expense expense;
  final VoidCallback? onTap;

  /// The row's title: the note, else the category, else "Jajan".
  static String titleOf(Expense expense) =>
      _blankToNull(expense.note) ?? expense.category ?? 'Jajan';

  /// Category (when the title is the note), wallet and place.
  static String metaOf(Expense expense) {
    final hasNote = _blankToNull(expense.note) != null;
    return [
      if (hasNote && expense.category != null) expense.category!,
      expense.walletName ?? 'Dompet dihapus',
      if (_blankToNull(expense.placeName) case final place?) place,
    ].join(' · ');
  }

  /// `HH:mm` of [instant] in WIB, whatever the device time zone.
  static String wibTime(DateTime instant) {
    final wib = instant.toUtc().add(kWibOffset);
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(wib.hour)}:${two(wib.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    final radius = BorderRadius.circular(VillageRadius.note);
    final amount = '-${formatRupiah(expense.amount)}';
    return Semantics(
      button: onTap != null,
      child: Material(
        color: c.putih,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: c.merahBorder, width: 2),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 40,
                    child: Text(
                      wibTime(expense.date),
                      style: villageText(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: c.redup,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          titleOf(expense),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: villageText(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: c.ink,
                          ),
                        ),
                        Text(
                          metaOf(expense),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: villageText(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: c.redup,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    amount,
                    style: villageText(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: c.merah,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String? _blankToNull(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
