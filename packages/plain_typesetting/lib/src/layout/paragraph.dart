/// Paragraphs broken into lines: inline content becomes the boxes, glue
/// and penalties of Knuth and Plass's model, break opportunities come from
/// UAX #14, and a `LineBreaker` strategy chooses the breaks (first fit and
/// Knuth-Plass are provided). Lines are then aligned, measured and
/// painted.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:plain_typesetting/src/canvas.dart';
import 'package:plain_typesetting/src/color.dart';
import 'package:plain_typesetting/src/font.dart';
import 'package:plain_typesetting/src/geometry.dart';
import 'package:plain_typesetting/src/graphic.dart' show SplitGraphic;
import 'package:plain_typesetting/src/layout/alternates.dart';
import 'package:plain_typesetting/src/layout/east_asian.dart';
import 'package:plain_typesetting/src/layout/inline.dart';
import 'package:plain_typesetting/src/layout/kashida.dart';
import 'package:plain_typesetting/src/link.dart';
import 'package:plain_unicode/plain_unicode.dart'
    show
        BidiText,
        GeneralCategory,
        LineBreakClass,
        LineBreakStrictness,
        TextDirection,
        emojiSequenceLength,
        generalCategory,
        hasRightToLeft,
        isDefaultIgnorable,
        isMark,
        lineBreakClass,
        lineBreakOffsets,
        reorderRuns;

/// How the lines of a paragraph are spaced.
@immutable
sealed class LineHeight {
  const new _();

  /// The fonts' height (ascender to descender, plus their line gap) and
  /// [leading] more; [above] of that space between lines set above the
  /// text, the rest under it. With [skip], lines are [skip]'s height and
  /// [leading] apart, TeX's `\baselineskip`, whatever their fonts, unless
  /// a line's text and the depth of the line above are taller than
  /// [skip]'s, when they are [lineSkip] apart instead (TeX's interline
  /// glue, its `\lineskiplimit` its `\lineskip`).
  const factory font({
    double leading,
    double above,
    double? endDepth,
    TextStyle? skip,
    double? lineSkip,
  }) = FontLineHeight;

  /// [factor] times the largest font size on the line, the extra split
  /// above and below the text (as CSS does).
  const factory multiple(double factor) = MultipleLineHeight;

  /// [points] per line.
  const factory exact(double points) = ExactLineHeight;

  /// Lines from their cap heights to their baselines (CSS's
  /// `text-box-edge: cap alphabetic`), [leading] between them: a
  /// paragraph's first line has its capitals' tops at its top, and it
  /// ends at its last line's baseline.
  const factory cap({double leading}) = CapLineHeight;
}

/// Lines as tall as their fonts, plus leading.
final class FontLineHeight extends LineHeight {
  /// The fonts' height plus [leading], [above] of the space between lines
  /// (the leading and the fonts' line gap) over the text.
  const new({
    this.leading = 0,
    this.above = 0,
    this.endDepth,
    this.skip,
    this.lineSkip,
  }) : super._();

  /// Where given, the text whose height (ascender to descender and line
  /// gap) and [leading] the lines' baselines are apart (TeX's
  /// `\baselineskip`, The TeXbook ch. 12): a line with taller or deeper
  /// text than it doesn't move the lines around it while the two fit.
  final TextStyle? skip;

  /// With [skip], the space between a line's text and the line above's
  /// where they are taller than [skip]'s (TeX's `\lineskip`): unless
  /// given, [skip]'s own, its line gap and [leading], so that a theme's
  /// leading, even a negative one, holds for lines of its text.
  final double? lineSkip;

  /// [lines] (one after another, of one paragraph or several set as one)
  /// apart by [skip], where given (TeX's interline glue, The TeXbook
  /// ch. 12): each line's baseline the skip's pitch below the one above's,
  /// or where the line's text and the depth of the one above don't fit
  /// that, their sum and the line skip; the first where it is.
  List<Line> apart(List<Line> lines) {
    final skip = this.skip;
    if (skip == null || lines.length < 2) return lines;
    final font = skip.font;
    final scale = skip.size / 1000;
    final extent = (font.ascender - font.descender) * scale;
    final pitch = extent + font.lineGap * scale + leading;
    final between = lineSkip ?? pitch - extent;
    final out = <Line>[lines.first];
    for (final line in lines.skip(1)) {
      final above = out.last;
      final below = above.height - above.baseline;
      final apart = math.max(pitch, -above.descent + line.ascent + between);
      final shift = apart - below - line.baseline;
      // (Within rounding, where it is.)
      out.add(
        shift.abs() < 1e-9
            ? line
            : Line(
                line.fragments,
                width: line.width,
                height: line.height + shift,
                baseline: line.baseline + shift,
                ascent: line.ascent,
                descent: line.descent,
                hyphenated: line.hyphenated,
                readingOrder: line.readingOrder,
              ),
      );
    }
    return out;
  }

  /// Where given, how far below its baseline a paragraph's last line ends
  /// (the space under it the paragraph's own, not a line's after it: a
  /// heading's or a table cell's text ends at its descender).
  final double? endDepth;

  /// The extra space between lines, in points.
  final double leading;

  /// How much of the space between lines (the leading and the fonts'
  /// line gap) is set above each line's text, in points: none (all of it
  /// under the text, the default), half the leading (CSS's half-leading),
  /// or as a Prawn text box sets it, half the leading and the line gap.
  final double above;
}

/// Lines a multiple of their font size tall.
final class MultipleLineHeight extends LineHeight {
  /// [factor] times the font size.
  const new(this.factor) : super._();

  /// The multiple.
  final double factor;
}

/// Lines of a fixed height.
final class ExactLineHeight extends LineHeight {
  /// [points] tall.
  const new(this.points) : super._();

  /// The height, in points.
  final double points;
}

/// Lines from their cap heights to their baselines, leading between them.
final class CapLineHeight extends LineHeight {
  /// [leading] between one line's baseline and the next one's cap height.
  const new({this.leading = 0}) : super._();

  /// The space between lines, in points.
  final double leading;
}

/// How lines sit between the margins.
enum TextAlign {
  /// Against the left margin.
  left,

  /// Centered.
  center,

  /// Against the right margin.
  right,

  /// Against both margins, stretching the spaces (the last line, and
  /// lines ending in a hard break, are aligned by
  /// [Paragraph.alignLast], left unless it says otherwise).
  justify,
}

/// Where a paragraph's lines may break, besides spaces.
enum BreakOpportunities {
  /// Where UAX #14's default rules allow (after a hyphen or a slash,
  /// before an opening bracket, between ideographs...).
  unicode,

  /// After a hyphen alone (and a word wider than the line between its
  /// characters): code wrapped as typewriters and Prawn wrap it.
  spacesAndHyphens,
}

/// Whether a line may break inside a word of letters written without
/// spaces between them (CSS's `word-break`).
enum WordBreak {
  /// Wherever UAX #14 allows: between any two Han characters, kana or
  /// Hangul syllables.
  normal,

  /// Not between letters, digits, Han or Hangul (CSS's `keep-all`): only
  /// at spaces and punctuation, a word wider than the line between its
  /// characters all the same.
  keepAll,

  /// `keepAll` in Korean text (its runs' language `ko`), else `normal`.
  /// KLREQ (7.1.1) lets a Korean text break by syllables or by words
  /// (eojeol), the author's choice; by words is the common one.
  auto,
}

/// How an opening bracket starting a line is set (JLREQ 3.1.5).
enum LineStartBrackets {
  /// Solid, its blank half dropped, at the start of every line (①, as
  /// JIS X 4051 has it): after a paragraph's indent, and at a wrapped
  /// line's start, touching the edge.
  solid,

  /// Full width, its blank half kept, at the start of every line (②).
  fullWidth,

  /// Full width at a paragraph's start (which is not indented further:
  /// the caller sets no indent there), solid at a wrapped line's (③, as
  /// novels set dialogue).
  novel,
}

/// Finds where words may be hyphenated.
abstract interface class Hyphenator {
  /// The offsets in [word] (letters only) a hyphen may go before.
  List<int> hyphenate(String word);
}

/// How far [char] may hang past a line's end, as a fraction of its
/// width: margin kerning (character protrusion, Hàn Thế Thành,
/// "Micro-typographic extensions to the TeX typesetting system", 2000),
/// the right-hand amounts of LaTeX's microtype package's default set.
double rightProtrusion(String char) => switch (char) {
  '.' => 0.7,
  ',' || ':' || '-' || '\u00ad' || '\u2010' => 0.5,
  '\u2019' || "'" => 0.4,
  ';' || '\u201d' || '"' => 0.3,
  '~' || '+' => 0.25,
  '\u2013' || '/' || ')' || '*' => 0.2,
  '\u2014' => 0.15,
  '!' || '?' => 0.1,
  'A' || 'F' || 'K' || 'L' || 'T' || 'V' || 'W' || 'X' || 'Y' => 0.05,
  'k' || 'r' || 'v' || 'w' || 'x' || 'y' => 0.05,
  '1' || '4' || '7' || '@' || '%' => 0.05,
  _ => 0.0,
};

/// How far [char] may hang before a line's start, as a fraction of its
/// width: microtype's default left protrusion (a hyphen half, opening
/// quotes three tenths, a few capitals a twentieth).
double leftProtrusion(String char) => switch (char) {
  '-' || '\u2010' => 0.5,
  '\u2018' || '\u201c' || '\u201e' || "'" || '"' || '\u00ab' => 0.3,
  'A' || 'T' || 'V' || 'W' || 'X' || 'Y' => 0.05,
  _ => 0.0,
};

/// A paragraph: inline content, aligned and spaced.
@immutable
final class Paragraph {
  /// A paragraph of [content].
  const new(
    this.content, {
    this.align = TextAlign.left,
    this.lineHeight = const LineHeight.font(),
    this.firstLineIndent = 0,
    this.hyphenator,
    this.breakLongWords = true,
    this.hyphenRepetition = HyphenRepetition.none,
    this.riseInLineHeight = true,
    this.alignLast = TextAlign.left,
    this.protrusion = 0,
    this.justifyToWidest = false,
    this.hangIndent = 0,
    this.hangLines = 0,
    this.firstLineContent,
    this.strut,
    this.rightToLeft = false,
    this.breakOpportunities = BreakOpportunities.unicode,
    this.kashida = 0,
    this.eastAsian = true,
    this.wordBreak = WordBreak.auto,
    this.hangingPunctuation = false,
    this.lineStartBrackets = LineStartBrackets.solid,
    this.tshegPadding = false,
    this.justificationAlternates = true,
    this.lineBreak = LineBreakStrictness.strict,
  });

  /// This paragraph with [content], [align], [firstLineIndent],
  /// [justifyToWidest], [hangLines], [breakOpportunities] or [lineHeight]
  /// instead of its own.
  Paragraph copyWith({
    List<InlineContent>? content,
    TextAlign? align,
    LineHeight? lineHeight,
    double? firstLineIndent,
    bool? justifyToWidest,
    int? hangLines,
    BreakOpportunities? breakOpportunities,
  }) => Paragraph(
    content ?? this.content,
    align: align ?? this.align,
    lineHeight: lineHeight ?? this.lineHeight,
    firstLineIndent: firstLineIndent ?? this.firstLineIndent,
    hyphenator: hyphenator,
    breakLongWords: breakLongWords,
    hyphenRepetition: hyphenRepetition,
    riseInLineHeight: riseInLineHeight,
    alignLast: alignLast,
    protrusion: protrusion,
    justifyToWidest: justifyToWidest ?? this.justifyToWidest,
    hangIndent: hangIndent,
    hangLines: hangLines ?? this.hangLines,
    firstLineContent: firstLineContent,
    strut: strut,
    rightToLeft: rightToLeft,
    breakOpportunities: breakOpportunities ?? this.breakOpportunities,
    kashida: kashida,
    eastAsian: eastAsian,
    wordBreak: wordBreak,
    hangingPunctuation: hangingPunctuation,
    lineStartBrackets: lineStartBrackets,
    tshegPadding: tshegPadding,
    justificationAlternates: justificationAlternates,
    lineBreak: lineBreak,
  );

  /// How strictly the lines break around East Asian punctuation and small
  /// kana (CSS's `line-break`: [LineBreakStrictness]), its Chinese and
  /// Japanese rules where the text's language is either.
  final LineBreakStrictness lineBreak;

  /// The inline content.
  final List<InlineContent> content;

  /// Whether Han, kana and the other text written without spaces is set
  /// as JLREQ and CLREQ have it (see `east_asian.dart`): full-width
  /// punctuation squeezed, a quarter em between Han or kana and Latin,
  /// justified lines stretched between characters.
  final bool eastAsian;

  /// How far each word of a justified line of Arabic may be lengthened by
  /// kashida (tatweel between its letters, at the place its letters rank
  /// first: see `kashida.dart`), in em, before the line's spaces are
  /// widened: 0 for none.
  final double kashida;

  /// Where the lines may break besides at spaces.
  final BreakOpportunities breakOpportunities;

  /// Whether lines break inside words written without spaces between
  /// their letters (by default, not in Korean).
  final WordBreak wordBreak;

  /// Whether a full-width full stop or comma ending a line hangs past its
  /// end (burasagari, JLREQ 2.5.1), rather than going to the next line or
  /// the line being squeezed for it.
  final bool hangingPunctuation;

  /// How an opening bracket starting a line is set (JLREQ 3.1.5).
  final LineStartBrackets lineStartBrackets;

  /// Whether a justified line of Tibetan ending with a tsheg is filled out
  /// with more tshegs, the rest of its room spread between its characters
  /// (r12a's Tibetan notes' second way: pecha and many printed books),
  /// rather than spread between its characters alone.
  final bool tshegPadding;

  /// Whether a justified line takes its fonts' justification alternates
  /// (`jalt`: Nastaliq's wider letterforms, W3C alreq 7.2.3) before its
  /// spaces widen.
  final bool justificationAlternates;

