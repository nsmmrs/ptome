/// A font's color glyphs (OpenType 1.9): layered and painted glyphs
/// (`COLR` versions 0 and 1, colored from `CPAL`'s palettes) and bitmap
/// glyphs (PNG images in `CBDT`/`CBLC` strikes, Google's color bitmaps,
/// and in `sbix` strikes, Apple's). [ColorGlyphs.paint] walks a glyph's
/// paint as HarfBuzz 14.6.0's `hb_font_paint_glyph` does, telling a
/// [ColorPainter] what to draw.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:plain_fonts/src/opentype.dart';

/// A color: red, green, blue and alpha from 0 to 255.
@immutable
final class PaletteColor {
  /// The color of [red], [green], [blue] and [alpha] (0 to 255).
  const new(this.red, this.green, this.blue, [this.alpha = 255]);

  /// Red, 0 to 255.
  final int red;

  /// Green, 0 to 255.
  final int green;

  /// Blue, 0 to 255.
  final int blue;

  /// Alpha, 0 (transparent) to 255 (opaque).
  final int alpha;

  /// Opaque black.
  static const PaletteColor black = PaletteColor(0, 0, 0);

  @override
  bool operator ==(Object other) =>
      other is PaletteColor &&
      other.red == red &&
      other.green == green &&
      other.blue == blue &&
      other.alpha == alpha;

  @override
  int get hashCode => Object.hash(red, green, blue, alpha);

  @override
  String toString() => [
    red,
    green,
    blue,
    alpha,
  ].map((c) => c.toRadixString(16).padLeft(2, '0')).join();
}

/// A color a glyph is painted in: a palette's, or the text's own
/// (`foreground`, palette index 0xFFFF), with the paint's alpha applied.
@immutable
final class PaintColor {
  /// [color], the text's own when [foreground].
  const new(this.color, {this.foreground = false});

  /// The color, its alpha the palette's times the paint's.
  final PaletteColor color;

  /// Whether it is the text's color rather than a palette's.
  final bool foreground;

  @override
  bool operator ==(Object other) =>
      other is PaintColor &&
      other.color == color &&
      other.foreground == foreground;

  @override
  int get hashCode => Object.hash(color, foreground);
}

/// How a gradient continues past its first and last stops.
enum ColorExtend {
  /// The end colors continue.
  pad,

  /// The stops repeat.
  repeat,

  /// The stops repeat, every other time backwards.
  reflect,
}

/// The stops of a gradient, colors resolved, in the font's order.
@immutable
final class ColorLine {
  /// [stops] continued past their ends by [extend].
  const new(this.extend, this.stops);

  /// How it continues past the first and last stops.
  final ColorExtend extend;

  /// Each stop's offset and color.
  final List<(double, PaintColor)> stops;
}

/// How a paint is composited onto what is below it (`COLR`'s
/// CompositeMode: Porter and Duff's operators, then the blend modes of
/// W3C's Compositing and Blending).
enum CompositeMode {
  /// Nothing.
  clear,

  /// The source alone.
  src,

  /// The backdrop alone.
  dest,

  /// The source over the backdrop.
  srcOver,

  /// The backdrop over the source.
  destOver,

  /// The source where the backdrop is.
  srcIn,

  /// The backdrop where the source is.
  destIn,

  /// The source where the backdrop isn't.
  srcOut,

  /// The backdrop where the source isn't.
  destOut,

  /// The source over the backdrop, where the backdrop is.
  srcAtop,

  /// The backdrop over the source, where the source is.
  destAtop,

  /// The source and the backdrop where the other isn't.
  xor,

  /// The two added.
  plus,

  /// Screen.
  screen,

  /// Overlay.
  overlay,

  /// Darken.
  darken,

  /// Lighten.
  lighten,

  /// Color dodge.
  colorDodge,

  /// Color burn.
  colorBurn,

  /// Hard light.
  hardLight,

  /// Soft light.
  softLight,

  /// Difference.
  difference,

  /// Exclusion.
  exclusion,

  /// Multiply.
  multiply,

  /// The source's hue.
  hue,

  /// The source's saturation.
  saturation,

  /// The source's hue and saturation.
  color,

  /// The source's luminosity.
  luminosity,
}

