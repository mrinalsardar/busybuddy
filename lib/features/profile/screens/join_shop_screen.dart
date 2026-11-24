import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';

/// Joins an existing shop as staff with an invite code from its owner. Needs
/// a connection. Once joined, the shop's data downloads with the next sync;
/// the router then leaves this screen by itself.
class JoinShopScreen extends ConsumerStatefulWidget {
  const JoinShopScreen({super.key});

  @override
  ConsumerState<JoinShopScreen> createState() => _JoinShopScreenState();
}

class _JoinShopScreenState extends ConsumerState<JoinShopScreen> {
  final _codeCtrl = TextEditingController();
  bool _busy = false;
  bool _joined = false;
  String? _error;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Enter the invite code');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).joinShop(code);
      if (mounted) setState(() => _joined = true);
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go('/onboarding'),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: _joined ? _waiting() : _form(),
        ),
      ),
    );
  }

  Widget _waiting() => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          Text('You joined the shop',
              style: TextStyle(
                  fontSize: 24, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
          const SizedBox(height: 8),
          Text('Downloading its data. This needs an internet connection.',
              style: TextStyle(fontSize: 15, color: AppTheme.textSecondary)),
        ],
      );

  Widget _form() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Text('Join a shop',
              style: TextStyle(
                  fontSize: 28, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
          const SizedBox(height: 8),
          Text('Ask the shop owner for an invite code (Settings, Invite staff).',
              style: TextStyle(fontSize: 15, color: AppTheme.textSecondary)),
          const SizedBox(height: 24),
          TextField(
            key: const Key('inviteCode'),
            controller: _codeCtrl,
            enabled: !_busy,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              hintText: 'Invite code',
              prefixIcon: Icon(Icons.vpn_key_outlined),
            ),
            onSubmitted: (_) => _join(),
          ),
          // Fixed-height slot so the Join button does not move when an error shows.
          SizedBox(
            key: const Key('joinError'),
            height: 60,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _error == null
                  ? null
                  : Text(_error!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppTheme.error)),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _busy ? null : _join,
              child: _busy
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : const Text('Join shop'),
            ),
          ),
        ],
      );
}
