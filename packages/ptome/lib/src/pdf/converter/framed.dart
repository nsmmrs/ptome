part of '../converter.dart';

// Blocks with a background and a border.

extension _Framed on PdfConverter {
  /// The shadow of a block of theme [category], if any: its color
  /// (`<category>_shadow_color`), offset (`_shadow_offset`, right and
  /// down), blur (`_shadow_blur`, how far it fades out) and opacity
  /// (`_shadow_opacity`, 0.3); painted under the block, rounded as it is.
  void Function(Canvas canvas, Rect rect, double radius)? _shadow(
    String category,
  ) {
    final color = pdfColorOf(_c('${category}_shadow_color'));
    if (color == null) return null;
    final offset = switch (_theme.value('${category}_shadow_offset')) {
      ThemeList(:final values) when values.length >= 2 => (
        PdfConverter._toPoints(values[0]),
        PdfConverter._toPoints(values[1]),
      ),
      _ => (0.0, 2.0),
    };
    final blur = (_n('${category}_shadow_blur') ?? 4).toDouble();
    final opacity = (_n('${category}_shadow_opacity') ?? 0.3).toDouble();
    // (PDF has no blur: rounded rectangles shrinking inward, each adding a
    // little more of the color, so it fades out over the blur.)
    const steps = 8;
    return (canvas, rect, radius) {
      final (dx, dy) = offset;
      canvas
        ..save()
        ..setFillColor(color)
        ..opacity(fill: 1 - math.pow(1 - opacity, 1 / steps).toDouble());
      for (var i = 0; i < steps; i++) {
        final grow = blur / 2 - blur * i / steps;
        final r = Rect(
          rect.left + dx - grow,
          rect.bottom - dy - grow,
          rect.width + grow * 2,
          rect.height + grow * 2,
        );
        final rounded = radius + grow;
        rounded > 0 ? canvas.roundedRect(r, rounded) : canvas.rect(r);
        canvas.fill();
      }
      canvas.restore();
    };
  }