/// An affine transformation: a point (x, y) goes to (xx·x + xy·y + dx,
/// yx·x + yy·y + dy), as HarfBuzz's `hb_transform_t` (and a PDF's `cm`,
/// [xx yx xy yy dx dy]) has it.
typedef ColorTransform = ({
  double xx,
  double yx,
  double xy,
  double yy,
  double dx,
  double dy,
});

/// A rectangle in font units.
typedef ColorBox = ({int xMin, int yMin, int xMax, int yMax});

/// A bitmap glyph: a PNG image and where it goes, its extents in font
/// units ([left] and [top] from the glyph's origin, y up), as HarfBuzz
/// gives them (rounded to whole units).
@immutable
final class BitmapGlyph {
  /// The image [png], [pixelWidth] by [pixelHeight], placed at
  /// ([left], [top]) and [width] by [height] font units large.
  const new(
    this.png, {
    required this.pixelWidth,
    required this.pixelHeight,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  /// The PNG image.
  final Uint8List png;

  /// The image's width in pixels.
  final int pixelWidth;

  /// The image's height in pixels.
  final int pixelHeight;

  /// Its left edge, from the glyph's origin, in font units.
  final int left;

  /// Its top edge, above the baseline, in font units.
  final int top;

  /// Its width in font units.
  final int width;

  /// Its height in font units (down from [top]).
  final int height;
}

/// What a color glyph's paint draws, told as HarfBuzz's paint functions
/// are (`hb_paint_funcs_t`), each nesting a callback: the coordinates are
/// in font units (y up), a color fills the clip in effect.
abstract interface class ColorPainter {
  /// Draws what [paint] draws through [transform].
  void transform(ColorTransform transform, void Function() paint);

  /// Draws what [paint] draws clipped to [glyph]'s outline.
  void clipGlyph(int glyph, void Function() paint);

  /// Draws what [paint] draws clipped to [box].
  void clipBox(ColorBox box, void Function() paint);

  /// Fills [glyph]'s outline with [color].
  void fillGlyph(int glyph, PaintColor color);

  /// Fills the clip with [color].
  void solid(PaintColor color);

  /// Fills the clip with a linear gradient of [line]: from ([x0], [y0])
  /// to ([x1], [y1]), its lines of one color parallel to the line from
  /// ([x0], [y0]) to ([x2], [y2]).
  void linearGradient(
    ColorLine line,
    double x0,
    double y0,
    double x1,
    double y1,
    double x2,
    double y2,
  );

  /// Fills the clip with a radial gradient of [line] from the circle
  /// ([x0], [y0], [r0]) to the circle ([x1], [y1], [r1]).
  void radialGradient(
    ColorLine line,
    double x0,
    double y0,
    double r0,
    double x1,
    double y1,
    double r1,
  );

  /// Fills the clip with a sweep gradient of [line] around ([x], [y])
  /// from [startAngle] to [endAngle] (radians, counterclockwise from the
  /// x axis).
  void sweepGradient(
    ColorLine line,
    double x,
    double y,
    double startAngle,
    double endAngle,
  );

  /// Draws what [source] draws onto what [backdrop] draws, by [mode].
  void composite(
    CompositeMode mode,
    void Function() backdrop,
    void Function() source,
  );

  /// Draws [bitmap] (its extents in font units).
  void image(BitmapGlyph bitmap);
}

/// A paint of `COLR` version 1, read from the font.
sealed class _Paint {
  const new();
}

final class _Layers extends _Paint {
  const new(this.first, this.count);
  final int first;
  final int count;
}

final class _Solid extends _Paint {
  const new(this.paletteIndex, this.alpha);
  final int paletteIndex;
  final double alpha;
}

final class _RawLine {
  const new(this.extend, this.stops);
  final ColorExtend extend;
  final List<(double, int, double)> stops;
}

final class _Linear extends _Paint {
  const new(this.line, this.x0, this.y0, this.x1, this.y1, this.x2, this.y2);
  final _RawLine line;
  final double x0;
  final double y0;
  final double x1;
  final double y1;
  final double x2;
  final double y2;
}

final class _Radial extends _Paint {
  const new(this.line, this.x0, this.y0, this.r0, this.x1, this.y1, this.r1);
  final _RawLine line;
  final double x0;
  final double y0;
  final double r0;
  final double x1;
  final double y1;
  final double r1;
}

final class _Sweep extends _Paint {
  const new(this.line, this.x, this.y, this.start, this.end);
  final _RawLine line;
  final double x;
  final double y;
  final double start;
  final double end;
}

final class _Glyph extends _Paint {
  const new(this.glyph, this.paint);
  final int glyph;
  final _Paint paint;
}

final class _ColorGlyph extends _Paint {
  const new(this.glyph);
  final int glyph;
}

final class _Transformed extends _Paint {
  const new(this.transform, this.paint);
  final ColorTransform transform;
  final _Paint paint;
}

final class _Composite extends _Paint {
  const new(this.source, this.mode, this.backdrop);
  final _Paint source;
  final CompositeMode mode;
  final _Paint backdrop;
}

/// A paint that can't be read (an unknown format, data past the end):
/// nothing is drawn for it.
final class _Nothing extends _Paint {
  const new();
}

/// Big-endian reads from a table.
extension type const _Bytes(ByteData data) {
  int u8(int at) => data.getUint8(at);
  int i8(int at) => data.getInt8(at);
  int u16(int at) => data.getUint16(at);
  int i16(int at) => data.getInt16(at);
  int u24(int at) => data.getUint8(at) << 16 | data.getUint16(at + 1);
  int u32(int at) => data.getUint32(at);
  double f2dot14(int at) => data.getInt16(at) / 16384;
  double fixed(int at) => data.getInt32(at) / 65536;
  int get length => data.lengthInBytes;
}

_Bytes? _bytesOf(OpenTypeFont font, String tag) => switch (font.table(tag)) {
  final table? => _Bytes(ByteData.sublistView(table)),
  null => null,
};

/// The color glyphs of an OpenType font: its `COLR` paints and layers in
/// `CPAL`'s colors, and its `CBDT` and `sbix` bitmaps.
final class ColorGlyphs {
  new _(this.font)
    : _colr = _bytesOf(font, 'COLR'),
      _cpal = _bytesOf(font, 'CPAL'),
      _cblc = _bytesOf(font, 'CBLC'),
      _cbdt = _bytesOf(font, 'CBDT'),
      _sbix = _bytesOf(font, 'sbix');

  /// The color glyphs of [font]; null when it has none (no `COLR`,
  /// `CBDT` or `sbix` table).
  static ColorGlyphs? of(OpenTypeFont font) {
    if (!font.hasTable('COLR') &&
        !(font.hasTable('CBDT') && font.hasTable('CBLC')) &&
        !font.hasTable('sbix')) {
      return null;
    }
    return ColorGlyphs._(font);
  }

  /// The font.
  final OpenTypeFont font;

  final _Bytes? _colr;
  final _Bytes? _cpal;
  final _Bytes? _cblc;
  final _Bytes? _cbdt;
  final _Bytes? _sbix;

  /// The palettes (`CPAL`), each a list of colors.
  late final List<List<PaletteColor>> palettes = _safe(() {
    final cpal = _cpal;
    if (cpal == null) return const <List<PaletteColor>>[];
    final entries = cpal.u16(2);
    final count = cpal.u16(4);
    final records = cpal.u32(8);
    return [
      for (var p = 0; p < count; p++)
        [
          for (var e = 0; e < entries; e++)
            () {
              final at = records + 4 * (cpal.u16(12 + 2 * p) + e);
              return PaletteColor(
                cpal.u8(at + 2),
                cpal.u8(at + 1),
                cpal.u8(at),
                cpal.u8(at + 3),
              );
            }(),
        ],
    ];
  }, const <List<PaletteColor>>[]);

  /// Whether [glyph] is a color glyph (painted, layered or a bitmap).
  bool hasGlyph(int glyph) =>
      _basePaint(glyph) != null ||
      _layersOf(glyph) != null ||
      _bitmap(glyph) != null;

  /// Paints [glyph] with [painter] in [palette] (`CPAL`'s), [foreground]
  /// standing for the text's color: its `COLR` version 1 paint (clipped
  /// to its clip box), else its version 0 layers, else its `CBDT`
  /// bitmap, else its `sbix` one, as HarfBuzz paints it. Returns whether
  /// it is a color glyph.
  bool paint(
    int glyph,
    ColorPainter painter, {
    int palette = 0,
    PaletteColor foreground = PaletteColor.black,
  }) {
    final context = _Context(this, painter, palette, foreground);
    if (_basePaint(glyph) case final paint?) {
      context.colorGlyphs.add(glyph);
      void draw() => context.recurse(paint);
      switch (clipBoxOf(glyph)) {
        case final box?:
          painter.clipBox(box, draw);
        case null:
          draw();
      }
      return true;
    }
    if (_layersOf(glyph) case final layers?) {
      for (final (layer, index) in layers) {
        painter.fillGlyph(layer, context.color(index, 1));
      }
      return true;
    }
    if (_bitmap(glyph) case final bitmap?) {
      painter.image(bitmap);
      return true;
    }
    return false;
  }

  /// The bitmap of [glyph], if it has one: its `CBDT` image, else its
  /// `sbix` one, from the strike of the smallest size not under [ppem]
  /// (else the largest; the largest without [ppem]), as HarfBuzz chooses.
  BitmapGlyph? bitmap(int glyph, {int? ppem}) => _bitmap(glyph, ppem: ppem);

  /// The extents of [glyph]'s bitmap, as HarfBuzz measures a glyph: its
  /// `sbix` image's, else its `CBDT` one's (the largest strikes'); null
  /// where it has none.
  BitmapGlyph? bitmapExtents(int glyph) =>
      _safe(() => _sbixBitmap(glyph, null), null) ??
      _safe(() => _cbdtBitmap(glyph, null), null);

  /// [glyph]'s clip box (`COLR` version 1's ClipList), if it has one.
  ColorBox? clipBoxOf(int glyph) => _safe(() {
    final colr = _colr;
    if (colr == null || colr.u16(0) < 1 || colr.length < 34) return null;
    final list = colr.u32(22);
    if (list == 0) return null;
    final count = colr.u32(list + 1);
    for (var i = 0; i < count; i++) {
      final record = list + 5 + 7 * i;
      if (glyph < colr.u16(record) || glyph > colr.u16(record + 2)) continue;
      final box = list + colr.u24(record + 4);
      return (
        xMin: colr.i16(box + 1),
        yMin: colr.i16(box + 3),
        xMax: colr.i16(box + 5),
        yMax: colr.i16(box + 7),
      );
    }
    return null;
  }, null);

  // COLR version 1.

  late final Map<int, int> _basePaintOffsets = _safe(() {
    final colr = _colr;
    if (colr == null || colr.u16(0) < 1 || colr.length < 34) {
      return const <int, int>{};
    }
    final list = colr.u32(14);
    if (list == 0) return const <int, int>{};
    return {
      for (var i = 0; i < colr.u32(list); i++)
        colr.u16(list + 4 + 6 * i): list + colr.u32(list + 6 + 6 * i),
    };
  }, const <int, int>{});

  final Map<int, _Paint> _paints = {};

  _Paint? _basePaint(int glyph) => switch (_basePaintOffsets[glyph]) {
    final at? => _paintAt(at),
    null => null,
  };

  _Paint _layer(int index) => _safe(() {
    final colr = _colr!;
    final list = colr.u32(18);
    if (list == 0 || index >= colr.u32(list)) return const _Nothing();
    return _paintAt(list + colr.u32(list + 4 + 4 * index));
  }, const _Nothing());

  _Paint _paintAt(int at, [int depth = 0]) =>
      _paints[at] ??= _safe(() => _readPaint(at, depth), const _Nothing());

  _Paint _readPaint(int at, int depth) {
    if (depth > 64) return const _Nothing();
    final c = _colr!;
    _Paint child(int offsetAt) => _paintAt(at + c.u24(offsetAt), depth + 1);
    ColorTransform matrix(double xx, double yx, double xy, double yy) =>
        (xx: xx, yx: yx, xy: xy, yy: yy, dx: 0.0, dy: 0.0);
    final format = c.u8(at);
    // (The variable formats, one more than each, read as their default
    // instance: the deltas aren't applied.)
    switch (format) {
      case 1:
        return _Layers(c.u32(at + 2), c.u8(at + 1));
      case 2 || 3:
        return _Solid(c.u16(at + 1), c.f2dot14(at + 3));
      case 4 || 5:
        return _Linear(
          _line(at + c.u24(at + 1), variable: format == 5),
          c.i16(at + 4).toDouble(),
          c.i16(at + 6).toDouble(),
          c.i16(at + 8).toDouble(),
          c.i16(at + 10).toDouble(),
          c.i16(at + 12).toDouble(),
          c.i16(at + 14).toDouble(),
        );
      case 6 || 7:
        return _Radial(
          _line(at + c.u24(at + 1), variable: format == 7),
          c.i16(at + 4).toDouble(),
          c.i16(at + 6).toDouble(),
          c.u16(at + 8).toDouble(),
          c.i16(at + 10).toDouble(),
          c.i16(at + 12).toDouble(),
          c.u16(at + 14).toDouble(),
        );
      case 8 || 9:
        // (HarfBuzz's angles: 180° per unit, from 180°.)
        return _Sweep(
          _line(at + c.u24(at + 1), variable: format == 9),
          c.i16(at + 4).toDouble(),
          c.i16(at + 6).toDouble(),
          (c.f2dot14(at + 8) + 1) * math.pi,
          (c.f2dot14(at + 10) + 1) * math.pi,
        );
      case 10:
        return _Glyph(c.u16(at + 4), child(at + 1));
      case 11:
        return _ColorGlyph(c.u16(at + 1));
      case 12 || 13:
        final t = at + c.u24(at + 4);
        return _Transformed((
          xx: c.fixed(t),
          yx: c.fixed(t + 4),
          xy: c.fixed(t + 8),
          yy: c.fixed(t + 12),
          dx: c.fixed(t + 16),
          dy: c.fixed(t + 20),
        ), child(at + 1));
      case 14 || 15:
        return _Transformed((
          xx: 1,
          yx: 0,
          xy: 0,
          yy: 1,
          dx: c.i16(at + 4).toDouble(),
          dy: c.i16(at + 6).toDouble(),
        ), child(at + 1));
      case 16 || 17:
        return _Transformed(
          matrix(c.f2dot14(at + 4), 0, 0, c.f2dot14(at + 6)),
          child(at + 1),
        );
      case 18 || 19:
        return _Transformed(
          _aroundCenter(
            c.f2dot14(at + 4),
            c.f2dot14(at + 6),
            c.i16(at + 8).toDouble(),
            c.i16(at + 10).toDouble(),
          ),
          child(at + 1),
        );
      case 20 || 21:
        final s = c.f2dot14(at + 4);
        return _Transformed(matrix(s, 0, 0, s), child(at + 1));
      case 22 || 23:
        final s = c.f2dot14(at + 4);
        return _Transformed(
          _aroundCenter(
            s,
            s,
            c.i16(at + 6).toDouble(),
            c.i16(at + 8).toDouble(),
          ),
          child(at + 1),
        );
      case 24 || 25:
        return _Transformed(
          _rotation(c.f2dot14(at + 4) * math.pi, 0, 0),
          child(at + 1),
        );
      case 26 || 27:
        return _Transformed(
          _rotation(
            c.f2dot14(at + 4) * math.pi,
            c.i16(at + 6).toDouble(),
            c.i16(at + 8).toDouble(),
          ),
          child(at + 1),
        );
      case 28 || 29:
        return _Transformed(
          _skewing(-c.f2dot14(at + 4) * math.pi, c.f2dot14(at + 6) * math.pi),
          child(at + 1),
        );
      case 30 || 31:
        return _Transformed(
          _skewing(
            -c.f2dot14(at + 4) * math.pi,
            c.f2dot14(at + 6) * math.pi,
            c.i16(at + 8).toDouble(),
            c.i16(at + 10).toDouble(),
          ),
          child(at + 1),
        );
      case 32:
        final mode = c.u8(at + 4);
        return _Composite(
          child(at + 1),
          mode < CompositeMode.values.length
              ? CompositeMode.values[mode]
              : CompositeMode.clear,
          child(at + 5),
        );
      default:
        return const _Nothing();
    }
  }

  _RawLine _line(int at, {required bool variable}) {
    final c = _colr!;
    final extend = switch (c.u8(at)) {
      1 => ColorExtend.repeat,
      2 => ColorExtend.reflect,
      _ => ColorExtend.pad,
    };
    final size = variable ? 10 : 6;
    return _RawLine(extend, [
      for (var i = 0; i < c.u16(at + 1); i++)
        (
          c.f2dot14(at + 3 + size * i),
          c.u16(at + 5 + size * i),
          c.f2dot14(at + 7 + size * i),
        ),
    ]);
  }

  static ColorTransform _aroundCenter(
    double sx,
    double sy,
    double cx,
    double cy,
  ) => (
    xx: sx,
    yx: 0,
    xy: 0,
    yy: sy,
    dx: cx != 0 ? (1 - sx) * cx : 0,
    dy: cy != 0 ? (1 - sy) * cy : 0,
  );

  static ColorTransform _rotation(double radians, double cx, double cy) {
    final c = math.cos(radians);
    final s = math.sin(radians);
    return (
      xx: c,
      yx: s,
      xy: -s,
      yy: c,
      dx: (1 - c) * cx + s * cy,
      dy: -s * cx + (1 - c) * cy,
    );
  }

  static ColorTransform _skewing(
    double skewX,
    double skewY, [
    double cx = 0,
    double cy = 0,
  ]) {
    final x = skewX != 0 ? math.tan(skewX) : 0.0;
    final y = skewY != 0 ? math.tan(skewY) : 0.0;
    return (
      xx: 1,
      yx: y,
      xy: x,
      yy: 1,
      dx: cy != 0 ? -x * cy : 0,
      dy: cx != 0 ? -y * cx : 0,
    );
  }

  // COLR version 0.

  /// [glyph]'s layers (`COLR` version 0): each glyph and its palette
  /// index, bottom first.
  List<(int, int)>? _layersOf(int glyph) => _safe(() {
    final colr = _colr;
    if (colr == null) return null;
    final count = colr.u16(2);
    final records = colr.u32(4);
    final layers = colr.u32(8);
    // (The base glyph records are sorted by glyph: searched by halves.)
    var low = 0;
    var high = count - 1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      final record = records + 6 * mid;
      final id = colr.u16(record);
      if (id < glyph) {
        low = mid + 1;
      } else if (id > glyph) {
        high = mid - 1;
      } else {
        final first = colr.u16(record + 2);
        return [
          for (var i = 0; i < colr.u16(record + 4); i++)
            (
              colr.u16(layers + 4 * (first + i)),
              colr.u16(layers + 4 * (first + i) + 2),
            ),
        ];
      }
    }
    return null;
  }, null);

  // Bitmaps.

  BitmapGlyph? _bitmap(int glyph, {int? ppem}) =>
      _safe(() => _cbdtBitmap(glyph, ppem), null) ??
      _safe(() => _sbixBitmap(glyph, ppem), null);

  /// The strike of [sizes] HarfBuzz chooses for [ppem]: the smallest not
  /// under it, else the largest.
  static int _choose(List<int> sizes, int? ppem) {
    final requested = ppem == null || ppem == 0 ? 1 << 30 : ppem;
    var best = 0;
    for (var i = 1; i < sizes.length; i++) {
      final size = sizes[i];
      if ((requested <= size && size < sizes[best]) ||
          (requested > sizes[best] && size > sizes[best])) {
        best = i;
      }
    }
    return best;
  }

  BitmapGlyph? _cbdtBitmap(int glyph, int? ppem) {
    final cblc = _cblc;
    final cbdt = _cbdt;
    if (cblc == null || cbdt == null) return null;
    final count = cblc.u32(4);
    if (count == 0) return null;
    final strike =
        8 +
        48 *
            _choose([
              for (var i = 0; i < count; i++)
                math.max(cblc.u8(8 + 48 * i + 44), cblc.u8(8 + 48 * i + 45)),
            ], ppem);
    final ppemX = cblc.u8(strike + 44);
    final ppemY = cblc.u8(strike + 45);
    if (ppemX == 0 || ppemY == 0) return null;
    final array = cblc.u32(strike);
    final tables = cblc.u32(strike + 8);
    for (var i = 0; i < tables; i++) {
      final record = array + 8 * i;
      final first = cblc.u16(record);
      final last = cblc.u16(record + 2);
      if (glyph < first || glyph > last) continue;
      final sub = array + cblc.u32(record + 4);
      final indexFormat = cblc.u16(sub);
      final imageFormat = cblc.u16(sub + 2);
      final imageData = cblc.u32(sub + 4);
      final index = glyph - first;
      // The image's offset and length in CBDT, and the metrics an index
      // of constant metrics gives (formats 2 and 5).
      int? offset;
      var length = 0;
      int? sharedMetrics;
      switch (indexFormat) {
        case 1:
          offset = imageData + cblc.u32(sub + 8 + 4 * index);
          length = imageData + cblc.u32(sub + 12 + 4 * index) - offset;
        case 3:
          offset = imageData + cblc.u16(sub + 8 + 2 * index);
          length = imageData + cblc.u16(sub + 10 + 2 * index) - offset;
        case 2:
          final size = cblc.u32(sub + 8);
          offset = imageData + size * index;
          length = size;
          sharedMetrics = sub + 12;
        case 4:
          final n = cblc.u32(sub + 8);
          for (var k = 0; k < n; k++) {
            final pair = sub + 12 + 4 * k;
            if (cblc.u16(pair) == glyph) {
              offset = imageData + cblc.u16(pair + 2);
              length = imageData + cblc.u16(pair + 6) - offset;
              break;
            }
          }
        case 5:
          final size = cblc.u32(sub + 8);
          sharedMetrics = sub + 12;
          final n = cblc.u32(sub + 20);
          for (var k = 0; k < n; k++) {
            if (cblc.u16(sub + 24 + 2 * k) == glyph) {
              offset = imageData + size * k;
              length = size;
              break;
            }
          }
      }
      if (offset == null || length <= 0) return null;
      // (height, width, bearingX, bearingY) of small or big metrics.
      (int, int, int, int) metrics(_Bytes bytes, int at) =>
          (bytes.u8(at), bytes.u8(at + 1), bytes.i8(at + 2), bytes.i8(at + 3));
      final (Uint8List png, (int, int, int, int) m) = switch (imageFormat) {
        17 => (
          _slice(cbdt, offset + 9, cbdt.u32(offset + 5)),
          metrics(cbdt, offset),
        ),
        18 => (
          _slice(cbdt, offset + 12, cbdt.u32(offset + 8)),
          metrics(cbdt, offset),
        ),
        19 when sharedMetrics != null => (
          _slice(cbdt, offset + 4, cbdt.u32(offset)),
          metrics(cblc, sharedMetrics),
        ),
        _ => (Uint8List(0), (0, 0, 0, 0)),
      };
      if (png.isEmpty) return null;
      final (height, width, bearingX, bearingY) = m;
      final xScale = font.unitsPerEm / ppemX;
      final yScale = font.unitsPerEm / ppemY;
      return BitmapGlyph(
        png,
        pixelWidth: width,
        pixelHeight: height,
        left: _roundf(bearingX * xScale),
        top: _roundf(bearingY * yScale),
        width: _roundf(width * xScale),
        height: _roundf(height * yScale),
      );
    }
    return null;
  }

  BitmapGlyph? _sbixBitmap(int glyph, int? ppem) {
    final sbix = _sbix;
    if (sbix == null || glyph >= font.numGlyphs) return null;
    final count = sbix.u32(4);
    if (count == 0) return null;
    final strikes = [for (var i = 0; i < count; i++) sbix.u32(8 + 4 * i)];
    final strike =
        strikes[_choose([for (final s in strikes) sbix.u16(s)], ppem)];
    final strikePpem = sbix.u16(strike);
    var id = glyph;
    // (A 'dupe' glyph is another glyph's image; followed a few times.)
    for (var hops = 0; hops < 8; hops++) {
      final start = strike + sbix.u32(strike + 4 + 4 * id);
      final end = strike + sbix.u32(strike + 8 + 4 * id);
      if (end - start < 8) return null;
      final type = String.fromCharCodes([
        for (var k = 0; k < 4; k++) sbix.u8(start + 4 + k),
      ]);
      if (type == 'dupe') {
        id = sbix.u16(start + 8);
        continue;
      }
      if (type != 'png ') return null;
      final png = _slice(sbix, start + 8, end - start - 8);
      if (png.length < 24) return null;
      final view = ByteData.sublistView(png);
      final pixelWidth = view.getUint32(16);
      final pixelHeight = view.getUint32(20);
      if (pixelWidth >= 65536 || pixelHeight >= 65536) return null;
      final x = sbix.i16(start);
      final y = sbix.i16(start + 2);
      final scale = strikePpem == 0 ? 1.0 : font.unitsPerEm / strikePpem;
      return BitmapGlyph(
        png,
        pixelWidth: pixelWidth,
        pixelHeight: pixelHeight,
        left: _roundf(x * scale),
        top: _roundf((pixelHeight + y) * scale),
        width: _roundf(pixelWidth * scale),
        height: _roundf(pixelHeight * scale),
      );
    }
    return null;
  }

  static Uint8List _slice(_Bytes bytes, int at, int length) =>
      Uint8List.sublistView(bytes.data, at, at + length);

  /// C's `roundf`: halves away from zero.
  static int _roundf(double v) =>
      v < 0 ? -(-v + 0.5).floor() : (v + 0.5).floor();

  /// What [read] gives; [otherwise] where the table can't be read (data
  /// past its end).
  static T _safe<T>(T Function() read, T otherwise) {
    try {
      return read();
      // RangeError on the VM; JavaScript's RangeError arrives as an
      // ArgumentError.
      // ignore: avoid_catching_errors
    } on ArgumentError {
      return otherwise;
    }
  }
}

/// A walk through a glyph's paint.
final class _Context {
  new(this.glyphs, this.painter, this.palette, this.foreground);

