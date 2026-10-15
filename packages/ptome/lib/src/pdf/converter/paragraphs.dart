part of '../converter.dart';

// Paragraphs.

/// Orphans and widows that keep a paragraph's lines together (more than
/// a heading has).
const int _wholeLines = 1 << 20;

/// The words from which a quotation is set off (Chicago 13.9).
const int _runInLimit = 100;

/// The lines a block quotation has at the least (fewer: run in).
const int _blockLeast = 5;

extension _Paragraphs on PdfConverter {
  /// Converts the paragraph [node].
  void convertParagraph(Block node) => _paragraph(node);

  /// [box]'s text as the engine's paragraph ([runs], its
  /// [TextBox.engineContent]) set as the box sets it: its leading, the
  /// space above its first line and under its last, its lines at least as
  /// tall as its base text where it asks (`normalizeLineHeight`), its last
  /// line's alignment, protrusion and width; with [hangIndent] for
  /// [hangLines] lines and [firstLineContent] where given.
  Paragraph _engineParagraphOf(
    TextBox box,
    List<InlineContent> runs, {
    double hangIndent = 0,
    int hangLines = 0,
    List<InlineContent>? firstLineContent,
  }) {
    final layout = box.layout;
    final state = box.state;
    final size = state.size;
    // (The text box's font metrics are Prawn's, an embedded font's
    // rounded to thousandths of the em; the engine's the font's own: the
    // leading and the space above take up the difference, so the lines
    // fall where the box sets them.)
    final face = _fonts.font(state.family, state.style);
    final engineFont = face.pdf;
    final scale = size / 1000;
    final engineHeight =
        (engineFont.ascender - engineFont.descender + engineFont.lineGap) *
        scale;
    final heightShift = face.heightAt(size) - engineHeight;
    final ascentShift = face.ascenderAt(size) - engineFont.ascender * scale;
    // (The space under the last line where it isn't the space between
    // lines' share, half the leading: none, a cell's line gap.)
    final ownEnd =
        (layout.initialGap - (layout.leading / 2 + face.lineGapAt(size)))
                .abs() >
            1e-9 ||
        (layout.paddingBottom - layout.leading / 2).abs() > 1e-9 ||
        layout.trailingLineGap ||
        layout.finalGap;
    return Paragraph(
      runs,
      hangIndent: hangIndent,
      hangLines: hangLines,
      firstLineContent: firstLineContent,
      rightToLeft: layout.rightToLeft && layout.mirrored,
      align: _aligned(
        layout.align,
        mirrored: layout.mirrored,
        rightToLeft: layout.rightToLeft,
      ),
      // (The space above each line as the text box sets it; with
      // `base_leading`, the lines from their cap heights.)
      lineHeight: layout.capLines
          ? LineHeight.cap(leading: layout.leading)
          : LineHeight.font(
              leading: layout.leading + heightShift,
              above: layout.initialGap + ascentShift,
              // (Lines the text's own font height apart whatever fonts
              // they mix, as the text box sets them: TeX's interline glue.)
              skip: _text.interlineGlue ? TextStyle(engineFont, size) : null,

              endDepth: ownEnd
                  ? face.descenderAt(size) +
                        layout.paddingBottom +
                        (layout.trailingLineGap ? face.lineGapAt(size) : 0) +
                        // (The space a line with more after it keeps under
                        // it: its line gap and the leading.)
                        (layout.finalGap
                            ? face.lineGapAt(size) + layout.leading
                            : 0)
                  : null,
            ),
      // (JLREQ 3.1.5 ③, `base_line_start_bracket: novel`: a paragraph
      // starting with an opening bracket not indented, the bracket's blank
      // half its indent.)
      firstLineIndent:
          _lineStartBrackets == LineStartBrackets.novel &&
              _startsWithOpeningBracket(runs)
          ? 0
          : layout.indentFirstLine,
      strut: layout.normalizeLineHeight ? TextStyle(engineFont, size) : null,
      // (`base_text_align_last`: a justified paragraph's last line, and
      // those before a hard break.)
      // (A line forced to justify, a first line set apart with more after
      // it, justified as the lines before the last are.)
      alignLast: layout.forceJustify && layout.align == 'justify'
          ? TextAlign.justify
          : _aligned(
              layout.alignLast,
              mirrored: layout.mirrored,
              rightToLeft: layout.rightToLeft,
            ),
      // (`base_overhang`: protrusion.)
      protrusion: layout.overhang,
      kashida: _text.kashida,
      // (`base_word_break`: `keep-all` breaks no word written without
      // spaces, `normal` wherever UAX #14 allows; by default, Korean
      // keeps its words.)
      // (`base_hanging_punctuation`: a full stop or comma ending a line
      // hangs past it, burasagari; `base_line_start_bracket`: how an
      // opening bracket starting a line is set, JLREQ 3.1.5.)
      hangingPunctuation: switch (_theme.value('base_hanging_punctuation')) {
        ThemeBool(value: true) => true,
        _ => false,
      },
      lineStartBrackets: _lineStartBrackets,
      lineBreak: _lineBreak,
      // (`base_tsheg_padding`: Tibetan lines ending with a tsheg filled
      // out with tshegs; `base_justify_alternates: false`: no `jalt`
      // forms, Nastaliq's wider letters, in justified lines.)
      tshegPadding: switch (_theme.value('base_tsheg_padding')) {
        ThemeBool(value: true) => true,
        _ => false,
      },
      justificationAlternates: switch (_theme.value(
        'base_justify_alternates',
      )) {
        ThemeBool(value: false) => false,
        _ => true,
      },
      wordBreak: switch (_s('base_word_break')) {
        'keep-all' => WordBreak.keepAll,
        'normal' => WordBreak.normal,
        _ => WordBreak.auto,
      },
      justifyToWidest: layout.justifyWidest,
      // (A superscript in the space between lines, as the text box sets
      // it.)
      riseInLineHeight: false,
    );
  }

