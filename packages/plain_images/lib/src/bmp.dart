part of 'image.dart';

/// How a BMP file's pixels are stored.
enum BmpCompression {
  /// As they are.
  none(0),

  /// 8-bit indices, run-length encoded.
  rle8(1),

  /// 4-bit indices, run-length encoded.
  rle4(2),

  /// 16 or 32 bits a pixel, channels where masks say.
  bitfields(3),

  /// A JPEG image.
  jpeg(4),

  /// A PNG image.
  png(5),

  /// Bit fields with an alpha mask.
  alphaBitfields(6),

  /// 1-bit pixels in ITU-T T.4's one-dimensional Huffman code (OS/2 2.x;
  /// its code 3).
  huffman(3),

  /// 24-bit pixels, run-length encoded (OS/2 2.x; its code 4).
  rle24(4);

  new(this.code);

  /// The compression's code in the file.
  final int code;
}

/// A BMP image: a Windows bitmap (a BITMAPINFOHEADER, or its version 2 to
/// 5 successors) or an OS/2 one (BITMAPCOREHEADER, or OS/2 2.x's 64-byte
/// header).
///
/// Indexed images (1, 2, 4 or 8 bits a pixel, RLE4 and RLE8 too) decode
/// to indices and their palette; others to 8-bit RGB, with an alpha
/// channel when an alpha mask is given (or, at 32 bits a pixel without
/// masks, from the fourth byte) and the alpha isn't 0 everywhere. Pixels
/// a run-length image leaves unset are transparent. A BMP holding a PNG
/// decodes as that PNG.
final class BmpFile extends ImageFile {
  new _(
    super.bytes, {
    required this.width,
    required this.height,
    required this.topDown,
    required this.bitsPerPixel,
    required this.compression,
    required this.dataOffset,
    required this.palette,
    required this.masks,
    required this.iccProfile,
  }) : super._();

