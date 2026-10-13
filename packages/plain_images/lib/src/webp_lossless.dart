/// WebP's lossless bitstream (VP8L; RFC 9649, 3–5): transforms
/// (predictor, color, subtract green, color indexing), prefix codes with
/// meta prefix codes per block, backward references and a color cache.
library;

import 'dart:typed_data';

import 'package:plain_images/src/exception.dart';

/// A lossless image: its size and its pixels, ARGB in 32 bits each, row
/// after row.
typedef Vp8lImage = ({int width, int height, Uint32List argb});

/// The size and whether alpha is used, from a lossless bitstream's
/// 5-byte header (the signature 0x2f, then 14 bits of width − 1, 14 of
/// height − 1, the alpha hint and 3 bits of version).
({int width, int height, bool alpha})? vp8lHeader(Uint8List data) {
  if (data.length < 5 || data[0] != 0x2f) return null;
  final bits = data[1] | data[2] << 8 | data[3] << 16 | data[4] << 24;
  if ((bits >> 29) & 7 != 0) return null;
  return (
    width: (bits & 0x3fff) + 1,
    height: ((bits >> 14) & 0x3fff) + 1,
    alpha: (bits >> 28) & 1 == 1,
  );
}

/// The image of the lossless bitstream [data] (with its header), or, for
/// a [width] by [height] image without one (an `ALPH` chunk's), from its
/// transforms on.
Vp8lImage decodeVp8l(Uint8List data, {int? width, int? height}) {
  final reader = _BitReader(data);
  int w;
  int h;
  if (width == null || height == null) {
    final header = vp8lHeader(data);
    if (header == null) {
      throw const ImageFormatException('not a lossless WebP bitstream');
    }
    reader.skip(40);
    w = header.width;
    h = header.height;
  } else {
    w = width;
    h = height;
  }
  return (width: w, height: h, argb: _Decoder(reader).image(w, h));
}

/// Bits read least significant first.
final class _BitReader {
  new(this.data);

  final Uint8List data;
  int _at = 0;
  // Bits held, the next one lowest, and how many; past the end, zeros.
  int _bits = 0;
  int _held = 0;
  bool _eos = false;

  void _fill() {
    while (_held <= 24) {
      if (_at < data.length) {
        _bits |= data[_at++] << _held;
      } else {
        // Past the end: zero bits, noted.
        if (_held == 0 || _at >= data.length + 8) _eos = true;
        _at++;
      }
      _held += 8;
    }
  }

  /// Whether reading went past the end of the data.
  bool get pastEnd => _eos || _at > data.length + 4;

  /// The next [n] (0 to 24) bits.
  int read(int n) {
    if (n == 0) return 0;
    if (_held < n) _fill();
    final value = _bits & ((1 << n) - 1);
    _bits >>= n;
    _held -= n;
    return value;
  }

  /// The next bits without consuming them (at least 15 available).
  int peek() {
    if (_held < 16) _fill();
    return _bits;
  }

  void consume(int n) {
    _bits >>= n;
    _held -= n;
  }

  void skip(int n) {
    var left = n;
    while (left > 0) {
      final step = left > 24 ? 24 : left;
      read(step);
      left -= step;
    }
  }
}