  /// Whether the paragraph's base direction is right to left (Arabic,
  /// Hebrew): its lines start at the right, where its indents go, and
  /// its text is put in visual order by the Unicode Bidirectional
  /// Algorithm (UAX #9, each line resolved on its own), right-to-left
  /// runs shaped as such. Text in a right-to-left script is reordered in
  /// a left-to-right paragraph too. [align] stays absolute: a
  /// right-to-left paragraph set from its start is aligned right (and
  /// its [alignLast] too). [protrusion] is not applied.
  final bool rightToLeft;

  /// Whether text raised or lowered ([TextStyle.rise], a superscript or a
  /// subscript) makes its line taller (as CSS's line boxes grow); false
  /// keeps the line's pitch, the raised text reaching into the space
  /// between lines (as TeX's \baselineskip and Prawn's lines do).
  final bool riseInLineHeight;

  /// The alignment.
  final TextAlign align;

  /// The alignment of a justified paragraph's last line and those ending
  /// in a hard break (CSS's `text-align-last`): [TextAlign.justify]
  /// stretches them too.
  final TextAlign alignLast;

  /// How far a line's end characters hang into the margin, as a share of
  /// [rightProtrusion]'s and [leftProtrusion]'s amounts (0: none; 1:
  /// microtype's default set): character protrusion, a line's last
  /// character at its end always, its first at its start when the line is
  /// justified, the breaker counting them as the lines are then drawn.
  final double protrusion;

  /// Whether a justified paragraph's lines are stretched to its widest
  /// line's natural width (its first line's indent counted) rather than to
  /// the measure: a paragraph in a block sized to its content, where
  /// stretching to the measure would make it wider than its text.
  final bool justifyToWidest;

  /// How far the first [hangLines] lines are set in from the start, the
  /// room beside them left (a drop initial's): TeX's `\hangindent`, with
  /// `\hangafter` the negative of [hangLines].
  final double hangIndent;

  /// How many lines [hangIndent] sets in.
  final int hangLines;

  /// A style each line is at least as tall as text in (TeX's `\strut`: a
  /// caption's lines as tall as the body text's, whatever their size), or
  /// null.
  final TextStyle? strut;

  /// The same text in its first line's style (CSS's `::first-line`: an
  /// abstract's first line in bold), or null: the paragraph is broken in
  /// that style, its first line kept, and the rest of the text broken
  /// again in its own.
  final List<InlineContent>? firstLineContent;

  /// The line spacing.
  final LineHeight lineHeight;

  /// The indent of the first line, in points.
  final double firstLineIndent;

  /// What hyphenates words, if anything.
  final Hyphenator? hyphenator;

  /// Whether a word wider than the line is broken between any two
  /// characters (rather than sticking out).
  final bool breakLongWords;

  /// Whether a line broken after a word's own hyphen (a compound's) starts
  /// with the hyphen again.
  final HyphenRepetition hyphenRepetition;
}

/// When a compound's hyphen is repeated at the start of the next line, as
/// the orthographies of some languages have it (for Spanish, the Real
/// Academia Española's Ortografía de la lengua española, 2010).
enum HyphenRepetition {
  /// Never.
  none,

  /// Always: Czech, Croatian, Lower Sorbian, Polish, Portuguese, Slovak.
  always,

  /// Before a word that doesn't start with a capital: Spanish.
  beforeLowercase;

  /// The repetition the typography of the language [tag] (`pt`, `es-MX`)
  /// asks for.
  static HyphenRepetition forLanguage(String? tag) =>
      switch (tag?.toLowerCase().split(RegExp('[-_]')).first) {
        'cs' || 'hr' || 'dsb' || 'pl' || 'pt' || 'sk' => always,
        'es' => beforeLowercase,
        _ => none,
      };

  /// Whether the hyphen is repeated before [following] text.
  bool repeatsBefore(String following) => switch (this) {
    none => false,
    always => true,
    beforeLowercase =>
      following.isNotEmpty &&
          !_isUppercase(String.fromCharCode(following.runes.first)),
  };

  static bool _isUppercase(String c) =>
      c != c.toLowerCase() && c == c.toUpperCase();
}

/// An item of the paragraph's line breaking model.
@immutable
sealed class LineItem {
  const new _();

  /// The item's natural width, in points.
  double get width;
}

/// Content that is never broken: a piece of a word, or an image.
final class BoxItem extends LineItem {
  /// The [text] of [content] (empty for an image), [width] wide.
  const new(this.content, this.text, this.width) : super._();

  /// The text run or image.
  final InlineContent content;

  /// The text.
  final String text;

  @override
  final double width;
}

/// A space: where a line may break (if a box comes before it), and what
/// stretches or shrinks to justify a line.
final class GlueItem extends LineItem {
  /// The space [text] of [run], [width] wide, which may grow by
  /// [stretch] and shrink by [shrink].
  const new(this.run, this.text, this.width, this.stretch, this.shrink)
    : super._();

  /// Glue that fills the rest of the last line.
  const new fill()
    : run = null,
      text = '',
      width = 0,
      stretch = double.infinity,
      shrink = 0,
      super._();

  /// The run the space belongs to (null for fill glue).
  final TextRun? run;

  /// The space characters.
  final String text;

  @override
  final double width;

  /// How much the space may grow.
  final double stretch;

  /// How much the space may shrink.
  final double shrink;
}

/// A place the line may break at a cost.
final class PenaltyItem extends LineItem {
  /// A break costing [penalty] (`forced` or below always breaks, `never`
  /// or above never does); [flagged] breaks add a hyphen of [width] in
  /// [run]'s style; a break with a [carry] starts the next line with a
  /// hyphen that wide (a compound's hyphen repeated, see
  /// [HyphenRepetition]).
  const new(
    this.width,
    this.penalty, {
    this.flagged = false,
    this.run,
    this.carry = 0,
  }) : super._();

  /// The cost of breaking that forces a break.
  static const double forced = -10000;

  /// The cost of breaking that forbids it.
  static const double never = 10000;

  @override
  final double width;

  /// The cost of breaking here.
  final double penalty;

  /// Whether breaking here adds a hyphen.
  final bool flagged;

  /// The width of the hyphen the next line starts with when the line
  /// breaks here (0: none).
  final double carry;

  /// The run the break is in: the hyphen's style, and the metrics of an
  /// empty line ending here.
  final TextRun? run;

  /// Whether the line must break here.
  bool get isForced => penalty <= forced;
}

/// The width available to each line (0-based) of a paragraph.
typedef LineWidths = double Function(int line);

/// Chooses where a paragraph's lines break.
abstract interface class LineBreaker {
  /// The lines of [paragraph] in [widths].
  List<Line> breakLines(Paragraph paragraph, LineWidths widths);
}

/// A line breaker over the items of [paragraphItems].
abstract base class ItemLineBreaker implements LineBreaker {
  /// A line breaker.
  const new();

  /// The indices of the items lines end at (glue or penalties), in order;
  /// the last is the final forced break. [protrudeLeft] and
  /// [protrudeRight]: how far an item's first or last character may hang
  /// into the margin (see [KnuthPlassLineBreaker.breakItems]), which a
  /// breaker may count.
  List<int> breakItems(
    List<LineItem> items,
    LineWidths widths, {
    double Function(int item)? protrudeLeft,
    double Function(int item)? protrudeRight,
  });

  /// How much wider or narrower the letters of a justified line may be set
  /// (see [KnuthPlassLineBreaker.expansion]); none by default.
  double get expansion => 0;

  @override
  List<Line> breakLines(Paragraph paragraph, LineWidths widths) {
    final indent = paragraph.firstLineIndent;
    double indented(int line) =>
        widths(line) -
        (line == 0 ? indent : 0) -
        (line < paragraph.hangLines ? paragraph.hangIndent : 0);
    final items = paragraphItems(
      paragraph,
      maxWidth: paragraph.breakLongWords ? indented(0) : null,
    );
    if (items.isEmpty) return const [];
    if (paragraph.firstLineContent case final first?) {
      return _withFirstLine(paragraph, first, items, widths, indented(0));
    }
    return breakItemLines(paragraph, items, widths).lines;
  }

  /// [paragraph]'s lines with its first in [first]'s style: broken in
  /// that style, its first line kept, the rest of [items] (the text after
  /// the text that line takes) broken again.
  List<Line> _withFirstLine(
    Paragraph paragraph,
    List<InlineContent> first,
    List<LineItem> items,
    LineWidths widths,
    double firstWidth,
  ) {
    final styled = Paragraph(
      first,
      align: paragraph.align,
      lineHeight: paragraph.lineHeight,
      firstLineIndent: paragraph.firstLineIndent,
      hyphenator: paragraph.hyphenator,
      breakLongWords: paragraph.breakLongWords,
      hyphenRepetition: paragraph.hyphenRepetition,
      riseInLineHeight: paragraph.riseInLineHeight,
      alignLast: paragraph.alignLast,
      protrusion: paragraph.protrusion,
      hangIndent: paragraph.hangIndent,
      hangLines: paragraph.hangLines,
      wordBreak: paragraph.wordBreak,
      hangingPunctuation: paragraph.hangingPunctuation,
      lineStartBrackets: paragraph.lineStartBrackets,
      lineBreak: paragraph.lineBreak,
    );
    final firstItems = paragraphItems(
      styled,
      maxWidth: paragraph.breakLongWords ? firstWidth : null,
    );
    final (:lines, :breaks) = breakItemLines(styled, firstItems, widths);
    if (lines.length < 2) return lines;
    // (How much of the text the first line takes, and where that ends in
    // the paragraph's own items.)
    int length(LineItem item) => switch (item) {
      BoxItem(:final text) || GlueItem(:final text) => text.length,
      _ => 0,
    };
    var taken = 0;
    for (var i = 0; i <= breaks.first; i++) {
      taken += length(firstItems[i]);
    }
    var at = 0;
    var counted = 0;
    while (at < items.length && counted < taken) {
      counted += length(items[at]);
      at++;
    }
    while (at < items.length &&
        switch (items[at]) {
          GlueItem() => true,
          PenaltyItem(:final isForced) => !isForced,
          BoxItem() => false,
        }) {
      at++;
    }
    final rest = breakItemLines(
      paragraph.copyWith(
        firstLineIndent: 0,
        hangLines: math.max(0, paragraph.hangLines - 1),
      ),
      items.sublist(at),
      (line) => widths(line + 1),
    ).lines;
    return _interline(paragraph, [lines.first, ...rest]);
  }

  /// The lines of [paragraph] made of [items] (its [paragraphItems], or
  /// those after one of its lines, to be broken again) in [widths], and
  /// the item each line breaks at.
  ///
  /// Each line is set [offsets] in from the start, where given (a line
  /// beside an outline, in the room it leaves).
  ({List<Line> lines, List<int> breaks}) breakItemLines(
    Paragraph paragraph,
    List<LineItem> items,
    LineWidths widths, {
    LineWidths? offsets,
  }) {
    if (items.isEmpty) return (lines: const [], breaks: const []);
    final indent = paragraph.firstLineIndent;
    double indented(int line) =>
        widths(line) -
        (line == 0 ? indent : 0) -
        (line < paragraph.hangLines ? paragraph.hangIndent : 0);
    // (Protrusion: what hangs at a line's ends counted as the line is
    // then drawn, at its end always, at its start when justified.)
    double Function(int)? protrude({required bool right}) {
      if (paragraph.protrusion <= 0 &&
          !(right && paragraph.hangingPunctuation)) {
        return null;
      }
      if (!right && paragraph.align != TextAlign.justify) return null;
      return (item) {
        final (run, text) = switch (items[item]) {
          BoxItem(:final content, :final text) => (content, text),
          PenaltyItem(:final run) => (run, '-'),
          _ => (null, ''),
        };
        if (run is! TextRun || text.isEmpty) return 0;
        return _protrusionOf(paragraph, run, text, right: right);
      };
    }

    final breaks = breakItems(
      items,
      indented,
      protrudeLeft: protrude(right: false),
      protrudeRight: protrude(right: true),
    );
    return (
      lines: buildLines(
        paragraph,
        items,
        breaks,
        widths,
        expansion: expansion,
        offsets: offsets,
      ),
      breaks: breaks,
    );
  }
}

/// How far [text]'s last ([right]) or first character hangs into the
/// margin in [run], with [paragraph]'s protrusion.
double _protrusionOf(
  Paragraph paragraph,
  TextRun run,
  String text, {
  required bool right,
}) {
  final char = String.fromCharCode(right ? text.runes.last : text.runes.first);
  // (A full stop or comma hung whole past the line's end: burasagari.)
  if (right &&
      paragraph.hangingPunctuation &&
      hangsAtLineEnd(char.runes.single)) {
    return run.style.font.widthOf(char, run.style.size);
  }
  final factor = right ? rightProtrusion(char) : leftProtrusion(char);
  return factor == 0
      ? 0
      : paragraph.protrusion *
            factor *
            run.style.font.widthOf(char, run.style.size);
}

/// The cost from which a break is a last resort for [FirstFitLineBreaker].
const double _lastResort = 500;

/// Breaks each line at the last opportunity that fits: the way most
/// word processors (and Prawn) fill lines. A break costing 500 or more
/// (between the characters of a word too long for a line) is taken only
/// when the line has no other.
final class FirstFitLineBreaker extends ItemLineBreaker {
  /// A first-fit line breaker.
  const new();

  @override
  List<int> breakItems(
    List<LineItem> items,
    LineWidths widths, {
    double Function(int item)? protrudeLeft,
    double Function(int item)? protrudeRight,
  }) {
    final breaks = <int>[];
    var start = 0;
    while (start < items.length) {
      final s = _skipDiscardable(items, start);
      if (s >= items.length) break;
      final available = widths(breaks.length) + _epsilon;
      var width = _carry(items, start - 1);
      int? candidate;
      var lastResort = false;
      int? end;
      // (What hangs past the end of a line breaking after the last box:
      // its protrusion, a hanging full stop or comma.)
      var lastBox = -1;
      double hang() => lastBox < 0 ? 0 : (protrudeRight?.call(lastBox) ?? 0);
      for (var i = s; i < items.length; i++) {
        final item = items[i];
        switch (item) {
          case PenaltyItem(isForced: true):
            end = width <= available + hang() || candidate == null
                ? i
                : candidate;
          case PenaltyItem(:final penalty):
            // A costly break (between the characters of a word too long
            // for a line) only when the line has no other.
            final last = penalty >= _lastResort;
            if (penalty < PenaltyItem.never &&
                (!last || candidate == null || lastResort)) {
              if (width + item.width <= available + hang()) {
                candidate = i;
                lastResort = last;
              } else if (candidate == null) {
                end = i; // overfull, but the first chance to break
              }
            }
          case GlueItem(:final stretch):
            if (i > s && items[i - 1] is BoxItem && stretch.isFinite) {
              if (width <= available + hang()) {
                candidate = i;
                lastResort = false;
              } else {
                end = candidate ?? i;
              }
            }
            width += item.width;
          case BoxItem():
            width += item.width;
            lastBox = i;
            if (width > available + hang() && candidate != null) {
              end = candidate;
            }
        }
        if (end != null) break;
      }
      final at = end ?? items.length - 1;
      breaks.add(at);
      start = at + 1;
    }
    return breaks;
  }
}

