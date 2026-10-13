/// TIFF's own codecs: PackBits, LZW (TIFF 6.0, 13), and the predictors
/// (horizontal differencing, 14; floating point, Adobe's Technical Note 3).
library;

import 'dart:typed_data';

import 'package:plain_images/src/exception.dart';

/// [data] unpacked by PackBits (TIFF 6.0, 9), [expected] bytes at most.
Uint8List unpackBits(Uint8List data, int expected) {
  final out = Uint8List(expected);
  var o = 0;
  var at = 0;
  while (at < data.length && o < expected) {
    final n = data[at++];
    if (n < 128) {
      // n + 1 literal bytes.
      for (var i = 0; i <= n && at < data.length && o < expected; i++) {
        out[o++] = data[at++];
      }
    } else if (n > 128) {
      // The next byte 257 − n times.
      if (at >= data.length) break;
      final value = data[at++];
      for (var i = 0; i < 257 - n && o < expected; i++) {
        out[o++] = value;
      }
    }
    // (128: nothing.)
  }
  return out;
}

/// [data] decoded by TIFF's LZW (codes most significant bit first, 9 to
/// 12 bits, the code width growing a code early), [expected] bytes at
/// most; old-style LZW (least significant bit first) is told by its first
/// bytes, as libtiff tells it.
Uint8List lzwDecodeTiff(Uint8List data, int expected) {
  final out = Uint8List(expected);
  if (data.length >= 2 && data[0] == 0 && (data[1] & 1) == 1) {
    return _lzwOld(data, out);
  }
  final prefix = Int32List(4096);
  final suffix = Uint8List(4096);
  final lengths = Int32List(4096);
  for (var i = 0; i < 256; i++) {
    prefix[i] = -1;
    suffix[i] = i;
    lengths[i] = 1;
  }
  const clear = 256;
  const end = 257;
  var next = 258;
  var width = 9;
  var previous = -1;
  var bits = 0;
  var held = 0;
  var at = 0;
  var o = 0;
  while (o < expected) {
    while (held < width) {
      if (at >= data.length) return out;
      bits = ((bits & 0xffffff) << 8) | data[at++];
      held += 8;
    }
    final code = (bits >> (held - width)) & ((1 << width) - 1);
    held -= width;
    if (code == end) break;
    if (code == clear) {
      next = 258;
      width = 9;
      previous = -1;
      continue;
    }
    int first;
    if (code < next) {
      o = _write(out, o, code, prefix, suffix, lengths);
      first = _first(code, prefix, suffix);
    } else if (previous >= 0 && code == next) {
      // The code being made: the previous string and its first byte.
      first = _first(previous, prefix, suffix);
      o = _write(out, o, previous, prefix, suffix, lengths);
      if (o < expected) out[o++] = first;
    } else {
      throw const ImageFormatException('TIFF LZW data is damaged');
    }
    if (previous >= 0 && next < 4096) {
      prefix[next] = previous;
      suffix[next] = first;
      lengths[next] = lengths[previous] + 1;
      next++;
    }
    previous = code;
    // The width grows a code early (TIFF's LZW).
    if (next + 1 >= 1 << width && width < 12) width++;
  }
  return out;
}

/// Old-style LZW (libtiff's "compat" codec): codes least significant bit
/// first, the width growing when the table is full.
Uint8List _lzwOld(Uint8List data, Uint8List out) {
  final prefix = Int32List(4096);
  final suffix = Uint8List(4096);
  final lengths = Int32List(4096);
  for (var i = 0; i < 256; i++) {
    prefix[i] = -1;
    suffix[i] = i;
    lengths[i] = 1;
  }
  var next = 258;
  var width = 9;
  var previous = -1;
  var bits = 0;
  var held = 0;
  var at = 0;
  var o = 0;
  while (o < out.length) {
    while (held < width) {
      if (at >= data.length) return out;
      bits |= data[at++] << held;
      held += 8;
    }
    final code = bits & ((1 << width) - 1);
    bits >>= width;
    held -= width;
    if (code == 257) break;
    if (code == 256) {
      next = 258;
      width = 9;
      previous = -1;
      continue;
    }
    int first;
    if (code < next) {
      o = _write(out, o, code, prefix, suffix, lengths);
      first = _first(code, prefix, suffix);
    } else if (previous >= 0 && code == next) {
      first = _first(previous, prefix, suffix);
      o = _write(out, o, previous, prefix, suffix, lengths);
      if (o < out.length) out[o++] = first;
    } else {
      throw const ImageFormatException('TIFF LZW data is damaged');
    }
    if (previous >= 0 && next < 4096) {
      prefix[next] = previous;
      suffix[next] = first;
      lengths[next] = lengths[previous] + 1;
      next++;
    }
    previous = code;
    if (next >= 1 << width && width < 12) width++;
  }
  return out;
}

