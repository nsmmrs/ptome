// Compiled to JavaScript in CI: reads an SVG that uses most of what is
// drawn (entities, CSS, gradients, clip paths, groups, text, transforms,
// arcs) and draws it on a canvas that writes down every call, printing a
// digest; the CI job compares it with the Dart VM's, as the results must
// be the same on both.
import 'dart:convert';

import 'package:plain_svg/plain_svg.dart';
import 'package:plain_typesetting/plain_typesetting.dart';

const String _svg = '''
<?xml version="1.0"?>
<!DOCTYPE svg [<!ENTITY accent "fill:#c33;stroke:navy">]>
<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"
     viewBox="0 0 200 120" width="10cm" height="6cm" font-family="Mono">
  <style>.box { stroke-width: 2.5; } g > .dot { fill: rgb(10%, 60%, 30%) }</style>
  <defs>
    <linearGradient id="fade" x1="0" x2="1" gradientTransform="rotate(30)">
      <stop offset="0" stop-color="gold"/>
      <stop offset="60%" stop-color="#36f" stop-opacity="0.4"/>
    </linearGradient>
    <radialGradient id="glow" fx="30%" fy="30%" r="0.7">
      <stop offset="0" stop-color="white"/><stop offset="1" stop-color="teal"/>
    </radialGradient>
    <clipPath id="clip"><circle cx="60" cy="60" r="40"/></clipPath>
    <symbol id="star" viewBox="0 0 10 10"><path d="M5 0L6 4 10 4 7 6 8 10 5 7 2 10 3 6 0 4 4 4z"/></symbol>
  </defs>
  <rect class="box" x="5" y="5" width="190" height="110" rx="8" style="&accent;"/>
  <g transform="translate(10 10) scale(0.9) skewX(5)" opacity="0.7">
    <ellipse cx="60" cy="60" rx="50" ry="30" fill="url(#fade)" clip-path="url(#clip)"/>
    <circle class="dot" cx="140" cy="40" r="12"/>
    <path d="M20 100 a30 20 15 1 0 60 0 q 20 -30 40 0 t 40 0" fill="none"
          stroke="url(#glow)" stroke-dasharray="4 2" stroke-linecap="round"/>
  </g>
  <use xlink:href="#star" x="150" y="70" width="30" height="30" fill="purple"/>
  <text x="100" y="112" text-anchor="middle" font-size="9">Straße ΣΟΦΟΣ 日本語<tspan dy="-2" font-weight="bold">!</tspan></text>
</svg>''';

/// A font whose every character is 0.6 em wide.
final class _Font implements Font {
  @override
  String get name => 'Mono';
  @override
  double get ascender => 800;
  @override
  double get descender => -200;
  @override
  double get lineGap => 0;
  @override
  double get capHeight => 700;
  @override
  double get xHeight => 500;
  @override
  double get underlinePosition => -100;
  @override
  double get underlineThickness => 50;
  @override
  bool covers(int codePoint) => true;
  @override
  List<ShapedGlyph> shape(
    String text, {
    bool kerning = true,
    bool ligatures = false,
    Set<String> features = const {},
    bool rightToLeft = false,
  }) => [
    for (final c in text.runes) ShapedGlyph(c, String.fromCharCode(c), 600),
  ];
  @override
  double widthOf(String text, double size, {bool kerning = true}) =>
      text.runes.length * size * 0.6;
}

/// A canvas writing down each call, numbers to three decimals.
final class _Recorder implements SvgCanvas {
  final StringBuffer out = StringBuffer();

  void _call(String name, [List<Object?> arguments = const []]) {
    String format(Object? value) => switch (value) {
      final double d => d.toStringAsFixed(3),
      final Rect r => [
        r.left,
        r.bottom,
        r.width,
        r.height,
      ].map(format).join(' '),
      final Matrix m => [m.a, m.b, m.c, m.d, m.e, m.f].map(format).join(' '),
      final RgbColor c => [c.red, c.green, c.blue].map(format).join(' '),
      final GrayColor c => format(c.level),
      final List<Object?> l => l.map(format).join(' '),
      _ => '$value',
    };
    out.writeln('$name ${arguments.map(format).join(', ')}');
  }

  @override
  void save() => _call('save');
  @override
  void restore() => _call('restore');
  @override
  void saved(void Function() draw) {
    save();
    draw();
    restore();
  }