  /// How strictly lines break around East Asian punctuation and small
  /// kana (CSS's `line-break`): the theme's `base_line_break`, else the
  /// document's `line-break` (`strict`, the default, `normal`, `loose`,
  /// `anywhere`); UAX #14's rules under `asciidoctor-compat`.
  LineBreakStrictness get _lineBreak {
    if (asciidoctorCompat(_document, CompatFormat.pdf)) {
      return LineBreakStrictness.strict;
    }
    final value = (_s('base_line_break') ?? _document.attr('line-break'))
        ?.trim()
        .toLowerCase();
    return LineBreakStrictness.values.firstWhere(
      (s) => s.name == value,
      orElse: () => LineBreakStrictness.strict,
    );
  }

  /// How an opening bracket starting a line is set
  /// (`base_line_start_bracket`: `solid`, `full-width`, `novel`).
  LineStartBrackets get _lineStartBrackets =>
      switch (_s('base_line_start_bracket')) {
        'full-width' => LineStartBrackets.fullWidth,
        'novel' => LineStartBrackets.novel,
        _ => LineStartBrackets.solid,
      };

  /// Whether [runs] start with a full-width opening bracket.
  static bool _startsWithOpeningBracket(List<InlineContent> runs) {
    for (final run in runs) {
      if (run case TextRun(:final text) when text.trim().isNotEmpty) {
        return const {
          0x3008, 0x300a, 0x300c, 0x300e, 0x3010, 0x3014, 0x3016, //
          0x3018, 0x301a, 0x301d, 0xff08, 0xff3b, 0xff5b, 0xff5f,
        }.contains(text.trimLeft().runes.first);
      }
      if (run is! TextRun) return false;
    }
    return false;
  }

  /// The theme's alignment [value] (`left`, `center`, `right`,
  /// `justify`); in a right-to-left document, [mirrored] (the theme's
  /// `left`, the start, is the right) unless it names the page's sides.
  TextAlign _aligned(String? value, {bool mirrored = true, bool? rightToLeft}) {
    final flip = (rightToLeft ?? _rightToLeft) && mirrored;
    return switch (value) {
      'justify' => TextAlign.justify,
      'center' => TextAlign.center,
      'right' => flip ? TextAlign.left : TextAlign.right,
      _ => flip ? TextAlign.right : TextAlign.left,
    };
  }

