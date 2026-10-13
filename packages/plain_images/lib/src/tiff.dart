part of 'image.dart';

/// How a TIFF image's data is compressed (TIFF 6.0 and its extensions).
enum TiffCompression {
  /// Not compressed.
  none(1, 'none'),

  /// CCITT Modified Huffman, rows byte-aligned (TIFF's "CCITT RLE").
  ccittRle(2, 'CCITT RLE'),

  /// CCITT Group 3 (T.4).
  ccittGroup3(3, 'CCITT Group 3'),

  /// CCITT Group 4 (T.6).
  ccittGroup4(4, 'CCITT Group 4'),

  /// LZW.
  lzw(5, 'LZW'),

  /// The original TIFF 6.0 JPEG ("old-style").
  oldJpeg(6, 'old-style JPEG'),

  /// JPEG (TIFF Technical Note 2).
  jpeg(7, 'JPEG'),

  /// Deflate (zlib).
  deflate(8, 'Deflate'),

  /// Deflate, under its earlier code.
  adobeDeflate(32946, 'Deflate'),

  /// PackBits.
  packBits(32773, 'PackBits'),

  /// LZMA2.
  lzma(34925, 'LZMA'),

  /// Zstandard.
  zstd(50000, 'Zstandard'),

  /// WebP.
  webp(50001, 'WebP'),

  /// JPEG 2000.
  jpeg2000(34712, 'JPEG 2000'),

  /// JBIG.
  jbig(34661, 'JBIG');

  new(this.code, this.label);

  /// The compression's code in the file.
  final int code;

  /// Its usual name.
  final String label;
}

/// A TIFF image (TIFF 6.0, and BigTIFF): its first page.
///
/// Strips or tiles, chunky or planar samples; bilevel, gray, palette,
/// RGB, CMYK, YCbCr and CIE L*a*b* images of 1 to 16 bits a sample (and
/// 32-bit or floating-point ones, scaled to 16 bits), with alpha
/// (associated alpha unpremultiplied); compressed by PackBits, LZW,
/// Deflate, CCITT RLE, Group 3 or Group 4, JPEG or WebP, with the
/// horizontal or floating-point predictor. Later pages are counted, not
/// read.
final class TiffFile extends ImageFile {
  new _(
    super.bytes, {
    required this.width,
    required this.height,
    required this.compression,
    required this.photometric,
    required this.bitsPerSample,
    required this.samplesPerPixel,
    required this.sampleFormat,
    required this.planar,
    required this.predictor,
    required this.extraSamples,
    required this.colorMap,
    required this.tileWidth,
    required this.tileHeight,
    required this.offsets,
    required this.byteCounts,
    required this.lsbFirst,
    required this.t4Options,
    required this.jpegTables,
    required this.ycbcrSubsampling,
    required this.referenceBlackWhite,
    required this.ycbcrCoefficients,
    required this.iccProfile,
    required this.orientation,
    required this.pages,
    required this.littleEndian,
    required this.tiled,
  }) : super._();

