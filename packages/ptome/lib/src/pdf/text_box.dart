/// Text laid out as Prawn 2.4 lays it out, with asciidoctor-pdf 2.3.27's
/// extensions: fragments wrapped line by line (Prawn's `LineWrap`, with
/// word joiners), each line as tall as its tallest fragment, baselines
/// placed with the leading and the gaps asciidoctor-pdf passes,
/// justification by word spacing, font fallback per glyph. A
/// [TextBox] is plain_pdf custom content: the layout gives it the room
/// left on the page and it places the lines that fit.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:plain_pdf/plain_pdf.dart';
import 'package:plain_svg/plain_svg.dart';
import 'package:plain_typesetting/plain_typesetting.dart';
import 'package:plain_unicode/plain_unicode.dart'
    show
        VerticalOrientation,
        emojiSequenceLength,
        hasRightToLeft,
        isDefaultIgnorable,
        isMark,
        verticalOrientation;
import 'package:ptome/src/cursor.dart';
import 'package:ptome/src/logging.dart';
import 'package:ptome/src/pdf/fonts.dart';
import 'package:ptome/src/pdf/markup.dart';
import 'package:ptome/src/pdf/math.dart';
import 'package:ptome/src/pdf/ruby.dart';
import 'package:ptome/src/pdf/svg_size.dart';
import 'package:ptome/src/pdf/theme.dart';
import 'package:ptome/src/pdf/warichu.dart';

const String _zwsp = '​';
const String _shy = '­';
const String _nul = '\u0000';

/// The font state text starts from (Prawn's current font, size and
/// color, as `theme_font` sets them).
final class TextState {
  /// The state of [family] in [style] at [size] points, in [color].
  const new({
    required this.family,
    required this.size,
    this.style = 'normal',
    this.color,
    this.kerning = true,
    this.characterSpacing = 0,
    this.features = const {},
  });

  /// The OpenType features the text is set with (the modern engine's:
  /// `onum` for old-style numerals...).
  final Set<String> features;

  /// The space added between characters (Prawn's `character_spacing`).
  final double characterSpacing;

  /// The font family.
  final String family;

  /// The font style.
  final String style;

  /// The size, in points.
  final double size;

  /// The default color of the fragments.
  final ThemeColor? color;

  /// Whether text is kerned.
  final bool kerning;
}

/// How a block of text is laid out (the options asciidoctor-pdf passes to
/// Prawn's `text`).
final class TextLayout {
  /// Text aligned by [align], lines [leading] apart, the first line
  /// [initialGap] below the top, [paddingBottom] below the last line.
  const new({
    this.align = 'left',
    this.mirrored = true,
    this.rightToLeft = false,
    this.vertical = false,
    this.flipped = false,
    this.language,
    this.leading = 0,
    this.initialGap = 0,
    this.paddingBottom = 0,
    this.finalGap = false,
    this.trailingLineGap = false,
    this.singleLine = false,
    this.shrinkToFit = false,
    this.indentFirstLine = 0,
    this.normalizeLineHeight = false,
    this.forceJustify = false,
    this.orphans = 1,
    this.widows = 1,
    this.wrapIndent,
    this.wrapMarker = false,
    this.at,
    this.skew,
    this.overhang = 0,
    this.capLines = false,
    this.justifyWidest = false,
    this.alignLast,
    this.dropLines = 0,
    this.dropIndent = 0,
    this.lineInsets = const [],
  });

  /// The room taken from each line's width, by line (of this piece of the
  /// text): at its left and at its right (beside a float's outline).
  final List<(double, double)> lineInsets;

  /// This layout with [insets] taken from its lines' widths.
  TextLayout withLineInsets(List<(double, double)> insets) =>
      copyWith(lineInsets: insets);

  /// This layout with the values given instead of its own.
  TextLayout copyWith({
    double? paddingBottom,
    bool? finalGap,
    bool? singleLine,
    bool? shrinkToFit,
    bool? forceJustify,
    List<(double, double)>? lineInsets,
  }) => TextLayout(
    align: align,
    mirrored: mirrored,
    rightToLeft: rightToLeft,
    vertical: vertical,
    flipped: flipped,
    language: language,
    leading: leading,
    initialGap: initialGap,
    paddingBottom: paddingBottom ?? this.paddingBottom,
    finalGap: finalGap ?? this.finalGap,
    trailingLineGap: trailingLineGap,
    singleLine: singleLine ?? this.singleLine,
    shrinkToFit: shrinkToFit ?? this.shrinkToFit,
    indentFirstLine: indentFirstLine,
    normalizeLineHeight: normalizeLineHeight,
    forceJustify: forceJustify ?? this.forceJustify,
    orphans: orphans,
    widows: widows,
    wrapIndent: wrapIndent,
    wrapMarker: wrapMarker,
    at: at,
    skew: skew,
    overhang: overhang,
    capLines: capLines,
    justifyWidest: justifyWidest,
    alignLast: alignLast,
    dropLines: dropLines,
    dropIndent: dropIndent,
    lineInsets: lineInsets ?? this.lineInsets,
  );

  /// How many lines at the start of the text are set [dropIndent] in, to
  /// make room for a drop (a large chapter number or initial beside
  /// them).
  final int dropLines;

  /// How far the first [dropLines] lines are set in.
  final double dropIndent;

  /// Where a justified paragraph's lines that aren't justified (its last
  /// line) go: `center` or `right`, as CSS's `text-align-last`; left when
  /// null.
  final String? alignLast;

  /// Whether justified lines are set to the width of the paragraph's
  /// widest line (overfull lines shrunk to the room) rather than to the
  /// room (a paragraph in a block sized to its content).
  final bool justifyWidest;

  /// Lines set from their cap heights (CSS's `text-box-edge: cap
  /// alphabetic`): each line's box from its tallest cap height to its
  /// baseline ([leading] is the space between boxes), the first line's
  /// cap height at the top and the last ending at its baseline.
  final bool capLines;

  /// How far punctuation and dashes at a line's end hang into the margin:
  /// a factor of the fraction of each character's width the line may
  /// stretch into (0, none; 1, microtype's default protrusion).
  final double overhang;

  /// The text sheared as one block about its last baseline (a heading's
  /// skew): each glyph slanted by this ratio (the tangent of the
  /// angle, positive leaning right), each line shifted right by it times
  /// its height above the last line's baseline.
  final double? skew;

  /// `left`, `center`, `right` or `justify`.
  final String align;

  /// The extra space between lines.
  final double leading;

  /// The space above the first line of each piece.
  final double initialGap;

  /// The space below the last line.
  final double paddingBottom;

  /// Whether the line gap and the leading follow the last line too.
  final bool finalGap;

  /// Whether the line gap alone follows the last line (as prawn-table
  /// measures a cell's text).
  final bool trailingLineGap;

  /// Whether [align] is the theme's, mirrored in a right-to-left document
  /// (`left` the start), rather than the page's own sides (running content,
  /// whose columns the page layout places).
  final bool mirrored;

  /// Whether the text is written right to left (its block's direction, or
  /// the document's, when the box was made).
  final bool rightToLeft;

  /// Whether the text is set in vertical lines (`page_writing_mode`):
  /// its Han, kana and full-width punctuation upright, the rest on its
  /// side, in the page's turned frame.
  final bool vertical;

  /// Whether the vertical text is laid out in a mirrored frame (a
  /// vertical-lr block's on a horizontal page; a vertical-lr page's text is
  /// [TextContext.mirroredFrame]): drawn mirrored back.
  final bool flipped;

  /// The text's language (BCP 47), unless a fragment says otherwise: the
  /// block's or the document's.
  final String? language;

  /// Whether only the first line is laid out (the rest is left over, the
  /// line gap and the leading following the line).
  final bool singleLine;

  /// Whether the font size shrinks (half a point at a time, to 5) until
  /// all the text fits (Prawn's `overflow: :shrink_to_fit`).
  final bool shrinkToFit;

  /// The indent of the first line.
  final double indentFirstLine;

  /// This layout with no gap above the first line.
  TextLayout get withoutInitialGap => TextLayout(
    align: align,
    mirrored: mirrored,
    rightToLeft: rightToLeft,
    vertical: vertical,
    flipped: flipped,
    language: language,
    leading: leading,
    paddingBottom: paddingBottom,
    finalGap: finalGap,
    trailingLineGap: trailingLineGap,
    singleLine: singleLine,
    shrinkToFit: shrinkToFit,
    indentFirstLine: indentFirstLine,
    normalizeLineHeight: normalizeLineHeight,
    forceJustify: forceJustify,
    orphans: orphans,
    widows: widows,
  );

  /// Whether each line is at least as tall as the base font.
  final bool normalizeLineHeight;

  /// Whether the last line is justified too.
  final bool forceJustify;

  /// The fewest lines the text leaves at the bottom of a region when it
  /// goes on in the next (1: no rule).
  final int orphans;

  /// The fewest lines the text takes to the top of the next region when
  /// it goes on there (1: no rule).
  final int widows;

  /// How far past a line's own indentation the lines it wraps onto start
  /// (a hanging indent for code), or null to start them at the left.
  final double? wrapIndent;

  /// Whether a line that wraps is marked with a return arrow past its
  /// end (for code).
  final bool wrapMarker;

  /// Where the text's block starts in the source, for messages.
  final Cursor? at;
}

/// What the text needs from the conversion: fonts, the root font size,
/// fallback fonts, and where messages go.
final class TextContext {
  /// A context.
  new({
    required this.fonts,
    required this.rootSize,
    this.fallbacks = const [],
    this.images,
    this.boundsHeight = double.infinity,
    this.decorationWidth = 1,
    this.lineBreaking = LineBreaking.auto,
    this.hyphenRepetition = HyphenRepetition.none,
    this.typographicScripts = false,
    this.labels,
    this.capsTracking = 0,
    this.expansion = 0,
    this.kashida = 0,
    this.mirroredFrame = false,
    this.wordSpace = 1,
    this.engine,
    this.maxHyphenRun,
    this.lastLineMin = 0,
    this.interlineGlue = false,
    this.languageFallback,
    this.emojiFallback,
    this.combineDigits = 0,
    this.invisibleIgnorables = false,
    this.fallbackMetrics = true,
    this.lowercaseSmallCaps = false,
    LoggerBase? logger,
  }) : logger = logger ?? LoggerManager.logger;

  /// This context without its [engine]: texts set in the box's own lines.
  late final TextContext withoutEngine = engine == null
      ? this
      : TextContext(
          fonts: fonts,
          rootSize: rootSize,
          fallbacks: fallbacks,
          images: images,
          boundsHeight: boundsHeight,
          decorationWidth: decorationWidth,
          lineBreaking: lineBreaking,
          hyphenRepetition: hyphenRepetition,
          typographicScripts: typographicScripts,
          labels: labels,
          capsTracking: capsTracking,
          expansion: expansion,
          kashida: kashida,
          mirroredFrame: mirroredFrame,
          wordSpace: wordSpace,
          maxHyphenRun: maxHyphenRun,
          lastLineMin: lastLineMin,
          interlineGlue: interlineGlue,
          languageFallback: languageFallback,
          emojiFallback: emojiFallback,
          combineDigits: combineDigits,
          invisibleIgnorables: invisibleIgnorables,
          fallbackMetrics: fallbackMetrics,
          lowercaseSmallCaps: lowercaseSmallCaps,
          logger: logger,
        );

  /// How much wider or narrower the letters of a justified line may be set
  /// (font expansion: `base_font_expansion`, modern engine).
  final double expansion;

  /// How far each word of a justified line of Arabic may be lengthened by
  /// kashida before the spaces widen, in em (`base_kashida`, modern
  /// engine): 0 for none.
  final double kashida;

  /// In vertical text, the most digits a number may have to be set across
  /// the line, upright (tate-chu-yoko, `base_text_combine_upright`); 0 for
  /// none.
  final int combineDigits;

  /// Whether vertical text is laid out in a mirrored frame (vertical-lr
  /// pages): drawn mirrored back ([TextStyle.flipped]).
  final bool mirroredFrame;

  /// What sets a text in the modern engine (plain_typesetting's paragraph
  /// as content, which [TextBox] places and measures by): null for a text
  /// the engine doesn't set as this box does, or in the compatibility
  /// mode, where the box sets its own lines.
  final CustomContent? Function(TextBox text)? engine;

  /// Whether lines are the text's own font height and the leading apart,
  /// whatever fonts they mix, unless a line's text and the depth of the
  /// line above don't fit that (TeX's interline glue: modern engine),
  /// rather than each line its tallest font's height down from the one
  /// above (Prawn's).
  final bool interlineGlue;

  /// The width of the spaces between words in the engine's paragraphs, as
  /// a share of the face's own (`base_word_spacing`: a dictionary's 72%).
  final double wordSpace;

  /// The most hyphenated lines in a row (`base_hyphenate_limit_lines`).
  final int? maxHyphenRun;

  /// The least a paragraph's last line fills of its measure
  /// (`base_last_line_min_width`): no runts where there is another way.
  final double lastLineMin;

  /// The tracking of text set in capitals or small capitals, in ems (the
  /// modern engine's `caps_letter_spacing`; microtype's 0.05 em).
  final double capsTracking;

  /// Whether the modern engine sets superscripts and subscripts in the
  /// font's own glyphs for them (its `sups` and `subs` features) at the
  /// text's size, when it has them for every character, rather than
  /// smaller and shifted (true superior and inferior figures).
  final bool typographicScripts;

  /// The text of the label of a fragment's key ([Fragment.label]), as the
  /// layout has it now (null keeps the fragment's text).
  final String? Function(String key)? labels;

  /// Reads the inline image at a path in a format, or returns null (with
  /// the reason) when it can't.
  final (Graphic?, String?) Function(String path, String? format)? images;

  /// The height of the content area (the most an inline image may be).
  final double boundsHeight;

  /// The width of underlines and strike-throughs that don't set one (the
  /// theme's `base_text_decoration_width`).
  final double decorationWidth;

  /// How the modern engine breaks lines.
  final LineBreaking lineBreaking;

  /// Whether a line broken after a compound's hyphen starts with it again
  /// (the document's language: Portuguese, Spanish...).
  final HyphenRepetition hyphenRepetition;

  /// The fonts.
  final FontCatalog fonts;

  /// The root font size (`rem`).
  final double rootSize;

  /// The fallback font families.
  final List<String> fallbacks;

  /// The family a character none of the text's fonts and [fallbacks] has
  /// is looked for in last, by the text's language (BCP 47) and its font's
  /// family (the installed Noto CJK face of the language's region: modern
  /// engine), or null.
  final String? Function(String? language, String family)? languageFallback;

  /// The family an emoji sequence no font of the text's has in color is
  /// set in (the installed Noto Color Emoji: modern engine), or null.
  final String? Function()? emojiFallback;

  /// Whether a default-ignorable character no font has (a bidirectional
  /// isolate, a joiner) stays in its run, invisible as it is, unwarned of
  /// (modern engine), rather than looked for in the fallback fonts and
  /// warned of, as Asciidoctor PDF does.
  final bool invisibleIgnorables;

  /// Whether text set in a fallback font counts that font's metrics
  /// toward its line's height (`font_fallback_metrics: own`, the
  /// default), or the text's own font's (`base`).
  final bool fallbackMetrics;

  /// Whether small capitals a font lacks are made from the text's
  /// lowercase letters alone, its capitals kept at full size
  /// (`base_small_caps_synthesis: lowercase`), rather than the whole text
  /// in smaller capitals (the default).
  final bool lowercaseSmallCaps;

  /// Where warnings go.
  final LoggerBase logger;

  final Map<int, bool> _warnedMissing = {};
}

/// A fragment ready to wrap: its text and its resolved formatting.
final class _Item {
  new(this.text, this.format, {this.defaultColor = false});

  String text;
  final _Format format;

  /// Whether the fragment's color is the text's (not its own).
  final bool defaultColor;
  bool excludeTrailingWhiteSpace = false;
  bool normalizedSoftHyphen = false;

  _Item copy({String? text}) =>
      _Item(text ?? this.text, format, defaultColor: defaultColor)
        ..excludeTrailingWhiteSpace = excludeTrailingWhiteSpace
        ..normalizedSoftHyphen = normalizedSoftHyphen;
}

/// The size of small capitals a font lacks, of the text's.
const double _smallCapitalScale = 0.8;

/// Runs of lowercase letters (group 1) and of everything else.
final RegExp _caseRx = RegExp(r'(\p{Ll}+)|[^\p{Ll}]+', unicode: true);

/// A fragment's formatting with its font resolved.
final class _Format {
  new(
    this.fragment,
    this.font,
    this.size, {
    this.image,
    this.features = const {},
    this.smallCapitals = false,
    this.typographic = false,
    this.tracking = 0,
  });

  final Fragment fragment;
  final FontFace font;
  final double size;

  /// The space after each character, in points (half of it before the
  /// first and after the last: microtype's outer kerning).
  final double tracking;

  /// This format with [tracking].
  _Format _tracked(double tracking) => _Format(
    fragment,
    font,
    size,
    image: image,
    features: features,
    smallCapitals: smallCapitals,
    typographic: typographic,
    tracking: tracking,
  );

  /// This format's small capitals at full size: the capitals of text
  /// set in [smallCapitals].
  _Format get _full => _Format(
    fragment,
    font,
    size / _smallCapitalScale,
    image: image,
    features: features,
    typographic: typographic,
    tracking: tracking,
  );

  /// Whether a superscript or subscript is set in the font's glyphs for
  /// it (on the baseline, at the text's size).
  final bool typographic;

  /// The OpenType features the text is set with.
  final Set<String> features;

  /// Whether the text is set in capitals, smaller, for small capitals the
  /// font lacks.
  final bool smallCapitals;

