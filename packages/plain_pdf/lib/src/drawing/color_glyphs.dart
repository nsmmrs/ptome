part of 'canvas.dart';

// Color glyphs (`COLR`/`CPAL`, `CBDT`, `sbix`): each drawn once as a form
// in font units, as HarfBuzz paints it (plain_fonts' ColorGlyphs), and
// placed wherever the glyph is set, marked as reading as its text.

/// The forms of each font's color glyphs drawn so far, by glyph and the
/// text's color.
final Expando<Map<(int, Color), PdfForm>> _colorForms = Expando();

/// Whether each glyph of a font is a color glyph, as looked up so far.
final Expando<Map<int, bool>> _isColorGlyph = Expando();

/// The color glyphs of [style]'s font, where it has any.
ColorGlyphs? _colorGlyphsOf(TextStyle style) => switch (style.font) {
  final OpenTypeTextFont font => font.font.colorGlyphs,
  _ => null,
};

bool _isColor(ColorGlyphs colors, int glyph) =>
    (_isColorGlyph[colors] ??= {})[glyph] ??= colors.hasGlyph(glyph);

/// How far the paint of a gradient or a color reaches around a glyph, in
/// ems: past the clip it is cut to.
const double _reach = 4;

/// A [ColorPainter] drawing on a PDF canvas, in font units: outlines of
/// the font's glyphs as text (filled, or the clip), colors and gradients
/// as fills and shadings, composites as transparency groups and soft
/// masks, bitmaps as images.
final class _PdfColorPainter implements ColorPainter {
  new(this.canvas, this.style, this.foreground, this.unitsPerEm);

  /// The canvas drawn on now (a group's, inside one).
  PdfCanvas canvas;

  /// The text's style: its font draws the outlines.
  final TextStyle style;

  /// The text's color, which a glyph's foreground color stands for.
  final Color foreground;

  /// The font's units per em.
  final int unitsPerEm;

  double get _far => _reach * unitsPerEm;

  /// The area a group or a mask covers.
  Rect get _area => Rect(-_far, -_far, 2 * _far, 2 * _far);

  (Color, double) _color(PaintColor color) => (
    color.foreground
        ? foreground
        : RgbColor(
            color.color.red / 255,
            color.color.green / 255,
            color.color.blue / 255,
          ),
    color.color.alpha / 255,
  );

  /// [color] as RGB, as shadings need their stops alike.
  static RgbColor _rgb(Color color) => switch (color) {
    final RgbColor rgb => rgb,
    GrayColor(:final level) => RgbColor(level, level, level),
    CmykColor(:final cyan, :final magenta, :final yellow, :final black) =>
      RgbColor(
        (1 - cyan) * (1 - black),
        (1 - magenta) * (1 - black),
        (1 - yellow) * (1 - black),
      ),
    SpotColor(:final alternate, :final tint) => _rgb(
      CmykColor(
        alternate.cyan * tint,
        alternate.magenta * tint,
        alternate.yellow * tint,
        alternate.black * tint,
      ),
    ),
  };

  /// Draws [glyph]'s outline as text: filled, or added to the clip.
  void _outline(int glyph, TextRenderMode mode) {
    final font = style.font;
    if (font is! EmbeddedFont ||
        (!font.font.isTrueType && !font.font.hasTable('CFF '))) {
      return;
    }
    canvas._glyphs(
      [ShapedGlyph(glyph, '', font.font.advance(glyph) * 1000 / unitsPerEm)],
      0,
      0,
      TextStyle(font, unitsPerEm.toDouble(), renderMode: mode),
    );
  }

  void _fill(Color color, double alpha, void Function() paint) {
    canvas.saved(() {
      canvas.setFillColor(color);
      if (alpha < 1) canvas.opacity(fill: alpha);
      paint();
    });
  }

  @override
  void transform(ColorTransform t, void Function() paint) {
    canvas.saved(() {
      canvas.transform(Matrix(t.xx, t.yx, t.xy, t.yy, t.dx, t.dy));
      paint();
    });
  }

  @override
  void clipGlyph(int glyph, void Function() paint) {
    canvas.saved(() {
      _outline(glyph, TextRenderMode.clip);
      paint();
    });
  }

  @override
  void clipBox(ColorBox box, void Function() paint) {
    canvas.saved(() {
      canvas
        ..rect(
          Rect.fromEdges(
            box.xMin.toDouble(),
            box.yMin.toDouble(),
            box.xMax.toDouble(),
            box.yMax.toDouble(),
          ),
        )
        ..clip();
      paint();
    });
  }

  @override
  void fillGlyph(int glyph, PaintColor color) {
    final (c, alpha) = _color(color);
    if (alpha == 0) return;
    _fill(c, alpha, () => _outline(glyph, TextRenderMode.fill));
  }