  /// [box] in [style] as the engine's paragraph, where the engine sets it
  /// as the box does (FEAT-5w237r), else the box itself.
  ///
  /// With [whole], its lines kept together (as a heading's).
  LayoutBox _engineOr(
    TextBox box, {
    BoxStyle style = const BoxStyle(),
    bool whole = false,
  }) {
    final layout = box.layout;
    if (!_engineParagraphs ||
        layout.singleLine ||
        layout.shrinkToFit ||
        layout.finalGap ||
        layout.forceJustify ||
        layout.wrapIndent != null ||
        layout.dropLines > 0 ||
        layout.lineInsets.isNotEmpty ||
        (layout.capLines && layout.trailingLineGap) ||
        // (Labelled as the pages are laid out: the box places it, its
        // lines the engine's.)
        box.hasLabels) {
      return CustomBox(box, style: style);
    }
    final runs = box.engineContent();
    if (runs == null || runs.isEmpty) return CustomBox(box, style: style);
    _engineParagraphCount++;
    return ParagraphBox(
      _engineParagraphOf(box, runs),
      style: style,
      orphans: whole ? _wholeLines : layout.orphans,
      widows: whole ? _wholeLines : layout.widows,
      lineBreaker: textLineBreaker(_text, layout.align, box.state.size),
    );
  }

  /// [box] as the engine's paragraph, as content that the box places and
  /// measures by (`TextContext.engine`), where the engine sets it as the
  /// box does; null for the box to set its own lines.
  CustomContent? _engineTextOf(TextBox box) {
    final layout = box.layout;
    if (layout.wrapIndent case final wrapIndent?
        when !layout.finalGap &&
            !layout.forceJustify &&
            layout.dropLines == 0 &&
            layout.lineInsets.isEmpty) {
      return _engineCodeOf(box, wrapIndent);
    }
    if (layout.wrapIndent != null || layout.lineInsets.isNotEmpty) {
      return null;
    }
    // (A drop beside its first lines, where the text starts: those lines
    // set in by its width, as the box sets them.)
    final dropped = box.first && layout.dropLines > 0;
    Paragraph paragraphOf(List<InlineContent> runs) => _engineParagraphOf(
      box,
      runs,
      hangIndent: dropped ? layout.dropIndent : 0,
      hangLines: dropped ? layout.dropLines : 0,
    );
    // (With an image a share of the width: the paragraph at each width.)
    if (box.hasRelativeImages) {
      ParagraphContent? at(double width) {
        final runs = box.engineContent(width: width);
        if (runs == null || runs.isEmpty) return null;
        return ParagraphContent(
          paragraphOf(runs),
          lineBreaker: textLineBreaker(_text, layout.align, box.state.size),
          orphans: layout.orphans,
          widows: layout.widows,
          slant: layout.skew ?? 0,
          goesOn: !box.startsLine,
        );
      }

      return at(1000) == null ? null : _EngineAtWidth(at);
    }
    final runs = box.engineContent();
    if (runs == null || runs.isEmpty) return null;
    return ParagraphContent(
      paragraphOf(runs),
      lineBreaker: textLineBreaker(_text, layout.align, box.state.size),
      orphans: layout.orphans,
      widows: layout.widows,
      slant: layout.skew ?? 0,
      goesOn: !box.startsLine,
    );
  }

  /// [box], a listing that wraps with a hanging indent (`code_wrap_indent`)
  /// or a marker, as the engine's lines: each of its lines a paragraph of
  /// its own, broken as the box breaks code.
  CustomContent? _engineCodeOf(TextBox box, double wrapIndent) {
    final runs = box.engineContent();
    if (runs == null || runs.isEmpty) return null;
    final layout = box.layout;
    // (Its lines: the runs split at their line feeds.)
    final lines = <List<InlineContent>>[[]];
    for (final run in runs) {
      if (run case TextRun(:final text) when text.contains('\n')) {
        for (final (i, part) in text.split('\n').indexed) {
          if (i > 0) lines.add([]);
          lines.last.add(run.withText(part));
        }
      } else {
        lines.last.add(run);
      }
    }
    final base = _engineParagraphOf(
      box,
      runs,
    ).copyWith(breakOpportunities: BreakOpportunities.spacesAndHyphens);
    // (Each line but the last spaced as a line of the listing: the space
    // under the listing's last line is its own.)
    final within = switch (base.lineHeight) {
      FontLineHeight(
        :final leading,
        :final above,
        :final skip,
        :final lineSkip,
      ) =>
        LineHeight.font(
          leading: leading,
          above: above,
          skip: skip,
          lineSkip: lineSkip,
        ),
      final height => height,
    };
    return _EngineCode(
      [
        for (final (i, content) in lines.indexed)
          (
            base.copyWith(
              content: content,
              lineHeight: i < lines.length - 1 ? within : base.lineHeight,
            ),
            _leadingWidth(content),
          ),
      ],
      wrapIndent: wrapIndent,
      marker: layout.wrapMarker,
      orphans: layout.orphans,
      widows: layout.widows,
    );
  }

