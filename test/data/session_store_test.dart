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

  test('save replaces a previous session', () async {
    const store = SecureSessionStore();
    await store.save(token: 'old', userJson: '{"id":"u1"}');

    await store.save(token: 'new', userJson: '{"id":"u2"}');

    expect(await store.readToken(), 'new');
    expect(await store.readUserJson(), '{"id":"u2"}');
  });

  test('clear without a session is a no-op', () async {
    const store = SecureSessionStore();

    await store.clear();

    expect(await store.readToken(), isNull);
  });

  test('clear leaves unrelated secure-storage keys alone', () async {
    FlutterSecureStorage.setMockInitialValues({'other.key': 'keep'});
    const store = SecureSessionStore();
    await store.save(token: 'jwe-token', userJson: '{}');

    await store.clear();

    expect(await const FlutterSecureStorage().read(key: 'other.key'), 'keep');
  });

  test('clear removes the token and user', () async {
    const store = SecureSessionStore();
    await store.save(token: 'jwe-token', userJson: '{"id":"u1"}');

    await store.clear();

    expect(await store.readToken(), isNull);
    expect(await store.readUserJson(), isNull);
  });
}
