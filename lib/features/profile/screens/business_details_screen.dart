import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../../../core/models/business_profile.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';

class BusinessDetailsScreen extends ConsumerStatefulWidget {
  final String businessType;
  const BusinessDetailsScreen({super.key, required this.businessType});

  @override
  ConsumerState<BusinessDetailsScreen> createState() => _BusinessDetailsScreenState();
}

class _BusinessDetailsScreenState extends ConsumerState<BusinessDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  String _currency = 'INR';
  final _taxLabelCtrl = TextEditingController(text: 'GST');
  bool _saving = false;

  BusinessType get _type =>
      BusinessType.values.firstWhere((e) => e.name == widget.businessType);

  @override
  void dispose() {
    _nameCtrl.dispose();
    _taxLabelCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final profile = BusinessProfile(
      id: const Uuid().v4(),
      name: _nameCtrl.text.trim(),
      type: _type,
      currency: _currency,
      currencyDecimals: currencyDecimals[_currency]!,
      taxLabel: _taxLabelCtrl.text.trim(),
      variantSupport: _type.hasVariantSupport,
      expiryTracking: _type.hasExpiryTracking,
      createdAt: DateTime.now(),
    );

    try {
      await ref.read(activeProfileProvider.notifier).setProfile(profile);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save profile: $e'), backgroundColor: AppTheme.error),
      );
      return;
    }
    if (mounted) context.go('/');
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                // Header
                Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryPurple.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Center(
                        child: Text(_type.icon, style: const TextStyle(fontSize: 28)),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _type.label,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        Text(
                          'Set up your business',
                          style: TextStyle(
                            fontWeight: FontWeight.w400,
                            fontSize: 14,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // Features enabled banner
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    border: Border.all(color: AppTheme.accent.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.auto_awesome, color: AppTheme.accent, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _type.hasVariantSupport
                              ? 'Size & color variants enabled'
                              : _type.hasExpiryTracking
                                  ? 'Expiry date tracking enabled'
                                  : 'Standard product management',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                // Form fields
                _label('Business Name'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    hintText: 'e.g. My Awesome Store',
                    prefixIcon: Icon(Icons.store_rounded),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 20),

                _label('Currency'),
                const SizedBox(height: 8),
                // Fixed once products or sales exist (see Settings).
                DropdownButtonFormField<String>(
                  initialValue: _currency,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.currency_exchange_rounded),
                  ),
                  items: [
                    for (final code in currencyDecimals.keys)
                      DropdownMenuItem(value: code, child: Text(code)),
                  ],
                  onChanged: (code) => setState(() => _currency = code!),
                ),
                const SizedBox(height: 20),

                _label('Tax Label'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _taxLabelCtrl,
                  decoration: const InputDecoration(
                    hintText: 'GST',
                    prefixIcon: Icon(Icons.receipt_long_rounded),
                  ),
                ),
                const SizedBox(height: 40),

                // Save button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Get Started'),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppTheme.textSecondary,
        letterSpacing: 0.5,
      ),
    );
  }
}
