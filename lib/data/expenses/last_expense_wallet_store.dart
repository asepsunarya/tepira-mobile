import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../session_store.dart' show kSecureStorage;

/// Remembers the wallet of the last expense, so the Jajan form can preselect
/// it (SPEC-v2 §4 `expenses`). Behind an interface so tests use a fake.
abstract interface class LastExpenseWalletStore {
  /// The stored wallet id, or null when none is stored or it is unreadable.
  Future<int?> read();

  Future<void> write(int walletId);
}

/// [LastExpenseWalletStore] in `flutter_secure_storage` under [key], with
/// the session's storage options, as SPEC-v2 §10 asks (no new dependency).
class SecureLastExpenseWalletStore implements LastExpenseWalletStore {
  const SecureLastExpenseWalletStore([this._storage = kSecureStorage]);

  static const key = 'lastExpenseWalletId';

  final FlutterSecureStorage _storage;

  @override
  Future<int?> read() async {
    final raw = await _storage.read(key: key);
    return raw == null ? null : int.tryParse(raw);
  }

  @override
  Future<void> write(int walletId) =>
      _storage.write(key: key, value: '$walletId');
}

final lastExpenseWalletStoreProvider = Provider<LastExpenseWalletStore>(
  (ref) => const SecureLastExpenseWalletStore(),
);

/// The stored last expense wallet id, read once per form visit.
final lastExpenseWalletIdProvider = FutureProvider.autoDispose<int?>(
  (ref) => ref.watch(lastExpenseWalletStoreProvider).read(),
);