  /// The inline image the fragment is, once arranged.
  final _Image? image;

  bool get subscript =>
      fragment.styles?.contains(FragmentStyle.subscript) ?? false;
  bool get superscript =>
      fragment.styles?.contains(FragmentStyle.superscript) ?? false;
}

/// An inline image arranged on a line: the room it takes, the size it is
/// drawn at, and the metrics it gives its line.
final class _Image {
  const new(
    this.graphic, {
    required this.width,
    required this.height,
    required this.drawWidth,
    required this.drawHeight,
    this.ascender,
    this.descender,
    this.lineHeightIncreased = false,
    this.mathDepth,
  });

  final Graphic graphic;
  final double width;
  final double height;
  final double drawWidth;
  final double drawHeight;
  final double? ascender;
  final double? descender;
  final bool lineHeightIncreased;

  /// A formula's depth below the baseline (it stands on the baseline).
  final double? mathDepth;
}

/// The prefix of the anchors that side notes are set level with (the top
/// of the text they are in rather than its baseline).
const sideNoteAnchorPrefix = '_side_';

/// The prefix of the anchors of labels hung left of their line (a poem's
/// verse numbers): placed at the text's baseline.
const hangAnchorPrefix = '_hang_';

/// A fragment as printed on a line.
final class _Printed {
  new(
    this.text,
    this.format,
    this.width,
    this.wordSpacing,
    this.spaces, {
    this.scale = 1,
  });

  String text;
  final _Format format;
  double width;
  final double wordSpacing;
  final int spaces;

  /// How much wider its letters are set (font expansion).
  final double scale;
  double left = 0;
  double baseline = 0;

  double get ascender => format.fragment.isMarker
      ? 0
      : format.image?.ascender ?? format.font.ascenderAt(format.size);
  double get descender =>
      format.image?.descender ?? format.font.descenderAt(format.size);
  double get yOffset => format.typographic
      ? 0
      : format.subscript
      ? -descender
      : format.superscript
      ? 0.85 * ascender
      : 0;
}

/// A line placed in a piece: its fragments, positioned (x from the left
/// edge, baseline down from the piece's top).
final class _Line {
  new(this.fragments);

  final List<_Printed> fragments;

  /// Whether the line wraps: the text of its line goes on in the next.
  bool wrapped = false;

  /// Whether the line ends with a line break of the source.
  bool hard = false;
}

/// Text laid out in lines (Knuth and Plass's line breaking, or for code
/// one line at a time with a hanging indent), as plain_pdf custom content.
final class TextBox implements ShapedContent, BaselineContent, JoinableContent {
  /// The text of [fragments] (from the markup) starting from [state],
  /// laid out by [layout].
  factory(
    List<Fragment> fragments,
    TextState state,
    TextLayout layout,
    TextContext context,
  ) {
    final items = <_Item>[];
    for (final fragment in fragments) {
      final defaultColor = fragment.color == null;
      final copy = fragment.copy()..color ??= state.color;
      for (final run in _withFallbacks(
        copy,
        state,
        context,
        language: layout.language,
      )) {
        final format = _resolve(run, state, context);
        final text = format.font.normalize(run.text);
        // (Small capitals the font lacks: the text in smaller capitals;
        // with `base_small_caps_synthesis: lowercase`, its lowercase
        // letters alone, its capitals as they are, as CSS synthesizes
        // them; BUG-mpp8wr.)
        final parts = format.smallCapitals && context.lowercaseSmallCaps
            ? [
                for (final m in _caseRx.allMatches(text))
                  if (m[1] != null)
                    (m[0]!.toUpperCase(), format)
                  else
                    (m[0]!, format._full),
              ]
            : [(format.smallCapitals ? text.toUpperCase() : text, format)];
        // One item per line of the fragment (Prawn's `format_array=`), its
        // words in capitals apart when they are tracked.
        for (final (part, partFormat) in parts) {
          for (final m in _linesRx.allMatches(part)) {
            for (final (piece, pieceFormat) in _capitalWords(
              m[0]!,
              partFormat,
              context,
            )) {
              items.add(_Item(piece, pieceFormat, defaultColor: defaultColor));
            }
          }
        }
      }
    }
    return TextBox._(items, state, layout, context, first: true);
  }

  new _(
    this._items,
    this._state,
    this._layout,
    this._context, {
    required this.first,
    this.continuedIndent,
    bool? startsLine,
  }) : startsLine = startsLine ?? first;

  /// Whether its first line starts a line of the source (the text before
  /// it, if any, ended with a line break): logical line numbers count it.
  final bool startsLine;

  /// This text with its first line going on from the line before it: a
  /// verse line shared between two speakers, counted once by logical line
  /// numbers.
  TextBox continuing() => TextBox._(
    _items,
    _state,
    _layout,
    _context,
    first: first,
    continuedIndent: continuedIndent,
    startsLine: false,
  );

  final List<_Item> _items;
  final TextState _state;
  final TextLayout _layout;
  final TextContext _context;

  /// The text's style.
  TextState get state => _state;

  /// The text's layout.
  TextLayout get layout => _layout;

  /// Whether this is the first piece of the text (its first line is
  /// indented).
  final bool first;

  /// The indent of the first line when it goes on with a line that
  /// wrapped at the end of the text before (see [TextLayout.wrapIndent]).
  final double? continuedIndent;

  /// Whether there is no text.
  bool get isEmpty => _items.isEmpty;

  /// Whether the text has labels the layout gives as the pages are laid
  /// out (a footnote's number on its page): a text the box places, which
  /// labels it as it's placed, not one the engine's paragraph box sets.
  bool get hasLabels =>
      _context.labels != null &&
      _items.any((item) => item.format.fragment.label != null);

  /// Whether the text has an inline image as wide as a share of the
  /// width it's set in (its `engineContent` then at a given width).
  bool get hasRelativeImages => _items.any(
    (item) =>
        item.format.fragment.imagePath != null &&
        item.format.image == null &&
        (item.format.fragment.imageWidth ?? '100%').contains('%'),
  );

  /// This text set in the box's own lines, never the engine's (for what
  /// builds on the box's line breaking: a first line of its own style).
  TextBox get boxOnly => TextBox._(
    _items,
    _state,
    _layout,
    _context.withoutEngine,
    first: first,
    continuedIndent: continuedIndent,
    startsLine: startsLine,
  );

  /// [engine]'s text placed as the box places its own: shrunk half a
  /// point at a time (to 5) until it all fits, with [TextLayout.shrinkToFit];
  /// its first line alone, with [TextLayout.singleLine].
  CustomPlacement? _enginePlace(
    CustomContent engine,
    double width,
    double available, {
    required bool atTop,
  }) {
    // (A single line: the first alone, what doesn't fit on it left out, as
    // the box lays out only one; shrunk until nothing is, where it
    // shrinks.)
    CustomPlacement? once(CustomContent content) {
      if (_layout.singleLine && content is LinedContent) {
        if (content.lineCount(width) == 0) {
          return content.place(width, available, atTop: atTop);
        }
        if (!atTop && content.linesThatFit(width, available) < 1) return null;
        return content.placeLines(width, 1);
      }
      return content.place(width, available, atTop: atTop);
    }

    CustomPlacement? single(CustomPlacement? placed) {
      if (placed == null || !_layout.singleLine || placed.rest == null) {
        return placed;
      }
      return CustomPlacement(
        height: placed.height,
        paint: placed.paint,
        anchors: placed.anchors,
        lines: placed.lines,
      );
    }

    if (!_layout.shrinkToFit) return single(once(engine));
    var box = this;
    var content = engine;
    var size = _state.size;
    while (true) {
      final placed = once(content);
      if (size <= 5 || (placed != null && placed.rest == null)) {
        return single(placed);
      }
      size = math.max(size - 0.5, 5);
      box = box.resized(size);
      final next = box._engine;
      if (next == null) {
        return box._placeShrinking(width, available, atTop: atTop);
      }
      content = next;
    }
  }

  /// The width [text] in [format] takes as the box sets it in a slot: the
  /// fragment's own width, or the text's and its border offset on either
  /// side (the wrap's widths, for the engine).
  double _slotWidth(String text, _Format format) {
    final fragment = format.fragment;
    var width = switch (fragment.width) {
      final String fixed when fixed.endsWith('em') =>
        _Wrap._toF(fixed) * format.size,
      final String fixed => strToPoints(fixed),
      null => () {
        final bare = text.replaceAll(RegExp('[\u0000\u00ad]'), '');
        final tracked =
            format.font.widthOf(
              bare,
              format.size,
              kerning: _state.kerning,
              features: format.features,
              vertical: _layout.vertical,
              combineDigits: _layout.vertical ? _context.combineDigits : 0,
            ) +
            format.tracking * bare.runes.length;
        final count = bare.runes.length;
        final spacing = _state.characterSpacing;
        return spacing == 0 || count < 2
            ? tracked
            : tracked + spacing * (count - 1);
      }(),
    };
    if (fragment.borderOffset case final offset?) width += offset * 2;
    return width;
  }

  /// The text as the engine sets it ([TextContext.engine]), which places
  /// and measures it, or null for this box's own lines.
  CustomContent? get _engine {
    final factory = _context.engine;
    if (_items.isEmpty || factory == null) return null;
    // (Labelled as the layout labels it now: a footnote's number on its
    // page.)
    _relabel();
    return (_engines[_labelState()] ??= (factory(this),)).$1;
  }

  final Map<String, (CustomContent?,)> _engines = {};

  /// The text as the engine's inline content (FEAT-n1bkgf: text set by
  /// plain_typesetting's paragraphs rather than this box's own lines):
  /// each item a text run in its resolved font, size, tracking, features,
  /// color, decorations, link and anchor, a superscript or subscript
  /// raised or lowered as this box sets it. Null when the text has what
  /// a run can't carry yet (an inline image or formula, a background or
  /// border, small capitals the font lacks), for the box to set it.
  List<InlineContent>? engineContent({double width = double.infinity}) =>
      _engineRuns(width: width)?.runs;

  /// [engineContent], and where each character of each run comes from: its
  /// item and the offset in the item's text.
  ({List<InlineContent> runs, List<List<(int, int)>> sources})? _engineRuns({
    double width = double.infinity,
  }) {
    final runs = <InlineContent>[];
    final sources = <List<(int, int)>>[];
    final images = _context.images;
    int? lastImage;
    for (final (index, item) in _items.indexed) {
      var format = item.format;
      final fragment = format.fragment;
      // (An inline image or formula, which the box arranges as it lays out
      // its text: arranged here at the size it asks for, as the box does
      // unless that is a share of the width.)
      if (fragment.imagePath case final path? when format.image == null) {
        if (images == null) return null;
        final id = fragment.objectId;
        if (id != null && id == lastImage) continue;
        lastImage = id;
        final (graphic, _) = images(path, fragment.imageFormat);
        if (graphic == null) return null;
        // (One a share of the width: arranged at the width it's set in.)
        if (graphic is! InlineMath &&
            graphic is! InlineRuby &&
            graphic is! InlineWarichu &&
            (fragment.imageWidth ?? '100%').contains('%') &&
            width.isInfinite) {
          return null;
        }
        format = _arrangeImage(item, graphic, width).format;
      }
      // (A background or border drawn around the text, with no room of
      // its own around it: the engine's decoration.)
      final decorated =
          fragment.backgroundColor != null || fragment.borderWidth != null;
      // (Text the layout labels, a footnote's number on its page: the box
      // relabels it as the pages are laid out.)
      if (fragment.callbacks?.any(
            (callback) =>
                callback == FragmentCallback.inlineImage &&
                format.image == null,
          ) ??
          false) {
        return null;
      }
      // (Text the box sets in a slot, aligned there: a fixed width, or its
      // own and its border offset on either side, as a key's label is. A
      // slot of words and spaces, each as wide, stays the box's.)
      final slotted =
          fragment.width != null ||
          (decorated && (fragment.borderOffset ?? 0) != 0);
      // (A padded span of words and spaces: each word padded in a slot of
      // its own, the spaces between as they are, as the box pads its
      // words. A fixed width is the whole span's: one slot, its words and
      // spaces in it.)
      final spaced =
          slotted &&
          fragment.width == null &&
          item.text.trim().isNotEmpty &&
          item.text.contains(_boxSpaces);
      final font = format.font;
      final rise = format.typographic
          ? 0.0
          : format.subscript
          // (Lowered by the font's descender, a positive length here.)
          ? -font.descenderAt(format.size)
          : format.superscript
          ? 0.85 * font.ascenderAt(format.size)
          : 0.0;
      final styles = fragment.styles ?? const {};
      final link = switch (fragment.link) {
        final String target when target.startsWith('#') => NamedTarget(
          target.substring(1),
        ),
        final String target => UriTarget(target),
        null => switch (fragment.anchor) {
          final String name => NamedTarget(name),
          null => null,
        },
      };
      if (format.image case final image?) {
        // (A jukugo compound's characters: what is beside the compound.)
        var first = index;
        var last = index;
        if (image.graphic case InlineRuby(:final jukugo?)) {
          bool ofIt(int i) => switch (_graphicOf(_items[i])) {
            InlineRuby(jukugo: final other) => other == jukugo,
            _ => false,
          };
          while (first > 0 && ofIt(first - 1)) {
            first--;
          }
          while (last + 1 < _items.length && ofIt(last + 1)) {
            last++;
          }
        }
        runs.add(
          _engineImage(
            image,
            format,
            link,
            before: first > 0 ? _neighbourText(_items[first - 1]) : null,
            after: last + 1 < _items.length
                ? _neighbourText(_items[last + 1])
                : null,
          ),
        );
        sources.add(const []);
        continue;
      }
      // (A destination marker's placeholder isn't drawn, as the box
      // doesn't draw it: its anchor alone; nor is one a template left in
      // the text, a NUL. A slot is never broken: no soft hyphens in it.)
      TextRun textRun(
        String text, {
        required bool slot,
        required String raw,
      }) => TextRun(
        text,
        TextStyle(
          font.pdf,
          format.size,
          characterSpacing: _state.characterSpacing + format.tracking,
          wordSpacing: _context.wordSpace == 1
              ? 0
              : (_context.wordSpace - 1) *
                    TextStyle(font.pdf, format.size).measure(' '),
          rise: rise,
          kerning: _state.kerning,
          ligatures: font.ligates,
          features: format.features,
          skew: _layout.skew ?? (font.slanted ? 0.2 : 0),
          embolden: font.emboldened ? format.size / 40 : 0,
          vertical: _layout.vertical,
          flipped:
              _layout.vertical && (_layout.flipped || _context.mirroredFrame),
          language: fragment.language ?? _layout.language,
          combineDigits: _layout.vertical ? _context.combineDigits : 0,
          combineUpright: _layout.vertical && fragment.combineUpright,
        ),
        color: _pdfColor(fragment.color),
        artifact: fragment.artifact,
        slotWidth: slot ? _slotWidth(raw, format) : null,
        // (Aligned in its slot as it asks: a fixed width's text
        // centered, as its markup says.)
        slotAlign:
            (fragment.callbacks?.contains(FragmentCallback.inlineTextAligner) ??
                    false) ||
                fragment.width != null
            ? switch (fragment.align) {
                'center' => TextAlign.center,
                'right' => TextAlign.right,
                _ => TextAlign.left,
              }
            : TextAlign.left,
        underline: styles.contains(FragmentStyle.underline),
        strikethrough: styles.contains(FragmentStyle.strikethrough),
        emphasisMark: fragment.textEmphasis,
        emphasisUnder: fragment.textEmphasisUnder,
        flushRight: fragment.flushRight,
        leader: fragment.leader,
        turn: switch (fragment.turnover) {
          'up' => Turnover.up,
          'down' => Turnover.down,
          'auto' => Turnover.auto,
          _ => null,
        },
        metricsFont: switch (fragment.metricsFont) {
          final family? => switch (_font(family, font.style, _context)) {
            final TrueTypeFont face => face.pdf,
            _ => null,
          },
          null => null,
        },
        link: link,
        anchor: fragment.isMarker ? fragment.name : null,
        // (A marker's anchor at the baseline, as the box reports it, but
        // a side note's, at the top of its text where the note goes.)
        anchorOnBaseline:
            fragment.isMarker &&
            !(fragment.name?.startsWith(sideNoteAnchorPrefix) ?? false),
        decoration: decorated
            ? InlineDecoration(
                background: _pdfColor(fragment.backgroundColor),
                borderColor: _pdfColor(fragment.borderColor),
                borderWidth: (fragment.borderWidth ?? 0).toDouble(),
                radius: (fragment.borderRadius ?? 0).toDouble(),
                outset: (fragment.borderOffset ?? 0).toDouble(),
              )
            : null,
      );
      TextRun run(String raw, int start, {required bool slot}) {
        final kept = StringBuffer();
        final from = <(int, int)>[];
        if (!fragment.isMarker) {
          for (var i = 0; i < raw.length; i++) {
            final unit = raw.codeUnitAt(i);
            if (unit == 0 || (slot && unit == 0xad)) continue;
            kept.writeCharCode(unit);
            from.add((index, start + i));
          }
        }
        sources.add(from);
        return textRun(kept.toString(), slot: slot, raw: raw);
      }

      if (spaced) {
        for (final piece in _boxTokens.allMatches(item.text)) {
          final text = piece[0]!;
          runs.add(run(text, piece.start, slot: !_boxSpaces.hasMatch(text)));
        }
      } else {
        runs.add(run(item.text, 0, slot: slotted));
      }
    }
    // (The paragraph starts at its first character: spaces before it,
    // after the anchors of index terms say, take no room, as the box's
    // lines start.)
    for (final (i, run) in runs.indexed) {
      if (run is! TextRun) break;
      // (An anchor's marker, of no width, passed over.)
      if (run.anchor != null) continue;
      // (ASCII spaces: a no-break space, a listing's indentation, stays.)
      final trimmed = run.text.replaceFirst(RegExp('^[ \t\r\f\v]+'), '');
      sources[i] = sources[i].sublist(run.text.length - trimmed.length);
      if (trimmed.isEmpty) {
        runs[i] = run.withText('');
        continue;
      }
      runs[i] = run.withText(trimmed);
      break;
    }
    return (runs: runs, sources: sources);
  }

