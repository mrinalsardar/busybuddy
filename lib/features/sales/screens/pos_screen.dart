import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/images/product_image.dart';
import '../../../core/models/product.dart';
import '../../../core/models/product_variant.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/plural.dart';
import '../../../core/providers/core_providers.dart';
import '../../inventory/providers/inventory_providers.dart';
import '../providers/sales_providers.dart';

class PosScreen extends ConsumerWidget {
  const PosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final profile = ref.watch(activeProfileProvider).value;
    final todayAsync = ref.watch(todayTotalProvider);
    final money = profile?.money ?? MoneyFormat.fallback;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(profile?.name ?? 'BusyBuddy',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            todayAsync.when(
              data: (t) => Text("Today's sales: ${money.format(t)}",
                  style: TextStyle(fontWeight: FontWeight.w400, fontSize: 12, color: context.colors.textSecondary)),
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // ── Product picker ──────────────────────────
          Expanded(child: _ProductPicker(money: money)),

          // ── Cart summary ────────────────────────────
          if (cart.items.isNotEmpty)
            _CartPanel(money: money),
        ],
      ),
    );
  }
}

// ── Product Picker (top half) ──────────────────────────
class _ProductPicker extends ConsumerWidget {
  final MoneyFormat money;
  const _ProductPicker({required this.money});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(posProductListProvider);
    final allowOversell =
        ref.watch(activeProfileProvider).value?.allowOversell ?? false;

    return productsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (products) {
        if (products.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.point_of_sale_rounded,
                    size: 48, color: context.colors.textSecondary.withValues(alpha: 0.4)),
                const SizedBox(height: 12),
                Text('Add products in Inventory first',
                    style: TextStyle(fontWeight: FontWeight.w400, color: context.colors.textSecondary)),
              ],
            ),
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.78,
          ),
          itemCount: products.length,
          itemBuilder: (_, i) {
            final p = products[i];
            return _ProductTile(
              name: p.name,
              imagePath: p.imagePath,
              priceMinor: p.priceMinor,
              canSell: allowOversell || p.stockQty > 0,
              money: money,
              onTap: () => _addToCart(context, ref, p),
            );
          },
        );
      },
    );
  }
}

/// Adds a product to the cart, asking for a variant first when it has any.
Future<void> _addToCart(BuildContext context, WidgetRef ref, Product product) async {
  final List<ProductVariant> variants;
  try {
    variants = await ref.read(variantsProvider(product.id).future);
  } catch (e) {
    if (context.mounted) _showMessage(context, 'Could not load variants: $e');
    return;
  }
  if (!context.mounted) return;

  ProductVariant? variant;
  if (variants.isNotEmpty) {
    variant = await showModalBottomSheet<ProductVariant>(
      context: context,
      builder: (_) => _VariantPicker(product: product, variants: variants),
    );
    if (variant == null || !context.mounted) return;
    // A sync can have changed the product while the picker was open.
    product = _current(ref.read(posProductListProvider).value, product);
  }
  if (!ref.read(cartProvider).addItem(product, variant: variant) && context.mounted) {
    _showMessage(context, 'No more stock for ${product.name}');
  }
}

/// [product] as [products] now has it, or unchanged if it is not listed.
Product _current(List<Product>? products, Product product) =>
    products?.where((p) => p.id == product.id).firstOrNull ?? product;

void _showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), backgroundColor: context.colors.error));
}