  /// The BMP image in [bytes].
  factory read(Uint8List bytes) {
    if (bytes.length < 26 || bytes[0] != 0x42 || bytes[1] != 0x4d) {
      throw const ImageFormatException('not a BMP image');
    }
    final view = ByteData.sublistView(bytes);
    final dataOffset = view.getUint32(10, Endian.little);
    final headerSize = view.getUint32(14, Endian.little);
    const h = 14;
    if (headerSize < 12 || h + headerSize > bytes.length) {
      throw ImageFormatException(
        'BMP header of $headerSize bytes is not valid',
      );
    }
    final core = headerSize == 12;
    final width = core
        ? view.getUint16(h + 4, Endian.little)
        : view.getInt32(h + 4, Endian.little);
    final rawHeight = core
        ? view.getUint16(h + 6, Endian.little)
        : view.getInt32(h + 8, Endian.little);
    final bits = view.getUint16(h + (core ? 10 : 14), Endian.little);
    final code = core || headerSize < 20
        ? 0
        : view.getUint32(h + 16, Endian.little);
    // (OS/2 2.x's codes 3 and 4 are Huffman 1D and RLE24, not bit fields
    // and JPEG.)
    final os2 = headerSize == 16 || headerSize == 64;
    final compression = switch (code) {
      3 when os2 => BmpCompression.huffman,
      4 when os2 => BmpCompression.rle24,
      _ =>
        BmpCompression.values
            .take(BmpCompression.alphaBitfields.index + 1)
            .where((c) => c.code == code)
            .firstOrNull,
    };
    if (compression == BmpCompression.huffman) {
      throw const ImageFormatException(
        'BMP Huffman compression (OS/2) is not supported',
      );
    }
    if (compression == null) {
      throw ImageFormatException('BMP compression $code is not defined');
    }
    if (width <= 0 || rawHeight == 0) {
      throw const ImageFormatException('BMP image is empty');
    }
    final topDown = rawHeight < 0;
    final height = rawHeight.abs();
    if (!const [1, 2, 4, 8, 16, 24, 32, 64].contains(bits) &&
        compression != BmpCompression.jpeg &&
        compression != BmpCompression.png) {
      throw ImageFormatException(
        'BMP images of $bits bits a pixel are not '
        'supported',
      );
    }
    // Masks: in the header (version 2 and later), or after a 40-byte one.
    List<int>? masks;
    if (compression == BmpCompression.bitfields ||
        compression == BmpCompression.alphaBitfields) {
      final count = compression == BmpCompression.alphaBitfields ? 4 : 3;
      final at = headerSize >= 52 ? h + 40 : h + headerSize;
      final present = headerSize >= 56 ? 4 : (headerSize >= 52 ? 3 : count);
      if (at + 4 * present > bytes.length) {
        throw const ImageFormatException('BMP bit field masks are truncated');
      }
      masks = [
        for (var i = 0; i < present; i++)
          view.getUint32(at + 4 * i, Endian.little),
        if (present == 3) 0,
      ];
    } else if (headerSize >= 56 && (bits == 16 || bits == 32)) {
      // An alpha mask a version 3+ header gives without bit fields.
      final alpha = view.getUint32(h + 52, Endian.little);
      if (alpha != 0) {
        masks = bits == 16
            ? [0x7c00, 0x03e0, 0x001f, alpha]
            : [0xff0000, 0x00ff00, 0x0000ff, alpha];
      }
    }
    // The palette: after the header (and masks given after it).
    Uint8List? palette;
    if (bits <= 8 &&
        compression != BmpCompression.jpeg &&
        compression != BmpCompression.png) {
      final entry = core ? 3 : 4;
      var at = h + headerSize;
      if (headerSize == 40 && masks != null) at += 4 * (masks.length);
      final used = core ? 0 : view.getUint32(h + 32, Endian.little);
      var count = used == 0 || used > 1 << bits ? 1 << bits : used;
      final end = dataOffset > at && dataOffset <= bytes.length
          ? dataOffset
          : bytes.length;
      if (at + count * entry > end) count = (end - at) ~/ entry;
      if (count <= 0) {
        throw const ImageFormatException('BMP palette is missing');
      }
      // RGB triples, black past the file's entries.
      palette = Uint8List(3 << bits);
      for (var i = 0; i < count; i++) {
        palette[3 * i] = bytes[at + entry * i + 2];
        palette[3 * i + 1] = bytes[at + entry * i + 1];
        palette[3 * i + 2] = bytes[at + entry * i];
      }
    }
    // An embedded profile (version 5: `MBED`, at an offset from the
    // header).
    Uint8List? iccProfile;
    if (headerSize >= 124 &&
        view.getUint32(h + 56, Endian.little) == 0x4d424544) {
      final at = h + view.getUint32(h + 112, Endian.little);
      final size = view.getUint32(h + 116, Endian.little);
      if (size > 0 && at + size <= bytes.length) {
        iccProfile = Uint8List.sublistView(bytes, at, at + size);
      }
    }
    if (dataOffset >= bytes.length) {
      throw const ImageFormatException('BMP pixel data is missing');
    }
    return BmpFile._(
      bytes,
      width: width,
      height: height,
      topDown: topDown,
      bitsPerPixel: bits,
      compression: compression,
      dataOffset: dataOffset,
      palette: palette,
      masks: masks,
      iccProfile: iccProfile,
    );
  }

  @override
  ImageFormat get format => ImageFormat.bmp;

  @override
  final int width;

  @override
  final int height;

  /// Whether the rows are stored top to bottom (the height is negative).
  final bool topDown;

  /// The bits a pixel.
  final int bitsPerPixel;

  /// How the pixels are stored.
  final BmpCompression compression;

  /// Where the pixels start.
  final int dataOffset;

  /// The palette of an indexed image: RGB triples, as many as its bits
  /// allow (black past the file's).
  final Uint8List? palette;

