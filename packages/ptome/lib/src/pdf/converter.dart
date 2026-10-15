/// The PDF backend (`-b pdf`): converts documents as asciidoctor-pdf
/// 2.3.27 does, with its themes, into plain_pdf boxes laid out on pages. Text
/// is set by a Prawn-compatible text box ([TextBox]); blocks, page
/// breaks and running content are plain_pdf's box tree.
///
/// The converter's state and its entry points are here; what it does for
/// each concern (the document and its pages, sections, paragraphs, framed
/// blocks, images, tables, lists, code, running content, inline
/// elements...) is an extension of it in `converter/`, and the contents
/// it lays out are in `converter/contents.dart`.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:plain_math/plain_math.dart';
import 'package:plain_pdf/plain_pdf.dart';
import 'package:plain_svg/plain_svg.dart';
import 'package:plain_typesetting/plain_typesetting.dart';
import 'package:plain_unicode/plain_unicode.dart' show CounterStyle, isEmoji;
import 'package:ptome/src/abstract_block.dart';
import 'package:ptome/src/abstract_node.dart';
import 'package:ptome/src/attribute_list.dart';
import 'package:ptome/src/block.dart';
import 'package:ptome/src/compat.dart';
import 'package:ptome/src/converter.dart';
import 'package:ptome/src/cursor.dart';
import 'package:ptome/src/dates.dart';
import 'package:ptome/src/direction.dart';
import 'package:ptome/src/document.dart';
import 'package:ptome/src/helpers.dart';
import 'package:ptome/src/image_shape.dart';
import 'package:ptome/src/index_catalog.dart' show indexHasCategoryHeadings;
import 'package:ptome/src/index_order.dart';
import 'package:ptome/src/inline.dart';
import 'package:ptome/src/io.dart' as io;
import 'package:ptome/src/jump.dart';
import 'package:ptome/src/list.dart';
import 'package:ptome/src/locale_labels.dart';
import 'package:ptome/src/look/document_look.dart';
import 'package:ptome/src/look/model.dart' show TitlePart;
import 'package:ptome/src/numbering.dart';
import 'package:ptome/src/output_template.dart';
import 'package:ptome/src/page_map.dart';
import 'package:ptome/src/parallel.dart';
import 'package:ptome/src/pdf/fonts.dart';
import 'package:ptome/src/pdf/highlight_style.dart';
import 'package:ptome/src/pdf/hyphenate.dart';
import 'package:ptome/src/pdf/icons.dart';
import 'package:ptome/src/pdf/index.dart';
import 'package:ptome/src/pdf/look_theme.dart';
import 'package:ptome/src/pdf/markup.dart';
import 'package:ptome/src/pdf/math.dart';
import 'package:ptome/src/pdf/ruby.dart';
import 'package:ptome/src/pdf/svg_size.dart';
import 'package:ptome/src/pdf/text_box.dart';
import 'package:ptome/src/pdf/theme.dart';
import 'package:ptome/src/pdf/warichu.dart';
import 'package:ptome/src/quotation.dart';
import 'package:ptome/src/ruby_text.dart';
import 'package:ptome/src/section.dart';
import 'package:ptome/src/table.dart';
import 'package:ptome/src/timings.dart';
import 'package:ptome/src/units/citation.dart' show Passage, passageText;
import 'package:ptome/src/units/engine.dart' show Unit;

part 'converter/admonitions.dart';
part 'converter/captions.dart';
part 'converter/code.dart';
part 'converter/contents.dart';
part 'converter/document.dart';
part 'converter/framed.dart';
part 'converter/images.dart';
part 'converter/inline.dart';
part 'converter/lists.dart';
part 'converter/outline.dart';
part 'converter/paragraphs.dart';
part 'converter/preamble.dart';
part 'converter/running_content.dart';
part 'converter/sections.dart';
part 'converter/tables.dart';
part 'converter/text.dart';
part 'converter/theme_keys.dart';
part 'converter/theme_values.dart';
part 'converter/traversal.dart';

/// The NUL character the gem puts in empty anchors (zero width).
const String _dummyText = '\u0000';

/// Page sizes by name, in points (Prawn's table).
const Map<String, (double, double)> _pageSizes = {
  '4A0': (4767.87, 6740.79),
  '2A0': (3370.39, 4767.87),
  'A0': (2383.94, 3370.39),
  'A1': (1683.78, 2383.94),
  'A2': (1190.55, 1683.78),
  'A3': (841.89, 1190.55),
  'A4': (595.28, 841.89),
  'A5': (419.53, 595.28),
  'A6': (297.64, 419.53),
  'A7': (209.76, 297.64),
  'A8': (147.4, 209.76),
  'A9': (104.88, 147.4),
  'A10': (73.7, 104.88),
  'B0': (2834.65, 4008.19),
  'B1': (2004.09, 2834.65),
  'B2': (1417.32, 2004.09),
  'B3': (1000.63, 1417.32),
  'B4': (708.66, 1000.63),
  'B5': (498.9, 708.66),
  'B6': (354.33, 498.9),
  'B7': (249.45, 354.33),
  'B8': (175.75, 249.45),
  'B9': (124.72, 175.75),
  'B10': (87.87, 124.72),
  'C0': (2599.37, 3676.54),
  'C1': (1836.85, 2599.37),
  'C2': (1298.27, 1836.85),
  'C3': (918.43, 1298.27),
  'C4': (649.13, 918.43),
  'C5': (459.21, 649.13),
  'C6': (323.15, 459.21),
  'C7': (229.61, 323.15),
  'C8': (161.57, 229.61),
  'C9': (113.39, 161.57),
  'C10': (79.37, 113.39),
  'RA0': (2437.8, 3458.27),
  'RA1': (1729.13, 2437.8),
  'RA2': (1218.9, 1729.13),
  'RA3': (864.57, 1218.9),
  'RA4': (609.45, 864.57),
  'SRA0': (2551.18, 3628.35),
  'SRA1': (1814.17, 2551.18),
  'SRA2': (1275.59, 1814.17),
  'SRA3': (907.09, 1275.59),
  'SRA4': (637.8, 907.09),
  'EXECUTIVE': (521.86, 756.0),
  'FOLIO': (612.0, 936.0),
  'LEGAL': (612.0, 1008.0),
  'LETTER': (612.0, 792.0),
  'TABLOID': (792.0, 1224.0),
};

/// The font settings in effect (the gem's `theme_font` state).
/// A slot of the title page (a theme's `title_page_recto` or
/// `title_page_verso`, ADR-0023): a part of the header or an attribute's
/// value, its role, the space around it, text before it and the
/// separator between its items.
final class _TitleSlot {
  const new({
    this.part,
    this.attribute,
    this.role,
    this.marginTop,
    this.marginBottom,
    this.before,
    this.separator,
  });

  /// A slot of [part], as the theme's or the gem's.
  const new part(TitlePart? part) : this(part: part);

  final TitlePart? part;
  final String? attribute;
  final String? role;
  final double? marginTop;
  final double? marginBottom;
  final String? before;
  final String? separator;
}

final class _FontState {
  const new({
    required this.family,
    required this.style,
    required this.size,
    required this.color,
    required this.lineHeight,
    this.kerning = true,
    this.transform,
    this.leadingKey,
    this.letterSpacing = 0,
  });

  final String family;
  final String style;
  final double size;
  final ThemeColor? color;
  final double lineHeight;
  final bool kerning;
  final String? transform;

  /// The theme key of the text's cap-height leading (`<category>_leading`),
  /// when its category or one it inherits from sets one (else
  /// `base_leading`).
  final String? leadingKey;

  /// The tracking, in ems (`<category>_letter_spacing`, modern engine).
  final double letterSpacing;

  _FontState copyWith({
    String? family,
    String? style,
    double? size,
    ThemeColor? color,
    double? lineHeight,
    bool? kerning,
    String? transform,
  }) => _FontState(
    family: family ?? this.family,
    style: style ?? this.style,
    size: size ?? this.size,
    color: color ?? this.color,
    lineHeight: lineHeight ?? this.lineHeight,
    kerning: kerning ?? this.kerning,
    transform: transform ?? this.transform,
    leadingKey: leadingKey,
    letterSpacing: letterSpacing,
  );
}

