/// The canvas pages and forms are drawn on: a typed front for the
/// content-stream operators (ISO 32000-2, 8 and 9), keeping track of the
/// resources the content uses. There is no hidden state beyond what PDF
/// itself keeps (the graphics state stack): text is always drawn at an
/// explicit position.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:plain_fonts/plain_fonts.dart'
    show
        BitmapGlyph,
        ColorBox,
        ColorExtend,
        ColorGlyphs,
        ColorLine,
        ColorPainter,
        ColorTransform,
        CompositeMode,
        PaintColor,
        PaletteColor;
import 'package:plain_pdf/src/byte_writer.dart';
import 'package:plain_pdf/src/drawing/shading.dart';
import 'package:plain_pdf/src/fonts/fonts.dart';
import 'package:plain_pdf/src/images/images.dart';
import 'package:plain_pdf/src/objects.dart';
import 'package:plain_pdf/src/reader/reader.dart';
import 'package:plain_svg/plain_svg.dart'
    show Gradient, LinearGradient, RadialGradient, SvgCanvas;
import 'package:plain_typesetting/plain_typesetting.dart';

part 'color_glyphs.dart';

/// What a soft mask takes from its form (ISO 32000-2, 11.6.5.2).
enum SoftMaskKind {
  /// The luminosity of the form's colors.
  luminosity('Luminosity'),

  /// The form's alpha.
  alpha('Alpha');

  new(this.pdfName);

  /// The kind's PDF name.
  final String pdfName;
}

/// A transparency group (ISO 32000-2, 11.6.6): a form painted as one
/// object.
@immutable
final class TransparencyGroup {
  /// A group; [isolated] ones start from a transparent backdrop,
  /// [knockout] ones paint each object over the group's backdrop rather
  /// than over each other.
  const new({this.isolated = false, this.knockout = false});

  /// Whether the group is isolated.
  final bool isolated;

  /// Whether the group is a knockout group.
  final bool knockout;
}

/// A form XObject: content drawn once and painted wherever it is used
/// (ISO 32000-2, 8.10), also the content of soft masks.
final class PdfForm {
  /// A form whose content is in [bbox], drawn by [draw].
  new(
    this.bbox,
    void Function(PdfCanvas canvas) draw, {
    this.group,
    this.matrix,
  }) {
    draw(_canvas);
    if (_canvas._unbalanced case final problem?) throw StateError(problem);
  }

  /// The form's bounding box, in its own space.
  final Rect bbox;

  /// The transparency group the form is, if any.
  final TransparencyGroup? group;

  /// The transformation from form space to the space it is painted in.
  final Matrix? matrix;

  final PdfCanvas _canvas = PdfCanvas._();
}

/// The canvas [form] is drawn on.
@internal
PdfCanvas formCanvas(PdfForm form) => form._canvas;

/// A new, empty canvas (for a page).
@internal
PdfCanvas newCanvas() => PdfCanvas._();

/// Where a tagged page's canvas records the logical structure painted on
/// it (the document's structure tree).
@internal
abstract interface class StructureRecorder {
  /// [element] begun, inside [parent] (null: at the top).
  void begin(StructureElement element, StructureElement? parent);

  /// The marked-content id of the next piece of [element]'s content on
  /// the page.
  int mark(StructureElement element);
}

/// Has [canvas] record the structure painted on it in [recorder]: its
/// content marked as its elements' (`BDC` with an `MCID`) or as
/// artifacts (ISO 32000-2, 14.7.2 and 14.8.2.2); text in another language
/// than its element's (or than [language], the document's) marked with
/// its own (14.9.2.2).
@internal
void tagCanvas(
  PdfCanvas canvas,
  StructureRecorder recorder, {
  String? language,
}) => canvas
  .._recorder = recorder
  .._language = language;

/// The element whose content [canvas] is painting now, if any (a link's).
@internal
StructureElement? canvasElement(PdfCanvas canvas) =>
    canvas._elements.lastOrNull;

/// Ends the marked-content sequence open at the end of [canvas]'s content.
@internal
void closeCanvasMarks(PdfCanvas canvas) => canvas._unmark();

/// [canvas] as the PDF canvas it must be for [what] (a PDF image, form or
/// page, which belong to a PDF's resources) to paint on.
PdfCanvas pdfCanvasOf(Canvas canvas, String what) => switch (canvas) {
  final PdfCanvas pdf => pdf,
  _ => throw ArgumentError.value(
    canvas,
    'canvas',
    '$what paints on a PdfCanvas',
  ),
};

/// [style]'s font, which must be a PDF font to be set on a PDF canvas.
PdfFont _pdfFont(TextStyle style) => switch (style.font) {
  final PdfFont font => font,
  final other => throw ArgumentError.value(
    other,
    'style.font',
    'a PDF canvas sets text in PdfFonts',
  ),
};

/// The resources [canvas]'s content uses, by category (`Font`,
/// `XObject`, `ExtGState`, `ColorSpace`, `Shading`) and name.
@internal
Map<String, Map<String, Resource>> canvasResources(PdfCanvas canvas) =>
    canvas._resources;

/// The content stream of [canvas].
@internal
Uint8List canvasContent(PdfCanvas canvas) => canvas._content.toBytes();

/// Whether [canvas]'s content uses transparency.
@internal
bool canvasUsesTransparency(PdfCanvas canvas) => canvas._usesTransparency;

