/// The canvas typesetting draws on, whatever the output: an interface a
/// backend implements (plain_pdf's `Canvas` writes PDF content
/// streams), with the line, color, text and blending settings and the
/// text style it takes.
library;

import 'package:meta/meta.dart';
import 'package:plain_typesetting/src/color.dart';
import 'package:plain_typesetting/src/font.dart';
import 'package:plain_typesetting/src/geometry.dart';
import 'package:plain_typesetting/src/shaping.dart'
    show hasLanguageSystem, shapeInLanguage, shapeUpright;
import 'package:plain_unicode/plain_unicode.dart'
    show
        BidiText,
        TextDirection,
        VerticalOrientation,
        hasRightToLeft,
        isMark,
        verticalOrientation;

/// The shape at the ends of stroked open lines.
enum LineCap {
  /// Squared off at the end.
  butt,

  /// A semicircle around the end.
  round,

  /// Squared off half the line width past the end.
  projectingSquare,
}

/// The shape of corners of stroked lines.
enum LineJoin {
  /// A pointed corner, beveled past the miter limit.
  miter,

  /// A rounded corner.
  round,

  /// A beveled corner.
  bevel,
}

/// How text is painted (ISO 32000-2, 9.3.6).
enum TextRenderMode {
  /// Filled.
  fill,

  /// Stroked.
  stroke,

  /// Filled, then stroked.
  fillStroke,

  /// Neither (invisible, still selectable).
  invisible,

  /// Filled, and added to the clipping path.
  fillClip,

  /// Stroked, and added to the clipping path.
  strokeClip,

  /// Filled, stroked, and added to the clipping path.
  fillStrokeClip,

  /// Added to the clipping path.
  clip,
}

/// How colors painted over others combine (ISO 32000-2, 11.3.5).
enum BlendMode {
  /// The source color.
  normal,

  /// Multiplied.
  multiply,

  /// Screened.
  screen,

  /// Multiply or screen, by the backdrop.
  overlay,

  /// The darker.
  darken,

  /// The lighter.
  lighten,

  /// Backdrop brightened.
  colorDodge,

  /// Backdrop darkened.
  colorBurn,

  /// Multiply or screen, by the source.
  hardLight,

  /// Darken or lighten, by the source.
  softLight,

  /// The difference.
  difference,

  /// Like difference, lower in contrast.
  exclusion,
}

/// How text is set: the font and size, and the text state parameters.
@immutable
final class TextStyle {
  /// Text in [font] at [size] points.
  const new(
    this.font,
    this.size, {
    this.characterSpacing = 0,
    this.wordSpacing = 0,
    this.rise = 0,
    this.horizontalScaling = 100,
    this.renderMode = TextRenderMode.fill,
    this.kerning = true,
    this.ligatures = false,
    this.features = const {},
    this.skew = 0,
    this.embolden = 0,
    this.vertical = false,
    this.flipped = false,
    this.language,
    this.combineDigits = 0,
    this.combineUpright = false,
  });

  /// In vertical text, the most digits a number may have to be set across
  /// the line, upright as one character (tate-chu-yoko: JLREQ 3.2.5; CSS's
  /// `text-combine-upright: digits`): two side by side in their half-width
  /// forms, three in their third-width ones, a lone digit in its
  /// full-width form; 0 for none, every digit on its side.
  final int combineDigits;

  /// In vertical text, whether the whole text is set across the line,
  /// upright as one character (CSS's `text-combine-upright: all`: `!?`,
  /// `2026`), in the narrowest forms the font has for its length.
  final bool combineUpright;

  /// The text's language (BCP 47: `ja`, `zh-Hant`, `sr`), choosing the
  /// font's language system (its `locl` forms) as HarfBuzz chooses it;
  /// null for the font's default.
  final String? language;

  /// Whether the text is drawn mirrored top to bottom about the middle of
  /// its em box: text in the mirrored frame of a vertical-lr page
  /// (Mongolian, columns following to the right), where the mirroring
  /// undoes the frame's and leaves the glyphs as they are.
  final bool flipped;

  /// Whether the text is set in vertical lines (Japanese, Chinese read
  /// top to bottom): its characters that stand upright there (UAX #50's
  /// Vertical_Orientation U, Tu and Tr: Han, kana, full-width punctuation)
  /// shaped top to bottom and [ShapedGlyph.upright], the others (Latin,
  /// digits) on their side, as the line is laid out across and turned.
  final bool vertical;

  /// The font.
  final Font font;

  /// The size, in points.
  final double size;

  /// Extra space after each glyph, in points.
  final double characterSpacing;

  /// Extra space after each space, in points.
  final double wordSpacing;

  /// The baseline's shift up, in points.
  final double rise;

