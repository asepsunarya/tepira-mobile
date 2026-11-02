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
/// "Dana darurat di bank BCA" is BCA, not DANA.
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

/// The brand a wallet named [walletName] belongs to, or null. Matches a
/// brand name (or alias) as whole words, ignoring case, punctuation and extra
/// spaces, so "Kartu kredit BCA.", "(BCA)" and "bca utama" all get the BCA
/// logo. When a name holds several brands ("BCA/Mandiri"), the longest
/// spelling wins, then the first in list order.
Brand? brandForWalletName(String walletName) {
  final normalized = _normalize(walletName);
  if (normalized.isEmpty) return null;
  final name = ' $normalized ';
  final words = normalized.split(' ');
  for (final (spelling, brand) in _matchers) {
    if (!name.contains(' $spelling ')) continue;
    if (_ambiguousSpellings.contains(spelling) &&
        normalized != spelling &&
        !_hasAdjacentCue(words, spelling)) {
      continue;
    }
    return brand;
  }
  return null;
}

/// Whether some occurrence of the one-word [spelling] in [words] has one of
/// [_ambiguousCues] directly before or after it.
bool _hasAdjacentCue(List<String> words, String spelling) {
  bool cueAt(int start, List<String> cue) {
    if (start < 0 || start + cue.length > words.length) return false;
    for (var k = 0; k < cue.length; k++) {
      if (words[start + k] != cue[k]) return false;
    }
    return true;
  }

  for (var i = 0; i < words.length; i++) {
    if (words[i] != spelling) continue;
    for (final cue in _ambiguousCues) {
      if (cueAt(i + 1, cue) || cueAt(i - cue.length, cue)) return true;
    }
  }
  return false;
}

/// Lowercase words joined by single spaces; every run of characters that is
/// not a letter or digit (spaces, ".", ",", "(", ")", "/", "-", ...) is a
/// separator.
String _normalize(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
    .trim();
