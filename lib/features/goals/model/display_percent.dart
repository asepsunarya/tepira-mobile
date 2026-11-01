/// The whole percent shown for [saved] out of [target] rupiah:
/// `floor(saved * 100 / target)` clamped to 0..100.
///
/// Rounds down so a goal never shows 100% before `saved >= target`; the
/// server's one-decimal `percent` can read 100.0 at 99.96%. Integer math
/// keeps every boundary exact.
int displayPercent({required int saved, required int target}) {
  if (target <= 0 || saved <= 0) return 0;
  if (saved >= target) return 100;
  return saved * 100 ~/ target;
}
