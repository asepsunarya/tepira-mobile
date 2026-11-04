import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/categories.dart';
import '../../core/clock.dart';
import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/routes.dart';
import '../../core/rupiah_input_formatter.dart';
import '../../core/theme.dart';
import '../../core/wib.dart';
import '../../core/widgets/amount_keypad.dart';
import '../../core/widgets/village_button.dart';
import '../../core/widgets/village_card.dart';
import '../../core/widgets/village_chip.dart';
import '../../data/expenses/last_expense_wallet_store.dart';
import '../wallets/model/wallet.dart';
import '../wallets/wallet_providers.dart';
import 'expense_providers.dart';
import 'model/expense.dart';
import 'model/expense_input.dart';
import 'model/expense_wallet_choice.dart';
import 'widgets/expense_wallet_picker.dart';

/// Amounts of the Jajan quick chips (SPEC-v2 §4: 10, 15, 25 and 50 thousand).
const List<int> kExpenseQuickAmounts = [10000, 15000, 25000, 50000];

/// Oldest day the form offers, in days before today (the API accepts 7).
const int kExpenseMaxDaysBack = 7;

/// The Jajan tab of the Catat screen (`/record?tab=jajan`, SPEC-v2 §4
/// `expenses`): amount by chip, keypad or typing, an optional category,
/// the wallet to pay from, the day, an optional note and, under "Lainnya",
/// the money source. The fastest path is a chip and Simpan.
///
/// Given an [original] expense, the form starts filled with it and saves a
/// change instead (`/record?expense=:id`, SPEC-v2 §3.7): only the fields
/// that differ are sent, and a cleared category or note is sent as null.
/// An orphan row (its wallet deleted on the web) has no wallet selected, so
/// one must be picked before saving.
///
/// Simpan is disabled while a request runs, so a double tap sends one
/// request; the server's 120 s dedupe covers a resend after a lost answer.
class ExpenseForm extends ConsumerStatefulWidget {
  const ExpenseForm({super.key, this.original, this.onSubmittingChanged});

  /// The expense being changed, or null to record a new one.
  final Expense? original;

  /// Told when a save starts and ends, so the screen can lock its tabs.
  final ValueChanged<bool>? onSubmittingChanged;

  @override
  ConsumerState<ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends ConsumerState<ExpenseForm> {
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _note = TextEditingController();

  String? _category;
  int? _pickedWalletId;

  /// The chosen WIB day (UTC midnight, as [wibDate]); null means today.
  DateTime? _day;

  /// The picked source. Null only when changing an expense whose stored
  /// source the app does not know: no chip is selected and the stored
  /// source is kept unless the user picks one.
  ExpenseSource? _source = ExpenseSource.gaji;
  bool _showMore = false;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.original case final original?) {
      _setAmount(original.amount);
      _note.text = original.note ?? '';
      // A web key stored by an older web version selects its chip.
      _category = categoryLabelOf(original.category);
      _pickedWalletId = original.walletId;
      _day = wibDate(original.date);
      _source = ExpenseSource.values
          .where((source) => source.wire == original.source)
          .firstOrNull;
      _showMore = _source != ExpenseSource.gaji;
      // Simpan follows whether the note differs from the stored one.
      _note.addListener(_noteChanged);
    }
    _amount.addListener(_amountChanged);
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  /// The typed amount. Digits too many to parse (a long paste) count as
  /// over [kMaxExpenseAmount], so Simpan shows [kExpenseAmountMessage]
  /// instead of silently treating them as 0.
  int get _amountValue {
    final digits = _amount.text.replaceAll('.', '');
    if (digits.isEmpty) return 0;
    return int.tryParse(digits) ?? kMaxExpenseAmount + 1;
  }

  /// Rebuilds for every edit (chip, keypad, typing or paste), so the chips
  /// and Simpan follow the amount; a new amount clears the last error.
  void _amountChanged() => setState(() => _error = null);

  void _noteChanged() => setState(() {});

