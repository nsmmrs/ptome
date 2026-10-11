/// Looks (ADR-0023): one design file in three levels (tokens, styles of
/// elements and roles, templates) that every output compiles into its own
/// terms. Everything a look sets is optional: a look says only what it
/// means to, over the looks it extends and each output's base.
library;

import 'package:meta/meta.dart';
import 'package:yaml/yaml.dart';

/// Where an output shows a value: print (the PDF, and CSS print media),
/// the screen (HTML) or an e-book reader (EPUB).
enum Medium {
  /// The PDF, and CSS print media.
  print,

  /// HTML pages and the website.
  screen,

  /// An EPUB's reading system.
  ebook;

  /// The medium named [name], or null.
  static Medium? named(String name) =>
      values.where((m) => m.name == name).firstOrNull;
}

/// A value that may differ by [Medium]: [all] for every medium without
/// its own.
@immutable
final class ByMedium<T extends Object> {
  /// [all], and the values of [each] medium that differs.
  const new({this.all, this.each = const {}});

  /// The value of every medium without its own.
  final T? all;

  /// The media with values of their own.
  final Map<Medium, T> each;

  /// The value for [medium], or null.
  T? of(Medium medium) => each[medium] ?? all;
}

/// A unit a [Length] is written in.
enum LengthUnit {
  /// Points (1/72 in).
  pt('pt'),

  /// CSS pixels (0.75 pt).
  px('px'),

  /// Inches.
  inch('in'),

  /// Millimeters.
  mm('mm'),

  /// The font size.
  em('em'),

  /// The base font size (the root element's in CSS, the theme's base in
  /// the PDF).
  rem('rem'),

  /// The width of a `0` in the text face.
  ch('ch'),

  /// Multiples of the line spacing.
  lines('lines');

  new(this.symbol);

  /// How the unit is written.
  final String symbol;
}

/// A length: [value] in [unit].
@immutable
final class Length {
  /// [value] [unit]s.
  const new(this.value, this.unit);

  /// The number, as written (an integer stays one).
  final num value;

  /// The unit.
  final LengthUnit unit;

  /// The length in points, for an absolute unit (`1px` is `0.75pt`, CSS's
  /// reference pixel); null for one relative to the text.
  double? get points => switch (unit) {
    LengthUnit.pt => value.toDouble(),
    LengthUnit.px => value * 0.75,
    LengthUnit.inch => value * 72.0,
    LengthUnit.mm => value * 72 / 25.4,
    LengthUnit.em ||
    LengthUnit.rem ||
    LengthUnit.ch ||
    LengthUnit.lines => null,
  };

  /// As written: `0.75in`, `10.5pt`.
  @override
  String toString() => '$value${unit.symbol}';

  @override
  bool operator ==(Object other) =>
      other is Length && other.value == value && other.unit == unit;

  @override
  int get hashCode => Object.hash(value, unit);
}

/// A color, as six hexadecimal digits (`1F1F1F`).
@immutable
final class LookColor {
  /// The color [hex] (six digits, upper case).
  const new(this.hex);

  /// Six hexadecimal digits, upper case.
  final String hex;

  @override
  bool operator ==(Object other) => other is LookColor && other.hex == hex;

  @override
  int get hashCode => hex.hashCode;

  @override
  String toString() => '#$hex';
}

/// A weight of a face: 100 to 900 (`normal` is 400, `bold` 700), as
/// CSS has them; the PDF sets 600 and up in the bold face.
typedef FontWeight = int;

/// The shape of a face.
enum FontShape {
  /// Upright.
  normal,

  /// Italic.
  italic,
}

/// A variant of a face.
enum FontVariant {
  /// The face as it is.
  normal('normal'),

  /// Small capitals from the font (`smcp`), never shrunk capitals.
  smallCaps('small-caps');

  new(this.wire);

  /// As a look writes it.
  final String wire;
}

/// How text lines up.
enum Alignment {
  /// Flush with the start of the line (left, in a left-to-right
  /// script), ragged at its end.
  start,

  /// Centered.
  center,

  /// Flush with the end of the line.
  end,

  /// Flush with both ends.
  justify,
}

/// What sets paragraphs apart.
enum ParagraphSignal {
  /// Space between paragraphs.
  space,

  /// A first-line indent.
  indent,
}

/// A face, by role (`text`, `display`, `code`, `utility`).
@immutable
final class Face {
  /// A face of [family].
  const new({this.family, this.weight, this.shape, this.size});

  /// The family's name.
  final ByMedium<String>? family;

