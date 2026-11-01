import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/core/widgets/village_button.dart';

import 'village_test_app.dart';

void main() {
  testWidgets('renders every variant and the disabled state', (tester) async {
    await pumpVillage(
      tester,
      SizedBox(
        width: 280,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final variant in VillageButtonVariant.values) ...[
              VillageButton(
                label: variant.name,
                variant: variant,
                onPressed: () {},
              ),
              const SizedBox(height: 10),
            ],
            const VillageButton(label: 'Nonaktif', onPressed: null),
          ],
        ),
      ),
    );

    await expectLater(
      find.byKey(goldenKey),
      matchesGoldenFile('goldens/village_button.png'),
    );
  });

  testWidgets('calls onPressed when tapped', (tester) async {
    var taps = 0;
    await pumpVillage(
      tester,
      VillageButton(label: 'Setor', onPressed: () => taps++),
    );

    await tester.tap(find.text('Setor'));

    expect(taps, 1);
  });

  testWidgets('is exposed as a disabled button when onPressed is null', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpVillage(
      tester,
      const VillageButton(label: 'Setor', onPressed: null),
    );

    expect(
      tester.getSemantics(find.text('Setor')),
      matchesSemantics(
        label: 'Setor',
        isButton: true,
        hasEnabledState: true,
        isEnabled: false,
      ),
    );
    handle.dispose();
  });
}
