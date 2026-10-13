/// JPEG (ITU-T T.81 | ISO/IEC 10918-1) decoding: baseline, extended
/// (12-bit), progressive and lossless, with Huffman or arithmetic coding,
/// restart intervals, any sampling factors; then the samples as
/// libjpeg(-turbo) makes them by default: its accurate integer inverse DCT
/// (Loeffler, Ligtenberg and Moschytz's), its "fancy" (triangle)
/// upsampling of chroma, its YCbCr to RGB conversion.
library;

import 'dart:typed_data';

import 'package:plain_images/src/exception.dart';

/// A decoded JPEG image: `width` by `height` pixels of `channels`
/// samples (1 gray, 3 RGB, 4 CMYK as stored), each `precision` bits, row
/// after row, in `samples`; whether it has an Adobe segment, and its
/// transform.
typedef JpegPixels = ({
  int width,
  int height,
  int channels,
  int precision,
  Uint16List samples,
  bool adobe,
  int adobeTransform,
});

/// The zigzag order: the position in a block of each coefficient in
/// coding order.
const List<int> _natural = [
  0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5, //
  12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13, 6, 7, 14, 21, 28,
  35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51,
  58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62, 63,
  // Past the end, for corrupt data (as libjpeg pads it).
  63, 63, 63, 63, 63, 63, 63, 63, 63, 63, 63, 63, 63, 63, 63, 63,
];

/// The JPEG image in [data]; [tables], if given, is a stream of tables
/// (quantization, Huffman, restart interval) read first (TIFF's
/// JPEGTables); [ycc], if given, whether three components are YCbCr to
/// convert to RGB (else as the file's markers tell, as libjpeg tells it).
JpegPixels decodeJpeg(Uint8List data, {Uint8List? tables, bool? ycc}) {
  final decoder = _Decoder().._ycc = ycc;
  if (tables != null) decoder.read(tables, tablesOnly: true);
  decoder.read(data);
  return decoder.output();
}

final class _Component {
  new(this.id, this.h, this.v, this.quantTable);

  final int id;
  final int h;
  final int v;
  final int quantTable;

  /// The quantization table latched at its first scan.
  Int32List? quant;

  /// Blocks per line and per column, padded to whole MCUs.
  int blocksPerLine = 0;
  int blocksPerColumn = 0;

  /// Blocks per line and column the component itself covers.
  int widthInBlocks = 0;
  int heightInBlocks = 0;

  /// Its samples' size (before upsampling).
  int downsampledWidth = 0;
  int downsampledHeight = 0;

  /// The coefficients, 64 a block, in natural order, not dequantized.
  late Int16List coefficients;

  /// A lossless image's samples (point transform not yet undone).
  Int32List samples = Int32List(0);

  /// Arithmetic coding's DC context.
  int dcContext = 0;

  int dcPredictor = 0;
  int dcTable = 0;
  int acTable = 0;
}

/// A Huffman table: a lookup of the next 9 bits, then the canonical
/// codes' limits for longer ones (T.81, F.2.2.3).
final class _Huffman {
  factory of(List<int> counts, List<int> symbols) {
    final lookup = Int32List(1 << _lookahead);
    final maxCode = Int32List(18)..fillRange(0, 18, -1);
    final valPtr = Int32List(17);
    final minCode = Int32List(17);
    var code = 0;
    var k = 0;
    for (var length = 1; length <= 16; length++) {
      valPtr[length] = k;
      minCode[length] = code;
      for (var i = 0; i < counts[length - 1]; i++) {
        if (code >= 1 << length) {
          throw const ImageFormatException('JPEG Huffman table is damaged');
        }
        if (length <= _lookahead) {
          // Every lookahead value starting with this code.
          final shift = _lookahead - length;
          for (var fill = 0; fill < 1 << shift; fill++) {
            lookup[(code << shift) | fill] = length << 8 | symbols[k];
          }
        }
        code++;
        k++;
      }
      maxCode[length] = counts[length - 1] == 0 ? -1 : code - 1;
      // The codes must fit their length, none all ones (T.81, C).
      if (counts[length - 1] > 0 && code >= 1 << length) {
        throw const ImageFormatException('JPEG Huffman table is damaged');
      }
      code <<= 1;
    }
    maxCode[17] = 0x7fffffff;
    return _Huffman._(lookup, maxCode, valPtr, minCode, symbols);
  }

  const new _(
    this.lookup,
    this.maxCode,
    this.valPtr,
    this.minCode,
    this.symbols,
  );

  static const int _lookahead = 9;

  final Int32List lookup;
  final Int32List maxCode;
  final Int32List valPtr;
  final Int32List minCode;
  final List<int> symbols;
}

final class _Decoder {
  final List<Int32List?> _quant = List.filled(4, null);
  final List<_Huffman?> _dcTables = List.filled(4, null);
  final List<_Huffman?> _acTables = List.filled(4, null);
  var _restartInterval = 0;
  var _arithmetic = false;
  var _lossless = false;

  // Arithmetic coding's conditioning (DAC) and statistics.
  final List<int> _dcL = List.filled(4, 0);
  final List<int> _dcU = List.filled(4, 1);
  final List<int> _acK = List.filled(4, 5);
  final List<Uint8List> _dcStats = [for (var i = 0; i < 4; i++) Uint8List(64)];
  final List<Uint8List> _acStats = [for (var i = 0; i < 4; i++) Uint8List(256)];
  final Uint8List _fixedBin = Uint8List(1);
  var _c = 0;
  var _a = 0;
  var _ct = 0;

  var _width = 0;
  var _height = 0;
  var _precision = 8;
  var _progressive = false;
  var _frame = false;
  final List<_Component> _components = [];
  var _hMax = 1;
  var _vMax = 1;
  var _mcusPerLine = 0;
  var _mcuRows = 0;

  var _jfif = false;
  bool? _ycc;
  bool adobe = false;
  int adobeTransform = -1;

  // The bit reader over the entropy-coded data.
  late Uint8List _data;
  var _at = 0;
  var _bits = 0;
  var _held = 0;
  // A marker met in the data: no more bits until the next restart.
  var _marker = false;
  var _eobRun = 0;

