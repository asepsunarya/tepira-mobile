import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/features/expenses/model/expense_wallet_choice.dart';

import '../../../helpers/fake_wallets_repository.dart';

void main() {
  final reserved = testWallet(id: 7, isReserved: true);
  final bca = testWallet(id: 3);
  final card = testWallet(id: 9, type: 'credit', isDebt: true);
  final debtReserved =
      testWallet(id: 12, type: 'paylater', isDebt: true, isReserved: true);

  test('the last used wallet wins when it is not reserved', () {
    expect(defaultExpenseWallet([reserved, bca, card], 9), card);
  });

  test('a reserved last wallet is skipped for the first ordinary one', () {
    expect(defaultExpenseWallet([reserved, card, bca], 7), bca);
  });

  test('a last wallet that is gone falls back', () {
    expect(defaultExpenseWallet([bca, card], 404), bca);
  });

  test('ordinary before debt; reserved never', () {
    expect(defaultExpenseWallet([reserved, card], null), card);
    expect(defaultExpenseWallet([reserved], null), isNull);
    expect(defaultExpenseWallet(const [], 3), isNull);
  });

  test('a debt wallet flagged reserved counts as debt, so it may default', () {
    expect(defaultExpenseWallet([reserved, debtReserved], 12), debtReserved);
  });
}
