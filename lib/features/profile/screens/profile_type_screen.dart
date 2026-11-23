import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/business_profile.dart';

/// First onboarding screen — choose your business type.
class ProfileTypeScreen extends ConsumerWidget {
  const ProfileTypeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(authProvider) != null;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 48),
              // Animated header
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeOutCubic,
                builder: (_, value, child) => Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, 20 * (1 - value)),
                    child: child,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryPurple.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                      ),
                      child: Text(
                        'WELCOME TO BUSYBUDDY',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                          color: AppTheme.primaryPurple,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'What type of\nbusiness do\nyou run?',
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'This permanently configures your app features.',
                      style: TextStyle(
                        fontWeight: FontWeight.w400,
                        fontSize: 15,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              // Type cards
              Expanded(
                child: GridView.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 1.05,
                  children: BusinessType.values.map((type) {
                    return _BusinessTypeCard(
                      type: type,
                      onTap: () => context.go('/onboarding/details/${type.name}'),
                    );
                  }).toList(),
                ),
              ),
              // Only with a backend account: staff join a shop that exists.
              if (signedIn)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () => context.go('/onboarding/join'),
                      child: const Text('Have an invite code?'),
                    ),
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
            ],
          ),
        ),
      ),
    );
  }
}

class _BusinessTypeCard extends StatefulWidget {
  final BusinessType type;
  final VoidCallback onTap;

  const _BusinessTypeCard({required this.type, required this.onTap});

  @override
  State<_BusinessTypeCard> createState() => _BusinessTypeCardState();
}

class _BusinessTypeCardState extends State<_BusinessTypeCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnim = Tween<double>(begin: 1, end: 0.95).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color get _cardGradientStart {
    switch (widget.type) {
      case BusinessType.shoes:
        return const Color(0xFF6C63FF);
      case BusinessType.fashion:
        return const Color(0xFFE84393);
      case BusinessType.grocery:
        return const Color(0xFF00B894);
      case BusinessType.general:
        return const Color(0xFFFFB347);
    }
  }

  Color get _cardGradientEnd {
    switch (widget.type) {
      case BusinessType.shoes:
        return const Color(0xFF4834DF);
      case BusinessType.fashion:
        return const Color(0xFFB83280);
      case BusinessType.grocery:
        return const Color(0xFF00796B);
      case BusinessType.general:
        return const Color(0xFFE67E22);
    }
  }

  String get _featureHint {
    switch (widget.type) {
      case BusinessType.shoes:
        return 'Size & color variants';
      case BusinessType.fashion:
        return 'Size & color variants';
      case BusinessType.grocery:
        return 'Expiry date tracking';
      case BusinessType.general:
        return 'All-purpose setup';
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnim,
      child: GestureDetector(
        onTapDown: (_) => _controller.forward(),
        onTapUp: (_) {
          _controller.reverse();
          widget.onTap();
        },
        onTapCancel: () => _controller.reverse(),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_cardGradientStart, _cardGradientEnd],
            ),
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            boxShadow: [
              BoxShadow(
                color: _cardGradientStart.withValues(alpha: 0.35),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.type.icon,
                  style: const TextStyle(fontSize: 36),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.type.label,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _featureHint,
                      style: TextStyle(
                        fontWeight: FontWeight.w400,
                        fontSize: 11,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
