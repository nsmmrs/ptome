/// Y'CbCr 4:2:0 to RGB as libwebp converts it (14-bit fixed point,
/// BT.601 limited range), the chroma upsampled by "fancy" (9-3-3-1)
/// interpolation between the samples.
library;

import 'dart:typed_data';

int _mulHi(int v, int coeff) => (v * coeff) >> 8;

int _clip8(int v) => (v & ~16383) == 0 ? v >> 6 : (v < 0 ? 0 : 255);

/// [y], [u], [v] as 8-bit R, G, B into [out] at [at].
void yuvToRgb(int y, int u, int v, Uint8List out, int at) {
  final yy = _mulHi(y, 19077);
  out[at] = _clip8(yy + _mulHi(v, 26149) - 14234);
  out[at + 1] = _clip8(yy - _mulHi(u, 6419) - _mulHi(v, 13320) + 8708);
  out[at + 2] = _clip8(yy + _mulHi(u, 33050) - 17685);
}

/// The RGBA pixels (alpha 255) of a [width] by [height] image from its
/// planes.
Uint8List yuv420ToRgba(
  int width,
  int height,
  Uint8List yPlane,
  int yStride,
  Uint8List uPlane,
  Uint8List vPlane,
  int uvStride,
) {
  final out = Uint8List(width * height * 4);
  for (var i = 3; i < out.length; i += 4) {
    out[i] = 255;
  }
  // One row of output from luma row [row], chroma rows [top] (nearer)
  // and [cur] weighted 3 to 1.
  void line(int row, int top, int cur) {
    final yAt = row * yStride;
    final o = row * width * 4;
    final tAt = top * uvStride;
    final cAt = cur * uvStride;
    int load(Uint8List plane, int at) => plane[at];
    var tlU = load(uPlane, tAt);
    var tlV = load(vPlane, tAt);
    var lU = load(uPlane, cAt);
    var lV = load(vPlane, cAt);
    yuvToRgb(
      yPlane[yAt],
      (3 * tlU + lU + 2) >> 2,
      (3 * tlV + lV + 2) >> 2,
      out,
      o,
    );
    final last = (width - 1) >> 1;
    for (var x = 1; x <= last; x++) {
      final tU = uPlane[tAt + x];
      final tV = vPlane[tAt + x];
      final cU = uPlane[cAt + x];
      final cV = vPlane[cAt + x];
      // libwebp packs U and V in one word; the halves don't mix.
      int diag12(int tl, int t, int l, int c) =>
          (tl + t + l + c + 8 + 2 * (t + l)) >> 3;
      int diag03(int tl, int t, int l, int c) =>
          (tl + t + l + c + 8 + 2 * (tl + c)) >> 3;
      final d12u = diag12(tlU, tU, lU, cU);
      final d03u = diag03(tlU, tU, lU, cU);
      final d12v = diag12(tlV, tV, lV, cV);
      final d03v = diag03(tlV, tV, lV, cV);
      yuvToRgb(
        yPlane[yAt + 2 * x - 1],
        (d12u + tlU) >> 1,
        (d12v + tlV) >> 1,
        out,
        o + (2 * x - 1) * 4,
      );
      yuvToRgb(
        yPlane[yAt + 2 * x],
        (d03u + tU) >> 1,
        (d03v + tV) >> 1,
        out,
        o + 2 * x * 4,
      );
      tlU = tU;
      tlV = tV;
      lU = cU;
      lV = cV;
    }
    if (width.isEven) {
      yuvToRgb(
        yPlane[yAt + width - 1],
        (3 * tlU + lU + 2) >> 2,
        (3 * tlV + lV + 2) >> 2,
        out,
        o + (width - 1) * 4,
      );
    }
  }

  line(0, 0, 0);
  for (var y = 1; y + 1 < height; y += 2) {
    final k = (y - 1) >> 1;
    line(y, k, k + 1);
    line(y + 1, k + 1, k);
  }
  if (height.isEven && height > 1) {
    final k = (height - 1) >> 1;
    line(height - 1, k, k);
  }
  return out;
}
