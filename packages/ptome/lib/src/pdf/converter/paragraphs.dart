part of '../converter.dart';

// Paragraphs.

extension _Paragraphs on PdfConverter {
  /// Converts the paragraph [node].
  void convertParagraph(Block node) => _paragraph(node);

  /// Whether the engine's paragraphs can set text with [markup] as the
  /// text box does: none of what they don't do yet (FEAT-n1bkgf) in play,
  /// text running around a block floating to a side (after the first), a
  /// baseline grid,
  /// protrusion (`base_overhang`), font expansion, a last line aligned
  /// apart, labels hung from their anchors or side notes beside them.
  bool _engineCanSet(String markup) =>
      !_sideFloated &&
      _baselineGrid() == null &&
      _overhangAmount() == 0 &&
      _text.expansion == 0 &&
      _s('base_text_align_last') == null &&
      !markup.contains(hangAnchorPrefix) &&
      !markup.contains(sideNoteAnchorPrefix) &&
      !markup.contains('<side ');

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

  /// [content] (in [font], set by [align]) with [drop] beside its first
  /// lines: set in `heading_h<n>_drop_font_*`, sized so that its capitals
  /// run from the first line's to the last of its lines' baseline,
  /// `heading_h<n>_drop_gap` (0.3em) from the text.
  CustomContent _dropped(
    _Drop drop,
    String content,
    _FontState font, {
    required String align,
  }) {
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
      dropBox,
      width + shift,
      baseline + (drop.lines - 1) * pitch - dropBaseline,
      shift: shift,
    );
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
      content = transformText(content, transform);
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
        if (_pendingInitial case (final category, final lines)) {
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
      content = _hyphenated(content, align);
    }
    if (node.hasTitle) _caption(node, labeled: false);
    // The modern engine keeps a paragraph's lines together at page
    // breaks: no fewer than prose_orphans at the bottom of a page and
    // prose_widows at the top of the next (2 each by default).
    final box = _textBox(
      content,
      font,
      align: align,
      indent: indent,
      orphans: (_n('prose_orphans') ?? 2).toInt(),
      widows: (_n('prose_widows') ?? 2).toInt(),
    );
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
    if (_engineParagraphs &&
        firstLine == null &&
        initial == null &&
        _pendingDrop == null &&
        _engineCanSet(content)) {
      if (box.engineContent() case final runs? when runs.isNotEmpty) {
        _engineParagraphCount++;
        final metrics = _lineMetrics(font);
        // (The text box sets half the leading and the font's line gap
        // above its first line, the engine's paragraph all of it under
        // each line: the space above as padding, kept at a page's top as
        // the box keeps it, and that much less below.)
        // (The text box's font metrics are Prawn's, an embedded font's
        // rounded to thousandths of the em; the engine's the font's own:
        // the leading and the space above take up the difference, so the
        // lines fall where the box sets them.)
        final face = _fonts.font(font.family, font.style);
        final engineFont = face.pdf;
        final scale = font.size / 1000;
        final engineHeight =
            (engineFont.ascender - engineFont.descender + engineFont.lineGap) *
            scale;
        final heightShift = face.heightAt(font.size) - engineHeight;
        final ascentShift =
            face.ascenderAt(font.size) - engineFont.ascender * scale;
        _out.add(
          ParagraphBox(
            Paragraph(
              runs,
              align: switch (align) {
                'justify' => TextAlign.justify,
                'center' => TextAlign.center,
                'right' => TextAlign.right,
                _ => TextAlign.left,
              },
              // (Half the leading and the font's line gap above each line,
              // as the text box sets them.)
              lineHeight: LineHeight.font(
                leading: metrics.leading + heightShift,
                above: metrics.paddingTop + ascentShift,
              ),
              firstLineIndent: indent,
              // (A superscript in the space between lines, as the text
              // box sets it.)
              riseInLineHeight: false,
            ),
            style: BoxStyle(
              margin: EdgeInsets(bottom: marginBottom),
              anchor: node.id,
              runsAround: true,
              gridLine: _gridLineOf(node),
            ),
            orphans: (_n('prose_orphans') ?? 2).toInt(),
            widows: (_n('prose_widows') ?? 2).toInt(),
          ),
        );
        return;
      }
    }
    CustomContent text = box;
    if (initial ?? _takeDrop(node) case final drop? when firstLine == null) {
      text = _dropped(drop, content, font, align: align);
    }
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
      if (_n('role_${role.replaceAll('-', '_')}_grid_line') case final line?) {
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
}
