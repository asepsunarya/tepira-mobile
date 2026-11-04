import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/data/expenses/last_expense_wallet_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('writes and reads back the wallet id', () async {
    const store = SecureLastExpenseWalletStore();

    await store.write(9);

    expect(await store.read(), 9);
  });

  test('clear forgets the wallet and leaves other keys alone', () async {
    FlutterSecureStorage.setMockInitialValues({'other.key': 'keep'});
    const store = SecureLastExpenseWalletStore();
    await store.write(9);

    await store.clear();

    expect(await store.read(), isNull);
    expect(await const FlutterSecureStorage().read(key: 'other.key'), 'keep');
  });
}
