import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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

/// Shown when an explicit retry cannot load the goals list to check whether
/// the earlier attempt was stored. Nothing is created until it can check.
const String kNewGoalCheckFailedMessage =
    'Belum bisa cek daftar kavling. Coba lagi sebentar lagi supaya tidak '
    'terpatok dua kali.';

/// Shown when an explicit retry finds a goal with the same title and target
/// but cannot tell whether the earlier attempt stored it (the goals were not
/// known before that attempt). Nothing is created or opened.
const String kNewGoalAmbiguousMessage =
    'Sudah ada kavling dengan nama dan target yang sama. Cek daftar di Desa '
    'dulu supaya tidak terpatok dua kali.';

/// Outcome of looking for a goal an uncertain create may have stored.
sealed class _CreateCheck {
  const _CreateCheck();
}

/// The goal turned up in the reloaded list.
final class _Found extends _CreateCheck {
  const _Found(this.goal);

  final Goal goal;
}

/// The list loaded and holds no matching goal.
final class _NotFound extends _CreateCheck {
  const _NotFound();
}

/// The list could not be loaded, so it is unknown whether the goal exists.
final class _Unverified extends _CreateCheck {
  const _Unverified();
}

/// The list holds a matching goal, but without a snapshot of the goals known
/// before the first attempt it cannot be told apart from an older one.
final class _Ambiguous extends _CreateCheck {
  const _Ambiguous();
}

/// The Bangun kavling screen (`/goal/new`, artboard BuatGoal): name, target,
/// optional deadline and description. On success the Desa list is reloaded
/// and the new goal's Kavling replaces this screen, so going back lands on
/// the Desa.
///
/// A create that fails on the network (timeout, no connection, 502/503/504)
/// may still have been stored, so it is never retried by itself and the user
/// is not told it was not saved. Before the first create the screen takes a
/// snapshot of the goal ids that already exist (from the Desa list, or by
/// loading the list when the Desa has none). After a failed create the list
/// is reloaded, and the newest goal with the same title and target that is
/// not in the snapshot is opened with a notice: it can only come from this
/// screen's attempts, so its `createdAt` is not compared with the phone's
/// clock, which may be skewed against the server's. Without a snapshot no
/// goal is ever opened as recovered. Without a match the screen says the
/// connection dropped and offers an explicit retry, which checks the list
/// again before creating and does not create while the list cannot be
/// loaded or (without a snapshot) already holds an identical goal.
///
/// Accepted trade-off: an identical goal created on another device between
/// the snapshot and a lost create may be opened as recovered, but a
/// duplicate is never created.
///
/// Editing the title or target before a retry makes it a different goal:
/// only goals with the current title and target are looked for.
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

  /// Ids of the goals that existed before the first create of the current
  /// attempt sequence, or null when the list could not be loaded then. A
  /// matching goal is only taken for the one this screen created when it is
  /// not in this snapshot; without a snapshot none is.
  Set<int>? _knownIds;

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
      switch (await _findCreated(title, target)) {
        case _Found(:final goal):
          if (!mounted) return;
          return _openRecovered(goal);
        case _Unverified():
          // Cannot tell whether it was stored: creating now could duplicate.
          if (!mounted) return;
          setState(() {
            _submitting = false;
            _submitError = kNewGoalCheckFailedMessage;
          });
          return;
        case _Ambiguous():
          // An identical goal exists and may be the earlier attempt's.
          if (!mounted) return;
          setState(() {
            _submitting = false;
            _submitError = kNewGoalAmbiguousMessage;
          });
          return;
        case _NotFound():
          if (!mounted) return;
      }
    } else {
      // A fresh attempt: remember what already exists, so a goal from
      // before this submit is never "recovered" as the new one.
      _knownIds = await _snapshotIds();
      if (!mounted) return;
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
        final check = await _findCreated(title, target);
        if (!mounted) return;
        if (check case _Found(:final goal)) return _openRecovered(goal);
        // Not found or not verifiable: the goal may exist either way.
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

  /// Ids of the goals that exist now: the Desa list when it has settled
  /// data, else a fresh load. Null when the list cannot be loaded.
  Future<Set<int>?> _snapshotIds() async {
    // Only look at goalsProvider when something already holds it: reading
    // it otherwise would start a second, unawaited load. Its data is used
    // only when settled: while reloading or after a failed refresh it still
    // carries the previous, possibly stale list.
    final cached = ref.exists(goalsProvider) ? ref.read(goalsProvider) : null;
    if (cached case AsyncData(:final value)
        when !cached.isLoading && !cached.hasError) {
      return value.map((goal) => goal.id).toSet();
    }
    try {
      final goals = await ref.read(goalsRepositoryProvider).list();
      return goals.map((goal) => goal.id).toSet();
    } on AppException {
      return null;
    }
  }

  /// Reloads the goals and looks for the newest one with [title] and
  /// [target] that is not in the snapshot [_knownIds]. Such a goal did not
  /// exist before the first attempt, so it is this screen's: its
  /// `createdAt` is only used to pick the newest, never compared with the
  /// phone's clock.
  ///
  /// [_Unverified] when the list cannot be loaded, which is not the same as
  /// [_NotFound]: the goal may still exist. Without a snapshot nothing is
  /// ever [_Found]: a matching goal gives [_Ambiguous]; a list without one
  /// gives [_NotFound] and becomes the snapshot, since no earlier attempt
  /// stored this goal.
  Future<_CreateCheck> _findCreated(String title, int target) async {
    ref.invalidate(goalsProvider);
    final List<Goal> goals;
    try {
      goals = await ref.read(goalsRepositoryProvider).list();
    } on AppException {
      return const _Unverified();
    }
    final known = _knownIds;
    Goal? match;
    for (final goal in goals) {
      if (known != null && known.contains(goal.id)) continue;
      if (goal.title.trim() != title || goal.target != target) continue;
      if (match == null || goal.createdAt.isAfter(match.createdAt)) {
        match = goal;
      }
    }
    if (known == null) {
      if (match != null) return const _Ambiguous();
      _knownIds = goals.map((goal) => goal.id).toSet();
      return const _NotFound();
    }
    return match == null ? const _NotFound() : _Found(match);
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
/// server's validation message, which [BadRequestException.message] already
/// holds. Network and gateway failures never get here; they show
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