/// A canonical prefix code (RFC 9649, 3.7.2), looked up by the next bits
/// in two levels.
final class _PrefixCode {
  factory of(List<int> lengths) {
    final symbols = <int>[
      for (var s = 0; s < lengths.length; s++)
        if (lengths[s] > 0) s,
    ];
    if (symbols.isEmpty) {
      throw const ImageFormatException('prefix code without symbols');
    }
    if (symbols.length == 1) {
      // One symbol: it takes no bits.
      return _PrefixCode._(Int32List(0), symbols.single);
    }
    final maxLength = symbols
        .map((s) => lengths[s])
        .reduce((a, b) => a > b ? a : b);
    // Codes by length, then symbol (canonical, deflate's assignment).
    final count = List<int>.filled(maxLength + 1, 0);
    for (final s in symbols) {
      count[lengths[s]]++;
    }
    final next = List<int>.filled(maxLength + 2, 0);
    var code = 0;
    for (var bits = 1; bits <= maxLength; bits++) {
      code = (code + count[bits - 1]) << 1;
      next[bits] = code;
    }
    // A complete code is required (as libwebp requires it).
    var space = 0;
    for (var bits = 1; bits <= maxLength; bits++) {
      space += count[bits] << (maxLength - bits);
    }
    if (space != 1 << maxLength) {
      throw const ImageFormatException('prefix code is not complete');
    }
    // The codes, read least significant bit first: reversed.
    final reversed = List<int>.filled(lengths.length, 0);
    for (var s = 0; s < lengths.length; s++) {
      final length = lengths[s];
      if (length == 0) continue;
      final c = next[length]++;
      var r = 0;
      for (var i = 0; i < length; i++) {
        r |= ((c >> i) & 1) << (length - 1 - i);
      }
      reversed[s] = r;
    }
    // A root table indexed by the next [_rootBits] bits: (length << 16) |
    // symbol; for a longer code, a second table's bits and offset with
    // [_subTable] set, indexed by the bits after the root's.
    final rootBits = maxLength < _rootBits ? maxLength : _rootBits;
    final rootSize = 1 << rootBits;
    // The bits each second table needs: its codes' longest past the root.
    final subBits = List<int>.filled(rootSize, 0);
    for (var s = 0; s < lengths.length; s++) {
      final length = lengths[s];
      if (length <= rootBits) continue;
      final root = reversed[s] & (rootSize - 1);
      if (length - rootBits > subBits[root]) subBits[root] = length - rootBits;
    }
    var size = rootSize;
    final offsets = List<int>.filled(rootSize, 0);
    for (var root = 0; root < rootSize; root++) {
      if (subBits[root] == 0) continue;
      offsets[root] = size;
      size += 1 << subBits[root];
    }
    final table = Int32List(size);
    for (var root = 0; root < rootSize; root++) {
      if (subBits[root] > 0) {
        table[root] = _subTable | subBits[root] << 16 | offsets[root];
      }
    }
    for (var s = 0; s < lengths.length; s++) {
      final length = lengths[s];
      if (length == 0) continue;
      final r = reversed[s];
      if (length <= rootBits) {
        for (var fill = r; fill < rootSize; fill += 1 << length) {
          table[fill] = length << 16 | s;
        }
        continue;
      }
      final root = r & (rootSize - 1);
      final bits = subBits[root];
      final rest = length - rootBits;
      for (var fill = r >> rootBits; fill < 1 << bits; fill += 1 << rest) {
        table[offsets[root] + fill] = length << 16 | s;
      }
    }
    return _PrefixCode._(table, -1, rootBits);
  }

  const new _(this.table, this.only, [this.rootBits = 0]);

  static const int _rootBits = 8;
  static const int _subTable = 1 << 30;

  final Int32List table;

  /// The one symbol of a code with one, else −1.
  final int only;
  final int rootBits;

  int read(_BitReader reader) {
    if (only >= 0) return only;
    final bits = reader.peek();
    var entry = table[bits & ((1 << rootBits) - 1)];
    if (entry & _subTable != 0) {
      final subBits = (entry >> 16) & 0xff;
      entry =
          table[(entry & 0xffff) + ((bits >> rootBits) & ((1 << subBits) - 1))];
    }
    reader.consume(entry >> 16);
    return entry & 0xffff;
  }
}

/// The five codes of a prefix code group: green (with length prefixes and
/// color cache indices), red, blue, alpha, distance.
typedef _Group = (
  _PrefixCode green,
  _PrefixCode red,
  _PrefixCode blue,
  _PrefixCode alpha,
  _PrefixCode distance,
);

const List<int> _codeLengthOrder = [
  17, 18, 0, 1, 2, 3, 4, 5, 16, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, //
];