  /// The horizontal scaling, in percent.
  final double horizontalScaling;

  /// How the glyphs are painted.
  final TextRenderMode renderMode;

  /// Whether the font's kerning applies.
  final bool kerning;

  /// Whether the font's ligatures apply (embedded fonts).
  final bool ligatures;

  /// The OpenType features whose single substitutions apply (embedded
  /// fonts that have them: `onum` old-style numerals, `smcp` small
  /// capitals...).
  final Set<String> features;

  /// How far the glyphs slant: the tangent of the angle (0.2, about 11
  /// degrees, for an oblique face made from an upright one).
  final double skew;

  /// The width of a stroke around the glyphs, in points, in the current
  /// stroke color (a bold face made from a regular one; set the stroke
  /// color to the fill color).
  final double embolden;

  /// This style with the values given changed.
  TextStyle copyWith({
    Font? font,
    double? size,
    double? characterSpacing,
    double? wordSpacing,
    double? rise,
    double? horizontalScaling,
    TextRenderMode? renderMode,
    bool? kerning,
    bool? ligatures,
    Set<String>? features,
    double? skew,
    double? embolden,
    bool? vertical,
    bool? flipped,
    String? language,
    int? combineDigits,
    bool? combineUpright,
  }) => TextStyle(
    font ?? this.font,
    size ?? this.size,
    characterSpacing: characterSpacing ?? this.characterSpacing,
    wordSpacing: wordSpacing ?? this.wordSpacing,
    rise: rise ?? this.rise,
    horizontalScaling: horizontalScaling ?? this.horizontalScaling,
    renderMode: renderMode ?? this.renderMode,
    kerning: kerning ?? this.kerning,
    ligatures: ligatures ?? this.ligatures,
    features: features ?? this.features,
    skew: skew ?? this.skew,
    embolden: embolden ?? this.embolden,
    vertical: vertical ?? this.vertical,
    flipped: flipped ?? this.flipped,
    language: language ?? this.language,
    combineDigits: combineDigits ?? this.combineDigits,
    combineUpright: combineUpright ?? this.combineUpright,
  );

  @override
  bool operator ==(Object other) =>
      other is TextStyle &&
      other.font == font &&
      other.size == size &&
      other.characterSpacing == characterSpacing &&
      other.wordSpacing == wordSpacing &&
      other.rise == rise &&
      other.horizontalScaling == horizontalScaling &&
      other.renderMode == renderMode &&
      other.kerning == kerning &&
      other.ligatures == ligatures &&
      other.skew == skew &&
      other.embolden == embolden &&
      other.vertical == vertical &&
      other.flipped == flipped &&
      other.language == language &&
      other.combineDigits == combineDigits &&
      other.combineUpright == combineUpright &&
      other.features.length == features.length &&
      other.features.containsAll(features);

  @override
  int get hashCode => Object.hash(
    font,
    size,
    characterSpacing,
    wordSpacing,
    rise,
    horizontalScaling,
    renderMode,
    kerning,
    ligatures,
    Object.hashAllUnordered(features),
    skew,
    embolden,
    vertical,
    flipped,
    language,
    combineDigits,
    combineUpright,
  );

  /// The width of [glyphs] set in this style, in points.
  double widthOf(List<ShapedGlyph> glyphs) {
    var width = 0.0;
    for (var i = 0; i < glyphs.length; i++) {
      final glyph = glyphs[i];
      width += glyph.advance * size / 1000 + characterSpacing;
      if (glyph.text == ' ') width += wordSpacing;
      if (i < glyphs.length - 1) width += glyph.kerning * size / 1000;
    }
    return width * horizontalScaling / 100;
  }

  /// The width of [text] set in this style, in points.
  double measure(String text) => widthOf(shape(text));

  /// [text] as glyphs of this style's font (a right-to-left run with
  /// [rightToLeft]: in visual order).
  List<ShapedGlyph> shape(String text, {bool rightToLeft = false}) {
    if (font case final OpenTypeTextFont font) {
      if (vertical && !rightToLeft) return _shapeVertical(font, text);
      // (In a language the font has a system for: shaped in full.)
      if (language case final language?
          when hasLanguageSystem(font.font, language)) {
        return shapeInLanguage(
          font.font,
          text,
          language: language,
          kerning: kerning,
          ligatures: ligatures,
          features: features,
          rightToLeft: rightToLeft,
        );
      }
    }
    return font.shape(
      text,
      kerning: kerning,
      ligatures: ligatures,
      features: features,
      rightToLeft: rightToLeft,
    );
  }