  /// The width of the spaces (no-break or not) [content] starts with.
  static double _leadingWidth(List<InlineContent> content) {
    var width = 0.0;
    for (final run in content) {
      if (run is! TextRun) break;
      final leading = RegExp('^[\u00a0 ]*').stringMatch(run.text) ?? '';
      width += run.style.measure(leading);
      if (leading.length < run.text.length) break;
    }
    return width;
  }

  /// The roles of paragraphs a heading for the margin passes
  /// (`heading_h<n>_margin_skip_roles`: a pericope's parallel passages).
  Set<String> _marginSkipRoles(String category) =>
      switch (_keys(category).value('skip_roles')) {
        ThemeList(:final values) => {for (final v in values) v.rubyString},
        ThemeString(:final value) => value.split(RegExp(r'[\s,]+')).toSet(),
        _ => const <String>{},
      };

  /// The drop waiting for [node], when it takes it: a paragraph with none
  /// of the roles `heading_h<n>_drop_skip_roles` names (a psalm's title,
  /// a heading's parallel passages, which go before the drop).
  _Drop? _takeDrop(Block node) {
    final drop = _pendingDrop;
    if (drop == null) return null;
    final skip = switch (_keys(drop.category).value('skip_roles')) {
      ThemeList(:final values) => {for (final v in values) v.rubyString},
      ThemeString(:final value) => value.split(RegExp(r'[\s,]+')).toSet(),
      _ => const <String>{},
    };
    if (node.roles.any(skip.contains)) return null;
    _pendingDrop = null;
    return drop;
  }

  /// [drop] beside the first lines of text in [font]: set in
  /// `heading_h<n>_drop_font_*`, sized so that its capitals run from the
  /// first line's to the last of its lines' baseline,
  /// `heading_h<n>_drop_gap` (0.3em) from the text: the drop's text, the
  /// room it takes beside the lines, how far left of the text it starts
  /// (its opening punctuation) and how far down from the text's top.
  ({CustomContent box, double width, double shift, double dy}) _dropOf(
    _Drop drop,
    _FontState font,
  ) {
    final face = _fonts.font(font.family, font.style);
    final capLines = _capLeading(font) != null;
    final metrics = _lineMetrics(font);
    final cap = face.capHeightAt(font.size);
    // The first line's baseline and the distance between baselines.
    final baseline = capLines
        ? cap
        : metrics.paddingTop + face.ascenderAt(font.size);
    final pitch = (capLines ? cap : face.heightAt(font.size)) + metrics.leading;
    final category = drop.category;
    final unsized = _themeFont(category, font);
    final dropFace = _fonts.font(unsized.family, unsized.style);
    final size = ((drop.lines - 1) * pitch + cap) / dropFace.capHeightAt(1);
    final dropFont = unsized.copyWith(size: size);
    final text = drop.text.replaceAll('&', '&amp;').replaceAll('<', '&lt;');
    final gap = _keys(category).length('gap', font.size) ?? font.size * 0.3;
    // (Opening punctuation hung left of the text's edge.)
    final punctuation = _openingPunctuation.stringMatch(drop.text) ?? '';
    final shift = dropFace.widthOf(punctuation, size);
    final width = dropFace.widthOf(drop.text, size) - shift + gap;
    final dropBox = _textBox(
      text,
      dropFont,
      align: 'left',
      normalize: false,
      gaps: false,
      singleLine: true,
      overhang: false,
    );
    final dropBaseline = _capLeading(dropFont) != null
        ? dropFace.capHeightAt(size)
        : dropFace.ascenderAt(size);
    return (
      box: dropBox,
      width: width,
      shift: shift,
      dy: baseline + (drop.lines - 1) * pitch - dropBaseline,
    );
  }