  void read(Uint8List data, {bool tablesOnly = false}) {
    _data = data;
    if (data.length < 2 || data[0] != 0xff || data[1] != 0xd8) {
      throw const ImageFormatException('not a JPEG image');
    }
    var at = 2;
    while (at < data.length) {
      // The next marker (fill bytes skipped).
      if (data[at] != 0xff) {
        // Junk between segments: skip to the next 0xFF.
        at++;
        continue;
      }
      while (at < data.length && data[at] == 0xff) {
        at++;
      }
      if (at >= data.length) break;
      final marker = data[at++];
      if (marker == 0xd9) return; // EOI
      if (marker >= 0xd0 && marker <= 0xd7 || marker == 0x01) continue;
      if (at + 2 > data.length) {
        throw const ImageFormatException('JPEG segment is truncated');
      }
      final length = data[at] << 8 | data[at + 1];
      final end = at + length;
      if (length < 2 || end > data.length) {
        throw const ImageFormatException('JPEG segment is truncated');
      }
      final segment = Uint8List.sublistView(data, at + 2, end);
      switch (marker) {
        case 0xdb:
          _readQuant(segment);
        case 0xc4:
          _readHuffman(segment);
        case 0xdd:
          if (segment.length < 2) {
            throw const ImageFormatException('JPEG restart interval');
          }
          _restartInterval = segment[0] << 8 | segment[1];
        case 0xe0 when _startsWith(segment, 'JFIF\u0000'):
          _jfif = true;
        case 0xee when _startsWith(segment, 'Adobe') && segment.length >= 12:
          adobe = true;
          adobeTransform = segment[11];
        case 0xc0 || 0xc1 || 0xc2 || 0xc3 || 0xc9 || 0xca:
          if (tablesOnly) break;
          _arithmetic = marker >= 0xc9;
          _lossless = marker == 0xc3;
          _readFrame(segment, progressive: marker == 0xc2 || marker == 0xca);
        case 0xc5 || 0xc6 || 0xc7 || 0xcd || 0xce || 0xcf:
          throw const ImageFormatException(
            'JPEG hierarchical images are not supported',
          );
        case 0xcb:
          throw const ImageFormatException(
            'JPEG lossless images with arithmetic coding are not supported',
          );
        case 0xcc:
          _readConditioning(segment);
        case 0xda:
          if (!_frame) {
            throw const ImageFormatException('JPEG scan before its frame');
          }
          at = _readScan(segment, end);
          continue;
      }
      at = end;
    }
  }

  static bool _startsWith(Uint8List segment, String text) {
    if (segment.length < text.length) return false;
    for (var i = 0; i < text.length; i++) {
      if (segment[i] != text.codeUnitAt(i)) return false;
    }
    return true;
  }

  void _readQuant(Uint8List segment) {
    var at = 0;
    while (at < segment.length) {
      final precision = segment[at] >> 4;
      final id = segment[at] & 15;
      at++;
      if (id > 3) throw const ImageFormatException('JPEG quantization table');
      final table = Int32List(64);
      for (var k = 0; k < 64; k++) {
        if (at + (precision == 0 ? 1 : 2) > segment.length) {
          throw const ImageFormatException('JPEG quantization table');
        }
        // Stored in zigzag order.
        table[_natural[k]] = precision == 0
            ? segment[at++]
            : segment[at++] << 8 | segment[at++];
      }
      _quant[id] = table;
    }
  }

  void _readHuffman(Uint8List segment) {
    var at = 0;
    while (at + 17 <= segment.length) {
      final tableClass = segment[at] >> 4;
      final id = segment[at] & 15;
      if (id > 3 || tableClass > 1) {
        throw const ImageFormatException('JPEG Huffman table');
      }
      final counts = segment.sublist(at + 1, at + 17);
      at += 17;
      final total = counts.fold<int>(0, (a, b) => a + b);
      if (total > 256 || at + total > segment.length) {
        throw const ImageFormatException('JPEG Huffman table');
      }
      final symbols = segment.sublist(at, at + total);
      at += total;
      final table = _Huffman.of(counts, symbols);
      if (tableClass == 0) {
        _dcTables[id] = table;
      } else {
        _acTables[id] = table;
      }
    }
  }

  void _readConditioning(Uint8List segment) {
    for (var at = 0; at + 1 < segment.length; at += 2) {
      final tableClass = segment[at] >> 4;
      final id = segment[at] & 15;
      final value = segment[at + 1];
      if (id > 3) throw const ImageFormatException('JPEG conditioning');
      if (tableClass == 0) {
        _dcL[id] = value & 15;
        _dcU[id] = value >> 4;
      } else {
        _acK[id] = value;
      }
    }
  }

  void _readFrame(Uint8List s, {required bool progressive}) {
    if (_frame) throw const ImageFormatException('JPEG has two frames');
    if (s.length < 6) throw const ImageFormatException('JPEG frame header');
    _precision = s[0];
    _height = s[1] << 8 | s[2];
    _width = s[3] << 8 | s[4];
    final count = s[5];
    if (_lossless
        ? _precision < 2 || _precision > 16
        : _precision != 8 && _precision != 12) {
      throw ImageFormatException('JPEG precision $_precision');
    }
    if (_width == 0 || _height == 0) {
      throw const ImageFormatException(
        'JPEG images whose height is set by a DNL marker are not supported',
      );
    }
    if (count == 0 || s.length < 6 + 3 * count) {
      throw const ImageFormatException('JPEG frame header');
    }
    _progressive = progressive;
    for (var i = 0; i < count; i++) {
      final at = 6 + 3 * i;
      final h = s[at + 1] >> 4;
      final v = s[at + 1] & 15;
      if (h < 1 || h > 4 || v < 1 || v > 4) {
        throw const ImageFormatException('JPEG sampling factors');
      }
      _components.add(_Component(s[at], h, v, s[at + 2] & 3));
    }
    for (final c in _components) {
      if (c.h > _hMax) _hMax = c.h;
      if (c.v > _vMax) _vMax = c.v;
    }
    // (A lossless image's "blocks" are single samples.)
    final block = _lossless ? 1 : 8;
    _mcusPerLine = _ceilDiv(_width, block * _hMax);
    _mcuRows = _ceilDiv(_height, block * _vMax);
    for (final c in _components) {
      c
        ..downsampledWidth = _ceilDiv(_width * c.h, _hMax)
        ..downsampledHeight = _ceilDiv(_height * c.v, _vMax)
        ..widthInBlocks = _ceilDiv(_ceilDiv(_width * c.h, _hMax), block)
        ..heightInBlocks = _ceilDiv(_ceilDiv(_height * c.v, _vMax), block)
        ..blocksPerLine = _mcusPerLine * c.h
        ..blocksPerColumn = _mcuRows * c.v;
      c.coefficients = Int16List(
        c.blocksPerLine * c.blocksPerColumn * (_lossless ? 0 : 64),
      );
      if (_lossless) c.samples = Int32List(c.blocksPerLine * c.blocksPerColumn);
    }
    _frame = true;
  }

