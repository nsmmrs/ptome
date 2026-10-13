/// GIF files made by hand: what ImageMagick doesn't write (a local color
/// table only, no color table, a full LZW table kept without a clear
/// code), and damage.
library;

import 'dart:typed_data';

import 'package:plain_images/plain_images.dart';
import 'package:plain_images/src/gif_decode.dart';
import 'package:test/test.dart';

/// GIF's LZW encoding of [indices] with roots of [minCodeSize] bits, the
/// table never cleared once full (a decoder must keep using it).
Uint8List lzwEncode(List<int> indices, int minCodeSize) {
  final clear = 1 << minCodeSize;
  final out = BytesBuilder();
  var bits = 0;
  var held = 0;
  var size = minCodeSize + 1;
  void emit(int code) {
    bits |= code << held;
    held += size;
    while (held >= 8) {
      out.addByte(bits & 0xff);
      bits >>= 8;
      held -= 8;
    }
  }

  final table = <String, int>{};
  var next = clear + 2;
  emit(clear);
  var current = '${indices.first}';
  for (final index in indices.skip(1)) {
    final extended = '$current,$index';
    if (table.containsKey(extended)) {
      current = extended;
      continue;
    }
    emit(current.contains(',') ? table[current]! : int.parse(current));
    if (next < 4096) {
      table[extended] = next++;
      // The decoder is a code behind: it grows when it adds this one.
      if (next - 1 == 1 << size && size < 12) size++;
    }
    current = '$index';
  }
  emit(current.contains(',') ? table[current]! : int.parse(current));
  emit(clear + 1);
  if (held > 0) out.addByte(bits & 0xff);
  return out.takeBytes();
}

/// A GIF of one [width] by [height] frame of [indices]: [global] or
/// [local] color tables (RGB triples, a power of two entries), the frame
/// at [left], [top] on a screen [screen] large (the frame's size by
/// default), with a graphic control for [transparent].
Uint8List gif(
  int width,
  int height,
  List<int> indices, {
  List<int>? global,
  List<int>? local,
  int minCodeSize = 2,
  (int, int)? screen,
  int left = 0,
  int top = 0,
  int? transparent,
  Uint8List? data,
}) {
  int sizeBits(List<int> table) {
    var n = 0;
    while (3 << (n + 1) < table.length) {
      n++;
    }
    return n;
  }

  final (sw, sh) = screen ?? (width, height);
  final lzw = data ?? lzwEncode(indices, minCodeSize);
  return Uint8List.fromList([
    ...'GIF89a'.codeUnits,
    sw & 0xff, sw >> 8, sh & 0xff, sh >> 8, //
    if (global != null) 0x80 | sizeBits(global) else 0,
    0, 0,
    ...?global,
    if (transparent != null) ...[0x21, 0xf9, 4, 1, 0, 0, transparent, 0],
    0x2c, left & 0xff, left >> 8, top & 0xff, top >> 8, //
    width & 0xff, width >> 8, height & 0xff, height >> 8,
    if (local != null) 0x80 | sizeBits(local) else 0,
    ...?local,
    minCodeSize,
    for (var at = 0; at < lzw.length; at += 255) ...[
      if (lzw.length - at < 255) lzw.length - at else 255,
      ...lzw.sublist(at, at + 255 < lzw.length ? at + 255 : lzw.length),
    ],
    0,
    0x3b,
  ]);
}

void main() {
  const palette = [0, 0, 0, 255, 0, 0, 0, 255, 0, 0, 0, 255];

  test('a local color table only', () {
    final file = ImageFile.read(gif(2, 2, [0, 1, 2, 3], local: palette));
    final raster = file.decode();
    expect(raster.colorModel, ColorModel.indexed);
    expect(raster.samples, [0, 1, 2, 3]);
    expect(raster.palette!.sublist(0, 12), palette);
    expect(raster.transparency, isNull);
  });

  test('without a color table, gray levels', () {
    final raster = ImageFile.read(gif(4, 1, [0, 1, 2, 3])).decode();
    expect(raster.palette, [0, 0, 0, 85, 85, 85, 170, 170, 170, 255, 255, 255]);
  });

  test('the transparent index is a color key', () {
    final raster = ImageFile.read(
      gif(2, 1, [0, 1], global: palette, transparent: 1),
    ).decode();
    expect((raster.transparency! as ColorKey).values, [1]);
    expect(raster.toRgba8(), [0, 0, 0, 255, 255, 0, 0, 0]);
  });

  test('around a frame smaller than the screen, transparent', () {
    final file = ImageFile.read(
      gif(1, 1, [2], global: palette, screen: (3, 2), left: 1, top: 1),
    ) as GifFile;
    expect((file.width, file.height), (3, 2));
    final raster = file.decode();
    // The key is a fifth entry, past the palette's four.
    expect(raster.samples, [4, 4, 4, 4, 2, 4]);
    expect((raster.transparency! as ColorKey).values, [4]);
  });

  test('a full table is kept without a clear code', () {
    // Long enough that the encoder runs out of codes; its strings keep
    // being matched after.
    final indices = [
      for (var i = 0; i < 40000; i++) (i * 7 + (i >> 5) * 3 + (i >> 9)) & 15,
    ];
    final colors = [for (var i = 0; i < 16 * 3; i++) i * 5];
    final raster = ImageFile.read(
      gif(200, 200, indices, global: colors, minCodeSize: 4),
    ).decode();
    expect(raster.samples, indices);
  });

  test('a code for the string being made (KwKwK)', () {
    // 0 0 0 0: codes 0, then 6 (0 0) before it is in the table.
    expect(lzwDecodeGif(lzwEncode([0, 0, 0, 0, 0, 0], 2), 2, 6), [
      0, 0, 0, 0, 0, 0, //
    ]);
  });

  test('damage: missing data leaves 0, a missing image is an error', () {
    final whole = lzwEncode([1, 2, 3, 1, 2, 3, 1, 2, 3], 2);
    final cut = Uint8List.sublistView(whole, 0, 2);
    final raster = ImageFile.read(
      gif(9, 1, const [], global: palette, data: cut),
    ).decode();
    expect(raster.samples.length, 9);
    expect(raster.samples.last, 0);
    expect(
      () => ImageFile.read(
        Uint8List.fromList([...'GIF89a'.codeUnits, 1, 0, 1, 0, 0, 0, 0, 0x3b]),
      ),
      throwsA(isA<ImageFormatException>()),
    );
  });

  test('frames are counted', () {
    final one = gif(1, 1, [0], global: palette);
    // The same image twice: a second frame before the trailer.
    final two = Uint8List.fromList([
      ...one.sublist(0, one.length - 1),
      ...one.sublist(13 + 12, one.length),
    ]);
    expect((ImageFile.read(one) as GifFile).frames, 1);
    expect((ImageFile.read(two) as GifFile).frames, 2);
  });
}
