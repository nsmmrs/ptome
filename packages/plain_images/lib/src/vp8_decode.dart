/// VP8 key frames (RFC 6386), the lossy WebP bitstream: the boolean
/// entropy decoder, the frame header, per-macroblock modes and DCT/WHT
/// coefficients, intra prediction, the inverse transforms and the loop
/// filter, to Y, U and V planes (4:2:0).
library;

import 'dart:typed_data';

import 'package:plain_images/src/exception.dart';

import 'package:plain_images/src/vp8_tables.g.dart';

/// A decoded key frame: `width` by `height` luma samples in `y` (rows of
/// `yStride`), half as many chroma samples each way (rounded up) in `u`
/// and `v` (rows of `uvStride`).
typedef Vp8Frame = ({
  int width,
  int height,
  Uint8List y,
  Uint8List u,
  Uint8List v,
  int yStride,
  int uvStride,
});

/// The size of the VP8 key frame [data] (its 10-byte header), or null.
({int width, int height})? vp8Size(Uint8List data) {
  if (data.length < 10) return null;
  final keyFrame = data[0] & 1 == 0;
  if (!keyFrame || data[3] != 0x9d || data[4] != 0x01 || data[5] != 0x2a) {
    return null;
  }
  return (
    width: (data[6] | data[7] << 8) & 0x3fff,
    height: (data[8] | data[9] << 8) & 0x3fff,
  );
}

/// The planes of the VP8 key frame [data].
Vp8Frame decodeVp8(Uint8List data) => _Vp8(data).decode();

/// The boolean entropy decoder (RFC 6386, 7).
final class _BoolDecoder {
  new(this.data, this.at, this.end) {
    // Two bytes to start with.
    value = (_byte() << 8) | _byte();
  }

  final Uint8List data;
  int at;
  final int end;
  int value = 0;
  int range = 255;
  int bitCount = 0;

  /// Past the end: zeros.
  int _byte() => at < end ? data[at++] : (at++, 0).$2;

  /// Whether reading went well past the data.
  bool get pastEnd => at > end + 2;

  int read(int probability) {
    final split = 1 + (((range - 1) * probability) >> 8);
    final bigSplit = split << 8;
    int bit;
    if (value >= bigSplit) {
      bit = 1;
      range -= split;
      value -= bigSplit;
    } else {
      bit = 0;
      range = split;
    }
    while (range < 128) {
      value <<= 1;
      range <<= 1;
      if (++bitCount == 8) {
        bitCount = 0;
        value |= _byte();
      }
    }
    return bit;
  }

  /// An [n]-bit unsigned literal, most significant bit first.
  int literal(int n) {
    var v = 0;
    for (var i = 0; i < n; i++) {
      v = (v << 1) | read(128);
    }
    return v;
  }

  /// An [n]-bit magnitude and a sign bit after it.
  int signed(int n) {
    final v = literal(n);
    return read(128) == 1 ? -v : v;
  }

  /// A flag, then (if set) a signed [n]-bit value; else 0.
  int optionalSigned(int n) => read(128) == 1 ? signed(n) : 0;
}

// Luma modes (16 × 16) and chroma modes.
const int _dcPred = 0;
const int _vPred = 1;
const int _hPred = 2;
const int _tmPred = 3;
const int _bPred = 4;

// Subblock modes, in the RFC's order (kfBmodeProbs is indexed by it).
const int _bDc = 0;
const int _bTm = 1;
const int _bVe = 2;
const int _bHe = 3;
const int _bLd = 4;
const int _bRd = 5;
const int _bVr = 6;
const int _bVl = 7;
const int _bHd = 8;
const int _bHu = 9;

/// The subblock mode tree (RFC 6386, 11.2).
const List<int> _bmodeTree = [
  -_bDc, 2, -_bTm, 4, -_bVe, 6, 8, 12, -_bHe, 10, -_bRd, -_bVr, -_bLd, 14, //
  -_bVl, 16, -_bHd, -_bHu,
];

/// The band of each coefficient position (RFC 6386, 13.3), one more for
/// the position past the last.
const List<int> _bands = [0, 1, 2, 3, 6, 4, 5, 6, 6, 6, 6, 6, 6, 6, 6, 7, 0];

const List<int> _zigzag = [
  0,
  1,
  4,
  8,
  5,
  2,
  3,
  6,
  9,
  12,
  13,
  10,
  7,
  11,
  14,
  15,
];

const List<List<int>> _catProbs = [
  [173, 148, 140],
  [176, 155, 140, 135],
  [180, 157, 141, 134, 130],
  [254, 254, 243, 230, 196, 177, 153, 140, 133, 130, 129],
];

/// The dequantization factors of a segment: luma DC and AC, Y2 DC and
/// AC, chroma DC and AC.
typedef _Quant = (int, int, int, int, int, int);

// Work buffer: a macroblock with a row above (and its top right) and a
// column to the left; chroma alongside.
const int _bps = 32;
const int _yOff = _bps * 1 + 8;
const int _uOff = _yOff + _bps * 16 + _bps;
const int _vOff = _uOff + 16;
const int _workSize = _bps * 17 + _bps * 9;

final class _Vp8 {
  new(this.data);

  final Uint8List data;

  late int width;
  late int height;
  late int mbWidth;
  late int mbHeight;

  // Segments.
  var _segmentation = false;
  var _updateMap = false;
  var _absoluteDelta = false;
  final List<int> _segmentQuant = List.filled(4, 0);
  final List<int> _segmentFilter = List.filled(4, 0);
  final List<int> _segmentProbs = List.filled(3, 255);

  // The loop filter.
  var _simple = false;
  var _filterLevel = 0;
  var _sharpness = 0;
  var _useDeltas = false;
  final List<int> _refDeltas = List.filled(4, 0);
  final List<int> _modeDeltas = List.filled(4, 0);