  /// The TIFF image in [bytes].
  factory read(Uint8List bytes) {
    if (bytes.length < 8) throw const ImageFormatException('not a TIFF image');
    final little = bytes[0] == 0x49 && bytes[1] == 0x49;
    final big = bytes[0] == 0x4d && bytes[1] == 0x4d;
    if (!little && !big) throw const ImageFormatException('not a TIFF image');
    final reader = _TiffReader(bytes, little ? Endian.little : Endian.big);
    final version = reader.u16(2);
    final bigTiff = version == 43;
    if (version != 42 && !bigTiff) {
      throw const ImageFormatException('not a TIFF image');
    }
    reader.bigTiff = bigTiff;
    final ifd = bigTiff ? reader.u64(8) : reader.u32(4);
    final tags = reader.directory(ifd);
    // The pages: the chain of directories (each once).
    final seen = <int>{ifd};
    var pages = 1;
    var next = reader.nextDirectory(ifd);
    while (next != 0 && seen.add(next) && pages < 100000) {
      pages++;
      next = reader.nextDirectory(next);
    }
    int one(int tag, int fallback) {
      final values = tags[tag];
      return values == null || values.isEmpty
          ? fallback
          : _integer(values.first);
    }

    List<int> ints(int tag) => [
      for (final v in tags[tag] ?? const <num>[]) _integer(v),
    ];

    final width = one(256, 0);
    final height = one(257, 0);
    if (width <= 0 || height <= 0) {
      throw const ImageFormatException('TIFF image is empty');
    }
    final code = one(259, 1);
    final compression = TiffCompression.values
        .where((c) => c.code == code)
        .firstOrNull;
    if (compression == null) {
      throw ImageFormatException('TIFF compression $code is not supported');
    }
    if (const {
      TiffCompression.oldJpeg,
      TiffCompression.lzma,
      TiffCompression.zstd,
      TiffCompression.jpeg2000,
      TiffCompression.jbig,
    }.contains(compression)) {
      throw ImageFormatException(
        'TIFF images compressed by ${compression.label} are not supported',
      );
    }
    final samples = one(277, 1);
    if (samples < 1 || samples > 16) {
      throw const ImageFormatException('TIFF samples per pixel');
    }
    var bits = ints(258);
    if (bits.isEmpty) bits = [1];
    final bitsPerSample = bits.first;
    if (bitsPerSample < 1 || bitsPerSample > 64) {
      throw const ImageFormatException('TIFF bits per sample');
    }
    if (bits.any((b) => b != bitsPerSample)) {
      throw const ImageFormatException(
        'TIFF images with samples of different sizes are not supported',
      );
    }
    final photometric = one(
      262,
      // (Missing: as libtiff guesses.)
      samples >= 3 ? 2 : 1,
    );
    // Enough samples for the photometric interpretation's colors.
    final needed = switch (photometric) {
      0 || 1 || 3 => 1,
      5 => 4,
      _ => 3,
    };
    if (samples < needed) {
      throw ImageFormatException(
        'TIFF image has $samples samples a pixel for photometric '
        'interpretation $photometric',
      );
    }
    final tiled = tags.containsKey(322);
    final tileWidth = tiled ? one(322, 0) : width;
    final tileHeight = tiled ? one(323, 0) : math.min(one(278, height), height);
    if (tileWidth <= 0 || tileHeight <= 0) {
      throw const ImageFormatException('TIFF tile or strip size');
    }
    final offsets = ints(tiled ? 324 : 273);
    var byteCounts = ints(tiled ? 325 : 279);
    if (offsets.isEmpty) {
      throw const ImageFormatException('TIFF image has no data');
    }
    if (byteCounts.length < offsets.length) {
      // (Missing counts: to the next offset, or the file's end.)
      byteCounts = [
        for (var i = 0; i < offsets.length; i++)
          if (i < byteCounts.length)
            byteCounts[i]
          else
            (i + 1 < offsets.length ? offsets[i + 1] : bytes.length) -
                offsets[i],
      ];
    }
    final colorMapValues = ints(320);
    Uint8List? colorMap;
    if (photometric == 3) {
      final entries = 1 << bitsPerSample;
      if (colorMapValues.length < 3 * entries) {
        throw const ImageFormatException('TIFF palette image has no palette');
      }
      // 16-bit entries as libtiff takes them: their high byte, unless
      // every entry is below 256 (an 8-bit map written wrong).
      final wide = colorMapValues.any((v) => v >= 256);
      colorMap = Uint8List(3 * entries);
      for (var i = 0; i < entries; i++) {
        for (var c = 0; c < 3; c++) {
          final v = colorMapValues[c * entries + i];
          colorMap[3 * i + c] = wide ? v >> 8 : v;
        }
      }
    }
    final subsampling = ints(530);
    final reference = tags[532];
    final coefficients = tags[529];
    final jpegTables = reader.bytesOf(347);
    return TiffFile._(
      bytes,
      width: width,
      height: height,
      compression: compression,
      photometric: photometric,
      bitsPerSample: bitsPerSample,
      samplesPerPixel: samples,
      sampleFormat: one(339, 1),
      planar: one(284, 1) == 2,
      predictor: one(317, 1),
      extraSamples: ints(338),
      colorMap: colorMap,
      tileWidth: tileWidth,
      tileHeight: tileHeight,
      offsets: offsets,
      byteCounts: byteCounts,
      lsbFirst: one(266, 1) == 2,
      t4Options: one(292, 0),
      jpegTables: jpegTables,
      ycbcrSubsampling: subsampling.length >= 2
          ? (subsampling[0], subsampling[1])
          : (2, 2),
      referenceBlackWhite: reference == null || reference.length < 6
          ? null
          : [for (final v in reference) v.toDouble()],
      ycbcrCoefficients: coefficients == null || coefficients.length < 3
          ? null
          : [for (final v in coefficients) v.toDouble()],
      iccProfile: reader.bytesOf(34675),
      orientation: switch (one(274, 1)) {
        final o when o >= 1 && o <= 8 => o,
        _ => 1,
      },
      pages: pages,
      littleEndian: little,
      tiled: tiled,
    );
  }

  @override
  ImageFormat get format => ImageFormat.tiff;

  @override
  final int width;

  @override
  final int height;

  /// How the data is compressed.
  final TiffCompression compression;

  /// The photometric interpretation (0 white is zero, 1 black is zero,
  /// 2 RGB, 3 palette, 5 separated, 6 YCbCr, 8 CIE L*a*b*).
  final int photometric;

  /// The bits of each sample.
  final int bitsPerSample;

  /// The samples a pixel.
  final int samplesPerPixel;

  /// The samples' format: 1 unsigned, 2 signed, 3 floating point.
  final int sampleFormat;

  /// Whether each sample is stored in its own plane.
  final bool planar;

  /// The predictor: 1 none, 2 horizontal differencing, 3 floating point.
  final int predictor;

  /// What the samples past the color's are (0 unspecified, 1 associated
  /// alpha, 2 unassociated alpha).
  final List<int> extraSamples;