  /// Its weight where a style doesn't say.
  final ByMedium<FontWeight>? weight;

  /// Its shape where a style doesn't say.
  final ByMedium<FontShape>? shape;

  /// Its size, as a ratio of the text around it (a code face a little
  /// smaller than the text).
  final ByMedium<double>? size;

  /// The face as [medium] shows it.
  MediumFace at(Medium medium) => MediumFace(
    family: family?.of(medium),
    weight: weight?.of(medium),
    shape: shape?.of(medium),
    size: size?.of(medium),
  );
}

/// A [Face] as one medium shows it.
@immutable
final class MediumFace {
  /// A face of [family].
  const new({this.family, this.weight, this.shape, this.size});

  /// The family's name.
  final String? family;

  /// Its weight.
  final FontWeight? weight;

  /// Its shape.
  final FontShape? shape;

  /// Its size, as a ratio of the text around it.
  final double? size;
}

/// The paragraph signal: space between paragraphs, or a first-line
/// indent.
@immutable
final class Paragraph {
  /// Paragraphs set apart by [signal].
  const new({this.signal, this.space, this.indent});

  /// What sets paragraphs apart.
  final ByMedium<ParagraphSignal>? signal;

  /// The space between paragraphs.
  final ByMedium<Length>? space;

  /// The first line's indent.
  final ByMedium<Length>? indent;
}

/// A page's size.
sealed class PageSize {
  const new();
}

/// A size by name: `A4`, `Letter`.
final class NamedPageSize extends PageSize {
  /// The size [name].
  const new(this.name);

  /// The name.
  final String name;

  @override
  String toString() => name;
}

/// A trim: [width] by [height].
final class PageDimensions extends PageSize {
  /// A page [width] by [height].
  const new(this.width, this.height);

  /// The width.
  final Length width;

  /// The height.
  final Length height;

  @override
  String toString() => '$width × $height';
}

/// The page, in print.
@immutable
final class Page {
  /// A page of [size] inside [margin].
  const new({this.size, this.margin, this.inner, this.outer});

  /// The paper's size.
  final PageSize? size;

  /// One, two or four margins (top, sides; or top, right, bottom, left).
  final List<Length>? margin;

  /// The margins beside the binding and away from it, in a two-sided
  /// book.
  final Length? inner;

  /// The margin away from the binding.
  final Length? outer;
}

/// Level 1: the design's values, in no output's terms.
@immutable
final class Tokens {
  /// Tokens with the values given.
  const new({
    this.fonts = const {},
    this.textSize,
    this.headingSizes,
    this.small,
    this.leading,
    this.measure,
    this.paragraph,
    this.align,
    this.hyphenate,
    this.colors = const {},
    this.rules = const {},
    this.page,
  });

  /// Faces by role.
  final Map<String, Face> fonts;

  /// The text's size.
  final ByMedium<Length>? textSize;

  /// The headings' sizes, from level 1 (`h1`) down.
  final ByMedium<List<Length>>? headingSizes;

  /// Small text (captions, notes) as a ratio of the text.
  final ByMedium<double>? small;

  /// The line spacing, as a ratio of the size.
  final ByMedium<double>? leading;

  /// The line length.
  final ByMedium<Length>? measure;

  /// What sets paragraphs apart.
  final Paragraph? paragraph;

  /// How the text lines up.
  final ByMedium<Alignment>? align;

  /// Whether words are hyphenated at line ends.
  final ByMedium<bool>? hyphenate;

  /// Colors by role (`ink`, `link`, `tint`, ...).
  final Map<String, ByMedium<LookColor>> colors;

  /// Rule widths by name (`hairline`, `heavy`).
  final Map<String, ByMedium<Length>> rules;

  /// The page, in print.
  final Page? page;
}

/// What a style is for: an element of AsciiDoc's or a role.
@immutable
sealed class StyleTarget {
  /// Nothing.
  const new();

  /// The target written [key]: `.name` for a role, else an element.
  static StyleTarget? parse(String key) => key.startsWith('.')
      ? (key.length > 1 ? RoleTarget(key.substring(1)) : null)
      : switch (LookElement.named(key)) {
          final element? => ElementTarget(element),
          null => null,
        };
}

/// An element of AsciiDoc's.
final class ElementTarget extends StyleTarget {
  /// The style of [element].
  const new(this.element);

  /// The element.
  final LookElement element;

  @override
  bool operator ==(Object other) =>
      other is ElementTarget && other.element == element;

