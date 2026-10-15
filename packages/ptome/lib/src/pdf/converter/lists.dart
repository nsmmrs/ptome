part of '../converter.dart';

// Lists.

extension _Lists on PdfConverter {
  /// Converts the unordered list [node].
  void convertUlist(ListBlock node) {
    if (node.includesRole('braces') &&
        !asciidoctorCompat(_document, CompatFormat.pdf)) {
      _bracesList(node);
      return;
    }
    String? bullet;
    if (node.hasOption('checklist')) {
      bullet = 'checkbox';
    } else if (node.style case final style?) {
      bullet = switch (style) {
        'bibliography' => 'square',
        'unstyled' || 'no-bullet' => null,
        'disc' || 'circle' || 'square' || 'none' => style,
        _ => () {
          logger.warn('unknown unordered list style: $style');
          return 'disc';
        }(),
      };
    } else {
      // (`ulist_marker_nesting: ulist`, modern engine: the level among
      // unordered lists alone.)
      final own =
          _choice('ulist_marker_nesting', const ['all', 'ulist']) == 'ulist';
      bullet = switch (_listLevel(
        node,
        only: own ? BlockContext.ulist : null,
      )) {
        1 => 'disc',
        2 => 'circle',
        _ => 'square',
      };
    }
    _listBullets.add(bullet);
    _list(node);
    _listBullets.removeLast();
  }

  /// Adds the list [node] set as a tree of braces (Ptome's `braces` role,
  /// modern engine), as the synopses of Burton's Anatomy of Melancholy
  /// are printed: each item's text, then a brace to its right spanning
  /// its sublist, whose items stand one under another beyond it, the text
  /// level with the brace's point. In the `list_braces` font (the list's
  /// by default); `list_braces_width` (half an em) the brace's width,
  /// `list_braces_gap` (a quarter em) the space on each side of it,
  /// `list_braces_item_spacing` (none) the space between items,
  /// `list_braces_text_max_width` (`35%`) the most of the room an item's
  /// text with branches takes, `list_braces_line_width` (0.5) and
  /// `list_braces_color` (the text's) the brace's stroke. The items'
  /// other blocks are left out. Each tree is kept whole on a page; one
  /// taller than a page is split between its branches.
  void _bracesList(ListBlock node) {
    if (node.hasTitle) _caption(node, category: 'list', labeled: false);
    final font = _themeFont('list_braces', _font);
    _BraceNode branch(ListItem item) {
      final text = item.text;
      return _BraceNode(
        text == null || text.isEmpty
            ? null
            : _textBox(
                text,
                font,
                align: 'left',
                normalizeLineHeight: true,
                hyphenate: true,
              ),
        [
          for (final block in item.blocks)
            if (block case final ListBlock list
                when list.context == BlockContext.ulist ||
                    list.context == BlockContext.olist)
              for (final child in list.items) branch(child),
        ],
      );
    }

    final maxWidth = _s('list_braces_text_max_width') ?? '35%';
    _out.add(
      CustomBox(
        _BraceTree(
          [for (final item in node.items) branch(item)],
          braceWidth: _length('list_braces_width', font.size) ?? font.size / 2,
          gap: _length('list_braces_gap', font.size) ?? font.size / 4,
          spacing: _length('list_braces_item_spacing', font.size) ?? 0,
          textShare: maxWidth.endsWith('%')
              ? (double.tryParse(maxWidth.replaceAll('%', '')) ?? 35) / 100
              : (double.tryParse(maxWidth) ?? 0.35),
          lineWidth: (_n('list_braces_line_width') ?? 0.5).toDouble(),
          color: pdfColorOf(_c('list_braces_color') ?? font.color),
        ),
        style: BoxStyle(
          margin: _mirrorInsets(
            EdgeInsets(
              bottom: node.parent is ListItem
                  ? 0
                  : _marginBelow(node, fallback: 'prose'),
            ),
          ),
          anchor: node.id,
          structure: _struct('Div'),
        ),
      ),
    );
  }

  /// Converts the ordered list [node].
  void convertOlist(ListBlock node) {
    // The modern engine styles an ordered list with a role by the theme's
    // olist_role_<role>_* keys, over its olist_* keys.
    if (node.roles.isNotEmpty) {
      final saved = _theme;
      for (final role in node.roles) {
        _theme = _theme.overlaid(
          'olist_role_${role.replaceAll('-', '_')}_',
          'olist_',
        );
      }
      if (!identical(_theme, saved)) {
        try {
          _convertOlist(node);
        } finally {
          _theme = saved;
        }
        return;
      }
    }
    _convertOlist(node);
  }