  /// A palette image's palette: RGB triples, 8 bits each.
  final Uint8List? colorMap;

  /// The tiles' (or strips') width and height.
  final int tileWidth;

  /// The tiles' (or strips') height.
  final int tileHeight;

  /// Where each tile or strip is.
  final List<int> offsets;

  /// How long each tile or strip is.
  final List<int> byteCounts;

  /// Whether bits are stored least significant first (fill order 2).
  final bool lsbFirst;

  /// The Group 3 options (bit 0: two-dimensional, bit 2: EOLs end on a
  /// byte).
  final int t4Options;

  /// The JPEG tables JPEG-compressed tiles share.
  final Uint8List? jpegTables;

  /// YCbCr chroma subsampling, horizontal and vertical.
  final (int, int) ycbcrSubsampling;

  /// YCbCr's reference black and white, if given.
  final List<double>? referenceBlackWhite;

  /// YCbCr's luma coefficients, if given.
  final List<double>? ycbcrCoefficients;

  @override
  final Uint8List? iccProfile;

  @override
  final int orientation;

  /// The pages (image directories) in the file.
  final int pages;

  /// Whether the file is little-endian.
  final bool littleEndian;

  /// Whether the image is in tiles (else strips).
  final bool tiled;

  /// The color samples a pixel (without extra ones).
  int get _colorSamples => switch (photometric) {
    0 || 1 || 3 => 1,
    5 => math.min(4, samplesPerPixel),
    _ => math.min(3, samplesPerPixel),
  };

  /// The index of the alpha sample, if there is one.
  int? get _alpha {
    if (samplesPerPixel <= _colorSamples || extraSamples.isEmpty) return null;
    return extraSamples.first == 1 || extraSamples.first == 2
        ? _colorSamples
        : null;
  }

  @override
  ColorModel get colorModel => switch (photometric) {
    0 || 1 => ColorModel.gray,
    3 => ColorModel.indexed,
    5 when _colorSamples == 4 => ColorModel.cmyk,
    _ => ColorModel.rgb,
  };

  @override
  int get bitDepth {
    // (Decoded through JPEG or WebP, and YCbCr and L*a*b*: 8 bits.)
    if (compression == TiffCompression.jpeg ||
        compression == TiffCompression.webp ||
        photometric == 6 ||
        photometric == 8) {
      return compression == TiffCompression.jpeg && bitsPerSample > 8 ? 16 : 8;
    }
    final bits = bitsPerSample;
    if (sampleFormat == 3 || bits > 16) return 16;
    if (photometric == 3 || (photometric <= 1 && samplesPerPixel == 1)) {
      if (bits == 1 || bits == 2 || bits == 4 || bits == 8 || bits == 16) {
        return bits;
      }
    }
    return bits <= 8 ? 8 : 16;
  }

  @override
  Raster decode() {
    _checkSize();
    if (photometric != 0 &&
        photometric != 1 &&
        photometric != 2 &&
        photometric != 3 &&
        photometric != 5 &&
        photometric != 6 &&
        photometric != 8) {
      throw ImageFormatException(
        'TIFF photometric interpretation $photometric is not supported',
      );
    }
    if (compression == TiffCompression.jpeg ||
        compression == TiffCompression.webp) {
      return _decodeImages();
    }
    if (const {
          TiffCompression.ccittRle,
          TiffCompression.ccittGroup3,
          TiffCompression.ccittGroup4,
        }.contains(compression) &&
        (bitsPerSample != 1 || samplesPerPixel != 1)) {
      throw const ImageFormatException(
        'TIFF fax compression of other than bilevel images',
      );
    }
    final values = _samples();
    return _raster(values, samplesPerPixel);
  }

  /// Every sample of every pixel, row after row (chunky), each scaled to
  /// 16 bits if more than 16 (or floating point), else as it is.
  Uint16List _samples() {
    final planes = planar ? samplesPerPixel : 1;
    final perChunk = planar ? 1 : samplesPerPixel;
    final across = _ceilDiv(width, tileWidth);
    final down = _ceilDiv(height, tileHeight);
    final chunksPerPlane = across * down;
    final out = Uint16List(width * height * samplesPerPixel);
    final ycbcr = photometric == 6 && !planar;
    final (hs, vs) = ycbcrSubsampling;
    for (var plane = 0; plane < planes; plane++) {
      for (var chunk = 0; chunk < chunksPerPlane; chunk++) {
        final index = plane * chunksPerPlane + chunk;
        if (index >= offsets.length) break;
        final x0 = (chunk % across) * tileWidth;
        final y0 = (chunk ~/ across) * tileHeight;
        // A strip's last one is shorter; a tile is whole.
        final rows = tiled ? tileHeight : math.min(tileHeight, height - y0);
        final rowBytes = ycbcr
            ? _ceilDiv(tileWidth, hs) * (hs * vs + 2) * bitsPerSample ~/ 8
            : (tileWidth * perChunk * bitsPerSample + 7) >> 3;
        final rowsOfUnits = ycbcr ? _ceilDiv(rows, vs) : rows;
        final data = _chunk(index, rowBytes * rowsOfUnits, rows, perChunk);
        if (ycbcr) {
          _placeYcbcr(data, out, x0, y0, rows, hs, vs);
          continue;
        }
        _place(data, out, x0, y0, rows, perChunk, plane, rowBytes);
      }
    }
    return out;
  }

