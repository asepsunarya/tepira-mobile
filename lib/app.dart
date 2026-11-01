import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/routes.dart';
import 'core/theme.dart';
import 'features/auth/auth_providers.dart';
import 'features/auth/login_screen.dart';
import 'features/goals/goals_screen.dart';

const String kLoginPath = '/login';
const String kHomePath = '/';

/// Query parameter of `/login` that remembers the page asked for.
const String kReturnToParam = 'from';

/// Where the router sends [location] for [auth], or null to stay.
/// Signed-out users only see `/login`, which remembers any page other than
/// `/` in [kReturnToParam]; after sign-in they go there, else to `/`. While
/// the stored session is still being read nothing moves.
String? authRedirect(AuthState auth, Uri location) {
  final onLogin = location.path == kLoginPath;
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

/// The remembered page, accepted only as an in-app path.
String _returnTarget(Uri login) {
  final target = login.queryParameters[kReturnToParam];
  final inApp = target != null &&
      target.startsWith('/') &&
      !target.startsWith('//') &&
      Uri.tryParse(target)?.path != kLoginPath;
  return inApp ? target : kHomePath;
}

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
      // Placeholders until T8 (detail), T9 (new goal) and T10 (deposit).
      GoRoute(
        path: GoalRoutes.create,
        builder: (context, state) => const _ComingSoon(title: 'Bangun kavling'),
      ),
      GoRoute(
        path: GoalRoutes.detailPattern,
        builder: (context, state) => const _ComingSoon(title: 'Kavling'),
      ),
      GoRoute(
        path: GoalRoutes.record,
        builder: (context, state) => const _ComingSoon(title: 'Catat'),
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
