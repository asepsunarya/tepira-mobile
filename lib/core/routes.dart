/// Paths of the goal screens (SPEC section 4, docs/design/README.md).
abstract final class GoalRoutes {
  static const String create = '/goal/new';
  static const String detailPattern = '/goal/:id';
  static const String record = '/record';

  static String detail(int id) => '/goal/$id';
}

/// Path of the Pengaturan screen (artboard Pengaturan).
const String kSettingsPath = '/settings';