  /// Reads the scan whose header is [s], its data from [from]; where the
  /// next marker is.
  int _readScan(Uint8List s, int from) {
    final count = s[0];
    if (count < 1 || count > 4 || s.length < 1 + 2 * count + 3) {
      throw const ImageFormatException('JPEG scan header');
    }
    final scan = <_Component>[];
    for (var i = 0; i < count; i++) {
      final id = s[1 + 2 * i];
      final component = _components.where((c) => c.id == id).firstOrNull;
      if (component == null) {
        throw const ImageFormatException('JPEG scan of an unknown component');
      }
      component
        ..dcTable = s[2 + 2 * i] >> 4
        ..acTable = s[2 + 2 * i] & 15;
      if (component.dcTable > 3 || component.acTable > 3) {
        throw const ImageFormatException('JPEG scan selects no table');
      }
      // The quantization table, latched at the component's first scan.
      component.quant ??= _quant[component.quantTable];
      scan.add(component);
    }
    final at = 1 + 2 * count;
    final ss = s[at];
    final se = s[at + 1];
    final ah = s[at + 2] >> 4;
    final al = s[at + 2] & 15;
    if (_progressive &&
        (se > 63 || ss > se || (ss == 0 && se != 0) || al > 13 || ah > 13)) {
      throw const ImageFormatException('JPEG progressive scan parameters');
    }
    if (_lossless && al >= _precision) {
      throw const ImageFormatException('JPEG point transform');
    }
    _at = from;
    _bits = 0;
    _held = 0;
    _marker = false;
    _eobRun = 0;
    for (final c in scan) {
      c
        ..dcPredictor = 0
        ..dcContext = 0;
    }
    if (_lossless) return _readLosslessScan(scan, ss, al, from);
    if (_arithmetic) {
      _arithmeticStart(scan, ss: ss, ah: ah);
    }
    void Function(_Component, int) decodeBlock;
    if (_arithmetic) {
      decodeBlock = switch ((_progressive, ss == 0, ah == 0)) {
        (false, _, _) => _arithmeticSequential,
        (true, true, true) => (c, offset) => _arithmeticDcFirst(c, offset, al),
        (true, true, false) => (c, offset) => _arithmeticDcRefine(
          c,
          offset,
          al,
        ),
        (true, false, true) => (c, offset) => _arithmeticAcFirst(
          c,
          offset,
          ss,
          se,
          al,
        ),
        (true, false, false) => (c, offset) => _arithmeticAcRefine(
          c,
          offset,
          ss,
          se,
          al,
        ),
      };
    } else if (!_progressive) {
      decodeBlock = _decodeBaseline;
    } else if (ss == 0) {
      decodeBlock = ah == 0
          ? (c, offset) => _decodeDcFirst(c, offset, al)
          : (c, offset) => _decodeDcRefine(c, offset, al);
    } else {
      if (count != 1) {
        throw const ImageFormatException('JPEG AC scan of more components');
      }
      decodeBlock = ah == 0
          ? (c, offset) => _decodeAcFirst(c, offset, ss, se, al)
          : (c, offset) => _decodeAcRefine(c, offset, ss, se, al);
    }
    for (final c in scan) {
      if (_arithmetic) break;
      if (_dcTables[c.dcTable] == null &&
          (!_progressive || ss == 0) &&
          !(_progressive && ah > 0)) {
        throw const ImageFormatException('JPEG Huffman table is missing');
      }
      if (_acTables[c.acTable] == null && (!_progressive || ss > 0)) {
        throw const ImageFormatException('JPEG Huffman table is missing');
      }
    }
    final single = count == 1;
    final total = single
        ? scan.first.widthInBlocks * scan.first.heightInBlocks
        : _mcusPerLine * _mcuRows;
    var restarts = _restartInterval;
    for (var mcu = 0; mcu < total; mcu++) {
      if (_restartInterval > 0) {
        if (restarts == 0) {
          _restart(scan);
          if (_arithmetic) _arithmeticStart(scan, ss: ss, ah: ah);
          restarts = _restartInterval;
        }
        restarts--;
      }
      if (single) {
        final c = scan.first;
        final row = mcu ~/ c.widthInBlocks;
        final column = mcu % c.widthInBlocks;
        decodeBlock(c, (row * c.blocksPerLine + column) * 64);
      } else {
        final mcuRow = mcu ~/ _mcusPerLine;
        final mcuColumn = mcu % _mcusPerLine;
        for (final c in scan) {
          for (var v = 0; v < c.v; v++) {
            for (var h = 0; h < c.h; h++) {
              final row = mcuRow * c.v + v;
              final column = mcuColumn * c.h + h;
              decodeBlock(c, (row * c.blocksPerLine + column) * 64);
            }
          }
        }
      }
    }
    // The next marker: past the scan's data.
    var at2 = _at;
    while (at2 + 1 < _data.length) {
      if (_data[at2] == 0xff &&
          _data[at2 + 1] != 0 &&
          !(_data[at2 + 1] >= 0xd0 && _data[at2 + 1] <= 0xd7)) {
        return at2;
      }
      at2++;
    }
    return _data.length;
  }

  /// At a restart marker: the bits dropped, the marker read, predictions
  /// reset.
  void _restart(List<_Component> scan) {
    _bits = 0;
    _held = 0;
    // The marker: the RSTn at hand, else further on.
    var at = _at;
    while (at + 1 < _data.length) {
      if (_data[at] == 0xff && _data[at + 1] >= 0xd0 && _data[at + 1] <= 0xd7) {
        _at = at + 2;
        break;
      }
      if (_data[at] == 0xff && _data[at + 1] != 0 && _data[at + 1] != 0xff) {
        // Another marker: stop here (the rest reads as zeros).
        _at = at;
        break;
      }
      at++;
    }
    _marker = false;
    _eobRun = 0;
    for (final c in scan) {
      c.dcPredictor = 0;
    }
  }

  /// Fills the bit buffer to at least 25 bits; past a marker, zeros.
  void _fill() {
    while (_held <= 24) {
      var byte = 0;
      if (!_marker && _at < _data.length) {
        byte = _data[_at];
        if (byte == 0xff) {
          final next = _at + 1 < _data.length ? _data[_at + 1] : 0xd9;
          if (next == 0) {
            _at += 2;
          } else if (next == 0xff) {
            // Fill bytes before a marker.
            _at++;
            continue;
          } else {
            _marker = true;
            byte = 0;
          }
        } else {
          _at++;
        }
      }
      // (Only the bits held are kept: 32 at most.)
      _bits = ((_bits & 0xffffff) << 8) | byte;
      _held += 8;
    }
  }

  int _bit() {
    if (_held == 0) _fill();
    _held--;
    return (_bits >> _held) & 1;
  }

  int _receive(int n) {
    if (n == 0) return 0;
    if (n > 16) {
      // (A DC table's symbol is a bit count: 16 at most.)
      throw const ImageFormatException('JPEG Huffman table is damaged');
    }
    if (_held < n) _fill();
    _held -= n;
    return (_bits >> _held) & ((1 << n) - 1);
  }

  /// [n] bits as a signed value (T.81, F.2.2.1).
  int _receiveExtend(int n) {
    if (n == 0) return 0;
    final v = _receive(n);
    return v < 1 << (n - 1) ? v - (1 << n) + 1 : v;
  }