  final List<_Quant> _quant = List.filled(4, (0, 0, 0, 0, 0, 0));
  late final Uint8List _coeffProbs = Uint8List.fromList(defaultCoeffProbs);
  var _useSkip = false;
  var _skipProb = 0;

  Vp8Frame decode() {
    final size = vp8Size(data);
    if (size == null) throw const ImageFormatException('not a VP8 key frame');
    width = size.width;
    height = size.height;
    if (width == 0 || height == 0) {
      throw const ImageFormatException('VP8 frame is empty');
    }
    final tag = data[0] | data[1] << 8 | data[2] << 16;
    final firstSize = tag >> 5;
    if (10 + firstSize > data.length) {
      throw const ImageFormatException('VP8 first partition is truncated');
    }
    mbWidth = (width + 15) >> 4;
    mbHeight = (height + 15) >> 4;
    final header = _BoolDecoder(data, 10, 10 + firstSize);
    _readHeader(header);
    final partitions = _partitions(header, 10 + firstSize);
    return _frame(header, partitions);
  }

  void _readHeader(_BoolDecoder d) {
    d
      ..literal(1) // color space
      ..literal(1); // clamping type
    _segmentation = d.read(128) == 1;
    if (_segmentation) {
      _updateMap = d.read(128) == 1;
      final updateData = d.read(128) == 1;
      if (updateData) {
        _absoluteDelta = d.read(128) == 1;
        for (var s = 0; s < 4; s++) {
          _segmentQuant[s] = d.optionalSigned(7);
        }
        for (var s = 0; s < 4; s++) {
          _segmentFilter[s] = d.optionalSigned(6);
        }
      }
      if (_updateMap) {
        for (var i = 0; i < 3; i++) {
          _segmentProbs[i] = d.read(128) == 1 ? d.literal(8) : 255;
        }
      }
    }
    _simple = d.read(128) == 1;
    _filterLevel = d.literal(6);
    _sharpness = d.literal(3);
    _useDeltas = d.read(128) == 1;
    if (_useDeltas && d.read(128) == 1) {
      for (var i = 0; i < 4; i++) {
        if (d.read(128) == 1) _refDeltas[i] = d.signed(6);
      }
      for (var i = 0; i < 4; i++) {
        if (d.read(128) == 1) _modeDeltas[i] = d.signed(6);
      }
    }
    _partitionBits = d.literal(2);
    // The quantizers.
    final base = d.literal(7);
    final yDc = d.optionalSigned(4);
    final y2Dc = d.optionalSigned(4);
    final y2Ac = d.optionalSigned(4);
    final uvDc = d.optionalSigned(4);
    final uvAc = d.optionalSigned(4);
    for (var s = 0; s < 4; s++) {
      var q = base;
      if (_segmentation) {
        q = _absoluteDelta ? _segmentQuant[s] : base + _segmentQuant[s];
      }
      int at(int index, int max) => index < 0 ? 0 : (index > max ? max : index);
      var y2ac = acQuant[at(q + y2Ac, 127)] * 155 ~/ 100;
      if (y2ac < 8) y2ac = 8;
      _quant[s] = (
        dcQuant[at(q + yDc, 127)],
        acQuant[at(q, 127)],
        dcQuant[at(q + y2Dc, 127)] * 2,
        y2ac,
        dcQuant[at(q + uvDc, 117)],
        acQuant[at(q + uvAc, 127)],
      );
    }
    d.literal(1); // refresh entropy probabilities (a key frame's own)
    for (var i = 0; i < 4 * 8 * 3 * 11; i++) {
      if (d.read(coeffUpdateProbs[i]) == 1) _coeffProbs[i] = d.literal(8);
    }
    _useSkip = d.read(128) == 1;
    if (_useSkip) _skipProb = d.literal(8);
  }

  int _partitionBits = 0;

  /// The token partitions' decoders, after the first partition at [at].
  List<_BoolDecoder> _partitions(_BoolDecoder header, int at) {
    final count = 1 << _partitionBits;
    var start = at + 3 * (count - 1);
    if (start > data.length) {
      throw const ImageFormatException('VP8 partition sizes are truncated');
    }
    final out = <_BoolDecoder>[];
    for (var p = 0; p < count; p++) {
      var end = data.length;
      if (p < count - 1) {
        final size =
            data[at + 3 * p] |
            data[at + 3 * p + 1] << 8 |
            data[at + 3 * p + 2] << 16;
        end = start + size;
        if (end > data.length) end = data.length;
      }
      out.add(_BoolDecoder(data, start, end));
      start = end;
    }
    return out;
  }