int _first(int code, Int32List prefix, Uint8List suffix) {
  var c = code;
  while (prefix[c] >= 0) {
    c = prefix[c];
  }
  return suffix[c];
}

/// Writes [code]'s string at [at] (what fits); where it ends.
int _write(
  Uint8List out,
  int at,
  int code,
  Int32List prefix,
  Uint8List suffix,
  Int32List lengths,
) {
  final length = lengths[code];
  var c = code;
  var i = at + length - 1;
  while (i >= out.length) {
    c = prefix[c];
    i--;
  }
  while (c >= 0 && i >= at) {
    out[i--] = suffix[c];
    c = prefix[c];
  }
  final end = at + length;
  return end > out.length ? out.length : end;
}

/// Undoes horizontal differencing (predictor 2) in [rows] rows of
/// [width] pixels of [samples] samples of [bits] bits (8, 16, 32; 16-
/// and 32-bit ones in [littleEndian] order or not), in place.
void undoHorizontalDifferencing(
  Uint8List data,
  int width,
  int rows,
  int samples,
  int bits, {
  required bool littleEndian,
}) {
  final view = ByteData.sublistView(data);
  final endian = littleEndian ? Endian.little : Endian.big;
  final stride = width * samples * (bits >> 3);
  for (var row = 0; row < rows; row++) {
    final start = row * stride;
    if (start + stride > data.length) return;
    switch (bits) {
      case 8:
        for (var i = start + samples; i < start + stride; i++) {
          data[i] = (data[i] + data[i - samples]) & 0xff;
        }
      case 16:
        for (var i = samples; i < width * samples; i++) {
          final at = start + 2 * i;
          view.setUint16(
            at,
            (view.getUint16(at, endian) +
                    view.getUint16(at - 2 * samples, endian)) &
                0xffff,
            endian,
          );
        }
      case 32:
        for (var i = samples; i < width * samples; i++) {
          final at = start + 4 * i;
          view.setUint32(
            at,
            (view.getUint32(at, endian) +
                    view.getUint32(at - 4 * samples, endian)) &
                0xffffffff,
            endian,
          );
        }
      case 64:
        // Two 32-bit halves, the carry from the low one into the high.
        final low = littleEndian ? 0 : 4;
        final high = littleEndian ? 4 : 0;
        for (var i = samples; i < width * samples; i++) {
          final at = start + 8 * i;
          final back = at - 8 * samples;
          final sumLow =
              view.getUint32(at + low, endian) +
              view.getUint32(back + low, endian);
          final carry = sumLow > 0xffffffff ? 1 : 0;
          view
            ..setUint32(at + low, sumLow & 0xffffffff, endian)
            ..setUint32(
              at + high,
              (view.getUint32(at + high, endian) +
                      view.getUint32(back + high, endian) +
                      carry) &
                  0xffffffff,
              endian,
            );
        }
      default:
        throw ImageFormatException(
          'TIFF horizontal differencing of $bits-bit samples is not supported',
        );
    }
  }
}

/// Undoes the floating-point predictor (predictor 3) in [rows] rows of
/// [width] pixels of [samples] samples of [bytes] bytes each: each row's
/// bytes differenced, then the bytes of each sample regrouped from
/// planes (most significant first), big-endian.
void undoFloatingPointPredictor(
  Uint8List data,
  int width,
  int rows,
  int samples,
  int bytes,
) {
  final count = width * samples;
  final stride = count * bytes;
  final row = Uint8List(stride);
  for (var r = 0; r < rows; r++) {
    final start = r * stride;
    if (start + stride > data.length) return;
    // Byte differencing across the row, a sample's worth back.
    for (var i = start + samples; i < start + stride; i++) {
      data[i] = (data[i] + data[i - samples]) & 0xff;
    }
    // The planes: all most significant bytes, then the next...
    for (var i = 0; i < count; i++) {
      for (var b = 0; b < bytes; b++) {
        final byte = data[start + b * count + i];
        row[i * bytes + b] = byte;
      }
    }
    data.setRange(start, start + stride, row);
  }
}
