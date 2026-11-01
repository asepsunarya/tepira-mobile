/// The whole percent shown for [saved] out of [target] rupiah:
/// `floor(saved * 100 / target)` clamped to 0..100.
///
/// Rounds down so a goal never shows 100% before `saved >= target`; the
/// server's one-decimal `percent` can read 100.0 at 99.96%. Integer math
/// keeps every boundary exact; amounts too large for `saved * 100` to fit
/// in an int use [BigInt] instead of overflowing.
int displayPercent({required int saved, required int target}) {
  if (target <= 0 || saved <= 0) return 0;
  if (saved >= target) return 100;
  // Here 0 < saved < target, so the quotient is 0..99.
  if (saved <= _maxExactSaved) return saved * 100 ~/ target;
  return (BigInt.from(saved) * _hundred ~/ BigInt.from(target)).toInt();
}

/// The largest saved amount for which `saved * 100` is exact on every
/// platform: on the web an int is a double, exact only up to 2^53 - 1.
const int _maxExactSaved = 9007199254740991 ~/ 100;

final BigInt _hundred = BigInt.from(100);