  /// Chunk [index] decompressed to [expected] bytes (and its predictor
  /// undone).
  Uint8List _chunk(int index, int expected, int rows, int samples) {
    final offset = offsets[index];
    final length = byteCounts[index];
    if (offset < 0 || offset >= bytes.length || length <= 0) {
      return Uint8List(expected);
    }
    var raw = Uint8List.sublistView(
      bytes,
      offset,
      math.min(bytes.length, offset + length),
    );
    if (lsbFirst) raw = _reverseBits(raw);
    Uint8List data;
    switch (compression) {
      case TiffCompression.none:
        data = raw.length >= expected
            ? Uint8List.fromList(raw.sublist(0, expected))
            : (Uint8List(expected)..setAll(0, raw));
      case TiffCompression.packBits:
        data = unpackBits(raw, expected);
      case TiffCompression.lzw:
        data = lzwDecodeTiff(raw, expected);
      case TiffCompression.deflate || TiffCompression.adobeDeflate:
        final Uint8List inflated;
        try {
          inflated = zlibDecode(raw);
        } on FormatException catch (error) {
          throw ImageFormatException('TIFF Deflate data: ${error.message}');
        }
        data = inflated.length >= expected
            ? Uint8List.sublistView(inflated, 0, expected)
            : (Uint8List(expected)..setAll(0, inflated));
      case TiffCompression.ccittRle ||
          TiffCompression.ccittGroup3 ||
          TiffCompression.ccittGroup4:
        data = faxDecode(
          raw,
          tileWidth,
          rows,
          coding: switch (compression) {
            TiffCompression.ccittRle => FaxCoding.rle,
            TiffCompression.ccittGroup3 => FaxCoding.group3,
            _ => FaxCoding.group4,
          },
          twoDimensional: t4Options & 1 != 0,
          byteAlignedEol: t4Options & 4 != 0,
        );
      // (The fax codecs' bits: 1 black, as a white-is-zero image's.)
      case TiffCompression.oldJpeg ||
          TiffCompression.jpeg ||
          TiffCompression.lzma ||
          TiffCompression.zstd ||
          TiffCompression.webp ||
          TiffCompression.jpeg2000 ||
          TiffCompression.jbig:
        throw ImageFormatException(
          'TIFF compression ${compression.label} is not supported here',
        );
    }
    if (predictor == 2) {
      undoHorizontalDifferencing(
        data,
        tileWidth,
        rows,
        samples,
        bitsPerSample,
        littleEndian: littleEndian,
      );
    } else if (predictor == 3) {
      undoFloatingPointPredictor(
        data,
        tileWidth,
        rows,
        samples,
        bitsPerSample >> 3,
      );
    }
    return data;
  }

  /// A chunk's samples (of [samples] a pixel, rows [rowBytes] apart) into
  /// [out] at [x0], [y0]: of a planar image, sample [plane] of each pixel.
  void _place(
    Uint8List data,
    Uint16List out,
    int x0,
    int y0,
    int rows,
    int samples,
    int plane,
    int rowBytes,
  ) {
    final bits = bitsPerSample;
    final view = ByteData.sublistView(data);
    // (The floating-point predictor leaves samples big-endian.)
    final endian = littleEndian && predictor != 3 ? Endian.little : Endian.big;
    final columns = math.min(tileWidth, width - x0);
    for (var r = 0; r < rows && y0 + r < height; r++) {
      final row = r * rowBytes;
      for (var c = 0; c < columns; c++) {
        for (var s = 0; s < samples; s++) {
          final i = c * samples + s;
          int value;
          switch (bits) {
            case 8:
              value = data[row + i];
              if (sampleFormat == 2) value = (value + 128) & 0xff;
            case 16:
              value = view.getUint16(row + 2 * i, endian);
              if (sampleFormat == 2) value = (value + 32768) & 0xffff;
              if (sampleFormat == 3) value = _half(value);
            case 32:
              if (sampleFormat == 3) {
                value = _unit(view.getFloat32(row + 4 * i, endian));
              } else {
                value = view.getUint32(row + 4 * i, endian);
                if (sampleFormat == 2) {
                  value = (value + 0x80000000) & 0xffffffff;
                }
                value >>= 16;
              }
            case 64:
              value = sampleFormat == 3
                  ? _unit(view.getFloat64(row + 8 * i, endian))
                  : view.getUint32(
                          row + 8 * i + (endian == Endian.big ? 0 : 4),
                          endian,
                        ) >>
                        16;
            case 24 when sampleFormat == 3:
              value = _unit(_float24(data, row + 3 * i, endian));
            default:
              // Bit-packed samples, most significant bit first.
              final bit = i * bits;
              var v = 0;
              for (var k = 0; k < bits; k++) {
                final b = bit + k;
                v = (v << 1) | ((data[row + (b >> 3)] >> (7 - (b & 7))) & 1);
              }
              value = bits > 16 ? v >> (bits - 16) : v;
          }
          final pixel = (y0 + r) * width + x0 + c;
          out[pixel * samplesPerPixel + (samples == 1 ? plane : s)] = value;
        }
      }
    }
  }

