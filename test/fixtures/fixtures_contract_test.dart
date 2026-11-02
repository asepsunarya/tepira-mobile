// mobile_wallets.json must be the §2 `GET /api/mobile/wallets` example from
// docs/api-contract-v2.md, byte for byte. The contract lives on main; on a
// base without it the check is skipped.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _contractPath = 'docs/api-contract-v2.md';

/// The first ```json block after the "## 2." heading.
String? _section2Example(String contract) {
  final lines = contract.split('\n');
  final start = lines.indexWhere((l) => l.startsWith('## 2. '));
  if (start < 0) return null;
  final open = lines.indexWhere((l) => l.trim() == '```json', start);
  if (open < 0) return null;
  final next = lines.indexWhere((l) => l.startsWith('## '), start + 1);
  if (next >= 0 && open > next) return null;
  final close = lines.indexWhere((l) => l.trim() == '```', open + 1);
  if (close < 0) return null;
  return '${lines.sublist(open + 1, close).join('\n')}\n';
}

void main() {
  final contract = File(_contractPath);
  test(
    'mobile_wallets.json equals contract §2 exactly',
    () {
      final example = _section2Example(contract.readAsStringSync());
      expect(example, isNotNull, reason: '§2 json example not found');
      expect(
        File('test/fixtures/mobile_wallets.json').readAsStringSync(),
        example,
      );
    },
    skip: contract.existsSync() ? false : '$_contractPath not on this base',
  );
}