  @override
  void solid(PaintColor color) {
    final (c, alpha) = _color(color);
    if (alpha == 0) return;
    _fill(c, alpha, () {
      canvas
        ..rect(_area)
        ..fill();
    });
  }

  /// The stops of [line] normalized to offsets 0 to 1 (with the offsets
  /// they had at 0 and 1), repeated or reflected over the parameter range
  /// [from] to [to] (in the normalized offsets) by its extend mode, else
  /// as they are; null where they span nothing.
  List<(double, PaintColor)>? _stops(
    ColorLine line, {
    double from = 0,
    double to = 1,
  }) {
    final sorted = [...line.stops]..sort((a, b) => a.$1.compareTo(b.$1));
    if (sorted.isEmpty) return null;
    if (line.extend == ColorExtend.pad || to - from <= 0) return sorted;
    final out = <(double, PaintColor)>[];
    // (One period at a time, at most 256 of them.)
    final first = from.floor().clamp(-128, 128);
    final last = to.ceil().clamp(-128, 128);
    for (var period = first; period < last; period++) {
      final backwards = line.extend == ColorExtend.reflect && period.isOdd;
      final stops = backwards
          ? [for (final (o, c) in sorted.reversed) (1 - o, c)]
          : sorted;
      for (final (o, c) in stops) {
        out.add((period + o, c));
      }
    }
    return out;
  }

  /// [stops] at offsets from [from] to [to] as the shading's 0 to 1, in
  /// RGB and alpha.
  List<(double, RgbColor, double)> _shadingStops(
    List<(double, PaintColor)> stops,
    double from,
    double to,
  ) => [
    for (final (offset, color) in stops)
      () {
        final (c, alpha) = _color(color);
        return ((offset - from) / (to - from), _rgb(c), alpha);
      }(),
  ];

  /// Paints the shading [make] makes from the [stops]' colors, its alpha
  /// from a soft mask of the same shading in gray where a stop isn't
  /// opaque.
  void _shade(
    List<(double, RgbColor, double)> stops,
    PdfShading Function(List<GradientStop> stops) make,
  ) {
    canvas.saved(() {
      if (stops.any((s) => s.$3 < 1)) {
        final mask = make([
          for (final (o, _, a) in stops) GradientStop(o, GrayColor(a)),
        ]);
        canvas.softMask(
          PdfForm(
            _area,
            (c) => c.shade(mask),
            group: const TransparencyGroup(),
          ),
        );
      }
      canvas.shade(make([for (final (o, c, _) in stops) GradientStop(o, c)]));
    });
  }

  @override
  void linearGradient(
    ColorLine line,
    double x0,
    double y0,
    double x1,
    double y1,
    double x2,
    double y2,
  ) {
    // (The end of the gradient: p1 projected onto the line through p0
    // across p0–p2, along which the colors stay the same.)
    final nx = -(y2 - y0);
    final ny = x2 - x0;
    final n2 = nx * nx + ny * ny;
    var ex = x1;
    var ey = y1;
    if (n2 != 0) {
      final k = ((x1 - x0) * nx + (y1 - y0) * ny) / n2;
      ex = x0 + k * nx;
      ey = y0 + k * ny;
    }
    final sorted = _stops(line);
    if (sorted == null) return;
    final s0 = sorted.first.$1;
    final s1 = sorted.last.$1;
    if (s1 == s0 || (ex == x0 && ey == y0)) {
      solid(sorted.last.$2);
      return;
    }
    // (The stops' first and last offsets as the axis' ends.)
    double ax(double t) => x0 + t * (ex - x0);
    double ay(double t) => y0 + t * (ey - y0);
    final (px, py) = (ax(s0), ay(s0));
    final (qx, qy) = (ax(s1), ay(s1));
    var from = 0.0;
    var to = 1.0;
    if (line.extend != ColorExtend.pad) {
      // (The area's corners projected on the axis.)
      final dx = qx - px;
      final dy = qy - py;
      final d2 = dx * dx + dy * dy;
      final ts = [
        for (final (cx, cy) in [
          (-_far, -_far),
          (_far, -_far),
          (-_far, _far),
          (_far, _far),
        ])
          ((cx - px) * dx + (cy - py) * dy) / d2,
      ];
      from = ts.reduce(math.min);
      to = ts.reduce(math.max);
    }
    final normalized = ColorLine(line.extend, [
      for (final (o, c) in sorted) ((o - s0) / (s1 - s0), c),
    ]);
    final stops = _stops(normalized, from: from, to: to)!;
    final lo = line.extend == ColorExtend.pad ? 0.0 : stops.first.$1;
    final hi = line.extend == ColorExtend.pad ? 1.0 : stops.last.$1;
    _shade(
      _shadingStops(stops, lo, hi),
      (s) => AxialShading(
        px + lo * (qx - px),
        py + lo * (qy - py),
        px + hi * (qx - px),
        py + hi * (qy - py),
        s,
      ),
    );
  }

