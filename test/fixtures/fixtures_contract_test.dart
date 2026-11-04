// Each v2 fixture must be the matching ```json example from
// docs/api-contract-v2.md, byte for byte. The contract lives on main; on a
// base without it the checks are skipped.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _contractPath = 'docs/api-contract-v2.md';

/// Fixture name -> (contract section number, index of the ```json block in
/// that section).
const Map<String, (int, int)> _fixtures = {
  'mobile_wallets': (2, 0),
  'mobile_today_budget': (5, 0),
  'mobile_today_wallet': (5, 1),
  'mobile_expense_created': (6, 0),
  'mobile_expense_deduped': (6, 1),
  'mobile_expenses': (7, 0),
  'mobile_expense_updated': (8, 1),
  'mobile_expense_deleted': (9, 0),
  'mobile_expense_deleted_orphan': (9, 1),
};

/// The [index]th ```json block under the "## [section]." heading.
String? _example(String contract, int section, int index) {
  final lines = contract.split('\n');
  final start = lines.indexWhere((l) => l.startsWith('## $section. '));
  if (start < 0) return null;
  var end = lines.indexWhere((l) => l.startsWith('## '), start + 1);
  if (end < 0) end = lines.length;
  var seen = 0;
  for (var i = start + 1; i < end; i++) {
    if (lines[i].trim() != '```json') continue;
    final close = lines.indexWhere((l) => l.trim() == '```', i + 1);
    if (close < 0) return null;
    if (seen++ == index) {
      return '${lines.sublist(i + 1, close).join('\n')}\n';
    }
    i = close;
  }
  return null;
}

void main() {
  final contract = File(_contractPath);
  for (final MapEntry(key: name, value: (section, index))
      in _fixtures.entries) {
    test(
      '$name.json equals contract §$section example ${index + 1} exactly',
      () {
        final example = _example(contract.readAsStringSync(), section, index);
        expect(example, isNotNull, reason: '§$section json example not found');
        expect(
          File('test/fixtures/$name.json').readAsStringSync(),
          example,
        );
      },
      skip: contract.existsSync() ? false : '$_contractPath not on this base',
    );
  }
}