  /// This (left over) text in [state] and laid out by [layout] (the rest
  /// of a first line set in another style).
  TextBox restyled(TextState state, TextLayout layout) => TextBox._(
    [
      for (final item in _items)
        () {
          final fragment = item.format.fragment.copy();
          if (item.defaultColor) fragment.color = state.color;
          return _Item(
            item.text,
            item.format.image == null
                ? _resolve(fragment, state, _context)
                : item.format,
            defaultColor: item.defaultColor,
          );
        }(),
    ],
    state,
    layout,
    _context,
    first: false,
  );

  /// The format of [fragment] in [state]: its font and size, and in the
  /// modern engine its OpenType features (small capitals the font lacks
  /// set as smaller capitals).
  static _Format _resolve(
    Fragment fragment,
    TextState state,
    TextContext context,
  ) {
    final format = _resolveFeatures(fragment, state, context);
    final tracking = _trackingOf(format, context);
    return tracking == 0 ? format : format._tracked(tracking);
  }

  /// The tracking of [format], in points: its fragment's letter spacing,
  /// else, for text in capitals or small capitals, the context's
  /// [TextContext.capsTracking].
  static double _trackingOf(_Format format, TextContext context) {
    final size = format.size;
    if (format.fragment.letterSpacing case final spacing?) {
      final value =
          double.tryParse(
            RegExp(r'^\s*[+-]?(?:\d+(?:\.\d+)?|\.\d+)').stringMatch(spacing) ??
                '',
          ) ??
          0;
      return spacing.trim().endsWith('em') ? value * size : value;
    }
    final caps = context.capsTracking;
    if (caps == 0 || format.image != null || format.fragment.isMarker) {
      return 0;
    }
    final smallCaps =
        format.smallCapitals ||
        format.features.contains('smcp') ||
        format.features.contains('c2sc');
    return smallCaps ? caps * size : 0;
  }

  /// A word of two or more capitals (and the figures and marks in it).
  static final RegExp _capitalsRx = RegExp(
    r"(?<![\p{L}\p{N}])\p{Lu}[\p{Lu}\p{N}'’.&-]*\p{Lu}(?![\p{L}\p{N}])",
    unicode: true,
  );

  /// [text] in [format] cut where words in capitals start and end, those
  /// tracked by [TextContext.capsTracking] (unless their format is).
  static List<(String, _Format)> _capitalWords(
    String text,
    _Format format,
    TextContext context,
  ) {
    final caps = context.capsTracking;
    if (caps == 0 ||
        format.tracking != 0 ||
        format.image != null ||
        format.fragment.isMarker) {
      return [(text, format)];
    }
    final pieces = <(String, _Format)>[];
    var at = 0;
    for (final m in _capitalsRx.allMatches(text)) {
      if (m.start > at) pieces.add((text.substring(at, m.start), format));
      pieces.add((m[0]!, format._tracked(caps * format.size)));
      at = m.end;
    }
    if (pieces.isEmpty) return [(text, format)];
    if (at < text.length) pieces.add((text.substring(at), format));
    return pieces;
  }

  static _Format _resolveFeatures(
    Fragment fragment,
    TextState state,
    TextContext context,
  ) {
    final format = _resolveStyle(fragment, state, context);
    if (context.typographicScripts &&
        (format.superscript || format.subscript)) {
      if (_typographic(format, format.superscript ? 'sups' : 'subs')
          case final typographic?) {
        return typographic;
      }
    }
    final features = {...state.features, ...?fragment.features};
    if (features.isEmpty || format.image != null) return format;
    final font = format.font;
    final hasSmcp = font is TrueTypeFont && font.pdf.font.hasFeature('smcp');
    final fake = features.contains('smcp') && !hasSmcp;
    if (fake) features.remove('smcp');
    return _Format(
      fragment,
      font,
      fake ? format.size * _smallCapitalScale : format.size,
      features: features,
      smallCapitals: fake,
    );
  }

  /// [format], a superscript or subscript, in its font's glyphs for it
  /// ([feature]) at the size around it, when the font has one for each
  /// character; else null.
  static _Format? _typographic(_Format format, String feature) {
    final font = format.font;
    if (font is! TrueTypeFont || format.image != null) return null;
    final open = font.pdf.font;
    final substitutions = open.singleSubstitutions(feature);
    if (substitutions.isEmpty) return null;
    for (final rune in format.fragment.text.runes) {
      if (!substitutions.containsKey(open.glyphFor(rune))) return null;
    }
    return _Format(
      format.fragment,
      font,
      format.size / _scriptScale,
      features: {feature},
      typographic: true,
    );
  }

  /// How much smaller a superscript or subscript is set than its text.
  static const _scriptScale = 0.583;

  static _Format _resolveStyle(
    Fragment fragment,
    TextState state,
    TextContext context,
  ) {
    final styles = fragment.styles ?? const {};
    var bold = styles.contains(FragmentStyle.bold);
    var italic = styles.contains(FragmentStyle.italic);
    if (styles.contains(FragmentStyle.emphasis)) {
      // Against its surroundings: the fragment's other styles and the
      // state's.
      bold = bold || state.style.contains('bold');
      italic = !(italic || state.style.contains('italic'));
      final style = bold && italic
          ? 'bold_italic'
          : bold
          ? 'bold'
          : italic
          ? 'italic'
          : 'normal';
      return _Format(
        fragment,
        _font(fragment.font ?? state.family, style, context),
        _sizeOf(fragment, styles, state, context),
      );
    }
    final style = bold && italic
        ? 'bold_italic'
        : bold
        ? 'bold'
        : italic
        ? 'italic'
        : 'normal';
    final FontFace font;
    if (fragment.font != null || style != 'normal') {
      font = _font(fragment.font ?? state.family, style, context);
    } else {
      font = _font(state.family, state.style, context);
    }
    return _Format(fragment, font, _sizeOf(fragment, styles, state, context));
  }

  static double _sizeOf(
    Fragment fragment,
    Set<FragmentStyle> styles,
    TextState state,
    TextContext context,
  ) {
    var size = switch (fragment.size) {
      null => state.size,
      final s => resolveFontSize(s, state.size, context.rootSize),
    };
    if (styles.contains(FragmentStyle.subscript) ||
        styles.contains(FragmentStyle.superscript)) {
      size *= _scriptScale;
    }
    return size;
  }

  static FontFace _font(String family, String style, TextContext context) {
    try {
      return context.fonts.font(family, style);
    } on FontException {
      return context.fonts.font(family);
    }
  }

  /// [fragment] split where its font lacks glyphs a fallback font has
  /// (the gem's `analyze_glyphs_for_fallback_font_support`); a combining
  /// mark (or a joiner, or a variation selector) stays in the font of the
  /// character it follows where that font has it, so the two are shaped
  /// together.
  ///
  /// Last, a character none of them has is looked for in the family of the
  /// text's language ([TextContext.languageFallback]; the fragment's own,
  /// else [language], the text's).
  ///
  /// An emoji sequence shown as an emoji (UTS #51: a flag, a keycap, a
  /// ZWJ sequence, a skin tone, U+FE0F) stays whole in a font with color
  /// glyphs that has it: the text's font, else the first fallback, else
  /// [TextContext.emojiFallback]'s family.
  static List<Fragment> _withFallbacks(
    Fragment fragment,
    TextState state,
    TextContext context, {
    String? language,
  }) {
    if ((context.fallbacks.isEmpty &&
            context.languageFallback == null &&
            context.emojiFallback == null) ||
        fragment.imagePath != null) {
      return [fragment];
    }
    final base = _resolve(fragment, state, context).font;
    // (Looked up the first time a character needs it.)
    String? languageFamily;
    var lookedUp = false;
    String? lastResort() {
      if (!lookedUp) {
        lookedUp = true;
        languageFamily = context.languageFallback?.call(
          fragment.language ?? language,
          base.family,
        );
      }
      return languageFamily;
    }

    final runs = <Fragment>[];
    String? currentFamily;
    final text = StringBuffer();
    var first = true;
    void flush() {
      if (text.isEmpty && !first) return;
      runs.add(
        fragment.copy(text: text.toString())
          ..font = currentFamily ?? fragment.font
          ..metricsFont = currentFamily != null && !context.fallbackMetrics
              ? base.family
              : null,
      );
      text.clear();
    }

    // The family a color font that has [runes] is of (null: the text's
    // own); false where none is.
    (bool, String?) emojiFamily(List<int> runes) {
      bool has(FontFace face) =>
          face.hasColorGlyphs &&
          runes.every(
            (r) => r < 0x20 || face.hasGlyph(r) || isDefaultIgnorable(r),
          );
      if (has(base)) return (true, null);
      for (final fallback in context.fallbacks) {
        if (has(_font(fallback, base.style, context))) return (true, fallback);
      }
      if (context.emojiFallback?.call() case final family?
          when has(_font(family, base.style, context))) {
        return (true, family);
      }
      return (false, null);
    }

    final runes = fragment.text.runes.toList();
    for (var i = 0; i < runes.length; i++) {
      final rune = runes[i];
      // (An emoji sequence, whole in a color font that has it.)
      if (emojiSequenceLength(runes, i) case final length when length > 0) {
        final sequence = runes.sublist(i, i + length);
        if (emojiFamily(sequence) case (true, final family)) {
          if (!first && family != currentFamily) flush();
          first = false;
          currentFamily = family;
          text.write(String.fromCharCodes(sequence));
          i += length - 1;
          continue;
        }
      }
      String? family;
      final continues =
          !first &&
          (rune == 0x200d ||
              (rune >= 0xfe00 && rune <= 0xfe0f) ||
              (rune >= 0x0300 && isMark(rune)));
      if (context.invisibleIgnorables &&
          isDefaultIgnorable(rune) &&
          !base.hasGlyph(rune)) {
        family = currentFamily;
      } else if (continues &&
          (currentFamily == null
              ? base.hasGlyph(rune)
              : _font(currentFamily, base.style, context).hasGlyph(rune))) {
        family = currentFamily;
      } else if (rune != 0 &&
          !base.hasGlyph(rune) &&
          rune != 10 &&
          // (A line separator: a break, as a newline, not a glyph.)
          rune != 0x2028) {
        for (final fallback in context.fallbacks) {
          if (_font(fallback, base.style, context).hasGlyph(rune)) {
            family = fallback;
            break;
          }
        }
        if (family == null) {
          if (lastResort() case final last?
              when _font(last, base.style, context).hasGlyph(rune)) {
            family = last;
          }
        }
        // (A symbol none of them has, shown in the emoji font where it
        // has it, rather than as nothing.)
        if (family == null) {
          if (context.emojiFallback?.call() case final emoji?
              when _font(emoji, base.style, context).hasGlyph(rune)) {
            family = emoji;
          }
        }
        if (family == null &&
            context.fallbacks.isNotEmpty &&
            context._warnedMissing[rune] == null) {
          context._warnedMissing[rune] = true;
          context.logger.warn(
            "Could not locate the character `${String.fromCharCode(rune)}' "
            '(\\u${rune.toRadixString(16).padLeft(4, '0')}) in the following '
            'fonts: ${[base.family, ...context.fallbacks].join(', ')}',
          );
        }
      }
      if (!first && family != currentFamily) flush();
      first = false;
      currentFamily = family;
      text.writeCharCode(rune);
    }
    flush();
    return runs.isEmpty ? [fragment] : runs;
  }

  @override
  double minHeight(double width) {
    if (_engine case final engine?) return engine.minHeight(width);
    // The modern engine needs room for the lines the text may leave at
    // the bottom of a region (its orphans), not for all of it; all of a
    // text too short to split (fewer lines than its orphans and widows).
    if (_items.isNotEmpty) {
      _arrangeImages(width);
      // (The same for the same width and labels: kept.)
      final key = (width, _labelState());
      if (_minHeights[key] case final height?) return height;
      return _minHeights[key] = _minHeight(width);
    }
    final placed = place(width, double.infinity, atTop: true);
    if (placed == null) return 0;
    return placed.height;
  }

  final Map<(double, String), double> _minHeights = {};

  /// The line breaks the wraps of the items found, by the texts of their
  /// labels (see [_labelState]), then by breaker and widths.
  final Map<String, Map<_BreaksKey, List<int>>> _breaks = {};

  /// The breaks kept for the items as they are labelled now.
  Map<_BreaksKey, List<int>> _breaksNow() => _breaks[_labelState()] ??= {};
  final Map<(double, String), int> _lineCounts = {};

  /// The texts of the items whose text is a label (after [_relabel]): what
  /// a layout of the same items at the same width may differ by.
  String _labelState() => _context.labels == null
      ? ''
      : [
          for (final item in _items)
            if (item.format.fragment.label != null) item.text,
        ].join('\u0000');

  /// This text and [following] texts, in order, [separator] between each
  /// in the style the text before it ends in, as one text (notes run in).
  @override
  CustomContent? joinedWith(
    List<CustomContent> following, {
    required String separator,
  }) {
    if (following.any((content) => content is! TextBox)) return null;
    final items = [for (final item in _items) item.copy()];
    for (final other in following.cast<TextBox>()) {
      if (items.lastOrNull case final last?) {
        items.add(
          _Item(separator, last.format, defaultColor: last.defaultColor),
        );
      }
      items.addAll([for (final item in other._items) item.copy()]);
    }
    return TextBox._(
      items,
      _state,
      _layout,
      _context,
      first: first,
      continuedIndent: continuedIndent,
    );
  }

  /// Its first line's baseline below its top at [width] (the baseline
  /// grid's), none without text.
  @override
  double? firstBaseline(double width) {
    if (_items.isEmpty) return null;
    if (_engine case final BaselineContent engine) {
      return engine.firstBaseline(width);
    }
    _relabel();
    return _firstBaselines[(width, _labelState())] ??= () {
      final wrap = _wrapOf(
        [for (final item in _items) item.copy()],
        _state,
        _layout,
        _context,
        width,
        double.infinity,
        firstPiece: first,
        breaks: _breaksNow(),
        continuedIndent: continuedIndent,
        maxLines: 1,
      );
      if (wrap.run().isEmpty) return null;
      return _layout.initialGap + wrap._baseline.abs();
    }();
  }

  final Map<(double, String), double?> _firstBaselines = {};

  /// The least height [minHeight] computes (not kept).
  double _minHeight(double width) {
    _Wrap wrapped(int maxLines) => _wrapOf(
      [for (final item in _items) item.copy()],
      _state,
      _layout,
      _context,
      width,
      double.infinity,
      firstPiece: first,
      breaks: _breaksNow(),
      continuedIndent: continuedIndent,
      maxLines: maxLines,
    );
    final orphans = math.max(1, _layout.orphans);
    final unsplit = math.max(orphans, orphans + _layout.widows - 1);
    final whole = wrapped(unsplit);
    if (whole.run().isEmpty) return 0;
    if (whole.unconsumed.isEmpty || unsplit == orphans) {
      return _layout.initialGap + whole.height;
    }
    final wrap = wrapped(orphans)..run();
    return _layout.initialGap + wrap.height;
  }

  /// The items whose text is a label the layout gives ([Fragment.label]):
  /// their text as it is now.
  void _relabel() {
    final labels = _context.labels;
    if (labels == null) return;
    for (final item in _items) {
      if (item.format.fragment.label case final key?) {
        if (labels(key) case final text?) item.text = text;
      }
    }
  }

  @override
  (double, double) intrinsicWidths() {
    if (_engine case final engine?) return engine.intrinsicWidths();
    _relabel();
    // The widest unbreakable segment, and the widest line unwrapped (the
    // spaces at its ends not counted: they go at a line's ends).
    var least = 0.0;
    var most = 0.0;
    var line = 0.0;
    var spaces = 0.0;
    for (final item in _items) {
      if (item.text == '\n') {
        most = math.max(most, line);
        line = 0;
        spaces = 0;
        continue;
      }
      // An inline image not yet arranged: as wide as it asks to be (as
      // prawn-table measures a cell), not its placeholder text.
      final image = item.format.image == null
          ? _naturalImageWidth(item.format.fragment.imageWidth)
          : null;
      if (image != null) {
        least = math.max(least, image);
        line += spaces + image;
        spaces = 0;
        continue;
      }
      final font = item.format.font;
      final size = item.format.size;
      for (final segment in _tokenize(item.text)) {
        final width = font.widthOf(
          segment,
          size,
          kerning: _state.kerning,
          features: item.format.features,
          vertical: _layout.vertical,
          combineDigits: _layout.vertical ? _context.combineDigits : 0,
        );
        if (_strip(segment).isEmpty) {
          if (line > 0) spaces += width;
          continue;
        }
        least = math.max(least, width);
        line += spaces + width;
        spaces = 0;
      }
    }
    return (least, math.max(most, line));
  }

  /// The width an inline image of width [spec] (a fragment's: points,
  /// or in a table cell a percentage and its intrinsic width,
  /// `25%153.0`) asks of its column: the points, or the intrinsic width
  /// (the percentage is of the column, as prawn-table measures it); null
  /// for no image or a width relative to the room alone.
  static double? _naturalImageWidth(String? spec) {
    if (spec == null) return null;
    final pct = spec.indexOf('%');
    if (pct < 0) return double.tryParse(spec);
    return double.tryParse(spec.substring(pct + 1));
  }