  /// A YCbCr chunk's data units (hs × vs luma samples, then Cb and Cr)
  /// into [out] as Y, Cb, Cr for each pixel.
  void _placeYcbcr(
    Uint8List data,
    Uint16List out,
    int x0,
    int y0,
    int rows,
    int hs,
    int vs,
  ) {
    final unitsAcross = _ceilDiv(tileWidth, hs);
    final unitBytes = hs * vs + 2;
    for (var uy = 0; uy * vs < rows; uy++) {
      for (var ux = 0; ux < unitsAcross; ux++) {
        final at = (uy * unitsAcross + ux) * unitBytes;
        if (at + unitBytes > data.length) return;
        final cb = data[at + hs * vs];
        final cr = data[at + hs * vs + 1];
        for (var j = 0; j < vs; j++) {
          for (var i = 0; i < hs; i++) {
            final x = x0 + ux * hs + i;
            final y = y0 + uy * vs + j;
            if (x >= width || y >= height || ux * hs + i >= tileWidth) continue;
            if (uy * vs + j >= rows) continue;
            final p = (y * width + x) * samplesPerPixel;
            out[p] = data[at + j * hs + i];
            out[p + 1] = cb;
            out[p + 2] = cr;
          }
        }
      }
    }
  }

  /// The raster of every pixel's [samples] samples in [values].
  Raster _raster(Uint16List values, int samples) {
    final count = width * height;
    final bits = sampleFormat == 3 || bitsPerSample > 16 ? 16 : bitsPerSample;
    final top = (1 << bits) - 1;
    final depth = bitDepth;
    final outTop = (1 << depth) - 1;
    final alphaAt = _alpha;
    // Color samples: inverted (white is zero), converted (YCbCr,
    // L*a*b*), or as they are; scaled to the raster's depth.
    final model = colorModel;
    final channels = model.channels;
    final color = Uint16List(count * channels);
    if (photometric == 6) {
      final convert = _YCbCrToRgb.of(referenceBlackWhite, ycbcrCoefficients);
      for (var p = 0; p < count; p++) {
        convert.rgb(values, p * samples, color, p * 3);
      }
    } else if (photometric == 8) {
      for (var p = 0; p < count; p++) {
        _labToRgb(values, p * samples, bits, color, p * 3);
      }
    } else {
      for (var p = 0; p < count; p++) {
        for (var c = 0; c < channels; c++) {
          var v = values[p * samples + c];
          if (photometric == 0) v = top - v;
          color[p * channels + c] = depth == bits || model == ColorModel.indexed
              ? v
              : (v * outTop + (top >> 1)) ~/ top;
        }
      }
    }
    // Alpha, straight; associated alpha divided out of the color.
    Uint16List? alpha;
    if (alphaAt != null) {
      alpha = Uint16List(count);
      var opaque = true;
      for (var p = 0; p < count; p++) {
        final a = values[p * samples + alphaAt];
        alpha[p] = a;
        if (a != top) opaque = false;
      }
      if (extraSamples.first == 1) {
        for (var p = 0; p < count; p++) {
          final a = alpha[p];
          for (var c = 0; c < channels; c++) {
            final i = p * channels + c;
            final scaledTop = photometric == 6 || photometric == 8
                ? 255
                : outTop;
            final scaledAlpha = (a * scaledTop + (top >> 1)) ~/ top;
            color[i] = scaledAlpha == 0
                ? 0
                : math.min(
                    scaledTop,
                    (color[i] * scaledTop + (scaledAlpha >> 1)) ~/ scaledAlpha,
                  );
          }
        }
      }
      if (opaque) alpha = null;
    }
    final colorDepth = photometric == 6 || photometric == 8 ? 8 : depth;
    return Raster(
      width: width,
      height: height,
      colorModel: model,
      bitDepth: colorDepth,
      samples: _pack(color, colorDepth, channels),
      palette: colorMap,
      transparency: switch (alpha) {
        final a? => AlphaChannel(
          _pack(
            Uint16List.fromList([
              for (final v in a)
                if (colorDepth == 16)
                  (v * 65535 + (top >> 1)) ~/ top
                else
                  (v * 255 + (top >> 1)) ~/ top,
            ]),
            colorDepth == 16 ? 16 : 8,
            1,
          ),
          colorDepth == 16 ? 16 : 8,
        ),
        null => null,
      },
      iccProfile: iccProfile,
      orientation: orientation,
    );
  }