/// What is left open at the end of [canvas]'s content (a save without its
/// restore, an unpainted path), or null.
@internal
String? canvasUnbalanced(PdfCanvas canvas) => canvas._unbalanced;

/// A resource content refers to by name.
@internal
sealed class Resource {
  const new();
}

/// A font.
@internal
final class FontResource extends Resource {
  /// The resource of [font] (of its simple font [subset], for a
  /// single-byte [EmbeddedFont]).
  const new(this.font, {this.subset = 0});

  /// The font.
  final PdfFont font;

  /// The simple font of a single-byte font.
  final int subset;
}

/// A Type 3 font of color glyphs ([ColorFont]).
@internal
final class ColorFontResource extends Resource {
  /// The resource of [font].
  const new(this.font);

  /// The font.
  final ColorFont font;
}

/// An image.
@internal
final class ImageResource extends Resource {
  /// The resource of [image].
  const new(this.image);

  /// The image.
  final PdfImage image;
}

/// A form.
@internal
final class FormResource extends Resource {
  /// The resource of [form].
  const new(this.form);

  /// The form.
  final PdfForm form;
}

/// A page of another file.
@internal
final class ImportedPageResource extends Resource {
  /// The resource of [page].
  const new(this.page);

  /// The page.
  final ImportedPage page;
}

/// A spot color's Separation color space.
@internal
final class SeparationResource extends Resource {
  /// The color space of [name], approximated by [alternate].
  const new(this.name, this.alternate);

  /// The colorant.
  final String name;

  /// Its CMYK alternate.
  final CmykColor alternate;
}

/// A shading.
@internal
final class ShadingResource extends Resource {
  /// The resource of [shading].
  const new(this.shading);

  /// The shading.
  final PdfShading shading;
}

/// Graphics state parameters (an ExtGState dictionary).
@internal
final class GraphicsStateResource extends Resource {
  /// The parameters: opacity, blend mode, soft mask.
  const new({
    this.fillOpacity,
    this.strokeOpacity,
    this.blendMode,
    this.softMask,
    this.invertSoftMask = false,
    this.clearSoftMask = false,
  });

  /// The fill opacity (`ca`).
  final double? fillOpacity;

  /// The stroke opacity (`CA`).
  final double? strokeOpacity;

  /// The blend mode (`BM`).
  final BlendMode? blendMode;

  /// The soft mask (`SMask`): its form and kind.
  final (PdfForm, SoftMaskKind)? softMask;

  /// Whether the soft mask is inverted (its transfer function, `TR`,
  /// from 1 to 0).
  final bool invertSoftMask;

  /// Whether the parameters remove the soft mask (`/SMask /None`).
  final bool clearSoftMask;
}

/// A page's or form's content: operators appended in order.
final class PdfCanvas implements StructureCanvas, SvgCanvas {
  new _();

  /// Where the structure painted is recorded (a tagged page's).
  StructureRecorder? _recorder;

  /// The elements begun and not ended, innermost last.
  final List<StructureElement> _elements = [];

  /// The document's natural language, on a tagged page.
  String? _language;

  /// The language of the text being drawn in a marked-content sequence of
  /// its own, if it is.
  String? _spanLanguage;

  /// [style]'s language where it isn't the language of the content around
  /// it (the open language span's, else the innermost element's that has
  /// one, else the document's), on a tagged page.
  String? _otherLanguage(TextStyle style) {
    final language = style.language;
    if (_recorder == null || language == null || _artifacts > 0) return null;
    final around =
        _spanLanguage ??
        _elements.reversed.map((e) => e.language).nonNulls.firstOrNull ??
        _language;
    return around?.toLowerCase() == language.toLowerCase() ? null : language;
  }

  /// How many artifacts are begun and not ended.
  int _artifacts = 0;

  /// The save depth the open marked-content sequence began at, if one is.
  int? _markedAt;

  /// Begins a marked-content sequence for the content about to be painted,
  /// on a tagged page, unless one is open: the innermost element's, its
  /// next marked-content id, or an artifact's.
  void _mark() {
    final recorder = _recorder;
    if (recorder == null || _markedAt != null) return;
    _markedAt = _depth;
    if (_artifacts > 0 || _elements.isEmpty) {
      _content
        ..name('Artifact')
        ..operator(' BMC');
      return;
    }
    final element = _elements.last;
    _content
      ..name(element.role)
      ..byte(0x20)
      ..bytes(PdfDict({'MCID': PdfInt(recorder.mark(element))}).toBytes())
      ..operator(' BDC');
  }

  /// Ends the open marked-content sequence, if any.
  void _unmark() {
    if (_markedAt == null) return;
    _markedAt = null;
    _op('EMC');
  }

  @override
  void beginStructure(StructureElement element) {
    _noPath('a structure element');
    _unmark();
    _recorder?.begin(element, _elements.lastOrNull);
    _elements.add(element);
  }

  @override
  void endStructure() {
    _noPath('a structure element');
    if (_elements.isEmpty) throw StateError('endStructure() without begin');
    _unmark();
    _elements.removeLast();
  }

  @override
  void beginArtifact() {
    _noPath('an artifact');
    _unmark();
    _artifacts++;
  }

  @override
  void endArtifact() {
    _noPath('an artifact');
    if (_artifacts == 0) throw StateError('endArtifact() without begin');
    _unmark();
    _artifacts--;
  }

  final ByteWriter _content = ByteWriter();

  final Map<String, Map<String, Resource>> _resources = {};

  final Map<Object, String> _names = {};

  int _depth = 0;
  bool _path = false;

