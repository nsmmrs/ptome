part of 'image.dart';

/// A JPEG image (ISO/IEC 10918-1), read as far as its frame header.
final class JpegFile extends ImageFile {
  new _(
    super.bytes, {
    required this.width,
    required this.height,
    required this.components,
    required this.precision,
    required this.progressive,
    required this.adobe,
    required this.orientation,
    required this.iccProfile,
    required this.lossless,
    required this.arithmetic,
  }) : super._();

  /// The JPEG image in [bytes].
  factory read(Uint8List bytes) {
    if (bytes.length < 4 || bytes[0] != 0xff || bytes[1] != 0xd8) {
      throw const ImageFormatException('not a JPEG image');
    }
    final view = ByteData.sublistView(bytes);
    var adobe = false;
    var orientation = 1;
    // The ICC profile's chunks (APP2 "ICC_PROFILE"), by sequence number.
    final iccChunks = <int, Uint8List>{};
    var at = 2;
    while (at + 4 <= bytes.length) {
      if (bytes[at] != 0xff) {
        throw ImageFormatException(
          'JPEG marker expected at byte $at',
          offset: at,
        );
      }
      final marker = bytes[at + 1];
      if (marker == 0xff) {
        at += 1; // fill byte
        continue;
      }
      at += 2;
      if (marker == 0x01 || (marker >= 0xd0 && marker <= 0xd8)) continue;
      if (marker == 0xd9 || marker == 0xda) break;
      final length = view.getUint16(at);
      final end = at + length;
      if (length < 2 || end > bytes.length) break;
      final segment = Uint8List.sublistView(bytes, at + 2, end);
      if (_isStartOfFrame(marker)) {
        if (segment.length < 6) break;
        final height = view.getUint16(at + 3);
        if (height == 0) {
          throw const ImageFormatException(
            'JPEG images whose height is set by a DNL marker are not '
            'supported',
          );
        }
        return JpegFile._(
          bytes,
          width: view.getUint16(at + 5),
          height: height,
          components: segment[5],
          precision: segment[0],
          progressive: marker & 0x03 == 0x02,
          adobe: adobe,
          orientation: orientation,
          iccProfile: _profile(iccChunks),
          lossless: marker & 0x03 == 0x03,
          arithmetic: marker >= 0xc9,
        );
      }
      if (marker == 0xee && _startsWith(segment, _adobe)) adobe = true;
      if (marker == 0xe1 && _startsWith(segment, _exif)) {
        orientation = exifOrientation(Uint8List.sublistView(segment, 6));
      }
      if (marker == 0xe2 &&
          _startsWith(segment, _iccProfile) &&
          segment.length > 14) {
        iccChunks[segment[12]] = Uint8List.sublistView(segment, 14);
      }
      at = end;
    }
    throw const ImageFormatException('JPEG image has no frame header');
  }

  @override
  ImageFormat get format => ImageFormat.jpeg;

  @override
  final int width;

  @override
  final int height;

  /// The color components: 1 (gray), 3 (YCbCr or RGB) or 4 (CMYK or
  /// YCCK).
  final int components;

  /// The bits per sample in the file (8, or 12 in extended JPEG; 2 to 16
  /// in lossless JPEG).
  final int precision;

  /// Whether the image is lossless JPEG (not DCT-based).
  final bool lossless;

  /// Whether the image is arithmetic-coded (not Huffman-coded).
  final bool arithmetic;

  @override
  final Uint8List? iccProfile;

  @override
  int get bitDepth => precision > 8 ? 16 : 8;

  @override
  ColorModel get colorModel => switch (components) {
    1 => ColorModel.gray,
    4 => ColorModel.cmyk,
    _ => ColorModel.rgb,
  };

  /// Whether the image is progressive.
  final bool progressive;

  /// Whether the file has an Adobe (APP14) segment, whose CMYK data is
  /// stored inverted.
  final bool adobe;

  @override
  final int orientation;

  /// The samples as libjpeg decodes them by default (its accurate
  /// integer inverse DCT, "fancy" chroma upsampling and YCbCr to RGB
  /// conversion): gray, RGB or CMYK (an Adobe file's inverted CMYK
  /// turned back), 8 bits, or 16 for more precise samples (scaled to
  /// fill them).
  @override
  Raster decode() {
    _checkSize();
    final pixels = decodeJpeg(bytes);
    final channels = pixels.channels;
    final source = pixels.samples;
    final top = (1 << pixels.precision) - 1;
    final depth = bitDepth;
    final outTop = depth == 16 ? 65535 : 255;
    final invert = channels == 4 && pixels.adobe;
    final Uint8List samples;
    if (depth == 8 && top == 255) {
      samples = Uint8List(source.length);
      for (var i = 0; i < source.length; i++) {
        samples[i] = invert ? 255 - source[i] : source[i];
      }
    } else {
      // Scaled to the raster's depth, rounded.
      samples = Uint8List(source.length * (depth == 16 ? 2 : 1));
      for (var i = 0; i < source.length; i++) {
        var v = (source[i] * outTop + (top >> 1)) ~/ top;
        if (invert) v = outTop - v;
        if (depth == 16) {
          samples[2 * i] = v >> 8;
          samples[2 * i + 1] = v & 0xff;
        } else {
          samples[i] = v;
        }
      }
    }
    return Raster(
      width: pixels.width,
      height: pixels.height,
      colorModel: colorModel,
      bitDepth: depth,
      samples: samples,
      iccProfile: iccProfile,
      orientation: orientation,
    );
  }

  /// The ICC profile of its [chunks], in order, if they are all there.
  static Uint8List? _profile(Map<int, Uint8List> chunks) {
    if (chunks.isEmpty) return null;
    final out = BytesBuilder(copy: false);
    for (var sequence = 1; sequence <= chunks.length; sequence++) {
      final chunk = chunks[sequence];
      if (chunk == null) return null;
      out.add(chunk);
    }
    return out.takeBytes();
  }

  static bool _isStartOfFrame(int marker) =>
      marker >= 0xc0 &&
      marker <= 0xcf &&
      marker != 0xc4 &&
      marker != 0xc8 &&
      marker != 0xcc;

  static final List<int> _adobe = 'Adobe'.codeUnits;
  static final List<int> _exif = [0x45, 0x78, 0x69, 0x66, 0, 0];
  static final List<int> _iccProfile = 'ICC_PROFILE\u0000'.codeUnits;
}
