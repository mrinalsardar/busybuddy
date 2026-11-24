import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

/// Longest side, in pixels, of a stored product image. Larger pictures are
/// scaled down; smaller ones are never scaled up.
const maxProductImageSide = 1024;

/// JPEG quality (1-100) of a stored product image. A 1024 px photo comes out
/// at roughly 100-200 KB, well under the storage bucket's 1 MiB limit.
const productImageJpegQuality = 80;

/// A picked file that is not a readable image.
class UnsupportedImageException implements Exception {
  const UnsupportedImageException();

  @override
  String toString() => 'The file is not a supported image';
}

/// Turns any picked image (JPEG, PNG, WebP, ...) into the one format the app
/// stores: a JPEG of at most [maxProductImageSide] px on its longest side, with
/// the camera's rotation applied and its metadata (location included) dropped.
///
/// Throws [UnsupportedImageException] when [bytes] cannot be decoded.
Uint8List processProductImage(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const UnsupportedImageException();
  var image = img.bakeOrientation(decoded);
  if (image.width > maxProductImageSide || image.height > maxProductImageSide) {
    image = img.copyResize(
      image,
      width: image.width >= image.height ? maxProductImageSide : null,
      height: image.height > image.width ? maxProductImageSide : null,
      interpolation: img.Interpolation.average,
    );
  }
  // JPEG has no transparency: flatten onto white rather than black.
  if (image.hasAlpha) {
    final flat = img.Image(width: image.width, height: image.height, numChannels: 3);
    img.fill(flat, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(flat, image);
    image = flat;
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: productImageJpegQuality));
}

/// [processProductImage] off the UI isolate: decoding a camera photo takes a
/// noticeable moment.
Future<Uint8List> processProductImageInBackground(Uint8List bytes) => compute(processProductImage, bytes);
