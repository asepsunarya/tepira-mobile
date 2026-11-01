import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../core/widgets/village_button.dart';
import '../../core/widgets/village_card.dart';
import '../../core/widgets/village_chip.dart';
import '../../data/goals/goals_repository.dart';
import 'goal_providers.dart';
import 'model/goal.dart';
import 'widgets/amount_keypad.dart';

/// Amounts of the quick chips (SPEC section 4: 10, 20, 50 and 100 thousand).
const List<int> kQuickAmounts = [10000, 20000, 50000, 100000];

/// The Setor screen (`/record?goal=<id>`, artboard TambahSetoran): pick a
/// goal, enter an amount with the chips or keypad, add an optional note and
/// deposit. Jajan and quick capture are outside SPEC section 4.
///
/// A deposit that fails on the network may still have been stored, so it is
/// never retried by itself: the goal is reloaded and its latest deposits are
/// shown, and the user decides whether to deposit again.
class ContributeScreen extends ConsumerStatefulWidget {
  const ContributeScreen({super.key, this.goalParam});

  /// Raw `goal` query parameter. It preselects a goal when it is a decimal
  /// goal id from the user's list; otherwise the user picks one.
  final String? goalParam;

  @override
  ConsumerState<ContributeScreen> createState() => _ContributeScreenState();
}

class _ContributeScreenState extends ConsumerState<ContributeScreen> {
  final TextEditingController _note = TextEditingController();

  /// Goal the user picked; until then the requested goal is used.
  int? _pickedId;
  int _amount = 0;
  bool _submitting = false;

  /// Message of the last definite failure (the deposit was not stored).
  String? _error;

  /// Goal whose last deposit failed on the network, so may be stored.
  int? _uncertainGoalId;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  int? get _requestedId {
    final raw = widget.goalParam;
    return raw == null ? null : GoalRoutes.parseId(raw);
  }

  Goal? _selected(List<Goal>? goals) {
    final id = _pickedId ?? _requestedId;
    if (goals == null || id == null) return null;
    for (final goal in goals) {
      if (goal.id == id) return goal;
    }
    return null;
  }

  void _setAmount(int amount) => setState(() {
        _amount = amount;
        _error = null;
      });

  void _pick(Goal goal) => setState(() {
        _pickedId = goal.id;
        _error = null;
        _uncertainGoalId = null;
      });

  Future<void> _submit(Goal goal) async {
    if (_submitting || _amount <= 0) return;
    final amount = _amount;
    final note = _note.text.trim();
    setState(() {
      _submitting = true;
      _error = null;
      _uncertainGoalId = null;
    });
    try {
      await ref
          .read(goalsRepositoryProvider)
          .contribute(goal.id, amount, note.isEmpty ? null : note);
    } on NetworkException {
      if (!mounted) return;
      _reload(goal.id);
      setState(() {
        _submitting = false;
        _uncertainGoalId = goal.id;
      });
      return;
    } on AppException catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = error.message;
      });
      return;
    }
    if (!mounted) return;
    _reload(goal.id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Setoran ${formatRupiah(amount)} masuk ke ${goal.title}.',
        ),
      ),
    );
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(GoalRoutes.detail(goal.id));
    }
  }

  void _reload(int goalId) {
    ref.invalidate(goalDetailProvider(goalId));
    ref.invalidate(goalsProvider);
  }

  Future<void> _openPicker(List<Goal> goals) async {
    final picked = await showModalBottomSheet<Goal>(
      context: context,
      builder: (context) => _GoalPickerSheet(goals: goals),
    );
    if (picked != null) _pick(picked);
  }

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    final goals = ref.watch(goalsProvider);
    final list = goals.valueOrNull;
    final selected = _selected(list);
    final requestMissing = widget.goalParam != null &&
        _pickedId == null &&
        list != null &&
        selected == null;
    final uncertainId = _uncertainGoalId;
    final canSubmit = selected != null && _amount > 0 && !_submitting;

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
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                  children: [
                    _GoalField(
                      goals: goals,
                      selected: selected,
                      requestMissing: requestMissing,
                      onTap: list == null || _submitting
                          ? null
                          : () => _openPicker(list),
                      onRetry: () => ref.invalidate(goalsProvider),
                    ),
                    if (uncertainId != null) ...[
                      const SizedBox(height: 12),
                      _UncertainDeposit(goalId: uncertainId),
                    ],
                    const SizedBox(height: 12),
                    _AmountDisplay(amount: _amount),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        for (final (i, amount) in kQuickAmounts.indexed) ...[
                          if (i > 0) const SizedBox(width: 6),
                          Expanded(
                            child: VillageChip(
                              key: Key('chip-$amount'),
                              label: formatRupiah(amount),
                              selected: _amount == amount,
                              onTap:
                                  _submitting ? null : () => _setAmount(amount),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('note'),
                      controller: _note,
                      enabled: !_submitting,
                      maxLength: 120,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'Catatan (opsional)',
                        hintText: 'misal: sisa uang jajan',
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 12),
                    AmountKeypad(
                      onKey: _submitting
                          ? null
                          : (key) => _setAmount(keypadAmount(_amount, key)),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _error!,
                        key: const Key('submit-error'),
                        textAlign: TextAlign.center,
                        style: villageText(fontSize: 13, color: c.merah),
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
                    key: const Key('submit'),
                    label: _ctaLabel(selected),
                    onPressed: canSubmit ? () => _submit(selected) : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _ctaLabel(Goal? selected) {
    if (_submitting) return 'Menyimpan…';
    if (selected == null) return 'Pilih kavling dulu';
    if (_amount <= 0) return 'Isi nominal dulu';
    final label = 'Setor ${formatRupiah(_amount)}';
    return _uncertainGoalId == null ? label : '$label lagi';
  }
}

/// Close button and the Setor title. Jajan is shown but disabled: it is
/// outside SPEC section 4.
class _Header extends StatelessWidget {
  const _Header();

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
              borderRadius: radius,
              onTap: () => context.canPop() ? context.pop() : context.go('/'),
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
              'Setor',
              textAlign: TextAlign.center,
              style: villageText(
                fontSize: 15,
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

/// "Setor ke kavling" field: the selected goal, a prompt to pick one, or the
/// goal list's loading and error states.
class _GoalField extends StatelessWidget {
  const _GoalField({
    required this.goals,
    required this.selected,
    required this.requestMissing,
    required this.onTap,
    required this.onRetry,
  });

  final AsyncValue<List<Goal>> goals;
  final Goal? selected;
  final bool requestMissing;
  final VoidCallback? onTap;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    final list = goals.valueOrNull;
    final String name;
    String? note;
    if (selected case final goal?) {
      name = goal.title;
      note = '${formatRupiah(goal.saved)} dari ${formatRupiah(goal.target)}';
    } else if (list != null) {
      name = list.isEmpty ? 'Belum ada kavling' : 'Pilih kavling';
      if (requestMissing) note = 'Kavling dari tautan tidak ditemukan.';
    } else if (goals.hasError) {
      final error = goals.error;
      name = 'Daftar kavling gagal dimuat';
      note = error is AppException ? error.message : null;
    } else {
      name = 'Memuat kavling…';
    }

    final radius = BorderRadius.circular(16);
    return Material(
      color: c.putih,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: c.tileBorder, width: 2),
      ),
      child: InkWell(
        key: const Key('goal-picker'),
        borderRadius: radius,
        onTap: goals.hasError && list == null ? onRetry : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SETOR KE KAVLING',
                      style: villageText(fontSize: 10, color: c.redup),
                    ),
                    Text(
                      name,
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
                          color: requestMissing ? c.merah : c.redup,
                        ),
                      ),
                  ],
                ),
              ),
              Icon(
                goals.hasError && list == null
                    ? Icons.refresh_rounded
                    : Icons.expand_more_rounded,
                color: c.redup,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoalPickerSheet extends StatelessWidget {
  const _GoalPickerSheet({required this.goals});

  final List<Goal> goals;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          for (final goal in goals)
            ListTile(
              key: Key('pick-${goal.id}'),
              title: Text(goal.title),
              subtitle: Text(
                '${formatRupiah(goal.saved)} dari ${formatRupiah(goal.target)}',
              ),
              onTap: () => Navigator.of(context).pop(goal),
            ),
        ],
      ),
    );
  }
}

