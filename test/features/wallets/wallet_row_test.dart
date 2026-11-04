import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/features/wallets/widgets/wallet_row.dart';

import '../../core/widgets/village_test_app.dart';
import '../../helpers/fake_wallets_repository.dart';

void main() {
  testWidgets('normal, reserved and debt rows match the golden',
      (tester) async {
    tester.view.physicalSize = const Size(390, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpVillage(
      tester,
      SizedBox(
        width: 358,
        child: Column(
          children: [
            WalletRow(
              wallet: testWallet(
                name: 'Tunai',
                type: 'cash',
                balance: 320000,
                spentThisMonth: 410000,
              ),
            ),
            const SizedBox(height: 8),
            WalletRow(
              wallet: testWallet(
                name: 'Tabungan Kurban',
                balance: 3000000,
                isReserved: true,
              ),
            ),
            const SizedBox(height: 8),
            WalletRow(
              wallet: testWallet(
                name: 'Kartu Kredit',
                type: 'credit',
                balance: 1250000,
                isDebt: true,
                spentThisMonth: 150000,
              ),
            ),
          ],
        ),
      ),
    );

    await expectLater(
      find.byKey(goldenKey),
      matchesGoldenFile('goldens/wallet_row.png'),
    );
  });

  testWidgets('reads as one button with name, type, spending and balance',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pumpVillage(
      tester,
      WalletRow(
        wallet: testWallet(
          name: 'Kartu Kredit',
          type: 'credit',
          balance: 1250000,
          isDebt: true,
          spentThisMonth: 150000,
        ),
        onTap: () {},
      ),
    );

    expect(
      find.bySemanticsLabel(
        'Kartu Kredit, Utang · Kartu kredit · jajan bulan ini Rp150.000, '
        'saldo -Rp1.250.000',
      ),
      findsOneWidget,
    );
    handle.dispose();
  });
}