  bool _imagesArranged = false;

  /// Sizes the inline images for [width] points of room, once (the gem's
  /// `InlineImageArranger`): each becomes a placeholder as wide as the
  /// image, raising its line when the image is taller than the text.
  void _arrangeImages(double width) {
    _relabel();
    if (_imagesArranged) return;
    _imagesArranged = true;
    final images = _context.images;
    if (images == null) return;
    int? last;
    for (var i = 0; i < _items.length; i++) {
      final item = _items[i];
      final fragment = item.format.fragment;
      final path = fragment.imagePath;
      if (path == null || item.format.image != null) continue;
      final id = fragment.objectId;
      if (id != null && id == last) {
        _items.removeAt(i--);
        continue;
      }
      last = id;
      final (graphic, problem) = images(path, fragment.imageFormat);
      if (graphic == null) {
        _context.logger.warn('could not embed image: $path; $problem');
        continue;
      }
      _items[i] = _arrangeImage(item, graphic, width);
    }
  }

  /// [image], arranged in [format], as the engine's inline image, placed
  /// and measured as the box draws it: a formula standing on its depth;
  /// an image taller than the line raising it, standing on the line's
  /// descender; another centered in its text, its line no taller.
  InlineImage _engineImage(
    _Image image,
    _Format format,
    LinkTarget? link, {
    String? before,
    String? after,
  }) {
    if (image.graphic case final InlineWarichu warichu) {
      final cell = warichu.at(
        _warichuFace(warichu, format.font, format.fragment.language),
        format.size,
        vertical: _layout.vertical,
      );
      return InlineImage(
        EngineWarichu(cell, _pdfColor(format.fragment.color)),
        cell.width,
        cell.ascent + cell.descent,
        bottom: -cell.descent,
        lineAscent: cell.ascent,
        lineDescent: cell.descent,
        link: link,
      );
    }
    if (image.graphic case final InlineRuby ruby) {
      // (Its reading hanging over the kana beside it, JLREQ 3.3.8; the
      // engine sets it in at a line's start or end, 3.3.9.)
      final face = _rubyFace(ruby, format.font, format.fragment.language);
      final box = ruby.at(
        face,
        format.size,
        before: rubyOverhang(
          before == null || before.isEmpty ? null : before.runes.last,
          before: true,
          size: format.size,
        ),
        after: rubyOverhang(
          after == null || after.isEmpty ? null : after.runes.first,
          before: false,
          size: format.size,
        ),
        zhuyin: !_layout.vertical,
        vertical: _layout.vertical,
      );
      return InlineImage(
        EngineRuby(box, _pdfColor(format.fragment.color)),
        box.width,
        box.ascent + box.descent,
        bottom: -box.descent,
        lineAscent: box.ascent,
        lineDescent: box.descent,
        link: link,
        startOverhang: box.startOverhang,
        endOverhang: box.endOverhang,
      );
    }
    if (image.graphic case final InlineMath formula) {
      final depth = image.mathDepth ?? 0;
      return InlineImage(
        _EngineFormula(formula, format.size, _pdfColor(format.fragment.color)),
        image.width,
        image.height,
        bottom: -depth,
        lineAscent: image.height - depth,
        lineDescent: depth,
        link: link,
      );
    }
    if (image.lineHeightIncreased) {
      return InlineImage(
        image.graphic,
        image.drawWidth,
        image.drawHeight,
        bottom: -(image.descender ?? 0),
        lineAscent: image.ascender,
        lineDescent: image.descender,
        link: link,
      );
    }
    final ascender = format.font.ascenderAt(format.size);
    final descender = format.font.descenderAt(format.size);
    return InlineImage(
      image.graphic,
      image.drawWidth,
      image.drawHeight,
      bottom: (ascender - descender + image.height) / 2 - image.drawHeight,
      lineAscent: 0,
      lineDescent: 0,
      link: link,
    );
  }

  /// The text [item] stands for beside a ruby (whose reading may hang over
  /// it): a ruby's bases, else its text; an image's nothing.
  String? _neighbourText(_Item item) {
    String bases(InlineRuby ruby) => ruby.pairs.map((p) => p.$1).join();
    if (_graphicOf(item) case final InlineRuby ruby) return bases(ruby);
    if (item.format.fragment.imagePath != null) return null;
    return item.text;
  }

  /// The graphic [item] is, arranged or still to be.
  Graphic? _graphicOf(_Item item) {
    if (item.format.image?.graphic case final graphic?) return graphic;
    final fragment = item.format.fragment;
    if (fragment.imagePath case final path?) {
      return _context.images?.call(path, fragment.imageFormat).$1;
    }
    return null;
  }

  /// The face [ruby] is set in: [face], the text's, where it has every
  /// character of the base and the readings, else the first fallback
  /// font that has them, else the family of the text's language
  /// ([TextContext.languageFallback]).
  FontFace _rubyFace(InlineRuby ruby, FontFace face, String? language) =>
      _faceCovering(
        ruby.pairs.map((pair) => '${pair.$1}${pair.$2}').join(),
        face,
        language,
      );

  /// The face [warichu] is set in: as a ruby's ([_rubyFace]), one that
  /// has its text and the parentheses.
  FontFace _warichuFace(
    InlineWarichu warichu,
    FontFace face,
    String? language,
  ) => _faceCovering('（${warichu.text}）', face, language);

  /// [face] where it has every character of [text], else the first
  /// fallback font that has them, else the family of the text's language
  /// ([TextContext.languageFallback]), else [face].
  FontFace _faceCovering(String text, FontFace face, String? language) {
    bool covers(FontFace f) => text.runes.every(f.hasGlyph);
    if (covers(face)) return face;
    for (final family in [
      ..._context.fallbacks,
      ?_context.languageFallback?.call(
        language ?? _layout.language,
        face.family,
      ),
    ]) {
      final fallback = TextBox._font(family, face.style, _context);
      if (covers(fallback)) return fallback;
    }
    return face;
  }

  _Item _arrangeImage(_Item item, Graphic graphic, double available) {
    // Warichu: two lines of half the text's size within the line.
    if (graphic case final InlineWarichu warichu) {
      final fragment = item.format.fragment;
      final box = warichu.at(
        _warichuFace(warichu, item.format.font, fragment.language),
        item.format.size,
        vertical: _layout.vertical,
      );
      return _Item(
        '\u2063',
        _Format(
          fragment,
          item.format.font,
          item.format.size,
          image: _Image(
            graphic,
            width: box.width,
            height: box.ascent + box.descent,
            drawWidth: box.width,
            drawHeight: box.ascent + box.descent,
            ascender: box.ascent,
            descender: box.descent,
            mathDepth: box.descent,
          ),
        ),
      );
    }
    final fragment = item.format.fragment;
    // Ruby: its base at the text's size, its readings above, the line as
    // tall as they need.
    if (graphic case final InlineRuby ruby) {
      final box = ruby.at(
        _rubyFace(ruby, item.format.font, fragment.language),
        item.format.size,
        zhuyin: !_layout.vertical,
        vertical: _layout.vertical,
      );
      final lineFont = TextBox._font(_state.family, _state.style, _context);
      return _Item(
        '\u2063',
        _Format(
          fragment,
          item.format.font,
          item.format.size,
          image: _Image(
            graphic,
            width: box.width,
            height: box.ascent + box.descent,
            drawWidth: box.width,
            drawHeight: box.ascent + box.descent,
            ascender: math.max(box.ascent, lineFont.ascenderAt(_state.size)),
            descender: math.max(box.descent, lineFont.descenderAt(_state.size)),
            mathDepth: box.descent,
          ),
        ),
      );
    }
    // A formula: at the text's size, its depth below the baseline, the
    // line as tall as it needs.
    if (graphic case final InlineMath formula) {
      final box = formula.at(item.format.size);
      final lineFont = TextBox._font(_state.family, _state.style, _context);
      return _Item(
        '\u2063',
        _Format(
          fragment,
          item.format.font,
          item.format.size,
          image: _Image(
            graphic,
            width: box.width,
            height: box.height + box.depth,
            drawWidth: box.width,
            drawHeight: box.height + box.depth,
            ascender: math.max(box.height, lineFont.ascenderAt(_state.size)),
            descender: math.max(box.depth, lineFont.descenderAt(_state.size)),
            mathDepth: box.depth,
          ),
        ),
      );
    }
    final spec = fragment.imageWidth ?? '100%';
    double? width;
    double? scale;
    if (spec == 'auto') {
      width = null;
    } else if (spec.startsWith('auto*')) {
      scale = _Wrap._toF(spec.substring(5));
    } else {
      final pct = spec.indexOf('%');
      if (pct >= 0 && pct + 1 < spec.length) {
        width = math.min(
          available,
          _Wrap._toF(spec.substring(0, pct)) /
              100 *
              _Wrap._toF(spec.substring(pct + 1)),
        );
      } else {
        width = math.min(
          available,
          pct >= 0 ? _Wrap._toF(spec) / 100 * available : _Wrap._toF(spec),
        );
      }
    }
    final lineFont = TextBox._font(_state.family, _state.style, _context);
    final lineHeight = lineFont.heightAt(_state.size);
    final boundsHeight = _context.boundsHeight;
    final maxHeight = switch (fragment.imageFit) {
      'line' => math.min(boundsHeight, lineHeight),
      _ => boundsHeight,
    };
    double height;
    double drawWidth;
    double drawHeight;
    if (graphic case final SvgImage svg) {
      var (w, h) = prawnSvgSize(svg, width, null, available, boundsHeight);
      if (h > maxHeight) {
        (w, h) = prawnSvgSize(svg, null, maxHeight, available, boundsHeight);
        width = w;
      } else if (width != null) {
        width = w;
      } else {
        width = w * (scale ?? 1);
        if (width > available) width = available;
      }
      (drawWidth, drawHeight, height) = (w, h, h);
    } else {
      final ratio = graphic.intrinsicHeight / graphic.intrinsicWidth;
      if (width == null) {
        width = graphic.intrinsicWidth * 0.75 * (scale ?? 1);
        if (width > available) width = available;
      }
      height = width * ratio;
      if (height > maxHeight) {
        height = maxHeight;
        width = height / ratio;
      }
      (drawWidth, drawHeight) = (width, height);
    }
    double? ascender;
    double? descender;
    var size = item.format.size;
    var increased = false;
    if (height > lineHeight * 1.5) {
      descender = lineFont.descenderAt(_state.size);
      ascender = height - descender;
      if (height == boundsHeight) {
        ascender -= _layout.leading / 2 + lineFont.lineGapAt(_state.size);
      }
      size = height * (_state.size / lineHeight);
      increased = true;
    }
    return _Item(
      '\u2063',
      _Format(
        fragment,
        item.format.font,
        size,
        image: _Image(
          graphic,
          width: width,
          height: height,
          drawWidth: drawWidth,
          drawHeight: drawHeight,
          ascender: ascender,
          descender: descender,
          lineHeightIncreased: increased,
        ),
      ),
    );
  }

  /// The right edge and the top of the last fragment of the text laid
  /// out [width] wide, relative to the box's left and top, with the top
  /// of its first line and the left edge of its last line; null for no
  /// text.
  ({double right, double left, double top, double firstTop, double baseline})?
  lastFragment(double width) {
    // (Set by the engine: its lines' geometry.)
    if (_engine case final ParagraphContent engine) {
      return paragraphLastFragment(engine, width);
    }
    if (_items.isEmpty) return null;
    _arrangeImages(width);
    final gap = _layout.initialGap;
    final lines = _wrapOf(
      [for (final item in _items) item.copy()],
      _state,
      _layout,
      _context,
      width,
      double.infinity,
      firstPiece: first,
      breaks: _breaksNow(),
      continuedIndent: continuedIndent,
    ).run();
    final printed = [
      for (final line in lines)
        for (final f in line.fragments)
          if (!f.format.fragment.isMarker) f,
    ];
    if (printed.isEmpty) return null;
    final last = printed.last;
    final head = printed.first;
    final lastLine = [
      for (final f in lines.last.fragments)
        if (!f.format.fragment.isMarker) f.left,
    ];
    return (
      right: last.left + last.width,
      left: lastLine.isEmpty ? last.left : lastLine.reduce(math.min),
      top: gap + last.baseline - last.ascender,
      firstTop: gap + head.baseline - head.ascender,
      baseline: gap + last.baseline,
    );
  }

  @override
  CustomPlacement? place(
    double width,
    double available, {
    required bool atTop,
  }) {
    // The same for the same room and labels (the layout probes a text
    // many times over, and lays the document out again for its index,
    // footnote numbers and page references): kept, unless the placement
    // reported that the text cannot fit, which a later call reports
    // again.
    if (_engine case final engine?) {
      return _enginePlace(engine, width, available, atTop: atTop);
    }
    _relabel();
    final key = (width, available, atTop, _labelState());
    if (_placements[key] case final placed?) return placed.$1;
    _reported = false;
    final placed = _placeShrinking(width, available, atTop: atTop);
    if (!_reported) _placements[key] = (placed,);
    return placed;
  }

  final Map<(double, double, bool, String), (CustomPlacement?,)> _placements =
      {};

  /// Beside a float's outline: each line set in the room [insets] leaves
  /// it, the lines [_pitch] apart from the top; the rest as plain text.
  @override
  CustomPlacement? placeAround(
    double width,
    double available, {
    required bool atTop,
    required (double, double) Function(double top, double bottom) insets,
  }) {
    if (_items.isEmpty) return place(width, available, atTop: atTop);
    if (_engine case final ShapedContent engine) {
      return engine.placeAround(width, available, atTop: atTop, insets: insets);
    }
    _relabel();
    _arrangeImages(width);
    final pitch = _pitch(width);
    final gap = _layout.initialGap;
    final count = available.isFinite ? (available / pitch).ceil() + 1 : 0;
    final shaped = TextBox._(
      _items,
      _state,
      _layout.withLineInsets([
        for (var i = 0; i < count; i++)
          insets(gap + i * pitch, gap + (i + 1) * pitch),
      ]),
      _context,
      first: first,
      continuedIndent: continuedIndent,
    );
    final placed = shaped._place(width, available, atTop: atTop);
    return switch (placed?.rest) {
      final TextBox rest => CustomPlacement(
        height: placed!.height,
        anchors: placed.anchors,
        lines: placed.lines,
        paint: placed.paint,
        rest: TextBox._(
          rest._items,
          rest._state,
          _layout,
          rest._context,
          first: false,
          continuedIndent: rest.continuedIndent,
          startsLine: rest.startsLine,
        ),
      ),
      _ => placed,
    };
  }

  /// The distance between the text's lines at [width] (the baseline
  /// grid's step for body text).
  double linePitch(double width) => _pitch(width);

  /// The distance between the text's lines at [width]: its second line's
  /// height (its first's when it has one line).
  double _pitch(double width) {
    double heightOf(int lines) {
      final wrap = _wrapOf(
        [for (final item in _items) item.copy()],
        _state,
        _layout,
        _context,
        width,
        double.infinity,
        firstPiece: first,
        breaks: _breaksNow(),
        continuedIndent: continuedIndent,
        maxLines: lines,
      )..run();
      return wrap.height;
    }

    final one = heightOf(1);
    final two = heightOf(2);
    return two > one + 1e-6 ? two - one : one;
  }

  /// Whether the last [_place] reported that the text cannot fit.
  bool _reported = false;

  CustomPlacement? _placeShrinking(
    double width,
    double available, {
    required bool atTop,
  }) {
    if (!_layout.shrinkToFit) return _place(width, available, atTop: atTop);
    var box = this;
    var size = _state.size;
    while (true) {
      final last = size <= 5;
      final placed = box._place(width, available, atTop: atTop, quiet: !last);
      if (box._reported) _reported = true;
      if (last || (placed != null && placed.rest == null)) return placed;
      size = math.max(size - 0.5, 5);
      box = box.resized(size);
    }
  }

  /// This text at font [size] (the fragments of their own size keep it;
  /// the layout, its leading included, stays as it is).
  TextBox resized(double size) {
    final state = TextState(
      family: _state.family,
      size: size,
      style: _state.style,
      color: _state.color,
      kerning: _state.kerning,
      characterSpacing: _state.characterSpacing,
      features: _state.features,
    );
    return TextBox._(
      [
        for (final item in _items)
          _Item(
            item.text,
            item.format.image == null
                ? _resolve(item.format.fragment, state, _context)
                : item.format,
            defaultColor: item.defaultColor,
          ),
      ],
      state,
      _layout,
      _context,
      first: first,
    );
  }

  /// The fragments of the first line of the text laid out [width] wide,
  /// and the text left over (null when it all fits on the line).
  (List<Fragment>, TextBox?) splitFirstLine(double width) {
    _arrangeImages(width);
    final wrap = _wrapOf(
      [for (final item in _items) item.copy()],
      _state,
      _layout,
      _context,
      width,
      double.infinity,
      firstPiece: first,
      breaks: _breaksNow(),
      continuedIndent: continuedIndent,
    );
    final lines = wrap.run();
    final fragments = [
      if (lines.isNotEmpty)
        for (final printed in lines.first.fragments)
          printed.format.fragment.copy(text: printed.text),
    ];
    final rest = wrap.unconsumed;
    return (
      fragments,
      rest.isEmpty
          ? null
          : TextBox._(
              rest,
              _state,
              _layout,
              _context,
              first: false,
              continuedIndent: wrap.continuedIndent,
            ),
    );
  }