  /// [values] (each below 2^[depth]) packed as a raster's rows.
  Uint8List _pack(Uint16List values, int depth, int channels) {
    final rowBytes = (width * channels * depth + 7) >> 3;
    final out = Uint8List(rowBytes * height);
    final perRow = width * channels;
    for (var y = 0; y < height; y++) {
      final row = y * rowBytes;
      for (var i = 0; i < perRow; i++) {
        final v = values[y * perRow + i];
        switch (depth) {
          case 8:
            out[row + i] = v;
          case 16:
            out[row + 2 * i] = v >> 8;
            out[row + 2 * i + 1] = v & 0xff;
          default:
            final bit = i * depth;
            out[row + (bit >> 3)] |= v << (8 - depth - (bit & 7));
        }
      }
    }
    return out;
  }

  /// A JPEG- or WebP-compressed image: each tile or strip decoded and
  /// placed.
  Raster _decodeImages() {
    if (planar && samplesPerPixel > 1) {
      throw const ImageFormatException(
        'TIFF planar images compressed as images are not supported',
      );
    }
    final across = _ceilDiv(width, tileWidth);
    final down = _ceilDiv(height, tileHeight);
    final model = colorModel;
    final alphaAt = _alpha;
    final channels = model.channels;
    final depth = bitDepth;
    final sampleBytes = depth == 16 ? 2 : 1;
    final color = Uint8List(width * height * channels * sampleBytes);
    final alpha = alphaAt == null ? null : Uint8List(width * height);
    for (
      var chunk = 0;
      chunk < across * down && chunk < offsets.length;
      chunk++
    ) {
      final offset = offsets[chunk];
      final length = byteCounts[chunk];
      if (offset < 0 || offset >= bytes.length || length <= 0) continue;
      final raw = Uint8List.sublistView(
        bytes,
        offset,
        math.min(bytes.length, offset + length),
      );
      final x0 = (chunk % across) * tileWidth;
      final y0 = (chunk ~/ across) * tileHeight;
      final int w;
      final int h;
      final Uint16List samples;
      final int perPixel;
      if (compression == TiffCompression.jpeg) {
        final pixels = decodeJpeg(
          raw,
          tables: jpegTables,
          ycc: photometric == 6 ? true : (photometric == 2 ? false : null),
        );
        (w, h, samples, perPixel) = (
          pixels.width,
          pixels.height,
          pixels.samples,
          pixels.channels,
        );
      } else {
        final raster = WebPFile.read(raw).decode();
        final rgba = raster.toRgba8();
        (w, h, samples, perPixel) = (
          raster.width,
          raster.height,
          Uint16List.fromList(rgba),
          4,
        );
      }
      for (var y = 0; y < h && y0 + y < height; y++) {
        for (var x = 0; x < w && x < tileWidth && x0 + x < width; x++) {
          final p = (y0 + y) * width + x0 + x;
          final s = (y * w + x) * perPixel;
          for (var c = 0; c < channels && c < perPixel; c++) {
            var v = samples[s + c];
            if (photometric == 0) v = (depth == 16 ? 65535 : 255) - v;
            if (sampleBytes == 2) {
              v = (v * 65535 + 2047) ~/ 4095;
              color[(p * channels + c) * 2] = v >> 8;
              color[(p * channels + c) * 2 + 1] = v & 0xff;
            } else {
              color[p * channels + c] = v;
            }
          }
          if (alpha != null) {
            alpha[p] = perPixel > channels ? samples[s + channels] : 255;
          }
        }
      }
    }
    final opaque = alpha == null || alpha.every((a) => a == 255);
    return Raster(
      width: width,
      height: height,
      colorModel: model,
      bitDepth: depth,
      samples: color,
      palette: colorMap,
      transparency: opaque ? null : AlphaChannel(alpha, 8),
      iccProfile: iccProfile,
      orientation: orientation,
    );
  }

  static Uint8List _reverseBits(Uint8List data) {
    final out = Uint8List(data.length);
    for (var i = 0; i < data.length; i++) {
      var b = data[i];
      b = ((b & 0xf0) >> 4) | ((b & 0x0f) << 4);
      b = ((b & 0xcc) >> 2) | ((b & 0x33) << 2);
      b = ((b & 0xaa) >> 1) | ((b & 0x55) << 1);
      out[i] = b;
    }
    return out;
  }
}

/// A floating-point sample (0 to 1) as 16 bits, clamped.
int _unit(double v) =>
    v.isNaN ? 0 : (v <= 0 ? 0 : (v >= 1 ? 65535 : (v * 65535).round()));

/// A half-precision float sample as 16 bits (0 to 1, clamped).
int _half(int bits) {
  final sign = bits >> 15;
  final exponent = (bits >> 10) & 0x1f;
  final mantissa = bits & 0x3ff;
  double v;
  if (exponent == 0) {
    v = mantissa / 1024 * math.pow(2, -14);
  } else if (exponent == 31) {
    v = mantissa == 0 ? double.infinity : double.nan;
  } else {
    v = (1 + mantissa / 1024) * math.pow(2, exponent - 15);
  }
  return _unit(sign == 1 ? -v : v);
}