/// The total-fit algorithm of Knuth and Plass ("Breaking paragraphs into
/// lines", Software: Practice and Experience 11, 1981), with TeX's
/// parameters (The TeXbook, chapter 14): the breaks that minimize the sum
/// of the lines' demerits, so spacing is even across the paragraph.
///
/// A line's badness is 100·r³, r how far its spaces stretch or shrink
/// (at most their shrink: never tighter); its demerits (l + b)² plus the
/// square of its break's penalty (less it, for a negative one), more for
/// two hyphenated lines in a row, a hyphenated next-to-last line, and
/// lines next to each other in fitness classes more than one apart
/// (tight, decent, loose, very loose). Breaks are tried within
/// [tolerance], then with [emergencyStretch] more on every line (TeX's
/// third pass), then at any looseness, and last one line at a time.
/// Every line knows its number, so lines of different widths (an indent,
/// a drop's lines, a runaround) are broken as well as the rest.
///
/// [raggedStretch] sets ragged lines as TeX's `\rightskip` does: each
/// line may fall short of the measure by that much at no more than a
/// badness of 100, its spaces keep their width, and the breaks that
/// even the lines' ends out the most are taken.
final class KnuthPlassLineBreaker extends ItemLineBreaker {
  /// A Knuth-Plass line breaker with TeX's default costs: [tolerance] a
  /// badness of 200, a [linePenalty] of 10, 10000 demerits for two
  /// hyphenated lines in a row ([flaggedDemerits]) or adjacent lines far
  /// apart in fitness ([fitnessDemerits]), and 5000 for a hyphenated
  /// next-to-last line ([finalHyphenDemerits]).
  const new({
    this.tolerance = 1.26,
    this.linePenalty = 10,
    this.flaggedDemerits = 10000,
    this.fitnessDemerits = 10000,
    this.finalHyphenDemerits = 5000,
    this.emergencyStretch = 0,
    this.raggedStretch,
    this.expansion = 0,
    this.maxHyphenRun,
    this.lastLineMin = 0,
    this.runtDemerits = 1000000,
  });

  /// The least a paragraph's last line should fill of its measure (a
  /// fraction, 0 for none): a shorter one, a runt, costs [runtDemerits],
  /// by default more than any line within the tolerance does, so the
  /// breaker takes one only when there is no other way.
  final double lastLineMin;

  /// The demerits of a last line shorter than [lastLineMin].
  final double runtDemerits;

  /// How much wider or narrower a line's letters may be set (font
  /// expansion, as pdfTeX's and microtype's: 0.02, their 20 thousandths,
  /// by the line, never penalised): stretch and shrink of that much of
  /// the line's text, besides its spaces' (Hàn Thế Thành, "Micro-
  /// typographic extensions to the TeX typesetting system", 2000).
  @override
  final double expansion;

  /// The most hyphenated lines in a row (none: no limit, as TeX, which
  /// only charges [flaggedDemerits]; the Chicago Manual of Style's three).
  final int? maxHyphenRun;

  /// The largest stretch ratio of a line in the first pass (1.26: a
  /// badness of 200, TeX's `\tolerance`).
  final double tolerance;

  /// The demerits of each line (TeX's `\linepenalty`).
  final double linePenalty;

  /// The demerits of two hyphenated lines in a row (TeX's
  /// `\doublehyphendemerits`).
  final double flaggedDemerits;

  /// The demerits of adjacent lines in very different fitness classes
  /// (TeX's `\adjdemerits`).
  final double fitnessDemerits;

  /// The demerits of a hyphenated next-to-last line (TeX's
  /// `\finalhyphendemerits`).
  final double finalHyphenDemerits;

  /// The stretch added to every line in the second pass, when the first
  /// found no breaks (TeX's `\emergencystretch`); 0 skips the pass.
  final double emergencyStretch;

  /// For ragged lines: how far short of the measure a line may fall (TeX's
  /// `\rightskip` stretch); `null` for justified lines.
  final double? raggedStretch;

  /// The breaks of [items] in [widths]; with [protrudeLeft] and
  /// [protrudeRight] (how far the item's first or last character may hang
  /// into the margin, by its index: a box, or the flagged penalty of a
  /// hyphen), each line is chosen as the wider measure its ends hang into
  /// (pdfTeX's `\pdfprotrudechars=2`).
  @override
  List<int> breakItems(
    List<LineItem> items,
    LineWidths widths, {
    double Function(int item)? protrudeLeft,
    double Function(int item)? protrudeRight,
  }) {
    // Running totals of the items before each index, the first item of
    // the line after a break at each index, and each line's width: the
    // same for every tolerance tried.
    final sums = _sumsOf(items);
    final protrusion = protrudeLeft == null && protrudeRight == null
        ? null
        : _protrusionOf(items, protrudeLeft, protrudeRight);
    final lineWidths = <double>[];
    double widthOf(int line) {
      while (lineWidths.length <= line) {
        lineWidths.add(widths(lineWidths.length));
      }
      return lineWidths[line];
    }

    // (TeX's easy_line, §848: the first line from which every line is as
    // wide as the one before, after which a break's line number makes no
    // difference to what can follow it, so breaks are no longer kept apart
    // by it. No paragraph has more lines than boxes.)
    var easy = 0;
    final boxes = items.whereType<BoxItem>().length;
    for (var line = 1; line <= boxes; line++) {
      if (widthOf(line) != widthOf(line - 1)) easy = line;
    }
    final passes = [
      (tolerance, 0.0),
      if (emergencyStretch > 0) (tolerance, emergencyStretch),
      (100.0, emergencyStretch),
    ];
    // (A pass whose best ends in a runt is kept while the passes with more
    // stretch are tried for a way without one; the last pass, at any
    // looseness, never takes its place.)
    List<int>? runt;
    for (final (i, (ratio, extra)) in passes.indexed) {
      final last = i == passes.length - 1;
      if (last && runt != null) return runt;
      final breaks = _total(
        items,
        sums,
        widthOf,
        ratio,
        extra,
        protrusion,
        easy: easy,
      );
      if (breaks == null) continue;
      if (last || !_endsInRunt(items, sums, widthOf, breaks)) return breaks;
      runt ??= breaks;
    }
    return runt ?? const FirstFitLineBreaker().breakItems(items, widths);
  }

  /// Whether the last line of [items] broken at [breaks] fills less of its
  /// measure than [lastLineMin].
  bool _endsInRunt(
    List<LineItem> items,
    (Float64List, Float64List, Float64List, Int32List, Int32List) sums,
    LineWidths widths,
    List<int> breaks,
  ) {
    if (lastLineMin <= 0 || breaks.isEmpty) return false;
    final (totalWidth, _, _, _, next) = sums;
    final position = breaks.length > 1 ? breaks[breaks.length - 2] : -1;
    final start = position < 0 ? 0 : next[position + 1];
    final end = breaks.last;
    final width = totalWidth[end] - totalWidth[start] + _carry(items, position);
    return width < lastLineMin * widths(breaks.length - 1);
  }

  /// How much wider a line from item `start` to the break at `at` is for
  /// what hangs at its ends.
  static double Function(int start, int at) _protrusionOf(
    List<LineItem> items,
    double Function(int item)? left,
    double Function(int item)? right,
  ) {
    // The last box before each index.
    final lastBox = Int32List(items.length + 1);
    var box = -1;
    for (var i = 0; i <= items.length; i++) {
      lastBox[i] = box;
      if (i < items.length && items[i] is BoxItem) box = i;
    }
    final lefts = <int, double>{};
    final rights = <int, double>{};
    return (start, at) {
      var extra = 0.0;
      if (left != null && start < items.length && items[start] is BoxItem) {
        extra += lefts[start] ??= left(start);
      }
      if (right != null) {
        final item = items[at];
        final last = item is PenaltyItem && item.flagged ? at : lastBox[at];
        if (last >= 0) extra += rights[last] ??= right(last);
      }
      return extra;
    };
  }

  /// The running totals of [items] before each index (their widths,
  /// stretch and shrink, expansion counted, and fills apart, so their
  /// totals subtract), and the first item of the line after a break at
  /// each index.
  (Float64List, Float64List, Float64List, Int32List, Int32List) _sumsOf(
    List<LineItem> items,
  ) {
    final n = items.length;
    final totalWidth = Float64List(n + 1);
    final totalStretch = Float64List(n + 1);
    final totalShrink = Float64List(n + 1);
    // Fills (infinite stretch) counted apart, so their totals subtract.
    final totalFills = Int32List(n + 1);
    for (var i = 0; i < n; i++) {
      final item = items[i];
      totalWidth[i + 1] =
          totalWidth[i] + (item is PenaltyItem ? 0 : item.width);
      final fill = item is GlueItem && item.stretch.isInfinite;
      // (Expansion: a share of the boxes' width too.)
      totalStretch[i + 1] =
          totalStretch[i] +
          (item is GlueItem && !fill ? item.stretch : 0) +
          (item is BoxItem ? item.width * expansion : 0);
      totalShrink[i + 1] =
          totalShrink[i] +
          (item is GlueItem ? item.shrink : 0) +
          (item is BoxItem ? item.width * expansion : 0);
      totalFills[i + 1] = totalFills[i] + (fill ? 1 : 0);
    }
    final next = Int32List(n + 1)..[n] = n;
    for (var i = n - 1; i >= 0; i--) {
      final discarded = switch (items[i]) {
        GlueItem() => true,
        PenaltyItem(:final isForced) => !isForced,
        BoxItem() => false,
      };
      next[i] = discarded ? next[i + 1] : i;
    }
    return (totalWidth, totalStretch, totalShrink, totalFills, next);
  }

  /// The line of [items] from [start] (after the break at [position]) to
  /// the break at [at], numbered [line]: how far its spaces stretch, its
  /// demerits after a line of [fitnessBefore] (hyphenated: [flaggedBefore]),
  /// and its fitness class.
  ({double ratio, double demerits, int fitness}) _line(
    List<LineItem> items,
    (Float64List, Float64List, Float64List, Int32List, Int32List) sums,
    LineWidths widths,
    int position,
    int start,
    int line,
    int at,
    double extraStretch, {
    required double penalty,
    required bool forced,
    required bool flagged,
    required bool flaggedBefore,
    required int fitnessBefore,
    double Function(int start, int at)? protrusion,
  }) {
    final (totalWidth, totalStretch, totalShrink, totalFills, _) = sums;
    final item = items[at];
    var width = totalWidth[at] - totalWidth[start] + _carry(items, position);
    if (item is PenaltyItem) width += item.width;
    // Ragged lines: their spaces as they are, and the line's end may
    // stretch by [raggedStretch].
    final ragged = raggedStretch;
    final stretch = totalFills[at] > totalFills[start]
        ? double.infinity
        : (ragged ?? totalStretch[at] - totalStretch[start]) + extraStretch;
    final shrink = ragged == null ? totalShrink[at] - totalShrink[start] : 0.0;
    final available = widths(line) + (protrusion?.call(start, at) ?? 0);
    final double ratio;
    if (width < available - _epsilon) {
      ratio = stretch > 0 ? (available - width) / stretch : double.infinity;
    } else if (width > available + _epsilon) {
      ratio = shrink > 0
          ? (available - width) / shrink
          : double.negativeInfinity;
    } else {
      ratio = 0;
    }
    // (math.pow's cube and square, multiplied as the VM's pow does.)
    final r = ratio.abs();
    final badness = 100 * (r * r * r);
    final base = linePenalty + badness;
    var demerits = base * base;
    if (penalty >= 0) {
      demerits += penalty * penalty;
    } else if (penalty > PenaltyItem.forced) {
      demerits -= penalty * penalty;
    }
    if (flagged && flaggedBefore) demerits += flaggedDemerits;
    // A runt: the paragraph's last line short of [lastLineMin].
    if (forced &&
        at == items.length - 1 &&
        lastLineMin > 0 &&
        width < lastLineMin * available) {
      demerits += runtDemerits;
    }
    // The paragraph's last line after a hyphenated one.
    if (forced && at == items.length - 1 && flaggedBefore) {
      demerits += finalHyphenDemerits;
    }
    final fitness = ratio < -0.5
        ? 0
        : ratio <= 0.5
        ? 1
        : ratio <= 1
        ? 2
        : 3;
    if ((fitness - fitnessBefore).abs() > 1) demerits += fitnessDemerits;
    return (ratio: ratio, demerits: demerits, fitness: fitness);
  }

  /// The total demerits of breaking [items] at [breaks] (the indices of
  /// the items broken at, the last the paragraph's end), as the first pass
  /// counts them; infinite when a line is overfull or past [tolerance]. For
  /// checking that the breaker finds the least there is.
  @visibleForTesting
  double demeritsOf(List<LineItem> items, LineWidths widths, List<int> breaks) {
    final sums = _sumsOf(items);
    final (_, _, _, _, next) = sums;
    var total = 0.0;
    var position = -1;
    var flagged = false;
    var fitness = 1;
    var run = 0;
    for (final (line, at) in breaks.indexed) {
      final item = items[at];
      final (:ratio, :demerits, fitness: lineFitness) = _line(
        items,
        sums,
        widths,
        position,
        position < 0 ? 0 : next[position + 1],
        line,
        at,
        0,
        penalty: item is PenaltyItem ? item.penalty : 0,
        forced: item is PenaltyItem && item.isForced,
        flagged: item is PenaltyItem && item.flagged,
        flaggedBefore: flagged,
        fitnessBefore: fitness,
      );
      if (ratio < -1 || ratio > tolerance) return double.infinity;
      final hyphenated = item is PenaltyItem && item.flagged;
      run = hyphenated ? run + 1 : 0;
      if (maxHyphenRun case final most? when run > most) {
        return double.infinity;
      }
      total += demerits;
      position = at;
      flagged = hyphenated;
      fitness = lineFitness;
    }
    return total;
  }