  final ColorGlyphs glyphs;
  final ColorPainter painter;
  final int palette;
  final PaletteColor foreground;

  /// The color glyphs being painted, which a glyph's paint may not
  /// reach again (HarfBuzz's decycler).
  final Set<int> colorGlyphs = {};
  int _depth = 0;

  /// The color of palette entry [index] (0xFFFF: the text's), its alpha
  /// times [alpha] (HarfBuzz's `get_color`).
  PaintColor color(int index, double alpha) {
    final palettes = glyphs.palettes;
    final foreground = index == 0xffff;
    final base = foreground
        ? this.foreground
        : palette < palettes.length && index < palettes[palette].length
        ? palettes[palette][index]
        : this.foreground;
    return PaintColor(
      PaletteColor(
        base.red,
        base.green,
        base.blue,
        ColorGlyphs._roundf(base.alpha * alpha.clamp(0, 1)),
      ),
      foreground: foreground,
    );
  }

  ColorLine line(_RawLine raw) => ColorLine(raw.extend, [
    for (final (offset, index, alpha) in raw.stops)
      (offset, color(index, alpha)),
  ]);

  void recurse(_Paint paint) {
    // (HarfBuzz's nesting limit.)
    if (_depth >= 64) return;
    _depth++;
    _paint(paint);
    _depth--;
  }