  bool _usesTransparency = false;

  String? get _unbalanced => _depth != 0
      ? '$_depth save() calls without restore()'
      : _path
      ? 'a path was left without painting it'
      : _elements.isNotEmpty
      ? '${_elements.length} structure elements begun without end'
      : _artifacts != 0
      ? '$_artifacts artifacts begun without end'
      : null;

  // Each operator is written straight to bytes, its operands formatted as
  // formatNumber formats them.

  void _op(String operator) => _content.operator(operator);

  void _op1(double a, String operator) => _content
    ..number(a, 5)
    ..byte(0x20)
    ..operator(operator);

  void _op2(double a, double b, String operator) => _content
    ..number(a, 5)
    ..byte(0x20)
    ..number(b, 5)
    ..byte(0x20)
    ..operator(operator);

  void _op3(double a, double b, double c, String operator) => _content
    ..number(a, 5)
    ..byte(0x20)
    ..number(b, 5)
    ..byte(0x20)
    ..number(c, 5)
    ..byte(0x20)
    ..operator(operator);

  void _op4(double a, double b, double c, double d, String operator) => _content
    ..number(a, 5)
    ..byte(0x20)
    ..number(b, 5)
    ..byte(0x20)
    ..number(c, 5)
    ..byte(0x20)
    ..number(d, 5)
    ..byte(0x20)
    ..operator(operator);

  void _op6(
    double a,
    double b,
    double c,
    double d,
    double e,
    double f,
    String operator,
  ) => _content
    ..number(a, 5)
    ..byte(0x20)
    ..number(b, 5)
    ..byte(0x20)
    ..number(c, 5)
    ..byte(0x20)
    ..number(d, 5)
    ..byte(0x20)
    ..number(e, 5)
    ..byte(0x20)
    ..number(f, 5)
    ..byte(0x20)
    ..operator(operator);

  void _opInt(int a, String operator) => _content
    ..numeric(a)
    ..byte(0x20)
    ..operator(operator);

  void _named(String operator, String name) => _content
    ..name(name)
    ..byte(0x20)
    ..operator(operator);

  /// The name [resource] has in [category], given by its first use.
  String _use(String category, Object key, Resource resource, String prefix) {
    final name = _names[key] ??= '$prefix${_names.length + 1}';
    (_resources[category] ??= {})[name] = resource;
    return name;
  }

  void _noPath(String what) {
    if (_path) throw StateError('$what inside a path: paint it first');
  }

  // Graphics state.

  /// Saves the graphics state (`q`).
  @override
  void save() {
    _noPath('save()');
    _depth += 1;
    _fills.add(_fill);
    _op('q');
  }

  /// The fill color set last (as PDF's graphics state keeps it; black
  /// to start with), and those of the states saved.
  Color _fill = const GrayColor(0);
  final List<Color> _fills = [];

  /// Restores the graphics state saved last (`Q`).
  @override
  void restore() {
    _noPath('restore()');
    if (_depth == 0) throw StateError('restore() without save()');
    // (A marked-content sequence begun inside what is restored ends
    // before it: the two nest.)
    if (_markedAt case final at? when at >= _depth) _unmark();
    _depth -= 1;
    _fill = _fills.removeLast();
    _op('Q');
  }

  /// Runs [draw] between [save] and [restore].
  @override
  void saved(void Function() draw) {
    save();
    draw();
    restore();
  }

  /// Transforms the coordinate system by [matrix] (`cm`).
  @override
  void transform(Matrix matrix) {
    _noPath('transform()');
    _op6(matrix.a, matrix.b, matrix.c, matrix.d, matrix.e, matrix.f, 'cm');
  }

  /// Moves the origin to ([x], [y]).
  @override
  void translate(double x, double y) => transform(Matrix.translation(x, y));

  /// Scales by [x] horizontally and [y] (default [x]) vertically.
  @override
  void scale(double x, [double? y]) => transform(Matrix.scaling(x, y ?? x));

  /// Rotates counterclockwise by [degrees].
  @override
  void rotate(double degrees) =>
      transform(Matrix.rotation(degrees * math.pi / 180));

  /// The width of stroked lines (`w`).
  @override
  void setLineWidth(double width) => _op1(width, 'w');

  /// The shape of line ends (`J`).
  @override
  void setLineCap(LineCap cap) => _opInt(cap.index, 'J');

  /// The shape of corners (`j`).
  @override
  void setLineJoin(LineJoin join) => _opInt(join.index, 'j');

  /// The miter limit (`M`).
  @override
  void setMiterLimit(double limit) => _op1(limit, 'M');

  /// The dash pattern (`d`): alternating dash and gap lengths starting at
  /// [phase]; empty for solid lines.
  @override
  void dash(List<double> pattern, [double phase = 0]) {
    // The array as PdfArray writes it (on the web, its whole numbers are
    // PdfInts, and -0.0 is written as 0).
    _content
      ..bytes(PdfArray.numbers(pattern).toBytes())
      ..commit()
      ..byte(0x20)
      ..number(phase, 5)
      ..operator(' d');
  }

  /// The color of fills, text included.
  @override
  void setFillColor(Color color) {
    _fill = color;
    _color(color, stroke: false);
  }

  /// The color of strokes.
  @override
  void setStrokeColor(Color color) => _color(color, stroke: true);