  /// The decoration of a block of theme [category] (the gem's
  /// `theme_fill_and_stroke_block`): its background and border, the
  /// border centered on the block's edge, with a dashed line where a split
  /// block continues; [extra] paints more.
  BoxDecoration? _blockDecoration(
    String category, {
    ThemeColor? background,
    bool noBorder = false,
    BoxDecoration? extra,
  }) {
    final widthValue = noBorder
        ? null
        : _theme.value('${category}_border_width');
    var borderWidth = switch (widthValue) {
      ThemeNumber(:final value) => value.toDouble(),
      ThemeList(:final values) when values.isNotEmpty => PdfConverter._toPoints(
        values[0],
      ),
      _ => 0.0,
    };
    final sideWidths = widthValue is ThemeList;
    var fill = background ?? _c('${category}_background_color');
    if (fill is TransparentColor) fill = null;
    // The modern engine: a shadow under the block and an image over its
    // background (`<category>_shadow_*`, `<category>_background_image`).
    final modern = !asciidoctorCompat(_document, CompatFormat.pdf);
    final shadow = modern ? _shadow(category) : null;
    final image = modern
        ? _resolveBackgroundImage('${category}_background_image')?.image
        : null;
    if (borderWidth <= 0 && fill == null && shadow == null && image == null) {
      return extra;
    }
    final stroke = _c('${category}_border_color') ?? _c('base_border_color');
    final pageBackground =
        _c('page_background_color') ?? const HexColor('FFFFFF');
    final radius = sideWidths
        ? 0.0
        : (_n('${category}_border_radius') ?? 0).toDouble();
    final dashRadius = radius + borderWidth;
    final Color? gapColor;
    final double shift;
    if (borderWidth > 0) {
      if (stroke == pageBackground) {
        (gapColor, shift) = (pdfColorOf(pageBackground), borderWidth * 0.5);
      } else if (fill != null && fill != stroke) {
        (gapColor, shift) = (pdfColorOf(fill), 0.0);
      } else {
        (gapColor, shift) = (pdfColorOf(pageBackground), 0.0);
      }
    } else {
      borderWidth = 0.5;
      (gapColor, shift) = (pdfColorOf(pageBackground), borderWidth * 0.5);
    }
    final hasStroke = (_n('${category}_border_width') ?? 0) > 0 || sideWidths;
    return (page, rect, {required first, required last}) {
      final canvas = page.canvas..save();
      shadow?.call(canvas, rect, radius);
      if (pdfColorOf(fill) case final color?) {
        canvas.setFillColor(color);
        radius > 0 ? canvas.roundedRect(rect, radius) : canvas.rect(rect);
        canvas.fill();
      }
      if (image != null) {
        canvas.save();
        radius > 0 ? canvas.roundedRect(rect, radius) : canvas.rect(rect);
        canvas
          ..clip()
          ..translate(rect.left, rect.bottom);
        _drawPageImage(canvas, image, size: (rect.width, rect.height));
        canvas.restore();
      }
      if (hasStroke) {
        if (pdfColorOf(stroke) case final color?) {
          PdfConverter._strokeBounds(
            canvas,
            rect,
            color,
            width: borderWidth,
            widths: _sideWidths(widthValue),
            style: _s('${category}_border_style'),
            radius: radius,
          );
        }
      }
      // A dashed line where the block continues from or to another page.
      void dashed(double y) {
        if (gapColor == null) return;
        canvas
          ..save()
          ..setStrokeColor(gapColor)
          ..setLineWidth(borderWidth * 1.2)
          ..dash([borderWidth * 1.2 * 4])
          ..moveTo(rect.left + dashRadius, y)
          ..lineTo(rect.right - dashRadius, y)
          ..stroke()
          ..restore();
      }

      if (!first) dashed(rect.top - shift);
      if (!last) dashed(rect.bottom + shift);
      canvas.restore();
      extra?.call(page, rect, first: first, last: last);
    };
  }

  /// The widths of a border's sides (top, right, bottom, left) from theme
  /// [value]: one width for all, or two (top and bottom, then sides), or
  /// four; null for one width for all.
  List<double>? _sideWidths(ThemeValue? value) => switch (value) {
    ThemeList(:final values) => switch ([
      for (final v in values)
        if (v is ThemeNull) 0.0 else PdfConverter._toPoints(v),
    ]) {
      [final a, final b] => [a, b, a, b],
      [final a, final b, final c, final d, ...] => [a, b, c, d],
      [final a, final b, final c] => [a, b, c, b],
      [final a] => [a, a, a, a],
      _ => null,
    },
    _ => null,
  };

  /// The padding of theme [key] as edge insets.
  EdgeInsets _padding(String key) {
    final values = _edgeValues(_theme.value(key) ?? const ThemeNumber(0));
    return EdgeInsets(
      top: values[0],
      right: values[1],
      bottom: values[2],
      left: values[3],
    );
  }

  /// Runs [body] with the font of theme [category] in effect.
  void _withFont(String category, void Function() body) {
    final saved = _font;
    _font = _themeFont(category, _font);
    try {
      body();
    } finally {
      _font = saved;
    }
  }

  /// The boxes [body] adds.
  List<LayoutBox> _collect(void Function() body) {
    final saved = _out;
    final boxes = <LayoutBox>[];
    _out = boxes;
    try {
      body();
    } finally {
      _out = saved;
    }
    return boxes;
  }

  /// Whether each piece of a block of theme [category] split across pages
  /// has its padding and border at its top and bottom (the modern
  /// engine's `<category>_box_decoration_break: clone`, as CSS's).
  bool _cloneEdges(String category) =>
      _choice('${category}_box_decoration_break', const ['slice', 'clone']) ==
      'clone';

  /// Whether the piece of a framed block a page's end cuts off reaches it
  /// (`block_split_end: region`) rather than ending under its last line
  /// (`content`).
  bool get _splitToRegionEnd =>
      _choice('block_split_end', const ['content', 'region']) == 'region';

