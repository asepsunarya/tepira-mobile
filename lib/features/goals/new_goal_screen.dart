import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/clock.dart';
import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../core/widgets/village_button.dart';
import '../../core/widgets/village_card.dart';
import '../../data/goals/goals_repository.dart';
import 'goal_providers.dart';
import 'model/goal.dart';
import 'model/new_goal_input.dart';

/// Title of the notice shown when a create failed on the network and no
/// matching goal turned up in the reloaded list. The goal may still have
/// been stored, so the user is asked to check before trying again.
const String kNewGoalUncertainTitle = 'Koneksi terputus — cek dulu';

/// Body of the uncertain-create notice.
const String kNewGoalUncertainMessage =
    'Kavlingmu mungkin sudah terpatok. Cek daftar di Desa dulu, atau coba '
    'lagi: kami cek dulu supaya tidak terpatok dua kali.';

/// Snackbar when a create that failed on the network turns out to be stored.
const String kNewGoalRecoveredMessage =
    'Kavling ini sudah terpatok tadi, meski koneksinya sempat terputus.';

/// How far a goal's `createdAt` may be from now and still count as the one
/// this screen just tried to create. Wide enough for a slow request and some
/// clock skew between the phone and the server.
const Duration kNewGoalMatchWindow = Duration(minutes: 10);

/// The Bangun kavling screen (`/goal/new`, artboard BuatGoal): name, target,
/// optional deadline and description. On success the Desa list is reloaded
/// and the new goal's Kavling replaces this screen, so going back lands on
/// the Desa.
///
/// A create that fails on the network (timeout, no connection, 502/503/504)
/// may still have been stored, so it is never retried by itself and the user
/// is not told it was not saved. The goals list is reloaded and a goal with
/// the same title and target created in the last few minutes is opened with
/// a notice. Without a match the screen says the connection dropped and
/// offers an explicit retry, which checks the list again before creating.
class NewGoalScreen extends ConsumerStatefulWidget {
  const NewGoalScreen({super.key});

  @override
  ConsumerState<NewGoalScreen> createState() => _NewGoalScreenState();
}

class _NewGoalScreenState extends ConsumerState<NewGoalScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _target = TextEditingController();
  final _description = TextEditingController();

  /// The user's local calendar date, at local midnight.
  DateTime? _deadline;
  bool _submitting = false;
  String? _submitError;

  /// True after a create failed on the network and no matching goal was
  /// found: the goal may exist, so the next submit checks the list first.
  bool _uncertain = false;

  @override
  void dispose() {
    _title.dispose();
    _target.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _deadline ?? today,
      firstDate: today,
      lastDate: DateTime(today.year + 100, 12, 31),
      helpText: 'Target tanggal',
      cancelText: 'Batal',
      confirmText: 'Pilih',
    );
    if (picked == null || !mounted) return;
    // The picker answers a local midnight; keep only the calendar fields.
    setState(() => _deadline = DateTime(picked.year, picked.month, picked.day));
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitError = null);
    if (!_formKey.currentState!.validate()) return;

    final title = _title.text.trim();
    final target = NewGoalInput.parseTarget(_target.text)!;
    setState(() => _submitting = true);

    if (_uncertain) {
      // The previous attempt may have been stored: look before creating.
      final existing = await _findCreated(title, target);
      if (!mounted) return;
      if (existing != null) return _openRecovered(existing);
    }

    final Goal goal;
    try {
      goal = await ref.read(goalsRepositoryProvider).create(
            title: title,
            target: target,
            description: NewGoalInput.description(_description.text),
            deadline: _deadline,
          );
    } on AppException catch (error) {
      if (!mounted) return;
      if (error is NetworkException || isGatewayError(error)) {
        // Outcome unknown: the goal may have been stored. Never retry here.
        final existing = await _findCreated(title, target);
        if (!mounted) return;
        if (existing != null) return _openRecovered(existing);
        setState(() {
          _submitting = false;
          _uncertain = true;
        });
        return;
      }
      setState(() {
        _submitting = false;
        _submitError = _messageFor(error);
      });
      return;
    }
    if (!mounted) return;
    ref.invalidate(goalsProvider);
    context.pushReplacement(GoalRoutes.detail(goal.id));
  }

  /// Reloads the goals and returns the newest one with [title] and [target]
  /// whose `createdAt` is within [kNewGoalMatchWindow] of now, or null when
  /// there is none or the list cannot be loaded.
  Future<Goal?> _findCreated(String title, int target) async {
    ref.invalidate(goalsProvider);
    final List<Goal> goals;
    try {
      goals = await ref.read(goalsRepositoryProvider).list();
    } on AppException {
      return null;
    }
    final now = ref.read(clockProvider)();
    Goal? match;
    for (final goal in goals) {
      if (goal.title.trim() != title || goal.target != target) continue;
      if (goal.createdAt.difference(now).abs() > kNewGoalMatchWindow) {
        continue;
      }
      if (match == null || goal.createdAt.isAfter(match.createdAt)) {
        match = goal;
      }
    }
    return match;
  }

  void _openRecovered(Goal goal) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text(kNewGoalRecoveredMessage)));
    context.pushReplacement(GoalRoutes.detail(goal.id));
  }

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    final deadline = _deadline;
    final error = _submitError;
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
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                const _Header(),
                const SizedBox(height: 14),
                VillageCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _Label('Nama goal'),
                      TextFormField(
                        key: const Key('title'),
                        controller: _title,
                        enabled: !_submitting,
                        textInputAction: TextInputAction.next,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          hintText: 'mis. Dana darurat',
                        ),
                        validator: (value) =>
                            NewGoalInput.titleError(value ?? ''),
                      ),
                      const SizedBox(height: 14),
                      const _Label('Target'),
                      TextFormField(
                        key: const Key('target'),
                        controller: _target,
                        enabled: !_submitting,
                        keyboardType: TextInputType.number,
                        inputFormatters: const [_RupiahDigitsFormatter()],
                        decoration: const InputDecoration(
                          prefixText: 'Rp ',
                          hintText: '0',
                        ),
                        validator: (value) =>
                            NewGoalInput.targetError(value ?? ''),
                      ),
                      const SizedBox(height: 14),
                      const _Label('Target tanggal (opsional)'),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              key: const Key('deadline'),
                              onPressed: _submitting ? null : _pickDeadline,
                              icon: const Icon(Icons.event_rounded),
                              label: Text(
                                deadline == null
                                    ? 'Pilih tanggal'
                                    : formatShortDate(deadline),
                              ),
                            ),
                          ),
                          if (deadline != null)
                            IconButton(
                              key: const Key('clearDeadline'),
                              onPressed: _submitting
                                  ? null
                                  : () => setState(() => _deadline = null),
                              icon: const Icon(
                                Icons.close_rounded,
                                semanticLabel: 'Hapus tanggal',
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      const _Label('Deskripsi (opsional)'),
                      TextFormField(
                        key: const Key('description'),
                        controller: _description,
                        enabled: !_submitting,
                        minLines: 2,
                        maxLines: 4,
                        validator: (value) =>
                            NewGoalInput.descriptionError(value ?? ''),
                      ),
                    ],
                  ),
                ),
                if (_uncertain) ...[
                  const SizedBox(height: 12),
                  _UncertainCreate(
                    onRetry: _submitting ? null : _submit,
                    onCheck: _submitting
                        ? null
                        : () =>
                            context.canPop() ? context.pop() : context.go('/'),
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    error,
                    key: const Key('submitError'),
                    textAlign: TextAlign.center,
                    style: villageText(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: c.merah,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                VillageButton(
                  key: const Key('submit'),
                  label: _submitting ? 'Mematok kavling…' : 'Patok kavling',
                  onPressed: _submitting ? null : _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The inline message for a definite create failure. A 400 carries the
/// server's validation message, which [AppException.message] already holds,
/// whether it arrives as [ServerException] (`{ok: false}` body) or
/// [ApiException]. Network and gateway failures never get here; they show
/// [_UncertainCreate] instead.
String _messageFor(AppException error) => error.message;

/// Shown after a create failed on the network and the reloaded list had no
/// matching goal: the request may still have reached the server, so the
/// user checks the Desa or retries explicitly (the retry looks again first).
class _UncertainCreate extends StatelessWidget {
  const _UncertainCreate({required this.onRetry, required this.onCheck});

  final VoidCallback? onRetry;
  final VoidCallback? onCheck;

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    return VillageCard(
      key: const Key('uncertain-create'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            kNewGoalUncertainTitle,
            style: villageText(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            kNewGoalUncertainMessage,
            style: villageText(fontSize: 12, color: c.redup, height: 1.4),
          ),
          const SizedBox(height: 8),
          VillageButton(
            key: const Key('uncertain-retry'),
            label: 'Coba lagi',
            variant: VillageButtonVariant.soft,
            onPressed: onRetry,
          ),
          const SizedBox(height: 6),
          TextButton(
            key: const Key('uncertain-check'),
            onPressed: onCheck,
            child: const Text('Cek daftar di Desa'),
          ),
        ],
      ),
    );
  }
}

/// Back button and the "Bangun kavling" title.
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    return Row(
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
            'Bangun kavling',
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
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: villageText(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: c.ink2,
        ),
      ),
    );
  }
}