  @override
  void radialGradient(
    ColorLine line,
    double x0,
    double y0,
    double r0,
    double x1,
    double y1,
    double r1,
  ) {
    final sorted = _stops(line);
    if (sorted == null) return;
    final s0 = sorted.first.$1;
    final s1 = sorted.last.$1;
    if (s1 == s0) {
      solid(sorted.last.$2);
      return;
    }
    // (The circle at parameter t; the stops' first and last offsets as
    // the shading's two circles.)
    (double, double, double) circle(double t) =>
        (x0 + t * (x1 - x0), y0 + t * (y1 - y0), r0 + t * (r1 - r0));
    final normalized = ColorLine(line.extend, [
      for (final (o, c) in sorted) ((o - s0) / (s1 - s0), c),
    ]);
    var from = 0.0;
    var to = 1.0;
    final (_, _, ra) = circle(s0);
    final (_, _, rb) = circle(s1);
    final dr = rb - ra;
    if (line.extend != ColorExtend.pad && dr != 0) {
      // (As far as the circles grow past the area, not below a radius of
      // nothing.)
      final big = 2 * _far;
      final zero = -ra / dr;
      final large = (big - ra) / dr;
      from = dr > 0 ? zero : large;
      to = dr > 0 ? large : zero;
    }
    // (Repeated or reflected, the stops cut where the circles start from
    // nothing and where they are past the area.)
    final pad = line.extend == ColorExtend.pad || dr == 0;
    final stops = pad
        ? _stops(normalized)!
        : _cut(_stops(normalized, from: from, to: to)!, from, to);
    final lo = pad ? 0.0 : from;
    final hi = pad ? 1.0 : to;
    double at(double u) => s0 + u * (s1 - s0);
    final (ax, ay, ar) = circle(at(lo));
    final (bx, by, br) = circle(at(hi));
    _shade(
      _shadingStops(stops, lo, hi),
      (s) => RadialShading(ax, ay, math.max(0, ar), bx, by, math.max(0, br), s),
    );
  }

  /// [stops] (in order) from [lo] to [hi]: those between, and the colors
  /// at [lo] and [hi] between the stops around them.
  static List<(double, PaintColor)> _cut(
    List<(double, PaintColor)> stops,
    double lo,
    double hi,
  ) => [
    (lo, _colorBetween(stops, lo)),
    for (final stop in stops)
      if (stop.$1 > lo && stop.$1 < hi) stop,
    (hi, _colorBetween(stops, hi)),
  ];

  /// The color at [t] between [stops] (in order): the first's before
  /// them, the last's after.
  static PaintColor _colorBetween(List<(double, PaintColor)> stops, double t) {
    if (t <= stops.first.$1) return stops.first.$2;
    for (var i = 1; i < stops.length; i++) {
      final (o1, c1) = stops[i];
      if (t <= o1) {
        final (o0, c0) = stops[i - 1];
        final k = o1 == o0 ? 1.0 : (t - o0) / (o1 - o0);
        int mix(int a, int b) => (a + k * (b - a)).round();
        return PaintColor(
          PaletteColor(
            mix(c0.color.red, c1.color.red),
            mix(c0.color.green, c1.color.green),
            mix(c0.color.blue, c1.color.blue),
            mix(c0.color.alpha, c1.color.alpha),
          ),
          foreground: c0.foreground && c1.foreground,
        );
      }
    }
    return stops.last.$2;
  }

  @override
  void sweepGradient(
    ColorLine line,
    double x,
    double y,
    double startAngle,
    double endAngle,
  ) {
    final sorted = _stops(line);
    if (sorted == null) return;
    // The color at parameter t: between the stops, else as the extend
    // mode continues them.
    PaintColor colorAt(double t) {
      final s0 = sorted.first.$1;
      final s1 = sorted.last.$1;
      var u = t;
      if (s1 > s0) {
        final span = s1 - s0;
        final v = (t - s0) / span;
        u = switch (line.extend) {
          ColorExtend.pad => t,
          ColorExtend.repeat => s0 + (v - v.floorToDouble()) * span,
          ColorExtend.reflect => () {
            final m = v - 2 * (v / 2).floorToDouble();
            return s0 + (m <= 1 ? m : 2 - m) * span;
          }(),
        };
      }
      return _colorBetween(sorted, u);
    }

    // (Wedges of a degree each, a little wider than that so that no seam
    // shows between them, each in the color at its middle.)
    final span = endAngle - startAngle;
    final radius = 2 * _far;
    const steps = 360;
    for (var i = 0; i < steps; i++) {
      final a0 = 2 * math.pi * i / steps;
      final a1 = 2 * math.pi * (i + 1.5) / steps;
      final middle = 2 * math.pi * (i + 0.5) / steps;
      final t = span == 0
          ? (middle < startAngle ? 0.0 : 1.0)
          : (middle - startAngle) / span;
      final (c, alpha) = _color(colorAt(t));
      if (alpha == 0) continue;
      _fill(c, alpha, () {
        canvas
          ..moveTo(x, y)
          ..lineTo(x + radius * math.cos(a0), y + radius * math.sin(a0))
          ..lineTo(x + radius * math.cos(a1), y + radius * math.sin(a1))
          ..closePath()
          ..fill();
      });
    }
  }