  void _color(Color color, {required bool stroke}) {
    switch (color) {
      case GrayColor(:final level):
        _op1(level, stroke ? 'G' : 'g');
      case RgbColor(:final red, :final green, :final blue):
        _op3(red, green, blue, stroke ? 'RG' : 'rg');
      case CmykColor(:final cyan, :final magenta, :final yellow, :final black):
        _op4(cyan, magenta, yellow, black, stroke ? 'K' : 'k');
      case SpotColor(:final name, :final alternate, :final tint):
        final space = _use(
          'ColorSpace',
          ('separation', name, alternate),
          SeparationResource(name, alternate),
          'CS',
        );
        _named(stroke ? 'CS' : 'cs', space);
        _op1(tint, stroke ? 'SCN' : 'scn');
    }
  }

  void _graphicsState(Object key, GraphicsStateResource state) {
    _noPath('a graphics state change');
    _usesTransparency = true;
    _named('gs', _use('ExtGState', key, state, 'GS'));
  }

  /// The opacity of fills and of strokes (0 transparent, 1 opaque).
  @override
  void opacity({double? fill, double? stroke}) => _graphicsState((
    'opacity',
    fill,
    stroke,
  ), GraphicsStateResource(fillOpacity: fill, strokeOpacity: stroke));

  /// The blend mode.
  @override
  void setBlendMode(BlendMode mode) =>
      _graphicsState(('blend', mode), GraphicsStateResource(blendMode: mode));

  /// Masks what is painted next by [mask] (a form with a transparency
  /// group), until the state is restored or [clearSoftMask] is called;
  /// with [invert], by its inverse (a transfer function from 1 to 0).
  void softMask(
    PdfForm mask, {
    SoftMaskKind kind = SoftMaskKind.luminosity,
    bool invert = false,
  }) {
    if (mask.group == null) {
      throw ArgumentError.value(
        mask,
        'mask',
        'a soft mask must be a form with a transparency group',
      );
    }
    _graphicsState((
      'softMask',
      mask,
      kind,
      invert,
    ), GraphicsStateResource(softMask: (mask, kind), invertSoftMask: invert));
  }

  /// Removes the soft mask.
  void clearSoftMask() => _graphicsState(
    'clearSoftMask',
    const GraphicsStateResource(clearSoftMask: true),
  );

  // Paths.

  /// Starts a subpath at ([x], [y]) (`m`).
  @override
  void moveTo(double x, double y) {
    if (!_path) _mark();
    _path = true;
    _op2(x, y, 'm');
  }

  /// A line to ([x], [y]) (`l`).
  @override
  void lineTo(double x, double y) {
    _needPath('lineTo()');
    _op2(x, y, 'l');
  }

  /// A cubic Bézier curve to ([x3], [y3]) with control points ([x1],
  /// [y1]) and ([x2], [y2]) (`c`).
  @override
  void curveTo(
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
  ) {
    _needPath('curveTo()');
    _op6(x1, y1, x2, y2, x3, y3, 'c');
  }

  /// Closes the subpath (`h`).
  @override
  void closePath() {
    _needPath('closePath()');
    _op('h');
  }

  void _needPath(String what) {
    if (!_path) throw StateError('$what needs a current point: moveTo() first');
  }

  /// A rectangle (`re`).
  @override
  void rect(Rect rect) {
    if (!_path) _mark();
    _path = true;
    _op4(rect.left, rect.bottom, rect.width, rect.height, 're');
  }

  /// A rectangle with corners rounded to [radius].
  @override
  void roundedRect(Rect rect, double radius) {
    final r = math.min(radius, math.min(rect.width, rect.height) / 2);
    if (r <= 0) return this.rect(rect);
    final k = r * _kappa;
    final Rect(:left, :bottom, :right, :top) = rect;
    moveTo(left + r, bottom);
    lineTo(right - r, bottom);
    curveTo(right - r + k, bottom, right, bottom + r - k, right, bottom + r);
    lineTo(right, top - r);
    curveTo(right, top - r + k, right - r + k, top, right - r, top);
    lineTo(left + r, top);
    curveTo(left + r - k, top, left, top - r + k, left, top - r);
    lineTo(left, bottom + r);
    curveTo(left, bottom + r - k, left + r - k, bottom, left + r, bottom);
    closePath();
  }

  /// An ellipse centered on ([cx], [cy]) with radii [rx] and [ry], as four
  /// Bézier curves.
  @override
  void ellipse(double cx, double cy, double rx, double ry) {
    final kx = rx * _kappa;
    final ky = ry * _kappa;
    moveTo(cx + rx, cy);
    curveTo(cx + rx, cy + ky, cx + kx, cy + ry, cx, cy + ry);
    curveTo(cx - kx, cy + ry, cx - rx, cy + ky, cx - rx, cy);
    curveTo(cx - rx, cy - ky, cx - kx, cy - ry, cx, cy - ry);
    curveTo(cx + kx, cy - ry, cx + rx, cy - ky, cx + rx, cy);
    closePath();
  }

  /// A circle centered on ([cx], [cy]) of [radius].
  @override
  void circle(double cx, double cy, double radius) =>
      ellipse(cx, cy, radius, radius);

  /// The control point distance of a quarter circle of radius 1.
  static final double _kappa = 4 * (math.sqrt(2) - 1) / 3;

  void _paint(String operator) {
    _needPath('painting');
    _path = false;
    _op(operator);
  }

  /// Fills the path (`f`, or `f*` with the even-odd rule).
  @override
  void fill({bool evenOdd = false}) => _paint(evenOdd ? 'f*' : 'f');

  /// Strokes the path (`S`).
  @override
  void stroke() => _paint('S');