  @override
  int get hashCode => element.hashCode;

  @override
  String toString() => element.wire;
}

/// Content with a role (`[.dek]`).
final class RoleTarget extends StyleTarget {
  /// The style of content with [role].
  const new(this.role);

  /// The role (`dek` for `[.dek]`).
  final String role;

  @override
  bool operator ==(Object other) => other is RoleTarget && other.role == role;

  @override
  int get hashCode => role.hashCode;

  @override
  String toString() => '.$role';
}

/// The elements a look styles.
enum LookElement {
  /// Every section title.
  heading('heading'),

  /// A section title of level 1 (a part, a chapter in a book).
  h1('h1'),

  /// A section title of level 2.
  h2('h2'),

  /// A section title of level 3.
  h3('h3'),

  /// A section title of level 4.
  h4('h4'),

  /// A section title of level 5.
  h5('h5'),

  /// A section title of level 6.
  h6('h6'),

  /// The document's title (on its title page).
  title('title'),

  /// The document's subtitle.
  subtitle('subtitle'),

  /// A paragraph of prose.
  paragraph('paragraph'),

  /// A link.
  link('link'),

  /// Code in a line of text.
  code('code'),

  /// A listing or literal block.
  codeBlock('code-block'),

  /// A block's title (a figure's, a table's).
  caption('caption'),

  /// A quote block.
  quote('quote'),

  /// A note, tip, warning, caution or important block.
  admonition('admonition'),

  /// An admonition's label (NOTE).
  admonitionLabel('admonition-label'),

  /// A sidebar.
  sidebar('sidebar'),

  /// A sidebar's title.
  sidebarTitle('sidebar-title'),

  /// A table.
  table('table'),

  /// A table's head rows.
  tableHead('table-head'),

  /// A footnote.
  footnote('footnote');

  new(this.wire);

  /// As a look writes it.
  final String wire;

  /// The element written [name], or null.
  static LookElement? named(String name) =>
      values.where((e) => e.wire == name).firstOrNull;
}

/// A color a style gives: a token's, its own, or none.
@immutable
sealed class ColorValue {
  /// Nothing.
  const new();
}

/// The color token [name].
final class ColorToken extends ColorValue {
  /// The token [name].
  const new(this.name);

  /// The token's name.
  final String name;
}

/// A color of the style's own.
final class ColorLiteral extends ColorValue {
  /// [color].
  const new(this.color);

  /// The color.
  final LookColor color;
}

/// No color: transparent, nothing painted.
final class NoColor extends ColorValue {
  /// Nothing.
  const new();
}

/// A size a style gives: a length, a ratio of the text around it, or a
/// size token (`small`).
@immutable
sealed class SizeValue {
  /// Nothing.
  const new();
}

/// A size as a length.
final class SizeLength extends SizeValue {
  /// [length].
  const new(this.length);

  /// The length.
  final Length length;
}

/// A size as a ratio of the text around it.
final class SizeRatio extends SizeValue {
  /// [ratio] times the text around it.
  const new(this.ratio);

  /// The ratio.
  final double ratio;
}

/// A size token's (`small`).
final class SizeToken extends SizeValue {
  /// The token [name].
  const new(this.name);

  /// The token's name.
  final String name;
}

/// A rule's width: a length or a rule token (`hairline`).
@immutable
sealed class WidthValue {
  /// Nothing.
  const new();
}

/// A rule's width as a length.
final class WidthLength extends WidthValue {
  /// [length].
  const new(this.length);

  /// The length.
  final Length length;
}

/// A rule token's width (`hairline`).
final class WidthToken extends WidthValue {
  /// The token [name].
  const new(this.name);

  /// The token's name.
  final String name;
}

/// A border or rule: none, or a width and a color.
@immutable
sealed class RuleValue {
  /// Nothing.
  const new();
}

/// No rule: none drawn.
final class NoRule extends RuleValue {
  /// Nothing.
  const new();
}

/// A rule drawn.
final class Rule extends RuleValue {
  /// A rule [width] wide, in [color].
  const new({required this.width, this.color});

  /// Its width.
  final WidthValue width;

  /// The text's color.
  final ColorValue? color;
}

/// Level 2: an element's or a role's style, in token terms. Every
/// property is optional.
@immutable
final class Style {
  /// A style with the properties given.
  const new({
    this.font,
    this.size,
    this.weight,
    this.shape,
    this.variant,
    this.color,
    this.background,
    this.leading,
    this.spaceBefore,
    this.spaceAfter,
    this.padding,
    this.radius,
    this.border,
    this.rule,
    this.keepWithNext,
    this.frame,
    this.frameSides,
    this.rows,
    this.columns,
    this.headRule,
    this.stripes,
  });

