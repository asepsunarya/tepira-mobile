import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/clock.dart';
import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../core/wib.dart';
import '../../core/widgets/village_button.dart';
import '../../core/widgets/village_card.dart';
import 'expense_providers.dart';
import 'model/expense.dart';
import 'model/expense_day.dart';
import 'widgets/expense_action_sheet.dart';
import 'widgets/expense_row.dart';
import 'widgets/history_skeleton.dart';

/// The Riwayat screen (`/history`, artboard Riwayat): one WIB month of
/// expenses with the server's total, grouped by WIB day, newest first.
/// The arrows switch months; the current month is the last one. Only
/// expenses are listed in v2, so the Semua/Setoran/Jajan filter of the
/// artboard is not shown (SPEC-v2 §12 K6). Pull down to reload.
///
/// Tapping a row opens Ubah and Hapus. Ubah opens the filled Jajan form;
/// Hapus asks first. Both put the server's answer into this list, Dompet
/// and Desa without reloading them.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  late WibMonth _month = _currentMonth;

  /// Expenses whose delete is running; their rows ignore taps meanwhile.
  final Set<int> _deleting = {};

  WibMonth get _currentMonth => WibMonth.of(ref.read(clockProvider)());

  void _show(WibMonth month) => setState(() => _month = month);

  Future<void> _openActions(Expense expense) async {
    final action = await showModalBottomSheet<ExpenseAction>(
      context: context,
      // Above the dock, which the shell's navigator sits under.
      useRootNavigator: true,
      builder: (context) => ExpenseActionSheet(expense: expense),
    );
    if (!mounted) return;
    switch (action) {
      case ExpenseAction.edit:
        context.push(ExpenseRoutes.edit(expense.id), extra: expense);
      case ExpenseAction.delete:
        await _delete(expense);
      case null:
        break;
    }
  }

  Future<void> _delete(Expense expense) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => DeleteExpenseDialog(expense: expense),
    );
    if (confirmed != true || !mounted || _deleting.contains(expense.id)) {
      return;
    }
    final writer = ref.read(expenseWriterProvider);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _deleting.add(expense.id));
    String message;
    try {
      await writer.delete(expense.id, listedIn: WibMonth.of(expense.date));
      message = 'Jajan ${formatRupiah(expense.amount)} dihapus';
    } on AppException catch (error) {
      message = error.message;
    } finally {
      // Any failure, including an unexpected error, frees the row again.
      if (mounted) setState(() => _deleting.remove(expense.id));
    }
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    final month = _month;
    final history = ref.watch(historyProvider(month));
    final notifier = ref.read(historyProvider(month).notifier);
    final data = history.valueOrNull;

    final Widget body;
    if (data != null && !history.hasError) {
      body = _Refreshable(
        onRefresh: notifier.refresh,
        children: [
          _MonthTotal(list: data, current: month == _currentMonth),
          if (data.more) ...[
            const SizedBox(height: 8),
            Text(
              'Menampilkan 500 terbaru',
              key: const Key('history-more'),
              textAlign: TextAlign.center,
              style: villageText(fontSize: 11, color: c.redup),
            ),
          ],
          const SizedBox(height: 4),
          if (data.expenses.isEmpty)
            const _EmptyMonth()
          else ...[
            ..._days(data.expenses),
            const SizedBox(height: 6),
            Text(
              'Ketuk catatan untuk mengubah atau menghapus.',
              textAlign: TextAlign.center,
              style: villageText(fontSize: 11, color: c.redup),
            ),
          ],
        ],
      );
    } else if (history.hasError && !history.isLoading) {
      body = _Refreshable(
        onRefresh: notifier.refresh,
        children: [
          _LoadError(error: history.error!, onRetry: notifier.refresh),
        ],
      );
    } else {
      body = const HistorySkeleton();
    }

    return Scaffold(
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
              const _Header(),
              _MonthSwitcher(
                month: month,
                onPrevious: () => _show(month.previous),
                onNext: month.compareTo(_currentMonth) < 0
                    ? () => _show(month.next)
                    : null,
              ),
              Expanded(child: body),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _days(List<Expense> expenses) {
    final today = wibDate(ref.read(clockProvider)());
    return [
      for (final day in groupByWibDay(expenses)) ...[
        _DayTitle(label: _dayLabel(day.day, today)),
        for (final expense in day.expenses) ...[
          ExpenseRow(
            key: ValueKey('expense-${expense.id}'),
            expense: expense,
            onTap: _deleting.contains(expense.id)
                ? null
                : () => _openActions(expense),
          ),
          const SizedBox(height: 6),
        ],
      ],
    ];
  }

  static String _dayLabel(DateTime day, DateTime today) {
    if (day == today) return 'Hari ini';
    if (day == today.subtract(const Duration(days: 1))) return 'Kemarin';
    return formatShortDate(day);
  }
}