  List<int>? _total(
    List<LineItem> items,
    (Float64List, Float64List, Float64List, Int32List, Int32List) sums,
    LineWidths widths,
    double limit,
    double extraStretch,
    double Function(int start, int at)? protrusion, {
    int? easy,
  }) {
    final (totalWidth, totalStretch, totalShrink, totalFills, next) = sums;
    final n = items.length;
    var active = <_Node>[
      _Node(-1, 0, 1, 0, null, flagged: false, start: 0, hyphens: 0),
    ];
    var survivors = <_Node>[];
    // The best break at this index for each fitness class and line count,
    // in the order they were first found.
    final bestFitness = <int>[];
    final bestLine = <int>[];
    final bestHyphens = <int>[];
    final best = <_Node>[];
    final hyphenLimit = maxHyphenRun;
    for (var i = 0; i < n; i++) {
      final item = items[i];
      final penalty = switch (item) {
        PenaltyItem(:final penalty) when penalty < PenaltyItem.never => penalty,
        GlueItem(:final stretch)
            when i > 0 && items[i - 1] is BoxItem && stretch.isFinite =>
          0.0,
        _ => null,
      };
      if (penalty == null) continue;
      final flagged = item is PenaltyItem && item.flagged;
      final forced = item is PenaltyItem && item.isForced;
      bestFitness.clear();
      bestLine.clear();
      bestHyphens.clear();
      best.clear();
      survivors.clear();
      for (final node in active) {
        final (:ratio, :demerits, :fitness) = _line(
          items,
          sums,
          widths,
          node.position,
          node.start,
          node.line,
          i,
          extraStretch,
          penalty: penalty,
          forced: forced,
          flagged: flagged,
          flaggedBefore: node.flagged,
          fitnessBefore: node.fitness,
          protrusion: protrusion,
        );
        if (ratio >= -1 && !forced) survivors.add(node);
        if (ratio < -1 || ratio > limit) continue;
        // (Hyphenated lines in a row: no more than [maxHyphenRun]; the
        // run is part of the state the best break is kept for.)
        final hyphens = flagged ? node.hyphens + 1 : 0;
        if (hyphenLimit != null && hyphens > hyphenLimit) continue;
        final run = hyphenLimit == null ? 0 : hyphens;
        final total = node.demerits + demerits;
        final line = node.line + 1;
        // (Past the easy line, one class for all the lines' numbers.)
        final lineClass = easy != null && line > easy ? easy + 1 : line;
        var at = 0;
        while (at < best.length &&
            (bestFitness[at] != fitness ||
                bestLine[at] != lineClass ||
                bestHyphens[at] != run)) {
          at++;
        }
        if (at == best.length || total < best[at].demerits) {
          final found = _Node(
            i,
            line,
            fitness,
            total,
            node,
            flagged: flagged,
            start: next[i + 1],
            hyphens: hyphens,
          );
          if (at == best.length) {
            bestFitness.add(fitness);
            bestLine.add(lineClass);
            bestHyphens.add(run);
            best.add(found);
          } else {
            best[at] = found;
          }
        }
      }
      // The survivors, then the new breaks, are the active ones.
      final kept = survivors..addAll(best);
      survivors = active;
      active = kept;
      if (active.isEmpty) return null;
    }
    final finals = active.where((node) => node.position == n - 1);
    if (finals.isEmpty) return null;
    var node = finals.reduce((a, b) => a.demerits <= b.demerits ? a : b);
    final breaks = <int>[];
    for (_Node? at = node; at != null && at.position >= 0; at = at.previous) {
      breaks.add(at.position);
      node = at;
    }
    return breaks.reversed.toList();
  }
}

final class _Node {
  new(
    this.position,
    this.line,
    this.fitness,
    this.demerits,
    this.previous, {
    required this.flagged,
    required this.start,
    required this.hyphens,
  });

  /// The item the break is at (-1 for the start of the paragraph).
  final int position;

  /// The number of lines before the break.
  final int line;

  final int fitness;
  final double demerits;
  final _Node? previous;
  final bool flagged;

  /// The first item of the line after the break.
  final int start;

  /// How many hyphenated lines in a row end at the break.
  final int hyphens;
}

const double _epsilon = 1e-6;

/// The width of the hyphen a line starts with after a break at [at] (see
/// [PenaltyItem.carry]); 0 at the paragraph's start.
double _carry(List<LineItem> items, int at) =>
    switch (at >= 0 ? items[at] : null) {
      PenaltyItem(:final carry) => carry,
      _ => 0,
    };

/// The first index from [start] that isn't glue or a penalty that
/// doesn't force a break (what a line break discards).
int _skipDiscardable(List<LineItem> items, int start) {
  var i = start;
  while (i < items.length &&
      (items[i] is GlueItem ||
          (items[i] is PenaltyItem && !(items[i] as PenaltyItem).isForced))) {
    i++;
  }
  return i;
}

/// Whether [run]'s words are kept whole by [wordBreak].
bool _keepsAll(WordBreak wordBreak, TextRun? run) => switch (wordBreak) {
  WordBreak.normal => false,
  WordBreak.keepAll => true,
  WordBreak.auto => _isKorean(run?.style.language),
};

bool _isKorean(String? language) {
  if (language == null) return false;
  final primary = language.toLowerCase().split(RegExp('[-_]')).first;
  return primary == 'ko' || primary == 'kor';
}

/// Whether the break at [at] in [text] is between two letters, digits,
/// Han characters or Hangul syllables (the classes CSS's `keep-all` keeps
/// together: AL, AI, NU, ID and Hangul's H2, H3, JL, JV, JT).
bool _inWord(String text, int at) =>
    at > 0 &&
    at < text.length &&
    _keptTogether(lineBreakClass(_runeBefore(text, at))) &&
    _keptTogether(lineBreakClass(_runeAt(text, at)));

int _runeBefore(String text, int at) {
  final low = text.codeUnitAt(at - 1);
  if (low >= 0xdc00 && low <= 0xdfff && at >= 2) {
    final high = text.codeUnitAt(at - 2);
    if (high >= 0xd800 && high <= 0xdbff) {
      return 0x10000 + ((high - 0xd800) << 10) + (low - 0xdc00);
    }
  }
  return low;
}

int _runeAt(String text, int at) {
  final high = text.codeUnitAt(at);
  if (high >= 0xd800 && high <= 0xdbff && at + 1 < text.length) {
    final low = text.codeUnitAt(at + 1);
    if (low >= 0xdc00 && low <= 0xdfff) {
      return 0x10000 + ((high - 0xd800) << 10) + (low - 0xdc00);
    }
  }
  return high;
}

bool _keptTogether(LineBreakClass c) => switch (c) {
  LineBreakClass.al ||
  LineBreakClass.ai ||
  LineBreakClass.nu ||
  LineBreakClass.id ||
  LineBreakClass.h2 ||
  LineBreakClass.h3 ||
  LineBreakClass.jl ||
  LineBreakClass.jv ||
  LineBreakClass.jt => true,
  _ => false,
};

/// Where the middles of an underline and a strike-through go in text in
/// [style] on the baseline [y] (up the page): under the baseline and
/// across the middle of the lower-case letters. In vertical text the
/// strike-through runs down the middle of the em box through [upright]
/// glyphs (Han, kana), through the middle of the letters of those on
/// their side (Latin, Mongolian; mirrored with them in a mirrored
/// frame's flipped text), and Japanese and Korean put their
/// underline on the right of the column, the line's over side (CSS Text
/// Decoration 3, `text-underline-position: right`; JLREQ's side lines);
/// Chinese keeps it on the left, and Mongolian, flipped in vertical-lr's
/// mirrored frame, on the right (mlreq 6.2.1, its right line).
(double, double) decorationLines(
  TextStyle style,
  double y, {
  bool upright = false,
}) {
  final font = style.font;
  final scale = style.size / 1000;
  final under = y + font.underlinePosition * scale;
  final letters = y + font.xHeight * scale / 2;
  if (!style.vertical && !style.flipped) return (under, letters);
  final middle = y + (font.ascender + font.descender) * scale / 2;
  final strike = upright
      ? middle
      : style.flipped
      ? 2 * middle - letters
      : letters;
  final primary = (style.language ?? '').toLowerCase().split(RegExp('[-_]'));
  final over =
      style.vertical &&
      !style.flipped &&
      const {'ja', 'jpn', 'ko', 'kor'}.contains(primary.first);
  return (over ? 2 * middle - under : under, strike);
}

/// The items of [paragraph]: its words as boxes, its spaces as glue, its
/// other break opportunities (UAX #14) as penalties, its hard breaks as
/// forced penalties. Soft hyphens, and the hyphenator's points, give
/// flagged penalties. With [maxWidth], a box wider than it is split into
/// characters with costly breaks between them.
List<LineItem> paragraphItems(Paragraph paragraph, {double? maxWidth}) {
  final contents = [
    for (final content in paragraph.content)
      ...switch (content) {
        PageReference(:final placeholder) => [content.resolve(placeholder)],
        TextRun(fallbackFonts: [_, ...]) => _withFallbacks(content),
        _ => [content],
      },
  ];
  final text = StringBuffer();
  for (final content in contents) {
    text.write(switch (content) {
      TextRun(:final text) => text,
      // U+FFFC OBJECT REPLACEMENT CHARACTER.
      InlineImage() => '\u{fffc}',
      PageReference(:final placeholder) => placeholder,
    });
  }
  final whole = text.toString();
  final breaks = lineBreakOffsets(
    whole,
    strictness: paragraph.lineBreak,
    chineseOrJapanese: paragraph.content.any(
      (c) =>
          c is TextRun &&
          RegExp(
            r'^(zh|ja|yue|cmn|wuu|hak|nan|gan|hsn|cjy|lzh)([-_]|$)',
            caseSensitive: false,
          ).hasMatch(c.style.language ?? ''),
    ),
  );
  // The first break opportunity not before the offset last asked about
  // (breakBefore is asked about offsets in order).
  var nextBreak = 0;
  final items = <LineItem>[];
  final word = StringBuffer();
  TextRun? wordRun;
  TextRun? lastRun;
  var softHyphen = false;

  void flush() {
    final run = wordRun;
    if (run == null || word.isEmpty) return;
    final piece = word.toString();
    word.clear();
    final hyphenator = paragraph.hyphenator;
    final points = hyphenator == null || !_isWord(piece)
        ? const <int>[]
        : hyphenator.hyphenate(piece);
    var from = 0;
    for (final point in [
      ...points.where((p) => p > 0 && p < piece.length),
    ]..sort()) {
      final part = piece.substring(from, point);
      items
        ..add(BoxItem(run, part, run.style.measure(part)))
        ..add(PenaltyItem(run.style.measure('-'), 50, flagged: true, run: run));
      from = point;
    }
    final rest = piece.substring(from);
    items.add(BoxItem(run, rest, run.style.measure(rest)));
  }

  // East Asian glue where the line may break at [at] (not after a
  // hyphen, nor after glue).
  GlueItem? eastAsianGlueAt(int at) {
    final run = lastRun;
    if (!paragraph.eastAsian ||
        run == null ||
        items.lastOrNull is GlueItem ||
        whole.codeUnitAt(at - 1) == 0x2d) {
      return null;
    }
    return _eastAsianGlue(whole, at, run.style);
  }

  var offset = 0;
  // (Whether spaces were the last of the text.)
  var spaced = false;
  void breakBefore(int at, {bool space = false}) {
    if (at == 0) return;
    while (nextBreak < breaks.length && breaks.offsetAt(nextBreak) < at) {
      nextBreak++;
    }
    final segments =
        paragraph.breakOpportunities == BreakOpportunities.spacesAndHyphens;
    var opportunity =
        nextBreak < breaks.length && breaks.offsetAt(nextBreak) == at;
    // (Breaking at spaces and after hyphens alone, but where a line must
    // end: no rule keeps a space from breaking either.)
    if (segments &&
        opportunity &&
        !breaks.isMandatoryAt(nextBreak) &&
        whole.codeUnitAt(at - 1) != 0x2d) {
      opportunity = false;
    }
    // (Korean, or `keepAll`: no break inside a word, CSS's `keep-all`.)
    if (opportunity &&
        !breaks.isMandatoryAt(nextBreak) &&
        _keepsAll(paragraph.wordBreak, lastRun) &&
        _inWord(whole, at)) {
      opportunity = false;
    }
    // (Spaces before what no line may start with, a closing bracket or a
    // slash, or after an opening one: no break at them, UAX #14's LB13 and
    // LB14.)
    final afterSpaces = spaced && !space && !segments;
    if (!space) spaced = false;
    if (afterSpaces && !opportunity && items.lastOrNull is GlueItem) {
      var first = items.length;
      while (first > 0 && items[first - 1] is GlueItem) {
        first--;
      }
      items.insert(first, const PenaltyItem(0, PenaltyItem.never));
    }
    if (opportunity && breaks.isMandatoryAt(nextBreak)) {
      flush();
      items
        ..add(const GlueItem.fill())
        ..add(PenaltyItem(0, PenaltyItem.forced, run: lastRun));
    } else if (opportunity) {
      flush();
      if (lastRun case final run? when softHyphen) {
        items.add(
          PenaltyItem(run.style.measure('-'), 50, flagged: true, run: run),
        );
      } else if (eastAsianGlueAt(at) case final glue?) {
        // (Where text written without spaces may break: its stretch; a
        // quarter em between Han or kana and Latin.)
        items.add(glue);
      } else if (items.lastOrNull is! GlueItem) {
        // After a compound's hyphen, a hyphenated break (TeX's explicit
        // hyphens, \exhyphenpenalty 50), the hyphen repeated on the next
        // line where the language has it so.
        final run = lastRun;
        final hyphen = whole.codeUnitAt(at - 1) == 0x2d;
        final repeat =
            run != null &&
            hyphen &&
            paragraph.hyphenRepetition.repeatsBefore(whole.substring(at));
        items.add(
          PenaltyItem(
            0,
            hyphen ? 50 : 0,
            flagged: hyphen,
            run: run,
            carry: repeat ? run.style.measure('-') : 0,
          ),
        );
      }
    }
    softHyphen = false;
  }

  for (final content in contents) {
    switch (content) {
      case PageReference():
        break; // resolved above
      case InlineImage(:final width):
        breakBefore(offset);
        flush();
        items.add(BoxItem(content, '', width));
        offset += 1;
      // A run of spaces in a slot of its own width: a space that neither
      // stretches nor shrinks (a term's gap before its description).
      case TextRun(:final text, :final slotWidth?)
          when text.isNotEmpty &&
              text.runes.every((r) => r == 0x20 || r == 0x09):
        breakBefore(offset, space: true);
        flush();
        items.add(GlueItem(content, text, slotWidth, 0, 0));
        spaced = true;
        lastRun = content;
        offset += text.length;
      // A run in a slot of its own width: one box, as an image is.
      case TextRun(:final text, :final slotWidth?):
        breakBefore(offset);
        flush();
        items.add(BoxItem(content, text, slotWidth));
        lastRun = content;
        offset += text.length;
      // An anchor with no text of its own (a destination where it is):
      // a box of no width, for the line to place it.
      case TextRun(:final text, anchor: _?) when text.isEmpty:
        flush();
        items.add(BoxItem(content, '', 0));
      case TextRun(:final text, :final style):
        final shrink = paragraph.align == TextAlign.justify
            ? style.measure(' ') / 3
            : 0.0;
        // (A run set flush right, as TeX sets a citation: the space before
        // it taken away; no break, a fill, a break, two spaces, an empty
        // box, no break, a fill: at the end of the line when it fits there,
        // else on a line of its own, flush right either way.)
        final flushing = content.flushRight && !identical(lastRun, content);
        if (flushing) {
          flush();
          while (items.isNotEmpty && items.last is GlueItem) {
            items.removeLast();
          }
          items
            ..add(PenaltyItem(0, PenaltyItem.never, run: content))
            ..add(const GlueItem.fill())
            ..add(PenaltyItem(0, 50, run: content))
            ..add(GlueItem(null, '', style.measure('  '), 0, 0))
            ..add(BoxItem(content, '', 0))
            ..add(PenaltyItem(0, PenaltyItem.never, run: content))
            ..add(const GlueItem.fill());
        }
        if (wordRun != content) flush();
        wordRun = content;
        lastRun = content;
        for (final rune in text.runes) {
          // (A run set flush right kept whole.)
          if (!content.flushRight) {
            breakBefore(offset, space: rune == 0x20 || rune == 0x09);
          } else if (rune == 0x20 || rune == 0x09) {
            flush();
            items.add(PenaltyItem(0, PenaltyItem.never, run: content));
          }
          wordRun = content;
          final length = rune > 0xffff ? 2 : 1;
          switch (rune) {
            case 0x0a || 0x0b || 0x0c || 0x0d || 0x85 || 0x2028 || 0x2029:
              break; // a hard break, already a forced penalty
            case 0x20 || 0x09:
              flush();
              final space = style.measure(' ');
              // Spaces only shrink in justified text: elsewhere nothing
              // would shrink them when the line is drawn.
              items.add(GlueItem(content, ' ', space, space / 2, shrink));
              spaced = true;
            case 0xad:
              // (Where a run set flush right is kept whole, not shown.)
              softHyphen = !content.flushRight;
            case 0x200b || 0x2060 || 0xfeff:
              break; // zero width, not drawn
            default:
              word.writeCharCode(rune);
          }
          offset += length;
        }
        flush();
    }
  }
  flush();
  // (A paragraph that ends in a soft hyphen, a line set apart from the
  // rest of its last word: the hyphen shown, as a line hyphenated there
  // shows it.)
  if (softHyphen && lastRun != null) {
    final run = lastRun;
    final mark = run.style.font.covers(0xad) ? '\u00ad' : '-';
    items.add(BoxItem(run, mark, run.style.measure('-')));
  }
  if (items.isEmpty) return items;
  _measureWithinWords(items);
  // (No fill after a run set flush right that ends the paragraph: TeX's
  // `\parfillskip=0pt`.)
  if (lastRun?.flushRight != true) items.add(const GlueItem.fill());
  items.add(PenaltyItem(0, PenaltyItem.forced, run: lastRun));
  return maxWidth == null ? items : _splitWide(items, maxWidth);
}