  Vp8Frame _frame(_BoolDecoder header, List<_BoolDecoder> partitions) {
    final yStride = mbWidth * 16;
    final uvStride = mbWidth * 8;
    final yPlane = Uint8List(yStride * mbHeight * 16);
    final uPlane = Uint8List(uvStride * mbHeight * 8);
    final vPlane = Uint8List(uvStride * mbHeight * 8);
    // Unfiltered bottom rows of the macroblock row above, by column.
    final topY = Uint8List(yStride);
    final topU = Uint8List(uvStride);
    final topV = Uint8List(uvStride);
    // Subblock mode contexts: above (four per macroblock), left (four).
    final modesAbove = Uint8List(mbWidth * 4);
    final modesLeft = Uint8List(4);
    // Non-zero contexts: above (per macroblock: 4 luma, 2 + 2 chroma
    // bits, and Y2), left.
    final nzAbove = Int32List(mbWidth);
    final nzDcAbove = Uint8List(mbWidth);
    var nzLeft = 0;
    var nzDcLeft = 0;
    // Per macroblock: the filter's level, interior limit, threshold and
    // whether inner edges are filtered (for the loop filter, after).
    final filterInfo = Int32List(mbWidth * mbHeight * 4);
    final work = Uint8List(_workSize);
    final coeffs = Int16List(384);
    final modes = Uint8List(16);
    final strengths = _filterStrengths();

    for (var mbY = 0; mbY < mbHeight; mbY++) {
      final tokens = partitions[mbY & (partitions.length - 1)];
      modesLeft.fillRange(0, 4, _bDc);
      nzLeft = 0;
      nzDcLeft = 0;
      // The left column and top left of the first macroblock.
      for (var j = 0; j < 16; j++) {
        work[_yOff + j * _bps - 1] = 129;
      }
      for (var j = 0; j < 8; j++) {
        work[_uOff + j * _bps - 1] = 129;
        work[_vOff + j * _bps - 1] = 129;
      }
      if (mbY > 0) {
        work[_yOff - _bps - 1] = 129;
        work[_uOff - _bps - 1] = 129;
        work[_vOff - _bps - 1] = 129;
      } else {
        work
          ..fillRange(_yOff - _bps - 1, _yOff - _bps + 20, 127)
          ..fillRange(_uOff - _bps - 1, _uOff - _bps + 8, 127)
          ..fillRange(_vOff - _bps - 1, _vOff - _bps + 8, 127);
      }
      for (var mbX = 0; mbX < mbWidth; mbX++) {
        // The macroblock's header.
        var segment = 0;
        if (_updateMap) {
          segment = header.read(_segmentProbs[0]) == 0
              ? header.read(_segmentProbs[1])
              : 2 + header.read(_segmentProbs[2]);
        }
        final skipFlag = _useSkip && header.read(_skipProb) == 1;
        final int yMode;
        if (header.read(145) == 0) {
          yMode = _bPred;
          for (var y = 0; y < 4; y++) {
            var left = modesLeft[y];
            for (var x = 0; x < 4; x++) {
              final above = modesAbove[mbX * 4 + x];
              final probs = (above * 10 + left) * 9;
              var i = 0;
              do {
                i = _bmodeTree[i + header.read(kfBmodeProbs[probs + (i >> 1)])];
              } while (i > 0);
              left = -i;
              modes[y * 4 + x] = left;
              modesAbove[mbX * 4 + x] = left;
            }
            modesLeft[y] = left;
          }
        } else {
          yMode = header.read(156) == 1
              ? (header.read(128) == 1 ? _tmPred : _hPred)
              : (header.read(163) == 1 ? _vPred : _dcPred);
          final implied = switch (yMode) {
            _vPred => _bVe,
            _hPred => _bHe,
            _tmPred => _bTm,
            _ => _bDc,
          };
          modesAbove.fillRange(mbX * 4, mbX * 4 + 4, implied);
          modesLeft.fillRange(0, 4, implied);
        }
        final uvMode = header.read(142) == 0
            ? _dcPred
            : header.read(114) == 0
            ? _vPred
            : (header.read(183) == 1 ? _tmPred : _hPred);

        // The coefficients.
        coeffs.fillRange(0, 384, 0);
        var anyCoefficients = false;
        if (!skipFlag) {
          final (y1Dc, y1Ac, y2Dc, y2Ac, uvDc, uvAc) = _quant[segment];
          var first = 0;
          var lumaType = 3;
          if (yMode != _bPred) {
            final dc = Int16List(16);
            final ctx = nzDcAbove[mbX] + nzDcLeft;
            final nz = _coefficients(tokens, 1, ctx, y2Dc, y2Ac, 0, dc, 0);
            nzDcAbove[mbX] = nzDcLeft = nz > 0 ? 1 : 0;
            if (nz > 0) anyCoefficients = true;
            _inverseWht(dc, coeffs);
            first = 1;
            lumaType = 0;
          }
          var tnz = nzAbove[mbX] & 0x0f;
          var lnz = nzLeft & 0x0f;
          for (var y = 0; y < 4; y++) {
            var l = lnz & 1;
            for (var x = 0; x < 4; x++) {
              final ctx = l + (tnz & 1);
              final nz = _coefficients(
                tokens,
                lumaType,
                ctx,
                y1Dc,
                y1Ac,
                first,
                coeffs,
                (y * 4 + x) * 16,
              );
              l = nz > first ? 1 : 0;
              if (nz > first) anyCoefficients = true;
              tnz = (tnz >> 1) | (l << 7);
            }
            tnz >>= 4;
            lnz = (lnz >> 1) | (l << 7);
          }
          var outAbove = tnz;
          var outLeft = lnz >> 4;
          for (var ch = 0; ch < 4; ch += 2) {
            tnz = nzAbove[mbX] >> (4 + ch);
            lnz = nzLeft >> (4 + ch);
            for (var y = 0; y < 2; y++) {
              var l = lnz & 1;
              for (var x = 0; x < 2; x++) {
                final ctx = l + (tnz & 1);
                final nz = _coefficients(
                  tokens,
                  2,
                  ctx,
                  uvDc,
                  uvAc,
                  0,
                  coeffs,
                  256 + ch * 32 + (y * 2 + x) * 16,
                );
                l = nz > 0 ? 1 : 0;
                if (nz > 0) anyCoefficients = true;
                tnz = (tnz >> 1) | (l << 3);
              }
              tnz >>= 2;
              lnz = (lnz >> 1) | (l << 5);
            }
            outAbove |= (tnz << 4) << ch;
            outLeft |= (lnz & 0xf0) << ch;
          }
          nzAbove[mbX] = outAbove;
          nzLeft = outLeft;
        } else {
          nzAbove[mbX] = 0;
          nzLeft = 0;
          if (yMode != _bPred) {
            nzDcAbove[mbX] = 0;
            nzDcLeft = 0;
          }
        }
        if (tokens.pastEnd) {
          throw const ImageFormatException('VP8 coefficients are truncated');
        }

        // The filter for this macroblock.
        final isB = yMode == _bPred ? 1 : 0;
        final strength = strengths[segment * 2 + isB];
        final f = (mbY * mbWidth + mbX) * 4;
        filterInfo[f] = strength.$1; // limit
        filterInfo[f + 1] = strength.$2; // interior limit
        filterInfo[f + 2] = strength.$3; // high edge variance threshold
        filterInfo[f + 3] = isB == 1 || anyCoefficients ? 1 : 0;

        // Reconstruction into the work buffer.
        if (mbX > 0) {
          // The left samples: the previous macroblock's right column
          // (and the row above's, for the top left).
          for (var j = -1; j < 16; j++) {
            final row = _yOff + j * _bps;
            for (var k = 0; k < 4; k++) {
              work[row - 4 + k] = work[row + 12 + k];
            }
          }
          for (var j = -1; j < 8; j++) {
            for (final off in const [_uOff, _vOff]) {
              final row = off + j * _bps;
              for (var k = 0; k < 4; k++) {
                work[row - 4 + k] = work[row + 4 + k];
              }
            }
          }
        }
        if (mbY > 0) {
          work
            ..setRange(_yOff - _bps, _yOff - _bps + 16, topY, mbX * 16)
            ..setRange(_uOff - _bps, _uOff - _bps + 8, topU, mbX * 8)
            ..setRange(_vOff - _bps, _vOff - _bps + 8, topV, mbX * 8);
        }
        if (yMode == _bPred) {
          const topRight = _yOff - _bps + 16;
          if (mbY > 0) {
            if (mbX >= mbWidth - 1) {
              work.fillRange(topRight, topRight + 4, topY[mbX * 16 + 15]);
            } else {
              work.setRange(topRight, topRight + 4, topY, (mbX + 1) * 16);
            }
          }
          // The top right repeated beside subblock rows 1 to 3.
          for (var r = 1; r < 4; r++) {
            work.setRange(
              topRight + r * 4 * _bps,
              topRight + r * 4 * _bps + 4,
              work,
              topRight,
            );
          }
          for (var n = 0; n < 16; n++) {
            final at = _yOff + (n >> 2) * 4 * _bps + (n & 3) * 4;
            _predict4(work, at, modes[n]);
            _inverseDct(coeffs, n * 16, work, at);
          }
        } else {
          _predict16(work, _yOff, yMode, mbX, mbY);
          for (var n = 0; n < 16; n++) {
            _inverseDct(
              coeffs,
              n * 16,
              work,
              _yOff + (n >> 2) * 4 * _bps + (n & 3) * 4,
            );
          }
        }
        _predict8(work, _uOff, uvMode, mbX, mbY);
        _predict8(work, _vOff, uvMode, mbX, mbY);
        for (var n = 0; n < 4; n++) {
          final at = (n >> 1) * 4 * _bps + (n & 1) * 4;
          _inverseDct(coeffs, 256 + n * 16, work, _uOff + at);
          _inverseDct(coeffs, 320 + n * 16, work, _vOff + at);
        }
        // Into the frame, and the bottom rows kept for the next row.
        for (var j = 0; j < 16; j++) {
          yPlane.setRange(
            (mbY * 16 + j) * yStride + mbX * 16,
            (mbY * 16 + j) * yStride + mbX * 16 + 16,
            work,
            _yOff + j * _bps,
          );
        }
        for (var j = 0; j < 8; j++) {
          final to = (mbY * 8 + j) * uvStride + mbX * 8;
          uPlane.setRange(to, to + 8, work, _uOff + j * _bps);
          vPlane.setRange(to, to + 8, work, _vOff + j * _bps);
        }
        topY.setRange(mbX * 16, mbX * 16 + 16, work, _yOff + 15 * _bps);
        topU.setRange(mbX * 8, mbX * 8 + 8, work, _uOff + 7 * _bps);
        topV.setRange(mbX * 8, mbX * 8 + 8, work, _vOff + 7 * _bps);
      }
    }
    if (header.pastEnd) {
      throw const ImageFormatException('VP8 first partition is truncated');
    }
    if (_filterLevel > 0) {
      _loopFilter(yPlane, uPlane, vPlane, yStride, uvStride, filterInfo);
    }
    return (
      width: width,
      height: height,
      y: yPlane,
      u: uPlane,
      v: vPlane,
      yStride: yStride,
      uvStride: uvStride,
    );
  }

