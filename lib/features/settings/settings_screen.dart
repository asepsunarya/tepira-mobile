import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/widgets/village_button.dart';
import '../../core/widgets/village_card.dart';
import '../../data/auth/auth_user.dart';

/// Shown when [SettingsScreen.onSignOut] fails, e.g. secure storage refuses
/// to delete the session.
const String kSignOutFailedMessage = 'Belum bisa keluar. Coba lagi.';

/// The minimal Pengaturan screen (`/settings`): who is signed in and a
/// confirmed "Keluar" button.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.user,
    required this.onSignOut,
  });

  final AuthUser user;

  /// Ends the session; the caller navigates to `/login` afterwards.
  final Future<void> Function() onSignOut;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _signingOut = false;

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => const _SignOutDialog(),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _signingOut = true);
    try {
      await widget.onSignOut();
    } on Object {
      if (!mounted) return;
      setState(() => _signingOut = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text(kSignOutFailedMessage)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    return Scaffold(
      backgroundColor: c.kertas,
      appBar: AppBar(title: const Text('Pengaturan')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _AccountCard(user: widget.user),
            const SizedBox(height: 24),
            VillageButton(
              key: const Key('sign-out'),
              label: 'Keluar',
              variant: VillageButtonVariant.danger,
              onPressed: _signingOut ? null : _confirmSignOut,
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.user});

  final AuthUser user;

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    final name = user.name?.trim();
    final shownName = name == null || name.isEmpty ? 'Warga desa' : name;
    final image = user.image;
    return VillageCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          ExcludeSemantics(
            child: CircleAvatar(
              radius: 28,
              backgroundColor: c.mintSoft,
              foregroundColor: c.mintText,
              foregroundImage: image == null ? null : NetworkImage(image),
              // Without this a failed photo load is reported as an error;
              // the initial underneath stays visible instead.
              onForegroundImageError: image == null ? null : (_, __) {},
              child: Text(
                shownName.characters.first.toUpperCase(),
                style: villageText(fontSize: 20, fontWeight: FontWeight.w900),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  shownName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: villageText(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: c.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  user.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: villageText(fontSize: 13, color: c.redup),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Asks before ending the session; pops `true` to sign out.
class _SignOutDialog extends StatelessWidget {
  const _SignOutDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Keluar dari desa?'),
      content: const Text(
        'Kamu perlu masuk dengan Google lagi untuk membuka desamu.',
      ),
      actions: [
        TextButton(
          key: const Key('cancel-sign-out'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Batal'),
        ),
        TextButton(
          key: const Key('confirm-sign-out'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Keluar'),
        ),
      ],
    );
  }
}
