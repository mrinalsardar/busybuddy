import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../../../core/db/data_exceptions.dart';
import '../../../core/images/image_processor.dart';
import '../../../core/images/image_providers.dart';
import '../../../core/images/product_image.dart';
import '../../../core/images/product_image_store.dart';
import '../../../core/models/product.dart';
import '../../../core/models/product_variant.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../providers/inventory_providers.dart';

class ProductFormScreen extends ConsumerStatefulWidget {
  final String? productId;
  const ProductFormScreen({super.key, this.productId});

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _skuCtrl = TextEditingController();
  final _barcodeCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _costCtrl = TextEditingController();
  final _categoryCtrl = TextEditingController();
  final _stockCtrl = TextEditingController(text: '0');
  final _lowStockCtrl = TextEditingController(text: '5');
  DateTime? _expiryDate;
  bool _saving = false;
  bool _isEdit = false;
  Product? _existing;

  // Picture: the saved one stays unless the user picks another (_newImage,
  // already resized) or removes it (_removeImage).
  Uint8List? _newImage;
  bool _removeImage = false;
  bool _pickingImage = false;

  // Variant management
  final List<_VariantEntry> _variants = [];

  bool get _showVariants =>
      ref.read(activeProfileProvider).value?.variantSupport ?? false;

  MoneyFormat get _money =>
      ref.read(activeProfileProvider).value?.money ?? MoneyFormat.fallback;

  bool get _hasVariants => _showVariants && _variants.isNotEmpty;

  bool get _showExpiry =>
      ref.read(activeProfileProvider).value?.expiryTracking ?? false;

  @override
  void initState() {
    super.initState();
    _isEdit = widget.productId != null;
    if (_isEdit) _loadProduct();
  }

