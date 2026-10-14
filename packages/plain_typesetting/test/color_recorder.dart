/// The operations a color glyph's paint gives, written as the native
/// oracle's --paint writes HarfBuzz's (tool/oracles/harfbuzz-native).
library;

import 'dart:typed_data';

import 'package:plain_fonts/plain_fonts.dart';

/// The operations a glyph's paint gives, written as the oracle writes
/// them ([ops]).
final class PaintRecorder implements ColorPainter {
  final List<String> ops = [];

  /// [v] to two decimals as C's printf writes HarfBuzz's single
  /// precision numbers: an exact half to the even digit.
  static String _n(double v) {
    final scaled = (Float32List(1)..[0] = v)[0] * 100;
    final floor = scaled.floorToDouble();
    final rounded = scaled - floor == 0.5
        ? (floor % 2 == 0 ? floor : floor + 1)
        : scaled.roundToDouble();
    final s = (rounded / 100).toStringAsFixed(2);
    return s == '-0.00' ? '0.00' : s;
  }

  static String _color(PaintColor c) => '${c.foreground ? 1 : 0}:${c.color}';

  static String _line(ColorLine line) {
    final stops = [
      for (final (offset, color) in line.stops)
        '${_n(offset)}/${_color(color)}',
    ];
    return '${line.extend.index} [${stops.join(',')}]';
  }

  @override
  void transform(ColorTransform t, void Function() paint) {
    final identity =
        t.xx == 1 &&
        t.yx == 0 &&
        t.xy == 0 &&
        t.yy == 1 &&
        t.dx == 0 &&
        t.dy == 0;
    if (!identity) {
      ops.add('T ${[t.xx, t.yx, t.xy, t.yy, t.dx, t.dy].map(_n).join(' ')}');
    }
    paint();
    if (!identity) ops.add('t');
  }

  @override
  void clipGlyph(int glyph, void Function() paint) {
    ops.add('CG $glyph');
    paint();
    ops.add('c');
  }

  @override
  void clipBox(ColorBox box, void Function() paint) {
    final edges = [box.xMin, box.yMin, box.xMax, box.yMax];
    ops.add('CR ${edges.map((v) => _n(v.toDouble())).join(' ')}');
    paint();
    ops.add('c');
  }

  @override
  void fillGlyph(int glyph, PaintColor color) =>
      ops.add('F $glyph ${_color(color)}');

  @override
  void solid(PaintColor color) => ops.add('S ${_color(color)}');

  @override
  void linearGradient(
    ColorLine line,
    double x0,
    double y0,
    double x1,
    double y1,
    double x2,
    double y2,
  ) =>
      ops.add('L ${_line(line)} ${[x0, y0, x1, y1, x2, y2].map(_n).join(' ')}');

  @override
  void radialGradient(
    ColorLine line,
    double x0,
    double y0,
    double r0,
    double x1,
    double y1,
    double r1,
  ) =>
      ops.add('R ${_line(line)} ${[x0, y0, r0, x1, y1, r1].map(_n).join(' ')}');

  @override
  void sweepGradient(
    ColorLine line,
    double x,
    double y,
    double startAngle,
    double endAngle,
  ) => ops.add(
    'W ${_line(line)} ${[x, y, startAngle, endAngle].map(_n).join(' ')}',
  );

  @override
  void composite(
    CompositeMode mode,
    void Function() backdrop,
    void Function() source,
  ) {
    ops.add('G');
    backdrop();
    ops.add('G');
    source();
    ops
      ..add('g ${mode.index}')
      ..add('g ${CompositeMode.srcOver.index}');
  }

  @override
  void image(BitmapGlyph bitmap) => ops.add(
    'I ${bitmap.pixelWidth} ${bitmap.pixelHeight} png  ${bitmap.left} '
    '${bitmap.top} ${bitmap.width} ${-bitmap.height} ${bitmap.png.length}',
  );
}

/// What [glyph] of [colors] paints, as the oracle writes it (`-` for a
/// glyph that isn't a color glyph).
String recordPaint(ColorGlyphs colors, int glyph, {int palette = 0}) {
  final recorder = PaintRecorder();
  return colors.paint(glyph, recorder, palette: palette)
      ? recorder.ops.join(' | ')
      : '-';
}
