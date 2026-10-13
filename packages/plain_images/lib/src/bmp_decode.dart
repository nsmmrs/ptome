/// BMP's run-length encodings of palette indices (RLE8 and RLE4, 8 and 4
/// bits a pixel): runs, absolute runs padded to two bytes, end of line,
/// end of bitmap and deltas.
library;

import 'dart:typed_data';

/// The indices of an image [width] by [height] (one byte each, rows
/// bottom to top as the file has them, unless [topDown]) that the RLE
/// [data] of [bits] (8 or 4) gives, and which pixels it set (null when it
/// set every one). Data past the image is ignored; data that stops early
/// leaves the rest unset.
(Uint8List, Uint8List?) rleDecodeBmp(
  Uint8List data,
  int width,
  int height,
  int bits, {
  required bool topDown,
}) {
  final out = Uint8List(width * height);
  final set = Uint8List(width * height);
  var x = 0;
  var y = 0;
  var at = 0;
  var complete = true;
  int row(int y) => topDown ? y : height - 1 - y;
  void put(int index) {
    if (x < width && y < height) {
      final i = row(y) * width + x;
      out[i] = index;
      set[i] = 1;
    }
    x++;
  }

  outer:
  while (at + 1 < data.length && y < height) {
    final count = data[at];
    final value = data[at + 1];
    at += 2;
    if (count > 0) {
      for (var i = 0; i < count; i++) {
        put(bits == 8 ? value : (i.isEven ? value >> 4 : value & 0x0f));
      }
      continue;
    }
    switch (value) {
      case 0: // End of line.
        x = 0;
        y++;
      case 1: // End of bitmap.
        break outer;
      case 2: // A delta: right and up.
        if (at + 1 >= data.length) break outer;
        x += data[at];
        y += data[at + 1];
        at += 2;
        complete = false;
      default: // Absolute: `value` pixels as they are, padded to 2 bytes.
        final bytes = bits == 8 ? value : (value + 1) >> 1;
        if (at + bytes > data.length) break outer;
        for (var i = 0; i < value; i++) {
          put(
            bits == 8
                ? data[at + i]
                : (i.isEven
                      ? data[at + (i >> 1)] >> 4
                      : data[at + (i >> 1)] & 0x0f),
          );
        }
        at += (bytes + 1) & ~1;
    }
  }
  if (complete) {
    for (final s in set) {
      if (s == 0) {
        complete = false;
        break;
      }
    }
  }
  return (out, complete ? null : set);
}

/// The RGB samples of an image [width] by [height] that the RLE24 [data]
/// (OS/2 2.x: RLE8's codes, a pixel three bytes, blue first) gives, and
/// which pixels it set (null when it set every one).
(Uint8List, Uint8List?) rleDecodeBmp24(
  Uint8List data,
  int width,
  int height, {
  required bool topDown,
}) {
  final out = Uint8List(width * height * 3);
  final set = Uint8List(width * height);
  var x = 0;
  var y = 0;
  var at = 0;
  void put(int b, int g, int r) {
    if (x < width && y < height) {
      final i = (topDown ? y : height - 1 - y) * width + x;
      out[3 * i] = r;
      out[3 * i + 1] = g;
      out[3 * i + 2] = b;
      set[i] = 1;
    }
    x++;
  }

  outer:
  while (at + 1 < data.length && y < height) {
    final count = data[at];
    if (count > 0) {
      if (at + 4 > data.length) break;
      for (var i = 0; i < count; i++) {
        put(data[at + 1], data[at + 2], data[at + 3]);
      }
      at += 4;
      continue;
    }
    final value = data[at + 1];
    at += 2;
    switch (value) {
      case 0:
        x = 0;
        y++;
      case 1:
        break outer;
      case 2:
        if (at + 1 >= data.length) break outer;
        x += data[at];
        y += data[at + 1];
        at += 2;
      default:
        final bytes = 3 * value;
        if (at + bytes > data.length) break outer;
        for (var i = 0; i < value; i++) {
          put(data[at + 3 * i], data[at + 3 * i + 1], data[at + 3 * i + 2]);
        }
        at += (bytes + 1) & ~1;
    }
  }
  return (out, set.contains(0) ? set : null);
}
