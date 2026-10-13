part of 'image.dart';

/// A WebP image (RFC 9649): lossy (VP8, with an `ALPH` chunk's alpha) or
/// lossless (VP8L), simple or extended (`VP8X`, with its ICC profile and
/// EXIF metadata); of an animation, the first frame on the canvas.
///
/// Lossy images decode as libwebp's `dwebp` decodes them by default
/// (its YUV to RGB conversion and "fancy" chroma upsampling), to the
/// byte; what the first frame of an animation doesn't cover is
/// transparent.
final class WebPFile extends ImageFile {
  new _(
    super.bytes, {
    required this.width,
    required this.height,
    required this.lossless,
    required this.alpha,
    required this.frames,
    required this.iccProfile,
    required this.orientation,
    required this.frameLeft,
    required this.frameTop,
    required this.frameWidth,
    required this.frameHeight,
    required this.image,
    required this.alphaChunk,
  }) : super._();

  /// The WebP image in [bytes].
  factory read(Uint8List bytes) {
    final view = ByteData.sublistView(bytes);
    if (bytes.length < 20 ||
        String.fromCharCodes(bytes, 0, 4) != 'RIFF' ||
        String.fromCharCodes(bytes, 8, 12) != 'WEBP') {
      throw const ImageFormatException('not a WebP image');
    }
    // The chunks, as far as the file and the RIFF size go.
    final riffEnd = math.min(
      bytes.length,
      8 + view.getUint32(4, Endian.little),
    );
    final chunks = <(String, Uint8List)>[];
    for (var at = 12; at + 8 <= riffEnd;) {
      final type = String.fromCharCodes(bytes, at, at + 4);
      final size = view.getUint32(at + 4, Endian.little);
      final end = math.min(at + 8 + size, riffEnd);
      chunks.add((type, Uint8List.sublistView(bytes, at + 8, end)));
      at = at + 8 + size + (size & 1);
    }
    if (chunks.isEmpty) {
      throw const ImageFormatException('WebP file has no chunks');
    }
    Uint8List? iccProfile;
    var orientation = 1;
    int? canvasWidth;
    int? canvasHeight;
    var frames = 0;
    // The first frame: where it goes and its chunks.
    (int, int, Uint8List?, Uint8List)? first;
    Uint8List? alphaChunk;
    Uint8List? still;
    for (final (type, data) in chunks) {
      switch (type) {
        case 'VP8X' when data.length >= 10:
          canvasWidth = 1 + (data[4] | data[5] << 8 | data[6] << 16);
          canvasHeight = 1 + (data[7] | data[8] << 8 | data[9] << 16);
        case 'ICCP':
          iccProfile = data;
        case 'EXIF':
          // (Some writers keep JPEG's "Exif\0\0" before the TIFF data.)
          orientation = exifOrientation(
            data.length > 6 && String.fromCharCodes(data, 0, 4) == 'Exif'
                ? Uint8List.sublistView(data, 6)
                : data,
          );
        case 'ALPH':
          alphaChunk ??= data;
        case 'VP8 ' || 'VP8L':
          still ??= data;
        case 'ANMF' when data.length >= 16:
          frames++;
          if (first == null) {
            final x = 2 * (data[0] | data[1] << 8 | data[2] << 16);
            final y = 2 * (data[3] | data[4] << 8 | data[5] << 16);
            // The frame's own chunks.
            Uint8List? frameAlpha;
            Uint8List? frameImage;
            final frameView = ByteData.sublistView(data);
            for (var at = 16; at + 8 <= data.length;) {
              final sub = String.fromCharCodes(data, at, at + 4);
              final size = frameView.getUint32(at + 4, Endian.little);
              final end = math.min(at + 8 + size, data.length);
              final payload = Uint8List.sublistView(data, at + 8, end);
              if (sub == 'ALPH') frameAlpha ??= payload;
              if (sub == 'VP8 ' || sub == 'VP8L') frameImage ??= payload;
              at = at + 8 + size + (size & 1);
            }
            if (frameImage != null) first = (x, y, frameAlpha, frameImage);
          }
      }
    }
    final (left, top, alpha, image) = switch (first) {
      final frame? => frame,
      null => switch (still) {
        final data? => (0, 0, alphaChunk, data),
        null => throw const ImageFormatException('WebP file has no image data'),
      },
    };
    final lossless = vp8lHeader(image);
    final lossy = lossless == null ? vp8Size(image) : null;
    final size = switch ((lossless, lossy)) {
      ((:final width, :final height, alpha: _), _) => (width, height),
      (null, (:final width, :final height)?) => (width, height),
      _ => throw const ImageFormatException(
        'WebP image data is neither VP8 nor VP8L',
      ),
    };
    final (frameWidth, frameHeight) = size;
    if (frameWidth == 0 || frameHeight == 0) {
      throw const ImageFormatException('WebP image is empty');
    }
    return WebPFile._(
      bytes,
      width: math.max(canvasWidth ?? frameWidth, left + frameWidth),
      height: math.max(canvasHeight ?? frameHeight, top + frameHeight),
      lossless: lossless != null,
      alpha: alpha != null || (lossless?.alpha ?? false),
      frames: math.max(frames, 1),
      iccProfile: iccProfile,
      orientation: orientation,
      frameLeft: left,
      frameTop: top,
      frameWidth: frameWidth,
      frameHeight: frameHeight,
      image: image,
      alphaChunk: lossless == null ? alpha : null,
    );
  }

