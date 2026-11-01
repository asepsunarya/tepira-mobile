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
import 'model/new_goal_input.dart';

/// Message when the goal could not be sent for lack of a connection.
const String kNewGoalNetworkMessage =
    'Koneksi bermasalah, kavling belum dipatok. Coba lagi.';

/// The Bangun kavling screen (`/goal/new`, artboard BuatGoal): name, target,
/// optional deadline and description. On success the Desa list is reloaded
/// and the new goal's Kavling replaces this screen, so going back lands on
/// the Desa.
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

    setState(() => _submitting = true);
    try {
      final goal = await ref.read(goalsRepositoryProvider).create(
            title: _title.text.trim(),
            target: NewGoalInput.parseTarget(_target.text)!,
            description: NewGoalInput.description(_description.text),
            deadline: _deadline,
          );
      if (!mounted) return;
      ref.invalidate(goalsProvider);
      context.pushReplacement(GoalRoutes.detail(goal.id));
    } on AppException catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitError = _messageFor(error);
      });
    }
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

/// The inline message for a failed create. A 400 carries the server's
/// validation message, shown as is; a lost connection asks to retry. The
/// status code decides, since a 400 arrives as [ServerException] when the
/// body is `{ok: false}` and as [ApiException] otherwise.
String _messageFor(AppException error) {
  final status = switch (error) {
    ApiException(:final statusCode) => statusCode,
    ServerException(:final statusCode) => statusCode,
    _ => null,
  };
  if (status == 400) return error.message;
  if (error is NetworkException) return kNewGoalNetworkMessage;
  return error.message;
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
class _RupiahDigitsFormatter extends TextInputFormatter {
  const _RupiahDigitsFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text
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
}
