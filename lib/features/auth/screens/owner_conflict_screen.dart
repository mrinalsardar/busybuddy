import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../sales/providers/sales_providers.dart';

/// Shown when a different account signed in while the previous account still
/// has changes that never uploaded (sales, stock). Nothing of the previous
/// account is shown, and nothing is deleted until the user confirms.
class OwnerConflictScreen extends ConsumerStatefulWidget {
  const OwnerConflictScreen({super.key});

  @override
  ConsumerState<OwnerConflictScreen> createState() => _OwnerConflictScreenState();
}

class _OwnerConflictScreenState extends ConsumerState<OwnerConflictScreen> {
  var _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    // The cart belongs to the previous account's shop.
    ref.read(cartProvider).clear();
    try {
      await action();
    } on AuthFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: context.colors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmDiscard() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard unsynced changes?'),
        content: const Text(
            'Sales and stock changes made on this device under the other account have not '
            'uploaded. Discarding deletes them for good.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Discard changes')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(ref.read(authRepositoryProvider).discardPendingChanges);
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(authRepositoryProvider);
    final previous = ref.watch(ownerConflictProvider)?.previousEmail;
    final account = previous ?? 'the previous account';
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Unsynced changes from another account',
                  style: TextStyle(
                      fontSize: 24, fontWeight: FontWeight.w700, color: context.colors.textPrimary)),
              const SizedBox(height: 8),
              Text(
                'This device holds changes made as $account that have not uploaded yet. '
                'Sign back in as that account while online so they can upload, or discard them.',
                style: TextStyle(fontSize: 15, color: context.colors.textSecondary),
              ),
              const SizedBox(height: 24),
              if (_busy)
                const Center(child: CircularProgressIndicator())
              else ...[
                ElevatedButton(
                  onPressed: () => _run(repo.leaveForPreviousAccount),
                  child: Text('Sign in as $account'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _confirmDiscard,
                  child: Text('Discard changes and continue', style: TextStyle(color: context.colors.error)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