  void _convertOlist(ListBlock node) {
    // (A counter style Asciidoctor doesn't know, or the language's
    // numerals: Ptome's.)
    final counter = asciidoctorCompat(_document, CompatFormat.pdf)
        ? null
        : listCounterStyle(node);
    var numeral = switch (node.style) {
      _ when counter != null => _Numeral.counter(counter, 1),
      'loweralpha' => const _Numeral.letters('a'),
      'upperalpha' => const _Numeral.letters('A'),
      'lowerroman' => const _Numeral.roman(1, upper: false),
      'upperroman' => const _Numeral.roman(1, upper: true),
      'lowergreek' => const _Numeral.letters('\u03b1'),
      'unstyled' || 'unnumbered' || 'no-bullet' => null,
      'none' => const _Numeral.none(),
      _ => const _Numeral.decimal(1),
    };
    final start =
        node.attr('start') ??
        (node.hasOption('reversed') ? '${node.items.length}' : null);
    if (numeral case final first?
        when first.kind != _NumeralKind.none && start != null) {
      final value = int.tryParse(start.trim()) ?? 0;
      var current = first;
      if (value > 1) {
        for (var i = 0; i < value - 1; i++) {
          current = current.next;
        }
      } else if (value < 1 && current.kind != _NumeralKind.letters) {
        for (var i = 0; i < (value - 1).abs(); i++) {
          current = current.previous;
        }
      }
      numeral = current;
    }
    _listNumerals.add(numeral);
    _list(node);
    _listNumerals.removeLast();
  }

  /// [node]'s nesting among lists (among lists of context [only]).
  int _listLevel(ListBlock node, {BlockContext? only}) {
    var level = 1;
    var ancestor = node.parent;
    while (ancestor != null) {
      if (ancestor case ListBlock(:final context)
          when only == null
              ? context == BlockContext.ulist || context == BlockContext.olist
              : context == only) {
        level++;
      }
      ancestor = ancestor.parent;
    }
    return level;
  }

  void _list(ListBlock node) {
    if (node.hasTitle) _caption(node, category: 'list', labeled: false);
    String? align;
    for (final role in node.roles) {
      if (role.startsWith('text-') &&
          const {
            'justify',
            'left',
            'center',
            'right',
          }.contains(role.substring(5))) {
        align = role.substring(5);
      }
    }
    if (align == null && node.style == 'bibliography') align = 'left';
    // (An ordered list's own, `olist_text_align`, in the modern engine.)
    if (node.context == BlockContext.olist) {
      align ??= _s('olist_text_align');
    }
    align ??= _s('list_text_align');
    final unmarked =
        (node.context == BlockContext.ulist && _listBullets.last == null) ||
        (node.context == BlockContext.olist && _listNumerals.last == null);
    var indent = _length('list_indent', _font.size) ?? 0;
    if (unmarked) {
      if (node.style == 'unstyled') {
        indent = 0;
      } else if (indent > 0) {
        final font = _fonts.font(_font.family, _font.style);
        final sample = node.context == BlockContext.ulist ? '\u2022x' : '1.x';
        indent = math.max(indent - font.widthOf(sample, _font.size), 0);
      }
    }
    final saved = _out;
    final items = <LayoutBox>[];
    _out = items;
    // The modern engine's list_body_indent: the markers at list_indent,
    // the text after the widest marker and the body indent. An ordered
    // list's own (`olist_body_indent`; `olist_marker_width`, its numbers
    // in boxes that wide at their left).
    final ordered = node.context == BlockContext.olist;
    final bodyIndent =
        (ordered ? _length('olist_body_indent', _font.size) : null) ??
        _length('list_body_indent', _font.size);
    final savedBodyIndent = _listBodyIndent;
    final savedMarkerWidth = _listMarkerWidth;
    final savedMarkerBox = _listMarkerBox;
    _listBodyIndent = bodyIndent;
    _listMarkerWidth = 0;
    _listMarkerBox = ordered ? _length('olist_marker_width', _font.size) : null;
    for (final item in node.items) {
      _listItem(item, node, align);
    }
    if (bodyIndent != null && !unmarked) {
      indent += _listMarkerWidth + bodyIndent;
    }
    _listBodyIndent = savedBodyIndent;
    _listMarkerWidth = savedMarkerWidth;
    _listMarkerBox = savedMarkerBox;
    _out = saved;
    final nested = node.parent is ListItem;
    _out.add(
      BlockBox(
        items,
        style: BoxStyle(
          margin: _mirrorInsets(
            EdgeInsets(
              left: indent,
              bottom: nested ? 0 : _marginBelow(node, fallback: 'prose'),
            ),
          ),
          anchor: node.id,
          structure: _struct('L'),
        ),
      ),
    );
  }