  /// The loop filter's limit, interior limit and high edge variance
  /// threshold for each segment, without and with subblock prediction
  /// (RFC 6386, 9.6, 15).
  List<(int, int, int)> _filterStrengths() => [
    for (var s = 0; s < 4; s++)
      for (var i4x4 = 0; i4x4 <= 1; i4x4++) _strength(s, i4x4 == 1),
  ];

  (int, int, int) _strength(int segment, bool i4x4) {
    var level = _filterLevel;
    if (_segmentation) {
      level = _segmentFilter[segment];
      if (!_absoluteDelta) level += _filterLevel;
    }
    if (_useDeltas) {
      level += _refDeltas[0];
      if (i4x4) level += _modeDeltas[0];
    }
    level = level < 0 ? 0 : (level > 63 ? 63 : level);
    if (level == 0) return (0, 0, 0);
    var interior = level;
    if (_sharpness > 0) {
      interior >>= _sharpness > 4 ? 2 : 1;
      if (interior > 9 - _sharpness) interior = 9 - _sharpness;
    }
    if (interior < 1) interior = 1;
    return (
      2 * level + interior,
      interior,
      level >= 40
          ? 2
          : level >= 15
          ? 1
          : 0,
    );
  }

  /// The coefficients of one block of [type] (0: luma after Y2, 1: Y2,
  /// 2: chroma, 3: luma with its DC) from [first], dequantized into
  /// [out] at [at] in raster order; the position after the last non-zero
  /// one (RFC 6386, 13).
  int _coefficients(
    _BoolDecoder d,
    int type,
    int ctx,
    int dcFactor,
    int acFactor,
    int first,
    Int16List out,
    int at,
  ) {
    var n = first;
    var p = ((type * 8 + _bands[n]) * 3 + ctx) * 11;
    final probs = _coeffProbs;
    while (n < 16) {
      if (d.read(probs[p]) == 0) return n; // end of block
      while (d.read(probs[p + 1]) == 0) {
        // A zero: the next position, in its zero context.
        n++;
        if (n == 16) return 16;
        p = ((type * 8 + _bands[n]) * 3 + 0) * 11;
      }
      int v;
      final int nextCtx;
      if (d.read(probs[p + 2]) == 0) {
        v = 1;
        nextCtx = 1;
      } else {
        v = _largeValue(d, p);
        nextCtx = 2;
      }
      if (d.read(128) == 1) v = -v;
      out[at + _zigzag[n]] = v * (n > 0 ? acFactor : dcFactor);
      n++;
      p = ((type * 8 + _bands[n]) * 3 + nextCtx) * 11;
    }
    return 16;
  }

