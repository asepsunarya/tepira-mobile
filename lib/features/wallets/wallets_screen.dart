import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../core/widgets/village_button.dart';
import '../../core/widgets/village_card.dart';
import 'model/wallet.dart';
import 'wallet_providers.dart';
import 'widgets/wallet_row.dart';
import 'widgets/wallet_totals_header.dart';
import 'widgets/wallets_skeleton.dart';

/// Group titles of the Dompet list, in display order, as on the web.
const Map<WalletKind, String> kWalletGroupTitles = {
  WalletKind.normal: 'Saldo & Tabungan',
  WalletKind.reserved: 'Dana Dicadangkan',
  WalletKind.debt: 'Kartu Kredit & Cicilan',
};

/// The Dompet screen (`/wallets`, artboard Dompet): the totals head, then
/// the wallets in three groups (empty groups hidden), each wallet opening
/// its edit form. Pull down to reload.
class WalletsScreen extends ConsumerWidget {
  const WalletsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = VillageColors.of(context);
    final wallets = ref.watch(walletsProvider);
    final notifier = ref.read(walletsProvider.notifier);
    final data = wallets.valueOrNull;

    final Widget body;
    if (data != null && !wallets.hasError) {
      body = _Refreshable(
        onRefresh: notifier.refresh,
        children: [
          WalletTotalsHeader(totals: data.totals),
          const SizedBox(height: 12),
          if (data.wallets.isEmpty)
            const _EmptyWallets()
          else
            ..._groups(context, data.wallets),
        ],
      );
    } else if (wallets.hasError && !wallets.isLoading) {
      body = _Refreshable(
        onRefresh: notifier.refresh,
        children: [
          _LoadError(error: wallets.error!, onRetry: notifier.refresh),
        ],
      );
    } else {
      body = const WalletsSkeleton();
    }

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [c.langit, c.langitMuda, c.kertas],
            stops: const [0, 0.45, 1],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const _Header(),
              Expanded(child: body),
              if (data != null && data.wallets.isNotEmpty && !wallets.hasError)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: VillageButton(
                    key: const Key('add-wallet'),
                    label: 'Tambah dompet',
                    onPressed: () => context.push(WalletRoutes.create),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _groups(BuildContext context, List<Wallet> wallets) {
    return [
      for (final MapEntry(key: kind, value: title)
          in kWalletGroupTitles.entries)
        if (wallets.where((wallet) => wallet.kind == kind).toList()
            case final group when group.isNotEmpty) ...[
          _GroupTitle(title: title, count: group.length),
          for (final wallet in group) ...[
            WalletRow(
              key: ValueKey('wallet-${wallet.id}'),
              wallet: wallet,
              onTap: () => context.push(WalletRoutes.edit(wallet.id)),
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 6),
        ],
    ];
  }
}

/// Back button and the "Peti harta" title of artboard Dompet.
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => context.canPop() ? context.pop() : context.go('/'),
            icon: Icon(
              Icons.chevron_left_rounded,
              color: c.ink,
              semanticLabel: 'Kembali ke desa',
            ),
          ),
          Expanded(
            child: Text(
              'Peti harta',
              textAlign: TextAlign.center,
              style: villageText(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: c.ink,
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Semantics(
        header: true,
        child: Text(
          '${title.toUpperCase()} · $count',
          style: villageText(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            color: c.redup,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

/// Pull-to-refresh list that scrolls even when its content is short.
class _Refreshable extends StatelessWidget {
  const _Refreshable({required this.onRefresh, required this.children});

  final Future<void> Function() onRefresh;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        children: children,
      ),
    );
  }
}

/// No wallet yet: one call to action.
class _EmptyWallets extends StatelessWidget {
  const _EmptyWallets();

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    return VillageCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Buat dompet pertamamu',
            style: villageText(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Catat di mana uangmu disimpan: tunai, rekening, e-wallet, atau '
            'kartu kredit. Jajan nanti dicatat dari dompet ini.',
            style: villageText(fontSize: 13, color: c.redup, height: 1.4),
          ),
          const SizedBox(height: 16),
          VillageButton(
            key: const Key('add-first-wallet'),
            label: 'Tambah dompet',
            onPressed: () => context.push(WalletRoutes.create),
          ),
        ],
      ),
    );
  }
}

/// Load failure with a retry. 401 never lands here: the router already
/// moved to `/login`.
class _LoadError extends StatelessWidget {
  const _LoadError({required this.error, required this.onRetry});

  final Object error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    final title = switch (error) {
      NetworkException() => 'Peti harta sedang offline',
      ServerException() => 'Balai Desa sedang tutup',
      _ => 'Dompet belum bisa dimuat',
    };
    final message = switch (error) {
      AppException(:final message) => message,
      _ => 'Ada yang tidak beres. Coba lagi.',
    };
    return VillageCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: villageText(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(message, style: villageText(fontSize: 13, color: c.redup)),
          const SizedBox(height: 16),
          VillageButton(
            key: const Key('retry'),
            label: 'Coba lagi',
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}