  void _listItem(ListItem item, ListBlock list, String? align) {
    String? marker;
    var markerFamily = _font.family;
    var markerSize = _font.size;
    var markerStyle = _font.style;
    var markerColor = _c('list_marker_font_color') ?? _font.color;
    var markerLineHeight = _font.lineHeight;
    // The modern engine's `<prefix>_font_variant_numeric` (old-style
    // figures for an ordered list's numbers).
    final markerFeatures = <String>{};
    void styleFrom(String prefix) {
      if (fontFeature(_keys(prefix).string('font_variant_numeric'))
          case final f?) {
        markerFeatures.add(f);
      }

      markerColor = _keys(prefix).color('font_color') ?? markerColor;
      markerFamily = _keys(prefix).string('font_family') ?? markerFamily;
      markerSize = (_keys(prefix).number('font_size') ?? markerSize).toDouble();
      markerStyle =
          PdfConverter._fontStyle(_keys(prefix).string('font_style')) ??
          markerStyle;
      markerLineHeight =
          (_keys(prefix).number('line_height') ?? markerLineHeight).toDouble();
    }

    if (list.context == BlockContext.olist) {
      final index = _listNumerals.removeLast();
      if (index != null) {
        if (index.kind == _NumeralKind.none) {
          marker = '';
          _listNumerals.add(index);
        } else {
          marker =
              list.style == 'decimal' &&
                  index.kind == _NumeralKind.decimal &&
                  index.value.abs() < 10
              ? '${index.value < 0 ? '-' : ''}0${index.value.abs()}.'
              : index.marker;
          _listNumerals.add(
            list.hasOption('reversed') ? index.previous : index.next,
          );
          styleFrom('olist_marker');
        }
      } else {
        _listNumerals.add(null);
      }
    } else if (_listBullets.last case final bullet?) {
      var type = bullet;
      if (bullet == 'checkbox') {
        if (item.hasAttr('checkbox')) {
          type = item.hasAttr('checked') ? 'checked' : 'unchecked';
          marker =
              _keys('ulist_marker_$type').string('content') ??
              (type == 'checked' ? '\u2611' : '\u2610');
        }
      } else {
        marker =
            _keys('ulist_marker_$type').string('content') ??
            switch (type) {
              'disc' => '\u2022',
              'circle' => '\u25e6',
              'square' => '\u25aa',
              _ => '',
            };
      }
      if (marker != null) {
        // Theme keys of the marker type win over the generic ones.
        styleFrom('ulist_marker');
        styleFrom('ulist_marker_$type');
      }
    }

    double? marginBottom = 0;
    if (item.isCompound) {
      marginBottom = null;
    } else if (_nextEnclosedBlockDescending(item) != null) {
      marginBottom = _length('list_item_spacing', _font.size) ?? 0;
    }
    final text = item.text;
    final primary = text == null || text.isEmpty
        ? (item.blocks.isEmpty ? _dummyText : null)
        : text;
    final children = <LayoutBox>[];
    final saved = _out;
    _out = children;
    final markerFont = _FontState(
      family: markerFamily,
      style: markerStyle,
      size: markerSize,
      color: markerColor,
      lineHeight: markerLineHeight,
      kerning: _font.kerning,
    );
    if (primary == null && marker != null && marker.isNotEmpty) {
      // No text: the marker is where the first block starts (the gem
      // floats it at the cursor).
      children.add(
        CustomBox(
          _withMarker(
            const _Nothing(),
            marker,
            markerFont,
            features: markerFeatures,
          ),
        ),
      );
    }
    if (primary != null) {
      // The modern engine keeps an item's text from leaving a lone line on
      // either side of a page break, as a paragraph's (`prose_orphans`,
      // `prose_widows`).
      final box = _textBox(
        primary,
        _font,
        align: align ?? _baseTextAlign,
        normalizeLineHeight: true,
        hyphenate: true,
        orphans: (_n('prose_orphans') ?? 2).toInt(),
        widows: (_n('prose_widows') ?? 2).toInt(),
      );
      final metrics = _lineMetrics(_font);
      final lineHeight = _font.lineHeight * _font.size;
      CustomContent content = _MinRoom(
        box,
        // (With lines set from their cap heights, a line is as tall as its
        // cap height.)
        _capLeading(_font) != null
            ? _fonts.font(_font.family, _font.style).capHeightAt(_font.size)
            : lineHeight + metrics.leading + metrics.paddingTop,
      );
      if (marker != null && marker.isNotEmpty) {
        content = _withMarker(
          content,
          marker,
          markerFont,
          features: markerFeatures,
        );
      }
      children.add(
        CustomBox(
          content,
          style: BoxStyle(
            margin: _mirrorInsets(
              EdgeInsets(
                bottom:
                    marginBottom ?? (_n('prose_margin_bottom') ?? 0).toDouble(),
              ),
            ),
          ),
        ),
      );
    }
    _traverse(item);
    _out = saved;
    _out.add(
      BlockBox(
        // (Tagged, the item's content its body, as a list item's holds
        // its label and its body alone.)
        _pdfUa
            ? [BlockBox(children, style: BoxStyle(structure: _struct('LBody')))]
            : children,
        style: BoxStyle(anchor: item.id, structure: _struct('LI')),
      ),
    );
  }