  int _largeValue(_BoolDecoder d, int p) {
    final probs = _coeffProbs;
    if (d.read(probs[p + 3]) == 0) {
      if (d.read(probs[p + 4]) == 0) return 2;
      return 3 + d.read(probs[p + 5]);
    }
    if (d.read(probs[p + 6]) == 0) {
      if (d.read(probs[p + 7]) == 0) return 5 + d.read(159);
      final v = 7 + 2 * d.read(165);
      return v + d.read(145);
    }
    final bit1 = d.read(probs[p + 8]);
    final bit0 = d.read(probs[p + 9 + bit1]);
    final cat = 2 * bit1 + bit0;
    var v = 0;
    for (final probability in _catProbs[cat]) {
      v += v + d.read(probability);
    }
    return v + 3 + (8 << cat);
  }

  /// The inverse Walsh–Hadamard transform of the Y2 block [input] into
  /// the DC of each luma block of [out] (RFC 6386, 14.3).
  static void _inverseWht(Int16List input, Int16List out) {
    final tmp = Int32List(16);
    for (var i = 0; i < 4; i++) {
      final a0 = input[i] + input[12 + i];
      final a1 = input[4 + i] + input[8 + i];
      final a2 = input[4 + i] - input[8 + i];
      final a3 = input[i] - input[12 + i];
      tmp[i] = a0 + a1;
      tmp[8 + i] = a0 - a1;
      tmp[4 + i] = a3 + a2;
      tmp[12 + i] = a3 - a2;
    }
    for (var i = 0; i < 4; i++) {
      final dc = tmp[i * 4] + 3;
      final a0 = dc + tmp[3 + i * 4];
      final a1 = tmp[1 + i * 4] + tmp[2 + i * 4];
      final a2 = tmp[1 + i * 4] - tmp[2 + i * 4];
      final a3 = dc - tmp[3 + i * 4];
      out[(i * 4) * 16] = _shr(a0 + a1, 3);
      out[(i * 4 + 1) * 16] = _shr(a3 + a2, 3);
      out[(i * 4 + 2) * 16] = _shr(a0 - a1, 3);
      out[(i * 4 + 3) * 16] = _shr(a3 - a2, 3);
    }
  }

  /// The inverse DCT of the block of [coeffs] at [at], added to the 4 × 4
  /// pixels of [dst] at [to] (RFC 6386, 14.4).
  static void _inverseDct(Int16List coeffs, int at, Uint8List dst, int to) {
    var any = false;
    for (var i = 0; i < 16; i++) {
      if (coeffs[at + i] != 0) {
        any = true;
        break;
      }
    }
    if (!any) return;
    final tmp = Int32List(16);
    int mul1(int a) => _shr(a * 20091, 16) + a;
    int mul2(int a) => _shr(a * 35468, 16);
    for (var i = 0; i < 4; i++) {
      final in0 = coeffs[at + i];
      final in4 = coeffs[at + 4 + i];
      final in8 = coeffs[at + 8 + i];
      final in12 = coeffs[at + 12 + i];
      final a = in0 + in8;
      final b = in0 - in8;
      final c = mul2(in4) - mul1(in12);
      final d = mul1(in4) + mul2(in12);
      tmp[i * 4] = a + d;
      tmp[i * 4 + 1] = b + c;
      tmp[i * 4 + 2] = b - c;
      tmp[i * 4 + 3] = a - d;
    }
    for (var i = 0; i < 4; i++) {
      final dc = tmp[i] + 4;
      final a = dc + tmp[8 + i];
      final b = dc - tmp[8 + i];
      final c = mul2(tmp[4 + i]) - mul1(tmp[12 + i]);
      final d = mul1(tmp[4 + i]) + mul2(tmp[12 + i]);
      final row = to + i * _bps;
      dst[row] = _clip(dst[row] + _shr(a + d, 3));
      dst[row + 1] = _clip(dst[row + 1] + _shr(b + c, 3));
      dst[row + 2] = _clip(dst[row + 2] + _shr(b - c, 3));
      dst[row + 3] = _clip(dst[row + 3] + _shr(a - d, 3));
    }
  }