  /// Fills, then strokes the path (`B`, or `B*`).
  @override
  void fillAndStroke({bool evenOdd = false}) => _paint(evenOdd ? 'B*' : 'B');

  /// Intersects the clipping path with the path, without painting it
  /// (`W n`, or `W* n`).
  @override
  void clip({bool evenOdd = false}) {
    _needPath('clip()');
    _op(evenOdd ? 'W*' : 'W');
    _paint('n');
  }

  /// Ends the path without painting it (`n`).
  @override
  void endPath() => _paint('n');

  /// Paints what [draw] paints as a form with a transparency group.
  @override
  void group(Rect bounds, void Function(SvgCanvas canvas) draw) =>
      form(PdfForm(bounds, draw, group: const TransparencyGroup()));

  /// Paints [gradient] as an axial or radial shading.
  @override
  void gradient(Gradient gradient) {
    final stops = [
      for (final stop in gradient.stops) GradientStop(stop.offset, stop.color),
    ];
    shade(switch (gradient) {
      LinearGradient(:final x1, :final y1, :final x2, :final y2) =>
        AxialShading(x1, y1, x2, y2, stops),
      RadialGradient(
        :final fx,
        :final fy,
        :final fr,
        :final cx,
        :final cy,
        :final r,
      ) =>
        RadialShading(fx, fy, fr, cx, cy, r, stops),
    });
  }

  /// Masks what is painted next by the luminosity of a form with a
  /// transparency group, which [draw] paints.
  @override
  void luminosityMask(Rect bounds, void Function(SvgCanvas canvas) draw) =>
      softMask(PdfForm(bounds, draw, group: const TransparencyGroup()));

  /// Paints [shading] over the clipping region (`sh`): clip to a path
  /// first to fill it with a gradient.
  void shade(PdfShading shading) {
    _noPath('shade()');
    _mark();
    _named('sh', _use('Shading', shading, ShadingResource(shading), 'Sh'));
  }

  // Images and forms.

  /// Paints [image] into [rect].
  void image(PdfImage image, Rect rect) {
    _noPath('image()');
    _mark();
    final name = _use('XObject', image, ImageResource(image), 'Im');
    _op('q');
    _op6(rect.width, 0, 0, rect.height, rect.left, rect.bottom, 'cm');
    _named('Do', name);
    _op('Q');
  }

  /// Paints [page], a page of another file, into [rect].
  void page(ImportedPage page, Rect rect) {
    _noPath('page()');
    _mark();
    if (page.group != null) _usesTransparency = true;
    final name = _use('XObject', page, ImportedPageResource(page), 'Pg');
    final m = page.placement(rect);
    _op('q');
    _op6(m.a, m.b, m.c, m.d, m.e, m.f, 'cm');
    _named('Do', name);
    _op('Q');
  }

  /// Paints [form] (`Do`).
  void form(PdfForm form) {
    _noPath('form()');
    _mark();
    if (form.group != null || form._canvas._usesTransparency) {
      _usesTransparency = true;
    }
    _named('Do', _use('XObject', form, FormResource(form), 'Fm'));
  }

  // Marked content.

  /// Begins a marked-content sequence tagged [tag] (ISO 32000-2, 14.6),
  /// to end with [endMarkedContent]. With [actualText], the sequence's
  /// content reads as that text when text is extracted, copied or read
  /// aloud (14.9.4): an empty one leaves decorative glyphs out.
  @override
  void beginMarkedContent(String tag, {String? actualText}) {
    _noPath('marked content');
    _mark();
    _content.name(tag);
    if (actualText != null) {
      _content
        ..byte(0x20)
        ..bytes(PdfDict({'ActualText': PdfString.text(actualText)}).toBytes())
        ..operator(' BDC');
    } else {
      _content.operator(' BMC');
    }
  }

  /// Ends the marked-content sequence [beginMarkedContent] began.
  @override
  void endMarkedContent() => _op('EMC');

  // Text.

  /// Draws [text] in [style] with its baseline starting at ([x], [y]);
  /// returns its width.
  @override
  double text(String text, double x, double y, TextStyle style) =>
      glyphs(style.shape(text), x, y, style);

