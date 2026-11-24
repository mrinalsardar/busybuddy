import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../db/database_helper.dart';
import 'product_image_store.dart';

/// Where a new product picture comes from.
enum ImagePickSource { camera, gallery }

/// Asks the user for a picture, through the system camera or gallery. Not
/// processed yet: see processProductImage.
class ProductImagePicker {
  const ProductImagePicker();

  /// The picked image's bytes, or null if the user cancelled.
  Future<Uint8List?> pick(ImagePickSource source) async {
    // maxWidth/maxHeight only spare memory (a camera photo can be 12 MP); the
    // stored size is set by processProductImage.
    final file = await ImagePicker().pickImage(
      source: source == ImagePickSource.camera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 2048,
      maxHeight: 2048,
    );
    return file?.readAsBytes();
  }
}

final productImagePickerProvider = Provider((_) => const ProductImagePicker());

/// Overridden in main with the Supabase client when a backend is configured;
/// otherwise images stay on the device.
final productImageStoreProvider = Provider(
  (_) => ProductImageStore(null, directory: DatabaseHelper().productImageDir),
);

/// The file to show for a product's `image_path`: the local copy, else a
/// download on demand, else null (see ProductImageStore.resolve). Not kept
/// once nothing shows it, so a missing image is tried again next time.
final productImageFileProvider = FutureProvider.autoDispose.family<File?, String>(
  (ref, path) => ref.watch(productImageStoreProvider).resolve(path),
);