  /// [content] (in [font], set by [align]) with [drop] beside its first
  /// lines (see [_dropOf]).
  CustomContent _dropped(
    _Drop drop,
    String content,
    _FontState font, {
    required String align,
  }) {
    final (:box, :width, :shift, :dy) = _dropOf(drop, font);
    return _Dropped(
      _textBox(
        content,
        font,
        align: align,
        orphans: (_n('prose_orphans') ?? 2).toInt(),
        widows: (_n('prose_widows') ?? 2).toInt(),
        dropLines: drop.lines,
        dropIndent: width,
      ),
      box,
      width + shift,
      dy,
      shift: shift,
    );
  }

  /// The first-line indent of text that opens with a phrase of a role
  /// whose `role_<role>_text_indent` is `continue` (modern engine): as
  /// far in as the last line of the text set before it reaches, and a
  /// space, so that a verse line shared between two speakers reads as one
  /// line (`[.shared]#’Tis time#`); null for other text. Records [content]'s
  /// own last line for the next.
  double? _continuedIndent(String content, _FontState font) {
    double? indent;
    final open = RegExp('^<span class="([^"]+)">').firstMatch(content);
    if (open != null &&
        !asciidoctorCompat(_document, CompatFormat.pdf) &&
        open[1]!
            .split(' ')
            .any((role) => _s('role_${role}_text_indent') == 'continue')) {
      if (_lastTextLine case (final line, final lineFont)) {
        final (_, width) = _textBox(
          '$line&#160;',
          lineFont,
          align: 'left',
        ).intrinsicWidths();
        indent = width;
      }
    }
    final br = content.lastIndexOf('<br>');
    _lastTextLine = (
      (br < 0 ? content : content.substring(br + '<br>'.length)).trim(),
      font,
    );
    return indent;
  }