  int _decode(_Huffman table) {
    if (_held < 16) _fill();
    final look =
        (_bits >> (_held - _Huffman._lookahead)) &
        ((1 << _Huffman._lookahead) - 1);
    final entry = table.lookup[look];
    if (entry != 0) {
      _held -= entry >> 8;
      return entry & 0xff;
    }
    // Longer codes: bit by bit past the lookahead.
    var length = _Huffman._lookahead + 1;
    var code = (_bits >> (_held - length)) & ((1 << length) - 1);
    while (code > table.maxCode[length]) {
      if (++length > 16) break;
      code = (_bits >> (_held - length)) & ((1 << length) - 1);
    }
    if (length > 16) {
      // A code no table has: corrupt data, read as 0 (as libjpeg does).
      _held -= 16;
      return 0;
    }
    _held -= length;
    final index = table.valPtr[length] + code - table.minCode[length];
    return index < table.symbols.length ? table.symbols[index] : 0;
  }

  void _decodeBaseline(_Component c, int offset) {
    final dc = _dcTables[c.dcTable]!;
    final ac = _acTables[c.acTable]!;
    final block = c.coefficients;
    final t = _decode(dc);
    c.dcPredictor += _receiveExtend(t);
    block[offset] = c.dcPredictor;
    for (var k = 1; k < 64;) {
      final rs = _decode(ac);
      final r = rs >> 4;
      final s = rs & 15;
      if (s == 0) {
        if (r != 15) break;
        k += 16;
        continue;
      }
      k += r;
      block[offset + _natural[k]] = _receiveExtend(s);
      k++;
    }
  }

  void _decodeDcFirst(_Component c, int offset, int al) {
    final t = _decode(_dcTables[c.dcTable]!);
    c.dcPredictor += _receiveExtend(t);
    c.coefficients[offset] = c.dcPredictor << al;
  }

  void _decodeDcRefine(_Component c, int offset, int al) {
    if (_bit() == 1) c.coefficients[offset] |= 1 << al;
  }

  void _decodeAcFirst(_Component c, int offset, int ss, int se, int al) {
    if (_eobRun > 0) {
      _eobRun--;
      return;
    }
    final ac = _acTables[c.acTable]!;
    final block = c.coefficients;
    for (var k = ss; k <= se; k++) {
      final rs = _decode(ac);
      final r = rs >> 4;
      final s = rs & 15;
      if (s != 0) {
        k += r;
        block[offset + _natural[k]] = _receiveExtend(s) * (1 << al);
      } else if (r == 15) {
        k += 15;
      } else {
        _eobRun = 1 << r;
        if (r != 0) _eobRun += _receive(r);
        _eobRun--;
        break;
      }
    }
  }

  void _decodeAcRefine(_Component c, int offset, int ss, int se, int al) {
    final p1 = 1 << al;
    final m1 = -(1 << al);
    final block = c.coefficients;
    var k = ss;
    if (_eobRun == 0) {
      final ac = _acTables[c.acTable]!;
      for (; k <= se; k++) {
        final rs = _decode(ac);
        var r = rs >> 4;
        var s = rs & 15;
        if (s != 0) {
          s = _bit() == 1 ? p1 : m1;
        } else if (r != 15) {
          _eobRun = 1 << r;
          if (r != 0) _eobRun += _receive(r);
          break;
        }
        do {
          final at = offset + _natural[k];
          final coefficient = block[at];
          if (coefficient != 0) {
            if (_bit() == 1 && (coefficient & p1) == 0) {
              block[at] = coefficient >= 0
                  ? coefficient + p1
                  : coefficient + m1;
            }
          } else {
            if (--r < 0) break;
          }
          k++;
        } while (k <= se);
        if (s != 0 && k <= 63) block[offset + _natural[k]] = s;
      }
    }
    if (_eobRun > 0) {
      for (; k <= se; k++) {
        final at = offset + _natural[k];
        final coefficient = block[at];
        if (coefficient != 0 && _bit() == 1 && (coefficient & p1) == 0) {
          block[at] = coefficient >= 0 ? coefficient + p1 : coefficient + m1;
        }
      }
      _eobRun--;
    }
  }

  // Arithmetic decoding (T.81, Annex D; F.2.4 and G.1.3.3), with
  // libjpeg's representation of its statistics.

  /// At a scan's start and each restart: the statistics of the scan's
  /// tables cleared, the decoder reset.
  void _arithmeticStart(
    List<_Component> scan, {
    required int ss,
    required int ah,
  }) {
    for (final c in scan) {
      if (!_progressive || (ss == 0 && ah == 0)) {
        _dcStats[c.dcTable].fillRange(0, 64, 0);
      }
      if (!_progressive || ss != 0) _acStats[c.acTable].fillRange(0, 256, 0);
      c
        ..dcPredictor = 0
        ..dcContext = 0;
    }
    _fixedBin[0] = 113;
    _c = 0;
    _a = 0;
    _ct = -16;
    _marker = false;
  }

  /// One binary decision with the statistics bin [stats][[at]].
  int _arithmeticDecode(Uint8List stats, int at) {
    while (_a < 0x8000) {
      if (--_ct < 0) {
        var byte = 0;
        if (!_marker && _at < _data.length) {
          byte = _data[_at++];
          if (byte == 0xff) {
            while (_at < _data.length && _data[_at] == 0xff) {
              _at++;
            }
            final next = _at < _data.length ? _data[_at] : 0xd9;
            if (next == 0) {
              _at++;
            } else {
              // A marker: zeros from here (the marker is left unread).
              _at--;
              _marker = true;
              byte = 0;
            }
          }
        }
        _c = ((_c << 8) | byte) & 0xffffffff;
        _ct += 8;
        if (_ct < 0 && ++_ct == 0) _a = 0x8000;
      }
      _a <<= 1;
    }
    final state = stats[at];
    final entry = _arithmeticTable[state & 0x7f];
    final qe = entry >> 16;
    final nextMps = (entry >> 8) & 0xff;
    final nextLps = entry & 0xff;
    var sv = state;
    var temp = _a - qe;
    _a = temp;
    temp <<= _ct;
    if (_c >= temp) {
      _c -= temp;
      if (_a < qe) {
        _a = qe;
        stats[at] = (sv & 0x80) ^ nextMps;
      } else {
        _a = qe;
        stats[at] = (sv & 0x80) ^ nextLps;
        sv ^= 0x80;
      }
    } else if (_a < 0x8000) {
      if (_a < qe) {
        stats[at] = (sv & 0x80) ^ nextLps;
        sv ^= 0x80;
      } else {
        stats[at] = (sv & 0x80) ^ nextMps;
      }
    }
    return sv >> 7;
  }

