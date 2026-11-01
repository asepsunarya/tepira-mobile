/// Paths of the goal screens (SPEC section 4, docs/design/README.md).
abstract final class GoalRoutes {
  static const String create = '/goal/new';
  static const String detailPattern = '/goal/:id';
  static const String record = '/record';

  /// Query parameter of [record] that preselects a goal (SPEC section 4).
  static const String recordGoalParam = 'goal';

  static String detail(int id) => '/goal/$id';

  /// The goal id in a `/goal/:id` path segment, or null when it is not a
  /// positive id written in decimal digits. The server accepts nothing else,
  /// so `0x0C`, `+12`, `-3` and `0` never reach the API. Leading zeros are
  /// still decimal: `012` is goal 12.
  static int? parseId(String raw) {
    if (!_decimalDigits.hasMatch(raw)) return null;
    final id = int.tryParse(raw);
    return id != null && id > 0 ? id : null;
  }

  static final RegExp _decimalDigits = RegExp(r'^[0-9]+$');

  /// The Setor screen with goal [id] preselected: `/record?goal=<id>`.
  static String recordFor(int id) =>
      Uri(path: record, queryParameters: {recordGoalParam: '$id'}).toString();
}

/// Path of the Pengaturan screen (artboard Pengaturan).
const String kSettingsPath = '/settings';
