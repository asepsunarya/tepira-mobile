/// Paths of the goal screens (SPEC section 4, docs/design/README.md).
abstract final class GoalRoutes {
  static const String create = '/goal/new';
  static const String detailPattern = '/goal/:id';
  static const String record = '/record';

  /// Query parameter of [record] that preselects a goal (SPEC section 4).
  static const String recordGoalParam = 'goal';

  static String detail(int id) => '/goal/$id';

  /// The goal id in a `/goal/:id` path segment, or null when it is not a
  /// positive int32 id written in decimal digits. The server accepts nothing
  /// else, so `0x0C`, `+12`, `-3`, `0` and `2147483648` never reach the API.
  /// Leading zeros are still decimal: `012` is goal 12.
  static int? parseId(String raw) {
    if (!_decimalDigits.hasMatch(raw)) return null;
    final id = int.tryParse(raw);
    return id != null && id > 0 && id <= maxId ? id : null;
  }

  /// The largest goal id the server accepts (the int32 maximum).
  static const int maxId = 2147483647;

  static final RegExp _decimalDigits = RegExp(r'^[0-9]+$');

  /// The Setor screen with goal [id] preselected: `/record?goal=<id>`.
  static String recordFor(int id) =>
      Uri(path: record, queryParameters: {recordGoalParam: '$id'}).toString();
}

/// Path of the Pengaturan screen (artboard Pengaturan).
const String kSettingsPath = '/settings';

/// Paths of the wallet screens (SPEC-v2 §4 `wallets`, artboards Dompet and
/// TambahDompet).
abstract final class WalletRoutes {
  static const String list = '/wallets';
  static const String create = '/wallets/new';
  static const String editPattern = '/wallets/:id/edit';

  static String edit(int id) => '/wallets/$id/edit';

  /// The wallet id in a `/wallets/:id/edit` path segment, or null when it is
  /// not a positive int32 written in decimal digits; the same rule as
  /// [GoalRoutes.parseId], because the server's path ids are the same.
  static int? parseId(String raw) => GoalRoutes.parseId(raw);
}