/// Watches the product and its variants, so it stays current while open.
class _VariantPicker extends ConsumerWidget {
  final Product product;
  /// Shown until the watched variants are read.
  final List<ProductVariant> variants;
  const _VariantPicker({required this.product, required this.variants});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = _current(ref.watch(posProductListProvider).value, product);
    final shown = ref.watch(variantsProvider(product.id)).value ?? variants;
    final allowOversell =
        ref.watch(activeProfileProvider).value?.allowOversell ?? false;
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text(current.name,
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700,
                    color: context.colors.textPrimary)),
          ),
          for (final v in shown)
            ListTile(
              enabled: allowOversell || v.stockQty > 0,
              title: Text(v.displayName.isEmpty ? 'Variant' : v.displayName),
              trailing: Text('${v.stockQty} in stock',
                  style: TextStyle(color: v.stockQty <= 0 ? context.colors.error : null)),
              onTap: () => Navigator.pop(context, v),
            ),
        ],
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  final String name;
  final String? imagePath;
  final int priceMinor;
  final bool canSell;
  final MoneyFormat money;
  final VoidCallback onTap;

  const _ProductTile({
    required this.name,
    required this.imagePath,
    required this.priceMinor,
    required this.canSell,
    required this.money,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.card,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: InkWell(
        onTap: canSell ? onTap : null,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        child: Opacity(
          opacity: canSell ? 1.0 : 0.4,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ProductImage(
                  imagePath: imagePath,
                  size: 48,
                  radius: 10,
                  placeholder: Icons.shopping_bag_outlined,
                ),
                const SizedBox(height: 8),
                Text(name,
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600,
                        color: context.colors.textPrimary),
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text(money.format(priceMinor),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: context.colors.accent)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Cart Panel (bottom) ────────────────────────────────
class _CartPanel extends ConsumerWidget {
  final MoneyFormat money;
  const _CartPanel({required this.money});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);

    return Container(
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: context.colors.shadow,
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.colors.textSecondary.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Cart items (scrollable, max 3 visible)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 150),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: cart.items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final ci = cart.items[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () => _editPrice(context, cart, ci, money),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(ci.displayName,
                                      style: TextStyle(
                                          fontWeight: FontWeight.w400,
                                          fontSize: 13, color: context.colors.textPrimary),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  Row(
                                    children: [
                                      Flexible(child: Text('@ ${money.format(ci.unitPriceMinor)}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              fontWeight: FontWeight.w400,
                                              fontSize: 11,
                                              color: context.colors.textSecondary))),
                                      const SizedBox(width: 4),
                                      Icon(Icons.edit_outlined,
                                          size: 12, color: context.colors.textSecondary),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // Qty stepper
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _StepperBtn(
                                icon: Icons.remove,
                                onTap: () => cart.updateQty(ci.cartKey, ci.qty - 1),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                child: Text('${ci.qty}',
                                    style: TextStyle(
                                        fontSize: 14, fontWeight: FontWeight.w700,
                                        color: context.colors.textPrimary)),
                              ),
                              _StepperBtn(
                                icon: Icons.add,
                                onTap: () {
                                  if (!cart.updateQty(ci.cartKey, ci.qty + 1)) {
                                    _showMessage(context, 'Only ${ci.available} in stock');
                                  }
                                },
                              ),
                            ],
                          ),
                          const SizedBox(width: 12),
                          ConstrainedBox(
                            constraints: const BoxConstraints(minWidth: 70),
                            child: Text(
                              money.format(ci.lineTotalMinor),
                              textAlign: TextAlign.end,
                              maxLines: 1,
                              softWrap: false,
                              style: TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w700,
                                  color: context.colors.textPrimary),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              const Divider(),
              // Total + checkout
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(countLabel(cart.itemCount, 'item'),
                          style: TextStyle(
                              fontWeight: FontWeight.w400,
                              fontSize: 12, color: context.colors.textSecondary)),
                      Text(money.format(cart.totalMinor),
                          style: TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w800,
                              color: context.colors.textPrimary)),
                    ],
                  ),
                  Row(
                    children: [
                      // Clear cart
                      IconButton(
                        onPressed: () => cart.clear(),
                        icon: Icon(Icons.delete_sweep_outlined,
                            color: context.colors.error),
                      ),
                      const SizedBox(width: 8),
                      // Checkout
                      SizedBox(
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: cart.items.isEmpty || cart.isCheckingOut
                              ? null
                              : () async {
                                  try {
                                    await ref.read(checkoutProvider)();
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('Sale not recorded: $e'),
                                          backgroundColor: context.colors.error,
                                        ),
                                      );
                                    }
                                    return;
                                  }
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Sale recorded!',
                                            style: TextStyle(fontWeight: FontWeight.w400)),
                                        backgroundColor: context.colors.success,
                                        behavior: SnackBarBehavior.floating,
                                        shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(10)),
                                      ),
                                    );
                                  }
                                },
                          icon: const Icon(Icons.check_circle_outline_rounded, size: 20),
                          label: const Text('Charge'),
                        ),
                      ),
                    ],
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

/// Lets the cashier change a line's unit price; the product price is only
/// a suggestion.
Future<void> _editPrice(
    BuildContext context, CartNotifier cart, CartItem item, MoneyFormat money) async {
  final price = await showDialog<int>(
    context: context,
    builder: (_) => _PriceDialog(item: item, money: money),
  );
  if (price != null) cart.updatePrice(item.cartKey, price);
}

/// Owns its text controller so it is disposed only after the dialog's exit
/// animation, not while the field is still on screen.
class _PriceDialog extends StatefulWidget {
  final CartItem item;
  final MoneyFormat money;
  const _PriceDialog({required this.item, required this.money});

  @override
  State<_PriceDialog> createState() => _PriceDialogState();
}

class _PriceDialogState extends State<_PriceDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _ctrl =
      TextEditingController(text: widget.money.toInput(widget.item.unitPriceMinor));

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.pop(context, widget.money.parse(_ctrl.text));
    }
  }

  @override
  Widget build(BuildContext context) {
    final money = widget.money;
    return AlertDialog(
      title: Text(widget.item.displayName),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _ctrl,
          autofocus: true,
          keyboardType: TextInputType.numberWithOptions(decimal: money.decimals > 0),
          decoration: InputDecoration(
            labelText: 'Unit price',
            helperText: 'Suggested ${money.format(widget.item.product.priceMinor)}',
          ),
          validator: (v) => money.parse(v ?? '') == null ? money.inputHint : null,
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: _submit, child: const Text('Set')),
      ],
    );
  }
}

class _StepperBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _StepperBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: AppTheme.primaryPurple.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 16, color: AppTheme.primaryPurple),
      ),
    );
  }
}