/// [items] with each piece of a word that a break divides (at a soft
/// hyphen, a hyphenation point, after a hyphen) as wide as it is within
/// the word: the word up to its end measured less the word before it, so
/// the kerning and any ligature across the break count with the piece
/// after it and the pieces add up to the word as it is drawn whole.
void _measureWithinWords(List<LineItem> items) {
  TextRun? run;
  var soFar = '';
  for (var i = 0; i < items.length; i++) {
    switch (items[i]) {
      // (A break within the word.)
      case PenaltyItem(isForced: false):
        continue;
      case BoxItem(content: final TextRun next, :final text)
          when text.isNotEmpty:
        if (identical(next, run) && soFar.isNotEmpty) {
          final style = next.style;
          final word = '$soFar$text';
          items[i] = BoxItem(
            next,
            text,
            style.measure(word) - style.measure(soFar),
          );
          soFar = word;
        } else {
          run = next;
          soFar = text;
        }
      case _:
        run = null;
        soFar = '';
    }
  }
}

/// [run] split where its font lacks characters a fallback font has, a
/// grapheme cluster at a time: a base and its combining marks, an emoji
/// sequence, set in one font (the first that has all of it, else the one
/// that has its first character); an emoji sequence shown as an emoji
/// (UTS #51), in the first of the fonts with color glyphs that has it.
List<TextRun> _withFallbacks(TextRun run) {
  final primary = run.style.font;
  Font fontFor(String cluster) {
    final runes = cluster.runes.toList();
    if (emojiSequenceLength(runes, 0) == runes.length) {
      for (final font in [primary, ...run.fallbackFonts]) {
        if (font case OpenTypeTextFont(font: final program)
            when program.colorGlyphs != null &&
                runes.every((r) => isDefaultIgnorable(r) || font.covers(r))) {
          return font;
        }
      }
    }
    if (runes.every((rune) => primary.covers(rune) || rune <= 0x20)) {
      return primary;
    }
    for (final font in run.fallbackFonts) {
      if (runes.every(font.covers)) return font;
    }
    if (primary.covers(runes.first)) return primary;
    for (final font in run.fallbackFonts) {
      if (font.covers(runes.first)) return font;
    }
    return primary;
  }

  final runs = <TextRun>[];
  final text = StringBuffer();
  Font? current;
  void flush() {
    if (text.isEmpty) return;
    final piece = run.withText(text.toString());
    runs.add(
      identical(current, primary)
          ? piece
          : piece.withStyle(run.style.copyWith(font: current)),
    );
    text.clear();
  }

  for (final cluster in _clusters(run.text)) {
    // Spaces and controls stay with the font around them.
    final font = cluster.runes.first <= 0x20 && current != null
        ? current
        : fontFor(cluster);
    if (!identical(font, current)) {
      flush();
      current = font;
    }
    text.write(cluster);
  }
  flush();
  return runs;
}

/// [text] in its grapheme clusters, as near as the line breaking classes
/// tell them (UAX #14's, not UAX #29's tables): a character with the
/// combining marks after it (class CM), a sequence joined by zero width
/// joiners (ZWJ) with its emoji modifiers (EM), a pair of regional
/// indicators (RI, a flag); a cluster is never split between lines or
/// fonts.
List<String> _clusters(String text) {
  final clusters = <String>[];
  final cluster = StringBuffer();
  int? previous;
  var indicators = 0;
  for (final rune in text.runes) {
    final kind = lineBreakClass(rune);
    final joins =
        previous != null &&
        (kind == LineBreakClass.cm ||
            kind == LineBreakClass.zwj ||
            kind == LineBreakClass.em ||
            lineBreakClass(previous) == LineBreakClass.zwj ||
            (kind == LineBreakClass.ri && indicators.isOdd));
    if (!joins && cluster.isNotEmpty) {
      clusters.add(cluster.toString());
      cluster.clear();
    }
    indicators = kind == LineBreakClass.ri ? indicators + 1 : 0;
    cluster.writeCharCode(rune);
    previous = rune;
  }
  if (cluster.isNotEmpty) clusters.add(cluster.toString());
  return clusters;
}

/// The glue between the characters of [text] around [at] where a line
/// may break there, for East Asian composition: a quarter em of [style]'s size
/// between Han or kana and Latin, stretching and shrinking by an eighth;
/// none, stretching by a quarter, between characters written without
/// spaces; else null.
GlueItem? _eastAsianGlue(String text, int at, TextStyle style) {
  final size = style.size;
  final before = text.codeUnitAt(at - 1);
  final after = text.codeUnitAt(at);
  final a = before & 0xfc00 == 0xdc00 && at >= 2
      ? text.runes.elementAt(text.substring(0, at).runes.length - 1)
      : before;
  final b = after & 0xfc00 == 0xd800 && at + 1 < text.length
      ? 0x10000 + ((after & 0x3ff) << 10) + (text.codeUnitAt(at + 1) & 0x3ff)
      : after;
  // (Digits set across a vertical line, upright, are set as an
  // ideograph: no quarter em.)
  final combined = style.combinesAt(text, at - 1) || style.combinesAt(text, at);
  // (JLREQ 3.8: the quarter em beside Latin stretching to half an em and
  // shrinking to an eighth; between characters a quarter em more, a
  // mark's blank half shrinking to nothing.)
  if (cjkWesternBoundary(a, b) && !combined) {
    return GlueItem(null, '', size / 4, size / 4, size / 8);
  }
  if (combined && (isSpaceless(a) || isSpaceless(b))) {
    return GlueItem(null, '', 0, size / 4, 0);
  }
  if (isSpaceless(a) && isSpaceless(b)) {
    return GlueItem(
      null,
      '',
      0,
      size / 4,
      size * markBlankBetween(a, b, style.language),
    );
  }
  return null;
}

/// Whether [text] is a word to hyphenate: letters, and the marks and
/// joiners on them (vowel signs, viramas, accents; the aksara classes of
/// the Brahmic scripts), a letter first.
bool _isWord(String text) {
  var first = true;
  for (final c in text.runes) {
    final ok = switch (lineBreakClass(c)) {
      LineBreakClass.al ||
      LineBreakClass.hl ||
      LineBreakClass.ak ||
      LineBreakClass.as_ => true,
      LineBreakClass.cm ||
      LineBreakClass.zwj ||
      LineBreakClass.ap ||
      LineBreakClass.vi ||
      LineBreakClass.vf => !first,
      _ => false,
    };
    if (!ok) return false;
    first = false;
  }
  return !first;
}

/// [items] with each box wider than [maxWidth] split into its grapheme
/// clusters, with costly breaks between them.
List<LineItem> _splitWide(List<LineItem> items, double maxWidth) {
  // The words wider than a line: runs of boxes with no break between them
  // (a word in several styles, or across anchors, is one word).
  final wide = <int>{};
  var start = 0;
  var width = 0.0;
  void close(int end) {
    if (width > maxWidth + _epsilon) {
      for (var i = start; i < end; i++) {
        wide.add(i);
      }
    }
  }

  for (final (i, item) in items.indexed) {
    if (item is BoxItem) {
      if (i == 0 || items[i - 1] is! BoxItem) {
        start = i;
        width = 0;
      }
      width += item.width;
      if (i + 1 == items.length || items[i + 1] is! BoxItem) close(i + 1);
    }
  }
  if (wide.isEmpty) return items;
  return [
    for (final (index, item) in items.indexed)
      if (item case BoxItem(content: final TextRun run, :final text)
          when wide.contains(index) && run.slotWidth == null) ...[
        // (Between the word's boxes too.)
        if (index > 0 && wide.contains(index - 1) && text.isNotEmpty)
          PenaltyItem(0, 1000, run: run),
        // (Between grapheme clusters, never inside one.)
        for (final (i, char) in _clusters(text).indexed) ...[
          if (i > 0) PenaltyItem(0, 1000, run: run),
          BoxItem(run, char, run.style.measure(char)),
        ],
        if (text.isEmpty) item,
      ] else
        item,
  ];
}

/// A piece of a line.
@immutable
sealed class LineFragment {
  const new _(this.x, this.width);

  /// The offset from the line's start, in points.
  final double x;

  /// The width, in points.
  final double width;
}

/// Text of one run on a line.
final class TextFragment extends LineFragment {
  /// [glyphs] of [run] set in [style] at [x], [rightToLeft] where they
  /// are a right-to-left run's, drawn in visual order.
  const new(
    super.x,
    super.width,
    this.run,
    this.text,
    this.glyphs,
    this.style, {
    this.rightToLeft = false,
  }) : super._();

  /// Whether the glyphs are a right-to-left run's, in visual order.
  final bool rightToLeft;

  /// The run the text comes from.
  final TextRun run;

  /// The text (with its spaces).
  final String text;

  /// The shaped glyphs.
  final List<ShapedGlyph> glyphs;

  /// The style it is drawn in: the run's, with the word spacing that
  /// justifies the line.
  final TextStyle style;
}

/// An inline image on a line.
final class ImageFragment extends LineFragment {
  /// [image] at [x], its bottom [bottom] points above the baseline.
  const new(super.x, super.width, this.image, this.bottom) : super._();

  /// The image.
  final InlineImage image;

  /// The offset of its bottom from the baseline (negative: below it).
  final double bottom;
}

/// A line of a paragraph, ready to paint.
@immutable
final class Line {
  /// A line of [fragments].
  const new(
    this.fragments, {
    required this.width,
    required this.height,
    required this.baseline,
    required this.ascent,
    required this.descent,
    required this.hyphenated,
    this.readingOrder,
  });