/// The distance map's (x, y) offsets for distance codes 1 to 120.
const List<int> _distanceMap = [
  0x18, 0x07, 0x17, 0x19, 0x28, 0x06, 0x27, 0x29, 0x16, 0x1a, //
  0x26, 0x2a, 0x38, 0x05, 0x37, 0x39, 0x15, 0x1b, 0x36, 0x3a,
  0x25, 0x2b, 0x48, 0x04, 0x47, 0x49, 0x14, 0x1c, 0x35, 0x3b,
  0x46, 0x4a, 0x24, 0x2c, 0x58, 0x45, 0x4b, 0x34, 0x3c, 0x03,
  0x57, 0x59, 0x13, 0x1d, 0x56, 0x5a, 0x23, 0x2d, 0x44, 0x4c,
  0x55, 0x5b, 0x33, 0x3d, 0x68, 0x02, 0x67, 0x69, 0x12, 0x1e,
  0x66, 0x6a, 0x22, 0x2e, 0x54, 0x5c, 0x43, 0x4d, 0x65, 0x6b,
  0x32, 0x3e, 0x78, 0x01, 0x77, 0x79, 0x53, 0x5d, 0x11, 0x1f,
  0x64, 0x6c, 0x42, 0x4e, 0x76, 0x7a, 0x21, 0x2f, 0x75, 0x7b,
  0x31, 0x3f, 0x63, 0x6d, 0x52, 0x5e, 0x00, 0x74, 0x7c, 0x41,
  0x4f, 0x10, 0x20, 0x62, 0x6e, 0x30, 0x73, 0x7d, 0x51, 0x5f,
  0x40, 0x72, 0x7e, 0x61, 0x6f, 0x50, 0x71, 0x7f, 0x60, 0x70,
];

enum _TransformKind { predictor, color, subtractGreen, colorIndexing }

/// A transform read from the bitstream, applied in reverse after the
/// image is decoded.
final class _Transform {
  new(this.kind, this.width, {this.bits = 0, this.data});

  final _TransformKind kind;

  /// The image's width before the transform (color indexing narrows it).
  final int width;
  final int bits;

  /// The predictor or color transform's image, or the color table.
  final Uint32List? data;
}

final class _Decoder {
  new(this.reader);

  final _BitReader reader;

  /// The image [width] by [height], its transforms read and undone.
  Uint32List image(int width, int height) {
    final transforms = <_Transform>[];
    final seen = <_TransformKind>{};
    var w = width;
    while (reader.read(1) == 1) {
      final kind = _TransformKind.values[reader.read(2)];
      if (!seen.add(kind)) {
        throw const ImageFormatException('a transform is repeated');
      }
      switch (kind) {
        case _TransformKind.predictor || _TransformKind.color:
          final bits = reader.read(3) + 2;
          final data = _entropyImage(
            _divRoundUp(w, 1 << bits),
            _divRoundUp(height, 1 << bits),
          );
          transforms.add(_Transform(kind, w, bits: bits, data: data));
        case _TransformKind.subtractGreen:
          transforms.add(_Transform(kind, w));
        case _TransformKind.colorIndexing:
          final size = reader.read(8) + 1;
          final table = _entropyImage(size, 1);
          // Each entry is a difference from the one before.
          for (var i = 1; i < size; i++) {
            table[i] = _addPixels(table[i], table[i - 1]);
          }
          final bits = size > 16
              ? 0
              : size > 4
              ? 1
              : size > 2
              ? 2
              : 3;
          // 256 entries: indices past the table are transparent black.
          final full = Uint32List(256)..setRange(0, size, table);
          transforms.add(_Transform(kind, w, bits: bits, data: full));
          w = _divRoundUp(w, 1 << bits);
      }
    }
    var pixels = _imageData(w, height, main: true);
    for (final transform in transforms.reversed) {
      pixels = _undo(transform, pixels, height);
    }
    return pixels;
  }

  /// A transform's or color table's image (no meta prefix codes).
  Uint32List _entropyImage(int width, int height) =>
      _imageData(width, height, main: false);