/// Keeps only digits and groups them by thousands with `.`: typing
/// `1500000` shows `1.500.000`. Signs, commas and letters are dropped, so the
/// field never holds a negative or decimal amount.
///
/// Rupiah has no cents, so a pasted amount ending in a decimal part
/// (`Rp1.500.000,00`, `1.500.000,50`, `1,50`) loses that part before the
/// non-digits are stripped; otherwise `,00` would be glued on and the amount
/// would grow 100x. Only a separator followed by 1 or 2 digits (optionally
/// `-` or `,-`) at the very end counts as decimal; a group of 3 digits is a
/// thousands group (`1,500,000`, `IDR 750.000`).
class _RupiahDigitsFormatter extends TextInputFormatter {
  const _RupiahDigitsFormatter();

  static final RegExp _decimalTail = RegExp(r'(?<=[0-9])[.,][0-9]{1,2},?-?$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = _dropDecimalTail(oldValue, newValue)
        .replaceAll(RegExp(r'[^0-9]'), '')
        .replaceFirst(RegExp(r'^0+(?=[0-9])'), '');
    final grouped = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) grouped.write('.');
      grouped.write(digits[i]);
    }
    final text = grouped.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  /// [newValue]'s text without a trailing decimal part that came in with this
  /// edit. The field itself only ever holds `.`-grouped digits, so a decimal
  /// tail that already overlaps the old text (deleting the last digit of
  /// `1.500.000` gives `1.500.00`) or that sits before the caret's end (a
  /// comma typed mid-number) is left alone and those edits behave as before.
  static String _dropDecimalTail(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.trimRight();
    final match = _decimalTail.firstMatch(text);
    if (match == null) return newValue.text;
    final caret = newValue.selection.isValid
        ? newValue.selection.end
        : newValue.text.length;
    if (caret < text.length) return newValue.text;
    final old = oldValue.text;
    var prefix = 0;
    while (prefix < old.length &&
        prefix < text.length &&
        old.codeUnitAt(prefix) == text.codeUnitAt(prefix)) {
      prefix++;
    }
    if (match.start < prefix) return newValue.text;
    return text.substring(0, match.start);
  }
}
