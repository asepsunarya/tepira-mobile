import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/data/session_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('returns nothing before a session is saved', () async {
    const store = SecureSessionStore();

    expect(await store.readToken(), isNull);
    expect(await store.readUserJson(), isNull);
  });

  test('saves and reads back the token and user', () async {
    const store = SecureSessionStore();

    await store.save(token: 'jwe-token', userJson: '{"id":"u1"}');

    expect(await store.readToken(), 'jwe-token');
    expect(await store.readUserJson(), '{"id":"u1"}');
  });

  test('clear removes the token and user', () async {
    const store = SecureSessionStore();
    await store.save(token: 'jwe-token', userJson: '{"id":"u1"}');

    await store.clear();

    expect(await store.readToken(), isNull);
    expect(await store.readUserJson(), isNull);
  });
}
