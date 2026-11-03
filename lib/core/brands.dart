/// Wallet brands with a logo in `assets/brands/` (from `docs/design/brands/full`).
///
/// The brand picker on the wallet form fills only the name (SPEC-v2 §11
/// assumption 7); the type stays the user's choice. A wallet's logo is found
/// from its name, so wallets made on the web get one too.
library;

class Brand {
  const Brand(this.name, this.asset, {this.aliases = const []});

  /// Name the picker fills in, as the design spells it.
  final String name;

  /// SVG under `assets/brands/`.
  final String asset;

  /// Other spellings that mean this brand; normalized like wallet names.
  final List<String> aliases;
}

/// Brands in the picker, in design order (artboard `TambahDompet`):
/// e-wallets first, then banks.
const List<Brand> kPickerBrands = [
  Brand('GoPay', 'assets/brands/gopay.svg'),
  Brand('OVO', 'assets/brands/ovo.svg'),
  Brand('DANA', 'assets/brands/dana.svg'),
  Brand('ShopeePay', 'assets/brands/shopeepay.svg', aliases: ['shopee pay']),
  Brand('LinkAja', 'assets/brands/linkaja.svg', aliases: ['link aja']),
  Brand('BCA', 'assets/brands/bca.svg'),
  Brand('Mandiri', 'assets/brands/mandiri.svg'),
  Brand('BNI', 'assets/brands/bni.svg'),
  Brand('BRI', 'assets/brands/bri.svg'),
  Brand('Jenius', 'assets/brands/jenius.svg'),
  Brand('Jago', 'assets/brands/jago.svg', aliases: ['bank jago']),
  Brand('SeaBank', 'assets/brands/seabank.svg', aliases: ['sea bank']),
];

/// Brands only recognised by name; longer names are checked first so "blu by
/// BCA" is not taken for "BCA".
const List<Brand> _extraBrands = [
  Brand('blu by BCA', 'assets/brands/blu-bca.svg', aliases: ['blu bca', 'blu']),
  Brand('BCA Flazz', 'assets/brands/bca-flazz.svg', aliases: ['flazz']),
  Brand(
    'Mandiri e-money',
    'assets/brands/mandiri-e-money.svg',
    aliases: ['e-money', 'emoney'],
  ),
  Brand('BNI TapCash', 'assets/brands/bni-tapcash.svg', aliases: ['tapcash']),
  Brand('BRI Brizzi', 'assets/brands/bri-brizzi.svg', aliases: ['brizzi']),
  Brand('BTN', 'assets/brands/btn.svg'),
  Brand('Flip', 'assets/brands/flip.svg'),
];

/// Every matcher, longest spelling first, built once. Spellings of equal
/// length keep their list order (name-only brands, then picker brands); the
/// list index is the explicit tie-break, so the order does not depend on
/// [List.sort] being stable. Spellings are normalized like wallet names, so
/// the alias "e-money" is stored as "e money" and still matches
/// "Mandiri e-money".
final List<(String, Brand)> _matchers = () {
  final indexed = [
    for (final brand in [..._extraBrands, ...kPickerBrands])
      for (final spelling in {
        _normalize(brand.name),
        for (final alias in brand.aliases) _normalize(alias),
      })
        (spelling, brand),
  ].indexed.toList()
    ..sort((a, b) {
      final byLength = b.$2.$1.length.compareTo(a.$2.$1.length);
      return byLength != 0 ? byLength : a.$1.compareTo(b.$1);
    });
  return [for (final (_, matcher) in indexed) matcher];
}();

/// Brand spellings that are also everyday Indonesian words ("dana" = fund,
/// "jago" = skilled), so "Dana darurat" or "Jago masak" is not a brand.
/// They match only when they are the whole name or one of [_ambiguousCues]
/// sits right before or after them ("DANA e-wallet", "Bank Jago",
/// "Jago Syariah"). A cue elsewhere in the name belongs to another word, so
/// "Dana darurat di bank BCA" is BCA, not DANA. A cue right after them that is
/// itself directly followed by another brand's spelling belongs to that
/// brand, so "Dana bank BCA" and "Dana Syariah Mandiri" are BCA and Mandiri.
const Set<String> _ambiguousSpellings = {'dana', 'jago'};

/// Words that mark a name as a bank or e-wallet account, as normalized word
/// sequences ("e-wallet" normalizes to "e wallet").
const List<List<String>> _ambiguousCues = [
  ['bank'],
  ['syariah'],
  ['wallet'],
  ['ewallet'],
  ['e', 'wallet'],
];

/// Multi-word aliases that pair an ambiguous word with a cue ("bank jago").
/// Each one is explicit on its own, so it is cue-backed wherever it matches.
/// Built once from [_matchers]: a spelling qualifies only when one of its
/// words is in [_ambiguousSpellings] and a whole [_ambiguousCues] sequence
/// sits right next to that word inside the spelling, so a lone "e" never
/// counts as a cue.
final Set<String> _cueAliases = {
  for (final (spelling, _) in _matchers)
    if (spelling.contains(' ') &&
        _ambiguousSpellings.any(
          (word) => _hasAdjacentCue(spelling.split(' '), word),
        ))
      spelling,
};

