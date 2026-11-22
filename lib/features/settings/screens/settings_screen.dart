import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/business_profile.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../providers/settings_providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _save(BuildContext context, WidgetRef ref, BusinessProfile updated) async {
    try {
      await ref.read(activeProfileProvider.notifier).updateProfile(updated);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save setting: $e'), backgroundColor: AppTheme.error),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(activeProfileProvider).valueOrNull;
    final canEditCurrency = ref.watch(canEditCurrencyProvider).valueOrNull ?? false;
    if (profile == null) return const Scaffold();

    return Scaffold(
      appBar: AppBar(title: Text('Settings', style: TextStyle(fontWeight: FontWeight.w700))),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _section('Selling'),
          SwitchListTile(
            title: const Text('Allow selling beyond stock'),
            subtitle: const Text(
                'On: stock can go negative. Off: a sale is blocked when stock runs out.'),
            value: profile.allowOversell,
            onChanged: (v) => _save(context, ref, profile.copyWith(allowOversell: v)),
          ),
          const SizedBox(height: 16),
          _section('Currency'),
          if (canEditCurrency) ...[
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
              subtitle: const Text(
                  'Locked once products or sales exist: changing it would change every stored amount.'),
              trailing: const Icon(Icons.lock_outline_rounded),
            ),
        ],
      ),
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: AppTheme.textSecondary,
        ),
      ),
    );
  }
}