  /// Entropy-coded pixels: the color cache, the meta prefix codes (in the
  /// main image), the prefix code groups, then the pixels.
  Uint32List _imageData(int width, int height, {required bool main}) {
    var cacheBits = 0;
    if (reader.read(1) == 1) {
      cacheBits = reader.read(4);
      if (cacheBits < 1 || cacheBits > 11) {
        throw ImageFormatException('color cache of $cacheBits bits');
      }
    }
    var prefixBits = 0;
    Uint32List? entropy;
    var groups = 1;
    if (main && reader.read(1) == 1) {
      prefixBits = reader.read(3) + 2;
      entropy = _entropyImage(
        _divRoundUp(width, 1 << prefixBits),
        _divRoundUp(height, 1 << prefixBits),
      );
      for (var i = 0; i < entropy.length; i++) {
        final group = (entropy[i] >> 8) & 0xffff;
        entropy[i] = group;
        if (group >= groups) groups = group + 1;
      }
    }
    final cacheSize = cacheBits == 0 ? 0 : 1 << cacheBits;
    final codes = <_Group>[
      for (var g = 0; g < groups; g++)
        (
          _readCode(256 + 24 + cacheSize),
          _readCode(256),
          _readCode(256),
          _readCode(256),
          _readCode(40),
        ),
    ];
    if (reader.pastEnd) {
      throw const ImageFormatException('bitstream is truncated');
    }
    return _pixels(width, height, codes, entropy, prefixBits, cacheBits);
  }

  _PrefixCode _readCode(int alphabet) {
    final lengths = List<int>.filled(alphabet, 0);
    if (reader.read(1) == 1) {
      // A simple code: one or two symbols.
      final two = reader.read(1) == 1;
      final first = reader.read(reader.read(1) == 1 ? 8 : 1);
      if (first >= alphabet) {
        throw const ImageFormatException('symbol out of range');
      }
      lengths[first] = 1;
      if (two) {
        final second = reader.read(8);
        if (second >= alphabet) {
          throw const ImageFormatException('symbol out of range');
        }
        lengths[second] = 1;
      }
      return _PrefixCode.of(lengths);
    }
    // The code lengths' code, then the code lengths.
    final count = reader.read(4) + 4;
    if (count > 19) throw const ImageFormatException('too many code lengths');
    final lengthLengths = List<int>.filled(19, 0);
    for (var i = 0; i < count; i++) {
      lengthLengths[_codeLengthOrder[i]] = reader.read(3);
    }
    final lengthCode = _PrefixCode.of(lengthLengths);
    var maxSymbol = alphabet;
    if (reader.read(1) == 1) {
      final bits = 2 + 2 * reader.read(3);
      maxSymbol = 2 + reader.read(bits);
      if (maxSymbol > alphabet) {
        throw const ImageFormatException('more code lengths than symbols');
      }
    }
    var previous = 8;
    var symbol = 0;
    while (symbol < alphabet) {
      if (maxSymbol-- == 0) break;
      final code = lengthCode.read(reader);
      if (code < 16) {
        lengths[symbol++] = code;
        if (code != 0) previous = code;
        continue;
      }
      final (extraBits, offset) = switch (code) {
        16 => (2, 3),
        17 => (3, 3),
        _ => (7, 11),
      };
      final repeat = reader.read(extraBits) + offset;
      if (symbol + repeat > alphabet) {
        throw const ImageFormatException('code lengths run past the symbols');
      }
      final value = code == 16 ? previous : 0;
      for (var i = 0; i < repeat; i++) {
        lengths[symbol++] = value;
      }
      if (reader.pastEnd) {
        throw const ImageFormatException('bitstream is truncated');
      }
    }
    return _PrefixCode.of(lengths);
  }