  /// Adds the paragraph [node], aligned to [textAlign] unless a role
  /// aligns it, its first line in [firstLine]'s font if given.
  void _paragraph(
    Block node, {
    String? textAlign,
    _FontState? firstLine,
    String? firstLineTransform,
  }) {
    final roles = node.roles;
    String? roleAlign;
    for (final role in roles.reversed) {
      roleAlign =
          PdfConverter._alignOf([role]) ??
          _keys('role_$role').string('text_align');
      if (roleAlign != null) break;
    }
    final align = roleAlign ?? textAlign ?? _baseTextAlign;
    var font = _font;
    for (final role in roles) {
      font = _themeFont('role_$role', font);
    }
    var indent = 0.0;
    if (align == 'justify' || align == 'left') {
      final textIndent = _length('prose_text_indent', font.size) ?? 0;
      final inner = _length('prose_text_indent_inner', font.size) ?? 0;
      if (textIndent > 0) {
        indent = textIndent;
      } else if (inner > 0 &&
          _flowPrevious(node)?.context == BlockContext.paragraph) {
        indent = inner;
      }
    }
    final next = _flowNext(node);
    final innerMargin = _n('prose_margin_inner');
    var marginBottom =
        innerMargin != null && next?.context == BlockContext.paragraph
        ? innerMargin.toDouble()
        : _marginBelow(node, next: next, fallback: 'prose');
    // The modern engine: a role's indent, and space before the next block,
    // in place of the prose's (`role_<role>_text_indent`,
    // `role_<role>_margin_bottom`).
    for (final role in roles) {
      if (_keys('role_$role').length('text_indent', font.size)
          case final value?) {
        indent = value;
      }
      final parent = node.parent;
      final last =
          parent is! AbstractBlock || identical(parent.blocks.last, node);
      if (_keys('role_$role').number('margin_bottom') case final value?
          when !last) {
        marginBottom = value.toDouble();
      }
    }

    var content = node.content() ?? '';
    // The modern engine: a paragraph of concealed index terms alone takes
    // no room (their anchors where it is); `index_terms_paragraph: line`
    // sets it as an empty line, as any paragraph.
    if (!node.hasTitle &&
        _choice('index_terms_paragraph', const ['none', 'line']) != 'line') {
      final terms = RegExp('<a id="([^"]+)" type="indexterm">$_dummyText</a>')
          .allMatches(content)
          .toList();
      if (terms.isNotEmpty &&
          content
              .replaceAll(
                RegExp('<a id="[^"]+" type="indexterm">$_dummyText</a>'),
                '',
              )
              .trim()
              .isEmpty) {
        // (They go with the block after them: the content they index.)
        _out.add(
          BlockBox([
            for (final term in terms)
              CustomBox(const _Nothing(), style: BoxStyle(anchor: term[1])),
          ], style: const BoxStyle(keepWithNext: true)),
        );
        return;
      }
    }
    if (font.transform case final transform? when transform != 'none') {
      content = transformText(content, transform, language: _language);
    }
    // A jump line (`[.jump]`, a cross reference alone; modern engine):
    // worded by `jump-template` with the target's page, known once the
    // pages are laid out ("Continued on page 7").
    if (isJump(node) && !asciidoctorCompat(_document, CompatFormat.pdf)) {
      if (_jumpAnchorRx.firstMatch(content) case final link?) {
        final target = link[1]!;
        final back = jumpsBack(_document, node, target);
        TextBox jump(String page) => _textBox(
          '<a anchor="$target">'
          '${jumpText(_document, title: link[2]!, back: back, page: page)}'
          '</a>',
          font,
          align: align,
          indent: indent,
        );
        _out.add(
          CustomBox(
            _LateText(jump, () => _anchorLabel(target)),
            style: BoxStyle(
              margin: EdgeInsets(bottom: marginBottom),
              anchor: node.id,
            ),
          ),
        );
        return;
      }
    }
    // The modern engine's `role_<role>_drop_lines`: the paragraph's own
    // first letter as an initial beside its first lines (and its first
    // `role_<role>_drop_lead_in` words in the role `lead-in`).
    _Drop? initial;
    if (_pendingDrop == null &&
        firstLine == null &&
        !asciidoctorCompat(_document, CompatFormat.pdf)) {
      for (final role in roles) {
        final lines = (_keys('role_$role').number('drop_lines') ?? 0).toInt();
        if (lines < 2) continue;
        if (PdfConverter._initialOf(content) case (final letter, final rest)) {
          final words = (_keys('role_$role').number('drop_lead_in') ?? 0)
              .toInt();
          content = words > 0 ? PdfConverter._leadIn(rest, words) : rest;
          initial = (text: letter, category: 'role_${role}_drop', lines: lines);
        }
        break;
      }
      // (`heading_h<n>_initial_lines`: the section's first paragraph opens
      // with its own first letter as an initial, its lead-in words
      // `_initial_lead_in`, as a novel's chapter opens.)
      if (initial == null) {
        // (`heading_h<n>_initial_skip_roles`: a paragraph with one of
        // them passes the initial on, as a rubric does to the prayer
        // after it.)
        if (_pendingInitial case (final category, final lines)
            when !roles.any(_marginSkipRoles(category).contains)) {
          _pendingInitial = null;
          if (PdfConverter._initialOf(content) case (
            final letter,
            final rest,
          )) {
            final words = (_keys(category).number('lead_in') ?? 0).toInt();
            content = words > 0 ? PdfConverter._leadIn(rest, words) : rest;
            initial = (text: letter, category: category, lines: lines);
          }
        }
      }
    }
    // (A section's heading for the margin, hung left of the first line.)
    if (_pendingMargin case final margin?
        when !node.roles.any(_marginSkipRoles(margin.category).contains)) {
      _pendingMargin = null;
      final id = '$hangAnchorPrefix${_hungLabels.length}';
      _hungLabels[id] = (margin.text, margin.font);
      content = '<a id="$id">$_dummyText</a>$content';
    }
    // (The modern engine: `role_<role>_hyphens: false` keeps a role's
    // paragraphs whole, as an agency's name in capitals.)
    if (!roles.any(
      (role) => _theme.value('role_${role}_hyphens') == const ThemeBool(false),
    )) {
      if (_quotationLint) _lintRunIn(node, content);
      content = _hyphenated(content, align);
    }
    if (node.hasTitle) _caption(node, labeled: false);
    final shared = _continuedIndent(content, font);
    // The modern engine keeps a paragraph's lines together at page
    // breaks: no fewer than prose_orphans at the bottom of a page and
    // prose_widows at the top of the next (2 each by default).
    final set = _textBox(
      content,
      font,
      align: align,
      indent: shared ?? indent,
      orphans: (_n('prose_orphans') ?? 2).toInt(),
      widows: (_n('prose_widows') ?? 2).toInt(),
    );
    final box = shared == null ? set : set.continuing();
    if (_floatGroup case final group? when _floatNext == node) {
      final metrics = _lineMetrics(font);
      final prawnFont = _fonts.font(font.family, font.style);
      final following = _nextEnclosedBlock(node);
      group.paragraphs.add(
        _FloatParagraph(
          box,
          _textBox(content, font, align: align, indent: indent, gaps: false),
          marginBottom: marginBottom,
          blockMargin: _themeMargin('block', 'bottom', following),
          paddingTop: metrics.paddingTop,
          paddingBottom: metrics.paddingBottom,
          lineLength:
              font.lineHeight * font.size +
              metrics.leading +
              metrics.paddingTop,
          descender: prawnFont.descenderAt(font.size),
          anchor: node.id,
        ),
      );
      if (following case final Block block
          when block.context == BlockContext.paragraph) {
        _floatNext = block;
      } else {
        _floatGroup = _floatNext = null;
      }
      return;
    }
    // (The modern engine: a plain paragraph set by plain_typesetting's
    // paragraphs rather than this converter's text box, FEAT-n1bkgf; one
    // with what they don't do yet is set by the box, as is everything
    // with `base_text_engine: box`.)
    // (Its initial, a drop beside its first lines.)
    final drop = firstLine == null ? initial ?? _takeDrop(node) : null;
    // (A first line of its own style, an abstract's: the same text in that
    // style for the engine; one transformed stays in the box.)
    final firstRuns = firstLine == null || firstLineTransform != null
        ? null
        : _textBox(
            content,
            firstLine,
            align: align,
            indent: indent,
            singleLine: true,
          ).engineContent();
    if (_engineParagraphs &&
        (firstLine == null || firstRuns != null) &&
        !box.hasLabels) {
      if (box.engineContent() case final runs? when runs.isNotEmpty) {
        _engineParagraphCount++;
        // (A drop: the first lines set in beside it, as the text box sets
        // them, the drop painted at the paragraph's top, the paragraph as
        // deep as the drop at least.)
        final dropped = drop == null ? null : _dropOf(drop, font);
        var text = _engineParagraphOf(
          box,
          runs,
          hangIndent: dropped?.width ?? 0,
          hangLines: drop?.lines ?? 0,
          firstLineContent: firstRuns,
        );
        if (drop != null) text = text.copyWith(firstLineIndent: 0);
        final paragraph = ParagraphBox(
          text,
          style: BoxStyle(
            margin: EdgeInsets(bottom: dropped == null ? marginBottom : 0),
            anchor: node.id,
            runsAround: true,
            gridLine: _gridLineOf(node),
            // (With a drop, the block around it the paragraph, the drop's
            // letter its first.)
            structure: dropped == null ? _struct('P') : null,
          ),
          orphans: (_n('prose_orphans') ?? 2).toInt(),
          widows: (_n('prose_widows') ?? 2).toInt(),
          // (Broken as the text box breaks a paragraph of its alignment
          // and size: ragged and justified in one document.)
          lineBreaker: textLineBreaker(_text, align, font.size),
        );
        if (dropped == null) {
          _out.add(paragraph);
        } else {
          final mark = dropped.box.place(
            dropped.width + dropped.shift,
            double.infinity,
            atTop: true,
          );
          _out.add(
            BlockBox(
              [paragraph],
              style: BoxStyle(
                margin: EdgeInsets(bottom: marginBottom),
                structure: _struct('P'),
                minHeight: mark == null ? 0 : dropped.dy + mark.height,
                decoration: (page, rect, {required first, required last}) {
                  if (first) {
                    mark?.paint(
                      page,
                      rect.left - dropped.shift,
                      rect.top - dropped.dy,
                    );
                  }
                },
              ),
            ),
          );
        }
        return;
      }
    }
    CustomContent text = box;
    if (drop != null) text = _dropped(drop, content, font, align: align);
    if (firstLine != null) {
      text = FirstLineTextBox(
        _textBox(
          content,
          firstLine,
          align: align,
          indent: indent,
          singleLine: true,
        ),
        box.state,
        box.layout,
        transform: firstLineTransform,
      );
    }
    _out.add(
      CustomBox(
        text,
        style: BoxStyle(
          margin: EdgeInsets(bottom: marginBottom),
          anchor: node.id,
          // The modern engine: beside a block floating to a side (a pull
          // quote, a sidebar), the paragraph runs around it.
          runsAround: !asciidoctorCompat(_document, CompatFormat.pdf),
          gridLine: _gridLineOf(node),
          structure: _struct('P'),
        ),
      ),
    );
  }