  /// Converts the description list [node].
  void convertDlist(ListBlock node) {
    switch (node.style) {
      case 'horizontal':
        _horizontalDlist(node);
      case 'qanda':
        _qanda(node);
      case 'unordered' || 'ordered':
        _dlistAsList(node, ordered: node.style == 'ordered');
      default:
        _withBaseKeys('description_list', () => _dlist(node));
    }
  }

  /// Runs [body] with the modern engine's `<category>_*` keys in place of
  /// the theme's (`quote_base_justify_width: widest`: a block sized to
  /// its content justifies its lines to the widest; `quote_list_*`
  /// for the lists in a quote), as a section role's.
  void _withBaseKeys(String category, void Function() body) {
    final savedAlign = _baseTextAlign;
    final savedTheme = _theme;
    _theme = _theme.overlaid('${category}_', '');
    if (_keys(category).string('base_text_align') case final align?) {
      _baseTextAlign = align;
    }
    try {
      body();
    } finally {
      _baseTextAlign = savedAlign;
      _theme = savedTheme;
    }
  }

  /// The height of a line of text in [font] (the gem's
  /// `height_of_typeset_text`).
  double _typesetHeight(_FontState font) => _textBox(
    'A',
    font,
    align: 'left',
  ).place(1000000, double.infinity, atTop: true)!.height;

  /// The text of the description list term [term] in [font].
  TextBox _term(ListItem term, _FontState font) {
    var text = term.text ?? '';
    if (font.transform case final transform? when transform != 'none') {
      text = transformText(text, transform, language: _language);
    }
    return _textBox(
      text,
      font,
      align: 'left',
      normalizeLineHeight: true,
      inheritedStyles: PdfConverter._stylesOf(font),
    );
  }

  /// Adds the description [desc] of a description list entry: its text,
  /// then its blocks (the gem's `traverse_list_item` for descriptions).
  void _description(ListItem desc) {
    final marginBottom = _nextEnclosedBlockDescending(desc) == null
        ? 0.0
        : (_n('prose_margin_bottom') ?? 0).toDouble();
    final text = desc.text;
    final primary = text == null || text.isEmpty
        ? (desc.blocks.isEmpty ? _dummyText : null)
        : text;
    if (primary != null) {
      final shared = _continuedIndent(primary, _font);
      final text = _textBox(
        primary,
        _font,
        align: _baseTextAlign,
        indent: shared ?? 0,
        normalizeLineHeight: true,
        hyphenate: true,
      );
      _out.add(
        CustomBox(
          shared == null ? text : text.continuing(),
          style: BoxStyle(
            margin: _mirrorInsets(EdgeInsets(bottom: marginBottom)),
          ),
        ),
      );
    }
    _traverse(desc);
  }

  void _dlist(ListBlock node) {
    final boxes = _collect(() {
      if (node.hasTitle) {
        _caption(node, category: 'description_list', labeled: false);
      }
      final termSpacing = (_n('description_list_term_spacing') ?? 0).toDouble();
      final termFont = _themeFont('description_list_term', _font);
      final termHeight = _typesetHeight(termFont);
      final proseHeight = _typesetHeight(_font);
      final indent =
          _length('description_list_description_indent', _font.size) ?? 0;
      // `description_list_term_display: inline` (modern engine): a term
      // run in before its description, the lines after the first hanging
      // by the description indent.
      final runIn =
          _choice('description_list_term_display', const ['block', 'inline']) ==
          'inline';
      for (final DlistEntry(:terms, description: desc) in node.entries) {
        final hasText = desc != null && desc.hasText;
        if (runIn && hasText && terms.length == 1) {
          _runInEntry(
            terms.single,
            desc,
            termFont,
            indent,
            last: identical(node.entries.last.description, desc),
          );
          continue;
        }
        final lines = terms.length + (hasText ? 1 : 0);
        final need =
            lines * termHeight +
            (lines - 1) * termSpacing +
            (desc != null && !hasText && desc.blocks.isNotEmpty
                ? termSpacing + proseHeight
                : 0);
        for (final (i, term) in terms.indexed) {
          final box = _term(term, termFont);
          _out.add(
            CustomBox(
              i == 0 ? _MinRoom(box, need) : box,
              style: BoxStyle(
                margin: _mirrorInsets(EdgeInsets(top: i > 0 ? termSpacing : 0)),
                // (`line_numbers_skip_terms`: a play's speakers' names
                // aren't counted.)
                unnumbered:
                    _theme.value('line_numbers_skip_terms') ==
                    const ThemeBool(true),
              ),
            ),
          );
        }
        if (desc == null) continue;
        final children = _collect(() {
          if (termSpacing > 0) _out.add(SpacerBox(termSpacing));
          _description(desc);
        });
        _out.add(
          BlockBox(
            children,
            style: BoxStyle(margin: _mirrorInsets(EdgeInsets(left: indent))),
          ),
        );
      }
    });
    _out.add(
      BlockBox(
        boxes,
        style: BoxStyle(
          margin: _mirrorInsets(
            EdgeInsets(
              bottom: node.parent is ListItem
                  ? 0
                  : _marginBelow(node, fallback: 'prose'),
            ),
          ),
          anchor: node.id,
        ),
      ),
    );
  }

