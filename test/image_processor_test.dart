import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:busybuddy/core/images/image_processor.dart';

Uint8List png(int width, int height, {bool alpha = false}) {
  final image = img.Image(width: width, height: height, numChannels: alpha ? 4 : 3);
  // A gradient, so it does not compress to nothing.
  for (final p in image) {
    p
      ..r = p.x % 256
      ..g = p.y % 256
      ..b = (p.x + p.y) % 256;
    if (alpha) p.a = 0;
  }
  return Uint8List.fromList(img.encodePng(image));
}

img.Image decode(Uint8List jpeg) {
  // JPEG signature: FF D8.
  expect(jpeg.sublist(0, 2), [0xFF, 0xD8]);
  return img.decodeJpg(jpeg)!;
}

void main() {
  test('a large landscape picture is scaled to 1024 px wide and becomes a JPEG', () {
    final out = decode(processProductImage(png(2000, 1000)));
    expect((out.width, out.height), (1024, 512));
  });

  test('a large portrait picture is scaled to 1024 px high', () {
    final out = decode(processProductImage(png(600, 1800)));
    expect((out.width, out.height), (341, 1024));
  });

  test('a small picture keeps its size', () {
    final out = decode(processProductImage(png(300, 200)));
    expect((out.width, out.height), (300, 200));
  });

  test('transparency becomes white, not black', () {
    final out = decode(processProductImage(png(64, 64, alpha: true)));
    final p = out.getPixel(32, 32);
    expect([p.r, p.g, p.b], everyElement(greaterThan(240)));
  });

  test('a camera-size picture stays under the 1 MiB bucket limit', () {
    expect(processProductImage(png(3000, 3000)).length, lessThan(1024 * 1024));
  });

  test('a file that is not a picture is refused', () {
    expect(() => processProductImage(Uint8List.fromList([1, 2, 3, 4])), throwsA(isA<UnsupportedImageException>()));
  });
}
