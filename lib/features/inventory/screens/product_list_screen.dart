import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/providers/core_providers.dart';
import '../providers/inventory_providers.dart';

class _SearchField extends ConsumerStatefulWidget {
  const _SearchField();

  @override
  ConsumerState<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends ConsumerState<_SearchField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: ref.read(inventorySearchProvider));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final search = ref.watch(inventorySearchProvider);
    ref.listen<String>(inventorySearchProvider, (_, next) {
      if (_controller.text != next) _controller.text = next;
    });
    return TextField(
      controller: _controller,
      onChanged: (v) => ref.read(inventorySearchProvider.notifier).state = v,
      decoration: InputDecoration(
        hintText: 'Search products…',
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: search.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () =>
                    ref.read(inventorySearchProvider.notifier).state = '',
              )
            : null,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }
}

class ProductListScreen extends ConsumerWidget {
  const ProductListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(productListProvider);
    final profile = ref.watch(activeProfileProvider).value;
    final isOwner = ref.watch(isOwnerProvider);
    final search = ref.watch(inventorySearchProvider);
    final category = ref.watch(inventoryCategoryFilterProvider);
    final avgPrices = ref.watch(avgSellingPriceProvider).value ?? const {};

    return Scaffold(
      appBar: AppBar(
        title: Text('Inventory', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list_rounded),
            onPressed: () => _showCategoryFilter(context, ref),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Search bar ─────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: const _SearchField(),
          ),

          // ── Product grid ───────────────────────────
          Expanded(
            child: productsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (products) {
                if (products.isEmpty) {
                  if (search.isNotEmpty || category != null) {
                    return _NoMatchState(
                      onClear: () {
                        ref.read(inventorySearchProvider.notifier).state = '';
                        ref.read(inventoryCategoryFilterProvider.notifier).state = null;
                      },
                    );
                  }
                  return _EmptyState(
                    onAdd: () => context.go('/inventory/add'),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(productListProvider),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                    itemCount: products.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final p = products[i];
                      final isLow = p.isLowStock;
                      return _ProductCard(
                        name: p.name,
                        category: p.category ?? 'Uncategorized',
                        priceMinor: p.priceMinor,
                        avgSoldMinor: avgPrices[p.id],
                        // Cost prices are for the owner only.
                        costMinor: isOwner ? p.costPriceMinor : 0,
                        stock: p.stockQty,
                        isLowStock: isLow,
                        money: profile?.money ?? MoneyFormat.fallback,
                        onTap: () => context.go('/inventory/edit/${p.id}'),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/inventory/add'),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Product'),
      ),
    );
  }

  void _showCategoryFilter(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.read(categoryListProvider);
    final current = ref.read(inventoryCategoryFilterProvider);

    categoriesAsync.whenData((categories) {
      showModalBottomSheet(
        context: context,
        backgroundColor: AppTheme.surfaceCard,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.textSecondary.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text('Filter by Category',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _FilterChip(
                    label: 'All',
                    selected: current == null,
                    onTap: () {
                      ref.read(inventoryCategoryFilterProvider.notifier).state =
                          null;
                      Navigator.pop(context);
                    },
                  ),
                  ...categories.map((c) => _FilterChip(
                        label: c,
                        selected: current == c,
                        onTap: () {
                          ref
                              .read(inventoryCategoryFilterProvider.notifier)
                              .state = c;
                          Navigator.pop(context);
                        },
                      )),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      );
    });
  }
}

// ── Sub-widgets ────────────────────────────────────────

class _ProductCard extends StatelessWidget {
  final String name;
  final String category;
  final int priceMinor;
  final int? avgSoldMinor;
  final int costMinor;
  final int stock;
  final bool isLowStock;
  final MoneyFormat money;
  final VoidCallback onTap;

  const _ProductCard({
    required this.name,
    required this.category,
    required this.priceMinor,
    required this.avgSoldMinor,
    required this.costMinor,
    required this.stock,
    required this.isLowStock,
    required this.money,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surfaceCard,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Icon placeholder
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppTheme.primaryPurple.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.inventory_2_outlined,
                    color: AppTheme.primaryPurple, size: 22),
              ),
              const SizedBox(width: 14),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 3),
                    Text(category,
                        style: TextStyle(
                            fontWeight: FontWeight.w400,
                            fontSize: 12, color: AppTheme.textSecondary)),
                  ],
                ),
              ),
              // Price + stock
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(money.format(priceMinor),
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary)),
                  if (avgSoldMinor != null)
                    Text('Avg sold ${money.format(avgSoldMinor!)}',
                        style: TextStyle(
                            fontWeight: FontWeight.w400,
                            fontSize: 11, color: AppTheme.textSecondary)),
                  if (costMinor > 0)
                    Text('Cost ${money.format(costMinor)}',
                        style: TextStyle(
                            fontWeight: FontWeight.w400,
                            fontSize: 11, color: AppTheme.textSecondary)),
                  const SizedBox(height: 3),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isLowStock
                          ? AppTheme.error.withValues(alpha: 0.12)
                          : AppTheme.success.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '$stock in stock',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isLowStock ? AppTheme.error : AppTheme.success,
                      ),
                    ),
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

class _NoMatchState extends StatelessWidget {
  final VoidCallback onClear;
  const _NoMatchState({required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off_rounded,
                size: 48, color: AppTheme.textSecondary),
            const SizedBox(height: 16),
            Text('No matching products',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary)),
            const SizedBox(height: 8),
            Text('Nothing matches your search or filter',
                style: TextStyle(
                    fontWeight: FontWeight.w400,
                    fontSize: 14, color: AppTheme.textSecondary)),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: onClear,
              child: const Text('Clear search and filter'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
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
              child: const Icon(Icons.inventory_2_outlined,
                  size: 36, color: AppTheme.primaryPurple),
            ),
            const SizedBox(height: 20),
            Text('No products yet',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary)),
            const SizedBox(height: 8),
            Text('Add your first product to get started',
                style: TextStyle(
                    fontWeight: FontWeight.w400,
                    fontSize: 14, color: AppTheme.textSecondary)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add Product'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primaryPurple
              : AppTheme.primaryPurple.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppTheme.primaryPurple,
          ),
        ),
      ),
    );
  }
}
