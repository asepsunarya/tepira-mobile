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
    );
  });

  group('exact-int boundary (2^53 - 1) ~/ 100 = 90071992547409', () {
    // Below or at the boundary saved * 100 stays within 2^53 - 1, so it is
    // exact on the web too; above it displayPercent switches to BigInt.
    const boundary = 90071992547409;

    int reference(int saved, int target) =>
        (BigInt.from(saved) * BigInt.from(100) ~/ BigInt.from(target)).toInt();

    test('the boundary is the largest saved with saved * 100 <= 2^53 - 1', () {
      expect(boundary * 100, lessThanOrEqualTo(9007199254740991));
      expect((boundary + 1) * 100, greaterThan(9007199254740991));
    });

    for (final saved in [boundary - 1, boundary, boundary + 1, boundary + 2]) {
      test('saved $saved matches exact floor for nearby targets', () {
        for (final target in [
          saved + 1,
          saved + 2,
          saved * 2,
          saved * 2 + 1,
          saved * 3 - 1,
          saved * 100 ~/ 73,
          saved * 100 ~/ 73 + 1,
          saved * 100 ~/ 99,
          saved * 100 ~/ 99 + 1,
        ]) {
          expect(
            _percent(saved, target),
            reference(saved, target),
            reason: '$saved / $target',
          );
        }
      });
    }

    test('one rupiah short of the target at the boundary is 99%', () {
      expect(_percent(boundary, boundary + 1), 99);
      expect(_percent(boundary + 1, boundary + 2), 99);
    });

    test('exactly half on either side of the boundary is 50%', () {
      expect(_percent(boundary, boundary * 2), 50);
      expect(_percent(boundary + 1, (boundary + 1) * 2), 50);
    });
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
