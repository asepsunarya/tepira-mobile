import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../core/widgets/village_button.dart';
import '../../core/widgets/village_card.dart';
import 'expense_form.dart';
import 'model/expense.dart';

/// The Jajan form filled with an expense to change it
/// (`/record?expense=:id`, SPEC-v2 §4). The Riwayat passes the listed
/// [expense] along; the API has no endpoint that reads one expense, so a
/// link without it (opened from outside, or after the app was restarted)
/// points back to the Riwayat instead.
class ExpenseEditScreen extends StatefulWidget {
  const ExpenseEditScreen({super.key, required this.expense});

  /// The expense to change, or null when the route did not carry it.
  final Expense? expense;

  @override
  State<ExpenseEditScreen> createState() => _ExpenseEditScreenState();
}

class _ExpenseEditScreenState extends State<ExpenseEditScreen> {
  /// A save is running; closing waits until it ends.
  bool _submitting = false;

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    final expense = widget.expense;
    // Android back waits for a running save, like the close button.
    return PopScope(
      canPop: !_submitting,
      child: Scaffold(
        body: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [c.langit, c.langitMuda, c.kertas],
              stops: const [0, 0.45, 1],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                _Header(enabled: !_submitting),
                Expanded(
                  child: expense == null
                      ? const _MissingExpense()
                      : ExpenseForm(
                          original: expense,
                          onSubmittingChanged: (busy) =>
                              setState(() => _submitting = busy),
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

/// Close button and the "Ubah jajan" title.
class _Header extends StatelessWidget {
  const _Header({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    final radius = BorderRadius.circular(16);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          Material(
            color: c.kartu.withValues(alpha: 0.9),
            shape: RoundedRectangleBorder(
              borderRadius: radius,
              side: BorderSide(color: c.putih, width: 2),
            ),
            child: InkWell(
              key: const Key('close'),
              borderRadius: radius,
              onTap: enabled
                  ? () => context.canPop()
                      ? context.pop()
                      : context.go(kHistoryPath)
                  : null,
              child: SizedBox.square(
                dimension: 44,
                child: Icon(
                  Icons.close_rounded,
                  color: c.ink,
                  semanticLabel: 'Tutup',
                ),
              ),
            ),
          ),
          Expanded(
            child: Text(
              'Ubah jajan',
              textAlign: TextAlign.center,
              style: villageText(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: c.ink,
              ),
            ),
          ),
          const SizedBox(width: 44),
        ],
      ),
    );
  }
}

class _MissingExpense extends StatelessWidget {
  const _MissingExpense();

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        VillageCard(
          key: const Key('expense-missing'),
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Jajan belum bisa dibuka',
                style: villageText(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: c.ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Buka jajan yang ingin diubah dari Riwayat.',
                style: villageText(fontSize: 13, color: c.redup),
              ),
              const SizedBox(height: 16),
              VillageButton(
                key: const Key('open-history'),
                label: 'Buka Riwayat',
                onPressed: () => context.go(kHistoryPath),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