  /// A DC difference (F.2.4.1), its conditioning updated.
  int _arithmeticDc(_Component c) {
    final stats = _dcStats[c.dcTable];
    var at = c.dcContext;
    if (_arithmeticDecode(stats, at) == 0) {
      c.dcContext = 0;
      return 0;
    }
    final sign = _arithmeticDecode(stats, at + 1);
    at += 2 + sign;
    var m = _arithmeticDecode(stats, at);
    if (m != 0) {
      at = 20;
      while (_arithmeticDecode(stats, at) == 1) {
        if ((m <<= 1) == 0x8000) return 0;
        at++;
      }
    }
    final table = c.dcTable;
    if (m < (1 << _dcL[table]) >> 1) {
      c.dcContext = 0;
    } else if (m > (1 << _dcU[table]) >> 1) {
      c.dcContext = 12 + sign * 4;
    } else {
      c.dcContext = 4 + sign * 4;
    }
    var v = m;
    at += 14;
    while ((m >>= 1) != 0) {
      if (_arithmeticDecode(stats, at) == 1) v |= m;
    }
    v++;
    return sign == 1 ? -v : v;
  }

  /// The AC coefficients [from] to [to] of a block (F.2.4.2), each
  /// shifted left by [al]; false on corrupt data.
  bool _arithmeticAc(_Component c, int offset, int from, int to, int al) {
    final stats = _acStats[c.acTable];
    final block = c.coefficients;
    for (var k = from; k <= to; k++) {
      var at = 3 * (k - 1);
      if (_arithmeticDecode(stats, at) == 1) break; // end of block
      while (_arithmeticDecode(stats, at + 1) == 0) {
        at += 3;
        if (++k > to) return false;
      }
      final sign = _arithmeticDecode(_fixedBin, 0);
      at += 2;
      var m = _arithmeticDecode(stats, at);
      if (m != 0 && _arithmeticDecode(stats, at) == 1) {
        m <<= 1;
        at = k <= _acK[c.acTable] ? 189 : 217;
        while (_arithmeticDecode(stats, at) == 1) {
          if ((m <<= 1) == 0x8000) return false;
          at++;
        }
      }
      var v = m;
      at += 14;
      while ((m >>= 1) != 0) {
        if (_arithmeticDecode(stats, at) == 1) v |= m;
      }
      v++;
      block[offset + _natural[k]] = (sign == 1 ? -v : v) * (1 << al);
    }
    return true;
  }

  void _arithmeticSequential(_Component c, int offset) {
    c.dcPredictor = (c.dcPredictor + _arithmeticDc(c)) & 0xffff;
    c.coefficients[offset] = c.dcPredictor;
    _arithmeticAc(c, offset, 1, 63, 0);
  }

  void _arithmeticDcFirst(_Component c, int offset, int al) {
    c.dcPredictor = (c.dcPredictor + _arithmeticDc(c)) & 0xffff;
    c.coefficients[offset] = _signed16(c.dcPredictor) * (1 << al);
  }

  void _arithmeticDcRefine(_Component c, int offset, int al) {
    if (_arithmeticDecode(_fixedBin, 0) == 1) {
      c.coefficients[offset] |= 1 << al;
    }
  }

  void _arithmeticAcFirst(_Component c, int offset, int ss, int se, int al) {
    _arithmeticAc(c, offset, ss, se, al);
  }

  void _arithmeticAcRefine(_Component c, int offset, int ss, int se, int al) {
    final stats = _acStats[c.acTable];
    final block = c.coefficients;
    final p1 = 1 << al;
    final m1 = -(1 << al);
    // The previous stage's end of block.
    var kex = se;
    for (; kex > 0; kex--) {
      if (block[offset + _natural[kex]] != 0) break;
    }
    for (var k = ss; k <= se; k++) {
      var at = 3 * (k - 1);
      if (k > kex && _arithmeticDecode(stats, at) == 1) break;
      for (;;) {
        final i = offset + _natural[k];
        final coefficient = block[i];
        if (coefficient != 0) {
          if (_arithmeticDecode(stats, at + 2) == 1) {
            block[i] = coefficient < 0 ? coefficient + m1 : coefficient + p1;
          }
          break;
        }
        if (_arithmeticDecode(stats, at + 1) == 1) {
          block[i] = _arithmeticDecode(_fixedBin, 0) == 1 ? m1 : p1;
          break;
        }
        at += 3;
        if (++k > se) return;
      }
    }
  }

