/// An image's outline from its alpha channel: where its opaque pixels
/// are, band by band, for text to run around (CSS's `shape-outside` with
/// an image, `shape-image-threshold`).
library;

import 'dart:typed_data';

import 'package:plain_images/plain_images.dart';

/// The outline of an image [width] by [height] pixels: across each band
/// of [bandRows] rows from the top, the first and last columns of its
/// opaque pixels (null for a band without any).
final class ImageOutline {
  /// An outline of [bands].
  const new(this.width, this.height, this.bandRows, this.bands);

  /// The image's width, in pixels.
  final int width;

  /// The image's height, in pixels.
  final int height;

  /// The rows in each band.
  final int bandRows;

  /// The columns each band covers, from the first to the last.
  final List<(int, int)?> bands;
}

/// The outline of the image file in [bytes], its pixels opaque where
/// their alpha is above [threshold] (0 to 1), in at most [maxBands] bands;
/// null when it can't be read or has nothing transparent (its outline is
/// its box).
ImageOutline? alphaOutline(
  List<int> bytes, {
  double threshold = 0.5,
  int maxBands = 200,
}) {
  final Raster raster;
  try {
    final file = ImageFile.read(Uint8List.fromList(bytes));
    // (JPEG has no transparency.)
    if (file is JpegFile) return null;
    raster = file.decode();
  } on FormatException {
    return null;
  }
  final (width, height) = (raster.width, raster.height);
  final bandRows = (height / maxBands).ceil().clamp(1, height);
  final int Function(int x, int y) sample;
  final double cut;
  switch (raster.transparency) {
    case null:
      return null;
    case AlphaChannel(samples: final alpha, :final bitDepth):
      final wide = bitDepth == 16;
      cut = threshold * (wide ? 65535 : 255);
      sample = (x, y) {
        final at = (y * width + x) * (wide ? 2 : 1);
        return wide ? alpha[at] << 8 | alpha[at + 1] : alpha[at];
      };
    case ColorKey(:final values):
      // Transparent or opaque: the key's pixels 0, the others 1.
      cut = threshold;
      final channels = raster.colorModel.channels;
      sample = (x, y) {
        for (var c = 0; c < channels; c++) {
          if (raster.sample(x, y, c) != values[c]) return 1;
        }
        return 0;
      };
  }

  final bands = <(int, int)?>[];
  for (var top = 0; top < height; top += bandRows) {
    int? first;
    int? last;
    for (var y = top; y < top + bandRows && y < height; y++) {
      for (var x = 0; x < width; x++) {
        if (sample(x, y) > cut) {
          if (first == null || x < first) first = x;
          break;
        }
      }
      for (var x = width - 1; x >= 0; x--) {
        if (sample(x, y) > cut) {
          if (last == null || x > last) last = x;
          break;
        }
      }
    }
    bands.add(first == null ? null : (first, last!));
  }
  return ImageOutline(width, height, bandRows, bands);
}
