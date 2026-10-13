/// Image files read for their header, then decoded to a [Raster]: the
/// formats, the header classes (one part file each), and the decoded
/// image.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:plain_compression/plain_compression.dart';
import 'package:plain_images/src/bmp_decode.dart';
import 'package:plain_images/src/ccitt.dart';
import 'package:plain_images/src/exception.dart';
import 'package:plain_images/src/exif.dart';
import 'package:plain_images/src/gif_decode.dart';
import 'package:plain_images/src/jpeg_decode.dart';
import 'package:plain_images/src/png_unfilter.dart';
import 'package:plain_images/src/tiff_decode.dart';
import 'package:plain_images/src/vp8_decode.dart';
import 'package:plain_images/src/webp_lossless.dart';
import 'package:plain_images/src/yuv.dart';

part 'bmp.dart';
part 'gif.dart';
part 'jpeg.dart';
part 'png.dart';
part 'tiff.dart';
part 'webp.dart';

/// An image file format.
enum ImageFormat {
  /// Portable Network Graphics (ISO/IEC 15948).
  png('PNG'),

  /// JPEG (ISO/IEC 10918-1), in a JFIF or EXIF file.
  jpeg('JPEG'),

  /// Graphics Interchange Format (87a and 89a).
  gif('GIF'),

  /// Windows and OS/2 bitmaps.
  bmp('BMP'),

  /// WebP (RFC 9649), lossy and lossless.
  webp('WebP'),

  /// TIFF 6.0 and BigTIFF.
  tiff('TIFF');

  new(this.label);

  /// The format's usual name.
  final String label;

  /// The format of the file [bytes] begins like, or null.
  static ImageFormat? of(Uint8List bytes) {
    if (_startsWith(bytes, _pngSignature)) return png;
    if (bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff) {
      return jpeg;
    }
    if (_startsWith(bytes, _gif87) || _startsWith(bytes, _gif89)) return gif;
    if (bytes.length >= 14 && bytes[0] == 0x42 && bytes[1] == 0x4d) {
      return bmp;
    }
    if (bytes.length >= 12 &&
        String.fromCharCodes(bytes, 0, 4) == 'RIFF' &&
        String.fromCharCodes(bytes, 8, 12) == 'WEBP') {
      return webp;
    }
    if (bytes.length >= 8 &&
        ((bytes[0] == 0x49 &&
                bytes[1] == 0x49 &&
                (bytes[2] == 42 || bytes[2] == 43) &&
                bytes[3] == 0) ||
            (bytes[0] == 0x4d &&
                bytes[1] == 0x4d &&
                bytes[2] == 0 &&
                (bytes[3] == 42 || bytes[3] == 43)))) {
      return tiff;
    }
    return null;
  }
}

/// The name of a format the file [bytes] begins like that isn't read
/// (AVIF, HEIC, JPEG XL, JPEG 2000, ...), or null.
String? unsupportedFormatOf(Uint8List bytes) {
  bool at(int offset, String text) {
    if (bytes.length < offset + text.length) return false;
    for (var i = 0; i < text.length; i++) {
      if (bytes[offset + i] != text.codeUnitAt(i)) return false;
    }
    return true;
  }

  if (at(4, 'ftyp')) {
    for (final (brand, name) in const [
      ('avif', 'AVIF'),
      ('avis', 'AVIF'),
      ('heic', 'HEIC'),
      ('heix', 'HEIC'),
      ('mif1', 'HEIF'),
      ('msf1', 'HEIF'),
      ('jxl ', 'JPEG XL'),
    ]) {
      if (at(8, brand)) return name;
    }
  }
  if (at(0, 'ÿ\u000a') || at(4, 'JXL ')) return 'JPEG XL';
  if (at(4, 'jP  ') || at(0, 'ÿOÿQ')) return 'JPEG 2000';
  if (at(0, '\u0000\u0000\u0001\u0000')) return 'ICO';
  if (at(0, '8BPS')) return 'PSD';
  if (at(0, '<svg') || at(0, '<?xml')) return 'SVG';
  if (at(0, '%PDF')) return 'PDF';
  return null;
}

/// An image file, read for its header: its size and how its samples are
/// laid out. [decode] reads its samples.
sealed class ImageFile {
  new _(this.bytes);

  /// The image file in [bytes], its format told by its signature; throws
  /// an [ImageFormatException] when it isn't one of [ImageFormat], or its
  /// header is damaged.
  factory read(Uint8List bytes) => switch (ImageFormat.of(bytes)) {
    ImageFormat.png => PngFile.read(bytes),
    ImageFormat.jpeg => JpegFile.read(bytes),
    ImageFormat.gif => GifFile.read(bytes),
    ImageFormat.bmp => BmpFile.read(bytes),
    ImageFormat.webp => WebPFile.read(bytes),
    ImageFormat.tiff => TiffFile.read(bytes),
    null => throw ImageFormatException(switch (unsupportedFormatOf(bytes)) {
      final name? => '$name images are not supported',
      null => 'not an image file plain_images reads',
    }, unsupportedFormat: unsupportedFormatOf(bytes)),
  };

