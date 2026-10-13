/// ITU-T T.4 and T.6 (fax) decoding: Modified Huffman (one-dimensional,
/// TIFF's CCITT RLE and Group 3 1-D), Modified READ (Group 3 2-D) and
/// Modified Modified READ (Group 4), to rows of bits, 1 for black.
library;

import 'dart:typed_data';

/// How a fax image is coded.
enum FaxCoding {
  /// TIFF's compression 2: Modified Huffman rows, each starting on a byte,
  /// no EOL codes.
  rle,

  /// Group 3 (T.4): EOL codes before rows; rows one-dimensional, or
  /// (two-dimensional coding) each row's EOL followed by a bit for its
  /// coding.
  group3,

  /// Group 4 (T.6): every row two-dimensional, against the one before.
  group4,
}

/// The [rows] rows of [width] pixels, packed (a row starting on a byte,
/// most significant bit first, 1 for black), that [data] codes. Lines
/// are runs as libtiff keeps them (zero-length runs included, which
/// later lines' two-dimensional codes count); a damaged line is ended as
/// libtiff ends it, and what the data lacks is left white.
Uint8List faxDecode(
  Uint8List data,
  int width,
  int rows, {
  required FaxCoding coding,
  bool twoDimensional = false,
  bool byteAlignedEol = false,
}) {
  final stride = (width + 7) >> 3;
  final out = Uint8List(stride * rows);
  final decoder = _Fax(_Bits(data), width);
  for (var row = 0; row < rows; row++) {
    var twoD = coding == FaxCoding.group4;
    if (coding == FaxCoding.rle) {
      decoder.reader.alignToByte();
    } else if (coding == FaxCoding.group3) {
      // An EOL code (zeros then a one; maybe padded to end on a byte):
      // where there is one (some writers leave them out).
      decoder.reader.skipEol(byteAligned: byteAlignedEol);
      if (twoDimensional) twoD = decoder.reader.bit() == 0;
    }
    if (decoder.reader.exhausted) break;
    decoder.start();
    if (twoD) {
      decoder.row2D();
    } else {
      decoder.row1D();
    }
    decoder
      ..cleanup()
      ..fill(out, row * stride)
      ..finish();
  }
  return out;
}

/// A line as libtiff decodes it: run lengths, white first, alternating.
final class _Fax {
  new(this.reader, this.width)
    : runs = Int32List(2 * width + 8),
      reference = Int32List(2 * width + 8) {
    // The line before the first: all white.
    reference[0] = width;
    reference[1] = 0;
  }

  final _Bits reader;
  final int width;
  Int32List runs;
  Int32List reference;

  /// The runs so far, the position reached, and a run's length pending
  /// (pass codes and makeup codes add to it).
  int count = 0;
  int a0 = 0;
  int pending = 0;

  void start() {
    count = 0;
    a0 = 0;
    pending = 0;
  }

  void setValue(int x) {
    if (count >= runs.length) return;
    runs[count++] = pending + x;
    a0 += x;
    pending = 0;
  }

  /// A run of [color]: makeup codes, then a terminating one; false at an
  /// EOL or a code the table hasn't.
  bool _run(int color) {
    final table = color == 0 ? _white : _black;
    while (true) {
      final run = table.readOrNull(reader);
      if (run == null) return false;
      if (run < 64) {
        setValue(run);
        return true;
      }
      a0 += run;
      pending += run;
    }
  }

  void row1D() {
    while (true) {
      if (!_run(0) || a0 >= width) return;
      if (!_run(1) || a0 >= width) return;
      // (Two zero runs in a row are dropped, as libtiff drops them.)
      if (count >= 2 && runs[count - 1] == 0 && runs[count - 2] == 0) {
        count -= 2;
      }
    }
  }

  void row2D() {
    // b1: a position on the reference line; r: the next run to add.
    var r = 0;
    int ref(int i) {
      if (i < 0 || i >= reference.length) throw const _FaxError();
      return reference[i];
    }

    var b1 = ref(r++);
    void checkB1() {
      if (count > 0) {
        while (b1 <= a0 && b1 < width) {
          b1 += ref(r) + ref(r + 1);
          r += 2;
        }
      }
    }

    try {
      while (a0 < width) {
        final mode = _modes.readOrNull(reader);
        if (mode == null) return;
        switch (mode) {
          case _pass:
            checkB1();
            b1 += ref(r++);
            pending += b1 - a0;
            a0 = b1;
            b1 += ref(r++);
          case _horizontal:
            final color = count & 1;
            if (!_run(color)) return;
            if (!_run(color ^ 1)) return;
            checkB1();
          case _extension:
            return;
          default:
            final offset = mode - _vertical - 3;
            checkB1();
            if (offset < 0) {
              if (b1 < a0 - offset) return;
              setValue(b1 - a0 + offset);
              b1 -= ref(--r);
            } else {
              setValue(b1 - a0 + offset);
              b1 += ref(r++);
            }
        }
      }
      if (pending != 0) {
        if (pending + a0 < width) {
          // A final V0 is expected.
          if (reader.bit() != 1) return;
        }
        setValue(0);
      }
    } on _FaxError {
      // A reference line run out, or too many runs: as a damaged line.
      return;
    }
  }