  /// A block of [children] with the padding, the background and the
  /// border of theme [category], [node]'s anchor, and the block margin
  /// below it.
  void _framed(
    AbstractBlock node,
    String category,
    List<LayoutBox> children, {
    bool noBorder = false,
    BoxDecoration? extra,
  }) {
    _out.add(
      BlockBox(
        children,
        style: BoxStyle(
          padding: _padding('${category}_padding'),
          margin: EdgeInsets(bottom: _marginBelow(node)),
          keepTogether: node.hasOption('unbreakable'),
          cloneEdges: _cloneEdges(category),
          splitToRegionEnd: _splitToRegionEnd,
          anchor: node.id,
          decoration: _blockDecoration(
            category,
            noBorder: noBorder,
            extra: extra,
          ),
        ),
      ),
    );
  }

  /// Converts a unit that is blocks (ADR-0020): its blocks, kept together
  /// as an open block keeps them, with the unit's ID.
  void convertUnit(Block node) {
    final children = _collect(() => _traverse(node));
    _out.add(BlockBox(children, style: BoxStyle(anchor: node.id)));
  }

  /// Converts the open block [node].
  void convertOpen(Block node) {
    if (node.style == 'abstract') {
      _abstract(node);
      return;
    }
    final count = _columnSetOf(node);
    final children = _collect(() {
      if (node.hasTitle) {
        _caption(
          node,
          category: node.style == 'table-container' ? 'table' : null,
          labeled: false,
        );
      }
      if (count == null) {
        _traverse(node);
      } else {
        _out.add(_columns(node, count, () => _traverse(node)));
      }
    });
    _out.add(
      BlockBox(
        children,
        style: BoxStyle(
          keepTogether: node.hasOption('unbreakable'),
          anchor: node.id,
        ),
      ),
    );
  }

  /// The number of columns [node] sets its content in, the modern
  /// engine's `[.columns]` (a section's or an open block's): its
  /// `column-count` attribute, else `columns_count` (2); a section role's
  /// `section_role_<role>_page_columns`; null for none (or inside columns
  /// already).
  int? _columnSetOf(AbstractBlock node) {
    if (_inColumns || asciidoctorCompat(_document, CompatFormat.pdf)) {
      return null;
    }
    // (A section role's page template's columns.)
    if (node is Section) {
      for (final role in node.roles) {
        final name = role.replaceAll('-', '_');
        if (_n('section_role_${name}_page_columns') case final count?
            when count >= 2) {
          return count.toInt();
        }
      }
    }
    if (!node.includesRole('columns')) return null;
    final count =
        int.tryParse(node.attr('column-count') ?? '') ??
        (_n('columns_count') ?? 2).toInt();
    return count >= 2 ? count : null;
  }

  /// What [content] adds, in [count] columns balanced where they end
  /// (what follows starts under the longer of them), [node]'s.
  LayoutBox _columns(AbstractBlock node, int count, void Function() content) {
    final gap =
        _length('columns_gap', _font.size) ??
        (_n('page_column_gap') ?? _rootFontSize).toDouble();
    final body = _inColumnSet(count, gap, () => _collect(content));
    return ColumnsBox(
      body,
      count: count,
      gap: gap,
      balance: true,
      rule: _columnRule('columns') ?? _columnRule('page_column'),
    );
  }

  /// The rule between columns the theme's `<prefix>_rule_width` and
  /// `_rule_color` give (modern engine), if any.
  ColumnRule? _columnRule(String prefix) {
    if (asciidoctorCompat(_document, CompatFormat.pdf)) return null;
    final width = _n('${prefix}_rule_width')?.toDouble() ?? 0;
    if (width <= 0) return null;
    final color = pdfColorOf(
      _c('${prefix}_rule_color') ?? _c('base_border_color'),
    );
    return color == null ? null : ColumnRule(width: width, color: color);
  }