  Future<void> _loadProduct() async {
    final dao = ref.read(productDaoProvider);
    final p = await dao.getById(widget.productId!);
    if (p == null) return;
    _existing = p;
    _nameCtrl.text = p.name;
    _skuCtrl.text = p.sku ?? '';
    _barcodeCtrl.text = p.barcode ?? '';
    _priceCtrl.text = _money.toInput(p.priceMinor);
    _costCtrl.text = _money.toInput(p.costPriceMinor);
    _categoryCtrl.text = p.category ?? '';
    _stockCtrl.text = p.stockQty.toString();
    _lowStockCtrl.text = p.lowStockThreshold.toString();
    _expiryDate = p.expiryDate;

    if (_showVariants) {
      final variantDao = ref.read(productVariantDaoProvider);
      final variants = await variantDao.getByProduct(p.id);
      for (final v in variants) {
        _variants.add(_VariantEntry(
          id: v.id,
          sizeCtrl: TextEditingController(text: v.size ?? ''),
          colorCtrl: TextEditingController(text: v.color ?? ''),
          stockCtrl: TextEditingController(text: v.stockQty.toString()),
          originalStock: v.stockQty,
        ));
      }
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _skuCtrl.dispose();
    _barcodeCtrl.dispose();
    _priceCtrl.dispose();
    _costCtrl.dispose();
    _categoryCtrl.dispose();
    _stockCtrl.dispose();
    _lowStockCtrl.dispose();
    for (final v in _variants) {
      v.sizeCtrl.dispose();
      v.colorCtrl.dispose();
      v.stockCtrl.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final profile = ref.read(activeProfileProvider).value!;
    final dao = ref.read(productDaoProvider);
    final id = _existing?.id ?? const Uuid().v4();
    final now = DateTime.now();

    final oldImagePath = _existing?.imagePath;
    var imagePath = _removeImage ? null : oldImagePath;
    if (_newImage != null) {
      try {
        imagePath = await ref.read(productImageStoreProvider).save(profile.id, id, _newImage!);
      } catch (e) {
        if (!mounted) return;
        setState(() => _saving = false);
        _showError('Could not save the picture: $e');
        return;
      }
    }

    final product = Product(
      id: id,
      profileId: profile.id,
      name: _nameCtrl.text.trim(),
      sku: _skuCtrl.text.trim().isEmpty ? null : _skuCtrl.text.trim(),
      barcode: _barcodeCtrl.text.trim().isEmpty ? null : _barcodeCtrl.text.trim(),
      // Validators guarantee these parse.
      priceMinor: _money.parse(_priceCtrl.text)!,
      costPriceMinor: _costCtrl.text.trim().isEmpty ? 0 : _money.parse(_costCtrl.text)!,
      category: _categoryCtrl.text.trim().isEmpty ? null : _categoryCtrl.text.trim(),
      // With variants, the DAO sets stock to the variant total.
      stockQty: _hasVariants ? 0 : int.parse(_stockCtrl.text.trim()),
      lowStockThreshold: int.parse(_lowStockCtrl.text.trim()),
      expiryDate: _expiryDate,
      imagePath: imagePath,
      archived: _existing?.archived ?? false,
      createdAt: _existing?.createdAt ?? now,
      updatedAt: now,
    );

    final variants = !_showVariants
        ? null
        : _variants
            .map((ve) => ProductVariant(
                  id: ve.id,
                  productId: id,
                  profileId: profile.id,
                  size: ve.sizeCtrl.text.trim().isEmpty ? null : ve.sizeCtrl.text.trim(),
                  color: ve.colorCtrl.text.trim().isEmpty ? null : ve.colorCtrl.text.trim(),
                  stockQty: int.parse(ve.stockCtrl.text.trim()),
                ))
            .toList();

    try {
      await dao.saveWithVariants(product, isNew: !_isEdit, variants: variants);
    } catch (e) {
      // Not saved: the new picture file is not wanted.
      if (_newImage != null) await _store.deleteLocal(imagePath!);
      if (!mounted) return;
      setState(() => _saving = false);
      _showError(e is DuplicateCodeException ? e.message : 'Could not save product: $e');
      return;
    }
    // Saved: the replaced or removed picture's file is not wanted on this
    // device any more (the server's copy is deleted from the queue).
    if (oldImagePath != null && oldImagePath != imagePath) await _store.deleteLocal(oldImagePath);

    invalidateProductViews(ref.invalidate);
    if (mounted) context.go('/inventory');
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.colors.card,
        title: const Text('Delete Product?'),
        content: const Text(
            'The product will be removed from inventory and POS. Past sales keep their records.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: TextStyle(color: context.colors.error)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await ref.read(productDaoProvider).archive(widget.productId!);
      } catch (e) {
        if (mounted) _showError('Could not delete product: $e');
        return;
      }
      final imagePath = _existing?.imagePath;
      if (imagePath != null) await _store.deleteLocal(imagePath);
      invalidateProductViews(ref.invalidate);
      if (mounted) context.go('/inventory');
    }
  }

  ProductImageStore get _store => ref.read(productImageStoreProvider);

  Future<void> _pickImage(ImagePickSource source) async {
    setState(() => _pickingImage = true);
    try {
      final picked = await ref.read(productImagePickerProvider).pick(source);
      if (picked == null) return;
      final jpeg = await processProductImageInBackground(picked);
      if (mounted) {
        setState(() {
          _newImage = jpeg;
          _removeImage = false;
        });
      }
    } on UnsupportedImageException {
      if (mounted) _showError('That file is not a picture the app can use');
    } catch (e) {
      if (mounted) _showError('Could not get the picture: $e');
    } finally {
      if (mounted) setState(() => _pickingImage = false);
    }
  }

  bool get _hasImage => _newImage != null || (!_removeImage && _existing?.imagePath != null);

  Widget _imageSection() {
    const size = 96.0;
    final Widget preview = _newImage != null
        ? ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            child: Image.memory(_newImage!, width: size, height: size, fit: BoxFit.cover),
          )
        : ProductImage(
            imagePath: _removeImage ? null : _existing?.imagePath,
            size: size,
            radius: AppTheme.radiusMd,
            placeholder: Icons.add_a_photo_outlined,
          );
    return Row(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            preview,
            if (_pickingImage) const CircularProgressIndicator(strokeWidth: 2.5),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              OutlinedButton.icon(
                onPressed: _pickingImage ? null : () => _pickImage(ImagePickSource.camera),
                icon: const Icon(Icons.photo_camera_outlined, size: 18),
                label: const Text('Camera'),
              ),
              OutlinedButton.icon(
                onPressed: _pickingImage ? null : () => _pickImage(ImagePickSource.gallery),
                icon: const Icon(Icons.photo_library_outlined, size: 18),
                label: const Text('Gallery'),
              ),
              if (_hasImage)
                TextButton.icon(
                  onPressed: _pickingImage
                      ? null
                      : () => setState(() {
                            _newImage = null;
                            _removeImage = true;
                          }),
                  icon: Icon(Icons.delete_outline_rounded, size: 18, color: context.colors.error),
                  label: Text('Remove', style: TextStyle(color: context.colors.error)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: context.colors.error),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go('/inventory'),
        ),
        title: Text(_isEdit ? 'Edit Product' : 'New Product'),
        actions: [
          if (_isEdit)
            IconButton(
              icon: Icon(Icons.delete_outline_rounded, color: context.colors.error),
              onPressed: _delete,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _section('Photo (optional)'),
              const SizedBox(height: 12),
              _imageSection(),
              const SizedBox(height: 24),
              _section('Basic Info'),
              const SizedBox(height: 12),
              _field('Product Name', _nameCtrl, Icons.label_outline_rounded,
                  required: true),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: _field('SKU', _skuCtrl, Icons.tag_rounded)),
                  const SizedBox(width: 12),
                  Expanded(child: _field('Barcode', _barcodeCtrl, Icons.qr_code_rounded)),
                ],
              ),
              const SizedBox(height: 14),
              _field('Category', _categoryCtrl, Icons.category_outlined),
              const SizedBox(height: 24),

              _section('Pricing'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _field('Suggested Price', _priceCtrl,
                        Icons.attach_money_rounded,
                        keyboard: _moneyKeyboard,
                        validator: (v) => _moneyValidator(v, required: true)),
                  ),
                  // Cost prices are for the owner only. A staff edit keeps the
                  // product's cost: _costCtrl still holds it.
                  if (ref.watch(isOwnerProvider)) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: _field('Cost Price', _costCtrl,
                          Icons.money_off_rounded,
                          keyboard: _moneyKeyboard,
                          validator: _moneyValidator),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 24),