  /// Ends the line at its width, as libtiff's CLEANUP_RUNS does.
  void cleanup() {
    if (pending != 0) setValue(0);
    if (a0 != width) {
      while (a0 > width && count > 0) {
        a0 -= runs[--count];
      }
      if (a0 < width) {
        if (a0 < 0) a0 = 0;
        if (count & 1 == 1) setValue(0);
        setValue(width - a0);
      } else if (a0 > width) {
        setValue(width);
        setValue(0);
      }
    }
  }

  /// The runs' black pixels into the packed row at [at].
  void fill(Uint8List out, int at) {
    var x = 0;
    for (var i = 0; i < count; i++) {
      final run = runs[i];
      final end = x + run > width ? width : x + run;
      if (i.isOdd) {
        for (var p = x; p < end; p++) {
          out[at + (p >> 3)] |= 0x80 >> (p & 7);
        }
      }
      x = end;
      if (x >= width) break;
    }
  }

  /// The line becomes the next one's reference (with an imaginary
  /// change after it).
  void finish() {
    setValue(0);
    final swap = reference;
    reference = runs;
    runs = swap;
  }
}

final class _FaxError implements Exception {
  const new();
}

/// Bits most significant first; past the end, zeros (and [exhausted]).
final class _Bits {
  new(this.data);

  final Uint8List data;
  int at = 0;
  int _bits = 0;
  int _held = 0;

  /// Whether reading has gone past the data (and its bits are the zeros
  /// supplied after it).
  bool get exhausted => at - (_held >> 3) > data.length;

  void _fill() {
    while (_held <= 24) {
      _bits = ((_bits & 0xffffff) << 8) | (at < data.length ? data[at] : 0);
      at++;
      _held += 8;
    }
  }

  int peek(int n) {
    if (_held < n) _fill();
    return (_bits >> (_held - n)) & ((1 << n) - 1);
  }

  void skip(int n) {
    if (_held < n) _fill();
    _held -= n;
  }

  int bit() {
    final b = peek(1);
    skip(1);
    return b;
  }

  void alignToByte() => _held -= _held & 7;

  /// Skips an EOL code (eleven or more zeros, then a one) if one comes;
  /// whether it did.
  bool skipEol({required bool byteAligned}) {
    var zeros = 0;
    while (peek(1) == 0) {
      skip(1);
      zeros++;
      if (exhausted) return false;
    }
    if (zeros >= 11) {
      skip(1);
      return true;
    }
    // Not an EOL: put the zeros back (they begin a code).
    _held += zeros;
    return false;
  }
}

/// A code table: for each (length, code), its run or mode, looked up by
/// the next 13 bits.
final class _Table {
  factory of(Map<int, String> codes) {
    final lookup = Int32List(1 << 13)..fillRange(0, 1 << 13, -1);
    for (final MapEntry(key: value, value: code) in codes.entries) {
      final length = code.length;
      final bits = int.parse(code, radix: 2);
      final shift = 13 - length;
      for (var fill = 0; fill < 1 << shift; fill++) {
        lookup[(bits << shift) | fill] = length << 16 | value;
      }
    }
    return _Table._(lookup);
  }

  const new _(this.lookup);

  final Int32List lookup;

  /// The next code's value, or null at an EOL or a code the table
  /// hasn't (the code left unread).
  int? readOrNull(_Bits reader) {
    final entry = lookup[reader.peek(13)];
    if (entry < 0) return null;
    reader.skip(entry >> 16);
    return entry & 0xffff;
  }
}

// Two-dimensional modes.
const int _pass = 0x100;
const int _horizontal = 0x101;
const int _extension = 0x102;
const int _vertical = 0x200; // + 3 + offset (offsets -3 to 3)

