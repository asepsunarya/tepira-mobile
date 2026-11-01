import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/theme.dart';
import 'features/auth/auth_providers.dart';
import 'features/auth/login_screen.dart';
import 'features/goals/goals_screen.dart';

const String kLoginPath = '/login';
const String kHomePath = '/';

/// Where the router sends [location] for [auth], or null to stay.
/// Signed-out users only see `/login`; signed-in users never do. While the
/// stored session is still being read nothing moves.
String? authRedirect(AuthState auth, String location) {
  return switch (auth) {
    AuthUnknown() => null,
    AuthSignedOut() => location == kLoginPath ? null : kLoginPath,
    AuthSignedIn() => location == kLoginPath ? kHomePath : null,
  };
}

/// The app router. It re-runs [authRedirect] whenever [authStateProvider]
/// changes, so sign-in, sign-out and an expired session all navigate.
final routerProvider = Provider<GoRouter>((ref) {
  final auth = ValueNotifier<AuthState>(ref.read(authStateProvider));
  ref.listen<AuthState>(authStateProvider, (_, next) => auth.value = next);
  final router = GoRouter(
    initialLocation: kHomePath,
    refreshListenable: auth,
    redirect: (context, state) =>
        authRedirect(auth.value, state.matchedLocation),
    routes: [
      GoRoute(
        path: kHomePath,
        builder: (context, state) => const GoalsScreen(),
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
