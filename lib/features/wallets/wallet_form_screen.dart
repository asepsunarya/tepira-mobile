import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../core/brands.dart';
import '../../core/errors.dart';
import '../../core/routes.dart';
import '../../core/rupiah_input_formatter.dart';
import '../../core/theme.dart';
import '../../core/unexpected_error.dart';
import '../../core/widgets/village_button.dart';
import '../../core/widgets/village_card.dart';
import '../../core/widgets/village_chip.dart';
import '../../data/wallets/wallets_repository.dart';
import 'model/wallet.dart';
import 'model/wallet_form_rules.dart';
import 'model/wallet_input.dart';
import 'model/wallet_type_label.dart';
import 'wallet_providers.dart';
import 'widgets/wallet_logo.dart';

/// Explanation under the "Dana dicadangkan" toggle (SPEC-v2 §4 `wallets`).
const String kReservedExplanation =
    'Uang yang disisihkan untuk tujuan tertentu. Tetap dihitung sebagai aset, '
    'tidak dihitung sebagai uang bebas.';

/// Shown when a create failed on the network: the wallet may have been
/// stored, so the user checks the list before saving again.
const String kWalletCreateUncertainMessage =
    'Koneksi terputus. Dompetmu mungkin sudah tersimpan. Cek daftar dompet '
    'dulu sebelum menyimpan lagi, supaya tidak dobel.';

/// Shown on `/wallets/:id/edit` when the id is invalid or the wallet is not
/// in the user's list.
const String kWalletNotFoundMessage = 'Dompet tidak ditemukan.';

/// The Tambah dompet (`/wallets/new`) and Ubah dompet (`/wallets/:id/edit`)
/// screens, artboard TambahDompet: brand picker, name, type, balance (or the
/// amount owed), description and the "Dana dicadangkan" toggle.
///
/// The edit form takes the wallet from [walletsProvider]; an id that is
/// invalid or not in the list shows [kWalletNotFoundMessage]. On success the
/// answer is put into [walletsProvider] (list and totals) and the screen
/// returns to the Dompet.
class WalletFormScreen extends ConsumerWidget {
  /// The Tambah dompet screen.
  const WalletFormScreen.create({super.key})
      : walletId = null,
        isEdit = false;

  /// The Ubah dompet screen for [walletId]; null means the path id was not
  /// valid.
  const WalletFormScreen.edit({super.key, required this.walletId})
      : isEdit = true;

  final int? walletId;
  final bool isEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isEdit) return const _WalletForm(original: null);
    final id = walletId;
    if (id == null) return const _Message(text: kWalletNotFoundMessage);
    final wallets = ref.watch(walletsProvider);
    final data = wallets.valueOrNull;
    if (data != null && !wallets.hasError) {
      final wallet = data.wallets.where((w) => w.id == id).firstOrNull;
      if (wallet == null) return const _Message(text: kWalletNotFoundMessage);
      return _WalletForm(key: ValueKey(id), original: wallet);
    }
    if (wallets.hasError && !wallets.isLoading) {
      final error = wallets.error;
      return _Message(
        text: error is AppException
            ? error.message
            : 'Dompet belum bisa dimuat. Coba lagi.',
        onRetry: ref.read(walletsProvider.notifier).refresh,
      );
    }
    return const _Frame(
      title: 'Ubah dompet',
      child: Padding(
        padding: EdgeInsets.only(top: 48),
        child: Center(
          child: CircularProgressIndicator(semanticsLabel: 'Memuat dompet'),
        ),
      ),
    );
  }
}

class _WalletForm extends ConsumerStatefulWidget {
  const _WalletForm({super.key, required this.original});

  /// The stored wallet on the edit screen; null on create.
  final Wallet? original;

  @override
  ConsumerState<_WalletForm> createState() => _WalletFormState();
}

