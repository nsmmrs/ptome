/// GIF's variable-length LZW (GIF89a, appendix F): codes packed least
/// significant bit first, a clear code and an end code after the roots,
/// the code size growing to 12 bits, a full table kept until the next
/// clear code.
library;

import 'dart:typed_data';

/// The [count] pixel indices that the LZW [data] (its sub-blocks joined)
/// with roots of [minCodeSize] bits decodes to. What the data lacks is
/// left 0, and what it has past [count] is dropped: a damaged image shows
/// what it has, as browsers show it.
Uint8List lzwDecodeGif(Uint8List data, int minCodeSize, int count) {
  final out = Uint8List(count);
  final clear = 1 << minCodeSize;
  final end = clear + 1;
  // Each code's last byte, its prefix code and its length; a root's
  // prefix is -1.
  final suffix = Uint8List(4096);
  final prefix = Int16List(4096);
  final lengths = Uint16List(4096);
  // Each code's first byte, for the code that isn't in the table yet.
  final first = Uint8List(4096);
  for (var i = 0; i < clear; i++) {
    suffix[i] = i;
    first[i] = i;
    prefix[i] = -1;
    lengths[i] = 1;
  }
  var size = minCodeSize + 1;
  var next = end + 1;
  var previous = -1;
  var bits = 0;
  var held = 0;
  var at = 0;
  var o = 0;
  while (o < count) {
    while (held < size) {
      if (at >= data.length) return out;
      bits |= data[at++] << held;
      held += 8;
    }
    final code = bits & ((1 << size) - 1);
    bits >>= size;
    held -= size;
    if (code == clear) {
      size = minCodeSize + 1;
      next = end + 1;
      previous = -1;
      continue;
    }
    if (code == end) return out;
    if (previous == -1) {
      // The first code after a clear: a root (anything else is damage,
      // taken as its low bits).
      final root = code < clear ? code : code & (clear - 1);
      out[o++] = root;
      previous = root;
      continue;
    }
    final int written;
    if (code < next) {
      written = _write(out, o, code, suffix, prefix, lengths);
      if (next < 4096) {
        prefix[next] = previous;
        suffix[next] = first[code];
        first[next] = first[previous];
        lengths[next] = lengths[previous] + 1;
        next++;
      }
    } else {
      // The code being made (KwKwK): the previous string and its first
      // byte; a code further on is damage, read as this one.
      if (next < 4096) {
        prefix[next] = previous;
        suffix[next] = first[previous];
        first[next] = first[previous];
        lengths[next] = lengths[previous] + 1;
        written = _write(out, o, next, suffix, prefix, lengths);
        next++;
      } else {
        written = _write(out, o, previous, suffix, prefix, lengths);
      }
    }
    o += written;
    previous = code < 4096 && code < next ? code : next - 1;
    if (next == 1 << size && size < 12) size++;
  }
  return out;
}

/// Writes code [code]'s string to [out] at [at] (as much as fits); the
/// bytes it takes.
int _write(
  Uint8List out,
  int at,
  int code,
  Uint8List suffix,
  Int16List prefix,
  Uint16List lengths,
) {
  final length = lengths[code];
  var c = code;
  // Past the end: walk down to what fits.
  var i = at + length - 1;
  while (i >= out.length) {
    c = prefix[c];
    i--;
  }
  while (c >= 0) {
    out[i--] = suffix[c];
    c = prefix[c];
  }
  return length;
}

/// The rows of an interlaced image [width] by [height] (its rows stored
/// every 8th from 0, every 8th from 4, every 4th from 2, every 2nd from
/// 1) put in order.
Uint8List deinterlaceGif(Uint8List rows, int width, int height) {
  final out = Uint8List(rows.length);
  var from = 0;
  for (final (start, step) in const [(0, 8), (4, 8), (2, 4), (1, 2)]) {
    for (var y = start; y < height; y += step) {
      out.setRange(y * width, (y + 1) * width, rows, from);
      from += width;
    }
  }
  return out;
}