  /// [text] for a vertical line: its runs of upright characters shaped
  /// top to bottom, the others across (to lie on their side); numbers of
  /// up to [combineDigits] digits, or all of it with [combineUpright], set
  /// across as one upright character.
  List<ShapedGlyph> _shapeVertical(OpenTypeTextFont font, String text) {
    if (combineUpright && text.isNotEmpty) {
      return _combined(font, text) ?? _shapeSplit(font, text);
    }
    if (combineDigits <= 0 || !text.contains(_digit)) {
      return _shapeSplit(font, text);
    }
    final out = <ShapedGlyph>[];
    var from = 0;
    for (final m in _number.allMatches(text)) {
      final digits = m[0]!;
      if (digits.length > combineDigits) continue;
      final combined = _combined(font, digits);
      if (combined == null) continue;
      if (m.start > from) {
        out.addAll(_shapeSplit(font, text.substring(from, m.start)));
      }
      out.addAll(combined);
      from = m.end;
    }
    if (from < text.length) out.addAll(_shapeSplit(font, text.substring(from)));
    return out;
  }

  /// [text] set across the line as one upright character, an em along
  /// it, centred across the column: in the narrowest forms the font has
  /// for its length (full-width alone, half-width two, third-width three,
  /// quarter-width four); null where it is still wider than an em.
  List<ShapedGlyph>? _combined(OpenTypeTextFont font, String text) {
    final count = text.runes.length;
    final form = switch (count) {
      1 => 'fwid',
      2 => 'hwid',
      3 => 'twid',
      _ => 'qwid',
    };
    final glyphs = shapeInLanguage(
      font.font,
      text,
      language: language ?? '',
      kerning: false,
      ligatures: ligatures,
      features: {...features, form},
    );
    final width = glyphs.fold<double>(0, (sum, g) => sum + g.advance);
    if (glyphs.isEmpty || width > 1050) return null;
    // (The baseline where an ideograph's em box puts it: the font's
    // vertical origin, an ideographic space's.)
    final origin =
        shapeUpright(
          font.font,
          '\u3000',
          kerning: false,
        ).firstOrNull?.yOffset ??
        -font.ascender;
    final out = <ShapedGlyph>[];
    var x = -width / 2;
    for (final (i, g) in glyphs.indexed) {
      out.add(
        ShapedGlyph.positioned(
          g.id,
          g.text,
          i == glyphs.length - 1 ? 1000 : 0,
          xOffset: x + g.xOffset,
          yOffset: origin + g.yOffset,
          upright: true,
        ),
      );
      x += g.advance;
    }
    return out;
  }

  /// [text] for a vertical line, split into its upright and sideways runs.
  List<ShapedGlyph> _shapeSplit(OpenTypeTextFont font, String text) {
    final out = <ShapedGlyph>[];
    final run = StringBuffer();
    bool? upright;
    void flush() {
      if (run.isEmpty) return;
      final part = run.toString();
      run.clear();
      out.addAll(
        upright!
            ? shapeUpright(
                font.font,
                part,
                kerning: kerning,
                features: features,
                language: language,
              )
            : language != null && hasLanguageSystem(font.font, language!)
            ? shapeInLanguage(
                font.font,
                part,
                language: language!,
                kerning: kerning,
                ligatures: ligatures,
                features: features,
              )
            : font.shape(
                part,
                kerning: kerning,
                ligatures: ligatures,
                features: features,
              ),
      );
    }

    for (final c in text.runes) {
      // (A mark or joiner goes with the character before it.)
      final stands = run.isNotEmpty && (isMark(c) || c == 0x200d)
          ? upright!
          : switch (verticalOrientation(c)) {
              VerticalOrientation.rotated => false,
              _ => true,
            };
      if (stands != upright) {
        flush();
        upright = stands;
      }
      run.writeCharCode(c);
    }
    flush();
    return out;
  }

  /// Whether the character at [index] of [text] is set across the line,
  /// upright, in this style: with [combineUpright], or a digit of a
  /// number of up to [combineDigits] digits, in vertical text.
  bool combinesAt(String text, int index) {
    if (!vertical || index < 0 || index >= text.length) return false;
    if (combineUpright) return true;
    if (combineDigits <= 0 || !_digit.hasMatch(text[index])) return false;
    for (final m in _number.allMatches(text)) {
      if (m.start <= index && index < m.end) {
        return m.end - m.start <= combineDigits;
      }
    }
    return false;
  }

  static final RegExp _digit = RegExp('[0-9]');

  /// A number standing alone: digits not inside a word or a longer
  /// number (`1,000`, `3.14`, `A4`).
  static final RegExp _number = RegExp(
    '(?<![0-9A-Za-z.,])[0-9]+(?![0-9A-Za-z]|[.,][0-9])',
  );

