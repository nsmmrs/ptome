part of 'image.dart';

/// The color type of a PNG image (ISO/IEC 15948, 11.2.2).
enum PngColorType {
  /// Gray samples.
  gray(0, 1),

  /// Red, green and blue samples.
  rgb(2, 3),

  /// Palette indices.
  palette(3, 1),

  /// Gray and alpha samples.
  grayAlpha(4, 2),

  /// Red, green, blue and alpha samples.
  rgba(6, 4);

  new(this.code, this.channels);

  /// The color type's code in the file.
  final int code;

  /// The samples per pixel.
  final int channels;

  /// Whether pixels carry an alpha sample.
  bool get hasAlpha => this == grayAlpha || this == rgba;

  /// The bit depths the color type allows.
  List<int> get bitDepths => switch (this) {
    gray => const [1, 2, 4, 8, 16],
    palette => const [1, 2, 4, 8],
    rgb || grayAlpha || rgba => const [8, 16],
  };
}

/// A PNG image (ISO/IEC 15948): its chunks read, its image data kept as
/// the zlib stream it is.
final class PngFile extends ImageFile {
  new _(
    super.bytes, {
    required this.width,
    required this.height,
    required this.bitDepth,
    required this.colorType,
    required this.interlaced,
    required this.data,
    required this.palette,
    required this.transparency,
    required this.iccProfile,
    required this.orientation,
  }) : super._();

  /// The PNG image in [bytes].
  factory read(Uint8List bytes) {
    if (!_startsWith(bytes, _pngSignature)) {
      throw const ImageFormatException('not a PNG image');
    }
    final view = ByteData.sublistView(bytes);
    ByteData? header;
    Uint8List? palette;
    Uint8List? transparency;
    Uint8List? iccProfile;
    var orientation = 1;
    final data = BytesBuilder(copy: false);
    var at = 8;
    while (at + 12 <= bytes.length) {
      final length = view.getUint32(at);
      final type = String.fromCharCodes(bytes, at + 4, at + 8);
      final start = at + 8;
      final end = start + length;
      if (end + 4 > bytes.length) {
        throw ImageFormatException('PNG chunk $type is truncated', offset: at);
      }
      final chunk = Uint8List.sublistView(bytes, start, end);
      // A critical chunk must be intact; ancillary ones are only hints.
      if (_critical.contains(type) &&
          crc32(bytes, start: at + 4, end: end) != view.getUint32(end)) {
        throw ImageFormatException(
          'PNG chunk $type is damaged (CRC mismatch)',
          offset: at,
        );
      }
      switch (type) {
        case 'IHDR' when length >= 13:
          header = ByteData.sublistView(chunk);
        case 'PLTE':
          palette = chunk;
        case 'tRNS':
          transparency = chunk;
        case 'iCCP':
          final nameEnd = chunk.indexOf(0);
          if (nameEnd > 0 && nameEnd + 2 <= chunk.length) {
            try {
              iccProfile = zlibDecode(chunk.sublist(nameEnd + 2));
            } on FormatException {
              // A damaged profile: fall back to the device color space.
            }
          }
        case 'eXIf':
          orientation = exifOrientation(chunk);
        case 'IDAT':
          data.add(chunk);
        case 'IEND':
          at = bytes.length;
          continue;
      }
      at = end + 4;
    }
    if (header == null) {
      throw const ImageFormatException('PNG image has no IHDR chunk');
    }
    if (data.isEmpty) {
      throw const ImageFormatException('PNG image has no IDAT chunk');
    }
    final width = header.getUint32(0);
    final height = header.getUint32(4);
    final bitDepth = header.getUint8(8);
    final code = header.getUint8(9);
    final colorType = PngColorType.values
        .where((t) => t.code == code)
        .firstOrNull;
    if (colorType == null) {
      throw ImageFormatException('PNG color type $code is not defined');
    }
    if (!colorType.bitDepths.contains(bitDepth)) {
      throw ImageFormatException(
        'PNG bit depth $bitDepth is not allowed for color type $code',
      );
    }
    if (width == 0 || height == 0) {
      throw const ImageFormatException('PNG image is empty');
    }
    if (colorType == PngColorType.palette && palette == null) {
      throw const ImageFormatException('PNG palette image has no palette');
    }
    final interlace = header.getUint8(12);
    if (interlace > 1) {
      throw ImageFormatException(
        'PNG interlace method $interlace is not defined',
      );
    }
    return PngFile._(
      bytes,
      width: width,
      height: height,
      bitDepth: bitDepth,
      colorType: colorType,
      interlaced: interlace == 1,
      data: data.takeBytes(),
      palette: colorType == PngColorType.palette ? palette : null,
      transparency: colorType.hasAlpha ? null : transparency,
      iccProfile: iccProfile,
      orientation: orientation,
    );
  }

  @override
  ImageFormat get format => ImageFormat.png;

  @override
  final int width;

  @override
  final int height;

  /// The bits per sample.
  @override
  final int bitDepth;

  /// The color type.
  final PngColorType colorType;

