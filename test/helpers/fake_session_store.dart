import 'package:tepira_mobile/data/session_store.dart';

/// In-memory [SessionStore] for tests.
class FakeSessionStore implements SessionStore {
  FakeSessionStore({this.token, this.userJson});

  String? token;
  String? userJson;

  @override
  Future<String?> readToken() async => token;

  @override
  Future<String?> readUserJson() async => userJson;

  @override
  Future<void> save({required String token, required String userJson}) async {
    this.token = token;
    this.userJson = userJson;
  }

  @override
  Future<void> clear() async {
    token = null;
    userJson = null;
  }
}