  /// Draws shaped [glyphs] of [style]'s font with the baseline starting
  /// at ([x], [y]); returns their width.
  ///
  /// Glyphs that text taken from the page can't read as their own text
  /// (one standing for no text, one the font's map reads as another, a
  /// mark moved onto its base, which extraction sets apart from it) are
  /// marked as reading as [text] (ISO 32000-2, 14.9.4): what they stand
  /// for in the order they are drawn, as the content around them reads,
  /// else their texts one after another.
  @override
  double glyphs(
    List<ShapedGlyph> glyphs,
    double x,
    double y,
    TextStyle style, {
    String? text,
  }) {
    // (Text in another language than its element's: a span of its own
    // with its Lang, as a screen reader switches voices.)
    if (_otherLanguage(style) case final language?) {
      _mark();
      _content
        ..name('Span')
        ..byte(0x20)
        ..bytes(PdfDict({'Lang': PdfString.text(language)}).toBytes())
        ..operator(' BDC');
      _spanLanguage = language;
      try {
        return this.glyphs(glyphs, x, y, style, text: text);
      } finally {
        _spanLanguage = null;
        endMarkedContent();
      }
    }
    // (Text in a mirrored frame, mirrored back about its em box's middle.)
    if (style.flipped) {
      final middle =
          y + (style.font.ascender + style.font.descender) / 2000 * style.size;
      var width = 0.0;
      saved(() {
        transform(Matrix(1, 0, 0, -1, 0, 2 * middle));
        width = this.glyphs(
          glyphs,
          x,
          y,
          style.copyWith(flipped: false),
          text: text,
        );
      });
      return width;
    }
    // (A vertical line's upright glyphs, each turned back a quarter turn.)
    if (glyphs.any((g) => g.upright)) return _vertical(glyphs, x, y, style);
    // (Color glyphs, drawn as their font paints them.)
    if (_colorGlyphsOf(style) case final colors?
        when style.renderMode != TextRenderMode.invisible &&
            glyphs.any((g) => _isColor(colors, g.id))) {
      return _withColorGlyphs(glyphs, x, y, style, colors);
    }
    final font = _pdfFont(style);
    // (A glyph moved off the baseline, or a mark onto its base: text taken
    // from the page sets it apart. A letter moved along the line is read
    // where it is.)
    final moved = glyphs.any(
      (glyph) =>
          glyph.yOffset != 0 || (glyph.advance == 0 && glyph.xOffset != 0),
    );
    final readable =
        !moved && (font is! EmbeddedFont || font.readsAsShown(glyphs));
    if (readable) return _glyphs(glyphs, x, y, style);
    beginMarkedContent(
      'Span',
      actualText: text ?? glyphs.map((glyph) => glyph.text).join(),
    );
    // (A single-byte font's runs place glyphs by their advances alone.)
    final singleByte = font is EmbeddedFont && font.singleByte;
    _glyphs(singleByte ? glyphs : _baseFirst(glyphs, style), x, y, style);
    endMarkedContent();
    return style.widthOf(glyphs);
  }

  /// [run], a vertical line's glyphs, laid out across from ([x], [y]): its
  /// glyphs on their side drawn as they are, each upright one turned a
  /// quarter turn back (left) about its place, its vertical origin's
  /// offsets from the line's center (half the font's ascender and
  /// descender above the baseline), so that the line turned to run down
  /// the page shows it upright; returns their width.
  double _vertical(List<ShapedGlyph> run, double x, double y, TextStyle style) {
    final size = style.size;
    final scale = size / 1000;
    final centre = y + (style.font.ascender + style.font.descender) / 2 * scale;
    var pen = x;
    var i = 0;
    while (i < run.length) {
      final upright = run[i].upright;
      var j = i;
      while (j < run.length && run[j].upright == upright) {
        j++;
      }
      final part = run.sublist(i, j);
      if (!upright) {
        glyphs(part, pen, y, style);
      } else {
        var at = pen;
        for (final g in part) {
          saved(() {
            transform(
              Matrix(
                0,
                1,
                -1,
                0,
                at - g.yOffset * scale,
                centre + g.xOffset * scale,
              ),
            );
            glyphs([ShapedGlyph(g.id, g.text, g.advance)], 0, 0, style);
          });
          at += (g.advance + g.kerning) * scale + style.characterSpacing;
        }
      }
      pen += style.widthOf(part);
      if (j < run.length) pen += part.last.kerning * scale;
      i = j;
    }
    return pen - x;
  }

  /// [glyphs] with color glyphs among them, from ([x], [y]): the color
  /// glyphs each as its form ([_colorForm]) marked as reading as its text
  /// (ISO 32000-2, 14.9.4), the rest as text (none in a font of bitmaps
  /// alone, which has no outlines); returns their width.
  double _withColorGlyphs(
    List<ShapedGlyph> glyphs,
    double x,
    double y,
    TextStyle style,
    ColorGlyphs colors,
  ) {
    final font = colors.font;
    final outlines = font.isTrueType || font.hasTable('CFF ');
    final across = style.horizontalScaling / 100;
    // (A thousandth of the em, in points along the line.)
    final unit = style.size / 1000 * across;
    var pen = x;
    var i = 0;
    while (i < glyphs.length) {
      final color = _isColor(colors, glyphs[i].id);
      var j = i + 1;
      while (j < glyphs.length && _isColor(colors, glyphs[j].id) == color) {
        j++;
      }
      final part = glyphs.sublist(i, j);
      if (!color) {
        if (outlines) this.glyphs(part, pen, y, style);
      } else {
        var at = pen;
        for (final (k, g) in part.indexed) {
          _colorGlyph(
            colors,
            g,
            at + g.xOffset * unit,
            y + style.rise + g.yOffset * style.size / 1000,
            style,
          );
          at += style.widthOf([g]);
          if (k < part.length - 1) at += g.kerning * unit;
        }
      }
      pen += style.widthOf(part);
      if (j < glyphs.length) pen += part.last.kerning * unit;
      i = j;
    }
    return pen - x;
  }