  /// The grid the body text's baselines keep to (`page_baseline_grid`,
  /// modern engine): `true` for the body text's line pitch, or a length;
  /// the first line where a body line at the top of the page has its
  /// baseline. For thin paper, whose show-through then falls between the
  /// lines (a line-matched Bible), and columns whose lines align.
  BaselineGrid? _baselineGrid() {
    if (asciidoctorCompat(_document, CompatFormat.pdf)) return null;
    // (Two lines a paragraph breaks into, one word each.)
    final body = _textBox('Ag Ag', _font, align: 'left');
    final step = switch (_theme.value('page_baseline_grid')) {
      ThemeBool(value: true) => body.linePitch(1),
      ThemeNumber(:final value) when value > 0 => value.toDouble(),
      _ => null,
    };
    if (step == null) return null;
    return BaselineGrid(step, offset: body.firstBaseline(1) ?? 0);
  }

  /// What [content] makes set in [count] columns [gap] apart.
  T _inColumnSet<T>(int count, double gap, T Function() content) {
    final (saved, savedWidth) = (_inColumns, _columnWidth);
    _inColumns = true;
    _columnWidth = _columnWidthOf(count, gap);
    try {
      return content();
    } finally {
      _inColumns = saved;
      _columnWidth = savedWidth;
    }
  }

  /// Whether [section] is an article's abstract (its first section, named
  /// abstract), which the gem converts as an abstract block.
  bool _isAbstract(Section section) =>
      _document.doctype == 'article' &&
      section.sectname == 'abstract' &&
      _document.sections.whereType<Section>().firstOrNull == section;

  /// Adds the name section of a man page, made from its `manname` and
  /// `manpurpose` (the gem's `generate_manname_section`).
  void _manNameSection(Document doc) {
    if (doc.doctype != 'manpage' || !doc.hasAttr('manpurpose')) return;
    var title = doc.attr('manname-title') ?? 'Name';
    final next = doc.blocks.whereType<Section>().firstOrNull?.title;
    if (next != null && next.toUpperCase() == next) {
      title = title.toUpperCase();
    }
    final section = Section(doc, 1)
      ..sectname = 'section'
      ..id = doc.attr('manname-id')
      ..title = title;
    section.append(
      Block(
        section,
        BlockContext.paragraph,
        source: '${doc.attr('manname')} - ${doc.attr('manpurpose')}',
        subs: const BlockSubs.spec('normal'),
      ),
    );
    convertSection(section);
  }

  /// The sections of [node] (an article's abstract isn't one).
  List<Section> _sectionsOf(AbstractBlock node) => [
    for (final section in node.blocks.whereType<Section>())
      if (!_isAbstract(section)) section,
  ];

