import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/core/routes.dart';

void main() {
  test('recordFor preselects the goal with the goal query parameter', () {
    final uri = Uri.parse(GoalRoutes.recordFor(12));
    expect(uri.path, GoalRoutes.record);
    expect(uri.queryParameters, {GoalRoutes.recordGoalParam: '12'});
    expect(GoalRoutes.recordFor(12), '/record?goal=12');
  });

  test('WalletRoutes builds the edit path and validates its id', () {
    expect(WalletRoutes.edit(7), '/wallets/7/edit');
    expect(WalletRoutes.parseId('7'), 7);
    expect(WalletRoutes.parseId('0'), isNull);
    expect(WalletRoutes.parseId('-3'), isNull);
    expect(WalletRoutes.parseId('abc'), isNull);
    expect(WalletRoutes.parseId('2147483648'), isNull);
  });

  test('ExpenseRoutes.record opens the Jajan tab of /record', () {
    final uri = Uri.parse(ExpenseRoutes.record);
    expect(uri.path, GoalRoutes.record);
    expect(uri.queryParameters, {ExpenseRoutes.tabParam: 'jajan'});
  });
}