  /// The most pixels [decode] decodes (8192 by 8192, more than a letter
  /// page scanned at 600 dpi): a larger image, most likely a damaged or
  /// hostile header, is an [ImageFormatException].
  static const int maxPixels = 1 << 26;

  /// The file.
  final Uint8List bytes;

  /// The format.
  ImageFormat get format;

  /// The width, in pixels.
  int get width;

  /// The height, in pixels.
  int get height;

  /// The color model of [decode]'s samples.
  ColorModel get colorModel;

  /// The bits per sample of [decode]'s samples.
  int get bitDepth;

  /// The EXIF orientation (1–8; 1 is upright). It is reported, not
  /// applied: placing the image is up to the caller.
  int get orientation => 1;

  /// The embedded ICC profile, if any.
  Uint8List? get iccProfile => null;

  /// The samples, palette and transparency; throws an
  /// [ImageFormatException] when the image data is damaged, or the image
  /// has more than [maxPixels] pixels.
  Raster decode();

  /// Throws when the image has more than [maxPixels] pixels.
  void _checkSize() {
    if (width * height > maxPixels) {
      throw ImageFormatException(
        '${format.label} image of $width by $height pixels is too large to '
        'decode',
      );
    }
  }
}

/// How a [Raster]'s samples give a pixel's color.
enum ColorModel {
  /// One gray sample.
  gray(1),

  /// Red, green and blue samples.
  rgb(3),

  /// Cyan, magenta, yellow and black samples.
  cmyk(4),

  /// One index into a palette of RGB colors.
  indexed(1);

  new(this.channels);

  /// The samples per pixel.
  final int channels;
}

/// A decoded image: its color samples in rows top to bottom, each row
/// packed (a sample's bits most significant first, a row starting on a
/// byte, 16-bit samples big-endian), with what is transparent kept apart.
@immutable
final class Raster {
  /// A raster of [samples], as described by the other fields.
  new({
    required this.width,
    required this.height,
    required this.colorModel,
    required this.bitDepth,
    required this.samples,
    this.palette,
    this.transparency,
    this.iccProfile,
    this.orientation = 1,
  }) : assert(
         samples.length >=
             ((width * colorModel.channels * bitDepth + 7) >> 3) * height,
         'samples for every row',
       );

  /// The width, in pixels.
  final int width;

  /// The height, in pixels.
  final int height;

  /// How the samples give a color.
  final ColorModel colorModel;

  /// The bits per sample: 1, 2, 4, 8 or 16.
  final int bitDepth;

  /// The color samples, row after row.
  final Uint8List samples;

  /// The palette of an [ColorModel.indexed] raster: RGB triples, 8 bits
  /// each.
  final Uint8List? palette;

  /// What is transparent, or null when every pixel is opaque.
  final Transparency? transparency;

  /// The ICC profile the samples are in, if any.
  final Uint8List? iccProfile;

  /// The EXIF orientation (1–8; 1 is upright), not applied.
  final int orientation;

  /// The bytes of a row of samples.
  int get rowBytes => (width * colorModel.channels * bitDepth + 7) >> 3;

  /// Sample [channel] of the pixel at [x], [y] (0 to `1 << bitDepth` − 1).
  int sample(int x, int y, [int channel = 0]) => _sampleAt(
    samples,
    rowBytes,
    bitDepth,
    x * colorModel.channels + channel,
    y,
  );

  /// The pixels as 8-bit RGBA, row after row: samples scaled to 8 bits,
  /// palettes looked up, CMYK converted naively (each of R, G, B is
  /// `(1 − C)(1 − K)`), straight (not premultiplied) alpha.
  Uint8List toRgba8() {
    if (bitDepth == 8 && colorModel != ColorModel.cmyk) return _rgba8Fast();
    final out = Uint8List(width * height * 4);
    final palette = this.palette;
    final channels = colorModel.channels;
    final alpha = transparency;
    int scale(int value) => switch (bitDepth) {
      1 => value * 255,
      2 => value * 85,
      4 => value * 17,
      8 => value,
      _ => (value * 255 + 32767) ~/ 65535,
    };
    var o = 0;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++, o += 4) {
        switch (colorModel) {
          case ColorModel.gray:
            final v = scale(sample(x, y));
            out[o] = out[o + 1] = out[o + 2] = v;
          case ColorModel.rgb:
            for (var c = 0; c < 3; c++) {
              out[o + c] = scale(sample(x, y, c));
            }
          case ColorModel.cmyk:
            final k = 255 - scale(sample(x, y, 3));
            for (var c = 0; c < 3; c++) {
              out[o + c] = ((255 - scale(sample(x, y, c))) * k + 127) ~/ 255;
            }
          case ColorModel.indexed:
            final i = sample(x, y) * 3;
            if (palette != null && i + 2 < palette.length) {
              out[o] = palette[i];
              out[o + 1] = palette[i + 1];
              out[o + 2] = palette[i + 2];
            }
        }
        out[o + 3] = switch (alpha) {
          null => 255,
          AlphaChannel(:final samples, :final bitDepth) =>
            bitDepth == 16
                ? ((samples[(y * width + x) * 2] << 8 |
                                  samples[(y * width + x) * 2 + 1]) *
                              255 +
                          32767) ~/
                      65535
                : samples[y * width + x],
          ColorKey(:final values) =>
            _keyed(values, [for (var c = 0; c < channels; c++) sample(x, y, c)])
                ? 0
                : 255,
        };
      }
    }
    return out;
  }
}

