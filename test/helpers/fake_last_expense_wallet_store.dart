import 'package:tepira_mobile/data/expenses/last_expense_wallet_store.dart';

/// In-memory [LastExpenseWalletStore] for tests.
class FakeLastExpenseWalletStore implements LastExpenseWalletStore {
  FakeLastExpenseWalletStore([this.walletId]);

  int? walletId;
  final List<int> writes = [];

  @override
  Future<int?> read() async => walletId;

  @override
  Future<void> write(int walletId) async {
    writes.add(walletId);
    this.walletId = walletId;
  }

  int clearCalls = 0;

  @override
  Future<void> clear() async {
    clearCalls++;
    walletId = null;
  }
}