  void _setAmount(int amount) {
    final text = amount == 0 ? '' : groupRupiahDigits('$amount');
    _amount.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  DateTime get _today => wibDate(ref.read(clockProvider)());

  /// The picked wallet; when there is none, a new expense gets the default
  /// wallet, while a change keeps none, so an orphan row needs a pick.
  Wallet? _selected(List<Wallet>? wallets, int? lastWalletId) {
    if (wallets == null) return null;
    final picked = _pickedWalletId;
    if (picked != null) {
      for (final wallet in wallets) {
        if (wallet.id == picked) return wallet;
      }
    }
    if (widget.original != null) return null;
    return defaultExpenseWallet(wallets, lastWalletId);
  }

  /// The change [original] would get from the form with [wallet], or null
  /// when the amount is out of range.
  ExpensePatch? _patch(Expense original, Wallet wallet) {
    final amount = _amountValue;
    if (amount < kMinExpenseAmount || amount > kMaxExpenseAmount) return null;
    return ExpensePatch.between(
      original,
      ExpenseEdit(
        amount: amount,
        walletId: wallet.id,
        category: _category,
        note: _note.text,
        source: _source,
        day: wibDayKey(_day ?? _today),
      ),
    );
  }

  void _setSubmitting(bool value) {
    setState(() => _submitting = value);
    widget.onSubmittingChanged?.call(value);
  }

  Future<void> _submit(Wallet wallet) async {
    final amount = _amountValue;
    if (_submitting || amount < kMinExpenseAmount) return;
    if (amount > kMaxExpenseAmount) {
      setState(() => _error = kExpenseAmountMessage);
      return;
    }
    if (widget.original case final original?) {
      return _submitChange(original, wallet);
    }
    final day = _day;
    final expense = NewExpense(
      amount: amount,
      walletId: wallet.id,
      category: _category,
      note: _note.text,
      source: _source ?? ExpenseSource.gaji,
      day: day == null || day == _today ? null : wibDayKey(day),
    );
    final writer = ref.read(expenseWriterProvider);
    final lastWallet = ref.read(lastExpenseWalletStoreProvider);
    setState(() => _error = null);
    _setSubmitting(true);
    var saved = false;
    try {
      await writer.create(expense);
      saved = true;
    } on AppException catch (error) {
      if (!mounted) return;
      if (error is BadRequestException && error.code == 'wallet_not_found') {
        _pickedWalletId = null;
        ref.read(walletsProvider.notifier).refresh();
      }
      setState(() => _error = error.message);
      return;
    } finally {
      // Any failure, including an unexpected error, unblocks the form.
      if (!saved && mounted) _setSubmitting(false);
    }
    // Best effort: a storage failure only loses the next default.
    lastWallet.write(wallet.id).catchError((Object _) {});
    if (!mounted) return;
    widget.onSubmittingChanged?.call(false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Jajan ${formatRupiah(amount)} tercatat')),
    );
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  Future<void> _submitChange(Expense original, Wallet wallet) async {
    final patch = _patch(original, wallet);
    if (patch == null || patch.isEmpty) return;
    final writer = ref.read(expenseWriterProvider);
    setState(() => _error = null);
    _setSubmitting(true);
    var saved = false;
    try {
      await writer.update(
        original.id,
        patch,
        listedIn: WibMonth.of(original.date),
      );
      saved = true;
    } on AppException catch (error) {
      if (!mounted) return;
      if (error is BadRequestException && error.code == 'wallet_not_found') {
        _pickedWalletId = null;
        ref.read(walletsProvider.notifier).refresh();
      }
      setState(() => _error = error.message);
      return;
    } finally {
      // Any failure, including an unexpected error, unblocks the form.
      if (!saved && mounted) _setSubmitting(false);
    }
    if (!mounted) return;
    widget.onSubmittingChanged?.call(false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Jajan diperbarui')),
    );
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(kHistoryPath);
    }
  }

  Future<void> _openWalletPicker(List<Wallet> wallets) async {
    final picked = await showModalBottomSheet<Wallet>(
      context: context,
      isScrollControlled: true,
      builder: (context) => ExpenseWalletSheet(wallets: wallets),
    );
    if (picked != null) {
      setState(() {
        _pickedWalletId = picked.id;
        _error = null;
      });
    }
  }

  Future<void> _pickDay() async {
    final today = _today;
    final first = today.subtract(const Duration(days: kExpenseMaxDaysBack));
    final day = _day ?? today;
    final picked = await showDatePicker(
      context: context,
      // A changed expense may be older than the days on offer.
      initialDate: day.isBefore(first) || day.isAfter(today) ? today : day,
      firstDate: first,
      lastDate: today,
      helpText: 'Tanggal jajan',
    );
    if (picked != null) {
      final day = DateTime.utc(picked.year, picked.month, picked.day);
      setState(() => _day = day);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wallets = ref.watch(walletsProvider);
    final lastWalletId = ref.watch(lastExpenseWalletIdProvider);
    final list = wallets.valueOrNull;

    if (list != null && list.wallets.isEmpty && !wallets.hasError) {
      return const _NoWallets();
    }

    final lastReady = !lastWalletId.isLoading;
    final selected =
        lastReady ? _selected(list?.wallets, lastWalletId.valueOrNull) : null;
    final amount = _amountValue;
    final original = widget.original;
    final unchanged = original != null &&
        selected != null &&
        (_patch(original, selected)?.isEmpty ?? false);
    final canSubmit = selected != null &&
        amount >= kMinExpenseAmount &&
        !unchanged &&
        !_submitting;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            children: [
              _AmountField(
                controller: _amount,
                enabled: !_submitting,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  for (final (i, quick) in kExpenseQuickAmounts.indexed) ...[
                    if (i > 0) const SizedBox(width: 6),
                    Expanded(
                      child: VillageChip(
                        key: Key('expense-chip-$quick'),
                        label: formatRupiah(quick),
                        selected: amount == quick,
                        onTap: _submitting ? null : () => _setAmount(quick),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              _walletField(wallets, selected, lastReady),
              const SizedBox(height: 12),
              const _Label('Kategori (opsional)'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final category in kExpenseCategories)
                    VillageChip(
                      key: Key('category-${category.key}'),
                      label: category.label,
                      selected: _category == category.label,
                      onTap: _submitting
                          ? null
                          : () => setState(
                                () => _category = _category == category.label
                                    ? null
                                    : category.label,
                              ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              const _Label('Tanggal'),
              const SizedBox(height: 6),
              _dayChips(),
              const SizedBox(height: 12),
              TextField(
                key: const Key('expense-note'),
                controller: _note,
                enabled: !_submitting,
                maxLength: kMaxExpenseNoteLength,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Catatan (opsional)',
                  hintText: 'misal: nasi padang',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 4),
              _more(),
              const SizedBox(height: 8),
              AmountKeypad(
                onKey: _submitting
                    ? null
                    : (key) => _setAmount(keypadAmount(amount, key)),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  key: const Key('expense-error'),
                  textAlign: TextAlign.center,
                  style: villageText(
                    fontSize: 13,
                    color: VillageColors.of(context).merah,
                  ),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SizedBox(
            width: double.infinity,
            child: VillageButton(
              key: const Key('expense-submit'),
              label: _ctaLabel(selected, amount, unchanged: unchanged),
              onPressed: canSubmit ? () => _submit(selected) : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _walletField(
    AsyncValue<WalletList> wallets,
    Wallet? selected,
    bool lastReady,
  ) {
    final list = wallets.valueOrNull;
    if (list == null && wallets.hasError) {
      final error = wallets.error;
      return ExpenseWalletField(
        name: 'Daftar dompet gagal dimuat',
        note: error is AppException ? error.message : null,
        warn: true,
        retry: true,
        onTap: () => ref.read(walletsProvider.notifier).refresh(),
      );
    }
    if (list == null || !lastReady) {
      return const ExpenseWalletField(
        name: 'Memuat dompet…',
        note: null,
        warn: false,
        retry: false,
        onTap: null,
      );
    }
    return ExpenseWalletField(
      name: selected?.name ?? 'Pilih dompet',
      note: selected == null ? null : expenseWalletNote(selected),
      warn: false,
      retry: false,
      onTap: _submitting ? null : () => _openWalletPicker(list.wallets),
    );
  }

  Widget _dayChips() {
    final today = _today;
    final yesterday = today.subtract(const Duration(days: 1));
    final day = _day ?? today;
    final other = day != today && day != yesterday;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        VillageChip(
          key: const Key('day-today'),
          label: 'Hari ini',
          selected: day == today,
          onTap: _submitting ? null : () => setState(() => _day = null),
        ),
        VillageChip(
          key: const Key('day-yesterday'),
          label: 'Kemarin',
          selected: day == yesterday,
          onTap: _submitting ? null : () => setState(() => _day = yesterday),
        ),
        VillageChip(
          key: const Key('day-pick'),
          label: other ? formatShortDate(day) : 'Pilih tanggal',
          selected: other,
          onTap: _submitting ? null : _pickDay,
        ),
      ],
    );
  }

  Widget _more() {
    final c = VillageColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          key: const Key('expense-more'),
          onPressed: () => setState(() => _showMore = !_showMore),
          icon: Icon(
            _showMore ? Icons.expand_less_rounded : Icons.expand_more_rounded,
            size: 18,
          ),
          label: const Text('Lainnya'),
          style: TextButton.styleFrom(
            foregroundColor: c.pinkText,
            minimumSize: const Size(44, 44),
            textStyle: villageText(fontSize: 12, fontWeight: FontWeight.w900),
          ),
        ),
        if (_showMore) ...[
          const _Label('Sumber dana'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: [
              for (final (source, label) in const [
                (ExpenseSource.gaji, 'Gaji'),
                (ExpenseSource.bonus, 'Bonus'),
              ])
                VillageChip(
                  key: Key('source-${source.wire}'),
                  label: label,
                  selected: _source == source,
                  onTap: _submitting
                      ? null
                      : () => setState(() => _source = source),
                ),
            ],
          ),
        ],
      ],
    );
  }

  String _ctaLabel(Wallet? selected, int amount, {required bool unchanged}) {
    if (_submitting) return 'Menyimpan…';
    if (amount < kMinExpenseAmount) return 'Isi nominal dulu';
    if (selected == null) return 'Pilih dompet dulu';
    if (unchanged) return 'Belum ada perubahan';
    if (widget.original != null) return 'Simpan perubahan';
    if (amount > kMaxExpenseAmount) return 'Simpan';
    return 'Simpan ${formatRupiah(amount)}';
  }
}

/// Large amount input. Typing and pasting go through
/// [RupiahInputFormatter], so `1.500.000,50` becomes `1.500.000`; the
/// on-screen keypad stands in for the system keyboard.
class _AmountField extends StatelessWidget {
  const _AmountField({required this.controller, required this.enabled});

  final TextEditingController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    final style = villageText(
      fontSize: 40,
      fontWeight: FontWeight.w900,
      color: c.ink,
    );
    return Column(
      children: [
        Text('Nominal', style: villageText(fontSize: 12, color: c.redup)),
        const SizedBox(height: 4),
        TextField(
          key: const Key('expense-amount'),
          controller: controller,
          enabled: enabled,
          keyboardType: TextInputType.none,
          textAlign: TextAlign.center,
          inputFormatters: const [RupiahInputFormatter()],
          style: style,
          decoration: InputDecoration.collapsed(
            hintText: '0',
            hintStyle: style.copyWith(color: c.redup),
          ).copyWith(
            prefixText: 'Rp',
            prefixStyle: style,
          ),
        ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    return Text(
      text.toUpperCase(),
      style: villageText(
        fontSize: 11,
        fontWeight: FontWeight.w900,
        color: c.redup,
      ),
    );
  }
}

/// Shown instead of the form when the user has no wallet yet: an expense
/// always needs one, and the server never picks it.
class _NoWallets extends StatelessWidget {
  const _NoWallets();

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        VillageCard(
          key: const Key('no-wallets'),
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Belum ada dompet',
                style: villageText(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: c.ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Jajan dicatat dari sebuah dompet. Buat dompet pertamamu, '
                'lalu catat jajan di sini.',
                style: villageText(fontSize: 13, color: c.redup),
              ),
              const SizedBox(height: 16),
              VillageButton(
                key: const Key('create-wallet'),
                label: 'Buat dompet dulu',
                onPressed: () => context.push(WalletRoutes.create),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