  /// [splitFirstLine] as the engine breaks the text, where it sets it: the
  /// first line's fragments, what follows (null when nothing does), and
  /// whether the line ends at a hard break. Null where the engine doesn't
  /// set the text as one paragraph.
  (List<Fragment>, TextBox?, bool)? engineSplitFirstLine(double width) {
    final engine = _engine;
    if (engine is! ParagraphContent) return null;
    final built = _engineRuns();
    if (built == null) return null;
    final lines = engine.linesAt(width);
    final taken = lines.length < 2 ? null : engine.textTaken(width, 1);
    if (lines.length >= 2 && taken == null) return null;
    // (Where the first line ends in the items: the item and the offset in
    // its text.)
    var cutItem = _items.length;
    var cutAt = 0;
    if (taken != null) {
      var remaining = taken.length;
      for (final (r, run) in built.runs.indexed) {
        final length = run is TextRun ? run.text.length : 0;
        if (remaining < length) {
          (cutItem, cutAt) = built.sources[r][remaining];
          break;
        }
        remaining -= length;
      }
    }
    final head = <Fragment>[
      for (final (i, item) in _items.indexed)
        if (i < cutItem)
          item.format.fragment.copy(text: item.text)
        else if (i == cutItem && cutAt > 0)
          item.format.fragment.copy(text: item.text.substring(0, cutAt)),
    ];
    // (The spaces it breaks at are neither its nor the rest's.)
    while (head.isNotEmpty) {
      final text = _rstrip(head.last.text);
      if (text.isNotEmpty || head.last.isMarker) {
        head.last = head.last.copy(text: text);
        break;
      }
      head.removeLast();
    }
    if (cutItem >= _items.length) return (head, null, false);
    final rest = [
      _items[cutItem].copy(text: _items[cutItem].text.substring(cutAt)),
      for (final item in _items.skip(cutItem + 1)) item.copy(),
    ];
    // (A hard break ending the line: the rest after it.)
    final forced = taken?.forced ?? false;
    while (rest.isNotEmpty) {
      final text = forced
          ? rest.first.text.replaceFirst(RegExp(r'^[ \t]*\n?'), '')
          : _lstrip(rest.first.text);
      if (text.isNotEmpty || rest.first.format.fragment.isMarker) {
        rest.first.text = text;
        break;
      }
      rest.removeAt(0);
    }
    return (
      head,
      rest.isEmpty
          ? null
          : TextBox._(rest, _state, _layout, _context, first: false),
      forced,
    );
  }

  CustomPlacement? _place(
    double width,
    double available, {
    required bool atTop,
    bool quiet = false,
  }) {
    if (_items.isEmpty) {
      // (No lines: the room above and below them still taken.)
      return CustomPlacement(
        height: _layout.initialGap + _layout.paddingBottom,
        paint: (page, x, top) {},
      );
    }
    _arrangeImages(width);
    final gap = _layout.initialGap;
    var wrap = _wrapOf(
      [for (final item in _items) item.copy()],
      _state,
      _layout,
      _context,
      width,
      available - gap,
      firstPiece: first,
      breaks: _breaksNow(),
      continuedIndent: continuedIndent,
    );
    var lines = wrap.run();
    // Widows and orphans: split no fewer than `orphans` lines here and
    // `widows` there, else fewer lines here, or none.
    if (lines.isNotEmpty &&
        wrap.unconsumed.isNotEmpty &&
        (_layout.orphans > 1 || _layout.widows > 1)) {
      final total = _lineCounts[(width, _labelState())] ??= _wrapOf(
        [for (final item in _items) item.copy()],
        _state,
        _layout,
        _context,
        width,
        double.infinity,
        firstPiece: first,
        breaks: _breaksNow(),
        continuedIndent: continuedIndent,
      ).run().length;
      final remaining = total - lines.length;
      var keep = lines.length;
      if (remaining < _layout.widows) keep -= _layout.widows - remaining;
      if (keep < _layout.orphans) {
        if (!atTop) return null;
        keep = lines.length;
      }
      if (keep != lines.length) {
        wrap = _wrapOf(
          [for (final item in _items) item.copy()],
          _state,
          _layout,
          _context,
          width,
          available - gap,
          firstPiece: first,
          breaks: _breaksNow(),
          continuedIndent: continuedIndent,
          maxLines: keep,
        );
        lines = wrap.run();
      }
    }
    if (lines.isEmpty) {
      if (!atTop || quiet) return null;
      // Nothing fits even on a fresh page: the gem reports it and drops
      // the text.
      _reported = true;
      _context.logger.error(
        'cannot fit formatted text on page: '
        '${_items.map((i) => i.text).join()}',
        at: _layout.at,
      );
      return CustomPlacement(height: 0, paint: (page, x, top) {});
    }
    final rest = wrap.unconsumed;
    final done = rest.isEmpty;
    var height = gap + wrap.height;
    if (_layout.finalGap || (_layout.singleLine && !done)) {
      height += wrap.lineGap + _layout.leading;
    }
    if (_layout.trailingLineGap) height += wrap.lineGap;
    if (done) height += _layout.paddingBottom;
    final anchors = <(String, double, double)>[];
    for (final line in lines) {
      for (final f in line.fragments) {
        final fragment = f.format.fragment;
        if (fragment.name case final name? when fragment.isMarker) {
          // (A side note's anchor at the top of its text, where the note
          // goes; others at the baseline, as the gem's.)
          final top = name.startsWith(sideNoteAnchorPrefix)
              ? f.format.font.ascenderAt(f.format.size)
              : f.ascender;
          anchors.add((
            name,
            f.left,
            gap + f.baseline - (name.startsWith(hangAnchorPrefix) ? 0 : top),
          ));
        }
      }
    }
    return CustomPlacement(
      height: height,
      anchors: anchors,
      lines: [
        for (final (i, line) in lines.indexed)
          if (line.fragments.isNotEmpty)
            PieceLine(
              gap + line.fragments.first.baseline,
              left: line.fragments.first.left,
              right: line.fragments.last.left + line.fragments.last.width,
              continues: i == 0 ? !startsLine : !lines[i - 1].hard,
              text: [
                for (final f in line.fragments)
                  if (!f.format.fragment.isMarker &&
                      !f.format.fragment.artifact)
                    f.text,
              ].join(),
            ),
      ],
      rest: done
          ? null
          : TextBox._(
              rest,
              _state,
              _layout,
              _context,
              first: false,
              continuedIndent: wrap.continuedIndent,
              startsLine: lines.isNotEmpty && lines.last.hard,
            ),
      paint: (page, x, top) => _paint(page, lines, x, top - gap, width),
    );
  }

  void _paint(
    LayoutPage page,
    List<_Line> lines,
    double x,
    double top,
    double width,
  ) {
    final canvas = page.canvas;
    final skew = _layout.skew;
    final lastBaseline = skew == null
        ? 0.0
        : lines
              .lastWhere(
                (l) => l.fragments.isNotEmpty,
                orElse: () => lines.last,
              )
              .fragments
              .fold<double>(0, (most, f) => math.max(most, f.baseline));
    for (final line in lines) {
      if (line.wrapped) _wrapArrow(canvas, line, x + width, top);
      for (final (index, f) in line.fragments.indexed) {
        final fragment = f.format.fragment;
        if (fragment.isMarker) continue;
        final left =
            x +
            f.left +
            (skew == null ? 0 : skew * (lastBaseline - f.baseline));
        final baseline = top - f.baseline;
        final y = baseline + f.yOffset;
        final callbacks = fragment.callbacks ?? const [];
        if (callbacks.contains(FragmentCallback.textBackgroundAndBorder)) {
          _background(canvas, fragment, left, y, f);
        }
        var textX = left;
        if (callbacks.contains(FragmentCallback.inlineTextAligner)) {
          final align = fragment.align;
          if (align == 'center' || align == 'right') {
            final natural = f.format.font.widthOf(
              f.text,
              f.format.size,
              kerning: _state.kerning,
              features: f.format.features,
              vertical: _layout.vertical,
              combineDigits: _layout.vertical ? _context.combineDigits : 0,
            );
            final gapWidth = fragment.width != null
                ? f.width - natural
                : (fragment.borderOffset ?? 0) * 2;
            if (gapWidth > 0) textX += gapWidth * (align == 'center' ? 0.5 : 1);
          }
        }
        if (f.format.image case final image?) {
          // The gem's `InlineImageRenderer`: centered in the fragment, or
          // standing on the descender of a raised line.
          final top = image.mathDepth != null
              ? baseline - image.mathDepth! + image.height
              : image.lineHeightIncreased
              ? baseline - f.descender + image.height
              : baseline +
                    f.ascender -
                    (f.ascender + f.descender - image.height) / 2;
          final imageLeft = left + (f.width - image.width) / 2;
          final rect = Rect(
            imageLeft,
            top - image.drawHeight,
            image.drawWidth,
            image.drawHeight,
          );
          switch (image.graphic) {
            case final PdfImage raster:
              raster.paint(canvas, rect);
            case final InlineWarichu warichu:
              // (The part of the note on this line: its cells beside one
              // another, drawn with the first.)
              InlineWarichu? warichuOf(_Printed g) => switch (g.format.image) {
                _Image(graphic: final InlineWarichu w)
                    when w.id == warichu.id =>
                  w,
                _ => null,
              };
              if (index > 0 && warichuOf(line.fragments[index - 1]) != null) {
                break;
              }
              final cells = <InlineWarichu>[];
              var right = rect.right;
              for (final g in line.fragments.skip(index)) {
                final cell = warichuOf(g);
                if (cell == null) break;
                cells.add(cell);
                right = x + g.left + g.width;
              }
              WarichuPart(
                cells,
                _warichuFace(warichu, f.format.font, fragment.language),
                f.format.size,
                vertical: _layout.vertical,
              ).paintAt(
                canvas,
                rect.left,
                right,
                rect.bottom + image.mathDepth!,
                color: _pdfColor(fragment.color),
              );
            case final InlineRuby ruby:
              final box = ruby.at(
                _rubyFace(ruby, f.format.font, fragment.language),
                f.format.size,
                zhuyin: !_layout.vertical,
                vertical: _layout.vertical,
              );
              final jukugo = ruby.jukugo;
              if (jukugo == null) {
                box.paintAt(
                  canvas,
                  rect.left,
                  rect.bottom + image.mathDepth!,
                  color: _pdfColor(fragment.color),
                );
                break;
              }
              // (A jukugo compound's characters beside one another on the
              // line: drawn as one part, with the first.)
              InlineRuby? pieceOf(_Printed g) => switch (g.format.image) {
                _Image(graphic: final InlineRuby r) when r.jukugo == jukugo =>
                  r,
                _ => null,
              };
              if (index > 0 && pieceOf(line.fragments[index - 1]) != null) {
                break;
              }
              final at = <(int, double)>[];
              for (final g in line.fragments.skip(index)) {
                final piece = pieceOf(g);
                if (piece == null) break;
                at.add((
                  piece.index,
                  x +
                      g.left +
                      (skew == null ? 0 : skew * (lastBaseline - g.baseline)),
                ));
              }
              jukugo.paintPart(
                canvas,
                at,
                box.face,
                box.size,
                rect.bottom + image.mathDepth!,
                readingBaseline: box.readingBaseline,
                before: box.before,
                after: box.after,
                vertical: box.vertical,
                color: _pdfColor(fragment.color),
              );
            case final InlineMath formula:
              // In the text's color; copied as its source.
              canvas
                ..save()
                ..beginMarkedContent('Span', actualText: formula.source);
              if (_pdfColor(fragment.color) case final color?) {
                canvas
                  ..setFillColor(color)
                  ..setStrokeColor(color);
              }
              formula
                  .at(f.format.size)
                  .paintAt(canvas, rect.left, rect.bottom + image.mathDepth!);
              canvas
                ..endMarkedContent()
                ..restore();
            case final other:
              canvas.save();
              other.paint(canvas, rect);
              canvas.restore();
          }
        } else if (f.text.isNotEmpty) {
          canvas.save();
          if (_pdfColor(fragment.color) case final color?) {
            canvas
              ..setFillColor(color)
              ..setStrokeColor(color);
          }
          if (fragment.artifact) {
            canvas.beginMarkedContent('Span', actualText: '');
          }
          final style = TextStyle(
            f.format.font.pdf,
            f.format.size,
            wordSpacing: f.wordSpacing,
            characterSpacing: _state.characterSpacing + f.format.tracking,
            horizontalScaling: f.scale * 100,
            kerning: _state.kerning,
            ligatures: f.format.font.ligates,
            features: f.format.features,
            skew: skew ?? (f.format.font.slanted ? 0.2 : 0),
            embolden: f.format.font.emboldened ? f.format.size / 40 : 0,
            vertical: _layout.vertical,
            flipped:
                _layout.vertical && (_layout.flipped || _context.mirroredFrame),
            language: fragment.language ?? _layout.language,
            combineDigits: _layout.vertical ? _context.combineDigits : 0,
            combineUpright: _layout.vertical && fragment.combineUpright,
          );
          // (Right-to-left text, Arabic or Hebrew, in visual order: the
          // box sets its fragments left to right.)
          final x = textX + f.format.tracking / 2;
          if (hasRightToLeft(f.text)) {
            canvas.glyphs(style.shapeBidi(f.text), x, y, style);
          } else {
            canvas.text(f.text, x, y, style);
          }
          // (Emphasis marks over or under its characters, `text_emphasis`.)
          if (fragment.textEmphasis case final mark?) {
            paintEmphasisMarks(
              canvas,
              hasRightToLeft(f.text)
                  ? style.shapeBidi(f.text)
                  : style.shape(f.text),
              x,
              y,
              style,
              mark,
              under: fragment.textEmphasisUnder,
              color: _pdfColor(fragment.color),
            );
          }
          canvas.restore();
          if (fragment.artifact) canvas.endMarkedContent();
        }
        final styles = fragment.styles ?? const {};
        if (styles.contains(FragmentStyle.underline) ||
            styles.contains(FragmentStyle.strikethrough)) {
          final underline = styles.contains(FragmentStyle.underline);
          var lineY = underline ? y - 1.25 : y + f.ascender * 0.3;
          // (Vertical text: the strike-through down the em box's middle,
          // a Japanese or Korean underline on the right, as the engine
          // sets them.)
          if (_layout.vertical) {
            final (under, strike) = decorationLines(
              TextStyle(
                f.format.font.pdf,
                f.format.size,
                vertical: true,
                flipped: _layout.flipped || _context.mirroredFrame,
                language: fragment.language ?? _layout.language,
              ),
              y,
              upright: f.text.runes.any(
                (c) => verticalOrientation(c) != VerticalOrientation.rotated,
              ),
            );
            lineY = underline ? under : strike;
          }
          canvas
            ..save()
            ..setLineWidth(
              (fragment.textDecorationWidth ?? _context.decorationWidth)
                  .toDouble(),
            );
          if (_pdfColor(fragment.textDecorationColor ?? fragment.color)
              case final color?) {
            canvas.setStrokeColor(color);
          }
          canvas
            ..moveTo(left, lineY)
            ..lineTo(left + f.width, lineY)
            ..stroke()
            ..restore();
        }
        final box = Rect(
          left,
          y - f.descender,
          f.width,
          f.ascender + f.descender,
        );
        if (fragment.link case final link?) {
          page.link(box, LinkTarget.uri(link));
        } else if (fragment.anchor case final anchor?) {
          page.link(box, LinkTarget.named(destinationName(anchor)));
        }
      }
    }
  }

  /// A return arrow just past [right], beside [line] (which wraps), in
  /// the line's text color and size: drawn rather than set in a font, so
  /// that no font needs the glyph and the text extracts unchanged.
  void _wrapArrow(Canvas canvas, _Line line, double right, double top) {
    final printed = [
      for (final f in line.fragments)
        if (!f.format.fragment.isMarker) f,
    ];
    if (printed.isEmpty) return;
    final last = printed.last;
    final size = last.format.size;
    final baseline = top - last.baseline;
    final left = right + size * 0.2;
    final bend = baseline + size * 0.2;
    canvas
      ..save()
      ..setStrokeColor(
        _pdfColor(last.format.fragment.color) ?? const Color.gray(0),
      )
      ..setLineWidth(size * 0.06)
      ..setLineCap(LineCap.round)
      ..setLineJoin(LineJoin.round)
      ..moveTo(left + size * 0.55, baseline + size * 0.6)
      ..lineTo(left + size * 0.55, bend)
      ..lineTo(left + size * 0.05, bend)
      ..moveTo(left + size * 0.25, bend + size * 0.2)
      ..lineTo(left + size * 0.05, bend)
      ..lineTo(left + size * 0.25, bend - size * 0.2)
      ..stroke()
      ..restore();
  }

  void _background(
    Canvas canvas,
    Fragment fragment,
    double left,
    double y,
    _Printed f,
  ) {
    final top = y + f.ascender;
    final offset = fragment.borderOffset?.toDouble();
    final double width;
    final double height;
    final double rectTop;
    if (offset != null) {
      rectTop = top + offset;
      width = f.width;
      height = f.ascender + f.descender + offset * 2;
    } else {
      rectTop = top;
      width = f.width;
      height = f.ascender + f.descender;
    }
    final rect = Rect(left, rectTop - height, width, height);
    final radius = (fragment.borderRadius ?? 0).toDouble();
    canvas.save();
    if (_pdfColor(fragment.backgroundColor) case final color?) {
      canvas.setFillColor(color);
      radius > 0 ? canvas.roundedRect(rect, radius) : canvas.rect(rect);
      canvas.fill();
    }
    final borderWidth = fragment.borderWidth;
    if (borderWidth != null && borderWidth > 0) {
      if (_pdfColor(fragment.borderColor) case final color?) {
        canvas
          ..setStrokeColor(color)
          ..setLineWidth(borderWidth.toDouble());
        radius > 0 ? canvas.roundedRect(rect, radius) : canvas.rect(rect);
        canvas.stroke();
      }
    }
    canvas.restore();
  }
}

