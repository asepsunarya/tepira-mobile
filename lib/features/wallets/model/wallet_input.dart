import 'wallet.dart';

/// Body of `POST /api/mobile/wallets` (SPEC-v2 §3.2). The server checks the
/// rules; the form validates the same ones before sending.
class NewWallet {
  const NewWallet({
    required this.name,
    required this.type,
    this.balance = 0,
    this.isDebt = false,
    this.isReserved = false,
    this.description,
  });

  final String name;

  /// One of [kWalletTypes].
  final String type;

  /// Opening balance; for debt, the amount owed (≥ 0).
  final int balance;

  /// The server forces true for [kDebtWalletTypes].
  final bool isDebt;
  final bool isReserved;

  /// Blank means none.
  final String? description;

  Map<String, Object?> toJson() => {
        'name': name.trim(),
        'type': type,
        'balance': balance,
        'isDebt': isDebt,
        'isReserved': isReserved,
        'description': _blankToNull(description),
      };
}

/// The fields a wallet form holds when the user saves an edit.
class WalletEdit {
  const WalletEdit({
    required this.name,
    required this.type,
    required this.balance,
    required this.isReserved,
    required this.description,
  });

  final String name;
  final String type;

  /// Compared with the stored raw [Wallet.balance].
  final int balance;
  final bool isReserved;

  /// Blank means none.
  final String? description;
}

/// Body of `PATCH /api/mobile/wallets/{id}`: only the fields that changed.
///
/// A field left out stays as stored and the server does not write it, which
/// matters for `balance`: sending an unchanged balance would overwrite an
/// expense that moved it meanwhile (SPEC-v2 §3.3).
class WalletPatch {
  const WalletPatch._(this._fields);

  /// The difference between [original] and [edit]. `isDebt` is never sent:
  /// the server rejects any change to it.
  factory WalletPatch.between(Wallet original, WalletEdit edit) {
    final name = edit.name.trim();
    final description = _blankToNull(edit.description);
    return WalletPatch._({
      if (name != original.name) 'name': name,
      if (edit.type != original.type) 'type': edit.type,
      if (edit.balance != original.balance) 'balance': edit.balance,
      if (edit.isReserved != original.isReserved) 'isReserved': edit.isReserved,
      if (description != original.description) 'description': description,
    });
  }

  final Map<String, Object?> _fields;

  /// Nothing changed; the server would answer "Tidak ada perubahan.".
  bool get isEmpty => _fields.isEmpty;

  /// `description: null` clears the description.
  Map<String, Object?> toJson() => Map.unmodifiable(_fields);
}

String? _blankToNull(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
