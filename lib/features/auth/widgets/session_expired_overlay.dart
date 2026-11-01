import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/village_button.dart';
import '../../../core/widgets/village_card.dart';

/// Compact version of the first tab of the `SesiBerakhir` artboard, shown
/// over the Login screen after the API rejected the session (HTTP 401).
class SessionExpiredOverlay extends StatelessWidget {
  const SessionExpiredOverlay({super.key, required this.onSignInAgain});

  final VoidCallback onSignInAgain;

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    return ColoredBox(
      color: c.ink.withValues(alpha: 0.35),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Semantics(
              scopesRoute: true,
              namesRoute: true,
              explicitChildNodes: true,
              label: 'Sesi berakhir',
              // VillageCard is translucent; back it so the Login copy
              // underneath does not show through.
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: c.kartu,
                  borderRadius: BorderRadius.circular(VillageRadius.card),
                ),
                child: VillageCard(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: c.pinkSoft,
                          borderRadius: BorderRadius.circular(28),
                        ),
                        child: SizedBox.square(
                          dimension: 80,
                          child: Center(
                            child: SvgPicture.string(
                              _personIconSvg,
                              width: 40,
                              height: 40,
                              theme: SvgTheme(currentColor: c.pinkText),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const _StatusCode('HTTP 401'),
                      const SizedBox(height: 12),
                      Text(
                        'Sesi desamu sudah berakhir',
                        textAlign: TextAlign.center,
                        style: villageText(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: c.ink,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Masuk lagi dengan Google untuk melanjutkan.',
                        textAlign: TextAlign.center,
                        style: villageText(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: c.ink2,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: VillageButton(
                          label: 'Masuk lagi',
                          onPressed: onSignInAgain,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Person outline from the SesiBerakhir artboard, stroked in currentColor.
const String _personIconSvg = '''
<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" xmlns="http://www.w3.org/2000/svg">
<path d="M4 21a8 8 0 0 1 16 0M12 13a5 5 0 1 0 0-10 5 5 0 0 0 0 10z"/>
</svg>
''';

class _StatusCode extends StatelessWidget {
  const _StatusCode(this.code);

  final String code;

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.putih,
        border: Border.all(color: c.garis, width: 2),
        borderRadius: BorderRadius.circular(VillageRadius.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Text(
          code,
          style: villageText(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: c.redup,
          ),
        ),
      ),
    );
  }
}