  /// [text], a line's, as glyphs in visual order: its runs of one
  /// direction ordered by the Unicode Bidirectional Algorithm (UAX #9) in
  /// a line whose base direction is [rightToLeft] or not, each shaped in
  /// its direction. Text without right-to-left characters is shaped as
  /// [shape] shapes it.
  List<ShapedGlyph> shapeBidi(String text, {bool rightToLeft = false}) {
    if (!rightToLeft && !hasRightToLeft(text)) return shape(text);
    final bidi = BidiText(
      text,
      direction: rightToLeft ? TextDirection.rtl : TextDirection.ltr,
    );
    return [
      for (final (from, to, level) in bidi.visualRuns(0, text.length))
        ...shape(text.substring(from, to), rightToLeft: level.isOdd),
    ];
  }
}

/// Something to draw on: paths, painted or clipping, text, and the
/// graphics state (a stack, as in PDF and PostScript), in points with y up.
///
/// Fonts and images belong to a backend: a canvas sets the text of the
/// fonts its backend made, and a backend's graphics paint only on its own
/// canvas.
abstract interface class Canvas {
  // Graphics state.

  /// Saves the graphics state.
  void save();

  /// Restores the graphics state saved last.
  void restore();

  /// Runs [draw] between [save] and [restore].
  void saved(void Function() draw);

  /// Transforms the coordinate system by [matrix].
  void transform(Matrix matrix);

  /// Moves the origin to ([x], [y]).
  void translate(double x, double y);

  /// Scales by [x] horizontally and [y] (default [x]) vertically.
  void scale(double x, [double? y]);

  /// Rotates counterclockwise by [degrees].
  void rotate(double degrees);

  /// The width of stroked lines.
  void setLineWidth(double width);

  /// The shape of line ends.
  void setLineCap(LineCap cap);

  /// The shape of corners.
  void setLineJoin(LineJoin join);

  /// The miter limit.
  void setMiterLimit(double limit);

  /// The dash pattern: alternating dash and gap lengths starting at
  /// [phase]; empty for solid lines.
  void dash(List<double> pattern, [double phase = 0]);

  /// The color of fills, text included.
  void setFillColor(Color color);

  /// The color of strokes.
  void setStrokeColor(Color color);

  /// The opacity of fills and of strokes (0 transparent, 1 opaque).
  void opacity({double? fill, double? stroke});

  /// The blend mode.
  void setBlendMode(BlendMode mode);

  // Paths.

  /// Starts a subpath at ([x], [y]).
  void moveTo(double x, double y);

  /// A line to ([x], [y]).
  void lineTo(double x, double y);

  /// A cubic Bézier curve to ([x3], [y3]) with control points ([x1],
  /// [y1]) and ([x2], [y2]).
  void curveTo(
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
  );

  /// Closes the subpath.
  void closePath();

  /// A rectangle.
  void rect(Rect rect);

  /// A rectangle with corners rounded to [radius].
  void roundedRect(Rect rect, double radius);

  /// An ellipse centered on ([cx], [cy]) with radii [rx] and [ry].
  void ellipse(double cx, double cy, double rx, double ry);

  /// A circle centered on ([cx], [cy]) of [radius].
  void circle(double cx, double cy, double radius);

  /// Fills the path (with the even-odd rule when [evenOdd]).
  void fill({bool evenOdd = false});

  /// Strokes the path.
  void stroke();

  /// Fills, then strokes the path.
  void fillAndStroke({bool evenOdd = false});

  /// Intersects the clipping path with the path, without painting it.
  void clip({bool evenOdd = false});

  /// Ends the path without painting it.
  void endPath();

  // Marked content.

  /// Begins a sequence of content tagged [tag] (as PDF's marked content),
  /// to end with [endMarkedContent]. With [actualText], the sequence reads
  /// as that text when text is extracted, copied or read aloud: an empty
  /// one leaves decorative glyphs out.
  void beginMarkedContent(String tag, {String? actualText});

  /// Ends the sequence [beginMarkedContent] began.
  void endMarkedContent();

  // Text.

  /// Draws [text] in [style] with its baseline starting at ([x], [y]);
  /// returns its width.
  double text(String text, double x, double y, TextStyle style);

  /// Draws shaped [glyphs] of [style]'s font with the baseline starting
  /// at ([x], [y]); returns their width.
  ///
  /// [text], where given, is what the glyphs stand for in the order they
  /// are drawn (a right-to-left run's characters reversed, as text drawn
  /// in visual order is): a backend mapping glyphs back to text (a PDF's
  /// ToUnicode) gives it to glyphs its map can't read as it (a glyph
  /// shared by several letters, one standing for no text, marks moved
  /// onto their base).
  double glyphs(
    List<ShapedGlyph> glyphs,
    double x,
    double y,
    TextStyle style, {
    String? text,
  });
}
