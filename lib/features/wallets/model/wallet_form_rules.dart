/// Client-side checks of the wallet form, the same rules and messages as the
/// server (SPEC-v2 §3.2, §3.3), so most mistakes are caught before sending.
library;

import 'wallet.dart';

const String kWalletNameError =
    'Nama dompet harus diisi, maksimal 60 karakter.';
const String kWalletBalanceError = 'Saldo harus berupa angka bulat.';
const String kWalletDebtNegativeError = 'Jumlah terutang tidak boleh negatif.';
const String kWalletDescriptionError = 'Deskripsi maksimal 200 karakter.';

const int _maxName = 60;
const int _maxDescription = 200;
const int _minInt32 = -2147483648;
const int _maxInt32 = 2147483647;

final RegExp _controlChars = RegExp(r'[\x00-\x1F\x7F-\x9F]');

/// [kWalletNameError] when the trimmed [name] is empty, longer than 60
/// characters or holds a control character; else null.
String? walletNameError(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty ||
      trimmed.length > _maxName ||
      _controlChars.hasMatch(trimmed)) {
    return kWalletNameError;
  }
  return null;
}

/// [kWalletDescriptionError] when the trimmed [description] is longer than
/// 200 characters; else null. Blank means none.
String? walletDescriptionError(String description) =>
    description.trim().length > _maxDescription
        ? kWalletDescriptionError
        : null;

/// The amount in the balance field: `.`-grouped digits with an optional
/// leading `-`; blank is 0. Null when it is not a whole number in the int32
/// range the server accepts.
int? parseWalletBalance(String text) {
  final compact = text.replaceAll(RegExp(r'[\s.]'), '');
  if (compact.isEmpty) return 0;
  if (!RegExp(r'^-?[0-9]+$').hasMatch(compact)) return null;
  if (compact.replaceFirst('-', '').length > 10) return null;
  final value = int.parse(compact);
  return value < _minInt32 || value > _maxInt32 ? null : value;
}

/// The error for the balance field [text], or null.
///
/// For a debt wallet the amount owed must not be negative, but on an edit
/// that is only checked when the balance changed: the web lets old debt
/// wallets store a negative balance, and renaming one must still work
/// (SPEC-v2 §3.3). [original] is null on create.
String? walletBalanceError(
  String text, {
  required bool isDebt,
  Wallet? original,
}) {
  final value = parseWalletBalance(text);
  if (value == null) return kWalletBalanceError;
  final changed = original == null || value != original.balance;
  if (isDebt && changed && value < 0) return kWalletDebtNegativeError;
  return null;
}

/// The types the form offers. A new wallet may take any of [kWalletTypes];
/// an existing one only those of its own group (asset or debt), since the
/// server refuses to move a wallet between them. A stored type the app does
/// not know stays selectable.
List<String> walletTypeChoices(Wallet? original) {
  if (original == null) return kWalletTypes;
  return [
    for (final type in kWalletTypes)
      if (kDebtWalletTypes.contains(type) == original.isDebt) type,
    if (!kWalletTypes.contains(original.type)) original.type,
  ];
}

/// Whether a wallet of [type] (or the stored [original]) is debt. Debt never
/// counts as reserved funds, so the reserved toggle is off for it.
bool walletIsDebt(String type, Wallet? original) =>
    original?.isDebt ?? kDebtWalletTypes.contains(type);