  /// Adds the abstract [node] (the gem's `convert_abstract`): its title,
  /// then its paragraphs in the abstract's font, the first line of the
  /// first in the theme's first-line style.
  void _abstract(AbstractBlock node) {
    final children = _collect(() {
      if (node.title case final title? when title.isNotEmpty) {
        final font = _themeFont('abstract_title', _font);
        final lineHeight =
            (_n('heading_line_height') ?? _n('base_line_height') ?? 1)
                .toDouble();
        _out.add(
          CustomBox(
            _textBox(
              title,
              font.copyWith(lineHeight: lineHeight),
              align: _s('abstract_title_text_align') ?? _baseTextAlign,
            ),
            style: BoxStyle(
              margin: EdgeInsets(
                top: (_n('heading_margin_top') ?? 0).toDouble(),
                bottom: (_n('heading_margin_bottom') ?? 0).toDouble(),
              ),
            ),
          ),
        );
      }
      _withFont('abstract', () {
        final align = _s('abstract_text_align') ?? _baseTextAlign;
        _FontState? firstLine;
        final style = _s('abstract_first_line_font_style');
        if (style != null && style != _font.style) {
          final styles = <String>{
            if (style == 'normal_italic') 'italic',
            if (style != 'normal' && style != 'normal_italic') ...{
              ...PdfConverter._stylesOf(_font),
              ...PdfConverter._stylesOf(_font.copyWith(style: style)),
            },
          };
          firstLine = _font.copyWith(
            style: styles.contains('bold')
                ? styles.contains('italic')
                      ? 'bold_italic'
                      : 'bold'
                : styles.contains('italic')
                ? 'italic'
                : 'normal',
          );
        }
        if (_c('abstract_first_line_font_color') case final color?) {
          firstLine = (firstLine ?? _font).copyWith(color: color);
        }
        var transform = _s('abstract_first_line_text_transform');
        if (transform == 'none') transform = null;
        if (transform != null) firstLine ??= _font;
        if (node.blocks.isNotEmpty) {
          for (final child in node.blocks) {
            if (child case final Block block
                when block.context == BlockContext.paragraph) {
              _paragraph(
                block,
                textAlign: align,
                firstLine: firstLine,
                firstLineTransform: transform,
              );
              firstLine = null;
              transform = null;
            } else {
              child.convert();
            }
          }
        } else if (node case final Block block
            when block.contentModel != ContentModel.compound) {
          if (block.content() case final text?) {
            final textAlign = PdfConverter._alignOf(block.roles) ?? align;
            final indent = (textAlign == 'justify' || textAlign == 'left')
                ? (_n('prose_text_indent') ?? 0).toDouble()
                : 0.0;
            final box = _textBox(
              text,
              _font,
              align: textAlign,
              indent: indent,
              hyphenate: true,
            );
            _out.add(
              CustomBox(
                firstLine == null
                    ? box
                    : FirstLineTextBox(
                        _textBox(
                          text,
                          firstLine,
                          align: textAlign,
                          indent: indent,
                          singleLine: true,
                          hyphenate: true,
                        ),
                        box.state,
                        box.layout,
                        transform: transform,
                      ),
              ),
            );
          }
        }
      });
    });
    _out.add(
      BlockBox(
        children,
        style: BoxStyle(
          padding: _padding('abstract_padding'),
          margin: _outdented(EdgeInsets(bottom: _marginBelow(node))),
          anchor: node.id,
        ),
      ),
    );
  }

  /// Converts the example block [node].
  void convertExample(Block node) {
    // The modern engine styles a block with a role by the theme's
    // example_role_<role>_* keys, over its example_* keys.
    if (_withRoleKeys(node, 'example', () => _convertExample(node))) return;
    _convertExample(node);
  }

  /// Converts [node] with the theme's `<category>_role_<role>_*` keys over
  /// its `<category>_*` keys (and `<category>_role_<role>_link_*` over
  /// `link_*`), for each of its roles that has some (modern engine);
  /// whether it did.
  bool _withRoleKeys(Block node, String category, void Function() convert) {
    if (node.roles.isEmpty || asciidoctorCompat(_document, CompatFormat.pdf)) {
      return false;
    }
    final saved = _theme;
    for (final role in node.roles) {
      final prefix = '${category}_role_${role.replaceAll('-', '_')}_';
      // (Links in it too: `<category>_role_<role>_link_*`.)
      _theme = _theme
          .overlaid(prefix, '${category}_')
          .overlaid('${prefix}link_', 'link_');
    }
    if (identical(_theme, saved)) return false;
    // (Links styled by the role: inline styles from the overlaid keys.)
    final savedMarkup = _markup;
    final linked = node.roles.any((role) {
      final prefix = '${category}_role_${role.replaceAll('-', '_')}_link_';
      return saved.keys.any((key) => key.startsWith(prefix));
    });
    if (linked) {
      _markup = MarkupTransform(
        theme: _theme,
        invertEmphasis: _invertEmphasis,
        keepIndexSpace: true,
      );
    }
    try {
      convert();
    } finally {
      _theme = saved;
      _markup = savedMarkup;
    }
    return true;
  }

