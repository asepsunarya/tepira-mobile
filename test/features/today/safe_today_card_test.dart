import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/core/theme.dart';
import 'package:tepira_mobile/features/today/model/today_summary.dart';
import 'package:tepira_mobile/features/today/widgets/safe_today_card.dart';

import '../../core/widgets/village_test_app.dart';
import '../../helpers/fake_today_repository.dart';

Future<void> _pump(WidgetTester tester, TodaySummary summary) async {
  tester.view.physicalSize = const Size(390, 400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await pumpVillage(
    tester,
    SizedBox(width: 358, child: SafeTodayCard(summary: summary)),
  );
}

/// Every text in the card, joined.
String _cardText(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byKey(const Key('safe-today')),
        matching: find.byType(Text),
      ),
    )
    .map((t) => t.data)
    .join(' | ');

void main() {
  testWidgets('budget basis: the server remaining and the daily allowance',
      (tester) async {
    await _pump(tester, fixtureTodayBudget());

    expect(find.text('AMAN DIPAKAI HARI INI'), findsOneWidget);
    expect(find.text('Rp100.000'), findsOneWidget);
    expect(
      find.text('Jatah Rp150.000/hari dari anggaran bulan ini'),
      findsOneWidget,
    );
  });

  testWidgets('wallet basis: Uang bebas over 30 days, budget not set',
      (tester) async {
    await _pump(tester, fixtureTodayWallet());

    expect(find.text('AMAN DIPAKAI HARI INI'), findsOneWidget);
    expect(find.text('Rp201.833'), findsOneWidget);
    expect(
      find.text(
        'Dari uang bebas dibagi 30 hari '
        '(anggaran bulan ini belum diatur di web)',
      ),
      findsOneWidget,
    );
  });

  testWidgets('remaining 0 -> "Jatah hari ini sudah habis"', (tester) async {
    await _pump(tester, testToday(remaining: 0, allowance: 150000));

    expect(find.text('Rp0'), findsOneWidget);
    expect(find.text('Jatah hari ini sudah habis'), findsOneWidget);
  });

  testWidgets('over_today: "Lewat Rp20.000 hari ini" in red', (tester) async {
    await _pump(
      tester,
      testToday(state: SafeTodayState.overToday, remaining: -20000),
    );

    final finder = find.byKey(const Key('safe-today-amount'));
    final amount = tester.widget<Text>(finder);
    expect(amount.data, 'Lewat Rp20.000 hari ini');
    expect(
      amount.style!.color,
      VillageColors.of(tester.element(finder)).merah,
    );
    expect(
      find.text('Jatah Rp150.000/hari dari anggaran bulan ini'),
      findsOneWidget,
    );
  });

  testWidgets('over_month: "Anggaran bulan ini sudah lewat", never "aman"',
      (tester) async {
    await _pump(
      tester,
      testToday(
        state: SafeTodayState.overMonth,
        allowance: 0,
        remaining: -120000,
        spentMonth: 4620000,
      ),
    );

    expect(find.text('ANGGARAN BULAN INI SUDAH LEWAT'), findsOneWidget);
    expect(find.text('Rp120.000'), findsOneWidget);
    expect(_cardText(tester).toLowerCase(), isNot(contains('aman')));
    expect(
      tester.getSemantics(find.byKey(const Key('safe-today'))).label,
      'Anggaran bulan ini sudah lewat, Rp120.000',
    );
  });

  testWidgets('over_month on the wallet basis never says "aman" either',
      (tester) async {
    await _pump(
      tester,
      testToday(
        basis: SafeTodayBasis.wallet,
        state: SafeTodayState.overMonth,
        status: BudgetStatus.overBudget,
        remaining: -5000,
      ),
    );

    expect(_cardText(tester).toLowerCase(), isNot(contains('aman')));
  });

  testWidgets('ok, over_today and over_month match the golden', (tester) async {
    tester.view.physicalSize = const Size(390, 520);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpVillage(
      tester,
      SizedBox(
        width: 358,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SafeTodayCard(summary: fixtureTodayBudget()),
            const SizedBox(height: 8),
            SafeTodayCard(
              summary: testToday(
                state: SafeTodayState.overToday,
                remaining: -20000,
              ),
            ),
            const SizedBox(height: 8),
            SafeTodayCard(
              summary: testToday(
                state: SafeTodayState.overMonth,
                allowance: 0,
                remaining: -120000,
              ),
            ),
          ],
        ),
      ),
    );

    await expectLater(
      find.byKey(goldenKey),
      matchesGoldenFile('goldens/safe_today_card.png'),
    );
  });
}