/// [color] for drawing (null for none or transparent).
Color? _pdfColor(ThemeColor? color) => switch (color) {
  null || TransparentColor() => null,
  HexColor(:final hex) => Color.hex(hex),
  CmykThemeColor(:final components) => Color.cmyk(
    components[0] / 100,
    components[1] / 100,
    components[2] / 100,
    components[3] / 100,
  ),
};

/// [color] as plain_pdf draws it, for the converter.
Color? pdfColorOf(ThemeColor? color) => _pdfColor(color);

/// The break characters of Prawn's line wrapping: whitespace (with the
/// zero width space), the soft hyphen and the hyphen.
const String _breakChars = ' \t$_zwsp$_shy-';

final RegExp _wordDivision = RegExp('[\t\n\v\r $_zwsp$_shy-]');

/// The spaces the box breaks words at (spaces, tabs, zero width spaces).
final RegExp _boxSpaces = RegExp('[ \t$_zwsp]');

/// A run of [_boxSpaces], or of what isn't.
final RegExp _boxTokens = RegExp('[ \t$_zwsp]+|[^ \t$_zwsp]+');

/// [text]'s tokens (scanned by hand: line breaking tokenizes every piece
/// of text, often): a word (a run without [_breakChars]) with the soft
/// hyphen or the hyphens after it, a run of spaces, tabs and zero width
/// spaces, hyphens with the word after them, a soft hyphen.
List<String> _tokenize(String text) {
  final tokens = <String>[];
  final n = text.length;
  var i = 0;
  while (i < n) {
    final c = text.codeUnitAt(i);
    final start = i;
    if (c == _shyUnit) {
      i++;
    } else if (c == 0x20 || c == 0x09 || c == _zwspUnit) {
      while (i < n && _isSpaceUnit(text.codeUnitAt(i))) {
        i++;
      }
    } else if (c == 0x2d) {
      while (i < n && text.codeUnitAt(i) == 0x2d) {
        i++;
      }
      while (i < n && !_isBreakUnit(text.codeUnitAt(i))) {
        i++;
      }
    } else {
      while (i < n && !_isBreakUnit(text.codeUnitAt(i))) {
        i++;
      }
      if (i < n && text.codeUnitAt(i) == _shyUnit) {
        i++;
      } else {
        while (i < n && text.codeUnitAt(i) == 0x2d) {
          i++;
        }
      }
    }
    tokens.add(text.substring(start, i));
  }
  return tokens;
}

const int _shyUnit = 0xad;
const int _zwspUnit = 0x200b;

bool _isSpaceUnit(int c) => c == 0x20 || c == 0x09 || c == _zwspUnit;

bool _isBreakUnit(int c) => _isSpaceUnit(c) || c == _shyUnit || c == 0x2d;

/// Whether [text] is nothing but spaces, tabs and zero width spaces (and
/// not empty).
bool _isBlank(String text) {
  if (text.isEmpty) return false;
  for (var i = 0; i < text.length; i++) {
    if (!_isSpaceUnit(text.codeUnitAt(i))) return false;
  }
  return true;
}

/// Whether [text] is nothing but spaces and tabs (and not empty).
bool _isSpaces(String text) {
  if (text.isEmpty) return false;
  for (var i = 0; i < text.length; i++) {
    final c = text.codeUnitAt(i);
    if (c != 0x20 && c != 0x09) return false;
  }
  return true;
}

/// The wrap of [items] for [context]'s engine: the modern engine's (whole
/// words, Knuth and Plass's breaking), else Prawn's (also for code, whose
/// wrapped
/// lines go on with a hanging indent).
_Wrap _wrapOf(
  List<_Item> items,
  TextState state,
  TextLayout layout,
  TextContext context,
  double width,
  double height, {
  required bool firstPiece,
  double? continuedIndent,
  int? maxLines,
  Map<_BreaksKey, List<int>>? breaks,
}) => layout.wrapIndent == null && context.lineBreaking != LineBreaking.segments
    ? _OptimalWrap(
        items,
        state,
        layout,
        context,
        width,
        height,
        firstPiece: firstPiece,
        maxLines: maxLines,
        breaks: breaks,
      )
    : _Wrap(
        items,
        state,
        layout,
        context,
        width,
        height,
        firstPiece: firstPiece,
        continuedIndent: continuedIndent,
        maxLines: maxLines,
      );

/// How the modern engine breaks a paragraph's lines (`base_line_breaking`).
enum LineBreaking {
  /// Optimally for justified and left-aligned text, one line at a time
  /// for text centered or aligned right.
  auto,

  /// Where the lines' demerits are least (Knuth and Plass's total fit,
  /// with TeX's costs), however the text is aligned.
  optimal,

  /// One line at a time, each as full as it goes.
  greedy,

  /// One line at a time, breaking between the text's segments as Prawn's
  /// line wrap does: at every space, before and after a hyphen, a word
  /// that runs across a style change moved from that change on, soft
  /// hyphens alone hyphenating.
  segments,
}

/// Prawn's `LineWrap`, `Arranger` and `Wrap` over the items of one piece.
base class _Wrap {
  new(
    this._unconsumed,
    this._state,
    this._layout,
    this._context,
    this._width,
    this._height, {
    required this.firstPiece,
    this.continuedIndent,
    this.maxLines,
  });

  /// The most lines to set (all that fit when null).
  final int? maxLines;

  /// The indent of lines that go on with a line that wrapped (see
  /// [TextLayout.wrapIndent]): from the start when the text goes on with
  /// one, else null; after [run], for the text left over.
  double? continuedIndent;

  final List<_Item> _unconsumed;
  final TextState _state;
  final TextLayout _layout;
  final TextContext _context;
  final double _width;
  final double _height;
  final bool firstPiece;

  // Arranger state.
  List<_Item> _consumed = [];
  _Format? _currentFormat;
  List<_Printed> _fragments = [];
  double _maxLineHeight = 0;
  double _maxDescender = 0;
  double _maxAscender = 0;

  // Line wrap state.
  double _accumulated = 0;
  bool _lineEmpty = true;
  bool _moreThanOneWord = false;
  bool _newline = false;
  bool _lineFull = false;
  String _output = '';
  String _previousFragment = '';
  bool _previousEndedWithBreakable = false;
  String _previousWithoutLastWord = '';
  int _spaceCount = 0;

  // Box state.
  double _baseline = 0;
  double _lineHeight = 0;
  double _descender = 0;
  double _ascender = 0;
  final List<_Line> _lines = [];

  List<_Item> get unconsumed => _unconsumed;

  /// The height of the lines placed.
  double get height => _lines.isEmpty ? 0 : (_baseline.abs() + _descender);

  /// The line gap of the last line.
  double get lineGap => _lineHeight - (_ascender + _descender);

  double _widthOf(String given, _Format? format) {
    // The modern engine: an anchor's placeholder takes no room (some fonts
    // give their .notdef glyph a width).
    final text = given.contains(_nul) ? given.replaceAll(_nul, '') : given;
    if (text.isEmpty && given.isNotEmpty) return 0;
    final font = format?.font ?? _baseFont;
    final size = format?.size ?? _state.size;
    final width = font.widthOf(
      text,
      size,
      kerning: _state.kerning,
      features: format?.features ?? _state.features,
      vertical: _layout.vertical,
      combineDigits: _layout.vertical ? _context.combineDigits : 0,
    );
    // (Tracking after each character.)
    final tracked = width + (format?.tracking ?? 0) * text.runes.length;
    // Prawn 2.4 adds the character spacing between characters.
    final spacing = _state.characterSpacing;
    if (spacing == 0 || text.length < 2) return tracked;
    final count = text.runes.length;
    return count > 1 ? tracked + spacing * (count - 1) : tracked;
  }

  late final FontFace _baseFont = TextBox._font(
    _state.family,
    _state.style,
    _context,
  );

  List<_Line> run() {
    var stop = false;
    var lineNumber = 0;
    while (!stop) {
      if (maxLines case final most? when lineNumber >= most) break;
      final indent = lineNumber == 0 && firstPiece
          ? _layout.indentFirstLine
          : continuedIndent ?? 0.0;
      try {
        _wrapLine(_width - indent);
      } on _CannotFit {
        // Prawn prints nothing more when a character doesn't fit the width.
        _unconsumed.insertAll(0, _consumed);
        break;
      }
      if (_enoughHeight()) {
        _moveBaselineDown();
        _printLine(indent);
        _markWrap(indent);
        lineNumber++;
        if (_layout.singleLine) stop = true;
      } else {
        stop = true;
      }
      stop = stop || _unconsumed.isEmpty;
    }
    return _lines;
  }

  /// Marks the line just printed when it wraps (its text goes on in the
  /// next), and sets the indent of the lines it wraps onto: the line's
  /// own indentation (its leading no-break spaces) and the layout's
  /// [TextLayout.wrapIndent], at most half the width.
  void _markWrap(double indent) {
    final wrapIndent = _layout.wrapIndent;
    // (No hanging indent and no marker: the lines go on at the left, as
    // Prawn wraps.)
    if ((wrapIndent == null || wrapIndent == 0) && !_layout.wrapMarker) {
      return;
    }
    if (_paragraphFinished) {
      continuedIndent = null;
      return;
    }
    _lines.last.wrapped = _layout.wrapMarker;
    if (wrapIndent == null || continuedIndent != null) return;
    var own = 0.0;
    if (_lines.last.fragments.firstOrNull case final first?) {
      final leading = _leadingSpacesRx.stringMatch(first.text) ?? '';
      if (leading.isNotEmpty) own = _widthOf(leading, first.format);
    }
    continuedIndent = math.min(indent + own + wrapIndent, _width / 2);
  }

  // LineWrap.

  void _wrapLine(double width) {
    _accumulated = 0;
    _lineEmpty = true;
    _moreThanOneWord = false;
    _newline = false;
    _lineFull = false;
    _consumed = [];
    _fragments = [];
    _maxLineHeight = 0;
    _maxDescender = 0;
    _maxAscender = 0;
    while (true) {
      final item = _nextString();
      if (item == null) break;
      _output = '';
      if (_lineEmptyNow && item.text != '\n' && item.text != _nul) {
        item.text = _lstrip(item.text);
      }
      if (_lineEmptyNow && item.text.isEmpty && _nextIsNewline) {
        _updateLastString('', '', normalized: true);
        continue;
      }
      if (!_addFragment(item, width)) break;
    }
    _finalizeLine();
  }

  bool get _lineEmptyNow => _lineEmpty && _accumulated == 0;

  bool get _nextIsNewline =>
      _unconsumed.isNotEmpty && _unconsumed.first.text == '\n';

  bool get _paragraphFinished =>
      _newline || _nextIsNewline || _unconsumed.isEmpty;

  _Item? _nextString() {
    if (_unconsumed.isEmpty) return null;
    final item = _unconsumed.removeAt(0);
    _consumed.add(item);
    _currentFormat = item.format;
    return item;
  }

  /// The text of the word-joined items after the next one (the gem's
  /// `preview_joined_string`).
  String? _previewJoined() {
    if (_unconsumed.isEmpty) return null;
    final next = _unconsumed.first;
    if (!next.format.fragment.wj ||
        (_consumed.isNotEmpty && _consumed.last.format.fragment.wj)) {
      return null;
    }
    var text = next.text == _nul ? '' : next.text;
    for (var i = 1; i < _unconsumed.length; i++) {
      final item = _unconsumed[i];
      if (!item.format.fragment.wj) break;
      if (item.text != _nul) text += item.text;
    }
    return text.isEmpty ? null : text;
  }

  bool _addFragment(_Item item, double width) {
    final fragment = item.text;
    if (fragment.isEmpty) return true;
    if (fragment == '\n') {
      _newline = true;
      return false;
    }
    final joined = _previewJoined();
    final joinedWidth = joined == null
        ? 0.0
        : _widthOf(_tokenize(joined).firstOrNull ?? '', item.format);
    final segments = _tokenize(fragment);
    for (final (index, segment) in segments.indexed) {
      double segmentWidth;
      double effective;
      if (segment == _zwsp) {
        segmentWidth = effective = 0;
      } else {
        // (An inline image's placeholder is as wide as the image.)
        segmentWidth = effective =
            item.format.image?.width ?? _widthOf(segment, item.format);
        if (index == segments.length - 1) effective += joinedWidth;
      }
      if (_accumulated + effective <= width) {
        _accumulated += segmentWidth;
        if (segment.endsWith(_shy)) {
          _accumulated -= _widthOf(_shy, item.format);
        }
        _output += segment;
      } else {
        if (_accumulated == 0 && _moreThanOneWord) _moreThanOneWord = false;
        _endOfLineReached(segment, item.format, width);
        _fragmentFinished(item);
        return false;
      }
    }
    _fragmentFinished(item);
    return true;
  }

  void _endOfLineReached(String segment, _Format format, double width) {
    _updateLineStatus();
    if (!_moreThanOneWord) {
      // Wrap by character.
      for (final rune in segment.runes) {
        final char = String.fromCharCode(rune);
        final charWidth = format.font.widthOf(
          char,
          format.size,
          kerning: false,
          vertical: _layout.vertical,
        );
        if (_accumulated + charWidth <= width) {
          _accumulated += charWidth;
          _output += char;
        } else {
          break;
        }
      }
      // Prawn drops the rest of the text when not even a character fits
      // the line; the modern engine sets one anyway, past the edge.
      if (_output.isEmpty && _lineEmptyNow && segment.isNotEmpty) {
        final char = String.fromCharCode(segment.runes.first);
        _accumulated += format.font.widthOf(
          char,
          format.size,
          kerning: false,
          vertical: _layout.vertical,
        );
        _output = char;
      }
    }
    _lineFull = true;
  }

  void _fragmentFinished(_Item item) {
    if (item.text == '\n') {
      _newline = true;
      _lineEmpty = false;
    } else {
      _updateOutput(item.text);
      _updateLineStatus();
      _pullPrecedingFragment(item.text);
    }
    _rememberFragment();
  }

  void _updateOutput(String fragment) {
    final remaining = fragment.length > _output.length
        ? fragment.substring(_output.length)
        : '';
    if ((_lineFull || _paragraphFinished) &&
        _lineEmptyNow &&
        _output.isEmpty &&
        _strip(fragment).isNotEmpty) {
      throw const _CannotFit();
    }
    _updateLastString(_output, remaining, normalized: true);
  }

  void _updateLineStatus() {
    if (_wordDivision.hasMatch(_output)) _moreThanOneWord = true;
  }

  void _pullPrecedingFragment(String current) {
    if (_output.isEmpty &&
        current.isNotEmpty &&
        _moreThanOneWord &&
        !(_previousEndedWithBreakable || _breakChars.contains(current[0]))) {
      _output = _previousWithoutLastWord;
      _updateOutput(_previousFragment);
    }
  }

  void _rememberFragment() {
    _previousFragment = _output;
    _previousEndedWithBreakable =
        _previousFragment.isNotEmpty &&
        _breakChars.contains(_previousFragment[_previousFragment.length - 1]);
    final lastWord = _trailingWordRx.stringMatch(_previousFragment) ?? '';
    _previousWithoutLastWord = _previousFragment.substring(
      0,
      _previousFragment.length - lastWord.length,
    );
  }

  /// The arranger's `update_last_string`.
  void _updateLastString(
    String printed,
    String unprinted, {
    required bool normalized,
  }) {
    if (printed.isEmpty) {
      if (_consumed.isNotEmpty) _consumed.removeLast();
    } else {
      _consumed.last
        ..text = printed
        ..normalizedSoftHyphen = normalized;
    }
    if (unprinted.isNotEmpty) {
      _unconsumed.insert(0, _Item(unprinted, _currentFormat!));
    }
    if (printed.isEmpty) {
      _currentFormat = _consumed.isEmpty ? null : _consumed.last.format;
    }
  }

  void _finalizeLine() {
    if (_layout.normalizeLineHeight) {
      _consumed.insert(
        0,
        _Item(_zwsp, _Format(Fragment(_zwsp), _baseFont, _state.size)),
      );
    }
    // Omit trailing whitespace from the line width.
    for (final item in _consumed.reversed) {
      if (item.text == '\n') break;
      if (_strip(item.text).isEmpty && _consumed.length > 1) {
        item.excludeTrailingWhiteSpace = true;
      } else {
        item.excludeTrailingWhiteSpace = true;
        break;
      }
    }
    _fragments = [];
    var blankTop = 0.0;
    // (A line of markers alone, an anchor's empty paragraph, is as tall
    // as their text would be.)
    var anyText = false;
    double? markerAscender;
    for (final item in _consumed) {
      // (An anchor's placeholder, of no width, not drawn either.)
      var text = item.text.replaceAll(_zwsp, '').replaceAll(_nul, '');
      if (item.excludeTrailingWhiteSpace) {
        text = _rstrip(text);
        if (item.normalizedSoftHyphen && text.isNotEmpty) {
          text =
              text.substring(0, text.length - 1).replaceAll(_shy, '') +
              text.substring(text.length - 1);
        }
      } else if (item.normalizedSoftHyphen && text.isNotEmpty) {
        text = text.replaceAll(_shy, '');
      }
      final format = item.format;
      // (A soft hyphen ending a line in a font without one: a hyphen.)
      if (text.endsWith(_shy) && !format.font.hasGlyph(_shyUnit)) {
        text = '${text.substring(0, text.length - 1)}-';
      }
      final isMarker = format.fragment.isMarker;
      final width = isMarker ? 0.0 : _fragmentWidth(text, format);
      final printed = _Printed(
        isMarker ? '' : text,
        format,
        width,
        0,
        // (A fragment as wide as it says, a fixed space: not stretched.)
        format.fragment.width != null ? 0 : ' '.allMatches(text).length,
      );
      _fragments.add(printed);
      // (A fallback font's text counted as the text's own font, where the
      // theme asks: `font_fallback_metrics: base`.)
      final font = switch (format.fragment.metricsFont) {
        final family? => TextBox._font(family, format.font.style, _context),
        null => format.font,
      };
      final image = format.image;
      if (isMarker) {
        markerAscender = math.max(
          markerAscender ?? 0,
          font.ascenderAt(format.size),
        );
      } else {
        anyText = true;
      }
      if (_layout.capLines) {
        // (A line break or spaces count only on a line without other
        // text: an empty line is as tall as its font's cap height.)
        if (!isMarker && image == null && text.trim().isEmpty) {
          blankTop = math.max(blankTop, font.capHeightAt(format.size));
          continue;
        }
        final top = isMarker
            ? 0.0
            : image?.ascender ?? font.capHeightAt(format.size);
        _maxLineHeight = math.max(_maxLineHeight, top);
        _maxAscender = math.max(_maxAscender, top);
      } else {
        _maxLineHeight = math.max(_maxLineHeight, font.heightAt(format.size));
        _maxDescender = math.max(
          _maxDescender,
          image?.descender ?? font.descenderAt(format.size),
        );
        _maxAscender = math.max(
          _maxAscender,
          isMarker ? 0 : image?.ascender ?? font.ascenderAt(format.size),
        );
      }
    }
    if (_layout.capLines && _maxLineHeight == 0 && blankTop > 0) {
      _maxLineHeight = _maxAscender = blankTop;
    }
    if (!anyText && !_layout.capLines && markerAscender != null) {
      _maxAscender = math.max(_maxAscender, markerAscender);
    }
    _spaceCount = _fragments.fold(0, (sum, f) => sum + f.spaces);
  }

  double _fragmentWidth(String text, _Format format) {
    final fragment = format.fragment;
    if (format.image case final image?) return image.width;
    var width = switch (fragment.width) {
      final String fixed when fixed.endsWith('em') => _toF(fixed) * format.size,
      final String fixed => strToPoints(fixed),
      null => _widthOf(text, format),
    };
    if (fragment.borderOffset case final offset?) width += offset * 2;
    return width;
  }

  static double _toF(String text) =>
      double.tryParse(
        RegExp(r'^\s*[+-]?(?:\d+(?:\.\d+)?|\.\d+)').stringMatch(text) ?? '',
      ) ??
      0;

  // Wrap.

  bool _enoughHeight() {
    _lineHeight = _maxLineHeight;
    _descender = _maxDescender;
    _ascender = _maxAscender;
    final diff = _baseline == 0
        ? _ascender + _descender
        : _descender + _advance;
    if (_baseline.abs() + diff > _height + 0.0001) {
      // Repack the fragments of this line.
      final repacked = <_Item>[
        for (final item in _consumed)
          item.copy()..excludeTrailingWhiteSpace = false,
      ];
      _unconsumed.insertAll(0, repacked);
      return false;
    }
    return true;
  }

  void _moveBaselineDown() {
    if (_baseline == 0) {
      _baseline = -_ascender;
    } else {
      _baseline -= _advance;
    }
    _aboveDescender = _descender;
  }

  /// The descender of the line above, once one is placed.
  double _aboveDescender = 0;

  /// How far the line's baseline is below the one above's: its tallest
  /// font's height and the leading (Prawn's); with interline glue, the
  /// text's own font height and the leading, or where the line's text and
  /// the depth of the line above are taller than its font's, by as much
  /// more (TeX's `\baselineskip`, its `\lineskiplimit` and `\lineskip`
  /// the font's own line gap and leading).
  double get _advance {
    if (!_context.interlineGlue || _layout.capLines) {
      return _lineHeight + _layout.leading;
    }
    final font = TextBox._font(_state.family, _state.style, _context);
    final size = _state.size;
    final extent = font.ascenderAt(size) + font.descenderAt(size);
    final pitch = font.heightAt(size) + _layout.leading;
    return math.max(pitch, _aboveDescender + _ascender + pitch - extent);
  }

  /// The width justified lines are set to, when not the room
  /// ([TextLayout.justifyWidest]).
  double? _justifyTo;

  /// How far the line's last character may hang past its end, as a
  /// fraction of its width: margin kerning (character protrusion, Hàn Thế
  /// Thành, "Micro-typographic extensions to the TeX typesetting system",
  /// 2000), with the right-hand amounts of LaTeX's microtype package's
  /// default set.
  double _overhang() {
    for (final f in _fragments.reversed) {
      final text = f.text.trimRight();
      if (text.isEmpty || text == '\n') continue;
      final char = String.fromCharCode(text.runes.last);
      final factor = rightProtrusion(char);
      if (factor == 0) return 0;
      return factor * f.format.font.widthOf(char, f.format.size);
    }
    return 0;
  }

  /// How far the line's first character may hang before its start, as a
  /// fraction of its width: microtype's default left protrusion (a
  /// hyphen half, opening quotes three tenths, a few capitals a
  /// twentieth).
  double _leftOverhang() {
    for (final f in _fragments) {
      if (f.format.fragment.isMarker) continue;
      final text = f.text.replaceAll(_zwsp, '').trimLeft();
      if (text.isEmpty || text == '\n') continue;
      final char = String.fromCharCode(text.runes.first);
      final factor = leftProtrusion(char);
      if (factor == 0) return 0;
      return factor * f.format.font.widthOf(char, f.format.size);
    }
    return 0;
  }

  void _printLine(double indent, [double right = 0]) {
    // (A line beside a float's outline ends [right] short of the width.)
    final room = _width - right;
    // Justified, but not the last line of a paragraph (unless
    // `base_text_align_last: justify`), unless it is wider than the room
    // (the optimal wrap shrinks spaces to fit a line; Prawn's wrap never
    // fills a line past the room).
    final justify =
        _layout.align == 'justify' &&
        _spaceCount > 0 &&
        (_layout.forceJustify ||
            _layout.alignLast == 'justify' ||
            !_paragraphFinished ||
            _accumulatedWidth > room - indent + 0.0001);
    final hang = _layout.overhang > 0 ? _layout.overhang * _overhang() : 0.0;
    // (Justified, the first character hangs at the left too.)
    final leftHang = _layout.overhang > 0 && justify
        ? _layout.overhang * _leftOverhang()
        : 0.0;
    final measure = math.min(_justifyTo ?? room, room);
    final target = measure - indent + hang + leftHang;
    // Font expansion (TextContext.expansion): the letters take their share
    // of the difference, as the breaker counted it (their width times the
    // expansion against the spaces' stretch, half a space, or shrink, a
    // third), within the expansion; the spaces the rest.
    var scale = 1.0;
    final expansion = _context.expansion;
    if (justify && expansion > 0) {
      final difference = target - _accumulatedWidth;
      var spaceWidth = 0.0;
      for (final f in _fragments) {
        if (f.spaces > 0) spaceWidth += f.spaces * _widthOf(' ', f.format);
      }
      final letters = _accumulatedWidth - spaceWidth;
      final glue = difference >= 0 ? spaceWidth / 2 : spaceWidth / 3;
      if (letters > 0) {
        final share =
            difference * letters * expansion / (glue + letters * expansion);
        scale = 1 + (share / letters).clamp(-expansion, expansion);
      }
    }
    var wordSpacing = justify
        ? (target / scale - _accumulatedWidth) / _spaceCount
        : 0.0;
    // A last line justified for being too wide only shrinks (with what
    // hangs past the room it may fit as it is).
    if (justify &&
        !_layout.forceJustify &&
        _layout.alignLast != 'justify' &&
        _paragraphFinished &&
        wordSpacing > 0) {
      wordSpacing = 0;
    }
    final printed = <_Printed>[];
    for (final f in _fragments) {
      if (f.text == '\n') break;
      printed.add(
        _Printed(
          f.text,
          f.format,
          (f.width + wordSpacing * f.spaces) * scale,
          wordSpacing,
          f.spaces,
          scale: scale,
        ),
      );
    }
    final lineWidth = printed.fold<double>(0, (sum, f) => sum + f.width);
    final available = room - indent + hang + leftHang;
    final offset = switch (justify ? 'justify' : _lineAlign) {
      'center' => available * 0.5 - lineWidth * 0.5,
      'right' => available - lineWidth,
      _ => 0.0,
    };
    var x = indent + offset - leftHang;
    for (final f in printed) {
      f
        ..left = x
        ..baseline = -_baseline;
      x += f.width;
    }
    _lines.add(_Line(printed)..hard = _newline);
    _fragments = [];
  }

  double get _accumulatedWidth => _fragments.fold(0, (sum, f) => sum + f.width);

  /// The alignment of a line set unjustified.
  String get _lineAlign =>
      _layout.align == 'justify' ? _layout.alignLast ?? 'left' : _layout.align;
}