  /// The red, green, blue and alpha masks of 16- and 32-bit pixels (alpha
  /// 0: none), when the file gives them.
  final List<int>? masks;

  @override
  final Uint8List? iccProfile;

  /// Whether the image decodes to palette indices.
  bool get _indexed => palette != null;

  @override
  ColorModel get colorModel => switch (compression) {
    BmpCompression.png || BmpCompression.jpeg => _embedded.colorModel,
    _ => _indexed ? ColorModel.indexed : ColorModel.rgb,
  };

  @override
  int get bitDepth => switch (compression) {
    BmpCompression.png || BmpCompression.jpeg => _embedded.bitDepth,
    BmpCompression.rle4 || BmpCompression.rle8 => 8,
    _ when bitsPerPixel == 64 => 16,
    _ => _indexed ? bitsPerPixel : 8,
  };

  late final ImageFile _embedded = switch (compression) {
    BmpCompression.png => PngFile.read(
      Uint8List.sublistView(bytes, dataOffset),
    ),
    _ => JpegFile.read(Uint8List.sublistView(bytes, dataOffset)),
  };

  @override
  Raster decode() {
    _checkSize();
    switch (compression) {
      case BmpCompression.png:
      case BmpCompression.jpeg:
        return _embedded.decode();
      case BmpCompression.rle4:
      case BmpCompression.rle8:
        return _decodeRle();
      case BmpCompression.rle24:
        return _decodeRle24();
      case BmpCompression.huffman:
        throw const ImageFormatException(
          'BMP Huffman compression (OS/2) is not supported',
        );
      case BmpCompression.none when bitsPerPixel == 64:
        return _decode64();
      case BmpCompression.none:
      case BmpCompression.bitfields:
      case BmpCompression.alphaBitfields:
        return _indexed ? _decodeIndexed() : _decodeDirect();
    }
  }

  /// The bytes of a stored row: padded to four.
  int get _stride => ((width * bitsPerPixel + 31) >> 5) << 2;

  /// Where the stored row of image row [y] starts.
  int _rowAt(int y) => dataOffset + (topDown ? y : height - 1 - y) * _stride;

  Raster _decodeIndexed() {
    final rowBytes = (width * bitsPerPixel + 7) >> 3;
    final samples = Uint8List(rowBytes * height);
    for (var y = 0; y < height; y++) {
      final from = _rowAt(y);
      final available = math.min(rowBytes, bytes.length - from);
      if (available <= 0) break;
      samples.setRange(y * rowBytes, y * rowBytes + available, bytes, from);
    }
    return Raster(
      width: width,
      height: height,
      colorModel: ColorModel.indexed,
      bitDepth: bitsPerPixel,
      samples: samples,
      palette: palette,
      iccProfile: iccProfile,
    );
  }

  Raster _decodeRle() {
    final (indices, set) = rleDecodeBmp(
      Uint8List.sublistView(bytes, dataOffset),
      width,
      height,
      compression == BmpCompression.rle8 ? 8 : 4,
      topDown: topDown,
    );
    var palette = this.palette!;
    Transparency? transparency;
    if (set != null) {
      // Unset pixels transparent: under an index past the palette's
      // entries, else (all 256 in use) an alpha channel.
      if (palette.length < 768) {
        final key = palette.length ~/ 3;
        palette = Uint8List(palette.length + 3)..setAll(0, palette);
        for (var i = 0; i < indices.length; i++) {
          if (set[i] == 0) indices[i] = key;
        }
        transparency = ColorKey([key]);
      } else {
        for (var i = 0; i < set.length; i++) {
          set[i] = set[i] == 0 ? 0 : 0xff;
        }
        transparency = AlphaChannel(set, 8);
      }
    }
    return Raster(
      width: width,
      height: height,
      colorModel: ColorModel.indexed,
      bitDepth: 8,
      samples: indices,
      palette: palette,
      transparency: transparency,
      iccProfile: iccProfile,
    );
  }