  Uint32List _pixels(
    int width,
    int height,
    List<_Group> codes,
    Uint32List? entropy,
    int prefixBits,
    int cacheBits,
  ) {
    final count = width * height;
    final out = Uint32List(count);
    final cache = cacheBits == 0 ? null : Uint32List(1 << cacheBits);
    final cacheShift = 32 - cacheBits;
    final entropyWidth = entropy == null
        ? 0
        : _divRoundUp(width, 1 << prefixBits);
    final mask = entropy == null ? -1 : (1 << prefixBits) - 1;
    var (green, red, blue, alpha, distance) = codes.first;
    void select(int x, int y) {
      (green, red, blue, alpha, distance) =
          codes[entropy![(y >> prefixBits) * entropyWidth + (x >> prefixBits)]];
    }

    var x = 0;
    var y = 0;
    var p = 0;
    while (p < count) {
      if (entropy != null && (x & mask) == 0) select(x, y);
      final symbol = green.read(reader);
      if (symbol < 256) {
        final r = red.read(reader);
        final b = blue.read(reader);
        final a = alpha.read(reader);
        final argb = a << 24 | r << 16 | symbol << 8 | b;
        out[p++] = argb;
        if (cache != null) cache[_hash(argb) >> cacheShift] = argb;
        if (++x == width) {
          x = 0;
          y++;
          if (reader.pastEnd) {
            throw const ImageFormatException('bitstream is truncated');
          }
        }
      } else if (symbol < 256 + 24) {
        final length = _prefixValue(symbol - 256);
        final code = _prefixValue(distance.read(reader));
        var d = code;
        if (code <= 120) {
          final xy = _distanceMap[code - 1];
          d = (xy >> 4) * width + 8 - (xy & 0xf);
          if (d < 1) d = 1;
        } else {
          d = code - 120;
        }
        if (d > p || p + length > count) {
          throw const ImageFormatException('backward reference out of range');
        }
        for (var i = 0; i < length; i++) {
          final argb = out[p - d];
          out[p++] = argb;
          if (cache != null) cache[_hash(argb) >> cacheShift] = argb;
        }
        x += length;
        while (x >= width) {
          x -= width;
          y++;
        }
        if (entropy != null && p < count) select(x, y);
        if (reader.pastEnd) {
          throw const ImageFormatException('bitstream is truncated');
        }
      } else {
        if (cache == null) throw const ImageFormatException('no color cache');
        final index = symbol - 280;
        if (index >= cache.length) {
          throw const ImageFormatException('color cache index out of range');
        }
        final argb = cache[index];
        out[p++] = argb;
        cache[_hash(argb) >> cacheShift] = argb;
        if (++x == width) {
          x = 0;
          y++;
        }
      }
    }
    return out;
  }

  /// The value of a length or distance prefix [code] and its extra bits.
  int _prefixValue(int code) {
    if (code < 4) return code + 1;
    final extra = (code - 2) >> 1;
    final offset = (2 + (code & 1)) << extra;
    return offset + reader.read(extra) + 1;
  }

  Uint32List _undo(_Transform transform, Uint32List pixels, int height) {
    final width = transform.width;
    switch (transform.kind) {
      case _TransformKind.subtractGreen:
        for (var i = 0; i < pixels.length; i++) {
          final argb = pixels[i];
          final green = (argb >> 8) & 0xff;
          final red = ((argb >> 16) + green) & 0xff;
          final blue = (argb + green) & 0xff;
          pixels[i] = (argb & 0xff00ff00) | red << 16 | blue;
        }
        return pixels;
      case _TransformKind.color:
        final bits = transform.bits;
        final tiles = _divRoundUp(width, 1 << bits);
        final data = transform.data!;
        for (var y = 0; y < height; y++) {
          for (var tile = 0; tile < tiles; tile++) {
            // One tile's multipliers over its span of the row.
            final element = data[(y >> bits) * tiles + tile];
            final greenToRed = _signed(element & 0xff);
            final greenToBlue = _signed((element >> 8) & 0xff);
            final redToBlue = _signed((element >> 16) & 0xff);
            final last = (tile + 1) << bits;
            final start = y * width + (tile << bits);
            final end = y * width + (last < width ? last : width);
            for (var i = start; i < end; i++) {
              final argb = pixels[i];
              final green = _signed((argb >> 8) & 0xff);
              final red = ((argb >> 16) + _shr(greenToRed * green, 5)) & 0xff;
              final blue =
                  (argb +
                      _shr(greenToBlue * green, 5) +
                      _shr(redToBlue * _signed(red), 5)) &
                  0xff;
              pixels[i] = (argb & 0xff00ff00) | red << 16 | blue;
            }
          }
        }
        return pixels;
      case _TransformKind.predictor:
        _unpredict(pixels, width, height, transform.bits, transform.data!);
        return pixels;
      case _TransformKind.colorIndexing:
        final bits = transform.bits;
        final table = transform.data!;
        final packed = _divRoundUp(width, 1 << bits);
        final out = Uint32List(width * height);
        final perByte = 1 << bits;
        final indexBits = 8 >> bits;
        final indexMask = (1 << indexBits) - 1;
        for (var y = 0; y < height; y++) {
          for (var x = 0; x < width; x++) {
            final word = pixels[y * packed + (x >> bits)];
            final index =
                ((word >> 8) >> (indexBits * (x & (perByte - 1)))) &
                (bits == 0 ? 0xff : indexMask);
            out[y * width + x] = table[index];
          }
        }
        return out;
    }
  }