  /// 16 × 16 luma prediction at [at] (RFC 6386, 12.2); DC from what is
  /// there at the frame's edges.
  static void _predict16(Uint8List b, int at, int mode, int mbX, int mbY) {
    switch (mode) {
      case _dcPred:
        var sum = 0;
        int dc;
        if (mbY > 0 && mbX > 0) {
          for (var j = 0; j < 16; j++) {
            sum += b[at - _bps + j] + b[at + j * _bps - 1];
          }
          dc = (sum + 16) >> 5;
        } else if (mbY > 0) {
          for (var j = 0; j < 16; j++) {
            sum += b[at - _bps + j];
          }
          dc = (sum + 8) >> 4;
        } else if (mbX > 0) {
          for (var j = 0; j < 16; j++) {
            sum += b[at + j * _bps - 1];
          }
          dc = (sum + 8) >> 4;
        } else {
          dc = 128;
        }
        for (var y = 0; y < 16; y++) {
          b.fillRange(at + y * _bps, at + y * _bps + 16, dc);
        }
      case _vPred:
        for (var y = 0; y < 16; y++) {
          b.setRange(at + y * _bps, at + y * _bps + 16, b, at - _bps);
        }
      case _hPred:
        for (var y = 0; y < 16; y++) {
          b.fillRange(at + y * _bps, at + y * _bps + 16, b[at + y * _bps - 1]);
        }
      default:
        _trueMotion(b, at, 16);
    }
  }

  /// 8 × 8 chroma prediction at [at].
  static void _predict8(Uint8List b, int at, int mode, int mbX, int mbY) {
    switch (mode) {
      case _dcPred:
        var sum = 0;
        int dc;
        if (mbY > 0 && mbX > 0) {
          for (var j = 0; j < 8; j++) {
            sum += b[at - _bps + j] + b[at + j * _bps - 1];
          }
          dc = (sum + 8) >> 4;
        } else if (mbY > 0) {
          for (var j = 0; j < 8; j++) {
            sum += b[at - _bps + j];
          }
          dc = (sum + 4) >> 3;
        } else if (mbX > 0) {
          for (var j = 0; j < 8; j++) {
            sum += b[at + j * _bps - 1];
          }
          dc = (sum + 4) >> 3;
        } else {
          dc = 128;
        }
        for (var y = 0; y < 8; y++) {
          b.fillRange(at + y * _bps, at + y * _bps + 8, dc);
        }
      case _vPred:
        for (var y = 0; y < 8; y++) {
          b.setRange(at + y * _bps, at + y * _bps + 8, b, at - _bps);
        }
      case _hPred:
        for (var y = 0; y < 8; y++) {
          b.fillRange(at + y * _bps, at + y * _bps + 8, b[at + y * _bps - 1]);
        }
      default:
        _trueMotion(b, at, 8);
    }
  }

  static void _trueMotion(Uint8List b, int at, int size) {
    final topLeft = b[at - _bps - 1];
    for (var y = 0; y < size; y++) {
      final left = b[at + y * _bps - 1];
      for (var x = 0; x < size; x++) {
        b[at + y * _bps + x] = _clip(left + b[at - _bps + x] - topLeft);
      }
    }
  }