/// Back button and the title of artboard Riwayat.
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => context.canPop() ? context.pop() : context.go('/'),
            icon: Icon(
              Icons.chevron_left_rounded,
              color: c.ink,
              semanticLabel: 'Kembali ke desa',
            ),
          ),
          Expanded(
            child: Text(
              'Riwayat',
              textAlign: TextAlign.center,
              style: villageText(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: c.ink,
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}

/// "November 2026" between the previous and next month arrows. A null
/// [onNext] disables the next arrow (no future months).
class _MonthSwitcher extends StatelessWidget {
  const _MonthSwitcher({
    required this.month,
    required this.onPrevious,
    required this.onNext,
  });

  final WibMonth month;
  final VoidCallback onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            key: const Key('month-previous'),
            onPressed: onPrevious,
            icon: Icon(
              Icons.chevron_left_rounded,
              color: c.ink,
              semanticLabel: 'Bulan sebelumnya',
            ),
          ),
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(
                formatMonthYear(month.year, month.month),
                key: const Key('history-month'),
                textAlign: TextAlign.center,
                style: villageText(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: c.ink,
                ),
              ),
            ),
          ),
          IconButton(
            key: const Key('month-next'),
            onPressed: onNext,
            icon: Icon(
              Icons.chevron_right_rounded,
              color: onNext == null ? c.disabled : c.ink,
              semanticLabel: 'Bulan berikutnya',
            ),
          ),
        ],
      ),
    );
  }
}

/// The month's total and count, both from the server: they cover every
/// expense of the month, also those past the 500 sent.
class _MonthTotal extends StatelessWidget {
  const _MonthTotal({required this.list, required this.current});

  final ExpenseList list;

  /// Whether [list] is the current WIB month; a past month is named.
  final bool current;

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.putih,
        borderRadius: BorderRadius.circular(VillageRadius.note),
        border: Border.all(color: c.merahBorder, width: 2),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  current
                      ? 'DIPAKAI BULAN INI'
                      : 'DIPAKAI ${formatMonthName(list.period.month).toUpperCase()}',
                  key: const Key('history-total-label'),
                  style: villageText(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: c.redup,
                  ),
                ),
                Text(
                  formatRupiah(list.total),
                  key: const Key('history-total'),
                  style: villageText(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: c.merah,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${list.count} jajan',
            key: const Key('history-count'),
            style: villageText(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: c.redup,
            ),
          ),
        ],
      ),
    );
  }
}

class _DayTitle extends StatelessWidget {
  const _DayTitle({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
      child: Semantics(
        header: true,
        child: Text(
          label.toUpperCase(),
          style: villageText(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: c.redup,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }
}

/// Pull-to-refresh list that scrolls even when its content is short.
class _Refreshable extends StatelessWidget {
  const _Refreshable({required this.onRefresh, required this.children});

  final Future<void> Function() onRefresh;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        children: children,
      ),
    );
  }
}

class _EmptyMonth extends StatelessWidget {
  const _EmptyMonth();

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    return VillageCard(
      key: const Key('history-empty'),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Belum ada jajan bulan ini',
            style: villageText(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Jajan yang kamu catat akan muncul di sini, dikelompokkan per hari.',
            style: villageText(fontSize: 13, color: c.redup, height: 1.4),
          ),
        ],
      ),
    );
  }
}

/// Load failure with a retry. 401 never lands here: the router already
/// moved to `/login`.
class _LoadError extends StatelessWidget {
  const _LoadError({required this.error, required this.onRetry});

  final Object error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    final message = switch (error) {
      AppException(:final message) => message,
      _ => 'Ada yang tidak beres. Coba lagi.',
    };
    return VillageCard(
      key: const Key('history-error'),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Riwayat belum bisa dimuat',
            style: villageText(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(message, style: villageText(fontSize: 13, color: c.redup)),
          const SizedBox(height: 16),
          VillageButton(
            key: const Key('retry'),
            label: 'Coba lagi',
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}