  /// The fragments, left to right, positioned for the alignment.
  final List<LineFragment> fragments;

  /// Where the line's text was put in visual order (right-to-left text),
  /// the indices of its [fragments] in reading order; null where the two
  /// orders are the same.
  final List<int>? readingOrder;

  /// The [fragments] in reading order: the order the text is read in, and
  /// its anchors (a footnote's reference) come in.
  Iterable<LineFragment> get fragmentsInReadingOrder => switch (readingOrder) {
    null => fragments,
    final order => order.map((i) => fragments[i]),
  };

  /// The width of the content, in points.
  final double width;

  /// The height the line takes, in points.
  final double height;

  /// The baseline's distance from the top of the line.
  final double baseline;

  /// The height of the content above the baseline.
  final double ascent;

  /// The depth of the content below the baseline (negative).
  final double descent;

  /// Whether the line ends with a hyphen the break added.
  final bool hyphenated;

  /// Paints the line with its top-left corner at ([x], [top]), reporting
  /// the rectangles of links to [link] and the positions of anchors to
  /// [anchor].
  void paint(
    Canvas canvas,
    double x,
    double top, {
    void Function(Rect rect, LinkTarget target)? link,
    void Function(String name, double x, double y)? anchor,
  }) {
    final y = top - baseline;
    for (var i = 0; i < fragments.length; i++) {
      final fragment = fragments[i];
      final left = x + fragment.x;
      // (The pieces of a split graphic beside one another on the line:
      // drawn as one.)
      if (fragment case ImageFragment(
        image: InlineImage(image: final SplitGraphic split),
      )) {
        final pieces = <(SplitGraphic, Rect)>[];
        var j = i;
        while (j < fragments.length) {
          final next = fragments[j];
          if (next case ImageFragment(:final image, :final bottom)
              when image.image is SplitGraphic &&
                  (image.image as SplitGraphic).group == split.group) {
            pieces.add((
              image.image as SplitGraphic,
              Rect(x + next.x, y + bottom, image.width, image.height),
            ));
            if (image.link case final target? when link != null) {
              link(
                Rect(x + next.x, y + bottom, image.width, image.height),
                target,
              );
            }
            j++;
          } else {
            break;
          }
        }
        split.paintPieces(canvas, pieces);
        i = j - 1;
        continue;
      }
      switch (fragment) {
        case TextFragment(
          :final run,
          :final glyphs,
          :final style,
          :final text,
          :final rightToLeft,
        ):
          final font = style.font;
          final size = style.size;
          if (run.decoration case final decoration?) {
            _decorate(
              canvas,
              decoration,
              Rect(
                left - decoration.padding,
                y + font.descender * size / 1000 - decoration.outset,
                fragment.width + 2 * decoration.padding,
                (font.ascender - font.descender) * size / 1000 +
                    2 * decoration.outset,
              ),
            );
          }
          canvas.save();
          if (run.color case final color?) canvas.setFillColor(color);
          if (run.artifact) canvas.beginMarkedContent('Span', actualText: '');
          // (In its slot, as aligned there: by its glyphs' advances, the
          // tracking after them aside.)
          final advances =
              style.widthOf(glyphs) - style.characterSpacing * glyphs.length;
          final inSlot = switch ((run.slotWidth, run.slotAlign)) {
            (null, _) || (_, TextAlign.left || TextAlign.justify) => 0.0,
            (_, TextAlign.center) => (fragment.width - advances) / 2,
            (_, TextAlign.right) => fragment.width - advances,
          };
          canvas.glyphs(
            glyphs,
            left + inSlot,
            y,
            style,
            // (What they stand for, as drawn: a backend's map from glyphs
            // to text may not give it back. None for decoration.)
            text: run.artifact
                ? null
                : rightToLeft
                ? String.fromCharCodes(text.runes.toList().reversed)
                : text,
          );
          if (run.artifact) canvas.endMarkedContent();
          if (run.emphasisMark case final mark?) {
            paintEmphasisMarks(
              canvas,
              glyphs,
              left + inSlot,
              y,
              style,
              mark,
              under: run.emphasisUnder,
              color: run.color,
            );
          }
          final thickness = font.underlineThickness * size / 1000;
          final (underlineY, strikeY) = decorationLines(
            style,
            y,
            upright: glyphs.any((g) => g.upright),
          );
          if (run.underline) {
            canvas
              ..rect(
                Rect(
                  left,
                  underlineY - thickness / 2,
                  fragment.width,
                  thickness,
                ),
              )
              ..fill();
          }
          if (run.strikethrough) {
            canvas
              ..rect(
                Rect(left, strikeY - thickness / 2, fragment.width, thickness),
              )
              ..fill();
          }
          canvas.restore();
          if (run.link case final target? when link != null) {
            link(
              Rect(
                left,
                y + font.descender * size / 1000,
                fragment.width,
                (font.ascender - font.descender) * size / 1000,
              ),
              target,
            );
          }
          if (run.anchor case final name? when anchor != null) {
            anchor(
              name,
              left,
              y + (run.anchorOnBaseline ? 0 : font.ascender * size / 1000),
            );
          }
        case ImageFragment(:final image, :final bottom):
          image.image.paint(
            canvas,
            Rect(left, y + bottom, image.width, image.height),
          );
          if (image.link case final target? when link != null) {
            link(Rect(left, y + bottom, image.width, image.height), target);
          }
      }
    }
  }
}

/// How far emphasis marks on text in [style] reach past the text's
/// ascender (or descender): seven twentieths of its size.
double emphasisExtent(TextStyle style) => style.size * 0.35;

/// Draws emphasis [mark] over (or, [under], under) each of [glyphs] that
/// starts a character, but spaces and punctuation, the glyphs drawn from
/// [x] on baseline [y] in [style], in [color]: centered on the character,
/// a fifth of the size past the text's ascender (or descender), in the
/// band [emphasisExtent] reserves. CSS's marks (dot, circle, double
/// circle, triangle, sesame; filled or open) are drawn as shapes, the same
/// in every font; another character is the font's glyph at half the size.
/// Marked as reading as nothing.
void paintEmphasisMarks(
  Canvas canvas,
  List<ShapedGlyph> glyphs,
  double x,
  double y,
  TextStyle style,
  String mark, {
  bool under = false,
  Color? color,
}) {
  final size = style.size;
  final font = style.font;
  final centreY = under
      ? y + font.descender * size / 1000 - size * 0.2
      : y + font.ascender * size / 1000 + size * 0.2;
  final markStyle = TextStyle(font, size / 2);
  final markGlyphs = markStyle.shape(mark);
  final markWidth = markStyle.widthOf(markGlyphs);
  final scale = style.horizontalScaling / 100;
  var pen = x;
  canvas
    ..save()
    ..beginMarkedContent('Span', actualText: '')
    ..setLineWidth(size * 0.03);
  if (color != null) {
    canvas
      ..setFillColor(color)
      ..setStrokeColor(color);
  }
  for (final (i, glyph) in glyphs.indexed) {
    final advance =
        (glyph.advance * size / 1000 +
            style.characterSpacing +
            (glyph.text == ' ' ? style.wordSpacing : 0)) *
        scale;
    final c = glyph.text.isEmpty ? null : glyph.text.runes.first;
    if (c != null && glyph.advance != 0 && !isMark(c) && !_unemphasized(c)) {
      final cx = pen + glyph.xOffset * size / 1000 * scale + advance / 2;
      if (!_drawEmphasisShape(canvas, mark, cx, centreY, size)) {
        canvas.glyphs(
          markGlyphs,
          cx - markWidth / 2,
          centreY - (font.ascender + font.descender) * size / 4000,
          markStyle,
        );
      }
    }
    pen += advance;
    if (i < glyphs.length - 1) pen += glyph.kerning * size / 1000 * scale;
  }
  canvas
    ..endMarkedContent()
    ..restore();
}

/// Draws CSS's emphasis mark [mark] (its character: • ◦ ● ○ ◉ ◎ ▲ △ ﹅ ﹆)
/// centered at ([cx], [cy]) for text of [size]; false for another mark.
bool _drawEmphasisShape(
  Canvas canvas,
  String mark,
  double cx,
  double cy,
  double size,
) {
  void triangle(double side) {
    final h = side * 0.866;
    canvas
      ..moveTo(cx - side / 2, cy - h / 3)
      ..lineTo(cx + side / 2, cy - h / 3)
      ..lineTo(cx, cy + 2 * h / 3)
      ..closePath();
  }

  void sesame() {
    canvas
      ..save()
      ..translate(cx, cy)
      ..rotate(-40)
      ..ellipse(0, 0, size * 0.05, size * 0.11);
  }

  switch (mark) {
    case '\u2022':
      canvas
        ..circle(cx, cy, size * 0.07)
        ..fill();
    case '\u25e6':
      canvas
        ..circle(cx, cy, size * 0.07)
        ..stroke();
    case '\u25cf':
      canvas
        ..circle(cx, cy, size * 0.12)
        ..fill();
    case '\u25cb':
      canvas
        ..circle(cx, cy, size * 0.12)
        ..stroke();
    case '\u25c9':
      canvas
        ..circle(cx, cy, size * 0.12)
        ..stroke()
        ..circle(cx, cy, size * 0.05)
        ..fill();
    case '\u25ce':
      canvas
        ..circle(cx, cy, size * 0.12)
        ..stroke()
        ..circle(cx, cy, size * 0.06)
        ..stroke();
    case '\u25b2':
      triangle(size * 0.26);
      canvas.fill();
    case '\u25b3':
      triangle(size * 0.26);
      canvas.stroke();
    case '\ufe45':
      sesame();
      canvas
        ..fill()
        ..restore();
    case '\ufe46':
      sesame();
      canvas
        ..stroke()
        ..restore();
    default:
      return false;
  }
  return true;
}

/// Whether [c] takes no emphasis mark: a space or punctuation, as CSS's
/// `text-emphasis` skips them.
bool _unemphasized(int c) => switch (generalCategory(c)) {
  GeneralCategory.spaceSeparator ||
  GeneralCategory.lineSeparator ||
  GeneralCategory.paragraphSeparator ||
  GeneralCategory.control ||
  GeneralCategory.connectorPunctuation ||
  GeneralCategory.dashPunctuation ||
  GeneralCategory.openPunctuation ||
  GeneralCategory.closePunctuation ||
  GeneralCategory.initialPunctuation ||
  GeneralCategory.finalPunctuation ||
  GeneralCategory.otherPunctuation => true,
  _ => false,
};

void _decorate(Canvas canvas, InlineDecoration decoration, Rect rect) {
  void shape(Rect r) => decoration.radius > 0
      ? canvas.roundedRect(r, decoration.radius)
      : canvas.rect(r);
  canvas.save();
  if (decoration.background case final background?) {
    canvas.setFillColor(background);
    shape(rect);
    canvas.fill();
  }
  final w = decoration.borderWidth;
  if (decoration.borderColor case final color? when w > 0) {
    canvas
      ..setStrokeColor(color)
      ..setLineWidth(w);
    shape(
      Rect(
        rect.left + w / 2,
        rect.bottom + w / 2,
        rect.width - w,
        rect.height - w,
      ),
    );
    canvas.stroke();
  }
  canvas.restore();
}

/// The lines of [paragraph] from its [items] broken at [breaks], in
/// [widths].
List<Line> buildLines(
  Paragraph paragraph,
  List<LineItem> items,
  List<int> breaks,
  LineWidths widths, {
  double expansion = 0,
  LineWidths? offsets,
}) {
  // (Justified to the widest line: each line's natural width first.)
  var widest = double.infinity;
  if (paragraph.justifyToWidest && paragraph.align == TextAlign.justify) {
    final natural = buildLines(
      paragraph.copyWith(align: TextAlign.left, justifyToWidest: false),
      items,
      breaks,
      widths,
      expansion: expansion,
    );
    widest = 0;
    for (final (number, line) in natural.indexed) {
      widest = math.max(
        widest,
        line.width + (number == 0 ? paragraph.firstLineIndent : 0),
      );
    }
  }
  final lines = <Line>[];
  var start = 0;
  for (final (number, end) in breaks.indexed) {
    final s = _skipDiscardable(items, start);
    final content = s < end ? items.sublist(s, end) : <LineItem>[];
    // (A line ending in a fill, before a run set flush right that goes on
    // the next line, isn't stretched: the fill takes its room.)
    var filled = false;
    while (content.isNotEmpty && content.last is GlueItem) {
      filled |= (content.removeLast() as GlueItem).stretch.isInfinite;
    }
    final breakItem = items[end];
    // (A hyphen added where a word is hyphenated; a break after the
    // text's own hyphen, flagged too, adds none.)
    final hyphen =
        breakItem is PenaltyItem && breakItem.flagged && breakItem.width > 0
        ? breakItem.run
        : null;
    final last =
        number == breaks.length - 1 ||
        (breakItem is PenaltyItem && breakItem.isForced);
    final indent =
        (number == 0 ? paragraph.firstLineIndent : 0.0) +
        (number < paragraph.hangLines ? paragraph.hangIndent : 0.0);
    final emptyRun = breakItem is PenaltyItem ? breakItem.run : null;
    // The hyphen repeated from the line before (see PenaltyItem.carry).
    final leading = switch (start > 0 ? items[start - 1] : null) {
      PenaltyItem(:final carry, :final run?) when carry > 0 => run,
      _ => null,
    };
    lines.add(
      _line(
        paragraph,
        content,
        hyphen,
        leading,
        math.min(widths(number), widest) - indent,
        // (A right-to-left paragraph's indents at its right.)
        (paragraph.rightToLeft ? 0 : indent) + (offsets?.call(number) ?? 0),
        // (The last line, and those before a hard break, justified too
        // where alignLast says so, as CSS's `text-align-last: justify`.)
        justify:
            paragraph.align == TextAlign.justify &&
            !(filled && !(breakItem is PenaltyItem && breakItem.isForced)) &&
            (!last || paragraph.alignLast == TextAlign.justify),
        emptyRun: emptyRun,
        expansion: expansion,
        end: number == breaks.length - 1,
        first: number == 0,
      ),
    );
    start = end + 1;
  }
  return _interline(paragraph, lines);
}