  /// Undoes the predictor transform in place: each pixel plus its
  /// prediction from the pixels decoded before it.
  static void _unpredict(
    Uint32List pixels,
    int width,
    int height,
    int bits,
    Uint32List modes,
  ) {
    final tiles = _divRoundUp(width, 1 << bits);
    // The top left pixel: opaque black; the rest of the first row: left.
    pixels[0] = _addPixels(pixels[0], 0xff000000);
    for (var x = 1; x < width; x++) {
      pixels[x] = _addPixels(pixels[x], pixels[x - 1]);
    }
    for (var y = 1; y < height; y++) {
      final row = y * width;
      // The first column: top.
      pixels[row] = _addPixels(pixels[row], pixels[row - width]);
      for (var tile = 0; tile < tiles; tile++) {
        // One tile's mode over its span of the row (but the first pixel).
        final mode = (modes[(y >> bits) * tiles + tile] >> 8) & 0xf;
        final first = tile << bits;
        final last = (tile + 1) << bits;
        final start = row + (first > 1 ? first : 1);
        final end = row + (last < width ? last : width);
        // Each pixel's left (L), top (T), top left (TL) and top right
        // (TR) neighbors; on the last column, TR is the row's first pixel
        // (what follows the top row in memory).
        switch (mode) {
          case 1:
            for (var i = start; i < end; i++) {
              pixels[i] = _addPixels(pixels[i], pixels[i - 1]);
            }
          case 2:
            for (var i = start; i < end; i++) {
              pixels[i] = _addPixels(pixels[i], pixels[i - width]);
            }
          case 3:
            for (var i = start; i < end; i++) {
              pixels[i] = _addPixels(pixels[i], pixels[i - width + 1]);
            }
          case 4:
            for (var i = start; i < end; i++) {
              pixels[i] = _addPixels(pixels[i], pixels[i - width - 1]);
            }
          case 5:
            for (var i = start; i < end; i++) {
              final prediction = _average(
                _average(pixels[i - 1], pixels[i - width + 1]),
                pixels[i - width],
              );
              pixels[i] = _addPixels(pixels[i], prediction);
            }
          case 6:
            for (var i = start; i < end; i++) {
              final prediction = _average(pixels[i - 1], pixels[i - width - 1]);
              pixels[i] = _addPixels(pixels[i], prediction);
            }
          case 7:
            for (var i = start; i < end; i++) {
              final prediction = _average(pixels[i - 1], pixels[i - width]);
              pixels[i] = _addPixels(pixels[i], prediction);
            }
          case 8:
            for (var i = start; i < end; i++) {
              final prediction = _average(
                pixels[i - width - 1],
                pixels[i - width],
              );
              pixels[i] = _addPixels(pixels[i], prediction);
            }
          case 9:
            for (var i = start; i < end; i++) {
              final prediction = _average(
                pixels[i - width],
                pixels[i - width + 1],
              );
              pixels[i] = _addPixels(pixels[i], prediction);
            }
          case 10:
            for (var i = start; i < end; i++) {
              final prediction = _average(
                _average(pixels[i - 1], pixels[i - width - 1]),
                _average(pixels[i - width], pixels[i - width + 1]),
              );
              pixels[i] = _addPixels(pixels[i], prediction);
            }
          case 11:
            for (var i = start; i < end; i++) {
              final prediction = _select(
                pixels[i - 1],
                pixels[i - width],
                pixels[i - width - 1],
              );
              pixels[i] = _addPixels(pixels[i], prediction);
            }
          case 12:
            for (var i = start; i < end; i++) {
              final prediction = _clampAddSubtractFull(
                pixels[i - 1],
                pixels[i - width],
                pixels[i - width - 1],
              );
              pixels[i] = _addPixels(pixels[i], prediction);
            }
          case 13:
            for (var i = start; i < end; i++) {
              final prediction = _clampAddSubtractHalf(
                _average(pixels[i - 1], pixels[i - width]),
                pixels[i - width - 1],
              );
              pixels[i] = _addPixels(pixels[i], prediction);
            }
          default:
            // 0 (and 14 and 15, as libwebp has them): opaque black.
            for (var i = start; i < end; i++) {
              pixels[i] = _addPixels(pixels[i], 0xff000000);
            }
        }
      }
    }
  }
}