/// The line breaker text aligned [align] (`justify`, `left`, …) in a
/// font of [size] is broken with in [context]: Knuth and Plass's total
/// fit with TeX's costs, justified lines with a third pass of 2em more
/// stretch (LaTeX's \sloppy has 3em), ragged ones as plain TeX's
/// \raggedright (each may fall 2em short at a badness of 100, so their
/// ends are even); or one line at a time. The text box's and the engine's
/// paragraphs break with the same one.
ItemLineBreaker textLineBreaker(
  TextContext context,
  String align,
  double size,
) => switch (context.lineBreaking) {
  LineBreaking.optimal ||
  LineBreaking.auto when align == 'justify' => KnuthPlassLineBreaker(
    emergencyStretch: 2 * size,
    expansion: context.expansion,
    maxHyphenRun: context.maxHyphenRun,
    lastLineMin: context.lastLineMin,
  ),
  LineBreaking.optimal => KnuthPlassLineBreaker(
    raggedStretch: 2 * size,
    maxHyphenRun: context.maxHyphenRun,
  ),
  LineBreaking.auto when align == 'left' => KnuthPlassLineBreaker(
    raggedStretch: 2 * size,
    maxHyphenRun: context.maxHyphenRun,
  ),
  _ => const FirstFitLineBreaker(),
};

/// A character wider than the line (Prawn's `CannotFit`).
final class _CannotFit implements Exception {
  const new();
}

// Ruby's whitespace (for strip and its kin): ASCII whitespace and NUL,
// never a no-break space.

/// [text] without the ASCII whitespace and NULs at its start.
String _lstrip(String text) {
  var start = 0;
  while (start < text.length && _isStripUnit(text.codeUnitAt(start))) {
    start++;
  }
  return start == 0 ? text : text.substring(start);
}

/// [text] without the ASCII whitespace and NULs at its end.
String _rstrip(String text) {
  var end = text.length;
  while (end > 0 && _isStripUnit(text.codeUnitAt(end - 1))) {
    end--;
  }
  return end == text.length ? text : text.substring(0, end);
}

bool _isStripUnit(int c) => c == 0x20 || (c >= 0x09 && c <= 0x0d) || c == 0;

String _strip(String text) => _lstrip(_rstrip(text));

/// Text whose first line is set in another style (the gem's
/// `text_with_formatted_first_line`): the first line laid out alone, the
/// rest after it without another gap above.
final class FirstLineTextBox implements BaselineContent {
  /// [first] (laid out with a single line) followed by its rest in
  /// [state], laid out by [layout] (without the initial gap right after
  /// the first line, with it on later pages).
  new(this.first, this.state, this.layout, {this.transform});

  /// The text in the first line's style, laid out a single line.
  final TextBox first;

  /// The text transform of the first line, applied once the line is
  /// broken (the line then shrinks to fit), if any.
  final String? transform;

  /// The style of the lines after the first.
  final TextState state;

  /// The layout of the lines after the first.
  final TextLayout layout;

  /// [first] set by this converter's text box alone.
  late final TextBox _box = first.boxOnly;

  /// The first line as the engine breaks the text, where it sets it: the
  /// line (transformed, shrunk to fit, as the box sets it), and what
  /// follows it in the first line's style.
  (TextBox, TextBox?)? _engineHead(double width) {
    if (first._context.engine == null) return null;
    first._relabel();
    final key = (width, first._labelState());
    final heads = _heads;
    if (heads.containsKey(key)) return heads[key];
    final split = first.engineSplitFirstLine(width);
    if (split == null) return heads[key] = null;
    final (fragments, rest, forced) = split;
    final line = first.layout;
    final more = rest != null;
    final head = TextBox(
      [
        for (final fragment in fragments)
          if (transform case final transform?)
            fragment.copy(text: transformText(fragment.text, transform))
          else
            fragment,
      ],
      first.state,
      line.copyWith(
        paddingBottom: more ? 0 : line.paddingBottom,
        finalGap: more || line.finalGap,
        singleLine: true,
        shrinkToFit: transform != null,
        // (A line with more after it is justified as the text is, where
        // the text justifies and no hard break ends it.)
        forceJustify: more && line.align == 'justify' && !forced,
      ),
      first._context,
    );
    return heads[key] = (head, rest);
  }

  final Map<(double, String), (TextBox, TextBox?)?> _heads = {};

  @override
  CustomPlacement? place(
    double width,
    double available, {
    required bool atTop,
  }) {
    final engine = _engineHead(width);
    final CustomPlacement? placedHead;
    if (engine case (final line, final more)) {
      final placed = line.place(width, available, atTop: atTop);
      placedHead = placed == null || more == null
          ? placed
          : CustomPlacement(
              height: placed.height,
              anchors: placed.anchors,
              lines: placed.lines,
              rest: more,
              paint: placed.paint,
            );
    } else {
      placedHead = transform == null
          ? _box.place(width, available, atTop: atTop)
          : _transformedFirstLine(width, available, atTop: atTop);
    }
    final head = placedHead;
    if (head == null) return null;
    final rest = head.rest;
    if (rest is! TextBox) return head;
    final tail = rest.restyled(state, layout.withoutInitialGap);
    final body = tail.place(width, available - head.height, atTop: false);
    if (body == null) {
      return CustomPlacement(
        height: head.height,
        anchors: head.anchors,
        lines: head.lines,
        rest: tail,
        paint: head.paint,
      );
    }
    final next = body.rest;
    return CustomPlacement(
      height: head.height + body.height,
      anchors: [
        ...head.anchors,
        for (final (name, x, y) in body.anchors) (name, x, y + head.height),
      ],
      lines: [
        ...head.lines,
        for (final line in body.lines)
          PieceLine(
            line.baseline + head.height,
            left: line.left,
            right: line.right,
            continues: line.continues,
            text: line.text,
          ),
      ],
      rest: next is TextBox ? next.restyled(state, layout) : next,
      paint: (page, x, top) {
        head.paint(page, x, top);
        body.paint(page, x, top - head.height);
      },
    );
  }

  /// The first line with its text transformed: broken as it is, then
  /// shrunk to fit (justified when more follows and the text justifies).
  CustomPlacement? _transformedFirstLine(
    double width,
    double available, {
    required bool atTop,
  }) {
    final (fragments, rest) = _box.splitFirstLine(width);
    final line = first.layout;
    final more = rest != null;
    final box = TextBox(
      [
        for (final fragment in fragments)
          fragment.copy(text: transformText(fragment.text, transform!)),
      ],
      first.state,
      TextLayout(
        align: line.align,
        mirrored: line.mirrored,
        rightToLeft: line.rightToLeft,
        leading: line.leading,
        initialGap: line.initialGap,
        paddingBottom: more ? 0 : line.paddingBottom,
        finalGap: more || line.finalGap,
        singleLine: true,
        shrinkToFit: true,
        indentFirstLine: line.indentFirstLine,
        normalizeLineHeight: line.normalizeLineHeight,
        forceJustify:
            more &&
            line.align == 'justify' &&
            fragments.lastOrNull?.text != '\n',
      ),
      _box._context,
    );
    final placed = box.place(width, available, atTop: atTop);
    if (placed == null || !more) return placed;
    return CustomPlacement(
      height: placed.height,
      anchors: placed.anchors,
      lines: placed.lines,
      rest: rest,
      paint: placed.paint,
    );
  }

  @override
  double minHeight(double width) => switch (_engineHead(width)) {
    (final line, _) => line.minHeight(width),
    null => _box.minHeight(width),
  };

  @override
  double? firstBaseline(double width) => switch (_engineHead(width)) {
    (final line, _) => line.firstBaseline(width),
    null => _box.firstBaseline(width),
  };

  @override
  (double, double) intrinsicWidths() => first.intrinsicWidths();
}

/// Text set smaller when its longest line is wider than the room (the
/// gem's `autofit` option: `compute_autofit_font_size`), no smaller than
/// [minimum].
final class AutofitTextBox implements BaselineContent {
  /// [text], shrunk to fit.
  const new(this.text, {this.minimum});

  /// The text at its own size.
  final TextBox text;

  /// The least font size, if any.
  final double? minimum;

  TextBox _fitted(double width) {
    final widest = text.intrinsicWidths().$2;
    if (widest <= width) return text;
    var size = (width * text.state.size / widest * 10000).truncate() / 10000;
    if (minimum case final least? when size < least) size = least;
    return text.resized(size);
  }

  @override
  CustomPlacement? place(
    double width,
    double available, {
    required bool atTop,
  }) => _fitted(width).place(width, available, atTop: atTop);

  @override
  double minHeight(double width) => _fitted(width).minHeight(width);

  @override
  double? firstBaseline(double width) => _fitted(width).firstBaseline(width);

  @override
  (double, double) intrinsicWidths() => text.intrinsicWidths();
}

