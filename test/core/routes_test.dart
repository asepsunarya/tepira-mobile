import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/core/routes.dart';

void main() {
  test('recordFor preselects the goal with the goal query parameter', () {
    final uri = Uri.parse(GoalRoutes.recordFor(12));
    expect(uri.path, GoalRoutes.record);
    expect(uri.queryParameters, {GoalRoutes.recordGoalParam: '12'});
    expect(GoalRoutes.recordFor(12), '/record?goal=12');
  });
}
