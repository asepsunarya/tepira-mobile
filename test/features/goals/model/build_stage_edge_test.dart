import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/features/goals/model/build_stage.dart';

BuildStage _stage(int saved, int target) =>
    buildStage(saved: saved, target: target);

void main() {
  test('one rupiah either side of every boundary (target 10 000)', () {
    expect(_stage(0, 10000), BuildStage.lahan);
    expect(_stage(1, 10000), BuildStage.fondasi);
    expect(_stage(2999, 10000), BuildStage.fondasi);
    expect(_stage(3000, 10000), BuildStage.dinding);
    expect(_stage(6999, 10000), BuildStage.dinding);
    expect(_stage(7000, 10000), BuildStage.atap);
    expect(_stage(9999, 10000), BuildStage.atap);
    expect(_stage(10000, 10000), BuildStage.selesai);
    expect(_stage(10001, 10000), BuildStage.selesai);
  });

  test('a negative saved stays lahan', () {
    expect(_stage(-1, 10000), BuildStage.lahan);
  });

  test('target 1: anything saved finishes the goal', () {
    expect(_stage(0, 1), BuildStage.lahan);
    expect(_stage(1, 1), BuildStage.selesai);
  });

  test('negative target stays lahan', () {
    expect(_stage(5000, -1), BuildStage.lahan);
  });

  test('one rupiah of the largest target is fondasi', () {
    expect(_stage(1, 2147483647), BuildStage.fondasi);
  });

  test('saved far above target with the largest values is selesai', () {
    expect(_stage(2147483647 * 4, 2147483647), BuildStage.selesai);
  });

  // The server rounds percent to one decimal, so a goal just under a
  // boundary can show the boundary percent. The stage follows saved/target
  // (SPEC section 4: buildStage(saved/target)), not the rounded percent.
  test('stage follows saved/target, not the rounded server percent', () {
    // 29.996% -> server percent 30.0, still fondasi.
    expect(_stage(29996, 100000), BuildStage.fondasi);
    // 99.96% -> server percent 100.0, still atap (remaining 4).
    expect(_stage(9996, 10000), BuildStage.atap);
  });

  test('fixture goals land on the expected stages', () {
    expect(_stage(0, 6000000), BuildStage.lahan); // Liburan Lombok, 0%
    expect(_stage(6200000, 15000000), BuildStage.dinding); // Laptop, 41.3%
    expect(_stage(7500000, 30000000), BuildStage.fondasi); // Dana darurat, 25%
    expect(_stage(4500000, 4500000), BuildStage.selesai); // Sepeda, 100%
  });
}
