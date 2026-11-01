import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/features/goals/model/new_goal_input.dart';

void main() {
  group('titleError', () {
    test('rejects an empty or blank name', () {
      expect(NewGoalInput.titleError(''), 'Nama goal harus diisi.');
      expect(NewGoalInput.titleError('   '), 'Nama goal harus diisi.');
    });

    test('accepts up to 60 characters after trimming', () {
      expect(NewGoalInput.titleError('  ${'a' * 60}  '), isNull);
      expect(
        NewGoalInput.titleError('a' * 61),
        'Nama goal maksimal 60 karakter.',
      );
    });

    test('rejects control characters', () {
      expect(NewGoalInput.titleError('Dana\u0007'), isNotNull);
    });
  });

  group('target', () {
    test('parses grouped and plain digits', () {
      expect(NewGoalInput.parseTarget('1.500.000'), 1500000);
      expect(NewGoalInput.parseTarget('1500000'), 1500000);
    });

    test('does not parse negative, decimal or non-numeric text', () {
      for (final raw in ['-5000', '12,5', '1.5', 'abc', '1.50.000', '']) {
        expect(NewGoalInput.parseTarget(raw), isNull, reason: raw);
      }
    });

    test('requires a value', () {
      expect(NewGoalInput.targetError(''), 'Target harus diisi.');
    });

    test('rejects 0, negative and non-numeric targets', () {
      for (final raw in ['0', '-5000', 'abc', '12,5']) {
        expect(
          NewGoalInput.targetError(raw),
          'Target harus berupa angka bulat lebih dari 0.',
          reason: raw,
        );
      }
    });

    test('accepts 1 to the int32 maximum', () {
      expect(NewGoalInput.targetError('1'), isNull);
      expect(NewGoalInput.targetError('2.147.483.647'), isNull);
      expect(
        NewGoalInput.targetError('2.147.483.648'),
        'Target terlalu besar.',
      );
    });
  });

  group('description', () {
    test('is optional and at most 200 characters', () {
      expect(NewGoalInput.descriptionError(''), isNull);
      expect(NewGoalInput.descriptionError('a' * 200), isNull);
      expect(
        NewGoalInput.descriptionError('a' * 201),
        'Deskripsi maksimal 200 karakter.',
      );
    });

    test('blank becomes null, text is trimmed', () {
      expect(NewGoalInput.description('   '), isNull);
      expect(NewGoalInput.description(' Untuk konten '), 'Untuk konten');
    });
  });
}