  void _convertExample(Block node) {
    if (node.hasOption('collapsible') &&
        _choice('example_collapsible', const ['frame', 'details']) ==
            'details') {
      _convertDetails(node);
      return;
    }
    final captionBelow = _s('example_caption_end') == 'bottom';
    if (!captionBelow && node.hasTitle) _caption(node, category: 'example');
    final children = _collect(
      () => _withFont('example', () => _traverse(node)),
    );
    if (!captionBelow) {
      _framed(node, 'example', children);
      return;
    }
    _out.add(
      BlockBox(
        children,
        style: BoxStyle(
          padding: _padding('example_padding'),
          keepTogether: node.hasOption('unbreakable'),
          anchor: node.id,
          decoration: _blockDecoration('example'),
        ),
      ),
    );
    if (node.hasTitle) _caption(node, category: 'example');
    final margin = _marginBelow(node);
    if (margin > 0) _out.add(SpacerBox(margin));
  }

  /// Converts the collapsible example block [node] as an open details
  /// element shows (`example_collapsible: details`): its title (else
  /// "Details") after a ▼, as a caption, over its content set in by the
  /// marker's width, with no frame.
  void _convertDetails(Block node) {
    const marker = '\u25bc ';
    final font = _themeFont('caption', _font);
    final indent = _fonts
        .font(font.family, font.style)
        .widthOf(marker, font.size, kerning: font.kerning);
    _out.add(
      _captionBox(
        node,
        labeled: false,
        title: '$marker${node.title ?? 'Details'}',
      ),
    );
    final children = _collect(() => _traverse(node));
    _out.add(
      BlockBox(
        children,
        style: BoxStyle(
          margin: EdgeInsets(left: indent),
          keepTogether: node.hasOption('unbreakable'),
          anchor: node.id,
        ),
      ),
    );
    final margin = _marginBelow(node);
    if (margin > 0) _out.add(SpacerBox(margin));
  }

  /// Converts the sidebar [node] (by the theme's `sidebar_role_<role>_*`
  /// keys for its roles, in the modern engine).
  void convertSidebar(Block node) {
    if (_withRoleKeys(node, 'sidebar', () => _convertSidebar(node))) return;
    _convertSidebar(node);
  }

  void _convertSidebar(Block node) {
    final children = _collect(() {
      if (node.title case final title? when title.isNotEmpty) {
        final font = _themeFont('sidebar_title', _font);
        final lineHeight =
            (_n('heading_line_height') ?? _n('base_line_height') ?? 1)
                .toDouble();
        var text = title;
        if (font.transform case final transform? when transform != 'none') {
          text = transformText(text, transform);
        }
        _out.add(
          CustomBox(
            _textBox(
              text,
              font.copyWith(lineHeight: lineHeight),
              align:
                  _s('sidebar_title_text_align') ??
                  _s('heading_text_align') ??
                  _baseTextAlign,
            ),
            style: BoxStyle(
              margin: EdgeInsets(
                // The modern engine: the title's own space below first.
                bottom:
                    ((_n('sidebar_title_margin_bottom')) ??
                            _n('heading_margin_bottom') ??
                            0)
                        .toDouble(),
              ),
            ),
          ),
        );
        // (The modern engine: a rule under it, `sidebar_title_rule_*`.)
        if (!asciidoctorCompat(_document, CompatFormat.pdf)) {
          if (_headingRule('sidebar_title') case final rule?) _out.add(rule);
        }
      }
      // (The modern engine: `sidebar_*` keys for the blocks inside it,
      // `sidebar_prose_margin_bottom`...)
      _withFont(
        'sidebar',
        () => _withBaseKeys('sidebar', () => _traverse(node)),
      );
    });
    _framed(node, 'sidebar', children);
  }

  /// Converts the quote or verse block [node] (with a role, by the
  /// theme's `quote_role_<role>_*` or `verse_role_<role>_*` keys over its
  /// `quote_*` or `verse_*` keys, modern engine).
  void convertQuote(Block node) {
    final key = node.context == BlockContext.quote ? 'quote' : 'verse';
    if (_withRoleKeys(node, key, () => _convertQuote(node))) return;
    _convertQuote(node);
  }

