import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/errors.dart';
import '../../core/theme.dart';
import '../../core/widgets/pill.dart';
import '../../core/widgets/village_card.dart';
import '../../data/auth/google_id_token_source.dart';
import 'auth_providers.dart';
import 'widgets/login_art.dart';
import 'widgets/session_expired_overlay.dart';

/// `/login`, from the `Login` artboard: Google is the only way in.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _signIn() async {
    // Ignore taps while a sign-in runs (e.g. a double tap on "Masuk lagi").
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authStateProvider.notifier).signIn();
    } on AppException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Object {
      if (mounted) setState(() => _error = kGoogleSignInFailedMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _signInAgain() {
    if (_busy) return;
    ref.read(authStateProvider.notifier).dismissSessionExpired();
    _signIn();
  }

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    final sessionExpired = switch (ref.watch(authStateProvider)) {
      AuthSignedOut(:final sessionExpired) => sessionExpired,
      _ => false,
    };
    return Scaffold(
      body: Stack(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, 0.45, 1],
                colors: [c.langit, c.langitMuda, c.kertas],
              ),
            ),
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - 52,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _Intro(),
                        const SizedBox(height: 32),
                        _SignInSection(
                          busy: _busy,
                          error: _error,
                          onSignIn: _signIn,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (sessionExpired)
            Positioned.fill(
              child: SessionExpiredOverlay(onSignInAgain: _signInAgain),
            ),
        ],
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro();

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SvgPicture.string(
              kVillageLogoSvg,
              width: 44,
              height: 44,
              semanticsLabel: 'Logo tepira village',
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    text: 'tepira ',
                    style: villageText(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: c.ink,
                    ),
                    children: [
                      TextSpan(
                        text: 'village',
                        style: villageText(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: c.ink,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  'desa tabunganmu',
                  style: villageText(fontSize: 12, color: c.redup),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'Bangun desamu, satu setoran '),
              TextSpan(text: 'teu pira', style: TextStyle(color: c.cta)),
              const TextSpan(text: ' tiap hari.'),
            ],
          ),
          style: villageText(
            fontSize: 34,
            fontWeight: FontWeight.w900,
            color: c.ink,
            height: 1.15,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Tiap goal jadi bangunan yang tumbuh setiap kamu menyetor. '
          'Jajan tercatat di warung, dompet jadi peti harta.',
          style: villageText(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: c.ink2,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 24),
        const _SamplePlotCard(),
      ],
    );
  }
}

class _SamplePlotCard extends StatelessWidget {
  const _SamplePlotCard();

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    return ExcludeSemantics(
      child: VillageCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SvgPicture.string(
                kSamplePlotSvg,
                height: 120,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CONTOH KAVLING',
                        style: villageText(
                          fontSize: 11,
                          color: c.redup,
                          letterSpacing: 0.33,
                        ),
                      ),
                      Text(
                        'Dana darurat · tahap dinding',
                        style: villageText(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: c.ink,
                        ),
                      ),
                    ],
                  ),
                ),
                const Pill(label: '34%'),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: 0.34, minHeight: 8, color: c.mint),
          ],
        ),
      ),
    );
  }
}

class _SignInSection extends StatelessWidget {
  const _SignInSection({
    required this.busy,
    required this.error,
    required this.onSignIn,
  });

  final bool busy;
  final String? error;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    final message = error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (message != null) ...[
          _ErrorNote(message),
          const SizedBox(height: 12),
        ],
        _GoogleButton(busy: busy, onPressed: busy ? null : onSignIn),
        const SizedBox(height: 12),
        Text(
          'Akun dan datanya sama dengan tepira.id. '
          'Dengan masuk kamu menyetujui Ketentuan Layanan.',
          textAlign: TextAlign.center,
          style: villageText(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: c.ink2,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

class _ErrorNote extends StatelessWidget {
  const _ErrorNote(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    return Semantics(
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.merahSoft,
          border: Border.all(color: c.merahBorder, width: 2),
          borderRadius: BorderRadius.circular(VillageRadius.tile),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: villageText(fontSize: 13, color: c.merah, height: 1.4),
          ),
        ),
      ),
    );
  }
}

/// Primary pill button with the Google mark, as in the Login artboard.
class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.busy, required this.onPressed});

  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    final radius = BorderRadius.circular(VillageRadius.pill);
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: 'Masuk dengan Google',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [c.cta, c.ctaEnd],
          ),
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: c.ctaEnd.withValues(alpha: 0.7),
              offset: const Offset(0, 14),
              blurRadius: 26,
              spreadRadius: -12,
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: const Key('google-sign-in'),
            onTap: onPressed,
            borderRadius: radius,
            child: SizedBox(
              height: 56,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox.square(
                    dimension: 28,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: c.putih,
                        shape: BoxShape.circle,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(5),
                        child: busy
                            ? CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: c.cta,
                              )
                            : SvgPicture.string(kGoogleMarkSvg),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    busy ? 'Menghubungkan…' : 'Masuk dengan Google',
                    style: villageText(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: c.putih,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
