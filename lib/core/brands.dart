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

  /// Other spellings that mean this brand (lowercase, single-spaced).
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

/// Every matcher, longest spelling first, built once.
final List<(String, Brand)> _matchers = [
  for (final brand in [..._extraBrands, ...kPickerBrands])
    for (final spelling in [_normalize(brand.name), ...brand.aliases])
      (spelling, brand),
]..sort((a, b) => b.$1.length.compareTo(a.$1.length));

/// The brand a wallet named [walletName] belongs to, or null. Matches a
/// brand name (or alias) as whole words, ignoring case and extra spaces, so
/// "Kartu kredit BCA" and "bca utama" both get the BCA logo.
Brand? brandForWalletName(String walletName) {
  final name = ' ${_normalize(walletName)} ';
  for (final (spelling, brand) in _matchers) {
    if (name.contains(' $spelling ')) return brand;
  }
  return null;
}

String _normalize(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