/// A 24-bit float (sign, 7-bit exponent, 16-bit mantissa) at [at].
double _float24(Uint8List data, int at, Endian endian) {
  final bits = endian == Endian.big
      ? data[at] << 16 | data[at + 1] << 8 | data[at + 2]
      : data[at + 2] << 16 | data[at + 1] << 8 | data[at];
  final sign = bits >> 23;
  final exponent = (bits >> 16) & 0x7f;
  final mantissa = bits & 0xffff;
  final v = exponent == 0
      ? mantissa / 65536 * math.pow(2, -62)
      : (1 + mantissa / 65536) * math.pow(2, exponent - 63);
  return sign == 1 ? -v : v;
}

/// CIE L*a*b* (8 bits: L* 0 to 255 for 0 to 100, a* and b* signed) to
/// sRGB, through XYZ under D65.
void _labToRgb(Uint16List values, int at, int bits, Uint16List out, int to) {
  final top = (1 << bits) - 1;
  final l = values[at] * 100 / top;
  final half = 1 << (bits - 1);
  double signed(int v) => (v >= half ? v - 2 * half : v) * 255 / top;
  final a = signed(values[at + 1]);
  final b = signed(values[at + 2]);
  final fy = (l + 16) / 116;
  final fx = fy + a / 500;
  final fz = fy - b / 200;
  double f(double t) =>
      t > 6 / 29 ? t * t * t : 3 * (6 / 29) * (6 / 29) * (t - 4 / 29);
  final x = 0.95047 * f(fx);
  final y = 1.0 * f(fy);
  final z = 1.08883 * f(fz);
  final linear = [
    3.2406 * x - 1.5372 * y - 0.4986 * z,
    -0.9689 * x + 1.8758 * y + 0.0415 * z,
    0.0557 * x - 0.2040 * y + 1.0570 * z,
  ];
  for (var c = 0; c < 3; c++) {
    final v = linear[c] <= 0.0031308
        ? 12.92 * linear[c]
        : 1.055 * math.pow(linear[c], 1 / 2.4) - 0.055;
    out[to + c] = (v.clamp(0, 1) * 255).round();
  }
}

/// libtiff's YCbCr to RGB conversion (TIFFYCbCrToRGBInit, in its fixed
/// point), with the reference black and white and luma coefficients.
final class _YCbCrToRgb {
  factory of(List<double>? reference, List<double>? coefficients) {
    // (Damaged values, not finite or degenerate: the defaults.)
    bool sane(List<double>? v) =>
        v != null && v.every((x) => x.isFinite && x.abs() < 1e6);
    final rb = sane(reference)
        ? reference!
        : const [0.0, 255.0, 128.0, 255.0, 128.0, 255.0];
    final luma = sane(coefficients) && coefficients![1] != 0
        ? coefficients
        : const [0.299, 0.587, 0.114];
    int fix(double x) => (x * 65536 + 0.5).toInt();
    double clamp(double v, double lo, double hi) =>
        v < lo ? lo : (v > hi ? hi : v);
    final f1 = 2 - 2 * luma[0];
    final d1 = fix(clamp(f1, 0, 2));
    final f2 = luma[0] * f1 / luma[1];
    final d2 = -fix(clamp(f2, 0, 2));
    final f3 = 2 - 2 * luma[2];
    final d3 = fix(clamp(f3, 0, 2));
    final f4 = luma[2] * f3 / luma[1];
    final d4 = -fix(clamp(f4, 0, 2));
    double code2v(double c, double black, double white, double range) =>
        (c - black) * range / (white - black != 0 ? white - black : 1);
    final crR = Int32List(256);
    final cbB = Int32List(256);
    final crG = Int32List(256);
    final cbG = Int32List(256);
    final y = Int32List(256);
    const half = 1 << 15;
    for (var i = 0, x = -128; i < 256; i++, x++) {
      final cr = clamp(
        code2v(x.toDouble(), rb[4] - 128, rb[5] - 128, 127),
        -128 * 32,
        128 * 32,
      ).toInt();
      final cb = clamp(
        code2v(x.toDouble(), rb[2] - 128, rb[3] - 128, 127),
        -128 * 32,
        128 * 32,
      ).toInt();
      crR[i] = _shr(d1 * cr + half, 16);
      cbB[i] = _shr(d3 * cb + half, 16);
      crG[i] = d2 * cr;
      cbG[i] = d4 * cb + half;
      y[i] = clamp(
        code2v((x + 128).toDouble(), rb[0], rb[1], 255),
        -128 * 32,
        128 * 32,
      ).toInt();
    }
    return _YCbCrToRgb._(crR, cbB, crG, cbG, y);
  }

  const new _(this.crR, this.cbB, this.crG, this.cbG, this.y);

  final Int32List crR;
  final Int32List cbB;
  final Int32List crG;
  final Int32List cbG;
  final Int32List y;

  void rgb(Uint16List values, int at, Uint16List out, int to) {
    final yy = y[values[at] > 255 ? 255 : values[at]];
    final cb = values[at + 1] > 255 ? 255 : values[at + 1];
    final cr = values[at + 2] > 255 ? 255 : values[at + 2];
    int clamp(int v) => v < 0 ? 0 : (v > 255 ? 255 : v);
    out[to] = clamp(yy + crR[cr]);
    out[to + 1] = clamp(yy + _shr(cbG[cb] + crG[cr], 16));
    out[to + 2] = clamp(yy + cbB[cb]);
  }
}