int _divRoundUp(int n, int d) => (n + d - 1) ~/ d;

/// Whether this is JavaScript, whose numbers are doubles.
const bool _web = identical(0, 0.0);

/// The color cache's hash of [argb]: its product with 0x1e35a7bd, modulo
/// 2^32 (in JavaScript, in halves, to stay exact).
@pragma('vm:prefer-inline')
int _hash(int argb) {
  const k = 0x1e35a7bd;
  if (!_web) return (argb * k) & 0xffffffff;
  final low = (argb & 0xffff) * k;
  final high = (((argb >> 16) & 0xffff) * k) & 0xffff;
  return (low + high * 65536) & 0xffffffff;
}

@pragma('vm:prefer-inline')
int _signed(int byte) => (byte ^ 0x80) - 0x80;

/// [v] shifted right by [n] bits, rounding down (`>>` of a negative number
/// compiled to JavaScript is unsigned).
@pragma('vm:prefer-inline')
int _shr(int v, int n) =>
    !_web || v >= 0 ? v >> n : -((-v + (1 << n) - 1) >> n);

/// [a] plus [b], each channel modulo 256.
@pragma('vm:prefer-inline')
int _addPixels(int a, int b) {
  final alphaGreen = (a & 0xff00ff00) + (b & 0xff00ff00);
  final redBlue = (a & 0x00ff00ff) + (b & 0x00ff00ff);
  return (alphaGreen & 0xff00ff00) | (redBlue & 0x00ff00ff);
}

/// Each channel's average of [a] and [b], rounded down.
@pragma('vm:prefer-inline')
int _average(int a, int b) => (((a ^ b) & 0xfefefefe) >> 1) + (a & b);

@pragma('vm:prefer-inline')
int _select(int l, int t, int tl) {
  // The sum of each channel's |L − TL| less that of |T − TL|: T when it
  // isn't more.
  final difference =
      _absDiff(l >> 24, tl >> 24) -
      _absDiff(t >> 24, tl >> 24) +
      _absDiff((l >> 16) & 0xff, (tl >> 16) & 0xff) -
      _absDiff((t >> 16) & 0xff, (tl >> 16) & 0xff) +
      _absDiff((l >> 8) & 0xff, (tl >> 8) & 0xff) -
      _absDiff((t >> 8) & 0xff, (tl >> 8) & 0xff) +
      _absDiff(l & 0xff, tl & 0xff) -
      _absDiff(t & 0xff, tl & 0xff);
  return difference <= 0 ? t : l;
}

@pragma('vm:prefer-inline')
int _absDiff(int a, int b) => a > b ? a - b : b - a;

@pragma('vm:prefer-inline')
int _clamp(int v) => v < 0 ? 0 : (v > 255 ? 255 : v);

@pragma('vm:prefer-inline')
int _clampAddSubtractFull(int a, int b, int c) =>
    _clamp((a >> 24) + (b >> 24) - (c >> 24)) << 24 |
    _clamp(((a >> 16) & 0xff) + ((b >> 16) & 0xff) - ((c >> 16) & 0xff)) << 16 |
    _clamp(((a >> 8) & 0xff) + ((b >> 8) & 0xff) - ((c >> 8) & 0xff)) << 8 |
    _clamp((a & 0xff) + (b & 0xff) - (c & 0xff));

@pragma('vm:prefer-inline')
int _clampAddSubtractHalf(int a, int b) =>
    _half(a >> 24, b >> 24) << 24 |
    _half((a >> 16) & 0xff, (b >> 16) & 0xff) << 16 |
    _half((a >> 8) & 0xff, (b >> 8) & 0xff) << 8 |
    _half(a & 0xff, b & 0xff);

/// One channel of [_clampAddSubtractHalf]: `a + (a − b) / 2`, the
/// division truncating toward zero, clamped.
@pragma('vm:prefer-inline')
int _half(int a, int b) => _clamp(a + (a - b) ~/ 2);