  /// A lossless scan (T.81, Annex H): each sample its predictor's value
  /// plus a difference coded as a DC one; where the next marker is.
  int _readLosslessScan(
    List<_Component> scan,
    int predictor,
    int pt,
    int from,
  ) {
    if (predictor < 1 || predictor > 7) {
      throw ImageFormatException('JPEG lossless predictor $predictor');
    }
    for (final c in scan) {
      if (_dcTables[c.dcTable] == null) {
        throw const ImageFormatException('JPEG Huffman table is missing');
      }
    }
    _at = from;
    _bits = 0;
    _held = 0;
    _marker = false;
    final single = scan.length == 1;
    final columns = single ? scan.first.widthInBlocks : _mcusPerLine;
    final rows = single ? scan.first.heightInBlocks : _mcuRows;
    final initial = 1 << (_precision - pt - 1);
    var restarts = _restartInterval;
    // The MCU row a restart interval began on: its first row is
    // predicted as the image's first is.
    var firstRow = 0;
    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < columns; column++) {
        if (_restartInterval > 0) {
          if (restarts == 0) {
            _restart(scan);
            restarts = _restartInterval;
            firstRow = row;
          }
          restarts--;
        }
        for (final c in scan) {
          final hs = single ? 1 : c.h;
          final vs = single ? 1 : c.v;
          for (var v = 0; v < vs; v++) {
            for (var h = 0; h < hs; h++) {
              final y = row * vs + v;
              final x = column * hs + h;
              final stride = c.blocksPerLine;
              final at = y * stride + x;
              final t = _decode(_dcTables[c.dcTable]!);
              final diff = t == 16 ? 32768 : _receiveExtend(t);
              final s = c.samples;
              final int prediction;
              if (y == firstRow * vs) {
                prediction = x == 0 ? initial : s[at - 1];
              } else if (x == 0) {
                prediction = s[at - stride];
              } else {
                final ra = s[at - 1];
                final rb = s[at - stride];
                final rc = s[at - stride - 1];
                prediction = switch (predictor) {
                  1 => ra,
                  2 => rb,
                  3 => rc,
                  4 => ra + rb - rc,
                  5 => ra + _shr(rb - rc, 1),
                  6 => rb + _shr(ra - rc, 1),
                  _ => (ra + rb) >> 1,
                };
              }
              s[at] = (prediction + diff) & 0xffff;
            }
          }
        }
      }
    }
    _pointTransform = pt;
    var at2 = _at;
    while (at2 + 1 < _data.length) {
      if (_data[at2] == 0xff &&
          _data[at2 + 1] != 0 &&
          !(_data[at2 + 1] >= 0xd0 && _data[at2 + 1] <= 0xd7)) {
        return at2;
      }
      at2++;
    }
    return _data.length;
  }

  var _pointTransform = 0;

  JpegPixels output() {
    if (!_frame) throw const ImageFormatException('JPEG image has no frame');
    final twelve = _precision == 12;
    final maxSample = twelve ? 4095 : 255;
    // The planes: each component's samples, its blocks inverse
    // transformed (a lossless image's, its point transform undone).
    final planes = <Uint16List>[];
    for (final c in _components) {
      if (_lossless) {
        final mask = (1 << _precision) - 1;
        planes.add(
          Uint16List.fromList([
            for (final v in c.samples) (v << _pointTransform) & mask,
          ]),
        );
        continue;
      }
      final quant = c.quant ?? _quant[c.quantTable];
      if (quant == null) {
        throw const ImageFormatException('JPEG quantization table is missing');
      }
      final stride = c.blocksPerLine * 8;
      final plane = Uint16List(stride * c.blocksPerColumn * 8);

      for (var row = 0; row < c.heightInBlocks; row++) {
        for (var column = 0; column < c.widthInBlocks; column++) {
          _idctIslow(
            c.coefficients,
            (row * c.blocksPerLine + column) * 64,
            quant,
            plane,
            row * 8 * stride + column * 8,
            stride,
            twelve: twelve,
          );
        }
      }
      planes.add(plane);
    }
    // Each component upsampled to the image's size.
    final full = <Uint16List>[
      for (var i = 0; i < _components.length; i++)
        _upsample(_components[i], planes[i]),
    ];
    final channels = switch (_components.length) {
      1 => 1,
      3 => 3,
      4 => 4,
      _ => throw ImageFormatException(
        'JPEG images with ${_components.length} components are not '
        'supported',
      ),
    };
    final count = _width * _height;
    final out = Uint16List(count * channels);
    // The color space, as libjpeg tells it.
    final ycc =
        channels == 3 &&
        (_ycc ??
            (_jfif ||
                (adobe
                    ? adobeTransform != 0
                    : !_lossless &&
                          !(_components[0].id == 82 &&
                              _components[1].id == 71 &&
                              _components[2].id == 66))));
    final ycck = channels == 4 && adobe && adobeTransform != 0;
    if (channels == 1) {
      out.setAll(0, full[0].sublist(0, count));
    } else if (ycc || ycck) {
      final top = _lossless ? (1 << _precision) - 1 : maxSample;
      final tables = _YccTables.of(top, (top + 1) >> 1);
      final y = full[0];
      final cb = full[1];
      final cr = full[2];
      for (var i = 0; i < count; i++) {
        final yy = y[i];
        final r = tables.clamp(yy + tables.crR[cr[i]]);
        final g = tables.clamp(
          yy + _shr(tables.cbG[cb[i]] + tables.crG[cr[i]], 16),
        );
        final b = tables.clamp(yy + tables.cbB[cb[i]]);
        if (ycck) {
          out[4 * i] = tables.clamp(
            tables.maxSample - (yy + tables.crR[cr[i]]),
          );
          out[4 * i + 1] = tables.clamp(
            tables.maxSample -
                (yy + _shr(tables.cbG[cb[i]] + tables.crG[cr[i]], 16)),
          );
          out[4 * i + 2] = tables.clamp(
            tables.maxSample - (yy + tables.cbB[cb[i]]),
          );
          out[4 * i + 3] = full[3][i];
        } else {
          out[3 * i] = r;
          out[3 * i + 1] = g;
          out[3 * i + 2] = b;
        }
      }
    } else {
      for (var i = 0; i < count; i++) {
        for (var c = 0; c < channels; c++) {
          out[channels * i + c] = full[c][i];
        }
      }
    }
    return (
      width: _width,
      height: _height,
      channels: channels,
      precision: _precision,
      samples: out,
      adobe: adobe,
      adobeTransform: adobeTransform,
    );
  }

  /// The component's samples at the image's size, as libjpeg upsamples
  /// them: "fancy" (triangle) filtering for 2:1 horizontally and/or
  /// vertically, replication for other whole ratios.
  Uint16List _upsample(_Component c, Uint16List plane) {
    final stride = c.blocksPerLine * (_lossless ? 1 : 8);
    final w = c.downsampledWidth;
    final h = c.downsampledHeight;
    final out = Uint16List(_width * _height);
    // A row of the component's samples, the rows past its real ones (and
    // above the first) the nearest real one.
    int rowAt(int y) => (y < 0 ? 0 : (y >= h ? h - 1 : y)) * stride;
    final hRatio = _hMax ~/ c.h;
    final vRatio = _vMax ~/ c.v;
    final wide = Uint16List(_ceilDiv(_width, 1) + 2 * hRatio + 8);
    if (hRatio == 1 && vRatio == 1) {
      for (var y = 0; y < _height; y++) {
        out.setRange(y * _width, (y + 1) * _width, plane, y * stride);
      }
      return out;
    }
    if (hRatio * c.h != _hMax || vRatio * c.v != _vMax) {
      throw const ImageFormatException('JPEG sampling factors');
    }
    if (hRatio == 2 && vRatio == 1) {
      // (A lossless image's samples are repeated: libjpeg filters only
      // what an inverse DCT made.)
      final fancy = w > 2 && !_lossless;
      for (var y = 0; y < _height; y++) {
        final row = rowAt(y);
        if (fancy) {
          _h2v1Fancy(plane, row, w, wide);
        } else {
          for (var x = 0; x < w; x++) {
            wide[2 * x] = wide[2 * x + 1] = plane[row + x];
          }
        }
        out.setRange(y * _width, (y + 1) * _width, wide);
      }
      return out;
    }
    if (hRatio == 1 && vRatio == 2 && !_lossless) {
      for (var y = 0; y < _height; y++) {
        final k = y >> 1;
        final near = rowAt(k);
        final far = rowAt(y.isEven ? k - 1 : k + 1);
        final bias = y.isEven ? 1 : 2;
        for (var x = 0; x < _width; x++) {
          out[y * _width + x] =
              (plane[near + x] * 3 + plane[far + x] + bias) >> 2;
        }
      }
      return out;
    }
    if (hRatio == 2 && vRatio == 2 && w > 2 && !_lossless) {
      for (var y = 0; y < _height; y++) {
        final k = y >> 1;
        final near = rowAt(k);
        final far = rowAt(y.isEven ? k - 1 : k + 1);
        var thisSum = plane[near] * 3 + plane[far];
        var nextSum = plane[near + 1] * 3 + plane[far + 1];
        wide[0] = (thisSum * 4 + 8) >> 4;
        wide[1] = (thisSum * 3 + nextSum + 7) >> 4;
        var lastSum = thisSum;
        thisSum = nextSum;
        for (var x = 2; x < w; x++) {
          nextSum = plane[near + x] * 3 + plane[far + x];
          wide[2 * x - 2] = (thisSum * 3 + lastSum + 8) >> 4;
          wide[2 * x - 1] = (thisSum * 3 + nextSum + 7) >> 4;
          lastSum = thisSum;
          thisSum = nextSum;
        }
        wide[2 * w - 2] = (thisSum * 3 + lastSum + 8) >> 4;
        wide[2 * w - 1] = (thisSum * 4 + 7) >> 4;
        out.setRange(y * _width, (y + 1) * _width, wide);
      }
      return out;
    }
    // Other whole ratios (and 2:2 at most two samples wide): each sample
    // repeated.
    for (var y = 0; y < _height; y++) {
      final row = (y ~/ vRatio) * stride;
      for (var x = 0; x < _width; x++) {
        out[y * _width + x] = plane[row + x ~/ hRatio];
      }
    }
    return out;
  }

  static void _h2v1Fancy(Uint16List plane, int row, int w, Uint16List out) {
    var value = plane[row];
    out[0] = value;
    out[1] = (value * 3 + plane[row + 1] + 2) >> 2;
    for (var x = 1; x < w - 1; x++) {
      value = plane[row + x] * 3;
      out[2 * x] = (value + plane[row + x - 1] + 1) >> 2;
      out[2 * x + 1] = (value + plane[row + x + 1] + 2) >> 2;
    }
    value = plane[row + w - 1];
    out[2 * w - 2] = (value * 3 + plane[row + w - 2] + 1) >> 2;
    out[2 * w - 1] = value;
  }
}