  /// Draws color glyph [glyph] of [colors]'s font at ([x], [y]) as a code
  /// of a Type 3 font of its color glyphs ([ColorFont]), which reads as
  /// its text; where its code reads as another (a glyph standing for
  /// different texts), marked as reading as its own.
  void _colorGlyph(
    ColorGlyphs colors,
    ShapedGlyph glyph,
    double x,
    double y,
    TextStyle style,
  ) {
    final fonts = _colorFonts[style.font] ??= {};
    final key = _fill;
    final list = fonts[key] ??= [];
    var font = list.where((f) => f._codes.containsKey(glyph.id)).firstOrNull;
    if (font == null) {
      // (255 codes a font: the last is its `m`, see _writeColorFont.)
      font = list.where((f) => f._forms.length < 255).firstOrNull;
      if (font == null) {
        font = ColorFont._(colors.font.unitsPerEm, colors.font.bbox);
        list.add(font);
      }
      font._codes[glyph.id] = font._forms.length;
      font._forms.add(_colorForm(colors, glyph.id, style));
      font._widths.add(colors.font.advance(glyph.id));
      font._texts.add(glyph.text);
    }
    final code = font._codes[glyph.id]!;
    final actual = font._texts[code] != glyph.text;
    if (actual) beginMarkedContent('Span', actualText: glyph.text);
    _noPath('text');
    _mark();
    _op('BT');
    _content
      ..name(_use('Font', font, ColorFontResource(font), 'F'))
      ..commit()
      ..byte(0x20)
      ..number(style.size, 5)
      ..operator(' Tf');
    _op6(style.horizontalScaling / 100, 0, style.skew, 1, x, y, 'Tm');
    _content
      ..string([code], 0, 1, hex: true)
      ..operator(' Tj');
    _op('ET');
    if (actual) endMarkedContent();
  }

  /// The form of color glyph [glyph] of [colors]'s font in [style], in
  /// font units, the text's color its foreground: drawn once for each
  /// font and color.
  PdfForm _colorForm(ColorGlyphs colors, int glyph, TextStyle style) {
    final forms = _colorForms[style.font] ??= {};
    return forms[(glyph, _fill)] ??= () {
      final upem = colors.font.unitsPerEm;
      final reach = _reach * upem;
      final fill = _fill;
      return PdfForm(Rect(-reach, -reach, 2 * reach, 2 * reach), (canvas) {
        colors.paint(glyph, _PdfColorPainter(canvas, style, fill, upem));
      });
    }();
  }

  /// [glyphs] with the marks they start with (a right-to-left cluster's,
  /// drawn before their base) drawn after its base instead, at the same
  /// places: text taken from the page places a marked sequence where its
  /// first glyph is, which is then the base, on the line.
  static List<ShapedGlyph> _baseFirst(
    List<ShapedGlyph> glyphs,
    TextStyle style,
  ) {
    final base = glyphs.indexWhere((glyph) => glyph.advance != 0);
    if (base <= 0) return glyphs;
    final b = glyphs[base];
    // (The character spacing after each glyph, in thousandths of the em.)
    final spacing = style.characterSpacing * 1000 / style.size;
    final marks = glyphs.sublist(0, base);
    final last = marks.last;
    // (How far the marks move the pen before the base: their kerning and
    // the spacing after each.)
    final before = marks.fold<double>(0, (sum, m) => sum + m.kerning + spacing);
    return [
      // (The base where it was, then back to where the marks start...)
      ShapedGlyph.positioned(
        b.id,
        b.text,
        b.advance,
        kerning: -(b.advance + spacing),
        xOffset: b.xOffset + before,
        yOffset: b.yOffset,
      ),
      ...marks.take(marks.length - 1),
      // (... and past it again after its marks.)
      ShapedGlyph.positioned(
        last.id,
        last.text,
        last.advance,
        kerning: last.kerning + b.advance + spacing + b.kerning,
        xOffset: last.xOffset,
        yOffset: last.yOffset,
      ),
      ...glyphs.sublist(base + 1),
    ];
  }

  double _glyphs(
    List<ShapedGlyph> glyphs,
    double x,
    double y,
    TextStyle style,
  ) {
    _noPath('text');
    _mark();
    final font = _pdfFont(style);
    // A single-byte font shows the glyphs in runs of one simple font each.
    final runs = switch (font) {
      EmbeddedFont(singleByte: true) => font.encodeRuns(glyphs),
      _ => null,
    };
    final fontName = _fontName(font, runs?.firstOrNull?.subset ?? 0);
    final embolden = style.embolden > 0;
    // The stroke's width stays with the text.
    if (embolden) _op('q');
    _op('BT');
    _content
      ..name(fontName)
      ..commit()
      ..byte(0x20)
      ..number(style.size, 5)
      ..operator(' Tf');
    if (style.characterSpacing != 0) _op1(style.characterSpacing, 'Tc');
    if (style.rise != 0) _op1(style.rise, 'Ts');
    if (style.horizontalScaling != 100) _op1(style.horizontalScaling, 'Tz');
    if (embolden) {
      _op1(style.embolden, 'w');
      _opInt(TextRenderMode.fillStroke.index, 'Tr');
    } else if (style.renderMode != TextRenderMode.fill) {
      _opInt(style.renderMode.index, 'Tr');
    }
    if (style.skew != 0) {
      _op6(1, 0, style.skew, 1, x, y, 'Tm');
    } else {
      _op2(x, y, 'Td');
    }
    if (runs == null) {
      _showText(glyphs, style);
    } else {
      _showRuns(glyphs, runs, font as EmbeddedFont, style);
    }
    _op('ET');
    if (embolden) _op('Q');
    return style.widthOf(glyphs);
  }

  /// The name of [font]'s resource (of its simple font [subset]).
  String _fontName(PdfFont font, int subset) => subset == 0
      ? _use('Font', font, FontResource(font), 'F')
      : _use('Font', (font, subset), FontResource(font, subset: subset), 'F');