  /// Adds a description list entry with its [term] run in before its
  /// description [desc]: one paragraph whose lines after the first hang
  /// by [hang], then the description's blocks, as far in.
  void _runInEntry(
    ListItem term,
    ListItem desc,
    _FontState termFont,
    double hang, {
    bool last = false,
  }) {
    // (`description_list_term_suffix`: after the term, as the colon of a
    // Federal Register caption, `AGENCY:`.)
    var text = '${term.text ?? ''}${_s('description_list_term_suffix') ?? ''}';
    if (termFont.transform case final transform? when transform != 'none') {
      text = transformText(text, transform, language: _language);
    }
    final styles = PdfConverter._stylesOf(termFont);
    if (styles.contains('italic')) text = '<em>$text</em>';
    if (styles.contains('bold')) text = '<strong>$text</strong>';
    if (termFont.family != _font.family) {
      text = '<font name="${termFont.family}">$text</font>';
    }
    final blocks = _collect(() => _traverse(desc));
    // The space after the term: an en space, or as wide as
    // `description_list_term_gap`. (A space, where the line may break.)
    final gap = switch (_theme.value('description_list_term_gap')) {
      ThemeNumber(:final value) => '<font width="$value"> </font>',
      ThemeString(:final value) => '<font width="$value"> </font>',
      _ => '&#8194;',
    };
    _out.add(
      CustomBox(
        _textBox(
          '$text$gap${desc.text}',
          _font,
          align: _baseTextAlign,
          // (`description_list_term_indent`: the term set in from the
          // lines after it, as the First Folio sets a speech's prefix.)
          indent:
              -hang +
              (_length('description_list_term_indent', _font.size) ?? 0),
          normalizeLineHeight: true,
          hyphenate: true,
          // (Kept from leaving a lone line at a page break, as a
          // paragraph.)
          orphans: (_n('prose_orphans') ?? 2).toInt(),
          widows: (_n('prose_widows') ?? 2).toInt(),
        ),
        style: BoxStyle(
          margin: _mirrorInsets(
            EdgeInsets(
              left: hang,
              bottom: blocks.isEmpty
                  ? 0
                  : (_n('prose_margin_bottom') ?? 0).toDouble(),
            ),
          ),
        ),
      ),
    );
    if (blocks.isNotEmpty) {
      _out.add(
        BlockBox(
          blocks,
          style: BoxStyle(margin: _mirrorInsets(EdgeInsets(left: hang))),
        ),
      );
    }
    // The entries apart as paragraphs (the paragraph spacing between
    // items), or as `description_list_item_spacing` says
    // (a tight list: the leading).
    if (!last) {
      final spacing =
          _length('description_list_item_spacing', _font.size) ??
          (_n('prose_margin_bottom') ?? 0).toDouble();
      if (spacing > 0) _out.add(SpacerBox(spacing));
    }
  }