/// libjpeg's YCbCr to RGB tables (16-bit fixed point).
final class _YccTables {
  factory of(int maxSample, int center) {
    final crR = Int32List(maxSample + 1);
    final cbB = Int32List(maxSample + 1);
    final crG = Int32List(maxSample + 1);
    final cbG = Int32List(maxSample + 1);
    int fix(double x) => (x * 65536 + 0.5).toInt();
    const half = 1 << 15;
    for (var i = 0, x = -center; i <= maxSample; i++, x++) {
      crR[i] = _shr(fix(1.40200) * x + half, 16);
      cbB[i] = _shr(fix(1.77200) * x + half, 16);
      crG[i] = -fix(0.71414) * x;
      cbG[i] = -fix(0.34414) * x + half;
    }
    return _YccTables._(crR, cbB, crG, cbG, maxSample);
  }

  const new _(this.crR, this.cbB, this.crG, this.cbG, this.maxSample);

  final Int32List crR;
  final Int32List cbB;
  final Int32List crG;
  final Int32List cbG;
  final int maxSample;

  int clamp(int v) => v < 0 ? 0 : (v > maxSample ? maxSample : v);
}

int _ceilDiv(int a, int b) => (a + b - 1) ~/ b;

int _signed16(int v) => (v ^ 0x8000) - 0x8000;

/// T.81's probability estimation state machine (Table D.2), as libjpeg
/// packs it (with its state 113, a fixed probability of one half): Qe
/// << 16 | Next_Index_MPS << 8 | Switch_MPS << 7 | Next_Index_LPS.
const List<int> _arithmeticTable = [
  0x5a1d0181,
  0x2586020e,
  0x11140310,
  0x080b0412,
  0x03d80514,
  0x01da0617,
  0x00e50719,
  0x006f081c,
  0x0036091e,
  0x001a0a21,
  0x000d0b23,
  0x00060c09,
  0x00030d0a,
  0x00010d0c,
  0x5a7f0f8f,
  0x3f251024,
  0x2cf21126,
  0x207c1227,
  0x17b91328,
  0x1182142a,
  0x0cef152b,
  0x09a1162d,
  0x072f172e,
  0x055c1830,
  0x04061931,
  0x03031a33,
  0x02401b34,
  0x01b11c36,
  0x01441d38,
  0x00f51e39,
  0x00b71f3b,
  0x008a203c,
  0x0068213e,
  0x004e223f,
  0x003b2320,
  0x002c0921,
  0x5ae125a5,
  0x484c2640,
  0x3a0d2741,
  0x2ef12843,
  0x261f2944,
  0x1f332a45,
  0x19a82b46,
  0x15182c48,
  0x11772d49,
  0x0e742e4a,
  0x0bfb2f4b,
  0x09f8304d,
  0x0861314e,
  0x0706324f,
  0x05cd3330,
  0x04de3432,
  0x040f3532,
  0x03633633,
  0x02d43734,
  0x025c3835,
  0x01f83936,
  0x01a43a37,
  0x01603b38,
  0x01253c39,
  0x00f63d3a,
  0x00cb3e3b,
  0x00ab3f3d,
  0x008f203d,
  0x5b1241c1,
  0x4d044250,
  0x412c4351,
  0x37d84452,
  0x2fe84553,
  0x293c4654,
  0x23794756,
  0x1edf4857,
  0x1aa94957,
  0x174e4a48,
  0x14244b48,
  0x119c4c4a,
  0x0f6b4d4a,
  0x0d514e4b,
  0x0bb64f4d,
  0x0a40304d,
  0x583251d0,
  0x4d1c5258,
  0x438e5359,
  0x3bdd545a,
  0x34ee555b,
  0x2eae565c,
  0x299a575d,
  0x25164756,
  0x557059d8,
  0x4ca95a5f,
  0x44d95b60,
  0x3e225c61,
  0x38245d63,
  0x32b45e63,
  0x2e17565d,
  0x56a860df,
  0x4f466165,
  0x47e56266,
  0x41cf6367,
  0x3c3d6468,
  0x375e5d63,
  0x52316669,
  0x4c0f676a,
  0x4639686b,
  0x415e6367,
  0x56276ae9,
  0x50e76b6c,
  0x4b85676d,
  0x55976d6e,
  0x504f6b6f,
  0x5a106fee,
  0x55226d70,
  0x59eb6ff0,
  0x5a1d7171,
];

/// Whether this is JavaScript, whose numbers are doubles.
const bool _web = identical(0, 0.0);

/// [v] shifted right by [n] bits, rounding down (`>>` of a negative number
/// compiled to JavaScript is unsigned).
@pragma('vm:prefer-inline')
int _shr(int v, int n) =>
    !_web || v >= 0 ? v >> n : -((-v + (1 << n) - 1) >> n);

// The accurate integer inverse DCT (Loeffler, Ligtenberg and Moschytz's
// algorithm, as libjpeg's "islow" computes it): 13-bit constants.
const int _fix0298631336 = 2446;
const int _fix0390180644 = 3196;
const int _fix0541196100 = 4433;
const int _fix0765366865 = 6270;
const int _fix0899976223 = 7373;
const int _fix1175875602 = 9633;
const int _fix1501321110 = 12299;
const int _fix1847759065 = 15137;
const int _fix1961570560 = 16069;
const int _fix2053119869 = 16819;
const int _fix2562915447 = 20995;
const int _fix3072711026 = 25172;

final Int32List _workspace = Int32List(64);