class _WalletFormState extends ConsumerState<_WalletForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _balance;
  late final TextEditingController _description;
  late String _type;
  late bool _reserved;
  bool _submitting = false;
  String? _submitError;

  Wallet? get _original => widget.original;
  bool get _isDebt => walletIsDebt(_type, _original);

  @override
  void initState() {
    super.initState();
    final original = _original;
    _name = TextEditingController(text: original?.name ?? '');
    _balance = TextEditingController(
      text: original == null ? '' : groupRupiahDigits('${original.balance}'),
    );
    _description = TextEditingController(text: original?.description ?? '');
    _type = original?.type ?? 'cash';
    _reserved = original != null && original.isReserved && !original.isDebt;
  }

  @override
  void dispose() {
    _name.dispose();
    _balance.dispose();
    _description.dispose();
    super.dispose();
  }

  void _pickType(String type) {
    setState(() {
      _type = type;
      if (_isDebt) _reserved = false;
    });
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitError = null);
    if (!_formKey.currentState!.validate()) return;

    final original = _original;
    final balance = parseWalletBalance(_balance.text)!;
    final repository = ref.read(walletsRepositoryProvider);
    final Future<WalletWrite> Function() request;
    if (original == null) {
      request = () => repository.create(
            NewWallet(
              name: _name.text,
              type: _type,
              balance: balance,
              isDebt: _isDebt,
              isReserved: _reserved,
              description: _description.text,
            ),
          );
    } else {
      final patch = WalletPatch.between(
        original,
        WalletEdit(
          name: _name.text,
          type: _type,
          balance: balance,
          isReserved: _reserved,
          description: _description.text,
        ),
      );
      if (patch.isEmpty) return _leave();
      request = () => repository.update(original.id, patch);
    }

    setState(() => _submitting = true);
    final WalletWrite write;
    var saved = false;
    try {
      write = await request();
      saved = true;
    } on AppException catch (error) {
      if (!mounted) return;
      final uncertain = original == null &&
          (error is NetworkException || isGatewayError(error));
      if (uncertain && ref.exists(walletsProvider)) {
        ref.read(walletsProvider.notifier).refresh();
      }
      setState(() {
        _submitError =
            uncertain ? kWalletCreateUncertainMessage : error.message;
      });
      return;
    } catch (_) {
      // Not an AppException: a bug or a parse error. Say so inline, and
      // rethrow so the error is forwarded to the zone error handler.
      if (mounted) setState(() => _submitError = kUnexpectedErrorMessage);
      rethrow;
    } finally {
      // Any failure, including an unexpected error, unblocks the form.
      if (!saved && mounted) setState(() => _submitting = false);
    }
    if (!mounted) return;
    if (ref.exists(walletsProvider)) {
      ref.read(walletsProvider.notifier).applyWrite(write);
    }
    _leave();
  }

  void _leave() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(WalletRoutes.list);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    final original = _original;
    final debt = _isDebt;
    final error = _submitError;
    final enabled = !_submitting;
    return _Frame(
      title: original == null ? 'Tambah dompet' : 'Ubah dompet',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            VillageCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Preview(name: _name, type: _type, isDebt: debt),
                  const SizedBox(height: 14),
                  const _Label('Pilih merek'),
                  _BrandPicker(
                    name: _name,
                    onPick: enabled
                        ? (brand) => setState(() => _name.text = brand.name)
                        : null,
                  ),
                  const SizedBox(height: 14),
                  const _Label('Nama dompet'),
                  TextFormField(
                    key: const Key('name'),
                    controller: _name,
                    enabled: enabled,
                    textInputAction: TextInputAction.next,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      hintText: 'BCA, GoPay, Dompet tunai…',
                    ),
                    validator: (value) => walletNameError(value ?? ''),
                  ),
                  const SizedBox(height: 14),
                  const _Label('Jenis'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final type in walletTypeChoices(original))
                        VillageChip(
                          key: Key('type-$type'),
                          label: walletTypeLabel(type),
                          selected: type == _type,
                          onTap: enabled ? () => _pickType(type) : null,
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _Label(
                    debt
                        ? 'Terutang saat ini'
                        : original == null
                            ? 'Saldo awal'
                            : 'Saldo saat ini',
                  ),
                  TextFormField(
                    key: const Key('balance'),
                    controller: _balance,
                    enabled: enabled,
                    keyboardType: const TextInputType.numberWithOptions(
                      signed: true,
                    ),
                    inputFormatters: const [SignedRupiahFormatter()],
                    decoration: const InputDecoration(
                      prefixText: 'Rp ',
                      hintText: '0',
                    ),
                    validator: (value) => walletBalanceError(
                      value ?? '',
                      isDebt: debt,
                      original: original,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    debt
                        ? 'Jajan dari dompet ini menambah utang, bukan '
                            'memotong saldo.'
                        : original == null
                            ? 'Saldo awal hanya dipakai sebagai titik mulai. '
                                'Jajan berikutnya mengubahnya otomatis.'
                            : 'Mengubah saldo di sini adalah koreksi manual; '
                                'tidak dicatat sebagai jajan.',
                    style: villageText(
                      fontSize: 11,
                      color: c.redup,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const _Label('Deskripsi (opsional)'),
                  TextFormField(
                    key: const Key('description'),
                    controller: _description,
                    enabled: enabled,
                    minLines: 1,
                    maxLines: 3,
                    validator: (value) => walletDescriptionError(value ?? ''),
                  ),
                  const SizedBox(height: 8),
                  _ReservedToggle(
                    value: _reserved,
                    onChanged: enabled && !debt
                        ? (value) => setState(() => _reserved = value)
                        : null,
                    debt: debt,
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
              label: _submitting ? 'Menyimpan…' : 'Simpan dompet',
              onPressed: _submitting ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}

/// The wallet as it will look in the list, following the name and type.
class _Preview extends StatelessWidget {
  const _Preview({
    required this.name,
    required this.type,
    required this.isDebt,
  });

  final TextEditingController name;
  final String type;
  final bool isDebt;

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: name,
      builder: (context, value, _) {
        final shown = value.text.trim();
        return Row(
          children: [
            WalletLogo(name: shown, type: type, isDebt: isDebt, size: 52),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    shown.isEmpty ? 'Nama dompet' : shown,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: villageText(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: c.ink,
                    ),
                  ),
                  Text(
                    isDebt
                        ? 'Dompet utang · ${walletTypeLabel(type)}'
                        : walletTypeLabel(type),
                    style: villageText(
                      fontSize: 12,
                      color: isDebt ? c.merah : c.mintText,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Brand logos; picking one fills the name only (SPEC-v2 §11 assumption 7).
class _BrandPicker extends StatelessWidget {
  const _BrandPicker({required this.name, required this.onPick});

  final TextEditingController name;
  final ValueChanged<Brand>? onPick;

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: name,
      builder: (context, value, _) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final brand in kPickerBrands)
            Semantics(
              button: true,
              selected: value.text.trim() == brand.name,
              label: brand.name,
              child: ExcludeSemantics(
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    key: Key('brand-${brand.name}'),
                    onTap: onPick == null ? null : () => onPick!(brand),
                    borderRadius: BorderRadius.circular(VillageRadius.tile),
                    child: Container(
                      width: 48,
                      height: 48,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: c.putih,
                        border: Border.all(
                          color: value.text.trim() == brand.name
                              ? c.pink
                              : c.tileBorder,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(VillageRadius.tile),
                      ),
                      child: SvgPicture.asset(brand.asset, fit: BoxFit.contain),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReservedToggle extends StatelessWidget {
  const _ReservedToggle({
    required this.value,
    required this.onChanged,
    required this.debt,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool debt;

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    // Its own Material: the card behind it would hide the tile's ink.
    return Material(
      type: MaterialType.transparency,
      child: SwitchListTile(
        key: const Key('reserved'),
        value: value,
        onChanged: onChanged,
        contentPadding: EdgeInsets.zero,
        activeTrackColor: c.mint,
        title: Text(
          'Dana dicadangkan',
          style: villageText(
            fontSize: 13,
            fontWeight: FontWeight.w900,
            color: c.ink,
          ),
        ),
        subtitle: Text(
          debt
              ? 'Dompet utang tidak bisa dijadikan dana dicadangkan.'
              : kReservedExplanation,
          style: villageText(fontSize: 11, color: c.redup, height: 1.4),
        ),
      ),
    );
  }
}

/// Gradient page with a back button, [title] and scrolling [child].
class _Frame extends StatelessWidget {
  const _Frame({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
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
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => context.canPop()
                        ? context.pop()
                        : context.go(WalletRoutes.list),
                    icon: Icon(
                      Icons.chevron_left_rounded,
                      color: c.ink,
                      semanticLabel: 'Kembali ke dompet',
                    ),
                  ),
                  Expanded(
                    child: Text(
                      title,
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
              const SizedBox(height: 14),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// The edit screen when the wallet cannot be shown, with an optional retry.
class _Message extends StatelessWidget {
  const _Message({required this.text, this.onRetry});

  final String text;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    final retry = onRetry;
    return _Frame(
      title: 'Ubah dompet',
      child: VillageCard(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              text,
              key: const Key('formMessage'),
              style: villageText(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: c.ink,
              ),
            ),
            if (retry != null) ...[
              const SizedBox(height: 16),
              VillageButton(
                key: const Key('retry'),
                label: 'Coba lagi',
                onPressed: retry,
              ),
            ],
          ],
        ),
      ),
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