  /// A description list with its terms in a column beside the
  /// descriptions.
  void _horizontalDlist(ListBlock node) {
    final boxes = _collect(() {
      if (node.hasTitle) {
        _caption(node, category: 'description_list', labeled: false);
      }
      final termFont = _themeFont('description_list_term', _font);
      final termHeight = _typesetHeight(termFont);
      final proseHeight = _typesetHeight(_font);
      final termSpacing = (_n('description_list_term_spacing') ?? 0).toDouble();
      const termLeft = 10.0;
      const termRight = 10.0;
      const descLeft = 10.0;
      const descRight = 10.0;
      // The widest term as it is set (its bold and italic words too).
      var widest = 0.0;
      for (final entry in node.entries) {
        for (final term in entry.terms) {
          widest = math.max(widest, _term(term, termFont).intrinsicWidths().$2);
        }
      }
      final rows = <TableRow>[];
      for (final DlistEntry(:terms, description: desc) in node.entries) {
        final need = math.max(
          (termSpacing + termHeight) * terms.length - termSpacing,
          desc != null ? proseHeight : 0.0,
        );
        final termBoxes = [
          for (final (i, term) in terms.indexed)
            CustomBox(
              i == 0
                  ? _MinRoom(_term(term, termFont), need)
                  : _term(term, termFont),
              style: BoxStyle(
                margin: _mirrorInsets(EdgeInsets(top: i > 0 ? termSpacing : 0)),
              ),
            ),
        ];
        rows.add(
          TableRow([
            TableCell(termBoxes, padding: const EdgeInsets(left: termLeft)),
            TableCell(
              desc == null ? const [] : _collect(() => _description(desc)),
              padding: const EdgeInsets(left: descLeft, right: descRight),
            ),
          ]),
        );
      }
      final termWidth = widest + termLeft + termRight;
      _out.add(
        TableBox(
          rows,
          columns: [
            ColumnWidth.computed(
              (width) =>
                  math.min(termWidth, width * 0.5 - termLeft - termRight),
            ),
            const ColumnWidth.fraction(1),
          ],
        ),
      );
    });
    _out.add(
      BlockBox(
        boxes,
        style: BoxStyle(
          margin: _mirrorInsets(
            EdgeInsets(
              bottom: node.parent is ListItem
                  ? 0
                  : _marginBelow(node, fallback: 'prose'),
            ),
          ),
          anchor: node.id,
        ),
      ),
    );
  }

  /// The glyph of callout [number] (empty when the theme has none). In
  /// the modern engine, `conum_glyphs` may be a text with `%d` for the
  /// number (`[%d]`), and a callout list's markers have their own
  /// (`callout_list_marker_content`: `%d.`).
  String _conumGlyph(int number, {bool list = false}) {
    if (_conumTemplate(list: list) case final template?) {
      return _render(template, {'number': '$number'});
    }
    return number >= 1 && number <= _conumGlyphs.length
        ? _conumGlyphs[number - 1]
        : '';
  }

  /// The template of callout markers (or of a callout list's markers,
  /// with [list]) in the modern engine (ADR-0010): `conum_glyphs` (or
  /// `callout_list_marker_content`) with `{{number}}`.
  String? _conumTemplate({bool list = false}) {
    final template =
        (list ? _s('callout_list_marker_content') : null) ?? _s('conum_glyphs');
    return template != null && template.contains('{{') ? template : null;
  }