  @override
  ImageFormat get format => ImageFormat.webp;

  @override
  final int width;

  @override
  final int height;

  /// Whether the (first) image is lossless (VP8L), not lossy (VP8).
  final bool lossless;

  /// Whether the image says it has alpha (an `ALPH` chunk, or the VP8L
  /// header's hint).
  final bool alpha;

  /// The frames in the file (more than one in an animation).
  final int frames;

  @override
  final Uint8List? iccProfile;

  @override
  final int orientation;

  /// The first frame's left edge on the canvas.
  final int frameLeft;

  /// The first frame's top edge on the canvas.
  final int frameTop;

  /// The first frame's width.
  final int frameWidth;

  /// The first frame's height.
  final int frameHeight;

  /// The first frame's VP8 or VP8L data.
  final Uint8List image;

  /// The first frame's `ALPH` chunk (a lossy image's alpha), if any.
  final Uint8List? alphaChunk;

  @override
  ColorModel get colorModel => ColorModel.rgb;

  @override
  int get bitDepth => 8;

  /// 8-bit RGB samples, and alpha unless every pixel is opaque.
  @override
  Raster decode() {
    _checkSize();
    final Uint8List rgba;
    if (lossless) {
      final argb = decodeVp8l(image).argb;
      rgba = Uint8List(frameWidth * frameHeight * 4);
      for (var i = 0; i < argb.length; i++) {
        final p = argb[i];
        rgba[4 * i] = (p >> 16) & 0xff;
        rgba[4 * i + 1] = (p >> 8) & 0xff;
        rgba[4 * i + 2] = p & 0xff;
        rgba[4 * i + 3] = (p >> 24) & 0xff;
      }
    } else {
      final frame = decodeVp8(image);
      rgba = yuv420ToRgba(
        frameWidth,
        frameHeight,
        frame.y,
        frame.yStride,
        frame.u,
        frame.v,
        frame.uvStride,
      );
      if (alphaChunk case final chunk?) {
        final alpha = decodeWebPAlpha(chunk, frameWidth, frameHeight);
        for (var i = 0; i < alpha.length; i++) {
          rgba[4 * i + 3] = alpha[i];
        }
      }
    }
    // The frame on the canvas, the rest transparent.
    final samples = Uint8List(width * height * 3);
    final alpha = Uint8List(width * height);
    var opaque = frameWidth == width && frameHeight == height;
    for (var y = 0; y < frameHeight; y++) {
      var o = (frameTop + y) * width + frameLeft;
      for (var x = 0; x < frameWidth; x++, o++) {
        final i = (y * frameWidth + x) * 4;
        samples[3 * o] = rgba[i];
        samples[3 * o + 1] = rgba[i + 1];
        samples[3 * o + 2] = rgba[i + 2];
        final a = rgba[i + 3];
        alpha[o] = a;
        if (a != 0xff) opaque = false;
      }
    }
    return Raster(
      width: width,
      height: height,
      colorModel: ColorModel.rgb,
      bitDepth: 8,
      samples: samples,
      transparency: opaque ? null : AlphaChannel(alpha, 8),
      iccProfile: iccProfile,
      orientation: orientation,
    );
  }
}

/// The alpha of a [width] by [height] lossy image from its `ALPH` chunk
/// [data] (RFC 9649, 5.2.3): raw or lossless-compressed (the green
/// channel of a VP8L image without its header), then unfiltered.
Uint8List decodeWebPAlpha(Uint8List data, int width, int height) {
  if (data.isEmpty) throw const ImageFormatException('WebP alpha is empty');
  final header = data[0];
  final compression = header & 3;
  final filter = (header >> 2) & 3;
  final count = width * height;
  final Uint8List filtered;
  switch (compression) {
    case 0:
      if (data.length - 1 < count) {
        throw const ImageFormatException('WebP alpha is truncated');
      }
      filtered = Uint8List.sublistView(data, 1, 1 + count);
    case 1:
      final argb = decodeVp8l(
        Uint8List.sublistView(data, 1),
        width: width,
        height: height,
      ).argb;
      filtered = Uint8List(count);
      for (var i = 0; i < count; i++) {
        filtered[i] = (argb[i] >> 8) & 0xff;
      }
    default:
      throw ImageFormatException(
        'WebP alpha compression $compression is not defined',
      );
  }
  if (filter == 0) return Uint8List.fromList(filtered);
  final out = Uint8List(count);
  for (var y = 0; y < height; y++) {
    final row = y * width;
    final above = row - width;
    if (y == 0 || filter == 1) {
      // Horizontal: from the left; a row's first from the one above
      // (the first row's from 0).
      var prediction = y == 0 ? 0 : out[above];
      for (var x = 0; x < width; x++) {
        prediction = (prediction + filtered[row + x]) & 0xff;
        out[row + x] = prediction;
      }
    } else if (filter == 2) {
      // Vertical.
      for (var x = 0; x < width; x++) {
        out[row + x] = (out[above + x] + filtered[row + x]) & 0xff;
      }
    } else {
      // Gradient: left + above − above left, clamped.
      var left = out[above];
      var topLeft = out[above];
      for (var x = 0; x < width; x++) {
        final top = out[above + x];
        var prediction = left + top - topLeft;
        prediction = prediction < 0 ? 0 : (prediction > 255 ? 255 : prediction);
        left = (prediction + filtered[row + x]) & 0xff;
        topLeft = top;
        out[row + x] = left;
      }
    }
  }
  return out;
}