/// The block of [coefficients] at [at], dequantized by [quant], inverse
/// transformed into [out] at [to] (rows [stride] apart).
void _idctIslow(
  Int16List coefficients,
  int at,
  Int32List quant,
  Uint16List out,
  int to,
  int stride, {
  required bool twelve,
}) {
  // (Shifts left by 13 bits are multiplications by 8192: shifting a
  // negative number compiled to JavaScript gives an unsigned result.)
  const constBits = 13;
  final pass1 = twelve ? 1 : 2;
  final maxSample = twelve ? 4095 : 255;
  final center = twelve ? 2048 : 128;
  final rangeMask = maxSample * 4 + 3;
  final ws = _workspace;
  // The post-IDCT range limit: centered, clamped, and (out of range
  // values wrapping as libjpeg's table has them) the same quirks.
  int limit(int v) {
    final i = v & rangeMask;
    if (i <= maxSample - center) return i + center;
    if (i < 2 * (maxSample + 1)) return maxSample;
    if (i < 4 * (maxSample + 1) - center) return 0;
    return i - (4 * (maxSample + 1) - center);
  }

  for (var c = 0; c < 8; c++) {
    final i = at + c;
    if (coefficients[i + 8] == 0 &&
        coefficients[i + 16] == 0 &&
        coefficients[i + 24] == 0 &&
        coefficients[i + 32] == 0 &&
        coefficients[i + 40] == 0 &&
        coefficients[i + 48] == 0 &&
        coefficients[i + 56] == 0) {
      final dc = coefficients[i] * quant[c] * (1 << pass1);
      for (var r = 0; r < 8; r++) {
        ws[r * 8 + c] = dc;
      }
      continue;
    }
    var z2 = coefficients[i + 16] * quant[16 + c];
    var z3 = coefficients[i + 48] * quant[48 + c];
    var z1 = (z2 + z3) * _fix0541196100;
    var tmp2 = z1 + z3 * -_fix1847759065;
    var tmp3 = z1 + z2 * _fix0765366865;
    z2 = coefficients[i] * quant[c];
    z3 = coefficients[i + 32] * quant[32 + c];
    var tmp0 = (z2 + z3) * 8192;
    var tmp1 = (z2 - z3) * 8192;
    final tmp10 = tmp0 + tmp3;
    final tmp13 = tmp0 - tmp3;
    final tmp11 = tmp1 + tmp2;
    final tmp12 = tmp1 - tmp2;
    tmp0 = coefficients[i + 56] * quant[56 + c];
    tmp1 = coefficients[i + 40] * quant[40 + c];
    tmp2 = coefficients[i + 24] * quant[24 + c];
    tmp3 = coefficients[i + 8] * quant[8 + c];
    z1 = tmp0 + tmp3;
    z2 = tmp1 + tmp2;
    z3 = tmp0 + tmp2;
    var z4 = tmp1 + tmp3;
    final z5 = (z3 + z4) * _fix1175875602;
    tmp0 *= _fix0298631336;
    tmp1 *= _fix2053119869;
    tmp2 *= _fix3072711026;
    tmp3 *= _fix1501321110;
    z1 *= -_fix0899976223;
    z2 *= -_fix2562915447;
    z3 *= -_fix1961570560;
    z4 *= -_fix0390180644;
    z3 += z5;
    z4 += z5;
    tmp0 += z1 + z3;
    tmp1 += z2 + z4;
    tmp2 += z2 + z3;
    tmp3 += z1 + z4;
    final shift = constBits - pass1;
    final round = 1 << (shift - 1);
    ws[c] = _shr(tmp10 + tmp3 + round, shift);
    ws[56 + c] = _shr(tmp10 - tmp3 + round, shift);
    ws[8 + c] = _shr(tmp11 + tmp2 + round, shift);
    ws[48 + c] = _shr(tmp11 - tmp2 + round, shift);
    ws[16 + c] = _shr(tmp12 + tmp1 + round, shift);
    ws[40 + c] = _shr(tmp12 - tmp1 + round, shift);
    ws[24 + c] = _shr(tmp13 + tmp0 + round, shift);
    ws[32 + c] = _shr(tmp13 - tmp0 + round, shift);
  }
  for (var r = 0; r < 8; r++) {
    final w = r * 8;
    final o = to + r * stride;
    if (ws[w + 1] == 0 &&
        ws[w + 2] == 0 &&
        ws[w + 3] == 0 &&
        ws[w + 4] == 0 &&
        ws[w + 5] == 0 &&
        ws[w + 6] == 0 &&
        ws[w + 7] == 0) {
      final shift = pass1 + 3;
      final dc = limit(_shr(ws[w] + (1 << (shift - 1)), shift));
      for (var x = 0; x < 8; x++) {
        out[o + x] = dc;
      }
      continue;
    }
    var z2 = ws[w + 2];
    var z3 = ws[w + 6];
    var z1 = (z2 + z3) * _fix0541196100;
    var tmp2 = z1 + z3 * -_fix1847759065;
    var tmp3 = z1 + z2 * _fix0765366865;
    var tmp0 = (ws[w] + ws[w + 4]) * 8192;
    var tmp1 = (ws[w] - ws[w + 4]) * 8192;
    final tmp10 = tmp0 + tmp3;
    final tmp13 = tmp0 - tmp3;
    final tmp11 = tmp1 + tmp2;
    final tmp12 = tmp1 - tmp2;
    tmp0 = ws[w + 7];
    tmp1 = ws[w + 5];
    tmp2 = ws[w + 3];
    tmp3 = ws[w + 1];
    z1 = tmp0 + tmp3;
    z2 = tmp1 + tmp2;
    z3 = tmp0 + tmp2;
    var z4 = tmp1 + tmp3;
    final z5 = (z3 + z4) * _fix1175875602;
    tmp0 *= _fix0298631336;
    tmp1 *= _fix2053119869;
    tmp2 *= _fix3072711026;
    tmp3 *= _fix1501321110;
    z1 *= -_fix0899976223;
    z2 *= -_fix2562915447;
    z3 *= -_fix1961570560;
    z4 *= -_fix0390180644;
    z3 += z5;
    z4 += z5;
    tmp0 += z1 + z3;
    tmp1 += z2 + z4;
    tmp2 += z2 + z3;
    tmp3 += z1 + z4;
    final shift = constBits + pass1 + 3;
    final round = 1 << (shift - 1);
    out[o] = limit(_shr(tmp10 + tmp3 + round, shift));
    out[o + 7] = limit(_shr(tmp10 - tmp3 + round, shift));
    out[o + 1] = limit(_shr(tmp11 + tmp2 + round, shift));
    out[o + 6] = limit(_shr(tmp11 - tmp2 + round, shift));
    out[o + 2] = limit(_shr(tmp12 + tmp1 + round, shift));
    out[o + 5] = limit(_shr(tmp12 - tmp1 + round, shift));
    out[o + 3] = limit(_shr(tmp13 + tmp0 + round, shift));
    out[o + 4] = limit(_shr(tmp13 - tmp0 + round, shift));
  }
}
