import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the backend session: the Auth.js session token and the signed-in
/// user as JSON. Kept behind an interface so tests can use an in-memory fake.
abstract interface class SessionStore {
  Future<String?> readToken();

  Future<String?> readUserJson();

  Future<void> save({required String token, required String userJson});

  Future<void> clear();
}

/// The platform keychain/keystore with the options every secure value in
/// the app uses, so all keys live in the same Android backend.
const FlutterSecureStorage kSecureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);

/// [SessionStore] backed by the platform keychain/keystore. The token never
/// goes to SharedPreferences or logs (SPEC section 9).
class SecureSessionStore implements SessionStore {
  const SecureSessionStore([this._storage = kSecureStorage]);

  static const tokenKey = 'tepira.session.token';
  static const userKey = 'tepira.session.user';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> readToken() => _storage.read(key: tokenKey);

  @override
  Future<String?> readUserJson() => _storage.read(key: userKey);

  @override
  Future<void> save({required String token, required String userJson}) async {
    await _storage.write(key: tokenKey, value: token);
    await _storage.write(key: userKey, value: userJson);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: tokenKey);
    await _storage.delete(key: userKey);
  }
}

final sessionStoreProvider = Provider<SessionStore>(
  (ref) => const SecureSessionStore(),
);
