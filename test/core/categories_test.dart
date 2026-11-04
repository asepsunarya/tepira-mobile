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

  test('categories.json holds the nine web categories (tepira 206408b)', () {
    final fixture = jsonDecode(
      File('test/fixtures/categories.json').readAsStringSync(),
    ) as List<Object?>;

    expect(fixture, [
      {
        'key': 'makan_harian',
        'label': 'Makan harian',
        'group': 'Kebutuhan wajib',
      },
      {'key': 'transport', 'label': 'Transport', 'group': 'Kebutuhan wajib'},
      {
        'key': 'pulsa_internet',
        'label': 'Pulsa & Internet',
        'group': 'Kebutuhan wajib',
      },
      {
        'key': 'listrik_kos',
        'label': 'Listrik / Air / Kos',
        'group': 'Kebutuhan wajib',
      },
      {
        'key': 'langganan',
        'label': 'Langganan (Spotify, Netflix, dll)',
        'group': 'Kewajiban & rutin',
      },
      {
        'key': 'kesehatan',
        'label': 'Kesehatan / Obat',
        'group': 'Kewajiban & rutin',
      },
      {
        'key': 'sosial',
        'label': 'Sosial (sedekah / bantu keluarga)',
        'group': 'Kewajiban & rutin',
      },
      {
        'key': 'nongkrong',
        'label': 'Nongkrong / jajan',
        'group': 'Hiburan & fleksibel',
      },
      {
        'key': 'belanja_kecil',
        'label': 'Belanja kecil',
        'group': 'Hiburan & fleksibel',
      },
    ]);
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

  group('categoryLabelOf', () {
    test('keeps a known label, null, and an unknown value', () {
      expect(categoryLabelOf('Transport'), 'Transport');
      expect(categoryLabelOf(null), isNull);
      expect(categoryLabelOf('Lain-lain'), 'Lain-lain');
    });

    test('maps every web key to its label', () {
      for (final c in kExpenseCategories) {
        expect(categoryLabelOf(c.key), c.label);
      }
    });

    test('matches keys exactly: no trimming or case folding', () {
      expect(categoryLabelOf(''), '');
      expect(categoryLabelOf('TRANSPORT'), 'TRANSPORT');
      expect(categoryLabelOf(' transport'), ' transport');
      expect(categoryLabelOf('transport '), 'transport ');
    });

    test('no web key equals a label, so the mapping is unambiguous', () {
      final labels = kExpenseCategories.map((c) => c.label).toSet();
      for (final c in kExpenseCategories) {
        expect(labels.contains(c.key), isFalse, reason: c.key);
      }
    });

    test('is idempotent', () {
      for (final c in kExpenseCategories) {
        expect(categoryLabelOf(categoryLabelOf(c.key)), c.label);
      }
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