  /// 4 × 4 subblock prediction at [at] (RFC 6386, 12.3).
  static void _predict4(Uint8List b, int at, int mode) {
    int top(int x) => b[at - _bps + x];
    int left(int y) => b[at + y * _bps - 1];
    void set(int x, int y, int v) => b[at + y * _bps + x] = v;
    int avg3(int a, int b, int c) => (a + 2 * b + c + 2) >> 2;
    int avg2(int a, int b) => (a + b + 1) >> 1;
    final x0 = b[at - _bps - 1];
    switch (mode) {
      case _bDc:
        var dc = 4;
        for (var i = 0; i < 4; i++) {
          dc += top(i) + left(i);
        }
        dc >>= 3;
        for (var y = 0; y < 4; y++) {
          b.fillRange(at + y * _bps, at + y * _bps + 4, dc);
        }
      case _bTm:
        _trueMotion(b, at, 4);
      case _bVe:
        final vals = [
          for (var x = 0; x < 4; x++)
            avg3(x == 0 ? x0 : top(x - 1), top(x), top(x + 1)),
        ];
        for (var y = 0; y < 4; y++) {
          for (var x = 0; x < 4; x++) {
            set(x, y, vals[x]);
          }
        }
      case _bHe:
        final a = x0;
        final bb = left(0);
        final c = left(1);
        final d = left(2);
        final e = left(3);
        final rows = [
          avg3(a, bb, c),
          avg3(bb, c, d),
          avg3(c, d, e),
          avg3(d, e, e),
        ];
        for (var y = 0; y < 4; y++) {
          b.fillRange(at + y * _bps, at + y * _bps + 4, rows[y]);
        }
      case _bRd:
        final i = left(0);
        final j = left(1);
        final k = left(2);
        final l = left(3);
        final a = top(0);
        final bb = top(1);
        final c = top(2);
        final d = top(3);
        final x = x0;
        set(0, 3, avg3(j, k, l));
        final ijk = avg3(i, j, k);
        set(1, 3, ijk);
        set(0, 2, ijk);
        final xij = avg3(x, i, j);
        set(2, 3, xij);
        set(1, 2, xij);
        set(0, 1, xij);
        final axi = avg3(a, x, i);
        set(3, 3, axi);
        set(2, 2, axi);
        set(1, 1, axi);
        set(0, 0, axi);
        final bax = avg3(bb, a, x);
        set(3, 2, bax);
        set(2, 1, bax);
        set(1, 0, bax);
        final cba = avg3(c, bb, a);
        set(3, 1, cba);
        set(2, 0, cba);
        set(3, 0, avg3(d, c, bb));
      case _bLd:
        final t = [for (var x = 0; x < 8; x++) top(x)];
        set(0, 0, avg3(t[0], t[1], t[2]));
        final bcd = avg3(t[1], t[2], t[3]);
        set(1, 0, bcd);
        set(0, 1, bcd);
        final cde = avg3(t[2], t[3], t[4]);
        set(2, 0, cde);
        set(1, 1, cde);
        set(0, 2, cde);
        final def = avg3(t[3], t[4], t[5]);
        set(3, 0, def);
        set(2, 1, def);
        set(1, 2, def);
        set(0, 3, def);
        final efg = avg3(t[4], t[5], t[6]);
        set(3, 1, efg);
        set(2, 2, efg);
        set(1, 3, efg);
        final fgh = avg3(t[5], t[6], t[7]);
        set(3, 2, fgh);
        set(2, 3, fgh);
        set(3, 3, avg3(t[6], t[7], t[7]));
      case _bVr:
        final i = left(0);
        final j = left(1);
        final k = left(2);
        final x = x0;
        final a = top(0);
        final bb = top(1);
        final c = top(2);
        final d = top(3);
        final xa = avg2(x, a);
        set(0, 0, xa);
        set(1, 2, xa);
        final ab = avg2(a, bb);
        set(1, 0, ab);
        set(2, 2, ab);
        final bc = avg2(bb, c);
        set(2, 0, bc);
        set(3, 2, bc);
        set(3, 0, avg2(c, d));
        set(0, 3, avg3(k, j, i));
        set(0, 2, avg3(j, i, x));
        final ixa = avg3(i, x, a);
        set(0, 1, ixa);
        set(1, 3, ixa);
        final xab = avg3(x, a, bb);
        set(1, 1, xab);
        set(2, 3, xab);
        final abc = avg3(a, bb, c);
        set(2, 1, abc);
        set(3, 3, abc);
        set(3, 1, avg3(bb, c, d));
      case _bVl:
        final t = [for (var x = 0; x < 8; x++) top(x)];
        set(0, 0, avg2(t[0], t[1]));
        final bc = avg2(t[1], t[2]);
        set(1, 0, bc);
        set(0, 2, bc);
        final cd = avg2(t[2], t[3]);
        set(2, 0, cd);
        set(1, 2, cd);
        final de = avg2(t[3], t[4]);
        set(3, 0, de);
        set(2, 2, de);
        set(0, 1, avg3(t[0], t[1], t[2]));
        final bcd = avg3(t[1], t[2], t[3]);
        set(1, 1, bcd);
        set(0, 3, bcd);
        final cde = avg3(t[2], t[3], t[4]);
        set(2, 1, cde);
        set(1, 3, cde);
        final def = avg3(t[3], t[4], t[5]);
        set(3, 1, def);
        set(2, 3, def);
        set(3, 2, avg3(t[4], t[5], t[6]));
        set(3, 3, avg3(t[5], t[6], t[7]));
      case _bHd:
        final i = left(0);
        final j = left(1);
        final k = left(2);
        final l = left(3);
        final x = x0;
        final a = top(0);
        final bb = top(1);
        final c = top(2);
        final ix = avg2(i, x);
        set(0, 0, ix);
        set(2, 1, ix);
        final ji = avg2(j, i);
        set(0, 1, ji);
        set(2, 2, ji);
        final kj = avg2(k, j);
        set(0, 2, kj);
        set(2, 3, kj);
        set(0, 3, avg2(l, k));
        set(3, 0, avg3(a, bb, c));
        set(2, 0, avg3(x, a, bb));
        final ixa = avg3(i, x, a);
        set(1, 0, ixa);
        set(3, 1, ixa);
        final jix = avg3(j, i, x);
        set(1, 1, jix);
        set(3, 2, jix);
        final kji = avg3(k, j, i);
        set(1, 2, kji);
        set(3, 3, kji);
        set(1, 3, avg3(l, k, j));
      default: // _bHu
        final i = left(0);
        final j = left(1);
        final k = left(2);
        final l = left(3);
        set(0, 0, avg2(i, j));
        final jk = avg2(j, k);
        set(2, 0, jk);
        set(0, 1, jk);
        final kl = avg2(k, l);
        set(2, 1, kl);
        set(0, 2, kl);
        set(1, 0, avg3(i, j, k));
        final jkl = avg3(j, k, l);
        set(3, 0, jkl);
        set(1, 1, jkl);
        final kll = avg3(k, l, l);
        set(3, 1, kll);
        set(1, 2, kll);
        for (final (x, y) in const [
          (3, 2),
          (2, 2),
          (0, 3),
          (1, 3),
          (2, 3),
          (3, 3),
        ]) {
          set(x, y, l);
        }
    }
  }

  /// The loop filter over the whole frame, macroblock by macroblock in
  /// raster order (RFC 6386, 15).
  void _loopFilter(
    Uint8List y,
    Uint8List u,
    Uint8List v,
    int yStride,
    int uvStride,
    Int32List info,
  ) {
    for (var mbY = 0; mbY < mbHeight; mbY++) {
      for (var mbX = 0; mbX < mbWidth; mbX++) {
        final f = (mbY * mbWidth + mbX) * 4;
        final limit = info[f];
        if (limit == 0) continue;
        final interior = info[f + 1];
        final hev = info[f + 2];
        final inner = info[f + 3] == 1;
        final yAt = mbY * 16 * yStride + mbX * 16;
        final uvAt = mbY * 8 * uvStride + mbX * 8;
        if (_simple) {
          if (mbX > 0) _simpleFilter(y, yAt, 1, yStride, 16, limit + 4);
          if (inner) {
            for (var k = 4; k < 16; k += 4) {
              _simpleFilter(y, yAt + k, 1, yStride, 16, limit);
            }
          }
          if (mbY > 0) _simpleFilter(y, yAt, yStride, 1, 16, limit + 4);
          if (inner) {
            for (var k = 4; k < 16; k += 4) {
              _simpleFilter(y, yAt + k * yStride, yStride, 1, 16, limit);
            }
          }
          continue;
        }
        if (mbX > 0) {
          _filter(y, yAt, 1, yStride, 16, limit + 4, interior, hev, edge: true);
          _filter(
            u,
            uvAt,
            1,
            uvStride,
            8,
            limit + 4,
            interior,
            hev,
            edge: true,
          );
          _filter(
            v,
            uvAt,
            1,
            uvStride,
            8,
            limit + 4,
            interior,
            hev,
            edge: true,
          );
        }
        if (inner) {
          for (var k = 4; k < 16; k += 4) {
            _filter(y, yAt + k, 1, yStride, 16, limit, interior, hev);
          }
          _filter(u, uvAt + 4, 1, uvStride, 8, limit, interior, hev);
          _filter(v, uvAt + 4, 1, uvStride, 8, limit, interior, hev);
        }
        if (mbY > 0) {
          _filter(y, yAt, yStride, 1, 16, limit + 4, interior, hev, edge: true);
          _filter(
            u,
            uvAt,
            uvStride,
            1,
            8,
            limit + 4,
            interior,
            hev,
            edge: true,
          );
          _filter(
            v,
            uvAt,
            uvStride,
            1,
            8,
            limit + 4,
            interior,
            hev,
            edge: true,
          );
        }
        if (inner) {
          for (var k = 4; k < 16; k += 4) {
            _filter(y, yAt + k * yStride, yStride, 1, 16, limit, interior, hev);
          }
          _filter(u, uvAt + 4 * uvStride, uvStride, 1, 8, limit, interior, hev);
          _filter(v, uvAt + 4 * uvStride, uvStride, 1, 8, limit, interior, hev);
        }
      }
    }
  }

