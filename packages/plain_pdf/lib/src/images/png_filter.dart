/// PNG scanline filtering (ISO/IEC 15948, 9, 12.8) of an image's samples
/// for a FlateDecode stream with a PNG predictor.
library;

import 'dart:typed_data';

/// [image]'s packed rows of [stride] bytes filtered again, each row with
/// the filter that leaves the smallest sum of absolute differences (the
/// heuristic of the PNG specification, 12.8; the first of equal ones),
/// for a FlateDecode stream with predictor 15.
Uint8List filterImage(Uint8List image, int stride, int bpp) {
  final rows = stride == 0 ? 0 : image.length ~/ stride;
  final out = Uint8List(rows * (stride + 1));
  // The row above the first: zeros.
  final zeros = Uint8List(stride);
  for (var r = 0; r < rows; r++) {
    final row = r * stride;
    final above = r == 0 ? zeros : image;
    final up = r == 0 ? 0 : row - stride;
    var bestFilter = 0;
    var bestScore = _score(
      image,
      row,
      above,
      up,
      stride,
      bpp,
      0,
      stride * 128 + 1,
    );
    for (var filter = 1; filter <= 4; filter++) {
      final score = _score(
        image,
        row,
        above,
        up,
        stride,
        bpp,
        filter,
        bestScore,
      );
      if (score < bestScore) {
        bestScore = score;
        bestFilter = filter;
      }
    }
    final at = r * (stride + 1);
    out[at] = bestFilter;
    _filterRow(image, row, above, up, stride, bpp, bestFilter, out, at + 1);
  }
  return out;
}

/// The sum of the absolute differences of [filter]'s residuals for the
/// row of [image] at [row] (the row above it in [above] at [up]), or
/// [limit] or more once it reaches it.
int _score(
  Uint8List image,
  int row,
  Uint8List above,
  int up,
  int stride,
  int bpp,
  int filter,
  int limit,
) {
  var score = 0;
  switch (filter) {
    case 0:
      for (var i = 0; i < stride; i++) {
        final v = image[row + i];
        score += v < 128 ? v : 256 - v;
        if (score >= limit) return score;
      }
    case 1:
      for (var i = 0; i < stride; i++) {
        final left = i >= bpp ? image[row + i - bpp] : 0;
        final v = (image[row + i] - left) & 0xff;
        score += v < 128 ? v : 256 - v;
        if (score >= limit) return score;
      }
    case 2:
      for (var i = 0; i < stride; i++) {
        final v = (image[row + i] - above[up + i]) & 0xff;
        score += v < 128 ? v : 256 - v;
        if (score >= limit) return score;
      }
    case 3:
      for (var i = 0; i < stride; i++) {
        final left = i >= bpp ? image[row + i - bpp] : 0;
        final v = (image[row + i] - ((left + above[up + i]) >> 1)) & 0xff;
        score += v < 128 ? v : 256 - v;
        if (score >= limit) return score;
      }
    default:
      for (var i = 0; i < stride; i++) {
        final a = i >= bpp ? image[row + i - bpp] : 0;
        final b = above[up + i];
        final c = i >= bpp ? above[up + i - bpp] : 0;
        final v = (image[row + i] - _paethOf(a, b, c)) & 0xff;
        score += v < 128 ? v : 256 - v;
        if (score >= limit) return score;
      }
  }
  return score;
}

/// Writes [filter]'s residuals for the row of [image] at [row] (the row
/// above it in [above] at [up]) to [out] at [at].
void _filterRow(
  Uint8List image,
  int row,
  Uint8List above,
  int up,
  int stride,
  int bpp,
  int filter,
  Uint8List out,
  int at,
) {
  switch (filter) {
    case 0:
      out.setRange(at, at + stride, image, row);
    case 1:
      for (var i = 0; i < stride; i++) {
        final left = i >= bpp ? image[row + i - bpp] : 0;
        out[at + i] = image[row + i] - left;
      }
    case 2:
      for (var i = 0; i < stride; i++) {
        out[at + i] = image[row + i] - above[up + i];
      }
    case 3:
      for (var i = 0; i < stride; i++) {
        final left = i >= bpp ? image[row + i - bpp] : 0;
        out[at + i] = image[row + i] - ((left + above[up + i]) >> 1);
      }
    default:
      for (var i = 0; i < stride; i++) {
        final a = i >= bpp ? image[row + i - bpp] : 0;
        final b = above[up + i];
        final c = i >= bpp ? above[up + i - bpp] : 0;
        out[at + i] = image[row + i] - _paethOf(a, b, c);
      }
  }
}

/// The Paeth predictor of left [a], above [b] and upper left [c] (the
/// one of them nearest `a + b - c`, in that order on ties), with the
/// absolute values inline.
@pragma('vm:prefer-inline')
int _paethOf(int a, int b, int c) {
  final p = a + b - c;
  var pa = p - a;
  if (pa < 0) pa = -pa;
  var pb = p - b;
  if (pb < 0) pb = -pb;
  var pc = p - c;
  if (pc < 0) pc = -pc;
  if (pa <= pb && pa <= pc) return a;
  if (pb <= pc) return b;
  return c;
}