  /// Converts the callout list [node].
  void convertColist(ListBlock node) {
    final previous = _previousSibling(node)?.context;
    final marginTop =
        previous == BlockContext.listing || previous == BlockContext.literal
        ? (_n('callout_list_margin_top_after_code') ?? 0).toDouble()
        : 0.0;
    final spacing =
        _length('callout_list_item_spacing', _font.size) ??
        _length('list_item_spacing', _font.size) ??
        0;
    final align =
        PdfConverter._alignOf(node.roles) ??
        (_s('callout_list_text_align')) ??
        _s('list_text_align');
    final items = _collect(() {
      _withFont('callout_list', () {
        final conumFont = _themeFont('conum', _font);
        final metrics = _lineMetrics(conumFont);
        final minRoom =
            conumFont.lineHeight * conumFont.size +
            metrics.leading +
            metrics.paddingTop;
        // The modern engine's `callout_list_marker_*` font keys, over the
        // conum's.
        final markerFont = _themeFont('callout_list_marker', conumFont);
        final markerFeatures = {
          ?fontFeature(_s('callout_list_marker_font_variant_numeric')),
        };
        final prawnFont = _fonts.font(conumFont.family, conumFont.style);
        // A marker box as wide as `callout_list_marker_width` (modern
        // engine), its marker
        // aligned in it by `callout_list_marker_text_align`.
        final fixedWidth = _length(
          'callout_list_marker_width',
          markerFont.size,
        );
        final markerAlign = _s('callout_list_marker_text_align') ?? 'center';
        for (final (i, item) in node.items.indexed) {
          final glyph = _conumGlyph(i + 1, list: true);
          final markerWidth =
              fixedWidth ??
              prawnFont.widthOf(
                '${glyph}x',
                conumFont.size,
                kerning: conumFont.kerning,
              );
          // In the modern engine, the item is the destination of its
          // markers, and its glyph links back to the first.
          final coids = (item.attr('coids') ?? '')
              .split(' ')
              .where((id) => id.isNotEmpty)
              .toList();
          var markerMarkup = glyph
              .replaceAll('&', '&amp;')
              .replaceAll('<', '&lt;');
          if (coids.isNotEmpty) {
            if (markerFont.color case final color?) {
              markerMarkup =
                  '<font color="${color.rubyString}">$markerMarkup</font>';
            }
            markerMarkup = '<a anchor="${coids.first}">$markerMarkup</a>';
          }
          final marker = _textBox(
            markerMarkup,
            markerFont,
            align: markerAlign,
            normalize: false,
            features: markerFeatures,
          );
          final last = i == node.items.length - 1;
          final text = item.text;
          var primary = text == null || text.isEmpty
              ? (item.blocks.isEmpty ? _dummyText : null)
              : text;
          // (An item of blocks alone is the destination of its first
          // marker only.)
          if (primary != null && coids.isNotEmpty) {
            final destinations = [
              for (final id in coids)
                '<a id="${PdfConverter._calloutItem(id)}">$_dummyText</a>',
            ];
            primary = '${destinations.join()}$primary';
          }
          final children = _collect(() {
            if (primary != null) {
              final box = _textBox(
                primary,
                _font,
                align: align ?? _baseTextAlign,
                normalizeLineHeight: true,
                hyphenate: true,
                // (No lone line at a page break, as a paragraph's.)
                orphans: (_n('prose_orphans') ?? 2).toInt(),
                widows: (_n('prose_widows') ?? 2).toInt(),
              );
              _out.add(
                CustomBox(
                  _MinRoom(
                    _Marked(
                      box,
                      marker,
                      markerWidth,
                      -markerWidth,
                      mirrored: _rightToLeft,
                    ),
                    // (With lines set from their cap heights, a line is as
                    // tall as its cap height.)
                    _capLeading(_font) != null
                        ? _fonts
                              .font(_font.family, _font.style)
                              .capHeightAt(_font.size)
                        : minRoom,
                  ),
                  style: BoxStyle(
                    margin: _mirrorInsets(
                      EdgeInsets(bottom: last ? 0 : spacing),
                    ),
                  ),
                ),
              );
            }
            _traverse(item);
          });
          _out.add(
            BlockBox(
              children,
              style: BoxStyle(
                margin: _mirrorInsets(EdgeInsets(left: markerWidth)),
                anchor:
                    item.id ??
                    (primary == null && coids.isNotEmpty
                        ? PdfConverter._calloutItem(coids.first)
                        : null),
              ),
            ),
          );
        }
      });
    });
    _out.add(
      BlockBox(
        items,
        style: BoxStyle(
          margin: _mirrorInsets(
            EdgeInsets(
              top: marginTop,
              bottom: _marginBelow(node, fallback: 'prose'),
              // (`callout_list_indent`, modern engine.)
              left: _length('callout_list_indent', _font.size) ?? 0,
            ),
          ),
          anchor: node.id,
        ),
      ),
    );
  }

  /// [content] with [marker] in [markerFont] beside its first line, right
  /// aligned in front of it, a space apart.
  CustomContent _withMarker(
    CustomContent content,
    String marker,
    _FontState markerFont, {
    Set<String> features = const {},
  }) {
    final gap = _fonts.font(_font.family, _font.style).widthOf('x', _font.size);
    final fixed = _listMarkerBox;
    final markerBox = _textBox(
      marker.replaceAll('&', '&amp;').replaceAll('<', '&lt;'),
      markerFont,
      align: fixed == null ? 'right' : 'left',
      normalize: false,
      // (The gem's tighter marker; not with `list_body_indent`.)
      characterSpacing: fixed == null && _listBodyIndent == null ? -0.5 : 0,
      features: features,
      // (A marker set at the end of its box doesn't hang into the gap.)
      overhang: false,
    );
    final fontWidth = _fonts
        .font(markerFont.family, markerFont.style)
        .widthOf(
          marker,
          markerFont.size,
          kerning: _font.kerning,
          features: {..._baseFeatures, ...features},
        );
    // (Outside the gem's look, as wide as its text set, in the fallback
    // fonts where the marker's font lacks its characters: a CJK
    // counter style's `あ、` in a Latin or Arabic text.)
    final width =
        fixed ??
        (asciidoctorCompat(_document, CompatFormat.pdf)
            ? fontWidth
            : math.max(fontWidth, markerBox.intrinsicWidths().$2));
    if (_listBodyIndent case final bodyIndent?) {
      _listMarkerWidth = math.max(_listMarkerWidth, width);
      return _Marked(
        content,
        markerBox,
        width,
        -width - bodyIndent,
        mirrored: _rightToLeft,
      );
    }
    return _Marked(
      content,
      markerBox,
      width,
      -width - gap + 0.5,
      mirrored: _rightToLeft,
    );
  }