              _section('Stock'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _hasVariants
                        ? Text('Quantity is the total of the variants below',
                            style: TextStyle(
                                fontWeight: FontWeight.w400,
                                fontSize: 13, color: context.colors.textSecondary))
                        : _field('Quantity', _stockCtrl,
                            Icons.inventory_rounded,
                            keyboard: TextInputType.number,
                            validator: _stockValidator(_existing?.stockQty)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _field('Low Stock Alert', _lowStockCtrl,
                        Icons.warning_amber_rounded,
                        keyboard: TextInputType.number,
                        validator: _countValidator),
                  ),
                ],
              ),

              // Expiry date (grocery only)
              if (_showExpiry) ...[
                const SizedBox(height: 24),
                _section('Expiry'),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _expiryDate ?? DateTime.now().add(const Duration(days: 30)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 3650)),
                    );
                    if (picked != null) setState(() => _expiryDate = picked);
                  },
                  child: InputDecorator(
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.calendar_today_rounded),
                      hintText: 'Select expiry date',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
                    ),
                    child: Text(
                      _expiryDate != null
                          ? '${_expiryDate!.day}/${_expiryDate!.month}/${_expiryDate!.year}'
                          : 'No date selected',
                      style: TextStyle(
                        fontWeight: FontWeight.w400,
                        color: _expiryDate != null
                            ? context.colors.textPrimary
                            : context.colors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ],

              // Variants (shoes/fashion only)
              if (_showVariants) ...[
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _section('Variants'),
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _variants.add(_VariantEntry(
                            id: const Uuid().v4(),
                            sizeCtrl: TextEditingController(),
                            colorCtrl: TextEditingController(),
                            stockCtrl: TextEditingController(text: '0'),
                          ));
                        });
                      },
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ..._variants.asMap().entries.map((entry) {
                  final i = entry.key;
                  final v = entry.value;
                  return Padding(
                    key: ValueKey(v.id),
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: context.colors.card,
                        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                        border: Border.all(color: context.colors.divider),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: v.sizeCtrl,
                                  decoration: const InputDecoration(
                                    hintText: 'Size',
                                    isDense: true,
                                    border: InputBorder.none,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: v.colorCtrl,
                                  decoration: const InputDecoration(
                                    hintText: 'Color',
                                    isDense: true,
                                    border: InputBorder.none,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 60,
                                child: TextFormField(
                                  controller: v.stockCtrl,
                                  keyboardType: TextInputType.number,
                                  validator: _stockValidator(v.originalStock),
                                  decoration: const InputDecoration(
                                    hintText: 'Qty',
                                    isDense: true,
                                    border: InputBorder.none,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.remove_circle_outline,
                                    color: context.colors.error, size: 20),
                                onPressed: () {
                                  setState(() => _variants.removeAt(i));
                                  // Dispose once the row's fields are gone.
                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                    v.sizeCtrl.dispose();
                                    v.colorCtrl.dispose();
                                    v.stockCtrl.dispose();
                                  });
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],

              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: context.colors.buttonSpinner))
                      : Text(_isEdit ? 'Update Product' : 'Save Product'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: context.colors.textSecondary,
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl, IconData icon,
      {bool required = false,
      TextInputType? keyboard,
      FormFieldValidator<String>? validator}) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboard,
      decoration: InputDecoration(
        hintText: label,
        prefixIcon: Icon(icon, size: 20),
      ),
      validator: validator ??
          (required
              ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
              : null),
    );
  }

  static const _moneyKeyboard = TextInputType.numberWithOptions(decimal: true);

  String? _moneyValidator(String? v, {bool required = false}) {
    if (v == null || v.trim().isEmpty) return required ? 'Required' : null;
    return _money.parse(v) == null ? _money.inputHint : null;
  }

  static String? _countValidator(String? v) {
    final n = int.tryParse(v?.trim() ?? '');
    return (n == null || n < 0) ? 'Whole number, 0 or more' : null;
  }

  /// Like [_countValidator], but keeps an existing negative stock (left by an
  /// allowed oversell) valid, so the product can be edited without fixing it.
  static FormFieldValidator<String> _stockValidator(int? original) => (v) {
        final n = int.tryParse(v?.trim() ?? '');
        if (n != null && n < 0 && n == original) return null;
        return _countValidator(v);
      };
}

class _VariantEntry {
  final String id;
  final TextEditingController sizeCtrl;
  final TextEditingController colorCtrl;
  final TextEditingController stockCtrl;
  /// Stock as loaded from the DB; null for a new row.
  final int? originalStock;

  _VariantEntry({
    required this.id,
    required this.sizeCtrl,
    required this.colorCtrl,
    required this.stockCtrl,
    this.originalStock,
  });
}
