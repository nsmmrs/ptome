// Decoding speed against package:image: images of a page's size, made
// once by package:image's encoders, each decoded by both libraries (the
// best of several runs), to each one's own image (plain_images: a Raster
// of the samples as they are; package:image: its Image) and to 8-bit
// RGBA.
//
//   dart run benchmark/decode.dart
// ignore_for_file: avoid_print
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:plain_images/plain_images.dart';

/// A picture: smooth gradients with noise, like a screenshot or chart
/// with some texture.
img.Image picture(int width, int height, {int channels = 3}) {
  final random = math.Random(7);
  final image = img.Image(width: width, height: height, numChannels: channels);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final p = image.getPixel(x, y)
        ..r = (x * 255 ~/ width + random.nextInt(8)).clamp(0, 255)
        ..g = (y * 255 ~/ height + random.nextInt(8)).clamp(0, 255)
        ..b = ((x + y) * 127 ~/ (width + height) + 64).clamp(0, 255);
      if (channels == 4) p.a = (x ~/ 64).isEven ? 255 : 128;
    }
  }
  return image;
}

/// The best of [runs] timings of [action], in milliseconds.
double best(void Function() action, {int runs = 7}) {
  var best = double.infinity;
  for (var i = 0; i < runs; i++) {
    final watch = Stopwatch()..start();
    action();
    best = math.min(best, watch.elapsedMicroseconds / 1000);
  }
  return best;
}

Uint8List theirsRgba(img.Image image) =>
    image.convert(numChannels: 4, format: img.Format.uint8).toUint8List();

void main() {
  final rgb = picture(1600, 1000);
  final rgba = picture(1600, 1000, channels: 4);
  final cases = <String, Uint8List>{
    'PNG RGB 1600x1000': img.encodePng(rgb),
    'PNG RGBA 1600x1000': img.encodePng(rgba),
    'PNG palette 1600x1000': img.encodePng(img.quantize(rgb)),
    'GIF 1600x1000': img.encodeGif(rgb, dither: img.DitherKernel.none),
    'BMP 24-bit 1600x1000': img.encodeBmp(rgb),
    'BMP 32-bit 1600x1000': img.encodeBmp(rgba),
  };
  print(
    '| image | plain_images decode | package:image decode | '
    'plain_images to RGBA | package:image to RGBA |',
  );
  print('|---|---:|---:|---:|---:|');
  for (final MapEntry(key: name, value: bytes) in cases.entries) {
    final ours = best(() => ImageFile.read(bytes).decode());
    final theirs = best(() => img.decodeImage(bytes));
    final oursRgba = best(() => ImageFile.read(bytes).decode().toRgba8());
    final theirsToRgba = best(() => theirsRgba(img.decodeImage(bytes)!));
    String ms(double v) => '${v.toStringAsFixed(1)} ms';
    print(
      '| $name | ${ms(ours)} | ${ms(theirs)} | ${ms(oursRgba)} | '
      '${ms(theirsToRgba)} |',
    );
  }
}