/// How a justified line's runs are adjusted ([_eastAsianAdjustment]).
typedef _Adjustment = ({
  double total,
  List<({double space, Map<int, double> gaps, double width})?> runs,
});

/// A place a line is adjusted at: run `run`'s spaces (a null `gap`) or
/// the place after its glyph `gap`, its text's `size`, how far it may go
/// at this stage (`limit`, points) and how many it stands for (`count`:
/// a run's spaces together).
typedef _Place = ({int run, int? gap, double size, double limit, int count});

/// The line of [shaped] runs adjusted by [difference] (points: more for
/// a line to stretch, less to shrink) in JLREQ 3.8's order, or null where
/// it has nothing of Japanese or Chinese to adjust.
///
/// Stretching (3.8.4, JIS X 4051's order): the spaces between words to
/// half an em; the quarter em between Han or kana and Latin to half an
/// em; between the other characters by a quarter em; then all of them
/// alike. Shrinking (3.8.3): the spaces between words to a quarter em;
/// the blank half of a mark mid-line (after a closing bracket or a comma,
/// before an opening bracket; each side of a middle dot) to nothing; the
/// quarter em between Han or kana and Latin to an eighth. Within each,
/// every place by as much, in proportion to its text's size.
_Adjustment? _eastAsianAdjustment(
  List<(InlineContent, String, List<ShapedGlyph>, double)> shaped,
  List<bool> directions,
  double difference,
) {
  final places = <EastAsianPlaces?>[];
  final spaceCounts = <int>[];
  var any = false;
  for (final (i, (content, text, glyphs, _)) in shaped.indexed) {
    if (content is! TextRun || content.slotWidth != null || directions[i]) {
      places.add(null);
      spaceCounts.add(0);
      continue;
    }
    // (Tibetan is justified between its characters alike.)
    if (hasTibetan(glyphs)) return null;
    final found = eastAsianPlaces(glyphs, content.style);
    places.add(found);
    spaceCounts.add(' '.allMatches(text).length);
    if (!found.isEmpty) any = true;
  }
  if (!any) return null;
  TextStyle styleOf(int i) => (shaped[i].$1 as TextRun).style;
  double spaceOf(int i) => styleOf(i).measure(' ') + styleOf(i).wordSpacing;
  // The stages, each a list of places with their limits.
  final stages = <List<_Place>>[];
  if (difference >= 0) {
    stages
      ..add([
        for (final (i, _) in places.indexed)
          if (places[i] != null && spaceCounts[i] > 0)
            (
              run: i,
              gap: null,
              size: styleOf(i).size,
              limit: math.max(0, styleOf(i).size / 2 - spaceOf(i)),
              count: spaceCounts[i],
            ),
      ])
      ..add([
        for (final (i, p) in places.indexed)
          if (p != null)
            for (final gap in p.mixed)
              (
                run: i,
                gap: gap,
                size: styleOf(i).size,
                limit: styleOf(i).size / 4,
                count: 1,
              ),
      ])
      ..add([
        for (final (i, p) in places.indexed)
          if (p != null)
            for (final gap in p.ideographic)
              (
                run: i,
                gap: gap,
                size: styleOf(i).size,
                limit: styleOf(i).size / 4,
                count: 1,
              ),
      ])
      // (Then all of them alike, without limit.)
      ..add([
        for (final stage in [...stages])
          for (final place in stage)
            (
              run: place.run,
              gap: place.gap,
              size: place.size,
              limit: double.infinity,
              count: place.count,
            ),
      ]);
  } else {
    stages
      ..add([
        for (final (i, _) in places.indexed)
          if (places[i] != null && spaceCounts[i] > 0)
            (
              run: i,
              gap: null,
              size: styleOf(i).size,
              limit: math.max(0, spaceOf(i) - styleOf(i).size / 4),
              count: spaceCounts[i],
            ),
      ])
      ..add([
        for (final (i, p) in places.indexed)
          if (p != null)
            for (final MapEntry(key: gap, value: em) in p.punctuation.entries)
              (
                run: i,
                gap: gap,
                size: styleOf(i).size,
                limit: styleOf(i).size * em,
                count: 1,
              ),
      ])
      ..add([
        for (final (i, p) in places.indexed)
          if (p != null)
            for (final gap in p.mixed)
              (
                run: i,
                gap: gap,
                size: styleOf(i).size,
                limit: styleOf(i).size / 8,
                count: 1,
              ),
      ]);
  }
  final sign = difference >= 0 ? 1.0 : -1.0;
  var left = difference.abs();
  final spaceAmounts = List<double>.filled(shaped.length, 0);
  final gapAmounts = [for (final _ in shaped) <int, double>{}];
  for (final stage in stages) {
    if (left <= 1e-9) break;
    if (stage.isEmpty) continue;
    // Water filled: as much at each place, per point of its size, up to
    // its limit.
    final order = [...stage]
      ..sort((a, b) => (a.limit / a.size).compareTo(b.limit / b.size));
    var weight = stage.fold<double>(0, (sum, p) => sum + p.size * p.count);
    var level = 0.0;
    for (final (k, place) in order.indexed) {
      final cap = place.limit / place.size;
      final need = (cap - level) * weight;
      if (need >= left) {
        level += left / weight;
        left = 0;
        break;
      }
      left -= need;
      level = cap;
      weight -= place.size * place.count;
      if (k == order.length - 1) break;
    }
    for (final place in stage) {
      final amount =
          sign * math.min(level, place.limit / place.size) * place.size;
      if (place.gap case final gap?) {
        gapAmounts[place.run][gap] = (gapAmounts[place.run][gap] ?? 0) + amount;
      } else {
        spaceAmounts[place.run] += amount;
      }
    }
  }
  final runs = <({double space, Map<int, double> gaps, double width})?>[];
  var total = 0.0;
  for (final (i, p) in places.indexed) {
    if (p == null) {
      runs.add(null);
      continue;
    }
    final width =
        spaceAmounts[i] * spaceCounts[i] +
        gapAmounts[i].values.fold<double>(0, (sum, a) => sum + a);
    total += width;
    runs.add((space: spaceAmounts[i], gaps: gapAmounts[i], width: width));
  }
  return (total: total, runs: runs);
}

/// [lines] apart by their paragraph's [FontLineHeight.skip], where it has
/// one.
List<Line> _interline(Paragraph paragraph, List<Line> lines) =>
    switch (paragraph.lineHeight) {
      final FontLineHeight height => height.apart(lines),
      _ => lines,
    };