  /// The simple filter across the edge before [at], [step] across it,
  /// [count] pixels along it [along] apart.
  static void _simpleFilter(
    Uint8List p,
    int at,
    int step,
    int along,
    int count,
    int limit,
  ) {
    final t = 2 * limit + 1;
    for (var i = 0; i < count; i++) {
      final o = at + i * along;
      final p1 = p[o - 2 * step];
      final p0 = p[o - step];
      final q0 = p[o];
      final q1 = p[o + step];
      if (4 * (p0 - q0).abs() + (p1 - q1).abs() <= t) {
        _filter2(p, o, step);
      }
    }
  }

  /// The normal filter: macroblock [edge]s with six taps, inner edges
  /// with four (RFC 6386, 15.3).
  static void _filter(
    Uint8List p,
    int at,
    int step,
    int along,
    int count,
    int limit,
    int interior,
    int hevThreshold, {
    bool edge = false,
  }) {
    final t = 2 * limit + 1;
    for (var i = 0; i < count; i++) {
      final o = at + i * along;
      final p3 = p[o - 4 * step];
      final p2 = p[o - 3 * step];
      final p1 = p[o - 2 * step];
      final p0 = p[o - step];
      final q0 = p[o];
      final q1 = p[o + step];
      final q2 = p[o + 2 * step];
      final q3 = p[o + 3 * step];
      if (4 * (p0 - q0).abs() + (p1 - q1).abs() > t) continue;
      if ((p3 - p2).abs() > interior ||
          (p2 - p1).abs() > interior ||
          (p1 - p0).abs() > interior ||
          (q3 - q2).abs() > interior ||
          (q2 - q1).abs() > interior ||
          (q1 - q0).abs() > interior) {
        continue;
      }
      final hev =
          (p1 - p0).abs() > hevThreshold || (q1 - q0).abs() > hevThreshold;
      if (hev) {
        _filter2(p, o, step);
      } else if (edge) {
        // Six pixels.
        final a = _sclip1(3 * (q0 - p0) + _sclip1(p1 - q1));
        final a1 = _shr(27 * a + 63, 7);
        final a2 = _shr(18 * a + 63, 7);
        final a3 = _shr(9 * a + 63, 7);
        p[o - 3 * step] = _clip(p2 + a3);
        p[o - 2 * step] = _clip(p1 + a2);
        p[o - step] = _clip(p0 + a1);
        p[o] = _clip(q0 - a1);
        p[o + step] = _clip(q1 - a2);
        p[o + 2 * step] = _clip(q2 - a3);
      } else {
        // Four pixels.
        final a = 3 * (q0 - p0);
        final a1 = _sclip2(_shr(a + 4, 3));
        final a2 = _sclip2(_shr(a + 3, 3));
        final a3 = _shr(a1 + 1, 1);
        p[o - 2 * step] = _clip(p1 + a3);
        p[o - step] = _clip(p0 + a2);
        p[o] = _clip(q0 - a1);
        p[o + step] = _clip(q1 - a3);
      }
    }
  }

  /// Two pixels changed, from four.
  static void _filter2(Uint8List p, int o, int step) {
    final p1 = p[o - 2 * step];
    final p0 = p[o - step];
    final q0 = p[o];
    final q1 = p[o + step];
    final a = 3 * (q0 - p0) + _sclip1(p1 - q1);
    final a1 = _sclip2(_shr(a + 4, 3));
    final a2 = _sclip2(_shr(a + 3, 3));
    p[o - step] = _clip(p0 + a2);
    p[o] = _clip(q0 - a1);
  }
}

int _clip(int v) => v < 0 ? 0 : (v > 255 ? 255 : v);

/// [v] shifted right by [n] bits, rounding down: `>>` of a negative number
/// compiled to JavaScript gives an unsigned 32-bit result instead.
@pragma('vm:prefer-inline')
int _shr(int v, int n) =>
    !_web || v >= 0 ? v >> n : -((-v + (1 << n) - 1) >> n);

/// Whether this is JavaScript, whose numbers are doubles.
const bool _web = identical(0, 0.0);

/// Clamped to −128 to 127.
int _sclip1(int v) => v < -128 ? -128 : (v > 127 ? 127 : v);

/// Clamped to −16 to 15.
int _sclip2(int v) => v < -16 ? -16 : (v > 15 ? 15 : v);