final _Table _white = _Table.of({
  0: '00110101', 1: '000111', 2: '0111', 3: '1000', 4: '1011', 5: '1100', //
  6: '1110', 7: '1111', 8: '10011', 9: '10100', 10: '00111', 11: '01000',
  12: '001000', 13: '000011', 14: '110100', 15: '110101', 16: '101010',
  17: '101011', 18: '0100111', 19: '0001100', 20: '0001000', 21: '0010111',
  22: '0000011', 23: '0000100', 24: '0101000', 25: '0101011', 26: '0010011',
  27: '0100100', 28: '0011000', 29: '00000010', 30: '00000011',
  31: '00011010', 32: '00011011', 33: '00010010', 34: '00010011',
  35: '00010100', 36: '00010101', 37: '00010110', 38: '00010111',
  39: '00101000', 40: '00101001', 41: '00101010', 42: '00101011',
  43: '00101100', 44: '00101101', 45: '00000100', 46: '00000101',
  47: '00001010', 48: '00001011', 49: '01010010', 50: '01010011',
  51: '01010100', 52: '01010101', 53: '00100100', 54: '00100101',
  55: '01011000', 56: '01011001', 57: '01011010', 58: '01011011',
  59: '01001010', 60: '01001011', 61: '00110010', 62: '00110011',
  63: '00110100',
  64: '11011', 128: '10010', 192: '010111', 256: '0110111', 320: '00110110',
  384: '00110111', 448: '01100100', 512: '01100101', 576: '01101000',
  640: '01100111', 704: '011001100', 768: '011001101', 832: '011010010',
  896: '011010011', 960: '011010100', 1024: '011010101', 1088: '011010110',
  1152: '011010111', 1216: '011011000', 1280: '011011001',
  1344: '011011010', 1408: '011011011', 1472: '010011000',
  1536: '010011001', 1600: '010011010', 1664: '011000', 1728: '010011011',
  ..._extendedMakeup,
});

final _Table _black = _Table.of({
  0: '0000110111', 1: '010', 2: '11', 3: '10', 4: '011', 5: '0011', //
  6: '0010', 7: '00011', 8: '000101', 9: '000100', 10: '0000100',
  11: '0000101', 12: '0000111', 13: '00000100', 14: '00000111',
  15: '000011000', 16: '0000010111', 17: '0000011000', 18: '0000001000',
  19: '00001100111', 20: '00001101000', 21: '00001101100',
  22: '00000110111', 23: '00000101000', 24: '00000010111',
  25: '00000011000', 26: '000011001010', 27: '000011001011',
  28: '000011001100', 29: '000011001101', 30: '000001101000',
  31: '000001101001', 32: '000001101010', 33: '000001101011',
  34: '000011010010', 35: '000011010011', 36: '000011010100',
  37: '000011010101', 38: '000011010110', 39: '000011010111',
  40: '000001101100', 41: '000001101101', 42: '000011011010',
  43: '000011011011', 44: '000001010100', 45: '000001010101',
  46: '000001010110', 47: '000001010111', 48: '000001100100',
  49: '000001100101', 50: '000001010010', 51: '000001010011',
  52: '000000100100', 53: '000000110111', 54: '000000111000',
  55: '000000100111', 56: '000000101000', 57: '000001011000',
  58: '000001011001', 59: '000000101011', 60: '000000101100',
  61: '000001011010', 62: '000001100110', 63: '000001100111',
  64: '0000001111', 128: '000011001000', 192: '000011001001',
  256: '000001011011', 320: '000000110011', 384: '000000110100',
  448: '000000110101', 512: '0000001101100', 576: '0000001101101',
  640: '0000001001010', 704: '0000001001011', 768: '0000001001100',
  832: '0000001001101', 896: '0000001110010', 960: '0000001110011',
  1024: '0000001110100', 1088: '0000001110101', 1152: '0000001110110',
  1216: '0000001110111', 1280: '0000001010010', 1344: '0000001010011',
  1408: '0000001010100', 1472: '0000001010101', 1536: '0000001011010',
  1600: '0000001011011', 1664: '0000001100100', 1728: '0000001100101',
  ..._extendedMakeup,
});

const Map<int, String> _extendedMakeup = {
  1792: '00000001000', 1856: '00000001100', 1920: '00000001101', //
  1984: '000000010010', 2048: '000000010011', 2112: '000000010100',
  2176: '000000010101', 2240: '000000010110', 2304: '000000010111',
  2368: '000000011100', 2432: '000000011101', 2496: '000000011110',
  2560: '000000011111',
};

final _Table _modes = _Table.of({
  _pass: '0001',
  _horizontal: '001',
  _vertical + 3: '1',
  _vertical + 4: '011',
  _vertical + 5: '000011',
  _vertical + 6: '0000011',
  _vertical + 2: '010',
  _vertical + 1: '000010',
  _vertical + 0: '0000010',
  _extension: '0000001',
});
