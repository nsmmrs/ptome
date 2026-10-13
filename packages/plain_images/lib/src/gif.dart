part of 'image.dart';

/// A GIF image (87a or 89a): its first frame, on the logical screen.
///
/// The image is the logical screen's size (made larger if the first frame
/// reaches past it). What the frame doesn't cover is transparent, as are
/// its pixels of the transparent index; the background color is not
/// painted, as browsers don't. Later frames of an animation are not read.
final class GifFile extends ImageFile {
  new _(
    super.bytes, {
    required this.width,
    required this.height,
    required this.frameLeft,
    required this.frameTop,
    required this.frameWidth,
    required this.frameHeight,
    required this.interlaced,
    required this.colorTable,
    required this.transparentIndex,
    required this.minCodeSize,
    required this.dataStart,
    required this.frames,
  }) : super._();

  /// The GIF image in [bytes].
  factory read(Uint8List bytes) {
    if (bytes.length < 13 ||
        !(_startsWith(bytes, _gif87) || _startsWith(bytes, _gif89))) {
      throw const ImageFormatException('not a GIF image');
    }
    int u16(int at) => bytes[at] | bytes[at + 1] << 8;
    final screenWidth = u16(6);
    final screenHeight = u16(8);
    final packed = bytes[10];
    var at = 13;
    Uint8List? global;
    if (packed & 0x80 != 0) {
      final size = 3 << ((packed & 7) + 1);
      if (at + size > bytes.length) {
        throw const ImageFormatException('GIF color table is truncated');
      }
      global = Uint8List.sublistView(bytes, at, at + size);
      at += size;
    }
    int? transparent;
    // The first image's descriptor and data, once found.
    GifFile? first;
    var frames = 0;
    // Past the sub-blocks starting at [from]: where the next block is.
    int skipBlocks(int from) {
      var i = from;
      while (i < bytes.length) {
        final size = bytes[i];
        i += 1 + size;
        if (size == 0) return i;
      }
      return bytes.length;
    }

    while (at < bytes.length) {
      switch (bytes[at]) {
        case 0x21: // An extension.
          if (at + 2 > bytes.length) break;
          final label = bytes[at + 1];
          if (first == null &&
              label == 0xf9 &&
              at + 7 < bytes.length &&
              bytes[at + 2] >= 4) {
            // Graphic control: the transparent index, if flagged.
            transparent = bytes[at + 3] & 1 != 0 ? bytes[at + 6] : null;
          }
          at = skipBlocks(at + 2);
          continue;
        case 0x2c: // An image.
          if (at + 10 > bytes.length) {
            throw const ImageFormatException(
              'GIF image descriptor is truncated',
            );
          }
          final left = u16(at + 1);
          final top = u16(at + 3);
          final w = u16(at + 5);
          final h = u16(at + 7);
          final flags = bytes[at + 9];
          at += 10;
          var table = global;
          if (flags & 0x80 != 0) {
            final size = 3 << ((flags & 7) + 1);
            if (at + size > bytes.length) {
              throw const ImageFormatException(
                'GIF local color table is truncated',
              );
            }
            table = Uint8List.sublistView(bytes, at, at + size);
            at += size;
          }
          if (at >= bytes.length) {
            throw const ImageFormatException('GIF image data is missing');
          }
          final minCodeSize = bytes[at];
          if (minCodeSize < 1 || minCodeSize > 8) {
            throw ImageFormatException(
              'GIF LZW code size $minCodeSize is not allowed',
              offset: at,
            );
          }
          frames++;
          first ??= GifFile._(
            bytes,
            width: math.max(screenWidth, left + w),
            height: math.max(screenHeight, top + h),
            frameLeft: left,
            frameTop: top,
            frameWidth: w,
            frameHeight: h,
            interlaced: flags & 0x40 != 0,
            colorTable: table,
            transparentIndex: transparent,
            minCodeSize: minCodeSize,
            dataStart: at + 1,
            frames: 0,
          );
          at = skipBlocks(at + 1);
          continue;
        case 0x3b: // The trailer.
          at = bytes.length;
          continue;
        default:
          // Damage past the first image ends the file; before it, it is
          // an error.
          if (first != null) {
            at = bytes.length;
            continue;
          }
          throw ImageFormatException(
            'GIF block 0x${bytes[at].toRadixString(16)} is not defined',
            offset: at,
          );
      }
      break;
    }
    if (first == null) {
      throw const ImageFormatException('GIF file has no image');
    }
    if (first.width == 0 || first.height == 0) {
      throw const ImageFormatException('GIF image is empty');
    }
    return GifFile._(
      bytes,
      width: first.width,
      height: first.height,
      frameLeft: first.frameLeft,
      frameTop: first.frameTop,
      frameWidth: first.frameWidth,
      frameHeight: first.frameHeight,
      interlaced: first.interlaced,
      colorTable: first.colorTable,
      transparentIndex: first.transparentIndex,
      minCodeSize: first.minCodeSize,
      dataStart: first.dataStart,
      frames: frames,
    );
  }

