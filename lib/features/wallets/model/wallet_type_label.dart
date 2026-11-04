/// Indonesian labels of the wallet types (artboard TambahDompet), shared by
/// the Dompet list and the wallet form.
library;

/// The label of [type]; a type the web stored that the app does not know is
/// shown as sent.
String walletTypeLabel(String type) => switch (type) {
      'bank' => 'Rekening bank',
      'e-wallet' => 'E-wallet',
      'cash' => 'Tunai',
      'investment' => 'Investasi',
      'credit' => 'Kartu kredit',
      'paylater' => 'Paylater',
      'other' => 'Lainnya',
      _ => type,
    };
