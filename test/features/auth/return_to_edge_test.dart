import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/app.dart';
import 'package:tepira_mobile/features/auth/auth_providers.dart';

import '../../helpers/fake_auth_repository.dart';

/// Independent edge cases for the `?from=` return-to target (T7, c38ff2d).
void main() {
  String? afterSignIn(String rawLoginLocation) => authRedirect(
        const AuthSignedIn(testUser),
        Uri.parse(rawLoginLocation),
      );

  String? afterSignInWithFrom(String from) => authRedirect(
        const AuthSignedIn(testUser),
        Uri(path: kLoginPath, queryParameters: {kReturnToParam: from}),
      );

  group('off-site targets land on /', () {
    for (final from in [
      '//evil.com',
      '///evil.com',
      'https://evil.com',
      'http://evil.com/goal/1',
      'HTTPS://evil.com',
      'javascript:alert(1)',
      'JavaScript:alert(1)',
      'data:text/html,<script>alert(1)</script>',
      'evil.com',
      ' /goal/1',
      '%2F%2Fevil.com',
      '%252F%252Fevil.com',
    ]) {
      test('from=$from', () {
        expect(afterSignInWithFrom(from), kHomePath, reason: from);
      });
    }

    test('percent-encoded //evil.com in the raw URL is decoded and rejected',
        () {
      expect(afterSignIn('/login?from=%2F%2Fevil.com'), kHomePath);
      expect(afterSignIn('/login?from=%2f%2fevil.com'), kHomePath);
      expect(afterSignIn('/login?from=//evil.com'), kHomePath);
    });

    test('double-encoded //evil.com stays rejected', () {
      expect(afterSignIn('/login?from=%252F%252Fevil.com'), kHomePath);
    });

    test('repeated from params cannot smuggle an off-site target', () {
      // Uri.queryParameters keeps the last value.
      expect(afterSignIn('/login?from=/goal/1&from=//evil.com'), kHomePath);
    });
  });

  group('backslash targets', () {
    test(r'Dart parses /\evil.com as host evil.com (why this matters)', () {
      final uri = Uri.parse(r'/\evil.com');
      expect(uri.host, 'evil.com');
      expect(uri.toString(), '//evil.com');
    });

    for (final from in [r'/\evil.com', r'/\/evil.com', r'/\\evil.com']) {
      test(
        'from=$from goes to /',
        () => expect(afterSignInWithFrom(from), kHomePath),
        skip: 'BUG: _returnTarget only checks startsWith("/") and not '
            'startsWith("//"), so "$from" is returned as the redirect. Dart '
            r'Uri.parse treats "\" like "/", so it becomes "//evil.com" '
            '(authority evil.com, empty path). In the app, go_router then '
            'throws an assertion (match.dart: uri.path.startsWith('
            'newMatchedLocation)) and the user stays stuck on /login; in a '
            'browser it is the classic open-redirect pattern. Fix: reject '
            r'any "\", or require Uri.parse(target) to have no scheme and '
            'no authority.',
      );
    }

    test('an encoded backslash stays a literal (not-found) path', () {
      // Not off-site: Uri keeps %5C encoded, so it is only an unknown page.
      expect(Uri.parse('/%5Cevil.com').hasAuthority, isFalse);
    });
  });

  group('case and trailing-slash variants of /login', () {
    test(
      'from=/LOGIN goes to /',
      () => expect(afterSignInWithFrom('/LOGIN'), kHomePath),
      skip: 'BUG (minor): "/LOGIN" is returned. go_router matches routes '
          'case-insensitively, so a signed-in user lands on LoginScreen '
          'again; authRedirect compares path == "/login" exactly, so it '
          'never moves them on. Same for a signed-in user opening /LOGIN '
          'directly. Fix: compare paths case-insensitively.',
    );

    test(
      'signed-in on /LOGIN is moved off the login page',
      () => expect(
        authRedirect(const AuthSignedIn(testUser), Uri.parse('/LOGIN')),
        isNotNull,
      ),
      skip: 'BUG (minor): see from=/LOGIN; returns null so LoginScreen '
          'stays up for a signed-in user.',
    );
  });

  group('login loops are broken', () {
    for (final from in [
      '/login',
      '/login?from=/login',
      '/login?from=%2Flogin%3Ffrom%3D%252Flogin',
      '/login#x',
      '/login?from=%2F%2Fevil.com',
    ]) {
      test('from=$from goes to /', () {
        expect(afterSignInWithFrom(from), kHomePath);
      });
    }

    test('nested raw /login?from=/login?from=/login goes to /', () {
      expect(afterSignIn('/login?from=/login?from=/login'), kHomePath);
    });

    test('a target that resolves to /login via dot segments goes to /', () {
      // Uri.parse normalises "/x/../login" to "/login".
      expect(afterSignInWithFrom('/x/../login'), kHomePath);
    });
  });

  group('safe in-app targets are kept', () {
    test('a plain page and a page with an encoded query string', () {
      expect(afterSignInWithFrom('/goal/1'), '/goal/1');
      expect(
        afterSignInWithFrom('/record?goal=3&note=a%20b'),
        '/record?goal=3&note=a%20b',
      );
      expect(
        afterSignIn('/login?from=%2Frecord%3Fgoal%3D3%26x%3D%252F%252Fevil'),
        '/record?goal=3&x=%2F%2Fevil',
      );
    });

    test('the root itself', () {
      expect(afterSignInWithFrom('/'), kHomePath);
    });

    test('a very long in-app value is returned unchanged (no crash)', () {
      final long = '/goal/1?x=${'a' * 20000}';
      expect(afterSignInWithFrom(long), long);
    });

    test('a very long off-site value still lands on /', () {
      expect(afterSignInWithFrom('//${'e' * 20000}.com'), kHomePath);
      expect(afterSignInWithFrom('https://${'e' * 20000}.com'), kHomePath);
    });
  });

  group('round trip through signed-out redirect', () {
    for (final page in [
      '/goal/7',
      '/record?goal=3&note=a%20b',
      '/goal/new',
    ]) {
      test(page, () {
        final login = authRedirect(const AuthSignedOut(), Uri.parse(page))!;
        expect(Uri.parse(login).path, kLoginPath);
        expect(afterSignIn(login), page);
      });
    }

    test('signed-out with a hostile query keeps it inside from, then rejects',
        () {
      final login = authRedirect(
        const AuthSignedOut(),
        Uri.parse('/goal/1?next=//evil.com'),
      )!;
      // The whole page incl. its query is the target; still in-app.
      expect(afterSignIn(login), '/goal/1?next=//evil.com');
    });
  });
}
