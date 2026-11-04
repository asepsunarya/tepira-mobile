import 'package:flutter/material.dart';

import '../theme.dart';

/// The largest amount the keypad builds, as in artboard TambahSetoran.
const int kMaxKeypadAmount = 999999999;

/// [amount] after pressing [key] on the [AmountKeypad]: a digit group is
/// appended, `⌫` drops the last digit. Presses that would pass
/// [kMaxKeypadAmount] are ignored.
int keypadAmount(int amount, String key) {
  if (key == AmountKeypad.backspace) return amount ~/ 10;
  final next = int.parse('${amount == 0 ? '' : amount}$key');
  return next <= kMaxKeypadAmount ? next : amount;
}

/// Three-column number pad from artboard TambahSetoran: 1 to 9, `000`, `0`
/// and backspace. A null [onKey] disables every key.
class AmountKeypad extends StatelessWidget {
  const AmountKeypad({super.key, required this.onKey});

  static const String backspace = '⌫';
  static const List<String> keys = [
    '1', '2', '3', '4', '5', '6', '7', '8', '9', '000', '0', backspace, //
  ];

  final ValueChanged<String>? onKey;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var row = 0; row < 4; row++) ...[
          if (row > 0) const SizedBox(height: 6),
          Row(
            children: [
              for (var col = 0; col < 3; col++) ...[
                if (col > 0) const SizedBox(width: 6),
                Expanded(
                  child: _Key(label: keys[row * 3 + col], onKey: onKey),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.label, required this.onKey});

  final String label;
  final ValueChanged<String>? onKey;

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    final radius = BorderRadius.circular(VillageRadius.tile);
    final onKey = this.onKey;
    return Semantics(
      button: true,
      label: label == AmountKeypad.backspace ? 'Hapus' : label,
      excludeSemantics: true,
      child: Material(
        color: c.putih,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: c.tileBorder, width: 2),
        ),
        child: InkWell(
          key: Key('key-$label'),
          borderRadius: radius,
          onTap: onKey == null ? null : () => onKey(label),
          child: SizedBox(
            height: 50,
            child: Center(
              child: Text(
                label,
                style: villageText(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: c.ink,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
