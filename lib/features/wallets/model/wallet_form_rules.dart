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

/// C0 controls and DEL, which the server refuses in a name. C1 controls
/// (U+0080 to U+009F) are accepted, as on the server.
final RegExp _controlChars = RegExp(r'[\x00-\x1F\x7F]');

/// [kWalletNameError] when the trimmed [name] is empty, longer than 60 code
/// points (one emoji counts as one, like `Array.from(s).length` on the
/// server), holds a C0 control character or DEL, or is not well-formed
/// UTF-16; else null.
String? walletNameError(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty ||
      trimmed.runes.length > _maxName ||
      _controlChars.hasMatch(trimmed) ||
      !_isWellFormed(trimmed)) {
    return kWalletNameError;
  }
  return null;
}

/// [kWalletDescriptionError] when the trimmed [description] is longer than
/// 200 code points, holds a NUL character or is not well-formed UTF-16, the
/// server's rules; else null. Blank means none.
String? walletDescriptionError(String description) {
  final trimmed = description.trim();
  if (trimmed.runes.length > _maxDescription ||
      trimmed.contains('\u0000') ||
      !_isWellFormed(trimmed)) {
    return kWalletDescriptionError;
  }
  return null;
}

/// False when [value] holds a lone surrogate (JavaScript `isWellFormed`).
bool _isWellFormed(String value) {
  for (var i = 0; i < value.length; i++) {
    final unit = value.codeUnitAt(i);
    if (unit >= 0xD800 && unit <= 0xDBFF) {
      final next = i + 1 < value.length ? value.codeUnitAt(i + 1) : 0;
      if (next < 0xDC00 || next > 0xDFFF) return false;
      i++;
    } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
      return false;
    }
  }
  return true;
}

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

/// The types the form offers. A new wallet and a debt wallet may take any
/// of [kWalletTypes]; an asset wallet may not take a debt type
/// ([kDebtWalletTypes]), the only type change the server refuses (a debt
/// wallet stays debt whatever its type). The stored type stays selectable
/// even when the app does not know it.
List<String> walletTypeChoices(Wallet? original) {
  if (original == null) return kWalletTypes;
  return [
    for (final type in kWalletTypes)
      if (original.isDebt || !kDebtWalletTypes.contains(type)) type,
    if (!kWalletTypes.contains(original.type)) original.type,
  ];
}

/// Whether a wallet of [type] (or the stored [original]) is debt. Debt never
/// counts as reserved funds, so the reserved toggle is off for it.
bool walletIsDebt(String type, Wallet? original) =>
    original?.isDebt ?? kDebtWalletTypes.contains(type);