  /// 24-bit pixels run-length encoded (OS/2 2.x): RLE8's runs, absolute
  /// runs and escapes with a blue, green and red triple for a byte.
  Raster _decodeRle24() {
    final (samples, set) = rleDecodeBmp24(
      Uint8List.sublistView(bytes, dataOffset),
      width,
      height,
      topDown: topDown,
    );
    return Raster(
      width: width,
      height: height,
      colorModel: ColorModel.rgb,
      bitDepth: 8,
      samples: samples,
      transparency: switch (set) {
        final set? => AlphaChannel(
          Uint8List.fromList([
            for (final s in set)
              if (s == 0) 0 else 0xff,
          ]),
          8,
        ),
        null => null,
      },
      iccProfile: iccProfile,
    );
  }

  /// 64-bit pixels: blue, green, red and alpha, each a signed 16-bit
  /// fixed-point number with 13 fraction bits, in linear light; as 16-bit
  /// sRGB samples and alpha, clamped to 0 to 1.
  Raster _decode64() {
    final samples = Uint8List(width * height * 6);
    final alpha = Uint8List(width * height * 2);
    final view = ByteData.sublistView(bytes);
    // The 16-bit sRGB value of each linear value 0 to 8192.
    final encode = Uint16List(8193);
    for (var i = 0; i <= 8192; i++) {
      final linear = i / 8192;
      final srgb = linear <= 0.0031308
          ? 12.92 * linear
          : 1.055 * math.pow(linear, 1 / 2.4) - 0.055;
      encode[i] = (srgb * 65535).round();
    }
    int clamp(int v) => v < 0 ? 0 : (v > 8192 ? 8192 : v);
    var opaque = true;
    for (var y = 0; y < height; y++) {
      final row = _rowAt(y);
      for (var x = 0; x < width; x++) {
        final at = row + 8 * x;
        if (at + 8 > bytes.length) break;
        final o = y * width + x;
        for (var c = 0; c < 3; c++) {
          final value =
              encode[clamp(view.getInt16(at + 2 * (2 - c), Endian.little))];
          samples[6 * o + 2 * c] = value >> 8;
          samples[6 * o + 2 * c + 1] = value & 0xff;
        }
        final a = (clamp(view.getInt16(at + 6, Endian.little)) * 65535 / 8192)
            .round();
        if (a != 65535) opaque = false;
        alpha[2 * o] = a >> 8;
        alpha[2 * o + 1] = a & 0xff;
      }
    }
    return Raster(
      width: width,
      height: height,
      colorModel: ColorModel.rgb,
      bitDepth: 16,
      samples: samples,
      transparency: opaque ? null : AlphaChannel(alpha, 16),
      iccProfile: iccProfile,
    );
  }

