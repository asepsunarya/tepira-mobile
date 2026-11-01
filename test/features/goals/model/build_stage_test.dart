import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/features/goals/model/build_stage.dart';

void main() {
  BuildStage stage(int saved, [int target = 1000000]) =>
      buildStage(saved: saved, target: target);

  test('lahan with nothing saved', () {
    expect(stage(0), BuildStage.lahan);
  });

  test('fondasi from the first rupiah up to just under 30%', () {
    expect(stage(1), BuildStage.fondasi);
    expect(stage(299999), BuildStage.fondasi);
  });

  test('dinding from exactly 30% up to just under 70%', () {
    expect(stage(300000), BuildStage.dinding);
    expect(stage(699999), BuildStage.dinding);
  });

  test('atap from exactly 70% up to just under 100%', () {
    expect(stage(700000), BuildStage.atap);
    expect(stage(999999), BuildStage.atap);
  });

  test('selesai at 100% and beyond', () {
    expect(stage(1000000), BuildStage.selesai);
    expect(stage(1500000), BuildStage.selesai);
  });

  test('boundaries are exact for targets that do not divide evenly', () {
    // 30% of 7 is 2.1 and 70% of 7 is 4.9.
    expect(stage(2, 7), BuildStage.fondasi);
    expect(stage(3, 7), BuildStage.dinding);
    expect(stage(4, 7), BuildStage.dinding);
    expect(stage(5, 7), BuildStage.atap);
  });

  test('the largest contract target does not overflow', () {
    const max = 2147483647;
    expect(stage(max ~/ 10 * 3, max), BuildStage.fondasi);
    expect(stage(max - 1, max), BuildStage.atap);
    expect(stage(max, max), BuildStage.selesai);
  });

  test('a non-positive target stays lahan', () {
    expect(stage(0, 0), BuildStage.lahan);
  });
}