/// Reads a TIFF's directories.
final class _TiffReader {
  new(this.bytes, this.endian) : view = ByteData.sublistView(bytes);

  final Uint8List bytes;
  final Endian endian;
  final ByteData view;
  bool bigTiff = false;

  /// Each tag's raw entry, for [bytesOf].
  final Map<int, (int, int, int)> _entries = {};

  int u16(int at) => at + 2 <= bytes.length ? view.getUint16(at, endian) : 0;
  int u32(int at) => at + 4 <= bytes.length ? view.getUint32(at, endian) : 0;

  /// A 64-bit value; past what a file in memory can hold (its high half
  /// not 0), one past the file's end.
  int u64(int at) {
    if (at < 0 || at + 8 > bytes.length) return 0;
    final hi = endian == Endian.big
        ? view.getUint32(at)
        : view.getUint32(at + 4, endian);
    final lo = endian == Endian.big
        ? view.getUint32(at + 4)
        : view.getUint32(at, endian);
    return hi == 0 ? lo : bytes.length + 1;
  }

  static const Map<int, int> _sizes = {
    1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 6: 1, 7: 1, 8: 2, 9: 4, 10: 8, 11: 4, //
    12: 8, 13: 4, 16: 8, 17: 8, 18: 8,
  };

  /// The tags of the directory at [at]: each tag's values.
  Map<int, List<num>> directory(int at) {
    final count = bigTiff ? u64(at) : u16(at);
    if (at <= 0 || at >= bytes.length || count > 100000) {
      throw const ImageFormatException('TIFF directory is damaged');
    }
    final entrySize = bigTiff ? 20 : 12;
    final first = at + (bigTiff ? 8 : 2);
    final tags = <int, List<num>>{};
    for (var i = 0; i < count; i++) {
      final e = first + i * entrySize;
      if (e + entrySize > bytes.length) break;
      final tag = u16(e);
      final type = u16(e + 2);
      final n = bigTiff ? u64(e + 4) : u32(e + 4);
      final size = _sizes[type];
      if (size == null || n > 1 << 28) continue;
      final total = size * n;
      final inline = bigTiff ? 8 : 4;
      final valueAt = total <= inline
          ? e + (bigTiff ? 12 : 8)
          : (bigTiff ? u64(e + 12) : u32(e + 8));
      if (valueAt < 0 || valueAt + total > bytes.length) continue;
      _entries[tag] = (type, n, valueAt);
      // Big byte arrays (profiles, tables) are read by [bytesOf].
      if ((type == 1 || type == 7) && n > 64) {
        tags[tag] = const [];
        continue;
      }
      tags[tag] = [
        for (var k = 0; k < n; k++) _value(type, valueAt + k * size),
      ];
    }
    return tags;
  }

  num _value(int type, int at) => switch (type) {
    1 || 2 || 7 => bytes[at],
    6 => bytes[at] >= 128 ? bytes[at] - 256 : bytes[at],
    3 => u16(at),
    8 => view.getInt16(at, endian),
    4 || 13 => u32(at),
    9 => view.getInt32(at, endian),
    5 => u32(at + 4) == 0 ? 0 : u32(at) / u32(at + 4),
    10 =>
      view.getInt32(at + 4, endian) == 0
          ? 0
          : view.getInt32(at, endian) / view.getInt32(at + 4, endian),
    11 => view.getFloat32(at, endian),
    12 => view.getFloat64(at, endian),
    _ => u64(at),
  };

  /// The bytes of a tag (a profile, tables), if it has them.
  Uint8List? bytesOf(int tag) {
    final entry = _entries[tag];
    if (entry == null) return null;
    final (type, n, at) = entry;
    final size = _sizes[type] ?? 1;
    return Uint8List.sublistView(bytes, at, at + n * size);
  }

  /// Where the directory after the one at [at] is (0: none).
  int nextDirectory(int at) {
    final count = bigTiff ? u64(at) : u16(at);
    final end = at + (bigTiff ? 8 + count * 20 : 2 + count * 12);
    final next = bigTiff ? u64(end) : u32(end);
    return next >= bytes.length ? 0 : next;
  }
}

int _ceilDiv(int a, int b) => (a + b - 1) ~/ b;

/// A tag's value as an integer: one written as a fraction or float, if it
/// is a whole number of a sensible size, else −1 (damage).
int _integer(num v) => v is int
    ? v
    : (v.isFinite && v.abs() < 1e15 && v == v.truncate() ? v.toInt() : -1);

/// Whether this is JavaScript, whose numbers are doubles.
const bool _web = identical(0, 0.0);

/// [v] shifted right by [n] bits, rounding down (`>>` of a negative number
/// compiled to JavaScript is unsigned).
int _shr(int v, int n) =>
    !_web || v >= 0 ? v >> n : -((-v + (1 << n) - 1) >> n);