extension on Raster {
  /// [Raster.toRgba8] of 8-bit gray, RGB or indexed samples, a pixel at a
  /// time without the general case's lookups.
  Uint8List _rgba8Fast() {
    final count = width * height;
    final out = Uint8List(count * 4);
    final samples = this.samples;
    switch (colorModel) {
      case ColorModel.gray:
        for (var p = 0, o = 0; p < count; p++, o += 4) {
          final v = samples[p];
          out[o] = v;
          out[o + 1] = v;
          out[o + 2] = v;
          out[o + 3] = 255;
        }
      case ColorModel.rgb:
        for (var p = 0, i = 0, o = 0; p < count; p++, i += 3, o += 4) {
          out[o] = samples[i];
          out[o + 1] = samples[i + 1];
          out[o + 2] = samples[i + 2];
          out[o + 3] = 255;
        }
      case ColorModel.indexed:
        // The palette as RGBA, every index covered.
        final table = Uint8List(256 * 4);
        final palette = this.palette ?? Uint8List(0);
        for (var i = 0; i < 256; i++) {
          if (3 * i + 2 < palette.length) {
            table[4 * i] = palette[3 * i];
            table[4 * i + 1] = palette[3 * i + 1];
            table[4 * i + 2] = palette[3 * i + 2];
          }
          table[4 * i + 3] = 255;
        }
        if (transparency case ColorKey(values: [final key])) {
          table[4 * key + 3] = 0;
        }
        for (var p = 0, o = 0; p < count; p++, o += 4) {
          final t = samples[p] << 2;
          out[o] = table[t];
          out[o + 1] = table[t + 1];
          out[o + 2] = table[t + 2];
          out[o + 3] = table[t + 3];
        }
      case ColorModel.cmyk:
        throw StateError('CMYK has no fast path');
    }
    switch (transparency) {
      case AlphaChannel(:final samples, bitDepth: 8):
        for (var p = 0; p < count; p++) {
          out[4 * p + 3] = samples[p];
        }
      case AlphaChannel(:final samples):
        for (var p = 0; p < count; p++) {
          out[4 * p + 3] =
              ((samples[2 * p] << 8 | samples[2 * p + 1]) * 255 + 32767) ~/
              65535;
        }
      case ColorKey(:final values) when colorModel != ColorModel.indexed:
        final channels = colorModel.channels;
        for (var p = 0; p < count; p++) {
          var keyed = true;
          for (var c = 0; c < channels; c++) {
            if (samples[p * channels + c] != values[c]) keyed = false;
          }
          if (keyed) out[4 * p + 3] = 0;
        }
      case _:
    }
    return out;
  }
}

bool _keyed(List<int> key, List<int> pixel) {
  for (var c = 0; c < key.length; c++) {
    if (key[c] != pixel[c]) return false;
  }
  return true;
}

int _sampleAt(Uint8List samples, int stride, int depth, int index, int y) {
  final row = y * stride;
  return switch (depth) {
    8 => samples[row + index],
    16 => samples[row + 2 * index] << 8 | samples[row + 2 * index + 1],
    _ =>
      (samples[row + ((index * depth) >> 3)] >>
              (8 - depth - ((index * depth) & 7))) &
          ((1 << depth) - 1),
  };
}

/// What of a [Raster] is transparent.
@immutable
sealed class Transparency {
  const new();
}

/// An alpha sample for each pixel, row after row (0 transparent, the
/// largest value opaque; not premultiplied into the color).
final class AlphaChannel extends Transparency {
  /// [samples] of [bitDepth] bits (8 or 16, big-endian).
  const new(this.samples, this.bitDepth);

  /// The samples.
  final Uint8List samples;

  /// The bits per sample: 8 or 16.
  final int bitDepth;
}

/// A color whose pixels are transparent (the others opaque): a sample
/// value for each channel (for an indexed raster, a palette index).
final class ColorKey extends Transparency {
  /// The key of [values].
  const new(this.values);

  /// The sample values.
  final List<int> values;
}

const List<int> _pngSignature = [
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, //
];
final List<int> _gif87 = 'GIF87a'.codeUnits;
final List<int> _gif89 = 'GIF89a'.codeUnits;

bool _startsWith(List<int> bytes, List<int> prefix) {
  if (bytes.length < prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (bytes[i] != prefix[i]) return false;
  }
  return true;
}