  @override
  ImageFormat get format => ImageFormat.gif;

  @override
  final int width;

  @override
  final int height;

  /// The first frame's left edge on the logical screen.
  final int frameLeft;

  /// The first frame's top edge on the logical screen.
  final int frameTop;

  /// The first frame's width.
  final int frameWidth;

  /// The first frame's height.
  final int frameHeight;

  /// Whether the first frame's rows are interlaced.
  final bool interlaced;

  /// The first frame's color table (local, else global): RGB triples; null
  /// when the file has none (gray levels are used).
  final Uint8List? colorTable;

  /// The first frame's transparent index, if it has one.
  final int? transparentIndex;

  /// The roots' bits of the first frame's LZW data.
  final int minCodeSize;

  /// Where the first frame's LZW sub-blocks start.
  final int dataStart;

  /// The frames in the file (more than one in an animation).
  final int frames;

  @override
  ColorModel get colorModel => ColorModel.indexed;

  @override
  int get bitDepth => 8;

  /// The frame's palette indices, as an 8-bit indexed raster: a key for
  /// the transparent index (and for what the frame doesn't cover, an index
  /// the palette doesn't use, or an alpha channel if it uses all 256).
  @override
  Raster decode() {
    _checkSize();
    // The sub-blocks joined.
    final data = BytesBuilder(copy: false);
    var at = dataStart;
    while (at < bytes.length) {
      final size = bytes[at];
      if (size == 0) break;
      final end = math.min(at + 1 + size, bytes.length);
      data.add(Uint8List.sublistView(bytes, at + 1, end));
      at = end;
    }
    var indices = lzwDecodeGif(
      data.takeBytes(),
      minCodeSize,
      frameWidth * frameHeight,
    );
    if (interlaced) {
      indices = deinterlaceGif(indices, frameWidth, frameHeight);
    }
    // The palette, as long as the indices need (black past the table's
    // end; gray levels without a table).
    final entries = 1 << minCodeSize > 256 ? 256 : 1 << minCodeSize;
    final table = colorTable;
    final palette = Uint8List(math.max(entries, (table?.length ?? 0) ~/ 3) * 3);
    if (table != null) {
      palette.setRange(0, math.min(table.length, palette.length), table);
    } else {
      final count = palette.length ~/ 3;
      for (var i = 0; i < count; i++) {
        final level = count == 1 ? 0 : i * 255 ~/ (count - 1);
        palette[3 * i] = palette[3 * i + 1] = palette[3 * i + 2] = level;
      }
    }
    final covers =
        frameLeft == 0 &&
        frameTop == 0 &&
        frameWidth == width &&
        frameHeight == height;
    if (covers) {
      return Raster(
        width: width,
        height: height,
        colorModel: ColorModel.indexed,
        bitDepth: 8,
        samples: indices,
        palette: palette,
        transparency: switch (transparentIndex) {
          final index? => ColorKey([index]),
          null => null,
        },
      );
    }
    // The frame on the screen; the rest transparent: under the
    // transparent index, else an index past the palette's entries, else
    // (all 256 in use) an alpha channel.
    var key = transparentIndex;
    var widened = palette;
    if (key == null && palette.length < 768) {
      key = palette.length ~/ 3;
      widened = Uint8List(palette.length + 3)..setAll(0, palette);
    }
    final samples = Uint8List(width * height);
    final alpha = key == null ? Uint8List(width * height) : null;
    if (key != null) samples.fillRange(0, samples.length, key);
    final rows = math.min(frameHeight, height - frameTop);
    final columns = math.min(frameWidth, width - frameLeft);
    for (var y = 0; y < rows; y++) {
      final to = (frameTop + y) * width + frameLeft;
      samples.setRange(to, to + columns, indices, y * frameWidth);
      alpha?.fillRange(to, to + columns, 0xff);
    }
    return Raster(
      width: width,
      height: height,
      colorModel: ColorModel.indexed,
      bitDepth: 8,
      samples: samples,
      palette: widened,
      transparency: key != null ? ColorKey([key]) : AlphaChannel(alpha!, 8),
    );
  }
}
