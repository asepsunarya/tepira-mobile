import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/routes.dart';
import '../../core/theme.dart';

/// The pages the dock switches between. Catat is a button, not a page: it
/// opens the Jajan form on top.
enum DockTab {
  desa('/'),
  riwayat(kHistoryPath),
  dompet(WalletRoutes.list);

  const DockTab(this.path);

  final String path;

  /// The tab showing [path], or null for a page outside the dock. Like
  /// go_router, it ignores letter case and one trailing slash.
  static DockTab? forPath(String path) {
    final lower = path.toLowerCase();
    final trimmed = lower.length > 1 && lower.endsWith('/')
        ? lower.substring(0, lower.length - 1)
        : lower;
    for (final tab in values) {
      if (tab.path == trimmed) return tab;
    }
    return null;
  }
}

/// Wraps the dock pages (Desa, Riwayat, Dompet) with the [AppDock] below
/// them. [location] is the router's current path.
class DockShell extends StatelessWidget {
  const DockShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    return ColoredBox(
      color: c.kertas,
      child: Column(
        children: [
          Expanded(
            // The dock sits under the page and takes the bottom inset.
            child: MediaQuery.removePadding(
              context: context,
              removeBottom: true,
              child: child,
            ),
          ),
          SafeArea(
            top: false,
            child: AppDock(current: DockTab.forPath(location)),
          ),
        ],
      ),
    );
  }
}

/// Bottom dock of artboard Main with the v2 tabs (SPEC-v2 §4 Navigasi):
/// Desa, Riwayat, Catat in the middle, and Dompet. The other artboard tabs
/// (Laporan, Jurnal) have no screen yet and stay hidden. Tabs replace the
/// page; Catat opens the Jajan tab on top, so a quick expense still takes
/// three taps.
class AppDock extends StatelessWidget {
  const AppDock({super.key, required this.current});

  /// The highlighted tab, or null when none is.
  final DockTab? current;

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    Widget tab(DockTab tab, IconData icon, String label) => _DockTile(
          key: Key('dock-${tab.name}'),
          icon: icon,
          label: label,
          selected: current == tab,
          onTap: current == tab ? null : () => context.go(tab.path),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 4),
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        label: 'Dock desa',
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.kartu.withValues(alpha: 0.88),
            border: Border.all(color: c.putih, width: 2),
            borderRadius: BorderRadius.circular(VillageRadius.card),
            boxShadow: [
              BoxShadow(
                color: c.shadow,
                offset: const Offset(0, 10),
                blurRadius: 30,
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                tab(DockTab.desa, Icons.cottage_rounded, 'Desa'),
                const SizedBox(width: 6),
                tab(DockTab.riwayat, Icons.schedule_rounded, 'Riwayat'),
                const SizedBox(width: 6),
                _DockTile(
                  key: const Key('dock-catat'),
                  icon: Icons.edit_note_rounded,
                  label: 'Catat',
                  onTap: () => context.push(ExpenseRoutes.record),
                ),
                const SizedBox(width: 6),
                tab(
                  DockTab.dompet,
                  Icons.account_balance_wallet_rounded,
                  'Dompet',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DockTile extends StatelessWidget {
  const _DockTile({
    super.key,
    required this.icon,
    required this.label,
    this.selected = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    final foreground = selected ? c.pinkText : c.redup;
    final radius = BorderRadius.circular(18);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? c.pinkSoft : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: selected
              ? BorderSide(color: c.pink.withValues(alpha: 0.4), width: 2)
              : BorderSide.none,
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: SizedBox.square(
            dimension: 62,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 24, color: foreground),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: villageText(fontSize: 10, color: foreground),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