  /// The face, by its role in the tokens.
  final ByMedium<String>? font;

  /// The size.
  final ByMedium<SizeValue>? size;

  /// The weight (the face's where null).
  final ByMedium<FontWeight>? weight;

  /// The shape (the face's where null).
  final ByMedium<FontShape>? shape;

  /// The variant.
  final ByMedium<FontVariant>? variant;

  /// The text's color.
  final ByMedium<ColorValue>? color;

  /// The background's color.
  final ByMedium<ColorValue>? background;

  /// The line spacing, as a ratio of the size.
  final ByMedium<num>? leading;

  /// The space above.
  final ByMedium<Length>? spaceBefore;

  /// The space below.
  final ByMedium<Length>? spaceAfter;

  /// The space inside, around the content.
  final ByMedium<Length>? padding;

  /// The corners' radius.
  final ByMedium<Length>? radius;

  /// The border.
  final ByMedium<RuleValue>? border;

  /// The rule beside the content (an admonition's).
  final ByMedium<RuleValue>? rule;

  /// Whether it stays with what follows it.
  final ByMedium<bool>? keepWithNext;

  /// A table's rules: its top and bottom, its sides, between its rows,
  /// between its columns, under its head; and its rows' alternate
  /// background.
  final ByMedium<RuleValue>? frame;

  /// A table's left and right sides.
  final ByMedium<RuleValue>? frameSides;

  /// The rules between a table's rows.
  final ByMedium<RuleValue>? rows;

  /// The rules between a table's columns.
  final ByMedium<RuleValue>? columns;

  /// The rule under a table's head.
  final ByMedium<RuleValue>? headRule;

  /// The background of every other body row.
  final ByMedium<ColorValue>? stripes;

  /// The style as [medium] shows it.
  MediumStyle at(Medium medium) => MediumStyle(
    font: font?.of(medium),
    size: size?.of(medium),
    weight: weight?.of(medium),
    shape: shape?.of(medium),
    variant: variant?.of(medium),
    color: color?.of(medium),
    background: background?.of(medium),
    leading: leading?.of(medium),
    spaceBefore: spaceBefore?.of(medium),
    spaceAfter: spaceAfter?.of(medium),
    padding: padding?.of(medium),
    radius: radius?.of(medium),
    border: border?.of(medium),
    rule: rule?.of(medium),
    keepWithNext: keepWithNext?.of(medium),
    frame: frame?.of(medium),
    frameSides: frameSides?.of(medium),
    rows: rows?.of(medium),
    columns: columns?.of(medium),
    headRule: headRule?.of(medium),
    stripes: stripes?.of(medium),
  );
}

/// A [Style] as one medium shows it.
@immutable
final class MediumStyle {
  /// The style's values in a medium.
  const new({
    this.font,
    this.size,
    this.weight,
    this.shape,
    this.variant,
    this.color,
    this.background,
    this.leading,
    this.spaceBefore,
    this.spaceAfter,
    this.padding,
    this.radius,
    this.border,
    this.rule,
    this.keepWithNext,
    this.frame,
    this.frameSides,
    this.rows,
    this.columns,
    this.headRule,
    this.stripes,
  });

  /// The [Style]'s `font` in the medium.
  final String? font;

  /// The [Style]'s `size` in the medium.
  final SizeValue? size;

  /// The [Style]'s `weight` in the medium.
  final FontWeight? weight;

  /// The [Style]'s `shape` in the medium.
  final FontShape? shape;

  /// The [Style]'s `variant` in the medium.
  final FontVariant? variant;

  /// The [Style]'s `color` in the medium.
  final ColorValue? color;

  /// The [Style]'s `background` in the medium.
  final ColorValue? background;

  /// The [Style]'s `leading` in the medium.
  final num? leading;

  /// The [Style]'s `spaceBefore` in the medium.
  final Length? spaceBefore;

  /// The [Style]'s `spaceAfter` in the medium.
  final Length? spaceAfter;

  /// The [Style]'s `padding` in the medium.
  final Length? padding;

  /// The [Style]'s `radius` in the medium.
  final Length? radius;

  /// The [Style]'s `border` in the medium.
  final RuleValue? border;

  /// The [Style]'s `rule` in the medium.
  final RuleValue? rule;

  /// The [Style]'s `keepWithNext` in the medium.
  final bool? keepWithNext;