  void _convertQuote(Block node) {
    final category = node.context == BlockContext.quote ? 'quote' : 'verse';
    final leftWidth = (_n('${category}_border_left_width') ?? 0).toDouble();
    final leftColor = leftWidth > 0
        ? _c('${category}_border_color') ?? _c('base_border_color')
        : null;
    final hasLeft = leftWidth > 0 && pdfColorOf(leftColor) != null;
    String? escape(String? text) =>
        text?.replaceAllMapped(RegExp(r'&(?!#?\w+;)'), (_) => '&amp;');
    final attribution = escape(node.attr('attribution'));
    final citeTitle = attribution == null
        ? null
        : escape(node.attr('citetitle'));
    if (node.hasTitle) _caption(node, category: category);
    final children = _collect(() {
      _withFont(category, () {
        if (category == 'quote') {
          _withBaseKeys(category, () => _traverse(node));
        } else {
          _out.add(
            CustomBox(
              _textBox(
                PdfConverter._guardIndentation(node.content() ?? ''),
                _font,
                align: PdfConverter._alignOf(node.roles) ?? 'left',
                normalize: false,
                hyphenate: true,
              ),
            ),
          );
        }
      });
      if (attribution != null) {
        // The modern engine's `<category>_cite_margin_top` and
        // `<category>_cite_text_align`; the gem's block margin, at the left.
        final margin =
            _length('${category}_cite_margin_top', _font.size) ??
            (_n('block_margin_bottom') ?? 0).toDouble();
        if (margin > 0) _out.add(SpacerBox(margin));
        _withFont('${category}_cite', () {
          final parts = [attribution, ?citeTitle].join(', ');
          _out.add(
            CustomBox(
              _textBox(
                '— $parts',
                _font,
                align: (_s('${category}_cite_text_align')) ?? 'left',
                normalize: false,
              ),
            ),
          );
        });
      }
    });
    _framed(
      node,
      category,
      children,
      noBorder: hasLeft,
      extra: hasLeft
          ? (page, rect, {required first, required last}) {
              page.canvas
                ..save()
                ..setStrokeColor(pdfColorOf(leftColor)!)
                ..setLineWidth(leftWidth)
                ..moveTo(rect.left + leftWidth * 0.5, rect.top)
                ..lineTo(rect.left + leftWidth * 0.5, rect.bottom)
                ..stroke()
                ..restore();
            }
          : null,
    );
  }

  /// Converts the thematic break [node].
  void convertThematicBreak(Block node) {
    final padding = _edgeValues(
      _theme.value('thematic_break_padding') ??
          ThemeList([
            ThemeNumber(_n('thematic_break_margin_top') ?? 0),
            const ThemeNumber(0),
          ]),
    );
    final color = pdfColorOf(_c('thematic_break_border_color'));
    final width = (_n('thematic_break_border_width') ?? 0.5).toDouble();
    final style = _s('thematic_break_border_style') ?? 'solid';
    _out.add(
      BlockBox(
        const [],
        style: BoxStyle(
          padding: EdgeInsets(
            top: padding[0],
            right: padding[1],
            bottom: padding[2],
            left: padding[3],
          ),
          margin: EdgeInsets(bottom: _marginBelow(node)),
          decoration: color == null
              ? null
              : (page, rect, {required first, required last}) {
                  final y = rect.top - padding[0];
                  final left = rect.left + padding[3];
                  final right = rect.right - padding[1];
                  final canvas = page.canvas
                    ..save()
                    ..setStrokeColor(color);
                  void rule(double at, double lineWidth) => canvas
                    ..setLineWidth(lineWidth)
                    ..moveTo(left, at)
                    ..lineTo(right, at)
                    ..stroke();
                  if (style == 'double') {
                    final single = width / 3;
                    rule(y + single, single);
                    rule(y - single, single);
                  } else {
                    if (style == 'dashed') canvas.dash([width * 4]);
                    if (style == 'dotted') canvas.dash([width]);
                    rule(y, width);
                  }
                  canvas.restore();
                },
        ),
      ),
    );
  }