  @override
  ColorModel get colorModel => switch (colorType) {
    PngColorType.gray || PngColorType.grayAlpha => ColorModel.gray,
    PngColorType.rgb || PngColorType.rgba => ColorModel.rgb,
    PngColorType.palette => ColorModel.indexed,
  };

  /// Whether the image is interlaced (Adam7).
  final bool interlaced;

  /// The image data (the IDAT chunks, a zlib stream of filtered rows).
  final Uint8List data;

  /// The palette (`PLTE`) of a palette image: RGB triples.
  final Uint8List? palette;

  /// The `tRNS` chunk: palette alpha, or the transparent color.
  final Uint8List? transparency;

  /// The embedded ICC profile (`iCCP`), decompressed.
  @override
  final Uint8List? iccProfile;

  @override
  final int orientation;

  /// The transparent color of a gray or RGB image's `tRNS` chunk, if any.
  ColorKey? get colorKey {
    final transparency = this.transparency;
    if (transparency == null || colorType == PngColorType.palette) {
      return null;
    }
    final view = ByteData.sublistView(transparency);
    final samples = colorType.channels;
    if (transparency.length < 2 * samples) return null;
    final limit = (1 << bitDepth) - 1;
    return ColorKey([
      for (var i = 0; i < samples; i++) view.getUint16(2 * i) & limit,
    ]);
  }

  /// The samples, alpha split out into an [AlphaChannel] (null when every
  /// pixel is opaque), a palette's alpha (`tRNS`) as an 8-bit
  /// [AlphaChannel], a gray or RGB image's transparent color as a
  /// [ColorKey]. [inflate] decompresses the image data (by default,
  /// plain_compression's [zlibDecode]).
  @override
  Raster decode({Uint8List Function(Uint8List data)? inflate}) {
    _checkSize();
    final Uint8List inflated;
    try {
      inflated = (inflate ?? zlibDecode)(data);
    } on FormatException catch (error) {
      throw ImageFormatException('PNG image data is damaged: ${error.message}');
    }
    final layout = PngLayout(width, height, colorType.channels, bitDepth);
    final Uint8List pixels;
    try {
      pixels = unfilterImage(inflated, layout, interlaced: interlaced);
    } on FormatException catch (error) {
      throw ImageFormatException(error.message);
    }
    Raster raster(Uint8List samples, Transparency? transparency) => Raster(
      width: width,
      height: height,
      colorModel: colorModel,
      bitDepth: bitDepth,
      samples: samples,
      palette: palette,
      transparency: transparency,
      iccProfile: iccProfile,
      orientation: orientation,
    );
    if (colorType.hasAlpha) {
      final (color, alpha, opaque) = _splitAlpha(
        pixels,
        colorType.channels - 1,
      );
      return raster(color, opaque ? null : AlphaChannel(alpha, bitDepth));
    }
    if (colorType == PngColorType.palette && transparency != null) {
      return raster(pixels, switch (_paletteAlpha(
        pixels,
        layout.rowBytes(width),
      )) {
        final alpha? => AlphaChannel(alpha, 8),
        null => null,
      });
    }
    return raster(pixels, colorKey);
  }

  /// [pixels] split into color samples and alpha samples, and whether
  /// every alpha byte is 0xff.
  (Uint8List, Uint8List, bool) _splitAlpha(
    Uint8List pixels,
    int colorChannels,
  ) {
    final sample = bitDepth >> 3;
    final count = width * height;
    final colorBytes = colorChannels * sample;
    final color = Uint8List(count * colorBytes);
    final alpha = Uint8List(count * sample);
    var from = 0;
    var c = 0;
    // The AND of every alpha byte: 0xff when all are.
    var all = 0xff;
    if (sample == 1 && colorChannels == 3) {
      // (8-bit RGBA, the usual.)
      for (var p = 0; p < count; p++, from += 4, c += 3) {
        color[c] = pixels[from];
        color[c + 1] = pixels[from + 1];
        color[c + 2] = pixels[from + 2];
        final value = pixels[from + 3];
        alpha[p] = value;
        all &= value;
      }
      return (color, alpha, all == 0xff);
    }
    var a = 0;
    for (var p = 0; p < count; p++) {
      for (var k = 0; k < colorBytes; k++) {
        color[c++] = pixels[from++];
      }
      for (var k = 0; k < sample; k++) {
        final value = pixels[from++];
        alpha[a++] = value;
        all &= value;
      }
    }
    return (color, alpha, all == 0xff);
  }

  /// The alpha of each pixel of a palette image, from the palette's alpha
  /// in `tRNS` (opaque past its end); null when every pixel is opaque.
  Uint8List? _paletteAlpha(Uint8List pixels, int stride) {
    final table = transparency!;
    final alpha = Uint8List(width * height);
    final mask = (1 << bitDepth) - 1;
    var all = 0xff;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final bit = x * bitDepth;
        final index =
            (pixels[y * stride + (bit >> 3)] >> (8 - bitDepth - (bit & 7))) &
            mask;
        final value = index < table.length ? table[index] : 0xff;
        alpha[y * width + x] = value;
        all &= value;
      }
    }
    return all == 0xff ? null : alpha;
  }
}

const Set<String> _critical = {'IHDR', 'PLTE', 'IDAT', 'IEND'};
