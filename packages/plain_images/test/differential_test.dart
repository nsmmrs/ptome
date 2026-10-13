/// plain_images against package:image, an independent pure-Dart decoder:
/// seeded random images in every layout package:image's encoders write
/// (PNG of each color type and bit depth, palettes with and without
/// alpha; GIF of 2 to 256 colors; BMP of 1 to 32 bits a pixel), decoded
/// by both to the same 8-bit RGBA (colors of fully transparent pixels
/// aside).
@TestOn('vm')
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:plain_images/plain_images.dart';
import 'package:test/test.dart';

/// package:image's decoding of [bytes] as 8-bit RGBA.
Uint8List oracle(Uint8List bytes) {
  final image = img.decodeImage(bytes)!;
  final out = Uint8List(image.width * image.height * 4);
  var o = 0;
  int eight(num value, num max) => (value * 255 / max).round();
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++, o += 4) {
      final p = image.getPixel(x, y);
      final max = p.maxChannelValue;
      // (Gray, and gray and alpha, are one and two channels.)
      final gray = !image.hasPalette && image.numChannels <= 2;
      out[o] = eight(p.r, max);
      out[o + 1] = eight(gray ? p.r : p.g, max);
      out[o + 2] = eight(gray ? p.r : p.b, max);
      out[o + 3] = switch (image.numChannels) {
        2 when gray => eight(p[1], max),
        4 => eight(p.a, max),
        _ when image.hasPalette && p.length == 4 => eight(p.a, max),
        _ => 255,
      };
    }
  }
  return out;
}

/// A random image of [format] with [channels], [palette] entries if
/// given: runs of random values, so the compressors find repeats.
img.Image randomImage(
  math.Random random,
  int width,
  int height, {
  img.Format format = img.Format.uint8,
  int channels = 3,
  int? palette,
  int paletteChannels = 3,
}) {
  if (palette != null) {
    final table = img.PaletteUint8(palette, paletteChannels);
    for (var i = 0; i < palette; i++) {
      for (var c = 0; c < paletteChannels; c++) {
        table.set(i, c, random.nextInt(256));
      }
    }
    final image = img.Image(
      width: width,
      height: height,
      format: format,
      numChannels: 1,
      palette: table,
    );
    _fill(random, image, 1, palette - 1);
    return image;
  }
  final image = img.Image(
    width: width,
    height: height,
    format: format,
    numChannels: channels,
  );
  _fill(random, image, channels, image.maxChannelValue.toInt());
  return image;
}

void _fill(math.Random random, img.Image image, int channels, int max) {
  var run = 0;
  var values = List<int>.filled(channels, 0);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      if (run-- <= 0) {
        run = random.nextInt(6);
        values = [for (var c = 0; c < channels; c++) random.nextInt(max + 1)];
        // Some fully transparent and fully opaque pixels.
        if (channels == 4 || channels == 2) {
          final roll = random.nextInt(4);
          if (roll == 0) values[channels - 1] = 0;
          if (roll == 1) values[channels - 1] = max;
        }
      }
      final p = image.getPixel(x, y);
      for (var c = 0; c < channels; c++) {
        p[c] = values[c];
      }
    }
  }
}

void main() {
  void check(String what, Uint8List bytes) {
    final ours = ImageFile.read(bytes).decode().toRgba8();
    final theirs = oracle(bytes);
    expect(ours.length, theirs.length, reason: what);
    for (var i = 0; i < ours.length; i += 4) {
      // (The color of a transparent pixel doesn't show.)
      if (ours[i + 3] == 0 && theirs[i + 3] == 0) continue;
      for (var c = 0; c < 4; c++) {
        if (ours[i + c] != theirs[i + c]) {
          fail(
            '$what: pixel ${i ~/ 4} is ${ours.sublist(i, i + 4)}, '
            'package:image says ${theirs.sublist(i, i + 4)}',
          );
        }
      }
    }
  }

  test('PNG', () {
    final random = math.Random(20261013);
    for (var trial = 0; trial < 300; trial++) {
      final w = 1 + random.nextInt(40);
      final h = 1 + random.nextInt(40);
      final kind = random.nextInt(4);
      final img.Image image;
      final String what;
      if (kind == 0) {
        final bits = [1, 2, 4, 8][random.nextInt(4)];
        final format = [
          img.Format.uint1,
          img.Format.uint2,
          img.Format.uint4,
          img.Format.uint8,
        ][[1, 2, 4, 8].indexOf(bits)];
        final alpha = random.nextBool();
        image = randomImage(
          random,
          w,
          h,
          format: format,
          palette: 1 << bits,
          paletteChannels: alpha ? 4 : 3,
        );
        what = 'PNG palette $bits bits${alpha ? ' alpha' : ''}';
      } else {
        final channels = 1 + random.nextInt(4);
        final format = channels == 1 && kind == 1
            ? [img.Format.uint1, img.Format.uint2, img.Format.uint4][random
                  .nextInt(3)]
            : (random.nextBool() ? img.Format.uint8 : img.Format.uint16);
        image = randomImage(random, w, h, format: format, channels: channels);
        what = 'PNG $channels channels $format';
      }
      check('$what ${w}x$h #$trial', img.encodePng(image));
    }
  });

  test('GIF', () {
    final random = math.Random(1987);
    for (var trial = 0; trial < 150; trial++) {
      final w = 1 + random.nextInt(60);
      final h = 1 + random.nextInt(60);
      final image = randomImage(random, w, h);
      final colors = 2 + random.nextInt(255);
      check(
        'GIF $colors colors ${w}x$h #$trial',
        img.GifEncoder(
          numColors: colors,
          dither: img.DitherKernel.none,
        ).encode(image, singleFrame: true),
      );
    }
  });

  test('BMP', () {
    final random = math.Random(1990);
    for (var trial = 0; trial < 200; trial++) {
      final w = 1 + random.nextInt(40);
      final h = 1 + random.nextInt(40);
      final kind = random.nextInt(5);
      final img.Image image;
      final String what;
      switch (kind) {
        case 0:
          final bits = [1, 4, 8][random.nextInt(3)];
          image = randomImage(
            random,
            w,
            h,
            format: [
              img.Format.uint1,
              img.Format.uint4,
              img.Format.uint8,
            ][[1, 4, 8].indexOf(bits)],
            palette: 1 << bits,
          );
          what = 'BMP palette $bits bits';
        case 1:
          image = randomImage(random, w, h);
          what = 'BMP 24 bits';
        case 2:
          image = randomImage(random, w, h, channels: 4);
          what = 'BMP 32 bits';
        case 3:
          image = randomImage(
            random,
            w,
            h,
            format: img.Format.uint4,
            channels: 4,
          );
          what = 'BMP 16 bits (4444)';
        default:
          image = randomImage(random, w, h, format: img.Format.uint4);
          what = 'BMP 12 bits (444 in 16)';
      }
      check('$what ${w}x$h #$trial', img.encodeBmp(image));
    }
  });
}