  void _paint(_Paint paint) {
    switch (paint) {
      case _Layers(:final first, :final count):
        for (var i = first; i < first + count; i++) {
          recurse(glyphs._layer(i));
        }
      case _Solid(:final paletteIndex, :final alpha):
        painter.solid(color(paletteIndex, alpha));
      case _Linear(
        line: final raw,
        :final x0,
        :final y0,
        :final x1,
        :final y1,
        :final x2,
        :final y2,
      ):
        painter.linearGradient(line(raw), x0, y0, x1, y1, x2, y2);
      case _Radial(
        line: final raw,
        :final x0,
        :final y0,
        :final r0,
        :final x1,
        :final y1,
        :final r1,
      ):
        painter.radialGradient(line(raw), x0, y0, r0, x1, y1, r1);
      case _Sweep(
        line: final raw,
        :final x,
        :final y,
        :final start,
        :final end,
      ):
        painter.sweepGradient(line(raw), x, y, start, end);
      case _Glyph(
        :final glyph,
        paint: _Solid(:final paletteIndex, :final alpha),
      ):
        // (A glyph filled with one color, as HarfBuzz optimizes it.)
        painter.fillGlyph(glyph, color(paletteIndex, alpha));
      case _Glyph(:final glyph, paint: final inner):
        painter.clipGlyph(glyph, () => recurse(inner));
      case _ColorGlyph(:final glyph):
        if (!colorGlyphs.add(glyph)) return;
        final inner = glyphs._basePaint(glyph);
        void draw() {
          if (inner != null) recurse(inner);
        }

        switch (glyphs.clipBoxOf(glyph)) {
          case final box?:
            painter.clipBox(box, draw);
          case null:
            draw();
        }
        colorGlyphs.remove(glyph);
      case _Transformed(:final transform, paint: final inner):
        painter.transform(transform, () => recurse(inner));
      case _Composite(:final source, :final mode, :final backdrop):
        painter.composite(mode, () => recurse(backdrop), () => recurse(source));
      case _Nothing():
        break;
    }
  }
}