  /// The line of the baseline grid a paragraph with one of its roles
  /// starts on at the least (`role_<role>_grid_line`, modern engine): a
  /// pleading's court title on line 8 of its first page.
  int? _gridLineOf(AbstractBlock node) {
    if (asciidoctorCompat(_document, CompatFormat.pdf)) return null;
    for (final role in node.roles) {
      if (_n('role_${_roleName(role)}_grid_line') case final line?) {
        return line.toInt();
      }
    }
    return null;
  }

  AbstractBlock? _previousSibling(AbstractBlock node) {
    final parent = node.parent;
    if (parent is! AbstractBlock) return null;
    var index = parent.blocks.indexOf(node);
    // (In the modern engine, past paragraphs of index terms alone: they
    // take no room.)
    while (index > 0 && _roomless(parent.blocks[index - 1])) {
      index--;
    }
    return index > 0 ? parent.blocks[index - 1] : null;
  }

  /// Whether [block] is a paragraph of concealed index terms alone, which
  /// the modern engine sets in no room.
  bool _roomless(AbstractBlock block) =>
      block.context == BlockContext.paragraph &&
      !block.hasTitle &&
      block is Block &&
      block.lines.isNotEmpty &&
      block.lines.every(
        (line) => RegExp(r'^\s*(\(\(\(.*?\)\)\)\s*)+$').hasMatch(line),
      );