  @override
  void transform(Matrix matrix) => _call('transform', [matrix]);
  @override
  void translate(double x, double y) => _call('translate', [x, y]);
  @override
  void scale(double x, [double? y]) => _call('scale', [x, y]);
  @override
  void rotate(double degrees) => _call('rotate', [degrees]);
  @override
  void setLineWidth(double width) => _call('lineWidth', [width]);
  @override
  void setLineCap(LineCap cap) => _call('lineCap', [cap.name]);
  @override
  void setLineJoin(LineJoin join) => _call('lineJoin', [join.name]);
  @override
  void setMiterLimit(double limit) => _call('miterLimit', [limit]);
  @override
  void dash(List<double> pattern, [double phase = 0]) =>
      _call('dash', [pattern, phase]);
  @override
  void setFillColor(Color color) => _call('fillColor', [color]);
  @override
  void setStrokeColor(Color color) => _call('strokeColor', [color]);
  @override
  void opacity({double? fill, double? stroke}) =>
      _call('opacity', [fill, stroke]);
  @override
  void setBlendMode(BlendMode mode) => _call('blend', [mode.name]);
  @override
  void moveTo(double x, double y) => _call('m', [x, y]);
  @override
  void lineTo(double x, double y) => _call('l', [x, y]);
  @override
  void curveTo(
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
  ) => _call('c', [x1, y1, x2, y2, x3, y3]);
  @override
  void closePath() => _call('h');
  @override
  void rect(Rect rect) => _call('re', [rect]);
  @override
  void roundedRect(Rect rect, double radius) =>
      _call('roundedRect', [rect, radius]);
  @override
  void ellipse(double cx, double cy, double rx, double ry) =>
      _call('ellipse', [cx, cy, rx, ry]);
  @override
  void circle(double cx, double cy, double radius) =>
      _call('circle', [cx, cy, radius]);
  @override
  void fill({bool evenOdd = false}) => _call('fill', [evenOdd]);
  @override
  void stroke() => _call('stroke');
  @override
  void fillAndStroke({bool evenOdd = false}) =>
      _call('fillAndStroke', [evenOdd]);
  @override
  void clip({bool evenOdd = false}) => _call('clip', [evenOdd]);
  @override
  void endPath() => _call('n');
  @override
  void beginMarkedContent(String tag, {String? actualText}) =>
      _call('bmc', [tag, actualText]);
  @override
  void endMarkedContent() => _call('emc');
  @override
  double text(String text, double x, double y, TextStyle style) {
    _call('text', [text, x, y, style.size, style.renderMode.name]);
    return style.measure(text);
  }

  @override
  double glyphs(
    List<ShapedGlyph> glyphs,
    double x,
    double y,
    TextStyle style, {
    String? text,
  }) {
    _call('glyphs', [glyphs.length, x, y]);
    return style.widthOf(glyphs);
  }

  @override
  void group(Rect bounds, void Function(SvgCanvas canvas) draw) {
    _call('group {', [bounds]);
    draw(this);
    _call('}');
  }

  @override
  void gradient(Gradient gradient) => _call('gradient', [
    switch (gradient) {
      LinearGradient(:final x1, :final y1, :final x2, :final y2) => [
        x1,
        y1,
        x2,
        y2,
      ],
      RadialGradient(:final fx, :final fy, :final cx, :final cy, :final r) => [
        fx,
        fy,
        cx,
        cy,
        r,
      ],
    },
    [for (final stop in gradient.stops) stop.offset],
    [for (final stop in gradient.stops) stop.color],
  ]);

  @override
  void luminosityMask(Rect bounds, void Function(SvgCanvas canvas) draw) {
    _call('mask {', [bounds]);
    draw(this);
    _call('}');
  }
}

void main() {
  final svg = SvgImage.parse(
    _svg,
    fonts: (family, {required bold, required italic}) => _Font(),
  );
  final canvas = _Recorder();
  svg.paint(canvas, Rect(20, 30, svg.width, svg.height));
  final drawn = '${canvas.out}${svg.warnings.join('\n')}';
  // An Adler-32 style checksum: its sums stay small enough for
  // JavaScript's numbers.
  var a = 1;
  var b = 0;
  for (final byte in utf8.encode(drawn)) {
    a = (a + byte) % 65521;
    b = (b + a) % 65521;
  }
  // The digest is the program's output.
  // ignore: avoid_print
  print('${drawn.length} $b-$a');
}
