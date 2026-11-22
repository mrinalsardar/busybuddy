import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/providers/core_providers.dart';
import '../providers/sales_providers.dart';

class SaleHistoryScreen extends ConsumerWidget {
  const SaleHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final salesAsync = ref.watch(recentSalesProvider);
    final profile = ref.watch(activeProfileProvider).valueOrNull;
    final money = profile?.money ?? MoneyFormat.fallback;
    final dateFmt = DateFormat('dd MMM yyyy, hh:mm a');

    return Scaffold(
      appBar: AppBar(
        title: Text('Sales History',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: salesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (sales) {
          if (sales.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryPurple.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.receipt_long_outlined,
                        size: 36, color: AppTheme.primaryPurple),
                  ),
                  const SizedBox(height: 20),
                  Text('No sales yet',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary)),
                  const SizedBox(height: 8),
                  Text('Complete your first sale in the POS tab',
                      style: TextStyle(
                          fontWeight: FontWeight.w400,
                          fontSize: 14, color: AppTheme.textSecondary)),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(recentSalesProvider),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              itemCount: sales.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final s = sales[i];
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceCard,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  ),
                  child: Row(
                    children: [
                      // Icon
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppTheme.success.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.receipt_outlined,
                            color: AppTheme.success, size: 22),
                      ),
                      const SizedBox(width: 14),
                      // Info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(dateFmt.format(s.createdAt),
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textPrimary)),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                _badge(s.paymentMethod.toUpperCase(),
                                    AppTheme.primaryPurple),
                                if (s.discountMinor > 0) ...[
                                  const SizedBox(width: 6),
                                  _badge(
                                      '-${money.format(s.discountMinor)}',
                                      AppTheme.warning),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Total
                      Text(money.format(s.totalMinor),
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.success)),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w700, color: color)),
    );
  }
}
