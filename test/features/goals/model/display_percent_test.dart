import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/features/goals/model/build_stage.dart';
import 'package:tepira_mobile/features/goals/model/display_percent.dart';

int _percent(int saved, int target) =>
    displayPercent(saved: saved, target: target);

void main() {
  test('rounds down, so 99.96% shows 99 and not 100', () {
    expect(_percent(9996, 10000), 99);
    expect(_percent(9999, 10000), 99);
    expect(_percent(999999, 1000000), 99);
  });

  test('shows 100 exactly when saved reaches the target', () {
    expect(_percent(10000, 10000), 100);
    expect(_percent(1, 1), 100);
  });

  test('clamps above the target to 100', () {
    expect(_percent(15000, 10000), 100);
    expect(_percent(2147483647 * 4, 2147483647), 100);
  });

  test('rounds down small amounts to 0 and stays 0 for nothing saved', () {
    expect(_percent(0, 10000), 0);
    expect(_percent(99, 10000), 0);
    expect(_percent(100, 10000), 1);
  });

  test('stays 0 for negative saved and non-positive targets', () {
    expect(_percent(-1, 10000), 0);
    expect(_percent(5000, 0), 0);
    expect(_percent(5000, -1), 0);
  });

  test('matches the stage boundaries', () {
    expect(_percent(2999, 10000), 29);
    expect(_percent(3000, 10000), 30);
    expect(_percent(6999, 10000), 69);
    expect(_percent(7000, 10000), 70);
    // 41.3% in the fixture.
    expect(_percent(6200000, 15000000), 41);
  });

  test('the stage agrees with the shown percent', () {
    for (final (saved, target) in [
      (1, 1000),
      (299, 1000),
      (300, 1000),
      (699, 1000),
      (700, 1000),
      (9996, 10000),
      (10000, 10000),
    ]) {
      final percent = _percent(saved, target);
      final expected = percent >= 100
          ? BuildStage.selesai
          : percent >= 70
              ? BuildStage.atap
              : percent >= 30
                  ? BuildStage.dinding
                  : BuildStage.fondasi;
      expect(
        buildStage(saved: saved, target: target),
        expected,
        reason: '$saved/$target shows $percent%',
      );
    }
  });
}
