import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/models/sale.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/providers/core_providers.dart';
import '../providers/sales_providers.dart';

class SaleHistoryScreen extends ConsumerWidget {
  const SaleHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final salesAsync = ref.watch(recentSalesProvider);
    final profile = ref.watch(activeProfileProvider).value;
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
                return Material(
                  color: AppTheme.surfaceCard,
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  child: InkWell(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  onTap: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    showDragHandle: true,
                    builder: (_) => SaleDetailSheet(sale: s),
                  ),
                  child: Padding(
                  padding: const EdgeInsets.all(16),
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
                  ),
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

/// Line items, payment, date and totals of one recorded sale.
class SaleDetailSheet extends ConsumerWidget {
  final Sale sale;
  const SaleDetailSheet({super.key, required this.sale});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final money = ref.watch(activeProfileProvider).value?.money ?? MoneyFormat.fallback;
    final isOwner = ref.watch(isOwnerProvider);
    final itemsAsync = ref.watch(saleItemsProvider(sale.id));
    final dateFmt = DateFormat('dd MMM yyyy, hh:mm a');
    const bold = TextStyle(fontWeight: FontWeight.w700);

    Widget row(String label, String value, {TextStyle? style}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [Text(label, style: style), Text(value, style: style)],
          ),
        );

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text(dateFmt.format(sale.createdAt),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(sale.paymentMethod.toUpperCase(),
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
            const Divider(height: 24),
            itemsAsync.when(
              loading: () => const Padding(
                  padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
              error: (e, _) => Text('Error: $e'),
              data: (items) => items.isEmpty
                  ? const Text('No items recorded for this sale.')
                  : Column(
                      children: [
                        for (final i in items)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(i.productName, style: bold),
                                      Text('${i.qty} × ${money.format(i.unitPriceMinor)}',
                                          style: TextStyle(color: AppTheme.textSecondary)),
                                      if (isOwner)
                                        Text('Cost ${money.format(i.costPriceMinor)} each',
                                            style: TextStyle(
                                                fontSize: 12, color: AppTheme.textSecondary)),
                                    ],
                                  ),
                                ),
                                Text(money.format(i.lineTotalMinor), style: bold),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
            const Divider(height: 24),
            row('Subtotal', money.format(sale.subtotalMinor)),
            if (sale.discountMinor > 0) row('Discount', '-${money.format(sale.discountMinor)}'),
            if (sale.taxAmountMinor > 0) row('Tax', money.format(sale.taxAmountMinor)),
            row('Total', money.format(sale.totalMinor),
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}
