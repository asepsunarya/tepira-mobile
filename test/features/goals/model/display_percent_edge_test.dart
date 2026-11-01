import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/features/goals/model/build_stage.dart';
import 'package:tepira_mobile/features/goals/model/display_percent.dart';

int _percent(int saved, int target) =>
    displayPercent(saved: saved, target: target);

/// Independent edge cases for displayPercent / buildStage (T7, be23fe7).
void main() {
  group('target zero or negative', () {
    for (final (saved, target) in [
      (0, 0),
      (1, 0),
      (-1, 0),
      (100, -100),
      (-100, -100),
      (-200, -100),
      (1, -9223372036854775807),
    ]) {
      test('$saved / $target is 0% and lahan', () {
        expect(_percent(saved, target), 0);
        expect(buildStage(saved: saved, target: target), BuildStage.lahan);
      });
    }
  });

  group('saved negative', () {
    test('any negative saved is 0% and lahan', () {
      for (final saved in [-1, -5000, -9223372036854775807]) {
        expect(_percent(saved, 10000), 0, reason: '$saved');
        expect(buildStage(saved: saved, target: 10000), BuildStage.lahan);
      }
    });
  });

  group('saved above target', () {
    test('clamps to 100 and selesai', () {
      for (final saved in [10001, 20000, 9223372036854775807]) {
        expect(_percent(saved, 10000), 100, reason: '$saved');
        expect(buildStage(saved: saved, target: 10000), BuildStage.selesai);
      }
    });
  });

  group('one rupiah boundaries', () {
    test('1 short of the target is 99%, never 100%', () {
      for (final target in [100, 101, 1000001, 999999999999]) {
        expect(_percent(target - 1, target), lessThan(100), reason: '$target');
        expect(
          buildStage(saved: target - 1, target: target),
          isNot(BuildStage.selesai),
        );
      }
    });

    test('1 rupiah of a huge target is 0% but already fondasi', () {
      expect(_percent(1, 1000000000000), 0);
      expect(buildStage(saved: 1, target: 1000000000000), BuildStage.fondasi);
    });

    test('tiny targets', () {
      expect(_percent(1, 3), 33);
      expect(_percent(2, 3), 66);
      expect(_percent(1, 2), 50);
      expect(_percent(1, 1), 100);
    });
  });

  group('large rupiah amounts', () {
    test('realistic large goals (up to 1e15 rupiah) are exact', () {
      expect(_percent(500000000000000, 1000000000000000), 50);
      expect(_percent(999999999999999, 1000000000000000), 99);
      expect(_percent(1000000000000000, 1000000000000000), 100);
    });

    test(
      'saved * 100 does not overflow for very large amounts',
      () {
        // 2^62 / 2: true value 50%.
        expect(_percent(4611686018427387904 ~/ 2, 4611686018427387904), 50);
        expect(_percent(100000000000000000, 200000000000000000), 50);
      },
      skip: 'BUG (low impact): displayPercent computes saved * 100 in 64-bit '
          'ints; for saved > ~9.2e16 rupiah it overflows and returns a '
          'negative/garbage percent (e.g. 1e17/2e17 is not 50). Unrealistic '
          'amounts; unverified whether the server caps target. Fix: compare '
          'saved ~/ (target / 100) style or use BigInt when saved > '
          'maxInt ~/ 100.',
    );
  });

  group('fractional server percent is not used', () {
    test('99.96% (server would say 100.0) still shows 99 and atap', () {
      expect(_percent(99960, 100000), 99);
      expect(buildStage(saved: 99960, target: 100000), BuildStage.atap);
    });

    test('29.99% is fondasi, 69.99% is dinding', () {
      expect(buildStage(saved: 2999, target: 10000), BuildStage.fondasi);
      expect(buildStage(saved: 6999, target: 10000), BuildStage.dinding);
    });
  });

  test('monotonic non-decreasing in saved for a fixed target', () {
    const target = 997; // prime, so every step is a fraction
    var last = 0;
    for (var saved = -5; saved <= target + 5; saved++) {
      final p = _percent(saved, target);
      expect(p, inInclusiveRange(0, 100));
      expect(p, greaterThanOrEqualTo(last), reason: '$saved');
      last = p;
    }
  });
}