/// The words of every spelling in [_matchers] that needs no cue (not in
/// [_ambiguousSpellings]), built once. A cue directly followed by one of
/// these belongs to that brand ("bank" in "Dana bank Mandiri"). Ambiguous
/// spellings are left out, so in "dana wallet jago wallet" both words keep
/// their own cue and the list-order tie-break decides.
final List<List<String>> _clearBrandWords = [
  for (final (spelling, _) in _matchers)
    if (!_ambiguousSpellings.contains(spelling)) spelling.split(' '),
];

/// The brand a wallet named [walletName] belongs to, or null. Matches a
/// brand name (or alias) as whole words, ignoring case, punctuation and extra
/// spaces, so "Kartu kredit BCA.", "(BCA)" and "bca utama" all get the BCA
/// logo. When a name holds several brands ("BCA/Mandiri"), a spelling backed
/// by an explicit bank/e-wallet cue wins first, so "DANA e-wallet via Flip" is
/// DANA and "Bank Jago via Flip" is Jago (see [_isCueBacked]). Otherwise, and
/// among cue-backed spellings, the longest spelling wins, then the first in
/// list order.
Brand? brandForWalletName(String walletName) {
  final normalized = _normalize(walletName);
  if (normalized.isEmpty) return null;
  final name = ' $normalized ';
  final words = normalized.split(' ');
  final spaced = _spacedWordStarts(walletName);
  final found = [
    for (final (spelling, brand) in _matchers)
      if (name.contains(' $spelling ') &&
          (!_ambiguousSpellings.contains(spelling) ||
              normalized == spelling ||
              _hasOwnAdjacentCue(words, spaced, spelling)))
        (spelling, brand),
  ];
  for (final (spelling, brand) in found) {
    if (_isCueBacked(spelling, words, spaced)) return brand;
  }
  return found.isEmpty ? null : found.first.$2;
}

/// Whether the matched [spelling] is an ambiguous brand word made explicit by
/// a cue: "dana"/"jago" with one of [_ambiguousCues] of its own directly next
/// to it in [words] ("DANA e-wallet", see [_hasOwnAdjacentCue]), or one of
/// [_cueAliases] ("bank jago"). Only these spellings outrank the
/// longest-first order; a cue next to a clear brand ("BNI Syariah") changes
/// nothing, because that brand needs no cue to match.
bool _isCueBacked(String spelling, List<String> words, Set<int> spaced) {
  if (_ambiguousSpellings.contains(spelling)) {
    return _hasOwnAdjacentCue(words, spaced, spelling);
  }
  return _cueAliases.contains(spelling);
}

/// Whether some occurrence of the one-word [spelling] in [words] has one of
/// [_ambiguousCues] of its own directly before or after it. A cue after
/// [spelling] that is followed, with only whitespace between, by a clear
/// brand's spelling (see [_clearBrandWords]) belongs to that brand instead:
/// in "Dana bank Mandiri" the "bank" is Mandiri's, so it does not back
/// "dana". Punctuation ends the cue's reach, so in "DANA e-wallet / Flip" the
/// cue stays DANA's. [spaced] holds the indexes of words preceded only by
/// whitespace (see [_spacedWordStarts]).
bool _hasOwnAdjacentCue(
  List<String> words,
  Set<int> spaced,
  String spelling,
) =>
    _hasAdjacentCue(
      words,
      spelling,
      cueTakenAt: (start) =>
          spaced.contains(start) &&
          _clearBrandWords.any((brand) => _wordsAt(words, start, brand)),
    );

/// Whether some occurrence of the one-word [spelling] in [words] has one of
/// [_ambiguousCues] directly before or after it. A cue after [spelling] does
/// not count when [cueTakenAt] is true for the index right after the cue.
bool _hasAdjacentCue(
  List<String> words,
  String spelling, {
  bool Function(int start)? cueTakenAt,
}) {
  for (var i = 0; i < words.length; i++) {
    if (words[i] != spelling) continue;
    for (final cue in _ambiguousCues) {
      if (_wordsAt(words, i - cue.length, cue)) return true;
      if (_wordsAt(words, i + 1, cue) &&
          !(cueTakenAt?.call(i + 1 + cue.length) ?? false)) {
        return true;
      }
    }
  }
  return false;
}

/// Whether [words] holds the word sequence [seq] starting at index [start].
bool _wordsAt(List<String> words, int start, List<String> seq) {
  if (start < 0 || start + seq.length > words.length) return false;
  for (var k = 0; k < seq.length; k++) {
    if (words[start + k] != seq[k]) return false;
  }
  return true;
}

final RegExp _wordPattern = RegExp(r'[\p{L}\p{N}]+', unicode: true);

/// Dart's `\s` plus U+0085 (NEXT LINE), which is Unicode White_Space but
/// not in `\s`.
final RegExp _whitespaceOnly = RegExp(r'^[\s\u0085]+$');

/// Indexes of the words of `_normalize(value).split(' ')` that are separated
/// from the word before them by whitespace only, with no punctuation.
Set<int> _spacedWordStarts(String value) {
  final lower = value.toLowerCase();
  final spaced = <int>{};
  var index = 0;
  int? previousEnd;
  for (final match in _wordPattern.allMatches(lower)) {
    if (previousEnd != null &&
        _whitespaceOnly.hasMatch(lower.substring(previousEnd, match.start))) {
      spaced.add(index);
    }
    previousEnd = match.end;
    index++;
  }
  return spaced;
}

/// Lowercase words joined by single spaces; every run of characters that is
/// not a letter or digit (spaces, ".", ",", "(", ")", "/", "-", ...) is a
/// separator.
String _normalize(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
    .trim();