/// The PDF converter.
final class PdfConverter extends BuiltInConverter
    implements FinishingConverter {
  /// The converter for [backend].
  new(super.backend, [super.opts]) {
    backendTraits = BackendTraits(
      basebackend: 'html',
      filetype: 'pdf',
      outfilesuffix: '.pdf',
      htmlsyntax: 'html',
    );
  }

  @override
  String get converterName => 'PdfConverter';

  Uint8List? _bytes;

  late Theme _theme;
  late FontCatalog _fonts;
  late TextContext _text;
  late MarkupTransform _markup;
  _FontState _font = const _FontState(
    family: 'Helvetica',
    style: 'normal',
    size: 12,
    color: null,
    lineHeight: 1,
  );
  late double _rootFontSize;
  late String _baseTextAlign;
  late List<LayoutBox> _out;
  late Document _document;
  final List<(Section, String)> _sections = [];

  /// The anchors made up for sections without an id, in the order they
  /// were asked for (the same on every run, unlike a hash code).
  final Map<Section, String> _madeUpAnchors = Map.identity();

  /// The anchor made up for [section], which has no id.
  String _madeUpAnchor(Section section) =>
      _madeUpAnchors[section] ??= '__section-${_madeUpAnchors.length + 1}';

  /// Saves the converted document (once its work on other cores is
  /// done, or doing it here).
  Uint8List Function()? _save;

  /// The work on other cores the save waits for.
  final List<Future<void>> _awaiting = [];

  /// The workers the converted document's work runs on, when it is
  /// awaited (the `jobs` attribute: the physical cores by default, `1`
  /// for none).
  Parallel? _parallel;

  /// Called (by tools measuring the work, `tool/spike_chunks.dart`) with
  /// the layout and the boxes the walk made, instead of laying them out.
  @internal
  static void Function(FlowLayout layout, List<LayoutBox> content)? onWalked;

  /// The PDF the last converted document made.
  Uint8List? get bytes => _bytes ??= _save?.call();

  @override
  Uint8List? get output => bytes;

  @override
  Future<void> finish() async {
    await Future.wait(_awaiting);
    _awaiting.clear();
    bytes;
  }

  @override
  void write(String path) {
    final bytes = this.bytes;
    if (bytes == null) throw StateError('no document converted');
    io.writeBytes(path, bytes);
  }

  @override
  String? convertBlock(AbstractBlock node, ConvertOptions? opts) {
    // (A block's own `lang` for its text, and its own direction, Ptome's:
    // not under asciidoctor-compat.)
    final language = _language;
    final direction = _blockRightToLeft;
    if (node is! Document) {
      if (node.attributes['lang'] case final String lang
          when !asciidoctorCompat(_document, CompatFormat.pdf)) {
        _language = lang;
      }
      if (blockDirection(node, CompatFormat.pdf) case final dir?) {
        _blockRightToLeft = dir == 'rtl';
      }
    }
    try {
      // (On a vertical page, a table or a listing set upright, across the
      // page, as JLREQ 4.4.2 has them.)
      // (A block's own writing mode, Ptome's `vertical-rl` and
      // `vertical-lr` roles: in vertical lines on a horizontal page.)
      if (_blockWritingMode(node) case final mode?
          when !_verticalWriting && _blockMode == null) {
        final out = _out;
        _out = [];
        _blockMode = mode;
        try {
          return _convertBlock(node, opts);
        } finally {
          final boxes = _out;
          _out = out;
          _blockMode = null;
          if (boxes.isNotEmpty) {
            _out.add(
              VerticalBox(
                boxes.length == 1 ? boxes.single : BlockBox(boxes),
                writingMode: mode,
              ),
            );
          }
        }
      }
      // (A block with a role of `line_numbers_skip_roles` is left out of
      // the line numbering: a play's stage directions.)
      if (_skipsNumbering(node)) {
        String? result;
        _unnumbering = true;
        try {
          final boxes = _collect(() => result = convertBlock(node, opts));
          _out.add(BlockBox(boxes, style: const BoxStyle(unnumbered: true)));
        } finally {
          _unnumbering = false;
        }
        return result;
      }
      // (Ptome's `mirror` role: the block set mirrored, left to right, as
      // Through the Looking-Glass prints Jabberwocky.)
      if (_mirrors(node)) {
        final out = _out;
        _out = [];
        _mirroring = true;
        try {
          return _convertBlock(node, opts);
        } finally {
          final boxes = _out;
          _out = out;
          _mirroring = false;
          if (boxes.isNotEmpty) {
            _out.add(
              MirroredBox(boxes.length == 1 ? boxes.single : BlockBox(boxes)),
            );
          }
        }
      }
      if (_setsUpright(node) && !_upright && _verticalWriting) {
        final out = _out;
        _out = [];
        _upright = true;
        try {
          return _convertBlock(node, opts);
        } finally {
          final boxes = _out;
          _out = out;
          _upright = false;
          if (boxes.isNotEmpty) {
            _out.add(
              UprightBox(boxes.length == 1 ? boxes.single : BlockBox(boxes)),
            );
          }
        }
      }
      return _convertBlock(node, opts);
    } finally {
      _language = language;
      _blockRightToLeft = direction;
    }
  }

  /// The writing mode of the vertical block being converted on a
  /// horizontal page (Ptome's `vertical-rl` and `vertical-lr` roles), or
  /// null.
  WritingMode? _blockMode;

  /// The vertical writing mode [node]'s role gives it (not under
  /// `asciidoctor-compat`), or null.
  WritingMode? _blockWritingMode(AbstractBlock node) {
    if (node is Document || node.role == null) return null;
    if (asciidoctorCompat(_document, CompatFormat.pdf)) return null;
    if (node.includesRole('vertical-rl')) {
      return WritingMode.verticalRightToLeft;
    }
    if (node.includesRole('vertical-lr')) {
      return WritingMode.verticalLeftToRight;
    }
    return null;
  }

  /// Whether headings are left out of the line numbering
  /// (`line_numbers_skip_headings`: a play's act and scene heads, where a
  /// bill counts its headings' lines).
  late final bool _headingsUnnumbered =
      _theme.value('line_numbers_skip_headings') == const ThemeBool(true);

  /// Whether a block left out of the line numbering is being converted.
  bool _unnumbering = false;

  /// Whether [node] is left out of the line numbering: the document's
  /// lines are numbered and it has a role of `line_numbers_skip_roles`.
  bool _skipsNumbering(AbstractBlock node) {
    if (_unnumbering || _lineNumbering == null || node is Document) {
      return false;
    }
    final roles = switch (_theme.value('line_numbers_skip_roles')) {
      ThemeList(:final values) => [
        for (final value in values)
          if (value case ThemeString(:final value)) value,
      ],
      ThemeString(:final value) => [value],
      _ => const <String>[],
    };
    return roles.any(node.includesRole);
  }

  /// How many columns the footnotes are set in (`footnotes_columns`, more
  /// than one; not under `asciidoctor-compat`), or null for the usual one.
  late final int? _footnoteColumns = switch (_n('footnotes_columns')) {
    final columns?
        when columns > 1 && !asciidoctorCompat(_document, CompatFormat.pdf) =>
      columns.toInt(),
    _ => null,
  };

  /// The name the main series of footnotes is laid out under when it is
  /// set in columns.
  static const String _footnoteColumnsStream = '_footnotes';

  /// The name the main series of footnotes is set under in a margin
  /// column (`footnotes_column`).
  static const String _footnoteSideStream = '_footnotes_side';

  /// A two- or three-em dash.
  static final RegExp _multiEmDashRx = RegExp('[\u2e3a\u2e3b]');

  /// Whether a block with the `mirror` role is being converted.
  bool _mirroring = false;

  /// Whether [node] is set mirrored: Ptome's `mirror` role (not under
  /// `asciidoctor-compat`), outside another mirrored block.
  bool _mirrors(AbstractBlock node) =>
      !_mirroring &&
      node is! Document &&
      node.includesRole('mirror') &&
      !asciidoctorCompat(_document, CompatFormat.pdf);

  /// Whether a table or a listing is being converted on a vertical page:
  /// set across the page, its text horizontal.
  bool _upright = false;

  /// Whether [node] is set upright on a vertical page: a table, a listing
  /// or a literal block, unless the theme's `table_writing_mode` (or the
  /// table's `vertical` role) sets a table in the columns' direction.
  bool _setsUpright(AbstractBlock node) => switch (node) {
    final Table table =>
      !table.includesRole('vertical') && _s('table_writing_mode') != 'vertical',
    Block(context: BlockContext.listing || BlockContext.literal) => true,
    // (Ptome's `horizontal-tb` role: any block set across.)
    _ when node is! Document && node.includesRole('horizontal-tb') => true,
    _ => false,
  };

  /// The language of the text being converted (BCP 47), choosing the
  /// fonts' language systems: the document's `lang`, a block's own
  /// (modern engine); null under `asciidoctor-compat`.
  String? _language;

  String? _convertBlock(AbstractBlock node, ConvertOptions? opts) {
    if (node is! Document && node is! Section) {
      final above = _marginAbove(node);
      if (above > 0) _out.add(SpacerBox(above));
    }
    switch (node) {
      case final Document document:
        convertDocument(document);
      case final Section section:
        convertSection(section);
      case final ListBlock list when list.context == BlockContext.ulist:
        convertUlist(list);
      case final ListBlock list when list.context == BlockContext.olist:
        convertOlist(list);
      case final ListBlock list when list.context == BlockContext.dlist:
        convertDlist(list);
      case final ListBlock list when list.context == BlockContext.colist:
        convertColist(list);
      case final Table table:
        convertTable(table);
      case final Block block:
        final context = block.context;
        if (context == BlockContext.paragraph) {
          convertParagraph(block);
        } else if (context == BlockContext.admonition) {
          convertAdmonition(block);
        } else if (context == BlockContext.listing ||
            context == BlockContext.literal) {
          convertCode(block);
        } else if (context == BlockContext.preamble) {
          convertPreamble(block);
        } else if (context == BlockContext.open) {
          convertOpen(block);
        } else if (context == BlockContext.unit) {
          convertUnit(block);
        } else if (context == BlockContext.example) {
          convertExample(block);
        } else if (context == BlockContext.sidebar) {
          convertSidebar(block);
        } else if (context == BlockContext.quote ||
            context == BlockContext.verse) {
          convertQuote(block);
        } else if (context == BlockContext.thematicBreak) {
          convertThematicBreak(block);
        } else if (context == BlockContext.pageBreak) {
          convertPageBreak(block);
        } else if (context == BlockContext.image) {
          convertImage(block);
        } else if (context == BlockContext.toc) {
          convertToc(block);
        } else if (context == BlockContext.floatingTitle) {
          convertFloatingTitle(block);
        } else if (context == BlockContext.pass) {
          convertPass(block);
        } else if (context == BlockContext.stem) {
          convertStem(block);
        } else if (context == BlockContext.audio ||
            context == BlockContext.video) {
          convertMedia(block);
        }
      // Other blocks aren't converted yet: they are left out.
      default:
        break;
    }
    return '';
  }

  // The document.

  /// The options the PDF is saved with ([nativeZlib]: the platform's
  /// zlib, as on the Dart VM).
  static PdfWriterOptions _writerOptions({
    required bool nativeZlib,
    DateTime? creationDate,
    bool dates = true,
  }) => PdfWriterOptions(
    deterministic: true,
    creationDate: creationDate,
    dates: dates,
    zlib: nativeZlib ? const _NativeZlib() : null,
  );

  /// The timings the PDF's phases are recorded in (`--progress`), if any.
  Timings? _phases;
  String? _runningPhase;

  /// [value] (`2026-10-06 04:38:31 +0000`, or `UTC` for the offset) as a
  /// date and time; the current time when it isn't one.
  static DateTime _dateTime(String? value) {
    final m = RegExp(
      r'^(\d{4})-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)(?: (UTC|[+-]\d{4}))?',
    ).firstMatch(value ?? '');
    if (m == null) return DateTime.now().toUtc();
    final local = DateTime.utc(
      int.parse(m[1]!),
      int.parse(m[2]!),
      int.parse(m[3]!),
      int.parse(m[4]!),
      int.parse(m[5]!),
      int.parse(m[6]!),
    );
    final offset = m[7];
    if (offset == null || offset == 'UTC') return local;
    final minutes =
        (int.parse(offset.substring(1, 3)) * 60 +
            int.parse(offset.substring(3))) *
        (offset.startsWith('-') ? -1 : 1);
    return local.subtract(Duration(minutes: minutes));
  }

  /// Makes the titled preamble of a book a preface section (the gem's
  /// `promote_preface_block`).
  static void _promotePreface(Document doc) {
    final blocks = doc.blocks;
    if (doc.doctype != 'book' || blocks.length < 2) return;
    final preamble = blocks[0];
    final next = blocks[1];
    final title = preamble.sourceTitle;
    if (preamble.context != BlockContext.preamble ||
        title == null ||
        title.isEmpty ||
        preamble.blocks.firstOrNull?.style == 'abstract' ||
        next is! Section) {
      return;
    }
    final preface = Section(doc, next.level)
      ..special = true
      ..sectname = 'preface'
      ..title = title;
    preface
      ..setAttr('style', 'preface')
      ..id = Section.generateId(preface.title ?? title, doc);
    final first = preamble.blocks.firstOrNull;
    if (first != null && first.hasOption('notitle')) {
      preface.setOption('notitle');
      if (first.context == BlockContext.paragraph && first.role == null) {
        first.setAttr('role', 'lead');
      }
    }
    [...preamble.blocks].forEach(preface.append);
    blocks[0] = preface;
  }

  /// [theme] with the defaults the converter assumes (the gem's
  /// `prepare_theme`).
  static Theme _prepareTheme(Theme theme) {
    void fallback(String key, ThemeValue value) {
      switch (theme[key]) {
        case null || ThemeNull() || ThemeBool(value: false):
          theme[key] = value;
        case _:
          break;
      }
    }

    if (theme['base_border_color'] case ThemeString(value: 'transparent')) {
      theme['base_border_color'] = const ThemeNull();
    }
    final borderColor = switch (theme['base_border_color']) {
      null || ThemeNull() => const ThemeString('000000'),
      final color => color,
    };
    fallback('base_font_color', const ThemeString('000000'));
    fallback('base_font_family', const ThemeString('Helvetica'));
    fallback('base_font_style', const ThemeString('normal'));
    fallback('page_numbering_start_at', const ThemeString('body'));
    fallback('running_content_start_at', const ThemeString('body'));
    fallback('heading_chapter_break_before', const ThemeString('always'));
    fallback('heading_part_break_before', const ThemeString('always'));
    for (final key in [
      'heading_margin_page_top',
      'heading_margin_top',
      'heading_margin_bottom',
      'prose_text_indent',
      'prose_text_indent_inner',
      'prose_margin_bottom',
      'block_margin_bottom',
      'list_indent',
      'list_item_spacing',
      'description_list_term_spacing',
      'description_list_description_indent',
      'image_border_width',
      'callout_list_margin_top_after_code',
      'footnotes_item_spacing',
      'toc_indent',
      'toc_hanging_indent',
    ]) {
      fallback(key, const ThemeNumber(0));
    }
    fallback('table_border_color', borderColor);
    fallback('table_border_width', const ThemeNumber(0.5));
    fallback('thematic_break_border_color', borderColor);
    fallback('code_linenum_font_color', const ThemeString('999999'));
    fallback('role_unresolved_font_color', const ThemeString('FF0000'));
    fallback('footnotes_margin_top', const ThemeString('auto'));
    fallback('index_columns', const ThemeNumber(2));
    fallback('index_column_gap', theme['base_font_size'] ?? const ThemeNull());
    fallback('kbd_separator', const ThemeString('+'));
    fallback('title_page_authors_delimiter', const ThemeString(', '));
    fallback('title_page_revision_delimiter', const ThemeString(', '));
    return theme;
  }

  /// The floated image the paragraphs after it wrap around, and the
  /// paragraph that goes in it next.
  _FloatGroup? _floatGroup;
  AbstractBlock? _floatNext;

  static const _tocStartAnchor = '__ptome-toc-start';
  static const _tocEndAnchor = '__ptome-toc-end';

  /// Whether the table of contents is at the top (after the title).
  bool _tocAtTop = false;

  /// Whether the table of contents has been added (there's only one).
  bool _tocDone = false;

  /// Whether the pages of the table of contents have no header, or no
  /// footer (a toc macro's options).
  bool _tocNoHeader = false;
  bool _tocNoFooter = false;

  /// The page (1-based) of each anchor, once laid out.
  Map<String, int> _anchorPages = const {};

  /// The pages a part or chapter title opens (none has running content
  /// in the modern engine, unless `running_content_on_openers` is true).
  Set<int> _openerPages = const {};

  /// [markup] in [style] (as inline markup).
  static String _styled(String markup, String style) => switch (style) {
    'bold' => '<strong>$markup</strong>',
    'italic' => '<em>$markup</em>',
    'bold_italic' => '<strong><em>$markup</em></strong>',
    _ => markup,
  };

  /// The document's title, or its untitled label when it has no header
  /// (the gem's `resolve_doctitle`).
  static String? _resolveDoctitle(Document doc) =>
      doc.hasHeader ? doc.doctitle() : doc.attr('untitled-label');

  /// Whether the document has a front cover, or a back cover, page.
  bool _frontCover = false;
  bool _backCover = false;

  /// The horizontal and vertical position of the background position
  /// [value] (`left top`, `center`...), or null (the gem's
  /// `resolve_background_position`).
  static (String, String)? _backgroundPosition(String value) {
    if (value.contains(' ')) {
      String? h;
      String? v;
      var center = false;
      for (final keyword in value.split(' ').take(2)) {
        switch (keyword) {
          case 'left' || 'right':
            h = keyword;
          case 'top' || 'bottom':
            v = keyword;
          case 'center':
            center = true;
        }
      }
      if (center) return (h ?? 'center', v ?? 'center');
      if (h != null && v != null) return (h, v);
      return null;
    }
    return switch (value) {
      'left' || 'right' || 'center' => (value, 'center'),
      'top' || 'bottom' => ('center', value),
      _ => null,
    };
  }

  /// The page background images, by side (`recto`, `verso`).
  late final Map<String, _PageImage?> _pageImages = () {
    final both = _resolveBackgroundImage('page-background-image')?.image;
    final images = <String, _PageImage?>{'recto': both, 'verso': both};
    for (final side in const ['recto', 'verso']) {
      if (_resolveBackgroundImage('page-background-image-$side')
          case final resolved?) {
        images[side] = resolved.image;
      }
    }
    return images;
  }();

  /// The title page's background image, if it has one of its own (the
  /// `none` symbol when it has none, not even the pages' image).
  late final ({String? symbol, _PageImage? image})? _titlePageImage =
      _resolveBackgroundImage(
        'title-page-background-image',
        symbols: const ['none'],
      );

  /// The image over every page but the front cover and the pages of PDF
  /// files (the theme's `page_foreground_image`).
  /// Whether what asciidoctor-pdf draws as stamps (the page's foreground
  /// image, the running content's background and border) is clipped to the
  /// page, as the stamps' bounding boxes clip it (`page_layer_clip`).
  late final bool _pageLayerClip =
      _choice('page_layer_clip', const ['none', 'page']) == 'page';

  late final _PageImage? _foregroundImage = _resolveBackgroundImage(
    'page-foreground-image',
  )?.image;

  /// How the body's lines are numbered (the `line-numbers` attribute),
  /// if they are.
  _LineNumbering? _lineNumbering;

  /// The lines counted so far (as the pages are drawn, in order).
  int _lineCount = 0;

  /// Where the count starts again: each first-level section's page and
  /// height (`line_numbers_restart: section`), and each unit's of a level
  /// (`line_numbers_restart_units`) with the label set beside its first
  /// line.
  List<(int, double, String?)> _lineRestarts = const [];

  /// The unit labels hung left of their lines (`units_<level>_label_hang`),
  /// by their anchors: their markup and font.
  final Map<String, (String, _FontState)> _hungLabels = {};

  /// Where each hung label goes: its page (1-based), and the baseline and
  /// left end of its line.
  List<(int, double, double, String, _FontState)> _hungAt = const [];

  /// The last line (after its last hard break) of the text the last
  /// paragraph or description set, and its font: where a shared verse
  /// line goes on from (`role_<role>_text_indent: continue`).
  (String, _FontState)? _lastTextLine;

  /// How many thematic breaks are marks (for their anchors' names).
  int _thematicBreaks = 0;

  /// The least inner margin the book's page count asks for
  /// (`page_margin_gutter: kdp`), once it is known.
  double _gutterLeast = 0;

  /// How many paragraphs the engine's paragraphs set (a debug count).
  int _engineParagraphCount = 0;

  /// Whether the PDF is to conform to PDF/UA-1 (`pdf-ua`, the modern
  /// engine): tagged, its content's logical structure recorded for
  /// assistive technology (FEAT-cs3j22).
  bool get _pdfUa =>
      _document.hasAttr('pdf-ua') &&
      !asciidoctorCompat(_document, CompatFormat.pdf);

  /// An element of the logical structure of [role] (with [alt], a
  /// figure's description) for a box, when the PDF is tagged ([_pdfUa]):
  /// in a block with its own language, that language (PDF/UA-1 7.2).
  StructureElement? _struct(String role, {String? alt}) => _pdfUa
      ? StructureElement(
          role,
          alt: alt,
          language: switch (_language) {
            final language?
                when language.toLowerCase() !=
                    _document.attr('lang')?.toLowerCase() =>
              language,
            _ => null,
          },
        )
      : null;

  /// Whether the text being converted is written right to left: the
  /// block's own direction where it has one ([blockDirection]: its `dir`,
  /// or a `lang` written the other way), else the document's
  /// ([_documentRightToLeft]); its paragraphs set from the right, their
  /// text in visual order (UAX #9), the theme's alignments mirrored.
  bool get _rightToLeft => _blockRightToLeft ?? _documentRightToLeft;

  /// The direction of the block being converted, where it has its own.
  bool? _blockRightToLeft;

  /// Whether the document is written right to left (`:dir: rtl`, as
  /// HTML's `dir`): its pages mirrored too.
  bool get _documentRightToLeft =>
      _document.attr('dir')?.toLowerCase() == 'rtl' &&
      !asciidoctorCompat(_document, CompatFormat.pdf);

  /// [insets] as a block's in this document: in a right-to-left one, its
  /// left (its start) at the right and its right at the left.
  EdgeInsets _mirrorInsets(EdgeInsets insets) => _rightToLeft
      ? EdgeInsets(
          top: insets.top,
          right: insets.left,
          bottom: insets.bottom,
          left: insets.right,
        )
      : insets;

  /// Whether plain paragraphs are set by the engine's paragraphs (the
  /// modern engine's, FEAT-n1bkgf; `base_text_engine: box` keeps them in
  /// this converter's text box).
  /// How the body's lines run (`page_writing_mode`: `horizontal-tb`,
  /// `vertical-rl` for Japanese and Chinese, `vertical-lr` for
  /// Mongolian; across under `asciidoctor-compat`).
  WritingMode get _writingMode => asciidoctorCompat(_document, CompatFormat.pdf)
      ? WritingMode.horizontal
      // (The theme's `page_writing_mode`, else the document's
      // `:writing-mode:`, as HTML and EPUB read it.)
      : switch (_choice('page_writing_mode', const [
              'horizontal-tb',
              'vertical-rl',
              'vertical-lr',
            ]) ??
            _document.attr('writing-mode')?.trim().toLowerCase()) {
          'vertical-rl' => WritingMode.verticalRightToLeft,
          'vertical-lr' => WritingMode.verticalLeftToRight,
          _ => WritingMode.horizontal,
        };

  /// Whether the body's lines run down the page.
  bool get _verticalWriting => _writingMode != WritingMode.horizontal;

  /// Whether text is set in vertical lines: on a vertical page, but not in
  /// a block set upright ([_upright]).
  bool get _verticalText =>
      (_verticalWriting && !_upright) || _blockMode != null;

  /// Whether the pages follow one another to the left, the book bound at
  /// the right: a right-to-left document's, or a vertical-rl one's.
  bool get _pagesRightToLeft =>
      _documentRightToLeft || _writingMode == WritingMode.verticalRightToLeft;

  bool get _engineParagraphs =>
      _s('base_text_engine') != 'box' &&
      !asciidoctorCompat(_document, CompatFormat.pdf);

  /// A section's first paragraph's initial waiting (the theme key
  /// category of its font and lead-in, and its depth in lines).
  (String, int)? _pendingInitial;

  /// A section heading waiting to be hung in the margin of its first
  /// paragraph (`heading_h<n>_display: margin`).
  ({String text, _FontState font, String category})? _pendingMargin;

  /// The background images of the running content, by periphery
  /// (`header`, `footer`).
  final Map<String, _PageImage?> _runningBackgrounds = {};

  /// Whether the document has a title page.
  bool _hasTitlePage = false;

  /// Whether the front cover is `~`: none, and the first page takes the
  /// margins of a recto page.
  bool _noCover = false;

  static const _beforeBodyAnchor = '__ptome-before-body';

  /// Whether a blank page was put before the body to start it on a recto
  /// page (a running content or page numbering start can then be on it).
  bool _blankBeforeBody = false;

  /// Whether the document is a book for print (`media=prepress`): its
  /// title page, table of contents, body, chapters and parts start on
  /// recto pages.
  bool _ppbook = false;

  /// What decides whether a page is a recto or a verso page for its
  /// running content and background: its physical page number or its
  /// page number; and whether the sides are inverted
  /// (`pdf-folio-placement`).
  ({bool physical, bool inverted}) _folio = (physical: false, inverted: false);

  /// The first block of [document], or of its preamble.
  static AbstractBlock _firstBlockOf(Document document) {
    final first = document.blocks.firstOrNull;
    if (first is Block && first.context == BlockContext.preamble) {
      return first.blocks.firstOrNull ?? first;
    }
    return first ?? document;
  }

  /// With `pdf-layout-report`, the blocks tagged for the report, and where
  /// each starts in the source.
  Map<String, (AbstractBlock, Cursor?)>? _reportTags;

  /// The OpenType features all text is set with in the modern engine:
  /// the theme's `base_font_variant_numeric` (`oldstyle-nums`...).
  late final Set<String> _baseFeatures = {
    ?fontFeature(_s('base_font_variant_numeric')),
  };

  static const _bodyAnchor = '__ptome-body';

  /// Marks where the body starts (after the title page and the table of
  /// contents of a book).
  static CustomBox _bodyMarker() =>
      const CustomBox(_Nothing(), style: BoxStyle(anchor: _bodyAnchor));

  /// The modern engine's keys as asciidoctor-pdf sets pages, for
  /// `asciidoctor-compat` (ADR-0015): each one the theme doesn't set.
  static const Map<String, ThemeValue> asciidoctorPdfLook = {
    'block_margin_collapse': ThemeBool(false),
    'base_line_breaking': ThemeString('segments'),
    'base_hyphens': ThemeBool(false),
    'prose_orphans': ThemeNumber(1),
    'prose_widows': ThemeNumber(1),
    'code_orphans': ThemeNumber(1),
    'code_widows': ThemeNumber(1),
    'block_split_end': ThemeString('region'),
    'code_highlight': ThemeString('none'),
    'svg_placement': ThemeString('page_origin'),
    'url_breaks': ThemeString('delimiters'),
    'base_slash_breaks': ThemeBool(false),
    'index_terms_paragraph': ThemeString('line'),
    'code_wrap_indent': ThemeNumber(0),
    'code_wrap_marker': ThemeString('none'),
    'footnotes_placement': ThemeString('end'),
    'toc_macro_in_section': ThemeBool(false),
    'running_content_on_openers': ThemeBool(true),
    'running_content_on_blank_pages': ThemeBool(true),
    'running_content_layer': ThemeString('over'),
    'page_layer_clip': ThemeString('page'),
    'base_emphasis_inversion': ThemeBool(false),
    'base_glyph_widths': ThemeString('thousandths'),
    'base_kerning_source': ThemeString('kern_table'),
    'base_text_shaping': ThemeString('right_to_left'),
    'base_font_embedding': ThemeString('simple'),
    'table_borders': ThemeString('with-cells'),
    'table_cell_margin_top': ThemeString('keep'),
    'example_collapsible': ThemeString('details'),
    'stem_math': ThemeString('source'),
  };

  static const _measurement = r'\d+(?:\.\d+)?(?:in|cm|mm|p[txc])?';

  static double _toPoints(ThemeValue value) => switch (value) {
    ThemeNumber(:final value) => value.toDouble(),
    final other => strToPoints(other.rubyString),
  };

  static String? _fontStyle(String? style) => switch (style) {
    'normal_italic' => 'italic',
    final s => s,
  };

  // Traversal.

  /// The theme category whose `_margin_top` and `_margin_bottom` keys
  /// space [node] in the modern engine (`code` for a listing, `list` for
  /// a list...).
  static String _spacingCategory(AbstractBlock node) => switch (node.context) {
    BlockContext.paragraph => 'prose',
    BlockContext.listing || BlockContext.literal => 'code',
    BlockContext.image => 'image',
    BlockContext.audio || BlockContext.video => 'media',
    BlockContext.table => 'table',
    BlockContext.quote => 'quote',
    BlockContext.verse => 'verse',
    BlockContext.sidebar => 'sidebar',
    BlockContext.example => 'example',
    BlockContext.admonition => 'admonition',
    BlockContext.ulist || BlockContext.olist => 'list',
    BlockContext.dlist => 'description_list',
    BlockContext.colist => 'callout_list',
    BlockContext.open => 'open',
    BlockContext.thematicBreak => 'thematic_break',
    BlockContext.pass => 'pass',
    BlockContext.stem => 'stem',
    _ => 'block',
  };

  // Sections.

  /// The section roles whose page templates the document uses.
  final Set<String> _pageRoles = {};

  /// The theme keys of a section role's page template.
  static const List<String> _pageRoleKeys = [
    'page_columns',
    'page_margin',
    'page_background_color',
    'page_background_image',
    'page_running_content',
  ];

  /// Whether nothing comes after [block] in the document.
  static bool _lastInDocument(AbstractBlock block) {
    AbstractNode node = block;
    for (var up = node.parent; up is AbstractBlock; up = node.parent) {
      if (!identical(up.blocks.last, node)) return false;
      node = up;
    }
    return true;
  }

  /// The theme category of the boxed section whose heading is being set
  /// (its `<category>_heading_*` keys replace the heading's), if any.
  String? _headingRole;

  /// [text] escaped for the text markup.
  static String _escapeMarkup(String text) =>
      text.replaceAll('&', '&amp;').replaceAll('<', '&lt;');

  /// Whether a part has started (an appendix ends it).
  bool _inPart = false;

  // Paragraphs.

  /// The paragraph [markup]'s initial: its first letter (or figure) and
  /// the opening punctuation before it, and the markup without them; null
  /// when it doesn't start with one.
  static (String, String)? _initialOf(String markup) {
    final initial = StringBuffer();
    final tags = StringBuffer();
    var i = 0;
    while (i < markup.length) {
      if (markup.startsWith('<', i)) {
        final end = markup.indexOf('>', i);
        if (end < 0) return null;
        tags.write(markup.substring(i, end + 1));
        i = end + 1;
        continue;
      }
      final String char;
      final int length;
      if (markup.startsWith('&', i)) {
        final end = markup.indexOf(';', i);
        if (end < 0) return null;
        final entity = markup.substring(i, end + 1);
        char = switch (entity) {
          '&amp;' => '&',
          '&lt;' => '<',
          '&gt;' => '>',
          '&quot;' => '"',
          _ when entity.startsWith('&#x') => String.fromCharCode(
            int.parse(entity.substring(3, entity.length - 1), radix: 16),
          ),
          _ when entity.startsWith('&#') => String.fromCharCode(
            int.parse(entity.substring(2, entity.length - 1)),
          ),
          _ => '',
        };
        length = entity.length;
        if (char.isEmpty) return null;
      } else {
        final rune = markup.runes.elementAt(
          markup.substring(0, i).runes.length,
        );
        char = String.fromCharCode(rune);
        length = char.length;
      }
      if (_openingPunctuation.hasMatch(char)) {
        initial.write(char);
        i += length;
        continue;
      }
      if (!RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(char)) return null;
      initial.write(char);
      return ('$initial', '$tags${markup.substring(i + length)}');
    }
    return null;
  }

  /// [markup] with the text of its first [words] words in spans of the
  /// role `lead-in` (a run of text each, so that the spans close inside
  /// the tags they meet).
  static String _leadIn(String markup, int words) {
    final out = StringBuffer();
    var count = 0;
    var inWord = false;
    var i = 0;
    while (i < markup.length && count < words) {
      if (markup.startsWith('<', i)) {
        final end = markup.indexOf('>', i);
        if (end < 0) break;
        out.write(markup.substring(i, end + 1));
        i = end + 1;
        continue;
      }
      // A run of text up to the next tag or the end of the words.
      final run = StringBuffer();
      while (i < markup.length && !markup.startsWith('<', i)) {
        final space = markup[i] == ' ';
        if (space && inWord) {
          inWord = false;
          if (++count == words) break;
        } else if (!space) {
          inWord = true;
        }
        run.write(markup[i]);
        i++;
      }
      if (run.isNotEmpty) out.write('<span class="lead-in">$run</span>');
    }
    return '$out${markup.substring(i)}';
  }

  /// The text alignment a `text-<align>` role among [roles] selects (the
  /// last one wins).
  static String? _alignOf(List<String> roles) {
    for (final role in roles.reversed) {
      if (role.startsWith('text-') &&
          const {
            'justify',
            'left',
            'center',
            'right',
          }.contains(role.substring(5))) {
        return role.substring(5);
      }
    }
    return null;
  }

  // Blocks with a background and a border.

  /// Strokes the border of [rect] in [color] (the gem's
  /// `fill_and_stroke_bounds`): [width] all around, or [widths] side by
  /// side (top, right, bottom, left), in [style] (`solid`, `dashed`,
  /// `dotted`, `double`) with corners of [radius].
  static void _strokeBounds(
    Canvas canvas,
    Rect rect,
    Color color, {
    double width = 0.5,
    List<double>? widths,
    String? style,
    double radius = 0,
  }) {
    if (widths case [final top, final right, final bottom, final left]) {
      if (top > 0) {
        _horizontalRule(
          canvas,
          color,
          rect.left - left * 0.5,
          rect.right - right * 0.5,
          rect.top,
          top,
          style,
        );
      }
      if (right > 0) {
        _verticalRule(
          canvas,
          color,
          rect.right,
          rect.top + top * 0.5,
          rect.bottom - bottom * 0.5,
          right,
          style,
        );
      }
      if (bottom > 0) {
        _horizontalRule(
          canvas,
          color,
          rect.left - left * 0.5,
          rect.right - right * 0.5,
          rect.bottom,
          bottom,
          style,
        );
      }
      if (left > 0) {
        _verticalRule(
          canvas,
          color,
          rect.left,
          rect.top + top * 0.5,
          rect.bottom - bottom * 0.5,
          left,
          style,
        );
      }
      return;
    }
    void outline(Rect r) => _roundedRectangle(canvas, r, radius);
    canvas
      ..save()
      ..setStrokeColor(color);
    switch (style) {
      case 'dashed':
        canvas
          ..setLineWidth(width)
          ..dash([width * 4]);
      case 'dotted':
        canvas
          ..setLineWidth(width)
          ..dash([width]);
      case 'double':
        final single = width / 3;
        final inset = single * 2;
        canvas.setLineWidth(single);
        outline(rect);
        canvas.stroke();
        outline(
          Rect(
            rect.left + inset,
            rect.bottom + inset,
            rect.width - inset * 2,
            rect.height - inset * 2,
          ),
        );
        canvas
          ..stroke()
          ..restore();
        return;
      default:
        canvas.setLineWidth(width);
    }
    outline(rect);
    canvas
      ..stroke()
      ..restore();
  }

  /// Adds [rect] with corners of [radius] to [canvas]'s path as Prawn
  /// draws it (`rounded_rectangle`): from the top left corner, clockwise,
  /// so that a dash pattern starts where Prawn's does.
  static void _roundedRectangle(Canvas canvas, Rect rect, double radius) {
    const kappa = 4 * (1.4142135623730951 - 1) / 3;
    final points = [
      (rect.left, rect.top),
      (rect.right, rect.top),
      (rect.right, rect.bottom),
      (rect.left, rect.bottom),
    ];
    // The point [distance] before the end [to] of the line from [from].
    (double, double) onLine(
      double distance,
      (double, double) from,
      (double, double) to,
    ) {
      final (x0, y0) = from;
      final (x1, y1) = to;
      final length = math.sqrt(math.pow(x1 - x0, 2) + math.pow(y1 - y0, 2));
      final p = length == 0 ? 1.0 : (length - distance) / length;
      return (x0 + p * (x1 - x0), y0 + p * (y1 - y0));
    }

    final (startX, startY) = onLine(radius, points[1], points[0]);
    canvas.moveTo(startX, startY);
    for (var i = 0; i < 4; i++) {
      final a = points[i];
      final corner = points[(i + 1) % 4];
      final b = points[(i + 2) % 4];
      final (x1, y1) = onLine(radius, a, corner);
      final (bx1, by1) = onLine(radius - radius * kappa, a, corner);
      final (x2, y2) = onLine(radius, b, corner);
      final (bx2, by2) = onLine(radius - radius * kappa, b, corner);
      canvas
        ..lineTo(x1, y1)
        ..curveTo(bx1, by1, bx2, by2, x2, y2);
    }
    canvas.closePath();
  }

  /// Strokes a horizontal rule from [x1] to [x2] at [y] (the gem's
  /// `stroke_horizontal_rule`).
  static void _horizontalRule(
    Canvas canvas,
    Color color,
    double x1,
    double x2,
    double y,
    double width,
    String? style,
  ) {
    canvas
      ..save()
      ..setStrokeColor(color);
    switch (style) {
      case 'dashed':
        canvas
          ..setLineWidth(width)
          ..dash([width * 4]);
      case 'dotted':
        canvas
          ..setLineWidth(width)
          ..dash([width]);
      case 'double':
        final single = width / 3;
        canvas
          ..setLineWidth(single)
          ..moveTo(x1, y + single)
          ..lineTo(x2, y + single)
          ..stroke()
          ..moveTo(x1, y - single)
          ..lineTo(x2, y - single)
          ..stroke()
          ..restore();
        return;
      default:
        canvas.setLineWidth(width);
    }
    canvas
      ..moveTo(x1, y)
      ..lineTo(x2, y)
      ..stroke()
      ..restore();
  }

  /// Strokes a vertical rule at [x] from [top] to [bottom] (the gem's
  /// `stroke_vertical_rule`).
  static void _verticalRule(
    Canvas canvas,
    Color color,
    double x,
    double top,
    double bottom,
    double width,
    String? style,
  ) {
    canvas
      ..save()
      ..setLineWidth(width)
      ..setStrokeColor(color);
    var at = x;
    switch (style) {
      case 'dashed':
        canvas.dash([width * 4]);
      case 'dotted':
        canvas.dash([width]);
      case 'double':
        canvas
          ..moveTo(at - width, top)
          ..lineTo(at - width, bottom)
          ..stroke();
        at += width;
    }
    canvas
      ..moveTo(at, top)
      ..lineTo(at, bottom)
      ..stroke()
      ..restore();
  }

  /// The layout of the page being filled (`portrait`, `landscape`).
  String _layout = 'portrait';

  /// The pages of PDF files that are pages of the document, by the key of
  /// the page template they're laid out with.
  final Map<String, ImportedPage> _importedPages = {};

  /// [text] as Ruby's `to_i` reads it: the leading integer, else 0.
  static int _rubyInt(String text) =>
      int.tryParse(RegExp(r'^\s*[-+]?\d+').stringMatch(text)?.trim() ?? '') ??
      0;

  /// Whether the body is set in the theme's page columns.
  bool _inColumns = false;

  /// An article's page columns as the page template's own (their count
  /// and gap), each with its notes (`footnotes_placement: column`).
  (int, double)? _pageColumns;

  /// The width of the columns the content is set in, null outside them.
  double? _columnWidth;

  /// A drop waiting for the paragraph it starts (`heading_h<n>_drop_lines`):
  /// its text, its theme category (`heading_h<n>_drop`) and the lines it
  /// spans.
  _Drop? _pendingDrop;

  /// The columns each chapter of a book is set in (`page_columns`, modern
  /// engine), its heading across them and the columns balanced where it
  /// ends; 0 for none.
  int _bookColumns = 0;

  // Images.

  static final RegExp _dataUri = RegExp(
    r'^data:image/(png|jpe?g|gif|pdf|bmp|tiff|svg\+xml);base64,(.*)$',
  );

  /// The format of the image [target] (its extension, lower case).
  static String _imageFormat(String target) {
    final name = target.split('/').last;
    final dot = name.lastIndexOf('.');
    return dot <= 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  /// The local path of the image read last (SVG images refer to files
  /// relative to it).
  String? _lastImagePath;

  static final RegExp _imageMacro = RegExp(r'^image:{1,2}(.*?)\[(.*?)\]$');

  /// The target and the attributes of [value] when it's an image macro
  /// (a theme's logo or running content image).
  static (String, Map<String, String>)? _imageMacroOf(
    String value,
    List<String> positional,
  ) {
    if (!value.contains(':')) return null;
    final match = _imageMacro.firstMatch(value);
    if (match == null) return null;
    return (match[1]!, AttributeList(match[2]!).parse(positional));
  }

  /// [text] as a number, as Ruby's `to_f` reads it (its leading number,
  /// else 0).
  static double _toF(String text) =>
      double.tryParse(
        RegExp(r'^\s*[+-]?(?:\d+(?:\.\d+)?|\.\d+)(?:[eE][+-]?\d+)?')
                .stringMatch(text)
                ?.trim() ??
            '',
      ) ??
      0;

  // Tables.

  /// [value] (a theme value, maybe a list) for each side: top, right,
  /// bottom, left (the gem's `expand_rect_values`).
  static List<ThemeValue?> _rectValues(ThemeValue? value, ThemeValue fallback) {
    if (value is ThemeList && value is! CmykThemeColor) {
      final v = [for (final item in value.values) item];
      ThemeValue at(int i) =>
          i < v.length && v[i] is! ThemeNull ? v[i] : fallback;
      return switch (v.length) {
        1 => [at(0), at(0), at(0), at(0)],
        2 => [at(0), at(1), at(0), at(1)],
        3 => [at(0), at(1), at(2), at(1)],
        _ => [at(0), at(1), at(2), at(3)],
      };
    }
    final one = value ?? fallback;
    return [one, one, one, one];
  }

  /// [value] for rows and columns (the gem's `expand_grid_values`).
  static List<ThemeValue?> _gridValues(ThemeValue? value, ThemeValue fallback) {
    if (value is ThemeList && value is! CmykThemeColor) {
      final v = value.values;
      ThemeValue at(int i) =>
          i < v.length && v[i] is! ThemeNull ? v[i] : fallback;
      return v.length == 1 ? [at(0), at(0)] : [at(0), at(1)];
    }
    final one = value ?? fallback;
    return [one, one];
  }

  static double _width(ThemeValue? value) => switch (value) {
    ThemeNumber(:final value) => value.toDouble(),
    _ => 0,
  };

  /// The width of the table converted last, for the room it's given, and
  /// its alignment (for its caption).
  double Function(double width) _tableWidth = _fullWidth;
  String _tableAlign = 'left';

  static double _fullWidth(double width) => width;

  // Admonitions.

  /// The admonition icons of the gem, by type: icon, color and size.
  static const Map<String, (String, String, double)> _admonitionIcons = {
    'caution': ('fas-fire', 'BF3400', 24),
    'important': ('fas-exclamation-circle', 'BF0000', 24),
    'note': ('fas-info-circle', '19407C', 24),
    'tip': ('far-lightbulb', '111111', 24),
    'warning': ('fas-exclamation-triangle', 'BF6900', 24),
  };

  /// The icon sets whose font was found missing (said once each).
  final Set<String> _missingIcons = {};

  // Code.

  /// [markup] without the spans highlighting put in (`hljs-` classes), the
  /// other spans kept.
  static String _withoutHighlightSpans(String markup) {
    final out = StringBuffer();
    final open = <bool>[];
    var last = 0;
    for (final m in RegExp(
      '<span( class="hljs-[^"]*")?[^>]*>|</span>',
    ).allMatches(markup)) {
      final opening = !m[0]!.startsWith('</');
      final highlight = opening
          ? m[1] != null
          : (open.isEmpty || open.removeLast());
      if (opening) open.add(highlight);
      if (highlight) {
        out.write(markup.substring(last, m.start));
        last = m.end;
      }
    }
    return (out..write(markup.substring(last))).toString();
  }

  /// The highlight.js themes read, by name.
  final Map<String, HighlightStyle?> _highlightStyles = {};

  bool _warnedMath = false;

  /// The math layout: in the theme's `math_font_family` (a font with an
  /// OpenType `MATH` table), else Noto Sans Math (installed); a character
  /// the font lacks in the base font. Null when no math font loads.
  late final MathLayout? _math = () {
    EmbeddedFont? fontOf(String family) {
      try {
        final face = _fonts.font(family);
        if (face.pdf case final EmbeddedFont font
            when font.font.hasTable('MATH')) {
          return font;
        }
      } on FontException {
        // Reported below.
      }
      return null;
    }

    final family = _s('math_font_family');
    var font = family == null ? null : fontOf(family);
    if (family != null && font == null) {
      logger.warn(
        'theme key math_font_family: $family is not a font with a MATH '
        'table; using Noto Sans Math',
      );
    }
    font ??= _fonts.hasFamily('Noto Sans Math')
        ? fontOf('Noto Sans Math')
        : null;
    if (font == null) {
      if (!_warnedMath) {
        _warnedMath = true;
        logger.warn(
          'math is shown as its source in the PDF: no math font is '
          'installed (`ptome doctor` installs Noto Sans Math)',
        );
      }
      return null;
    }
    final base = _fonts.font(_font.family, _font.style).pdf;
    return MathLayout(
      font,
      fallbacks: [if (base case final EmbeddedFont text) text],
    );
  }();

  /// The formulas converted so far, by source and language, with the
  /// warning each gave.
  final Map<(String, bool), (MathNode?, String?)> _formulas = {};

  /// The formula of [source] (see [_mathOf]), and the warning to give.
  static (MathNode?, String?) _convertMath(
    String source, {
    required bool latex,
  }) {
    final unknown = <String>{};
    try {
      final math = latex
          ? latexToMath(_stripDelimiters(source), unknown: unknown)
          : asciimathToMath(source);
      if (unknown.isNotEmpty) {
        return (
          math,
          'unknown LaTeX math command${unknown.length == 1 ? '' : 's'} '
              '${unknown.join(', ')}, shown as written: $source',
        );
      }
      return (math, null);
    } on MathMLException catch (error) {
      return (null, 'could not typeset math: $source ($error)');
    }
  }

  /// LaTeX math without the `\(...\)`, `\[...\]` or `$...$` around it
  /// (Asciidoctor keeps them in `latexmath` content).
  static String _stripDelimiters(String source) {
    final text = source.trim();
    for (final (open, close) in const [
      (r'\(', r'\)'),
      (r'\[', r'\]'),
      (r'$$', r'$$'),
      (r'$', r'$'),
    ]) {
      if (text.length >= open.length + close.length &&
          text.startsWith(open) &&
          text.endsWith(close)) {
        return text.substring(open.length, text.length - close.length);
      }
    }
    return text;
  }

  var _mathCount = 0;

  /// The ruby annotations registered as inline graphics so far.
  var _rubyCount = 0;

  static String _unescapeXml(String text) => text
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#8217;', "'")
      .replaceAll('&amp;', '&');

  static String _escapeXml(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  /// [text] with its tabs expanded and its indentation kept: a leading
  /// space of each line becomes a no-break space (the gem's
  /// `guard_indentation`).
  static String _guardIndentation(String text) {
    var result = _expandTabs(text);
    if (result.isEmpty) return result;
    if (result.startsWith(' ')) result = '\u00a0${result.substring(1)}';
    return result.replaceAll('\n ', '\n\u00a0');
  }

  /// [text] with tabs expanded to the next multiple of 4 columns (the
  /// gem's `expand_tabs`).
  static String _expandTabs(String text) {
    if (!text.contains('\t')) return text;
    return text
        .split('\n')
        .map((line) {
          if (!line.contains('\t')) return line;
          final out = StringBuffer();
          var column = 0;
          for (final char in line.split('')) {
            if (char == '\t') {
              final spaces = 4 - column % 4;
              out.write(' ' * spaces);
              column += spaces;
            } else {
              out.write(char);
              column++;
            }
          }
          return out.toString();
        })
        .join('\n');
  }

  // Lists.

  /// The list markers in effect, innermost last.
  final List<_Numeral?> _listNumerals = [];
  final List<String?> _listBullets = [];

  /// The styles [font] gives text (to inherit).
  static Set<String> _stylesOf(_FontState font) => {
    if (font.style == 'bold' || font.style == 'bold_italic') 'bold',
    if (font.style == 'italic' || font.style == 'bold_italic') 'italic',
  };

  /// The callout glyphs of the theme.
  late final List<String> _conumGlyphs = () {
    final setting = _s('conum_glyphs') ?? 'circled';
    List<String> range(int from, int to) => [
      for (var c = from; c <= to; c++) String.fromCharCode(c),
    ];
    String char(String code) => code.startsWith(r'\u')
        ? String.fromCharCode(int.tryParse(code.substring(2), radix: 16) ?? 0)
        : code;
    return switch (setting) {
      'circled' => range(0x2460, 0x2473),
      'filled' => [...range(0x2776, 0x277f), ...range(0x24eb, 0x24f4)],
      _ => [
        for (final part in setting.split(','))
          ...switch (part.trimLeft().split('-')) {
            [final from, final to, ...] => range(
              char(from).runes.first,
              char(to).runes.first,
            ),
            [final from, ...] => [char(from)],
            _ => const <String>[],
          },
      ],
    };
  }();

  /// The body indent of the list being converted (`list_body_indent`), if
  /// any.
  double? _listBodyIndent;

  /// The widest marker of the list being converted.
  double _listMarkerWidth = 0;

  /// The width of the boxes the markers of the list being converted are
  /// set in, at their left, if fixed (`olist_marker_width`).
  double? _listMarkerBox;

  // Text.

  final Set<String> _reportedChoices = {};

  static const _alignsV = ['top', 'middle', 'center', 'bottom'];

  /// Where the block being converted starts in the source (with the
  /// sourcemap the PDF backend turns on), for the modern engine's
  /// messages.
  Cursor? _at;

  /// The block quotations the quotation lint measures once laid out
  /// (`quotation-lint`): the anchors at their text's start and end, where
  /// they are in the source, and their line pitch.
  final List<(String, String, Cursor?, double)> _quotationChecks = [];

  /// Hyphenates words (soft hyphens where they may break), or null.
  PatternHyphenator? _hyphenator;

  /// Whether every text that may be hyphenated is (the `hyphens`
  /// attribute or the theme's `base_hyphens`), rather than justified text
  /// alone (the modern engine's default).
  bool _hyphenateAll = false;

  /// Whether a line may break before any CJK character (the document's
  /// `scripts` is `cjk`).
  bool _cjkLineBreaks = false;

  /// [text] with a zero width space before each CJK character.
  static String _breakCjk(String text) => text.replaceAllMapped(
    RegExp(
      r'(?=[\u3000\u30a0-\u30ff\u3040-\u309f\p{Script=Han}\uff00-\uffef])',
      unicode: true,
    ),
    (_) => '\u200b',
  );

  // Running content.

  /// The first and last mark anchor on each page (by 0-based page):
  /// `running_content_marks` names the prefix of the anchors that are
  /// marks (`v-` for a Bible's verses); a page without one has the last
  /// one before it for both.
  List<(String, String)?> _pageMarks = const [];

  /// The first and last unit of the level `running_content_units` names
  /// (`verse`, or `bible.verse`) on each page (by 0-based page), from the
  /// document's units (ADR-0020); a page without one has the last one
  /// before it for both.
  List<(Unit, Unit)?> _pageUnits = const [];

  /// The pages before the running content starts, and before the page
  /// numbers start (the gem's `num_front_matter_pages`).
  (int, int) _skip = (0, 0);

  /// The page the body starts on (1-based).
  int _bodyStart = 1;

  /// The line heights that set a font's lines a pitch apart, by its
  /// family, style, size and the pitch (`<category>_line_pitch`).
  final Map<(String, String, double, double), double?> _pitchedHeights = {};

  /// `folio-start`, read once (see `_folioStart`).
  int? _folioStartValue;

  /// The pages of the table of contents (1-based, inclusive), if any.
  (int, int)? _tocPages;

  static Color? _color(ThemeColor? value) =>
      value is TransparentColor ? null : pdfColorOf(value);

  static final RegExp _attributeReference = RegExp(
    r'(?<!\\)\{(\w+(?:-\w+)*)\}',
  );

  // The outline.

  static String _roman(int number) {
    const values = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1];
    const letters = [
      'm',
      'cm',
      'd',
      'cd',
      'c',
      'xc',
      'l',
      'xl',
      'x',
      'ix',
      'v',
      'iv',
      'i',
    ];
    final out = StringBuffer();
    var n = number;
    for (var i = 0; i < values.length; i++) {
      while (n >= values[i]) {
        out.write(letters[i]);
        n -= values[i];
      }
    }
    return out.toString();
  }

  /// [markup] as plain text: tags dropped (with an image's alt text),
  /// character references resolved (unknown named ones as `?`), spaces
  /// trimmed and squeezed (the gem's `sanitize`).
  static String _plain(String markup) {
    var text = markup;
    if (text.contains('<')) text = text.replaceAll(RegExp('<[^>]+>\x00?'), '');
    if (text.contains('&')) {
      text = text.replaceAllMapped(
        RegExp(
          r'&(?:amp;)?(?:([a-z][a-z]+\d{0,2})|#(?:(\d\d\d{0,4})|x([0-9a-fA-F]{2,4})));',
        ),
        (m) {
          if (m[1] case final name?) {
            return switch (name) {
              'amp' => '&',
              'apos' => "'",
              'gt' => '>',
              'lt' => '<',
              'nbsp' => ' ',
              'quot' => '"',
              _ => '?',
            };
          }
          final code = m[2] != null
              ? int.parse(m[2]!)
              : int.parse(m[3]!, radix: 16);
          return String.fromCharCode(code);
        },
      );
    }
    return text.trim().replaceAll(RegExp(' {2,}'), ' ');
  }

  // Inline elements.

  @override
  String? convertInline(Inline node) {
    // Inline content may be converted while the document is parsed (a
    // section title, for its id), before the document is converted: the
    // theme is loaded then (the gem's `load_theme`).
    if (!_ready) {
      if (node.document case final Document doc) {
        _document = doc;
        _theme = _prepareTheme(_loadTheme(doc));
        _fonts = FontCatalog(
          _theme,
          shaping: _shaping,
          thousandthWidths: _thousandthWidths,
          kernTableOnly: _kernTableOnly,
          rightToLeftShapingOnly: _rightToLeftShapingOnly,
          singleByteFonts: _singleByteFonts,
          warn: logger.warn,
        );
        _markup = MarkupTransform(
          theme: _theme,
          invertEmphasis: _invertEmphasis,
          keepIndexSpace: true,
        );
        _ready = true;
      }
    }
    return _convertInline(node);
  }

  /// Whether the theme (and the state inline conversions use) is loaded.
  bool _ready = false;

  /// Whether the document is being converted (rather than parsed: inline
  /// content converted for a title's id, which the gem converts before
  /// its PDF state exists).
  bool _converting = false;

  /// Whether an xref's text is being resolved (an xref in a reference's
  /// own text then shows its refid).
  bool _resolvingXref = false;

  /// The bibliography entries referenced (they link back to the first
  /// reference).
  final Set<String> _bibrefRefs = {};

  /// [text] (markup when [markup]) with a zero-width space where each URL
  /// in it may break, as The Chicago Manual of Style (17th ed.) has a URL
  /// broken: after its `://`, after a colon or a double slash;
  /// before a single slash, a tilde, a period, a comma, a hyphen, an
  /// underscore, a question mark, a number sign or a percent sign; before
  /// or after an equals sign or an ampersand; never with a hyphen added.
  /// The modern engine's; with [delimiters], after `/`, `?`, `&` and `#`
  /// alone ([_delimiterBreaks]), and a word that starts with `www.` isn't
  /// read as a URL.
  static String _breakUrls(
    String text, {
    bool markup = true,
    bool delimiters = false,
  }) {
    final www = !delimiters;
    final out = StringBuffer();
    // The text between tags only (an href stays whole).
    final pieces = markup
        ? RegExp('<[^>]*>|[^<]+').allMatches(text).map((m) => m[0]!)
        : [text];
    // (With [delimiters], a link's text alone: a URL that isn't a link,
    // such as one in code, keeps its characters together.)
    var inLink = !markup;
    for (final piece in pieces) {
      if (piece.startsWith('<a ')) inLink = true;
      if (piece == '</a>') inLink = false;
      if (piece.startsWith('<') ||
          (delimiters && !inLink) ||
          (!piece.contains('://') && !(www && piece.contains('www.')))) {
        out.write(piece);
        continue;
      }
      out.write(
        piece.replaceAllMapped(_urlRx, (m) {
          if (m[4] case final link?) {
            return www ? '${m[3]}${_linkBreaks(link)}' : m[0]!;
          }
          final link = m[2]!;
          return delimiters
              ? '${m[1]}${_delimiterBreaks(link)}'
              : '${m[1]}\u200b${_linkBreaks(link)}';
        }),
      );
    }
    return out.toString();
  }

  /// [text] (markup when [markup]) with a zero-width space after each
  /// slash that isn't before a digit, a space or another slash, and after
  /// each `?` and `!` before a letter or a digit: where the Unicode line
  /// breaking algorithm (UAX #14: a slash's class SY, `?` and `!`'s EX)
  /// lets a line break (`and/or`, `/contacts?rows_only`).
  static String _breakAfterSlashes(String text, {bool markup = true}) {
    final pieces = markup
        ? RegExp('<[^>]*>|[^<]+').allMatches(text).map((m) => m[0]!)
        : [text];
    return pieces
        .map(
          (piece) => piece.startsWith('<') && markup
              ? piece
              : piece
                    .replaceAll(RegExp(r'/(?=[^\s\d/\u200b])'), '/\u200b')
                    .replaceAllMapped(
                      RegExp(r'[?!](?=[\p{L}\p{N}])', unicode: true),
                      (m) => '${m[0]}\u200b',
                    ),
        )
        .join();
  }

  /// A URL's scheme and `://`, then its address, trailing punctuation left
  /// out (a sentence's period after it is not the URL's).
  static final RegExp _urlRx = RegExp(
    '([a-zA-Z][a-zA-Z0-9+.-]*://)'
    r"((?:[0-9A-Za-z!#$%*+,\-./:;=?@_~'\[\]()]|&amp;)*"
    r'(?:[0-9A-Za-z#$%*+\-/=@_~\[\]()]|&amp;))'
    // Or a link from its `www.`, where a word starts.
    r'|(^|[\s\u00a0])'
    r"(www\.(?:[0-9A-Za-z!#$%*+,\-./:;=?@_~'\[\]()]|&amp;)*"
    r'(?:[0-9A-Za-z#$%*+\-/=@_~\[\]()]|&amp;))',
  );

  /// [link] (the part after `://`, or from `www.`) with a zero-width space
  /// at each of The Chicago Manual of Style's break points (see
  /// [_breakUrls]); `&amp;` is one character.
  static String _linkBreaks(String link) {
    final chars = RegExp(
      '&amp;|.',
      dotAll: true,
    ).allMatches(link).map((m) => m[0]!).toList();
    const before = {'/', '~', '.', ',', '-', '_', '?', '#', '%', '=', '&amp;'};
    const after = {'=', '&amp;'};
    final out = StringBuffer();
    for (var i = 0; i < chars.length; i++) {
      final c = chars[i];
      final previous = i > 0 ? chars[i - 1] : '';
      // (Not at the start, after an opening bracket, or between two
      // slashes; never twice in one place.)
      final allowed = i > 0 && previous != '(' && previous != '[';
      final breakBefore =
          allowed &&
          ((before.contains(c) && !(c == '/' && previous == '/')) ||
              after.contains(previous) ||
              (previous == ':' && c != '/') ||
              (previous == '/' && i > 1 && chars[i - 2] == '/' && c != '/'));
      if (breakBefore) out.write('\u200b');
      out.write(c);
    }
    return out.toString();
  }

  /// [link] (the part after `://`) with a zero-width space after each `/`,
  /// `?`, `&amp;` and `#` but its last character, and none that would
  /// leave a single character after it.
  static String _delimiterBreaks(String link) {
    var out = link.replaceAllMapped(
      RegExp(r'(?:/|\?|&amp;|#)(?!$)'),
      (m) => '${m[0]}\u200b',
    );
    if (out.length > 1 && out[out.length - 2] == '\u200b') {
      out = out.substring(0, out.length - 2) + out.substring(out.length - 1);
    }
    return out;
  }

  /// The role of a table cell's text that is a single phrase with one
  /// (`<span class="paid">Paid</span>`), if any.
  static String? _cellRole(String text) {
    final m = RegExp(
      r'^<span class="([\w-]+)">((?:(?!</?span[ >]).)*)</span>$',
      dotAll: true,
    ).firstMatch(text);
    return m?[1];
  }

  /// The destination of the callout list item for the callout [id].
  static String _calloutItem(String id) => '$id-item';

  /// The images inline images refer to, by the `src` of their `<img>`.
  final Map<String, Graphic> _inlineGraphics = {};

  /// Why the inline images that couldn't be read couldn't, by `src`.
  final Map<String, String> _imageProblems = {};

  /// [value] as Ruby writes a float (`50.0`).
  static String _rubyFloat(double value) =>
      value == value.roundToDouble() ? '${value.toInt()}.0' : '$value';

  /// The index of the document (terms in titles are stored while the
  /// document is parsed).
  final IndexCatalog _index = IndexCatalog();

  /// The boxes of the index section, filled in once the pages of the
  /// terms are known.
  List<LayoutBox>? _indexSlot;

  /// [numbers] with runs of consecutive numbers joined as ranges (the gem's
  /// `consolidate_ranges`).
  static List<String> _consolidateRanges(List<String> numbers) {
    if (numbers.length < 2) return numbers;
    final ranges = <List<String>>[];
    String? previous;
    for (final number in numbers) {
      if (previous != null &&
          (int.tryParse(previous) ?? 0) + 1 == (int.tryParse(number) ?? 0)) {
        if (ranges.last.length == 1) {
          ranges.last.add(number);
        } else {
          ranges.last[1] = number;
        }
      } else {
        ranges.add([number]);
      }
      previous = number;
    }
    return [for (final range in ranges) range.join('-')];
  }

  /// A variation selector, with the character before it.
  static final RegExp _variationSelectorRx = RegExp(
    '(.)?([\ufe00-\ufe0f])',
    unicode: true,
  );

  static final RegExp _spaceBeforeFootnoteRx = RegExp(
    '[ \t]+(?=<sup class="wj"><a (?:id="_footnoteref_|anchor="_footnotedef_))',
  );

  /// The texts of the labels the layout gives (a footnote's number on its
  /// page, `fn<index>`), from the layout before.
  final Map<String, String> _layoutLabels = {};

  /// The footnotes with a reference without an anchor (a footnote
  /// referred to again by its id).
  final Set<String> _unanchoredFootnotes = {};

  /// The footnotes already rendered (at the end of earlier chapters).
  final List<Footnote> _renderedFootnotes = [];

  /// The labels of footnotes rendered at the end of a chapter, for
  /// references to them later.
  final Map<String, String> _footnoteLabels = {};

  /// The footnotes set at the bottom of the page their reference is on,
  /// by the reference's anchor (modern engine).
  final Map<String, LayoutBox> _notes = {};

  /// The notes set beside the line their anchor is on, by the anchor (a
  /// role with `role_<role>_display: side`; modern engine).
  final Map<String, LayoutBox> _sideNotes = {};

  /// Each side note's role and the start of its text, by its anchor, for
  /// messages.
  final Map<String, (String, String)> _sideNoteTexts = {};

  /// The side notes marked so far, for their anchors' names.
  int _sideCount = 0;

  /// Where a phrase the theme leaves out of the text was (a private-use
  /// character, taken out with the space after it before the text is set).
  static const _hiddenMark = '\u{F8FF}';

  static final _sideRx = RegExp(
    '<side id="([^"]+)" role="([^"]+)">(.*?)</side>',
    dotAll: true,
  );

  /// The note streams set at the foot of the page apart from the
  /// footnotes, in order (`note_streams`, modern engine): units notes of
  /// those streams (`note:x[…]`), each styled by its own
  /// `note_stream_<name>_*` keys (as the `footnotes_*` keys style the
  /// footnotes), in `note_stream_<name>_columns`.
  late final List<String> _noteStreams = switch (_theme.value('note_streams')) {
    ThemeList(:final values)
        when !asciidoctorCompat(_document, CompatFormat.pdf) =>
      [for (final value in values) value.rubyString],
    _ => const [],
  };

  /// The stream of each note set in one, by its anchor.
  final Map<String, String> _noteStreamOf = {};

  /// The stream of each note set in a margin column of its own, by its
  /// anchor.
  final Map<String, String> _sideNoteStreamOf = {};
}
