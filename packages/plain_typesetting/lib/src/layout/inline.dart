/// Inline content of paragraphs: styled text runs and inline images.
library;

import 'package:meta/meta.dart';
import 'package:plain_typesetting/src/canvas.dart';
import 'package:plain_typesetting/src/color.dart';
import 'package:plain_typesetting/src/font.dart';
import 'package:plain_typesetting/src/graphic.dart';
import 'package:plain_typesetting/src/layout/paragraph.dart' show TextAlign;
import 'package:plain_typesetting/src/link.dart';

/// A piece of a paragraph's content.
@immutable
sealed class InlineContent {
  const new _();
}

/// Text in one style.
final class TextRun extends InlineContent {
  /// [text] set in [style], painted in [color] (black by default), with
  /// the decorations asked for, linking to [link].
  const new(
    this.text,
    this.style, {
    this.color,
    this.underline = false,
    this.strikethrough = false,
    this.link,
    this.anchor,
    this.anchorOnBaseline = false,
    this.decoration,
    this.fallbackFonts = const [],
    this.artifact = false,
    this.slotWidth,
    this.slotAlign = TextAlign.left,
    this.emphasisMark,
    this.emphasisUnder = false,
  }) : super._();

  /// Where given, a mark set over each of the text's characters (but its
  /// spaces and punctuation) at half its size: emphasis marks, CSS's
  /// `text-emphasis` (JLREQ's bouten, a sesame dot over each character;
  /// CLREQ's dot under each), [emphasisUnder] under them.
  final String? emphasisMark;

  /// Whether [emphasisMark] goes under the characters.
  final bool emphasisUnder;

  /// Where given, the width the text takes on its line, whatever its own
  /// (a heading's number hung in a column, a key's label with room on
  /// either side): set whole, never broken, aligned in it by [slotAlign].
  final double? slotWidth;

  /// How the text sits in its [slotWidth].
  final TextAlign slotAlign;

  /// The text.
  final String text;

  /// Whether the text is decoration, not content (a listing's callout
  /// numbers): drawn as marked content that reads as nothing, so that
  /// text taken from the page, copied or read aloud, leaves it out.
  final bool artifact;

  /// The font, size and text state.
  final TextStyle style;

  /// The fill color, or null for the canvas's current color.
  final Color? color;

  /// Whether the text is underlined.
  final bool underline;

  /// Whether the text is struck through.
  final bool strikethrough;

  /// Where the text links to.
  final LinkTarget? link;

  /// A name for the position of the text: layout reports where it ends
  /// up (for destinations, a table of contents, an index), at the text's
  /// top.
  final String? anchor;

  /// Whether [anchor] is reported at the text's baseline instead (where
  /// something set beside the line, a label hung left of it, aligns).
  final bool anchorOnBaseline;

  /// A background and border drawn behind the text.
  final InlineDecoration? decoration;

  /// The fonts that set the characters [style]'s font lacks: each
  /// character goes to the first that has it.
  final List<Font> fallbackFonts;

  /// A run of [text] with this run's formatting.
  TextRun withText(String text) => TextRun(
    text,
    style,
    color: color,
    underline: underline,
    strikethrough: strikethrough,
    link: link,
    anchor: anchor,
    anchorOnBaseline: anchorOnBaseline,
    decoration: decoration,
    fallbackFonts: fallbackFonts,
    artifact: artifact,
    slotWidth: slotWidth,
    slotAlign: slotAlign,
    emphasisMark: emphasisMark,
    emphasisUnder: emphasisUnder,
  );

  /// This run in [style].
  TextRun withStyle(TextStyle style) => TextRun(
    text,
    style,
    color: color,
    underline: underline,
    strikethrough: strikethrough,
    link: link,
    anchor: anchor,
    anchorOnBaseline: anchorOnBaseline,
    decoration: decoration,
    artifact: artifact,
    slotWidth: slotWidth,
    slotAlign: slotAlign,
    emphasisMark: emphasisMark,
    emphasisUnder: emphasisUnder,
  );
}

/// A box drawn behind a run of text: a background and a border around
/// the text's ascent and descent, wider by [padding] on each side.
@immutable
final class InlineDecoration {
  /// A decoration.
  const new({
    this.background,
    this.borderColor,
    this.borderWidth = 0,
    this.radius = 0,
    this.padding = 0,
    this.outset = 0,
  });

  /// The fill.
  final Color? background;

  /// The border's color.
  final Color? borderColor;

  /// The border's width.
  final double borderWidth;

  /// The corner radius.
  final double radius;

  /// The extra width on the left and right, in points.
  final double padding;

  /// The extra height above the ascent and below the descent, in points.
  final double outset;
}

/// How an inline image sits on the line.
enum InlineAlignment {
  /// Its bottom on the baseline.
  baseline,

  /// Its middle on the middle of the line's text (half the x-height above
  /// the baseline of the run before it).
  middle,

  /// Its top at the top of the line's text.
  top,
}

/// An image in the text, of a given size.
final class InlineImage extends InlineContent {
  /// [image] (raster or SVG) drawn [width] by [height] points, aligned
  /// by [alignment].
  ///
  /// [bottom], where given, places its bottom that far above the baseline
  /// (below it when negative) instead; [lineAscent] and [lineDescent], how
  /// far above and below the baseline it reaches for its line's height,
  /// where they aren't its own (a formula as deep as its depth, an icon
  /// that takes no more room than the text around it). [startOverhang] and
  /// [endOverhang], how far it reaches over what is beside it (ruby's
  /// reading over the kana around its base, JLREQ 3.3.8): starting or
  /// ending a line, it is set that much further in, as it may reach no
  /// further than the line (3.3.9).
  const new(
    this.image,
    this.width,
    this.height, {
    this.alignment = InlineAlignment.baseline,
    this.link,
    this.bottom,
    this.lineAscent,
    this.lineDescent,
    this.startOverhang = 0,
    this.endOverhang = 0,
  }) : super._();

  /// How far it reaches before its start over what is beside it.
  final double startOverhang;

  /// How far it reaches after its end over what is beside it.
  final double endOverhang;

  /// Where its bottom is above the baseline, or null for [alignment]'s.
  final double? bottom;

  /// How far above the baseline it reaches for its line's height, or null
  /// for its top.
  final double? lineAscent;

  /// How far below the baseline it reaches for its line's height (a
  /// positive depth), or null for its bottom.
  final double? lineDescent;

  /// The image.
  final Graphic image;

  /// Its width, in points.
  final double width;

  /// Its height, in points.
  final double height;

  /// Its vertical alignment.
  final InlineAlignment alignment;

  /// Where the image links to.
  final LinkTarget? link;
}

/// The page number (or label) of an anchor, filled in when the layout
/// knows it: a table of contents, "see page 12". Until then it takes the
/// room of [placeholder].
final class PageReference extends InlineContent {
  /// The page of [anchor], set in [style] like a [TextRun].
  const new(
    this.anchor,
    this.style, {
    this.placeholder = '000',
    this.color,
    this.link,
  }) : super._();

  /// The anchor whose page is shown.
  final String anchor;

  /// The font, size and text state.
  final TextStyle style;

  /// The text measured before the page is known.
  final String placeholder;

  /// The fill color.
  final Color? color;

  /// Where the reference links to.
  final LinkTarget? link;

  /// The reference as a run of [text].
  TextRun resolve(String text) =>
      TextRun(text, style, color: color, link: link);
}
