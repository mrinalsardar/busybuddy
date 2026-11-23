import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';

/// Shown to a signed-in user whose device has no shop yet, until the first
/// sync has finished. The shop may already exist on the server (another
/// device, or an invite accepted earlier), so onboarding must not start yet.
class SyncingScreen extends ConsumerWidget {
  const SyncingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 24),
              Text('Loading your shop',
                  style: TextStyle(
                      fontSize: 24, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
              const SizedBox(height: 8),
              Text(
                'Downloading your data for the first time. This needs an internet connection.',
                style: TextStyle(fontSize: 15, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 24),
              TextButton(
                onPressed: () async {
                  try {
                    await ref.read(authRepositoryProvider).signOut();
                  } on AuthFailure catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('$e'), backgroundColor: AppTheme.error),
                      );
                    }
                  }
                },
                child: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