  /// [glyphs] of a single-byte [font] shown in [runs] of one simple font
  /// each (`Tf` between them), the kerning as `TJ` adjustments and the
  /// word spacing as `Tw` (to a hundred-thousandth of a point), which
  /// applies to the space, code 32 in each.
  void _showRuns(
    List<ShapedGlyph> glyphs,
    List<({int subset, int start, int end, Uint8List codes})> runs,
    EmbeddedFont font,
    TextStyle style,
  ) {
    final wordSpacing = (style.wordSpacing * 1e5).round() / 1e5;
    if (wordSpacing != 0) _op1(wordSpacing, 'Tw');
    final last = glyphs.length - 1;
    for (final (r, run) in runs.indexed) {
      if (r > 0 && run.subset != runs[r - 1].subset) {
        _content
          ..name(_fontName(font, run.subset))
          ..byte(0x20)
          ..number(style.size, 5)
          ..operator(' Tf');
      }
      final out = _content..byte(0x5b); // [
      var start = 0;
      for (var i = run.start; i < run.end; i++) {
        final drift = font.glyphAdvance(glyphs[i].id) - glyphs[i].advance;
        final adjustment = i < last
            ? -glyphs[i].kerning + (drift.abs() > 1e-9 ? drift : 0)
            : 0.0;
        if (adjustment != 0) {
          final end = i - run.start + 1;
          if (end != start) out.string(run.codes, start, end, hex: false);
          start = end;
          out
            ..byte(0x20)
            ..number(adjustment, 5)
            ..byte(0x20);
        }
      }
      if (run.codes.length != start) {
        out.string(run.codes, start, run.codes.length, hex: false);
      }
      out.operator('] TJ');
    }
    if (wordSpacing != 0) _op1(0, 'Tw');
  }

  /// The `TJ` operator showing [glyphs]: runs of glyph codes, with the
  /// kerning and the word spacing between them as adjustments.
  void _showText(List<ShapedGlyph> glyphs, TextStyle style) {
    final font = _pdfFont(style);
    final codes = font.encode(glyphs);
    final width = switch (font) {
      StandardFont() => 1,
      EmbeddedFont() => 2,
    };
    final hex = font is EmbeddedFont;
    // (The word spacing to a hundred-thousandth of a point, as a `Tw`
    // operand would give it, in thousandths of the size.)
    final wordSpacing = style.wordSpacing != 0
        ? (style.wordSpacing * 1e5).round() / 1e5 * 1000 / style.size
        : 0.0;
    // A glyph drawn off its pen position (a mark on its base) moves the
    // pen by its x offset before it and back after it, and a run of
    // glyphs raised by the same y offset is shown with its own rise.
    final positioned = _positioned(glyphs);
    final last = glyphs.length - 1;
    var out = _content..byte(0x5b); // [
    var start = 0;
    var rise = 0.0;
    void adjust(double adjustment, int end) {
      if (end != start) out.string(codes, start, end, hex: hex);
      start = end;
      out
        ..byte(0x20)
        ..number(adjustment, 5)
        ..byte(0x20);
    }

    for (var i = 0; i <= last; i++) {
      final glyph = glyphs[i];
      if (positioned) {
        if (glyph.yOffset != rise) {
          if (i * width != start) out.string(codes, start, i * width, hex: hex);
          start = i * width;
          out.operator('] TJ');
          rise = glyph.yOffset;
          _op1(style.rise + rise * style.size / 1000, 'Ts');
          out = _content..byte(0x5b);
        }
        if (glyph.xOffset != 0) adjust(-glyph.xOffset, i * width);
      }
      var adjustment = 0.0;
      if (i < last) {
        adjustment -= glyph.kerning;
        // (An advance shaping changed, a right-to-left run's positioning:
        // the pen moved by it, not by the font's.)
        if (font case final EmbeddedFont embedded) {
          final drift = embedded.glyphAdvance(glyph.id) - glyph.advance;
          if (drift.abs() > 1e-9) adjustment += drift;
        }
      }
      if (wordSpacing != 0 && glyph.text == ' ') adjustment -= wordSpacing;
      if (positioned) adjustment += glyph.xOffset;
      if (adjustment != 0) adjust(adjustment, (i + 1) * width);
    }
    final end = glyphs.length * width;
    if (end != start) out.string(codes, start, end, hex: hex);
    out.operator('] TJ');
    // (The rise set back: it outlasts the text object.)
    if (rise != 0) _op1(style.rise, 'Ts');
  }

  /// Whether any of [glyphs] is drawn off its pen position.
  static bool _positioned(List<ShapedGlyph> glyphs) =>
      glyphs.any((g) => g.xOffset != 0 || g.yOffset != 0);
}

/// A Type 3 font (ISO 32000-2, 9.6.4) of a font's color glyphs in one
/// text color: each code's glyph procedure paints the glyph's form, and
/// the code reads as the glyph's text (the first it stood for).
@internal
final class ColorFont {
  new _(this.unitsPerEm, this.bbox);

  /// The font's units per em: its glyph space's.
  final int unitsPerEm;

  /// The font's bounding box (xMin, yMin, xMax, yMax).
  final List<int> bbox;

  final Map<int, int> _codes = {};
  final List<PdfForm> _forms = [];
  final List<int> _widths = [];
  final List<String> _texts = [];

  /// Each code's form, in order.
  List<PdfForm> get forms => _forms;

  /// Each code's advance, in font units.
  List<int> get widths => _widths;

  /// Each code's text.
  List<String> get texts => _texts;
}

/// The Type 3 fonts of each font's color glyphs drawn so far, by the
/// text's color.
final Expando<Map<Color, List<ColorFont>>> _colorFonts = Expando();
