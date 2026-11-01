import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/core/widgets/pill.dart';
import 'package:tepira_mobile/core/widgets/stage_note.dart';
import 'package:tepira_mobile/core/widgets/stat_tile.dart';
import 'package:tepira_mobile/core/widgets/village_card.dart';
import 'package:tepira_mobile/core/widgets/village_chip.dart';

import 'village_test_app.dart';

void main() {
  testWidgets('renders a card with the shared village widgets', (
    tester,
  ) async {
    await pumpVillage(
      tester,
      const SizedBox(
        width: 300,
        child: VillageCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Kavling rumah'),
              SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: StatTile(label: 'Tabung', amount: 1250000)),
                  SizedBox(width: 6),
                  Expanded(
                    child: StatTile(
                      label: 'Jajan',
                      amount: 2180000,
                      tone: StatTone.spend,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: [
                  VillageChip(label: 'Rp20.000', selected: true),
                  VillageChip(label: 'Rp50.000'),
                ],
              ),
              SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: [
                  Pill(label: 'Aman', tone: PillTone.success),
                  Pill(label: 'Hampir', tone: PillTone.warning),
                  Pill(label: 'Lewat', tone: PillTone.danger),
                  Pill(label: 'Lv 5'),
                ],
              ),
              SizedBox(height: 8),
              StageNote(text: 'Tahap dinding. Setor Rp50.000 lagi ke atap.'),
            ],
          ),
        ),
      ),
    );

    await expectLater(
      find.byKey(goldenKey),
      matchesGoldenFile('goldens/village_card.png'),
    );
  });

  testWidgets('StatTile formats the amount as rupiah', (tester) async {
    await pumpVillage(
      tester,
      const StatTile(label: 'Tabung', amount: 1250000),
    );

    expect(find.text('TABUNG'), findsOneWidget);
    expect(find.text('Rp1.250.000'), findsOneWidget);
  });

  testWidgets('VillageChip reports taps and selection', (tester) async {
    final handle = tester.ensureSemantics();
    var taps = 0;
    await pumpVillage(
      tester,
      VillageChip(label: 'Rp20.000', selected: true, onTap: () => taps++),
    );

    await tester.tap(find.text('Rp20.000'));

    expect(taps, 1);
    expect(
      tester.getSemantics(find.text('Rp20.000')),
      matchesSemantics(
        label: 'Rp20.000',
        isButton: true,
        hasSelectedState: true,
        isSelected: true,
        hasTapAction: true,
        hasFocusAction: true,
        isFocusable: true,
      ),
    );
    handle.dispose();
  });
}