  /// Whether the quotation lint is on (`quotation-lint`, modern engine):
  /// quotations set otherwise than The Chicago Manual of Style has them
  /// (13.9: a hundred words or more set off as a block quotation, fewer
  /// run in) are reported.
  bool get _quotationLint =>
      _document.hasAttr('quotation-lint') &&
      !asciidoctorCompat(_document, CompatFormat.pdf);

  /// Reports a quotation of a hundred words or more run in to [node]'s
  /// [markup] (between its double quotation marks).
  void _lintRunIn(Block node, String markup) {
    // (The marks as characters or as the references the markup has.)
    final text = markup
        .replaceAll(RegExp('<[^>]*>'), '')
        .replaceAll('&#8220;', '\u201c')
        .replaceAll('&#8221;', '\u201d');
    for (final match in RegExp(
      '\u201c([^\u201c\u201d]*)\u201d',
    ).allMatches(text)) {
      final words = RegExp(
        r"[\p{L}\p{N}][\p{L}\p{N}'\u2019-]*",
        unicode: true,
      ).allMatches(match[1]!).length;
      if (words >= _runInLimit) {
        logger.warn(
          'a quotation of $words words run in: one of a hundred words or '
          'more is set off as a block quotation (Chicago 13.9)',
          at: node.sourceLocation ?? _at,
        );
      }
    }
  }

  /// The block quotations of fewer than five lines, laid out in [result]:
  /// reported (run in, Chicago 13.9).
  void _lintBlockQuotations(LayoutResult result) {
    for (final (start, end, at, pitch) in _quotationChecks) {
      final (from, to) = (result.anchors[start], result.anchors[end]);
      // (One that goes on to another page is long enough.)
      if (from == null || to == null || from.page != to.page) continue;
      final lines = ((from.y - to.y) / pitch).round();
      if (lines > 0 && lines < _blockLeast) {
        logger.warn(
          'a block quotation of $lines '
          '${lines == 1 ? 'line' : 'lines'}: one shorter than '
          '$_blockLeast lines is run in (Chicago 13.9)',
          at: at,
        );
      }
    }
  }
}
