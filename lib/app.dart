import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/routes.dart';
import 'core/theme.dart';
import 'features/auth/auth_providers.dart';
import 'features/auth/login_screen.dart';
import 'features/goals/goal_detail_screen.dart';
import 'features/goals/goals_screen.dart';
import 'features/settings/settings_screen.dart';

const String kLoginPath = '/login';
const String kHomePath = '/';

/// Query parameter of `/login` that remembers the page asked for.
const String kReturnToParam = 'from';

/// Where the router sends [location] for [auth], or null to stay.
/// Signed-out users only see `/login`, which remembers any page other than
/// `/` in [kReturnToParam]; after sign-in they go there, else to `/`. While
/// the stored session is still being read nothing moves.
String? authRedirect(AuthState auth, Uri location) {
  final onLogin = _isLoginPath(location.path);
  return switch (auth) {
    AuthUnknown() => null,
    AuthSignedOut() => onLogin ? null : _loginFor(location),
    AuthSignedIn() => onLogin ? _returnTarget(location) : null,
  };
}

String _loginFor(Uri location) {
  final target = location.toString();
  if (target == kHomePath) return kLoginPath;
  return Uri(path: kLoginPath, queryParameters: {kReturnToParam: target})
      .toString();
}

/// Whether [path] is the login page. go_router matches paths
/// case-insensitively, so `/LOGIN` is the login page too.
/// A single trailing slash (`/login/`) still names the login page.
bool _isLoginPath(String path) {
  final lower = path.toLowerCase();
  final trimmed = lower.length > 1 && lower.endsWith('/')
      ? lower.substring(0, lower.length - 1)
      : lower;
  return trimmed == kLoginPath;
}

/// The remembered page, accepted only as an in-app path.
///
/// Rejects anything that could leave the app: a scheme, an authority
/// (`//host`, or `/\host`, which [Uri.parse] reads as `//host`), any
/// backslash, whitespace or control character, and the login page itself.
/// The checks run on the parsed, dot-segment-normalised path, and that form
/// is what is returned, so `/..//host` cannot collapse into `//host`.
String _returnTarget(Uri login) {
  final target = login.queryParameters[kReturnToParam];
  if (target == null ||
      !target.startsWith('/') ||
      target.startsWith('//') ||
      target.contains(_unsafeTargetChars)) {
    return kHomePath;
  }
  final uri = Uri.tryParse(target);
  final inApp = uri != null &&
      !uri.hasScheme &&
      !uri.hasAuthority &&
      uri.path.startsWith('/') &&
      !uri.path.startsWith('//') &&
      !_isLoginPath(uri.path);
  return inApp ? uri.toString() : kHomePath;
}

/// Backslashes, whitespace and control characters (incl. DEL).
final RegExp _unsafeTargetChars = RegExp(r'[\\\s\x00-\x1F\x7F]');

/// The app router. It re-runs [authRedirect] whenever [authStateProvider]
/// changes, so sign-in, sign-out and an expired session all navigate.
final routerProvider = Provider<GoRouter>((ref) {
  final auth = ValueNotifier<AuthState>(ref.read(authStateProvider));
  ref.listen<AuthState>(authStateProvider, (_, next) => auth.value = next);
  final router = GoRouter(
    initialLocation: kHomePath,
    refreshListenable: auth,
    redirect: (context, state) => authRedirect(auth.value, state.uri),
    routes: [
      GoRoute(
        path: kHomePath,
        builder: (context, state) => const _Desa(),
      ),
      // Placeholders until T9 (new goal) and T10 (deposit).
      GoRoute(
        path: GoalRoutes.create,
        builder: (context, state) => const _ComingSoon(title: 'Bangun kavling'),
      ),
      GoRoute(
        path: GoalRoutes.detailPattern,
        builder: (context, state) => GoalDetailScreen(
          goalId: int.tryParse(state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: GoalRoutes.record,
        builder: (context, state) => const _ComingSoon(title: 'Catat'),
      ),
      GoRoute(
        path: kSettingsPath,
        builder: (context, state) => const _Settings(),
      ),
      GoRoute(
        path: kLoginPath,
        builder: (context, state) => const LoginScreen(),
      ),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    auth.dispose();
  });
  return router;
});

class TepiraApp extends ConsumerWidget {
  const TepiraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final restoring = ref.watch(authStateProvider) is AuthUnknown;
    return MaterialApp.router(
      title: 'tepira',
      theme: tepiraTheme,
      routerConfig: ref.watch(routerProvider),
      debugShowCheckedModeBanner: false,
      builder: (context, child) =>
          restoring ? const _RestoringSession() : child!,
    );
  }
}

/// The Desa screen with the signed-in user's name.
class _Desa extends ConsumerWidget {
  const _Desa();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);
    return GoalsScreen(
      userName: auth is AuthSignedIn ? auth.user.name : null,
    );
  }
}

/// Pengaturan for the signed-in user. Signing out lands on a plain
/// `/login`, so signing in again opens the Desa rather than Pengaturan.
class _Settings extends ConsumerWidget {
  const _Settings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);
    // Signed out, the router is already on its way to /login.
    if (auth is! AuthSignedIn) return const SizedBox.shrink();
    return SettingsScreen(
      user: auth.user,
      onSignOut: () async {
        // Read both before awaiting: this widget is gone once the state
        // flips to signed out.
        final controller = ref.read(authStateProvider.notifier);
        final router = ref.read(routerProvider);
        await controller.signOut();
        router.go(kLoginPath);
      },
    );
  }
}

/// Stand-in for a screen a later task builds.
class _ComingSoon extends StatelessWidget {
  const _ComingSoon({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: const Center(child: Text('Segera hadir')),
    );
  }
}

/// Shown for the moment the stored session is read from secure storage.
class _RestoringSession extends StatelessWidget {
  const _RestoringSession();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(semanticsLabel: 'Memuat sesi'),
      ),
    );
  }
}
