import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/core/categories.dart';

void main() {
  test('matches test/fixtures/categories.json (backend lib/categories.ts)', () {
    final fixture = jsonDecode(
      File('test/fixtures/categories.json').readAsStringSync(),
    ) as List<Object?>;

    expect(
      [
        for (final c in kExpenseCategories)
          {'key': c.key, 'label': c.label, 'group': c.group},
      ],
      fixture,
    );
  });

  test('labels are unique (the API identifies a category by label)', () {
    final labels = kExpenseCategories.map((c) => c.label).toList();

    expect(labels.toSet(), hasLength(labels.length));
  });

  group('categoryByLabel', () {
    test('finds a known label', () {
      expect(categoryByLabel('Makan harian')?.key, 'makan_harian');
    });

    test('is null for no category, a web key, or an unknown label', () {
      expect(categoryByLabel(null), isNull);
      expect(categoryByLabel('makan_harian'), isNull);
      expect(categoryByLabel('makan harian'), isNull);
    });
  });

  test('categoriesByGroup keeps list order', () {
    final groups = categoriesByGroup();

    expect(groups.keys, [
      'Kebutuhan wajib',
      'Kewajiban & rutin',
      'Hiburan & fleksibel',
    ]);
    expect(
      groups['Hiburan & fleksibel']!.map((c) => c.label),
      ['Nongkrong / jajan', 'Belanja kecil'],
    );
    expect(groups.values.expand((g) => g), hasLength(9));
  });
}
