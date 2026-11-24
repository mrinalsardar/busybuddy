import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';
import 'image_providers.dart';

/// A product's picture in a rounded square, or [placeholder] icon while there
/// is none: no image set, not downloaded yet, or not available offline.
class ProductImage extends ConsumerWidget {
  const ProductImage({
    super.key,
    required this.imagePath,
    required this.size,
    this.placeholder = Icons.inventory_2_outlined,
    this.radius = 12,
  });

  /// `product.image_path`; null when the product has no image.
  final String? imagePath;
  final double size;
  final IconData placeholder;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = imagePath;
    final file = path == null ? null : ref.watch(productImageFileProvider(path)).value;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: file == null
            ? ColoredBox(
                color: AppTheme.primaryPurple.withValues(alpha: 0.12),
                child: Icon(placeholder, color: AppTheme.primaryPurple, size: size * 0.45),
              )
            : Image.file(
                file,
                fit: BoxFit.cover,
                cacheWidth: (size * dpr).round(),
                // A failed decode (damaged file) falls back to the placeholder.
                errorBuilder: (_, _, _) => Icon(placeholder, color: AppTheme.primaryPurple, size: size * 0.45),
                semanticLabel: 'Product picture',
              ),
      ),
    );
  }
}