Line _line(
  Paragraph paragraph,
  List<LineItem> items,
  TextRun? hyphen,
  TextRun? leadingHyphen,
  double room,
  double indent, {
  required bool justify,
  required TextRun? emptyRun,
  double expansion = 0,
  bool end = false,
  bool first = false,
}) {
  var available = room;
  // Runs of items of the same content, in order.
  final pieces = <(InlineContent, StringBuffer)>[
    if (leadingHyphen != null) (leadingHyphen, StringBuffer('-')),
  ];
  for (final item in items) {
    final (InlineContent? content, String text) = switch (item) {
      BoxItem(:final content, :final text) => (content, text),
      GlueItem(:final run?, :final text) => (run, text),
      _ => (null, ''),
    };
    if (content == null) continue;
    if (content is TextRun &&
        pieces.isNotEmpty &&
        identical(pieces.last.$1, content)) {
      pieces.last.$2.write(text);
    } else {
      pieces.add((content, StringBuffer(text)));
    }
  }
  if (hyphen != null) {
    // (The soft hyphen, where the font has it: the line's hyphen divides
    // a word, which text taken from the page joins up again, as ISO 32000
    // has a soft hyphen at a line's end read.)
    final mark = hyphen.style.font.covers(0xad) ? '\u00ad' : '-';
    if (pieces.isNotEmpty && identical(pieces.last.$1, hyphen)) {
      pieces.last.$2.write(mark);
    } else {
      pieces.add((hyphen, StringBuffer(mark)));
    }
  }

  // Natural widths, and the spaces justification stretches.
  var natural = 0.0;
  var spaces = 0;
  final shaped = <(InlineContent, String, List<ShapedGlyph>, double)>[];
  final ranks = <int>[];
  final directions = <bool>[];
  for (final (content, text, rightToLeft, rank) in _visual(paragraph, pieces)) {
    ranks.add(rank);
    directions.add(rightToLeft);
    switch (content) {
      case TextRun(:final style, :final slotWidth):
        var glyphs = style.shape(text, rightToLeft: rightToLeft);
        // (The line's soft hyphen hidden by full shaping, a default
        // ignorable: the font's hyphen drawn for it, still read as it.)
        if (identical(content, hyphen) &&
            text.endsWith('\u00ad') &&
            glyphs.isNotEmpty) {
          final at = rightToLeft ? 0 : glyphs.length - 1;
          final dash = style.shape('-');
          if (glyphs[at] case ShapedGlyph(text: '\u00ad', advance: 0)
              when dash.length == 1 && dash.single.id != 0) {
            glyphs = [...glyphs]
              ..[at] = ShapedGlyph(
                dash.single.id,
                '\u00ad',
                dash.single.advance,
              );
          }
        }
        // (East Asian spacing: punctuation squeezed, a quarter em between
        // Han or kana and Latin.)
        if (paragraph.eastAsian && !rightToLeft && slotWidth == null) {
          glyphs = eastAsianSpacing(glyphs, style);
        }
        final width = slotWidth ?? style.widthOf(glyphs);
        // (And between this run and the one before, where they meet.)
        if (paragraph.eastAsian &&
            !rightToLeft &&
            slotWidth == null &&
            text.isNotEmpty &&
            shaped.isNotEmpty &&
            !directions[shaped.length - 1]) {
          if (shaped.last
              case (
                final TextRun before,
                final beforeText,
                final beforeGlyphs,
                final beforeWidth,
              )
              when beforeText.isNotEmpty &&
                  before.slotWidth == null &&
                  cjkWesternBoundary(beforeText.runes.last, text.runes.first) &&
                  !before.style.combinesAt(beforeText, beforeText.length - 1) &&
                  !content.style.combinesAt(text, 0)) {
            final quarter = before.style.size / 4;
            shaped.last = (
              before,
              beforeText,
              beforeGlyphs,
              beforeWidth + quarter,
            );
            natural += quarter;
          }
        }
        shaped.add((content, text, glyphs, width));
        natural += width;
        // (A slot's spaces don't stretch.)
        if (slotWidth == null) spaces += ' '.allMatches(text).length;
      case InlineImage(:final width):
        shaped.add((content, text, const [], width));
        natural += width;
      case PageReference():
        throw StateError('page references are resolved before breaking');
    }
  }
  // (East Asian: a full-width mark ending the line set half wide where
  // the text's region does so.)
  if (paragraph.eastAsian && shaped.isNotEmpty && !directions.last) {
    final (content, text, glyphs, width) = shaped.last;
    if (content is TextRun && content.slotWidth == null) {
      final trimmed = eastAsianLineEnd(glyphs, content.style);
      if (!identical(trimmed, glyphs)) {
        final narrower =
            width -
            content.style.widthOf(glyphs) +
            content.style.widthOf(trimmed);
        natural += narrower - width;
        shaped.last = (content, text, trimmed, narrower);
      }
    }
  }
  // (And an opening bracket starting it set solid, as the paragraph has
  // it: JLREQ 3.1.5.)
  final solidStart = switch (paragraph.lineStartBrackets) {
    LineStartBrackets.solid => true,
    LineStartBrackets.fullWidth => false,
    LineStartBrackets.novel => !first,
  };
  if (paragraph.eastAsian &&
      solidStart &&
      shaped.isNotEmpty &&
      !directions.first) {
    final (content, text, glyphs, width) = shaped.first;
    if (content is TextRun && content.slotWidth == null) {
      final trimmed = eastAsianLineStart(glyphs, content.style);
      if (!identical(trimmed, glyphs)) {
        final narrower =
            width -
            content.style.widthOf(glyphs) +
            content.style.widthOf(trimmed);
        natural += narrower - width;
        shaped.first = (content, text, trimmed, narrower);
      }
    }
  }
  // (An image reaching over what is beside it, ruby over kana, starting
  // or ending the line: as far in as it reaches, JLREQ 3.3.9.)
  if (shaped.firstOrNull case (final InlineImage image, _, _, _)
      when image.startOverhang > 0 && !directions.first) {
    natural += image.startOverhang;
  }
  if (shaped.lastOrNull case (final InlineImage image, _, _, _)
      when image.endOverhang > 0 && !directions.last) {
    natural += image.endOverhang;
  }
  // (The tracking after the line's last character is no part of it: the
  // line ends where its last letter does, aligned so.)
  if (shaped.lastOrNull case (final TextRun run, _, final glyphs, _)
      when glyphs.isNotEmpty) {
    natural -= run.style.characterSpacing;
  }
  // (A justified paragraph's last line, or one before a hard break, the
  // breaker set wider than its measure, its spaces shrunk: justified too,
  // shrunk to fit, never stretched.)
  final overfull =
      !justify &&
      paragraph.align == TextAlign.justify &&
      spaces > 0 &&
      natural > room + 1e-4;
  // (A line with a run set flush right isn't stretched: its fills take
  // the room, the run and what follows it set against the line's end.)
  final flushAt = paragraph.rightToLeft
      ? -1
      : shaped.indexWhere(
          (s) => s.$1 is TextRun && (s.$1 as TextRun).flushRight,
        );
  final stretch = justify && flushAt < 0;
  final justified = stretch || overfull;
  // Protrusion: the line's last character hangs past its end and, when it
  // is justified, its first before its start, the line that much wider
  // (as the breaker counted them).
  var leftHang = 0.0;
  if ((paragraph.protrusion > 0 || paragraph.hangingPunctuation) &&
      !paragraph.rightToLeft) {
    var hang = 0.0;
    for (final (content, text, glyphs, _) in shaped.reversed) {
      final trimmed = text.trimRight();
      if (trimmed.isEmpty) continue;
      if (content is TextRun) {
        // (A full stop or comma hung whole, as wide as it is set: half
        // wide where the line's end set it solid.)
        hang =
            paragraph.hangingPunctuation &&
                hangsAtLineEnd(trimmed.runes.last) &&
                glyphs.isNotEmpty
            ? content.style.widthOf([glyphs.last])
            : _protrusionOf(paragraph, content, trimmed, right: true);
      }
      break;
    }
    if (justified && spaces > 0 && paragraph.protrusion > 0) {
      for (final (content, text, _, _) in shaped) {
        final trimmed = text.replaceAll('\u200b', '').trimLeft();
        if (trimmed.isEmpty) continue;
        if (content is TextRun) {
          leftHang = _protrusionOf(paragraph, content, trimmed, right: false);
        }
        break;
      }
    }
    available += hang + leftHang;
  }
  // Tibetan ending with a tsheg: filled out with tshegs, standing for no
  // text (r12a's Tibetan notes).
  if (stretch && paragraph.tshegPadding && shaped.isNotEmpty) {
    final (content, text, glyphs, width) = shaped.last;
    if (content is TextRun &&
        content.slotWidth == null &&
        text.endsWith('\u0f0b')) {
      final tsheg = content.style.shape('\u0f0b');
      final w = tsheg.length == 1 ? content.style.widthOf(tsheg) : 0.0;
      final count = w > 0 ? ((available - natural) / w).floor() : 0;
      if (count > 0) {
        shaped.last = (
          content,
          text,
          [
            ...glyphs,
            for (var k = 0; k < count; k++)
              ShapedGlyph(tsheg.single.id, '', tsheg.single.advance),
          ],
          width + count * w,
        );
        natural += count * w;
      }
    }
  }
  // Justification alternates (Nastaliq's wider letterforms): taken
  // before the spaces widen, from the line's end.
  if (stretch && paragraph.justificationAlternates && available > natural) {
    for (var i = shaped.length - 1; i >= 0; i--) {
      if (available - natural <= 0) break;
      final (content, text, glyphs, width) = shaped[i];
      if (content is! TextRun || content.slotWidth != null) continue;
      final (glyphs: wider, :gained) = justificationAlternates(
        text,
        glyphs,
        content.style,
        available - natural,
        rightToLeft: directions[i],
      );
      if (gained > 0) {
        shaped[i] = (content, text, wider, width + gained);
        natural += gained;
      }
    }
  }
  // Kashida: Arabic words lengthened before the spaces are widened.
  if (stretch && paragraph.kashida > 0 && available > natural) {
    final runs = <KashidaRun?>[
      for (final (i, (content, _, glyphs, _)) in shaped.indexed)
        if (content case TextRun(:final style, slotWidth: null))
          (glyphs: glyphs, style: style, rightToLeft: directions[i])
        else
          null,
    ];
    final (lengthened, taken) = kashida(
      runs,
      available - natural,
      paragraph.kashida,
    );
    if (taken > 0) {
      for (final (i, glyphs) in lengthened.indexed) {
        if (glyphs == null) continue;
        final (content, text, _, width) = shaped[i];
        final style = (content as TextRun).style;
        shaped[i] = (
          content,
          text,
          glyphs,
          width + style.widthOf(glyphs) - style.widthOf(shaped[i].$3),
        );
      }
      natural += taken;
    }
  }
  // Justified with expansion: the letters take their share of the
  // difference (as the breaker counted it: their width times [expansion]
  // against the spaces' stretch or shrink), within the expansion, the
  // spaces the rest.
  var scale = 1.0;
  if (justified && expansion > 0) {
    final difference = available - natural;
    var letters = 0.0;
    var glue = 0.0;
    for (final item in items) {
      switch (item) {
        case BoxItem(:final width):
          letters += width;
        case GlueItem(:final stretch, :final shrink) when stretch.isFinite:
          glue += difference >= 0 ? stretch : shrink;
        case _:
      }
    }
    if (letters > 0) {
      final share = spaces == 0
          ? difference
          : difference * letters * expansion / (glue + letters * expansion);
      scale = 1 + (share / letters).clamp(-expansion, expansion);
    }
  }
  // (Text written without spaces stretches between its characters too,
  // as much as at each space.)
  final gaps = [
    for (final (content, _, glyphs, _) in shaped)
      if (stretch &&
          !overfull &&
          paragraph.eastAsian &&
          content is TextRun &&
          content.slotWidth == null)
        interCharacterGaps(glyphs)
      else
        const <int>[],
  ];
  final gapCount = gaps.fold(0, (sum, g) => sum + g.length);
  // (A justified line of Japanese or Chinese: adjusted in JLREQ 3.8's
  // order, each kind of place to its limit before the next.)
  final adjusted = stretch && !overfull && scale == 1 && paragraph.eastAsian
      ? _eastAsianAdjustment(shaped, directions, available - natural)
      : null;
  final extra = adjusted != null || !justified || spaces + gapCount == 0
      ? 0.0
      : overfull
      ? math.min<double>(0, (available / scale - natural) / spaces)
      : (available / scale - natural) / (spaces + gapCount);
  final width = adjusted != null
      ? natural + adjusted.total
      : (natural + extra * (spaces + gapCount)) * scale;
  // (A justified paragraph's line that isn't stretched: by alignLast.)
  final align = paragraph.align == TextAlign.justify && !stretch && !overfull
      ? paragraph.alignLast
      : paragraph.align;
  var x =
      indent -
      leftHang +
      switch (align) {
        TextAlign.left || TextAlign.justify => 0.0,
        TextAlign.center => (available - width) / 2,
        TextAlign.right => available - width,
      };

  // Vertical metrics.
  var ascent = 0.0;
  var descent = 0.0;
  var gap = 0.0;
  var size = 0.0;
  var xHeight = 0.0;
  void text(TextStyle style) {
    final scale = style.size / 1000;
    ascent = math.max(
      ascent,
      style.font.ascender * scale +
          (paragraph.riseInLineHeight ? math.max(0, style.rise) : 0),
    );
    descent = math.min(
      descent,
      style.font.descender * scale +
          (paragraph.riseInLineHeight ? math.min(0, style.rise) : 0),
    );
    gap = math.max(gap, style.font.lineGap * scale);
    size = math.max(size, style.size);
    xHeight = math.max(xHeight, style.font.xHeight * scale);
  }

  for (final (content, _, _, _) in shaped) {
    if (content is TextRun) {
      text(content.style);
      // (Emphasis marks over or under the text: the line that much taller
      // or deeper.)
      if (content.emphasisMark != null) {
        final style = content.style;
        final mark = emphasisExtent(style);
        if (content.emphasisUnder) {
          descent = math.min(
            descent,
            style.font.descender * style.size / 1000 - mark,
          );
        } else {
          ascent = math.max(
            ascent,
            style.font.ascender * style.size / 1000 + mark,
          );
        }
      }
    }
  }
  if (shaped.isEmpty && emptyRun != null) text(emptyRun.style);
  if (paragraph.strut case final strut?) text(strut);
  final textAscent = ascent;
  // (Lines from their cap heights: the tallest capitals of the line's
  // text, a line of spaces alone as tall as theirs.)
  var cap = 0.0;
  var blankCap = 0.0;
  double capOf(TextStyle style) =>
      style.font.capHeight * style.size / 1000 +
      (paragraph.riseInLineHeight ? math.max(0, style.rise) : 0);
  for (final (content, string, _, _) in shaped) {
    if (content is TextRun) {
      if (string.trim().isEmpty) {
        blankCap = math.max(blankCap, capOf(content.style));
      } else {
        cap = math.max(cap, capOf(content.style));
      }
    }
  }
  if (shaped.isEmpty && emptyRun != null) blankCap = capOf(emptyRun.style);
  final fragments = <LineFragment>[];
  for (final (i, (content, string, glyphs, natural)) in shaped.indexed) {
    if (i == flushAt) {
      var tail = 0.0;
      for (final (_, _, _, w) in shaped.skip(i)) {
        tail += w;
      }
      // (Two spaces from the text before it at the least, as broken.)
      final gap = i > 0 && content is TextRun
          ? content.style.measure('  ')
          : 0.0;
      x = math.max(x + gap, indent - leftHang + available - tail);
    }
    switch (content) {
      case TextRun(:final style)
          when adjusted != null && adjusted.runs[i] != null:
        // (Adjusted as JLREQ has it: its spaces and its places each by
        // their own amounts.)
        final run = adjusted.runs[i]!;
        fragments.add(
          TextFragment(
            x,
            natural + run.width,
            content,
            string,
            adjustGaps(glyphs, run.gaps, style),
            run.space == 0
                ? style
                : style.copyWith(wordSpacing: style.wordSpacing + run.space),
            rightToLeft: directions[i],
          ),
        );
        x += natural + run.width;
      case TextRun(:final style, :final slotWidth):
        final count = slotWidth != null ? 0 : ' '.allMatches(string).length;
        final adjustedStyle = extra == 0 && scale == 1
            ? style
            : style.copyWith(
                wordSpacing: style.wordSpacing + extra,
                horizontalScaling: style.horizontalScaling * scale,
              );
        final w = (natural + extra * (count + gaps[i].length)) * scale;
        fragments.add(
          TextFragment(
            x,
            w,
            content,
            string,
            widenGaps(glyphs, gaps[i], extra * 1000 / style.size),
            adjustedStyle,
            rightToLeft: directions[i],
          ),
        );
        x += w;
      case InlineImage(:final height, :final alignment):
        final bottom =
            content.bottom ??
            switch (alignment) {
              InlineAlignment.baseline => 0.0,
              InlineAlignment.middle => xHeight / 2 - height / 2,
              InlineAlignment.top => textAscent - height,
            };
        final top = content.lineAscent ?? bottom + height;
        ascent = math.max(ascent, top);
        descent = math.min(descent, -(content.lineDescent ?? -bottom));
        cap = math.max(cap, top);
        if (size == 0) size = height;
        // (Reaching over what is beside it, at the line's start or end: set
        // in by as much.)
        final edge = !directions[i];
        if (i == 0 && edge) x += content.startOverhang;
        fragments.add(ImageFragment(x, content.width, content, bottom));
        x += content.width;
        if (i == shaped.length - 1 && edge) x += content.endOverhang;
      case PageReference():
        throw StateError('page references are resolved before breaking');
    }
  }
  final (height, baseline) = switch (paragraph.lineHeight) {
    FontLineHeight(:final leading, :final above, :final endDepth) => (
      end && endDepth != null
          ? above + ascent + endDepth
          : ascent - descent + gap + leading,
      above + ascent,
    ),
    MultipleLineHeight(:final factor) => _centered(
      factor * size,
      ascent,
      descent,
    ),
    ExactLineHeight(:final points) => _centered(points, ascent, descent),
    // (The leading under each line but a paragraph's last.)
    CapLineHeight(:final leading) => (
      (cap > 0 ? cap : blankCap) + (end ? 0 : leading),
      cap > 0 ? cap : blankCap,
    ),
  };
  final capLines = paragraph.lineHeight is CapLineHeight;
  final reordered = [
    for (var i = 1; i < ranks.length; i++) ranks[i] < ranks[i - 1],
  ].any((b) => b);
  return Line(
    fragments,
    width: width,
    height: height,
    baseline: baseline,
    // (Lines from their cap heights: no more of them above the baseline,
    // nothing below it but the leading.)
    ascent: capLines ? baseline : ascent,
    descent: capLines ? 0 : descent,
    hyphenated: hyphen != null,
    readingOrder: reordered
        ? ([for (var i = 0; i < ranks.length; i++) i]
            ..sort((a, b) => ranks[a] - ranks[b]))
        : null,
  );
}

/// A line's [pieces] (each its content and text, in logical order) in
/// visual order, left to right, each with whether it is a right-to-left
/// run: split where their embedding levels change and reordered (UAX #9,
/// rules L1 and L2), the line resolved in [paragraph]'s base direction,
/// and its rank in reading order. A left-to-right line without
/// right-to-left text keeps its pieces.
List<(InlineContent, String, bool, int)> _visual(
  Paragraph paragraph,
  List<(InlineContent, StringBuffer)> pieces,
) {
  // (An image a neutral character: U+FFFC, the object replacement.)
  final texts = [
    for (final (content, buffer) in pieces)
      if (content is TextRun) buffer.toString() else '\ufffc',
  ];
  if (!paragraph.rightToLeft && !texts.any(hasRightToLeft)) {
    return [
      for (final (i, (content, _)) in pieces.indexed)
        (content, content is TextRun ? texts[i] : '', false, i),
    ];
  }
  final line = texts.join();
  final bidi = BidiText(
    line,
    direction: paragraph.rightToLeft ? TextDirection.rtl : TextDirection.ltr,
  );
  final levels = bidi.lineLevels(0, line.length);
  final base = paragraph.rightToLeft ? 1 : 0;
  // The runs of one piece and one level each, in logical order: their
  // start and end in the line, and the piece of each. A piece with no
  // text (an anchor alone, a footnote reference's) is a run of its own at
  // the level of what follows it, so that it goes where that goes.
  final spans = <(int, int, int)>[];
  final levelOf = <int>[];
  var at = 0;
  for (final (i, text) in texts.indexed) {
    if (text.isEmpty) {
      spans.add((at, at, i));
      levelOf.add(
        at < line.length
            ? levels[at]
            : at > 0
            ? levels[at - 1]
            : base,
      );
      continue;
    }
    var from = at;
    for (var k = at + 1; k <= at + text.length; k++) {
      if (k == at + text.length || levels[k] != levels[from]) {
        spans.add((from, k, i));
        levelOf.add(levels[from]);
        from = k;
      }
    }
    at += text.length;
  }
  // (Reordered by index, each run's start not unique once empty.)
  return [
    for (final (index, _, level) in reorderRuns([
      for (var r = 0; r < spans.length; r++) (r, r + 1, levelOf[r]),
    ]))
      if (spans[index] case (final from, final to, final piece))
        (pieces[piece].$1, line.substring(from, to), level.isOdd, index),
  ];
}

/// A line [height] tall with its content centered (the extra split above
/// and below, as CSS does).
(double, double) _centered(double height, double ascent, double descent) =>
    (height, (height - (ascent - descent)) / 2 + ascent);