  /// Converts the page break [node].
  void convertPageBreak(Block node) {
    const layouts = {'portrait', 'landscape'};
    var layout = node.attr('page-layout');
    if (layout == null || layout.isEmpty) {
      layout = node.roles.where(layouts.contains).lastOrNull;
    } else if (!layouts.contains(layout)) {
      layout = null;
    }
    if (_inColumns && node.hasRole('column') && layout == null) {
      _out.add(BreakBox.column(force: node.hasOption('always')));
      return;
    }
    if (layout != null) _layout = layout;
    _out.add(BreakBox.page(template: layout, force: node.hasOption('always')));
  }

  /// Adds [page] as a page of the document, in place of the current page
  /// when nothing is on it, with [anchor] at its top; with [advance], the
  /// content after it starts a new page in the current layout (the gem's
  /// `import_page`). An imported page has no running content.
  void _importPage(ImportedPage page, {String? anchor, bool advance = true}) {
    final key = 'pdf-page-${_importedPages.length + 1}';
    _importedPages[key] = page;
    _out
      ..add(BreakBox.page(template: key))
      ..add(
        CustomBox(
          _Absolute((_) {}, fill: true),
          style: BoxStyle(anchor: anchor),
        ),
      );
    if (advance) _out.add(BreakBox.page(template: _layout));
  }

  /// The pages of the PDF file at [path] (referred to as [target]), or
  /// null (with a warning) when it isn't a PDF file Ptome can read.
  List<ImportedPage>? _pdfPages(String path, String target) {
    try {
      return PdfFile.parse(Uint8List.fromList(io.readBytes(path))).pages;
    } on PdfFormatException catch (error) {
      logger.warn('could not insert pdf: $target; ${error.message}');
      return null;
    }
  }

  /// Inserts the pages of the PDF file the block image [node] refers to
  /// by [target] (its `page`, or its `pages`: numbers and ranges); false
  /// when there's no such file.
  bool _insertPdf(Block node, String target) {
    final path = Helpers.isUriish(target) ? null : _imagePath(node, target);
    if (path == null || !io.isFile(path) || !io.isReadable(path)) {
      logger.warn('pdf to insert not found or not readable: ${path ?? target}');
      return false;
    }
    final pages = _pdfPages(path, target) ?? const [];
    final numbers = switch (node.attr('pages')) {
      final value? => [
        for (final entry in value.split(value.contains(',') ? ',' : ';'))
          if (entry.contains('..'))
            for (
              var n = math.max(
                PdfConverter._rubyInt(entry.split('..').first),
                1,
              );
              n <=
                  math.max(
                    PdfConverter._rubyInt(entry.split('..').skip(1).join('..')),
                    1,
                  );
              n++
            )
              n
          else
            PdfConverter._rubyInt(entry),
      ],
      null => [math.max(PdfConverter._rubyInt(node.attr('page') ?? '1'), 1)],
    };
    for (final (i, number) in numbers.indexed) {
      if (pages.elementAtOrNull(number - 1) case final page? when number > 0) {
        _importPage(page, anchor: i == 0 ? node.id : null);
      } else {
        _out.add(BreakBox.page(template: _layout));
      }
    }
    return true;
  }

  /// The page's content width, or [_columnWidth] in columns: what a
  /// block floating to a side takes a share of.
  double get _floatRoom =>
      _columnWidth ??
      _pageSize(_document).$1 - _pageMargins(_document).horizontal;

  /// The width of [count] columns [gap] apart across the page's content.
  double _columnWidthOf(int count, double gap) =>
      (_pageSize(_document).$1 -
          _pageMargins(_document).horizontal -
          gap * (count - 1)) /
      count;
}
