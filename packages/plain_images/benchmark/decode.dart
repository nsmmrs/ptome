// Decoding speed against package:image: images of a page's size, made
// once by package:image's encoders, each decoded by both libraries (the
// best of several runs), to each one's own image (plain_images: a Raster
// of the samples as they are; package:image: its Image) and to 8-bit
// RGBA. WebP and progressive JPEG files are made by cwebp and cjpeg, when
// they are installed.
//
//   dart run benchmark/decode.dart
// ignore_for_file: avoid_print
import 'dart:io';
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

/// The pictures as WebP, by cwebp (package:image doesn't write WebP),
/// when it is installed.
Map<String, Uint8List> webp(img.Image rgb, img.Image rgba) {
  final dir = Directory.systemTemp.createTempSync('webp-bench.');
  try {
    final out = <String, Uint8List>{};
    for (final (name, image, options) in [
      ('WebP lossless 1600x1000', rgb, ['-lossless']),
      ('WebP lossy 1600x1000', rgb, ['-q', '80']),
      ('WebP lossy alpha 1600x1000', rgba, ['-q', '80']),
    ]) {
      final png = File('${dir.path}/in.png')
        ..writeAsBytesSync(img.encodePng(image));
      final result = Process.runSync('cwebp', [
        '-quiet',
        ...options,
        png.path,
        '-o',
        '${dir.path}/out.webp',
      ]);
      if (result.exitCode != 0) return out;
      out[name] = File('${dir.path}/out.webp').readAsBytesSync();
    }
    return out;
  } on ProcessException {
    return const {};
  } finally {
    dir.deleteSync(recursive: true);
  }
}

/// The picture as a progressive JPEG, by cjpeg (package:image doesn't
/// write one), when it is installed.
Map<String, Uint8List> progressiveJpeg(img.Image rgb) {
  final dir = Directory.systemTemp.createTempSync('jpeg-bench.');
  try {
    final ppm = File('${dir.path}/in.ppm')
      ..writeAsBytesSync([
        ...'P6\n${rgb.width} ${rgb.height}\n255\n'.codeUnits,
        ...rgb.toUint8List(),
      ]);
    final result = Process.runSync('cjpeg', [
      '-quality',
      '85',
      '-progressive',
      '-outfile',
      '${dir.path}/out.jpg',
      ppm.path,
    ]);
    if (result.exitCode != 0) return const {};
    return {
      'JPEG progressive 1600x1000': File('${dir.path}/out.jpg')
          .readAsBytesSync(),
    };
  } on ProcessException {
    return const {};
  } finally {
    dir.deleteSync(recursive: true);
  }
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
    'JPEG 4:2:0 1600x1000': img.encodeJpg(
      rgb,
      quality: 85,
      chroma: img.JpegChroma.yuv420,
    ),
    'JPEG 4:4:4 1600x1000': img.encodeJpg(rgb, quality: 85),
    ...webp(rgb, rgba),
    ...progressiveJpeg(rgb),
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