  /// Converts the question and answer list [node].
  void _qanda(ListBlock node) {
    final boxes = _collect(() {
      if (node.hasTitle) _caption(node, category: 'list', labeled: false);
      final align = PdfConverter._alignOf(node.roles) ?? _s('list_text_align');
      final termSpacing = (_n('description_list_term_spacing') ?? 0).toDouble();
      final metrics = _lineMetrics(_font);
      final minRoom =
          _font.lineHeight * _font.size + metrics.leading + metrics.paddingTop;
      final markerFont = _font.copyWith(
        color: _c('list_marker_font_color') ?? _font.color,
      );
      for (final (i, DlistEntry(:terms, description: desc))
          in node.entries.indexed) {
        double? descMargin = 0;
        if (desc != null) {
          if (desc.isCompound) {
            descMargin = null;
          } else if (_nextEnclosedBlockDescending(desc) != null) {
            descMargin = _length('list_item_spacing', _font.size) ?? 0;
          }
        }
        final children = _collect(() {
          for (final (t, term) in terms.indexed) {
            CustomContent box = _textBox(
              '<em>${term.text ?? ''}</em>',
              _font,
              align: align ?? _baseTextAlign,
              normalizeLineHeight: true,
            );
            if (t == 0) {
              box = _MinRoom(
                _withMarker(box, '${i + 1}.', markerFont),
                minRoom,
              );
            }
            _out.add(
              CustomBox(
                box,
                style: BoxStyle(
                  margin: _mirrorInsets(EdgeInsets(bottom: termSpacing)),
                ),
              ),
            );
          }
          if (desc == null) return;
          if (desc.text case final text? when desc.hasText) {
            _out.add(
              CustomBox(
                _textBox(
                  text,
                  _font,
                  align: align ?? _baseTextAlign,
                  normalizeLineHeight: true,
                  hyphenate: true,
                ),
                style: BoxStyle(
                  margin: _mirrorInsets(
                    EdgeInsets(
                      bottom:
                          descMargin ??
                          (_n('prose_margin_bottom') ?? 0).toDouble(),
                    ),
                  ),
                ),
              ),
            );
          }
          _traverse(desc);
        });
        _out.add(BlockBox(children));
      }
    });
    _out.add(
      BlockBox(
        boxes,
        style: BoxStyle(
          margin: _mirrorInsets(
            EdgeInsets(
              left: _length('list_indent', _font.size) ?? 0,
              bottom: node.parent is ListItem
                  ? 0
                  : _marginBelow(node, fallback: 'prose'),
            ),
          ),
          anchor: node.id,
        ),
      ),
    );
  }

  /// Converts the description list [node] as an unordered or ordered
  /// list of its terms (in bold) and descriptions.
  void _dlistAsList(ListBlock node, {required bool ordered}) {
    final parent = node.parent;
    if (parent is! AbstractBlock) return;
    final list = ListBlock(
      parent,
      ordered ? BlockContext.olist : BlockContext.ulist,
    );
    final stack = node.hasRole('stack');
    final stop = node.attr('subject-stop') ?? (stack ? null : ':');
    for (final DlistEntry(:terms, description: desc) in node.entries) {
      final subject = terms.first.text ?? '';
      final ListItem item;
      if (desc != null) {
        final punctuated = RegExp(r'[.!?;:]$')
            .hasMatch(PdfConverter._plain(subject));
        final description = desc.hasText
            ? '${stack ? '<br>' : ' '}${desc.text ?? ''}'
            : '';
        item = ListItem(
          list,
          '<strong>$subject${punctuated ? '' : stop ?? ''}</strong>'
          '$description',
        )..subs = [];
        [...desc.blocks].forEach(item.append);
      } else {
        item = ListItem(list, '<strong>$subject</strong>')..subs = [];
      }
      list.append(item);
    }
    if (ordered) {
      _listNumerals.add(const _Numeral.decimal(1));
    } else {
      _listBullets.add('disc');
    }
    final boxes = _collect(() => _list(list));
    if (ordered) {
      _listNumerals.removeLast();
    } else {
      _listBullets.removeLast();
    }
    _out.add(BlockBox(boxes, style: BoxStyle(anchor: node.id)));
  }

  /// The next block, descending into [item] first when it has blocks (the
  /// gem's `next_enclosed_block descend: true`).
  AbstractBlock? _nextEnclosedBlockDescending(ListItem item) =>
      item.blocks.isNotEmpty ? item.blocks.first : _nextEnclosedBlock(item);
}
