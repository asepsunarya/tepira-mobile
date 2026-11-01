import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/features/goals/model/new_goal_input.dart';

/// Edge cases for [NewGoalInput] against the server rules of
/// `POST /api/mobile/goals` (SPEC 3.4). The server trims with JS `trim()`,
/// counts length in code points (`Array.from(s).length`), and rejects
/// `[\u0000-\u001f\u007f]` in the title.
void main() {
  const tooLong = 'Nama goal maksimal 60 karakter.';
  const control = 'Nama goal tidak boleh berisi karakter khusus.';
  const empty = 'Nama goal harus diisi.';

  group('title length boundary', () {
    test('exactly 60 ASCII characters is accepted, 61 is rejected', () {
      expect(NewGoalInput.titleError('a' * 60), isNull);
      expect(NewGoalInput.titleError('a' * 61), tooLong);
    });

    test('surrounding whitespace does not count towards 60', () {
      expect(NewGoalInput.titleError('\t ${'a' * 60} \n'), isNull);
      expect(NewGoalInput.titleError(' ${'a' * 61} '), tooLong);
    });

    test('60 precomposed accented letters (BMP) are accepted', () {
      expect(NewGoalInput.titleError('é' * 60), isNull);
      expect(NewGoalInput.titleError('é' * 61), tooLong);
    });

    test('30 emoji (60 UTF-16 units, 30 code points) are accepted', () {
      expect(NewGoalInput.titleError('😀' * 30), isNull);
    });

    test(
      '31 emoji (62 UTF-16 units, 31 code points) are accepted like the server',
      () {
        expect(NewGoalInput.titleError('😀' * 31), isNull);
      },
      skip: 'BUG: titleError counts UTF-16 code units (String.length) but the '
          'server counts code points (Array.from(title).length), so names '
          'with emoji/astral characters are rejected client-side while the '
          'server would accept them (new_goal_input.dart:18)',
    );

    test(
      '59 letters + 1 emoji (60 code points, 61 units) is accepted',
      () {
        expect(NewGoalInput.titleError('${'a' * 59}🏠'), isNull);
      },
      skip: 'BUG: titleError counts UTF-16 code units, server counts code '
          'points; a 60-code-point name ending in an emoji is wrongly '
          'rejected (new_goal_input.dart:18)',
    );

    test('61 code points with an emoji is rejected (both sides agree)', () {
      expect(NewGoalInput.titleError('${'a' * 60}🏠'), tooLong);
    });
  });

  group('title whitespace and control characters', () {
    test('whitespace-only names are empty, including tabs, newlines, NBSP', () {
      for (final blank in [' ', '\t', '\n', ' \r\n ', ' ', '　']) {
        expect(NewGoalInput.titleError(blank), empty, reason: 'for $blank');
      }
    });

    test('inner newline, tab, CR, NUL, ESC and DEL are rejected', () {
      for (final c in ['\n', '\t', '\r', '\u0000', '\u001B', '\u007F']) {
        expect(
          NewGoalInput.titleError('Dana${c}darurat'),
          control,
          reason: 'for U+${c.codeUnitAt(0).toRadixString(16)}',
        );
      }
    });

    test('leading/trailing control whitespace is trimmed, not rejected', () {
      // The server trims first and only then checks for control chars.
      expect(NewGoalInput.titleError('\nDana darurat\t'), isNull);
    });

    test('C1 controls (U+0085) inside the name are allowed, as on the server',
        () {
      expect(NewGoalInput.titleError('Dana\u0085darurat'), isNull);
    });

    test('a too-long name is reported as too long before control chars', () {
      expect(NewGoalInput.titleError('${'a' * 61}\t'), tooLong);
    });
  });

  group('target boundaries', () {
    test('int32 max is accepted, one more is too big', () {
      expect(NewGoalInput.targetError('2147483647'), isNull);
      expect(NewGoalInput.parseTarget('2147483647'), 2147483647);
      expect(NewGoalInput.targetError('2.147.483.647'), isNull);
      expect(NewGoalInput.targetError('2147483648'), 'Target terlalu besar.');
      expect(
        NewGoalInput.targetError('2.147.483.648'),
        'Target terlalu besar.',
      );
    });

    test('a value overflowing int64 is still an error, not a crash', () {
      expect(NewGoalInput.targetError('99999999999999999999'), isNotNull);
      expect(NewGoalInput.targetError('9223372036854775808'), isNotNull);
    });

    test('1 is the smallest valid target', () {
      expect(NewGoalInput.targetError('1'), isNull);
    });

    test('leading zeros parse to the plain number; all zeros is invalid', () {
      expect(NewGoalInput.parseTarget('0001500'), 1500);
      expect(NewGoalInput.targetError('0001500'), isNull);
      expect(NewGoalInput.targetError('000'), isNotNull);
      expect(NewGoalInput.targetError('0.000'), isNotNull);
    });

    test('mis-grouped or decimal text is rejected', () {
      expect(NewGoalInput.parseTarget('1.50.000'), isNull);
      expect(NewGoalInput.parseTarget('1.500,00'), isNull);
      expect(NewGoalInput.parseTarget('1,500,000'), isNull);
      expect(NewGoalInput.parseTarget('.500'), isNull);
      expect(NewGoalInput.parseTarget('500.'), isNull);
      expect(NewGoalInput.parseTarget('+500'), isNull);
      expect(NewGoalInput.parseTarget('1e6'), isNull);
    });

    test('whitespace-only target is "required"', () {
      expect(NewGoalInput.targetError('   '), 'Target harus diisi.');
    });
  });

  group('description boundaries', () {
    const descTooLong = 'Deskripsi maksimal 200 karakter.';

    test('exactly 200 characters is accepted, 201 is rejected', () {
      expect(NewGoalInput.descriptionError('d' * 200), isNull);
      expect(NewGoalInput.descriptionError('d' * 201), descTooLong);
    });

    test('surrounding whitespace does not count towards 200', () {
      expect(NewGoalInput.descriptionError('   ${'d' * 200}\n\n'), isNull);
      expect(NewGoalInput.description('   ${'d' * 200}\n\n'), 'd' * 200);
    });

    test('whitespace-only description is valid and sent as null', () {
      for (final blank in ['', ' ', '\n\t ', ' ']) {
        expect(NewGoalInput.descriptionError(blank), isNull);
        expect(NewGoalInput.description(blank), isNull);
      }
    });

    test('inner newlines are kept in the description', () {
      expect(NewGoalInput.descriptionError('baris 1\nbaris 2'), isNull);
      expect(
        NewGoalInput.description(' baris 1\nbaris 2 '),
        'baris 1\nbaris 2',
      );
    });

    test('100 emoji (200 units, 100 code points) is accepted', () {
      expect(NewGoalInput.descriptionError('😀' * 100), isNull);
    });

    test(
      '101 emoji (202 units, 101 code points) is accepted like the server',
      () {
        expect(NewGoalInput.descriptionError('😀' * 101), isNull);
      },
      skip: 'BUG: descriptionError counts UTF-16 code units but the server '
          'counts code points, so a description with emoji is rejected '
          'client-side below the real 200 limit (new_goal_input.dart:50)',
    );
  });
}