class _AmountDisplay extends StatelessWidget {
  const _AmountDisplay({required this.amount});

  final int amount;

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    return Semantics(
      liveRegion: true,
      label: 'Nominal ${formatRupiah(amount)}',
      excludeSemantics: true,
      child: Column(
        children: [
          Text('Nominal', style: villageText(fontSize: 12, color: c.redup)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              formatRupiah(amount),
              key: const Key('amount'),
              style: villageText(
                fontSize: 40,
                fontWeight: FontWeight.w900,
                color: amount > 0 ? c.ink : c.redup,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Si penabung lari ke kavling, bangunan naik.',
            style: villageText(fontSize: 12, color: c.redup),
          ),
        ],
      ),
    );
  }
}

/// Shown after a deposit failed on the network: the request may still have
/// reached the server, so the reloaded latest deposits let the user check
/// before depositing again.
class _UncertainDeposit extends ConsumerWidget {
  const _UncertainDeposit({required this.goalId});

  final int goalId;

  static const int _shown = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = VillageColors.of(context);
    final detail = ref.watch(goalDetailProvider(goalId));
    final value = detail.valueOrNull;
    final Widget latest;
    if (detail.isLoading) {
      latest = const Center(
        child: CircularProgressIndicator(semanticsLabel: 'Memuat setoran'),
      );
    } else if (value == null) {
      latest = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Riwayat setoran belum bisa dimuat.',
            style: villageText(fontSize: 12, color: c.merah),
          ),
          const SizedBox(height: 8),
          VillageButton(
            key: const Key('reload-latest'),
            label: 'Muat ulang riwayat',
            variant: VillageButtonVariant.soft,
            onPressed: () => ref.invalidate(goalDetailProvider(goalId)),
          ),
        ],
      );
    } else {
      final contributions = [...value.contributions]
        ..sort((a, b) => b.date.compareTo(a.date));
      latest = contributions.isEmpty
          ? Text(
              'Belum ada setoran tercatat.',
              style: villageText(fontSize: 12, color: c.redup),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final contribution in contributions.take(_shown))
                  Text(
                    '${formatShortDate(contribution.date.toLocal())} · '
                    '+${formatRupiah(contribution.amount)}'
                    '${_noteSuffix(contribution.note)}',
                    key: Key('latest-${contribution.id}'),
                    style: villageText(fontSize: 13, color: c.ink),
                  ),
              ],
            );
    }
    return VillageCard(
      key: const Key('uncertain-deposit'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Koneksi terputus',
            style: villageText(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Setoranmu mungkin sudah tercatat. Cek setoran terakhir di bawah '
            'sebelum menyetor lagi.',
            style: villageText(fontSize: 12, color: c.redup, height: 1.4),
          ),
          const SizedBox(height: 8),
          latest,
        ],
      ),
    );
  }

  static String _noteSuffix(String? note) {
    final trimmed = note?.trim();
    return trimmed == null || trimmed.isEmpty ? '' : ' · $trimmed';
  }
}