  Raster _decodeDirect() {
    final masks =
        this.masks ??
        switch (bitsPerPixel) {
          16 => const [0x7c00, 0x03e0, 0x001f, 0],
          _ => const [0xff0000, 0x00ff00, 0x0000ff, 0],
        };
    final channels = [for (final mask in masks) _Channel.of(mask)];
    final samples = Uint8List(width * height * 3);
    final alpha = Uint8List(width * height);
    final bytesPerPixel = bitsPerPixel >> 3;
    // A 32-bit image without masks: its fourth bytes are alpha unless
    // they are all 0.
    final guessAlpha = bitsPerPixel == 32 && this.masks == null;
    // Each channel a whole byte (the usual 32-bit layouts): bytes copied.
    // (-1: no such channel; -2: not a whole byte.)
    int byteOf(_Channel c) => c.bits == 0
        ? -1
        : c.bits == 8 && c.shift.remainder(8) == 0
        ? c.shift >> 3
        : -2;
    final offsets = [
      for (final c in channels.take(3)) byteOf(c),
      if (guessAlpha) 3 else byteOf(channels[3]),
    ];
    final whole = bitsPerPixel == 32 && !offsets.contains(-2);
    var o = 0;
    for (var y = 0; y < height && whole; y++) {
      var at = _rowAt(y);
      final [r, g, b, a] = offsets;
      for (var x = 0; x < width; x++, o++, at += 4) {
        if (at + 4 > bytes.length) break;
        samples[3 * o] = r < 0 ? 0 : bytes[at + r];
        samples[3 * o + 1] = g < 0 ? 0 : bytes[at + g];
        samples[3 * o + 2] = b < 0 ? 0 : bytes[at + b];
        if (a >= 0) alpha[o] = bytes[at + a];
      }
      o = (y + 1) * width;
    }
    for (var y = 0; y < height && !whole; y++) {
      var at = _rowAt(y);
      for (var x = 0; x < width; x++, o++, at += bytesPerPixel) {
        if (at + bytesPerPixel > bytes.length) break;
        if (bitsPerPixel == 24) {
          samples[3 * o] = bytes[at + 2];
          samples[3 * o + 1] = bytes[at + 1];
          samples[3 * o + 2] = bytes[at];
          continue;
        }
        final pixel = switch (bitsPerPixel) {
          16 => bytes[at] | bytes[at + 1] << 8,
          _ =>
            bytes[at] |
                bytes[at + 1] << 8 |
                bytes[at + 2] << 16 |
                bytes[at + 3] << 24,
        };
        samples[3 * o] = channels[0].of(pixel);
        samples[3 * o + 1] = channels[1].of(pixel);
        samples[3 * o + 2] = channels[2].of(pixel);
        if (guessAlpha) {
          alpha[o] = bytes[at + 3];
        } else if (channels[3].bits > 0) {
          alpha[o] = channels[3].of(pixel);
        }
      }
      o = (y + 1) * width;
    }
    // Alpha that is 0 everywhere is taken as no alpha (as browsers take
    // it): writers often leave the alpha bits clear.
    var opaque = true;
    var clear = true;
    if (guessAlpha || channels[3].bits > 0) {
      for (final a in alpha) {
        if (a != 0xff) opaque = false;
        if (a != 0) clear = false;
        if (!opaque && !clear) break;
      }
    }
    final hasAlpha = (guessAlpha || channels[3].bits > 0) && !clear;
    return Raster(
      width: width,
      height: height,
      colorModel: ColorModel.rgb,
      bitDepth: 8,
      samples: samples,
      transparency: hasAlpha && !opaque ? AlphaChannel(alpha, 8) : null,
      iccProfile: iccProfile,
    );
  }
}

/// A channel of a bit field pixel: its mask's shift and width, scaled to
/// 8 bits.
final class _Channel {
  factory of(int mask) {
    if (mask == 0) return const _Channel._(0, 0, 0);
    var shift = 0;
    while ((mask >> shift) & 1 == 0) {
      shift++;
    }
    var bits = 0;
    while ((mask >> (shift + bits)) & 1 == 1) {
      bits++;
    }
    return _Channel._(shift, bits, (1 << bits) - 1);
  }

  const new _(this.shift, this.bits, this.max);

  final int shift;
  final int bits;
  final int max;

  /// The channel's value in [pixel], 0 to 255: fewer bits than 8
  /// repeated to fill them (as browsers expand them), more cut to 8.
  int of(int pixel) {
    if (bits == 0) return 0;
    final value = (pixel >> shift) & max;
    if (bits >= 8) return value >> (bits - 8);
    var out = 0;
    for (var filled = 0; filled < 8; filled += bits) {
      out = out << bits | value;
    }
    return out >> (_fill(bits) - 8);
  }

  /// The bits [of] fills: a whole number of [bits]-bit copies, 8 or more.
  static int _fill(int bits) => (8 + bits - 1) ~/ bits * bits;
}