  /// The [Style]'s `frame` in the medium.
  final RuleValue? frame;

  /// The [Style]'s `frameSides` in the medium.
  final RuleValue? frameSides;

  /// The [Style]'s `rows` in the medium.
  final RuleValue? rows;

  /// The [Style]'s `columns` in the medium.
  final RuleValue? columns;

  /// The [Style]'s `headRule` in the medium.
  final RuleValue? headRule;

  /// The [Style]'s `stripes` in the medium.
  final ColorValue? stripes;
}

/// Level 3: generated text and structure (ADR-0010).
@immutable
final class Templates {
  /// [named] templates, the [nodeTemplates] folder and the [titlePage].
  const new({this.named = const {}, this.nodeTemplates, this.titlePage});

  /// Mustache templates by name.
  final Map<String, String> named;

  /// The folder of `-T` node templates.
  final String? nodeTemplates;

  /// The title page's slots; null for each output's own.
  final TitlePage? titlePage;
}

/// A title page as DocBook XSL's `titlepage.templates.xml` writes one:
/// the parts of the document on the [recto], in order, and on the
/// [verso] (the back of the title page: a book's copyright page).
@immutable
final class TitlePage {
  /// A title page of [recto] and [verso] slots.
  const new({this.recto = const [], this.verso = const []});

  /// The front's slots, in order.
  final List<Slot> recto;

  /// The back's slots, in order (none: no verso).
  final List<Slot> verso;
}

/// A part of the document's header a title page shows.
enum TitlePart {
  /// The title (before the `title-separator`, when the look shows the
  /// subtitle).
  title,

  /// The subtitle (after the `title-separator`).
  subtitle,

  /// The authors.
  authors,

  /// The revision: its number, date and remark.
  revision,

  /// The logo (`title-logo-image`).
  logo,
}

/// What a slot shows.
sealed class SlotContent {
  const new();
}

/// A [part] of the document's header.
final class PartContent extends SlotContent {
  /// A slot of [part].
  const new(this.part);

  /// The part.
  final TitlePart part;

  @override
  String toString() => part.name;
}

/// The value of the document attribute [name] (`copyright`,
/// `publisher`), where the document sets it.
final class AttributeContent extends SlotContent {
  /// A slot of the attribute [name].
  const new(this.name);

  /// The attribute.
  final String name;

  @override
  String toString() => 'attribute $name';
}

/// One slot of a title page: what it shows, its role (a style the look's
/// `styles` give it), the space around it, text before it, and the
/// separator between its items (the authors').
@immutable
final class Slot {
  /// A slot of [content].
  const new(
    this.content, {
    this.role,
    this.spaceBefore,
    this.spaceAfter,
    this.before,
    this.separator,
  });

  /// What it shows.
  final SlotContent content;

  /// The role it is styled as (`.dek`'s `dek`).
  final String? role;

  /// The space above it.
  final ByMedium<Length>? spaceBefore;

  /// The space below it.
  final ByMedium<Length>? spaceAfter;

  /// Text before it (`by `).
  final String? before;

  /// The text between its items (authors).
  final String? separator;
}

/// A look: its levels, and what it says in an output's own terms where
/// tokens can't.
@immutable
final class Look {
  /// The look [name] with its levels.
  const new({
    required this.name,
    this.tokens = const Tokens(),
    this.styles = const {},
    this.templates = const Templates(),
    this.pdf = const [],
    this.css = const [],
    this.epubCss = const [],
    this.webfonts = const [],
    this.directory,
  });

  /// The look's name (its file's, without `-look.yml`).
  final String name;

  /// The folder of the look's file, which the paths it gives (fonts,
  /// images) are relative to; null for a built-in look.
  final String? directory;

  /// Level 1: the design's values.
  final Tokens tokens;

  /// Styles by target, in the order written.
  final Map<StyleTarget, Style> styles;

  /// Level 3: generated text and structure.
  final Templates templates;

  /// PDF theme entries, in the theme's own terms: each look's of the
  /// chain, the one it extends first (applied in order, as theme files
  /// are).
  final List<YamlMap> pdf;

  /// CSS rules after the device stylesheet (HTML, website), each look's.
  final List<String> css;

  /// CSS rules after the device stylesheet in an EPUB, each look's.
  final List<String> epubCss;

  /// The Google Fonts families HTML pages load for the look's faces
  /// (`Crimson Pro:400,400italic,700`), the latest look's that names
  /// any.
  final List<String> webfonts;
}