  /// A form with a transparency group of what [paint] draws.
  PdfForm _group(void Function() paint) => PdfForm(_area, (c) {
    final outer = canvas;
    canvas = c;
    paint();
    canvas = outer;
  }, group: const TransparencyGroup(isolated: true));

  @override
  void composite(
    CompositeMode mode,
    void Function() backdrop,
    void Function() source,
  ) {
    final b = _group(backdrop);
    final s = _group(source);
    void masked(PdfForm form, PdfForm mask, {bool invert = false}) {
      canvas.saved(() {
        canvas
          ..softMask(mask, kind: SoftMaskKind.alpha, invert: invert)
          ..form(form);
      });
    }

    // (The two composited in a group of their own, onto nothing else:
    // Porter and Duff's operators by masks of each other's alpha, the
    // blend modes by PDF's.)
    canvas.form(
      _group(() {
        switch (mode) {
          case CompositeMode.clear:
            break;
          case CompositeMode.src:
            canvas.form(s);
          case CompositeMode.dest:
            canvas.form(b);
          case CompositeMode.srcOver || CompositeMode.plus:
            canvas
              ..form(b)
              ..form(s);
          case CompositeMode.destOver:
            canvas
              ..form(s)
              ..form(b);
          case CompositeMode.srcIn:
            masked(s, b);
          case CompositeMode.destIn:
            masked(b, s);
          case CompositeMode.srcOut:
            masked(s, b, invert: true);
          case CompositeMode.destOut:
            masked(b, s, invert: true);
          case CompositeMode.srcAtop:
            canvas.form(b);
            masked(s, b);
          case CompositeMode.destAtop:
            masked(s, b, invert: true);
            masked(b, s);
          case CompositeMode.xor:
            masked(s, b, invert: true);
            masked(b, s, invert: true);
          case CompositeMode.screen ||
              CompositeMode.overlay ||
              CompositeMode.darken ||
              CompositeMode.lighten ||
              CompositeMode.colorDodge ||
              CompositeMode.colorBurn ||
              CompositeMode.hardLight ||
              CompositeMode.softLight ||
              CompositeMode.difference ||
              CompositeMode.exclusion ||
              CompositeMode.multiply ||
              CompositeMode.hue ||
              CompositeMode.saturation ||
              CompositeMode.color ||
              CompositeMode.luminosity:
            canvas.form(b);
            canvas.saved(() {
              canvas
                ..setBlendMode(_blendModes[mode]!)
                ..form(s);
            });
        }
      }),
    );
  }

  static const Map<CompositeMode, BlendMode> _blendModes = {
    CompositeMode.screen: BlendMode.screen,
    CompositeMode.overlay: BlendMode.overlay,
    CompositeMode.darken: BlendMode.darken,
    CompositeMode.lighten: BlendMode.lighten,
    CompositeMode.colorDodge: BlendMode.colorDodge,
    CompositeMode.colorBurn: BlendMode.colorBurn,
    CompositeMode.hardLight: BlendMode.hardLight,
    CompositeMode.softLight: BlendMode.softLight,
    CompositeMode.difference: BlendMode.difference,
    CompositeMode.exclusion: BlendMode.exclusion,
    CompositeMode.multiply: BlendMode.multiply,
    CompositeMode.hue: BlendMode.hue,
    CompositeMode.saturation: BlendMode.saturation,
    CompositeMode.color: BlendMode.color,
    CompositeMode.luminosity: BlendMode.luminosity,
  };

  @override
  void image(BitmapGlyph bitmap) {
    final PdfImage image;
    try {
      image = PdfImage.parse(bitmap.png);
    } on Object {
      return;
    }
    canvas.image(
      image,
      Rect(
        bitmap.left.toDouble(),
        (bitmap.top - bitmap.height).toDouble(),
        bitmap.width.toDouble(),
        bitmap.height.toDouble(),
      ),
    );
  }
}