/// [paragraph]'s last fragment as [TextBox.lastFragment] gives the box's,
/// its lines set [width] wide: its right edge, its line's left edge and
/// top, the top of the first line and the last line's baseline.
({double right, double left, double top, double firstTop, double baseline})?
paragraphLastFragment(ParagraphContent paragraph, double width) {
  final lines = paragraph.linesAt(width);
  final printed = [
    for (final line in lines)
      if (line.fragments.isNotEmpty) line,
  ];
  if (printed.isEmpty) return null;
  var y = 0.0;
  var lastY = 0.0;
  for (final line in lines) {
    if (identical(line, printed.last)) lastY = y;
    y += line.height;
  }
  final last = printed.last;
  final head = printed.first;
  final fragments = last.fragments;
  return (
    right: fragments.map((f) => f.x + f.width).reduce(math.max),
    left: fragments.map((f) => f.x).reduce(math.min),
    top: lastY + last.baseline - last.ascent,
    firstTop: head.baseline - head.ascent,
    baseline: lastY + last.baseline,
  );
}

/// The name of the PDF destination of [anchor]: the anchor itself when
/// it's ASCII, else `0x` and its UTF-8 bytes in hexadecimal (the gem's
/// `derive_anchor_from_id`).
String destinationName(String anchor) {
  if (anchor.codeUnits.every((unit) => unit < 0x80)) return anchor;
  final hex = [
    for (final byte in utf8.encode(anchor))
      byte.toRadixString(16).padLeft(2, '0'),
  ];
  return '0x${hex.join()}';
}

/// The modern engine's wrap: the breaks Knuth and Plass's total fit
/// chooses (with TeX's costs), over the same items, and the lines then set
/// as Prawn's wrap sets
/// them (justified by word spacing when justified).
final class _OptimalWrap extends _Wrap {
  new(
    super._unconsumed,
    super._state,
    super._layout,
    super._context,
    super._width,
    super._height, {
    required super.firstPiece,
    super.maxLines,
    Map<_BreaksKey, List<int>>? breaks,
  }) : _breakMemo = breaks;

  /// The breaks found for these items before (their text box's), if kept.
  final Map<_BreaksKey, List<int>>? _breakMemo;

  /// A stand-in for the content of the breaker's items (it reads only
  /// their widths).
  static final TextRun _content = TextRun(
    '',
    TextStyle(StandardFont.helvetica, 10),
  );

  /// Splits into characters a word longer than a line that runs across
  /// items ([pieces], with index terms' anchors or style changes between
  /// its parts), as a word in one item is split: the line may break
  /// before any of its characters ([charBreaks], at a cost).
  void _splitLongRuns(List<(int, String)> pieces, Set<int> charBreaks) {
    bool isSpace((int, String) piece) => piece.$2 == '\n' || _isBlank(piece.$2);
    bool isMarker((int, String) piece) =>
        _unconsumed[piece.$1].format.fragment.isMarker;
    final split = <(int, String)>[];
    final breaks = <int>{};
    var p = 0;
    while (p < pieces.length) {
      var q = p;
      var width = 0.0;
      while (q < pieces.length && !isSpace(pieces[q])) {
        if (!isMarker(pieces[q])) {
          final (i, text) = pieces[q];
          width += _widthOf(text, _unconsumed[i].format);
        }
        q++;
      }
      final long = q - p > 1 && width > _width;
      if (q == p) q++;
      for (var r = p; r < q; r++) {
        final piece = pieces[r];
        if (long && !isMarker(piece) && piece.$2.runes.length > 1) {
          for (final (k, rune) in piece.$2.runes.indexed) {
            if (k > 0 || r > p) breaks.add(split.length);
            split.add((piece.$1, String.fromCharCode(rune)));
          }
        } else {
          if (charBreaks.contains(r) || (long && r > p && !isMarker(piece))) {
            breaks.add(split.length);
          }
          split.add(piece);
        }
      }
      p = q;
    }
    pieces
      ..clear()
      ..addAll(split);
    charBreaks
      ..clear()
      ..addAll(breaks);
  }

  @override
  List<_Line> run() {
    _source = [..._unconsumed];
    // The pieces: the items' tokens (newlines are items of their own).
    // Spaces at the start of a line are left out, also after zero-width
    // markers (an index term's anchor before the first word), zero-width
    // spaces and NULs (an anchor's text left in a title).
    final pieces = <(int, String)>[];
    // The pieces a word longer than a line may break before.
    final charBreaks = <int>{};
    var lineStart = true;
    for (final (i, item) in _unconsumed.indexed) {
      if (item.text == '\n') {
        pieces.add((i, '\n'));
        lineStart = true;
      } else {
        for (final token in _tokenize(item.text)) {
          if (_isSpaces(token)) {
            if (lineStart) continue;
          } else if (!item.format.fragment.isMarker &&
              token.replaceAll(_zwsp, '').replaceAll('\u0000', '').isNotEmpty) {
            lineStart = false;
          }
          // A word longer than a line: a piece per character, so that the
          // line can break between them (at a cost).
          final word = token.endsWith(_shy)
              ? token.substring(0, token.length - 1)
              : token;
          if (!item.format.fragment.isMarker &&
              word.runes.length > 1 &&
              !_isBlank(word) &&
              _widthOf(word, item.format) > _width) {
            for (final (k, rune) in token.runes.indexed) {
              if (k > 0) charBreaks.add(pieces.length);
              pieces.add((i, String.fromCharCode(rune)));
            }
            continue;
          }
          pieces.add((i, token));
        }
      }
    }
    _splitLongRuns(pieces, charBreaks);
    final indent = firstPiece ? _layout.indentFirstLine : 0.0;
    // (A drop beside the first lines, where the text starts.)
    final drop = firstPiece ? _layout.dropLines : 0;
    // (Beside a float's outline, each line's room.)
    (double, double) inset(int line) =>
        line < _layout.lineInsets.length ? _layout.lineInsets[line] : (0, 0);
    double widthOf(int line) =>
        (line == 0 ? _width - indent : _width) -
        (line < drop ? _layout.dropIndent : 0) -
        inset(line).$1 -
        inset(line).$2;
    // The breaker's items, and the piece each comes from.
    final items = <LineItem>[];
    final from = <int>[];
    // The breaks before their piece (between the characters of a word too
    // long for a line), where the others come after theirs.
    final before = <int>{};
    void add(LineItem item, int piece) {
      items.add(item);
      from.add(piece);
    }

    // The word the pieces so far belong to, and its format.
    var wordSoFar = '';
    _Format? wordFormat;
    for (final (p, (i, token)) in pieces.indexed) {
      final format = _unconsumed[i].format;
      if (token == '\n') {
        wordSoFar = '';
        add(const GlueItem.fill(), p);
        add(const PenaltyItem(0, PenaltyItem.forced), p);
        continue;
      }
      if (_isBlank(token)) {
        wordSoFar = '';
        final spaces = token.replaceAll(_zwsp, '');
        if (spaces.isEmpty) {
          add(const PenaltyItem(0, 0), p);
        } else if (format.fragment.width != null) {
          // A space as wide as it says (a term's gap): a break that
          // neither stretches nor shrinks.
          final width = _fragmentWidth(spaces, format);
          add(GlueItem(null, spaces, width, 0, 0), p);
        } else {
          final width = _widthOf(spaces, format);
          // No break after an opening bracket or before a closing one or
          // other punctuation, spaces between or not (UAX #14's LB14 and
          // LB13: `{{ x }}` stays whole).
          final before = p > 0 ? pieces[p - 1].$2 : '';
          final after = p + 1 < pieces.length ? pieces[p + 1].$2 : '';
          if ((before.isNotEmpty &&
                  '([{'.contains(before[before.length - 1])) ||
              (after.isNotEmpty && ')]}!?,.:;/'.contains(after[0]))) {
            add(const PenaltyItem(0, PenaltyItem.never), p);
          }
          add(GlueItem(null, spaces, width, width / 2, width / 3), p);
        }
        continue;
      }
      final shy = token.endsWith(_shy);
      final word = shy ? token.substring(0, token.length - 1) : token;
      // A character of a word longer than a line: a costly break before
      // it (see the pieces).
      if (charBreaks.contains(p)) {
        before.add(items.length);
        add(const PenaltyItem(0, 900), p);
      }
      if (word.isNotEmpty) {
        // A piece of a word broken into pieces (at its hyphenation
        // points): its width within the word, kerning to the piece before
        // it included, so the pieces add up to the word.
        final double width;
        if (format.fragment.isMarker) {
          width = 0;
        } else if (identical(wordFormat, format) && wordSoFar.isNotEmpty) {
          width =
              _widthOf('$wordSoFar$word', format) - _widthOf(wordSoFar, format);
        } else {
          width = word == _unconsumed[i].text
              ? _fragmentWidth(word, format)
              : _widthOf(word, format);
        }
        if (!identical(wordFormat, format)) wordSoFar = '';
        wordSoFar += word;
        wordFormat = format;
        add(BoxItem(_content, word, width), p);
      }
      if (shy) {
        add(PenaltyItem(_widthOf('-', format), 50, flagged: true), p);
      } else if (word.endsWith('-') &&
          p + 1 < pieces.length &&
          !_isBlank(pieces[p + 1].$2) &&
          pieces[p + 1].$2 != '\n') {
        // After a hyphen of the text, before a word (a space or the end
        // breaks the line anyway, UAX #14's LB7): a hyphenated break, as
        // TeX's explicit hyphens (\exhyphenpenalty, 50), the hyphen
        // repeated at the next line's start where the language has it so.
        final next = pieces[p + 1].$2;
        final repeat = _context.hyphenRepetition.repeatsBefore(next);
        add(
          PenaltyItem(
            0,
            50,
            flagged: true,
            carry: repeat ? _widthOf('-', format) : 0,
          ),
          p,
        );
      }
    }
    add(const GlueItem.fill(), pieces.length);
    add(const PenaltyItem(0, PenaltyItem.forced), pieces.length);
    // (Knuth and Plass's total fit with TeX's costs, The TeXbook, ch. 14,
    // or one line at a time: see textLineBreaker.)
    final justify = _layout.align == 'justify';
    final breaker = textLineBreaker(_context, _layout.align, _state.size);
    // The same paragraph is broken at the same width again and again (as
    // pages are tried and the book laid out again): its breaks are kept by
    // its text box, whose items at a width are the same each time.
    final key = (
      _describeBreaker(breaker, drop > 1 ? (drop, widthOf(1)) : null),
      widthOf(0),
      widthOf(math.max(drop, 1)),
    );
    // (Protrusion, with `base_overhang`: the breaker counts what hangs at
    // a line's ends, as the line is then drawn: at its end always, at its
    // start when justified.)
    List<int> breakLines() {
      final hang = _layout.overhang;
      if (breaker is! KnuthPlassLineBreaker || hang <= 0) {
        return breaker.breakItems(items, widthOf);
      }
      double protrusion(int item, {required bool right}) {
        final (i, _) = pieces[from[item]];
        final format = _unconsumed[i].format;
        if (format.fragment.isMarker || format.image != null) return 0;
        final text = switch (items[item]) {
          BoxItem(:final text) => text,
          _ => '-',
        };
        if (text.isEmpty) return 0;
        final char = String.fromCharCode(
          right ? text.runes.last : text.runes.first,
        );
        final factor = right ? rightProtrusion(char) : leftProtrusion(char);
        return factor == 0
            ? 0
            : hang * factor * format.font.widthOf(char, format.size);
      }

      return breaker.breakItems(
        items,
        widthOf,
        protrudeLeft: justify ? (item) => protrusion(item, right: false) : null,
        protrudeRight: (item) => protrusion(item, right: true),
      );
    }

    final memo = _breakMemo;
    final breaks = memo == null
        ? breakLines()
        : memo[('${key.$1} hang ${_layout.overhang}', key.$2, key.$3)] ??=
              breakLines();

    // The pieces of each line: up to the piece its break is in (a space
    // or a newline ends the line it breaks), then on from the next. A line
    // after a break that carries a hyphen starts with it, in the format of
    // the piece the hyphen ends.
    final lines = <(int, int)>[];
    final repeatedHyphens = <int, int>{};
    var start = 0;
    for (final at in breaks) {
      final item = items[at];
      final piece = from[at];
      final end = switch (item) {
        // A break between two characters of a word: the line ends before
        // the second.
        PenaltyItem() when before.contains(at) => piece,
        // A break at a space or a newline: the line takes it (trailing
        // spaces are left out of its width; a newline is its end).
        GlueItem() || PenaltyItem() when piece < pieces.length => piece + 1,
        _ => math.min(piece + 1, pieces.length),
      };
      if (end > start || lines.isEmpty) lines.add((start, end));
      if (item case PenaltyItem(:final carry) when carry > 0) {
        repeatedHyphens[lines.length] = pieces[piece].$1;
      }
      start = end;
    }

    // Justified to the widest line: each line's natural width (without
    // the spaces it ends with, with a hyphen it adds).
    if (_layout.justifyWidest) {
      var widest = 0.0;
      var start = 0;
      for (final (n, at) in breaks.indexed) {
        var end = at;
        while (end > start && items[end - 1] is GlueItem) {
          end--;
        }
        var natural = n == 0 ? indent : 0.0;
        for (var k = start; k < end; k++) {
          if (items[k] is! PenaltyItem) natural += items[k].width;
        }
        if (items[at] case PenaltyItem(flagged: true, :final width)) {
          natural += width;
        }
        widest = math.max(widest, natural);
        start = at + 1;
        while (start < items.length &&
            (items[start] is GlueItem ||
                (items[start] is PenaltyItem &&
                    !(items[start] as PenaltyItem).isForced))) {
          start++;
        }
      }
      _justifyTo = widest;
    }

    // Each line set as Prawn's wrap sets it. While a line is set, the
    // items left over are read only for their first (whether one follows,
    // and whether it is a newline), so only that one is built per line;
    // the others are added where the wrap stops ([restFrom]).
    var lineNumber = 0;
    int? restFrom;
    for (final (first, end) in lines) {
      if (maxLines case final most? when lineNumber >= most) break;
      _consumed = _items(pieces, first, end);
      if (repeatedHyphens[lineNumber] case final i?) {
        _consumed.insert(
          0,
          _source[i].copy(text: '-')..normalizedSoftHyphen = true,
        );
      }
      var next = end;
      while (next < pieces.length && pieces[next].$1 == pieces[end].$1) {
        next++;
      }
      _unconsumed
        ..clear()
        ..addAll(_items(pieces, end, next));
      restFrom = next;
      _newline = end > first && pieces[end - 1].$2 == '\n';
      _accumulated = 0;
      _fragments = [];
      _maxLineHeight = 0;
      _maxDescender = 0;
      _maxAscender = 0;
      _finalizeLine();
      if (!_enoughHeight()) break;
      _moveBaselineDown();
      _printLine(
        (lineNumber == 0 ? indent : 0) +
            (lineNumber < drop ? _layout.dropIndent : 0) +
            inset(lineNumber).$1,
        inset(lineNumber).$2,
      );
      lineNumber++;
      if (_layout.singleLine) break;
    }
    if (lineNumber == lines.length) {
      _unconsumed.clear();
    } else if (restFrom != null) {
      _unconsumed.addAll(_items(pieces, restFrom, pieces.length));
    }
    return _lines;
  }

  /// The pieces [first] to [end] (exclusive) as items: consecutive pieces
  /// of an item make one, with the item's formatting.
  List<_Item> _items(List<(int, String)> pieces, int first, int end) {
    final result = <_Item>[];
    int? current;
    final text = StringBuffer();
    void flush() {
      if (current == null) return;
      result.add(
        _source[current].copy(text: text.toString())
          ..normalizedSoftHyphen = true,
      );
      text.clear();
    }

    for (var p = first; p < end; p++) {
      final (i, token) = pieces[p];
      if (i != current) {
        flush();
        current = i;
      }
      text.write(token);
    }
    flush();
    return result;
  }

  /// The items as they were before the wrap (its list changes).
  List<_Item> _source = const [];
}

// Patterns the line wrapping uses for every piece of text, built once.
final RegExp _linesRx = RegExp('[^\n]+|\n');
final RegExp _leadingSpacesRx = RegExp('^[\u00a0 ]*');
final RegExp _trailingWordRx = RegExp('[^$_breakChars]*\$');

/// What a paragraph's line breaks depend on besides its items: the
/// breaker and its costs (with a drop's lines and their width), the first
/// line's width and the others'.
typedef _BreaksKey = (String breaker, double first, double rest);

/// [breaker] and its costs, and a drop's lines and their width.
String _describeBreaker(ItemLineBreaker breaker, (int, double)? drop) {
  final costs = switch (breaker) {
    KnuthPlassLineBreaker(
      :final tolerance,
      :final emergencyStretch,
      :final raggedStretch,
      :final expansion,
      :final maxHyphenRun,
      :final lastLineMin,
    ) =>
      'knuth-plass $tolerance $emergencyStretch $raggedStretch '
          '$expansion $maxHyphenRun $lastLineMin',
    _ => breaker.runtimeType.toString(),
  };
  return drop == null ? costs : '$costs drop ${drop.$1} ${drop.$2}';
}

/// A formula drawn by the engine as an inline image: set at [size], in
/// [color], copied as its source, as the box draws it.
final class _EngineFormula implements Graphic {
  const new(this.formula, this.size, this.color);

  final InlineMath formula;
  final double size;
  final Color? color;

  @override
  double get intrinsicWidth => formula.at(size).width;

  @override
  double get intrinsicHeight => formula.at(size).intrinsicHeight;

  @override
  void paint(Canvas canvas, Rect rect) {
    final box = formula.at(size);
    canvas
      ..save()
      ..beginMarkedContent('Span', actualText: formula.source);
    if (color case final color?) {
      canvas
        ..setFillColor(color)
        ..setStrokeColor(color);
    }
    box.paintAt(canvas, rect.left, rect.bottom + box.depth);
    canvas
      ..endMarkedContent()
      ..restore();
  }
}
