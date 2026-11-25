import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/db/database_helper.dart';
import '../../../core/models/business_profile.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_mode_provider.dart';
import '../../../core/utils/money.dart';
import '../../sales/providers/sales_providers.dart';
import '../providers/settings_providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _save(BuildContext context, WidgetRef ref, BusinessProfile updated) async {
    try {
      await ref.read(activeProfileProvider.notifier).updateProfile(updated);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save setting: $e'), backgroundColor: context.colors.error),
      );
    }
  }

  Future<void> _setThemeMode(BuildContext context, WidgetRef ref, ThemeMode mode) async {
    try {
      await ref.read(themeModeProvider.notifier).set(mode);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save setting: $e'), backgroundColor: context.colors.error),
      );
    }
  }

  void _showError(BuildContext context, Object e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$e'), backgroundColor: context.colors.error),
    );
  }

  Future<void> _invite(BuildContext context, WidgetRef ref, BusinessProfile profile) async {
    final String code;
    try {
      code = await ref.read(authRepositoryProvider).createInvite(profile.id);
    } on AuthFailure catch (e) {
      if (context.mounted) _showError(context, e);
      return;
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Staff invite code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(code,
                key: const Key('inviteCode'),
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: 3)),
            const SizedBox(height: 12),
            const Text('Give this code to your staff member. It works once and expires in 7 days. '
                'They sign in, choose "Have an invite code?" and enter it.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: code)),
            child: const Text('Copy'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
        ],
      ),
    );
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    // Signing out removes this device's copy of the shop, so changes that
    // have not uploaded yet would be lost.
    final pending = (await (await DatabaseHelper().database).getUploadQueueStats()).count;
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: Text(pending > 0
            ? '$pending changes on this device have not synced yet and will be lost. '
                'Connect to the internet and wait for them to sync first.'
            : 'This removes the shop data from this device. It stays in your shop online '
                'and comes back when you sign in again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(pending > 0 ? 'Sign out anyway' : 'Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    // The cart belongs to this shop and user.
    ref.read(cartProvider).clear();
    try {
      await ref.read(authRepositoryProvider).signOut();
    } on AuthFailure catch (e) {
      if (context.mounted) _showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(activeProfileProvider).value;
    final canEditCurrency = ref.watch(canEditCurrencyProvider).value ?? false;
    final isOwner = ref.watch(isOwnerProvider);
    final signedIn = ref.watch(authProvider) != null;
    if (profile == null) return const Scaffold();

    return Scaffold(
      appBar: AppBar(title: Text('Settings', style: TextStyle(fontWeight: FontWeight.w700))),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // A device preference, so staff can change it too: it sits above the
          // owner-only notice.
          _section(context, 'Appearance'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SegmentedButton<ThemeMode>(
              key: const Key('themeMode'),
              segments: const [
                ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                ButtonSegment(value: ThemeMode.system, label: Text('System')),
              ],
              selected: {ref.watch(themeModeProvider)},
              onSelectionChanged: (s) => _setThemeMode(context, ref, s.single),
            ),
          ),
          const SizedBox(height: 16),
          if (!isOwner)
            const ListTile(
              leading: Icon(Icons.lock_outline_rounded),
              title: Text('Only the shop owner can change these settings.'),
            ),
          _section(context, 'Selling'),
          SwitchListTile(
            title: const Text('Allow selling beyond stock'),
            subtitle: const Text(
                'On: stock can go negative. Off: a sale is blocked when stock runs out.'),
            value: profile.allowOversell,
            onChanged: isOwner
                ? (v) => _save(context, ref, profile.copyWith(allowOversell: v))
                : null,
          ),
          const SizedBox(height: 16),
          _section(context, 'Currency'),
          if (canEditCurrency && isOwner) ...[
            ListTile(
              title: const Text('Currency'),
              trailing: DropdownButton<String>(
                value: currencyDecimals.containsKey(profile.currency) ? profile.currency : null,
                hint: Text(profile.currency),
                items: [
                  for (final code in currencyDecimals.keys)
                    DropdownMenuItem(value: code, child: Text(code)),
                ],
                onChanged: (code) => _save(context, ref,
                    profile.copyWith(currency: code, currencyDecimals: currencyDecimals[code])),
              ),
            ),
            ListTile(
              title: const Text('Decimal places'),
              subtitle: const Text('Set from the currency. Change only if your shop prices differently.'),
              trailing: DropdownButton<int>(
                value: profile.currencyDecimals,
                items: [
                  for (var d = 0; d <= 3; d++) DropdownMenuItem(value: d, child: Text('$d')),
                ],
                onChanged: (d) => _save(context, ref, profile.copyWith(currencyDecimals: d)),
              ),
            ),
          ] else
            ListTile(
              title: Text('${profile.currency} · ${profile.currencyDecimals} decimal places'),
              subtitle: Text(isOwner
                  ? 'Locked once products or sales exist: changing it would change every stored amount.'
                  : 'Only the shop owner can change this.'),
              trailing: const Icon(Icons.lock_outline_rounded),
            ),
          if (signedIn) ...[
            const SizedBox(height: 16),
            if (isOwner) ...[
              _section(context, 'Staff'),
              ListTile(
                leading: const Icon(Icons.person_add_alt_1_rounded),
                title: const Text('Invite staff'),
                subtitle: const Text('Create a code a staff member enters to join this shop.'),
                onTap: () => _invite(context, ref, profile),
              ),
              const SizedBox(height: 16),
            ],
            _section(context, 'Account'),
            ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title: Text(ref.watch(authRepositoryProvider).email ?? 'Signed in'),
            ),
            ListTile(
              leading: const Icon(Icons.logout_rounded),
              title: const Text('Sign out'),
              onTap: () => _signOut(context, ref),
            ),
          ],
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: context.colors.textSecondary,
        ),
      ),
    );
  }
}
