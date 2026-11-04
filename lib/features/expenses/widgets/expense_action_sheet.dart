import 'package:flutter/material.dart';

import '../../../core/format.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/village_button.dart';
import '../model/expense.dart';
import 'expense_row.dart';

/// What the user chose for an expense in the Riwayat.
enum ExpenseAction { edit, delete }

/// Bottom sheet of a tapped Riwayat row (artboard Riwayat): the expense and
/// its Ubah and Hapus buttons. Pops with the chosen [ExpenseAction].
class ExpenseActionSheet extends StatelessWidget {
  const ExpenseActionSheet({super.key, required this.expense});

  final Expense expense;

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              ExpenseRow.titleOf(expense),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: villageText(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: c.ink,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${formatRupiah(expense.amount)} · ${ExpenseRow.metaOf(expense)}',
              style: villageText(fontSize: 12, color: c.redup),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: VillageButton(
                    key: const Key('expense-edit'),
                    label: 'Ubah',
                    onPressed: () =>
                        Navigator.of(context).pop(ExpenseAction.edit),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: VillageButton(
                    key: const Key('expense-delete'),
                    label: 'Hapus',
                    variant: VillageButtonVariant.danger,
                    onPressed: () =>
                        Navigator.of(context).pop(ExpenseAction.delete),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks before deleting [expense]; pops true to delete.
class DeleteExpenseDialog extends StatelessWidget {
  const DeleteExpenseDialog({super.key, required this.expense});

  final Expense expense;

  @override
  Widget build(BuildContext context) {
    final refund = expense.walletName == null
        ? 'Dompetnya sudah dihapus, jadi tidak ada saldo yang dikembalikan.'
        : 'Saldo ${expense.walletName} dikembalikan.';
    return AlertDialog(
      title: Text('Hapus jajan ${formatRupiah(expense.amount)}?'),
      content: Text('${ExpenseRow.titleOf(expense)} dihapus. $refund'),
      actions: [
        TextButton(
          key: const Key('cancel-delete'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Batal'),
        ),
        TextButton(
          key: const Key('confirm-delete'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Hapus'),
        ),
      ],
    );
  }
}
