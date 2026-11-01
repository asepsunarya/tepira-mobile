/// Paths of the goal screens (SPEC section 4, docs/design/README.md).
abstract final class GoalRoutes {
  static const String create = '/goal/new';
  static const String detailPattern = '/goal/:id';
  static const String record = '/record';

  /// Query parameter of [record] that preselects a goal (SPEC section 4).
  static const String recordGoalParam = 'goal';

  static String detail(int id) => '/goal/$id';

  /// The Setor screen with goal [id] preselected: `/record?goal=<id>`.
  static String recordFor(int id) =>
      Uri(path: record, queryParameters: {recordGoalParam: '$id'}).toString();
}

/// Path of the Pengaturan screen (artboard Pengaturan).
const String kSettingsPath = '/settings';
