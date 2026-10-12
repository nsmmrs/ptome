part of '../converter.dart';

// Inline elements.

extension _InlineElements on PdfConverter {
  /// Whether adjacent margins collapse to the larger, as in CSS (the
  /// modern engine, unless the theme's `block_margin_collapse` is false),
  /// rather than add, as asciidoctor-pdf's do.
  bool get _collapseMargins => switch (_theme.value('block_margin_collapse')) {
    ThemeBool(:final value) => value,
    ThemeString(value: 'false' || 'none') => false,
    _ => true,
  };

  /// Whether emphasis is set against its surroundings (upright in italic
  /// text): in the modern engine, unless the theme's
  /// `base_emphasis_inversion` is false.
  bool get _invertEmphasis => switch (_theme.value('base_emphasis_inversion')) {
    ThemeBool(:final value) => value,
    ThemeString(value: 'false' || 'none') => false,
    _ => true,
  };

  /// How text becomes glyphs: as OpenType shapes it (GPOS kerning, and
  /// the standard ligatures unless the theme's `base_font_ligatures` is
  /// `none`).
  Shaping get _shaping => _s('base_font_ligatures') == 'none'
      ? Shaping.opentype
      : Shaping.ligatures;

  /// Whether glyphs are as wide as their advances in whole 1000ths of the
  /// em (`base_glyph_widths: thousandths`) rather than exactly.
  bool get _thousandthWidths =>
      _choice('base_glyph_widths', const ['exact', 'thousandths']) ==
      'thousandths';

  /// Whether fonts with TrueType outlines are embedded as simple fonts
  /// of up to 256 glyphs each (`base_font_embedding: simple`), word
  /// spacing then the `Tw` operator's, rather than as Type0 fonts.
  bool get _singleByteFonts =>
      _choice('base_font_embedding', const ['composite', 'simple']) == 'simple';

  /// Whether text is kerned by the font's `kern` table alone
  /// (`base_kerning_source: kern_table`) rather than by its GPOS pairs.
  bool get _kernTableOnly =>
      _choice('base_kerning_source', const ['font', 'kern_table']) ==
      'kern_table';
  String? _convertInline(Inline node) => switch (node.context) {
    InlineContext.anchor => _inlineAnchor(node),
    InlineContext.lineBreak => '${node.text ?? ''}<br>',
    InlineContext.button =>
      '<button>${(_s('button_content') ?? '%s').replaceFirst('%s', node.text ?? '')}</button>',
    InlineContext.callout => _inlineCallout(node),
    InlineContext.footnote => _inlineFootnote(node),
    InlineContext.image => _inlineImage(node),
    InlineContext.indexterm => _inlineIndexterm(node),
    InlineContext.kbd => _inlineKbd(node),
    InlineContext.menu => _inlineMenu(node),
    InlineContext.quoted => _inlineQuoted(node),
    // A unit's mark: its anchor, then its label (ADR-0020).
    InlineContext.unit =>
      '${node.id != null ? '<a id="${node.id}">$_dummyText</a>' : ''}'
          '${node.text ?? ''}',
    // A note's caller, or its unit's entry: text in the entry's role (a
    // reference Bible's cross-references, set beside their verse).
    InlineContext.note => _inlineQuoted(node),
  };
  String _inlineAnchor(Inline node) {
    final doc = _document;
    final target = node.target ?? '';
    switch (node.type) {
      case 'link':
        final anchor = node.id != null
            ? '<a id="${node.id}">$_dummyText</a>'
            : '';
        final role = node.role;
        final classAttr = role != null ? ' class="$role"' : '';
        final media = doc.attr('media') ?? 'screen';
        final text = node.text ?? '';
        var bare = target;
        if (media != 'screen' && target.startsWith('mailto:')) {
          bare = target.substring(7);
          if (bare == text) node.addRole('bare');
          if (!doc.hasAttr('hide-uri-scheme')) bare = target;
        }
        final roles = node.attr('role')?.split(' ') ?? const <String>[];
        if (roles.contains('bare')) {
          return '$anchor<a href="$target"$classAttr>'
              '$text</a>';
        }
        // `show-link-uri=footnote` (modern engine): the URI in a footnote,
        // as print books set it.
        if (doc.attr('show-link-uri') == 'footnote' && _pageFootnotes) {
          if (doc.hasAttr('hide-uri-scheme')) {
            final boundary = bare.indexOf('://');
            if (boundary >= 0) bare = bare.substring(boundary + 3);
          }
          final index = doc.counter('footnote-number');
          doc.registerFootnote(
            Footnote(index, null, '<a href="$target">$bare</a>'),
          );
          return '$anchor<a href="$target"$classAttr>$text</a>'
              '${_footnoteReference(index)}';
        }
        if (doc.hasAttr('show-link-uri') ||
            (media != 'screen' && doc.attributeUnspecified('show-link-uri'))) {
          if (doc.hasAttr('hide-uri-scheme')) {
            final boundary = bare.indexOf('://');
            if (boundary >= 0) bare = bare.substring(boundary + 3);
          }
          return '$anchor<a href="$target"$classAttr>$text</a> '
              '[<font size="0.85em">$bare</font>&#93;';
        }
        return '$anchor<a href="$target"$classAttr>$text</a>';
      case 'xref':
        if (node.attributes['path'] case final path?) {
          return '<a href="$target">${node.text ?? path}</a>';
        }
        if (node.attributes['refid'] case final refid?) {
          var text = node.text;
          String? anchor;
          if (text == null && !_resolvingXref) {
            _resolvingXref = true;
            try {
              final ref = doc.catalog.refs[refid];
              final style = node.attr('xrefstyle', null, 'xrefstyle');
              text = switch (ref) {
                final AbstractBlock block => block.xreftext(style),
                final Inline inline => inline.xreftext(style),
                _ => null,
              };
              if (text != null && text.contains('<a')) {
                text = text.replaceAll(RegExp(r'<(?:a\b[^>]*|/a)>'), '');
              }
              if (ref case final Inline inline
                  when inline.type == 'bibref' && _bibrefRefs.add(refid)) {
                anchor = '<a id="_bibref_ref_$refid">$_dummyText</a>';
              }
            } finally {
              _resolvingXref = false;
            }
          }
          return '${anchor ?? ''}<a anchor="$refid">${text ?? '[$refid]'}</a>'
              .replaceAll(']', '&#93;');
        }
        return '<a anchor="${doc.attr('pdf-anchor') ?? ''}">'
            '${node.text ?? '[^top&#93;'}</a>';
      case 'ref':
        return '<a id="${node.id}">$_dummyText</a>';
      case 'bibref':
        final id = node.id ?? '';
        var reftext = '[${node.reftext ?? id}]';
        if (_bibrefRefs.contains(id)) {
          reftext = '<a anchor="_bibref_ref_$id">$reftext</a>';
        }
        return '<a id="$id">$_dummyText</a>$reftext';
      default:
        logger.warn('unknown anchor type: ${node.type}');
        return '';
    }
  }

  /// Whether links break after their delimiters alone (`url_breaks:
  /// delimiters`) rather than at The Chicago Manual of Style's points.
  bool get _urlDelimiterBreaks =>
      _choice('url_breaks', const ['chicago', 'delimiters']) == 'delimiters';

  /// Whether a line may break after a slash in prose (`base_slash_breaks`,
  /// as the Unicode line breaking algorithm allows).
  bool get _slashBreaks => switch (_theme.value('base_slash_breaks')) {
    ThemeBool(value: false) => false,
    _ => true,
  };
  String _inlineCallout(Inline node) {
    var glyph = _conumGlyph(int.tryParse(node.text ?? '') ?? 0);
    // A marker as text: in its own style and figures.
    if (_conumTemplate() != null) {
      glyph =
          '<span class="conum-text">${glyph.replaceAll('&', '&amp;').replaceAll('<', '&lt;')}</span>';
    }
    final family = _s('conum_font_family');
    // The modern engine leaves the marker out of copied code, and links
    // it to its callout list item (which links back).
    final shown = '<span class="artifact">$glyph</span>';
    var result = family == null || family == _font.family
        ? shown
        : '<font name="$family">$shown</font>';
    // The marker keeps its color as a link (the text's, when the theme
    // gives it none).
    final color =
        _theme.value('conum_font_color')?.rubyString ?? _font.color?.rubyString;
    if (color != null) result = '<font color="$color">$result</font>';
    final id = node.id;
    if (id != null && _document.callouts.explained.contains(id)) {
      result =
          '<a id="$id">$_dummyText</a>'
          '<a anchor="${PdfConverter._calloutItem(id)}">$result</a>';
    }
    return result;
  }

  /// The inline image [node] as an `<img>` (the gem's
  /// `convert_inline_image`), or its alt text when it can't be read.
  String _inlineImage(Inline node) {
    final String image;
    if (node.type == 'icon') {
      image = _inlineIcon(node);
    } else {
      final target = node.target ?? '';
      final alt = node.attr('alt') ?? '';
      final data = PdfConverter._dataUri.firstMatch(target);
      final format = data != null
          ? switch (data[1]!) {
              'jpg' => 'jpeg',
              'svg+xml' => 'svg',
              final other => other,
            }
          : node.attr('format') ?? PdfConverter._imageFormat(target);
      List<int>? bytes;
      if (format == 'gif') {
        logger.warn('GIF image format not supported; convert $target to PNG');
      } else if (data != null) {
        try {
          bytes = base64.decode(data[2]!);
        } on FormatException {
          bytes = null;
        }
      } else {
        bytes = _imageBytes(node, target);
      }
      Graphic? graphic;
      String? problem;
      if (bytes != null) {
        (graphic, problem) = _graphicOf(
          bytes,
          format,
          path: data == null ? _lastImagePath : null,
        );
      }
      if (bytes == null) {
        image = '[$alt&#93;';
      } else {
        final src = target.replaceAll('"', '%22');
        if (graphic != null) _inlineGraphics[src] = graphic;
        if (problem != null) _imageProblems[src] = problem;
        final role = node.role;
        final classAttr = role == null ? '' : ' class="$role"';
        final fit = node.attr('fit');
        final fitAttr = fit == null ? '' : ' fit="$fit"';
        final intrinsic = graphic == null ? 0.0 : _intrinsicWidth(graphic);
        final width = _imageWidthOf(node.attr, fallback: false, vw: false);
        String widthValue;
        switch (width.kind) {
          // Converted while the document is parsed (a title, for its id),
          // the gem defers a scale to the arranger, which takes it as a
          // factor rather than a percentage.
          case _ImageWidthKind.scale when !_converting:
            widthValue = '${intrinsic * width.value * 100}';
          case _ImageWidthKind.scale:
            widthValue = '${intrinsic * width.value}';
          case _ImageWidthKind.percent:
            widthValue = '${PdfConverter._rubyFloat(width.value * 100)}%';
            if (node.parent?.context == BlockContext.tableCell) {
              widthValue += '$intrinsic';
            }
          case _ImageWidthKind.natural:
            widthValue = '$intrinsic';
          case _ImageWidthKind.points || _ImageWidthKind.viewport:
            widthValue = '${width.value}';
        }
        final escapedAlt = alt.replaceAll('"', '&quot;');
        image =
            '<img src="$src" format="$format" alt="$escapedAlt" '
            'width="$widthValue"$classAttr$fitAttr>';
      }
    }
    if (node.attr('link') case final link? when link.isNotEmpty) {
      return link.startsWith('#')
          ? '<a anchor="${link.substring(1)}">$image</a>'
          : '<a href="$link">$image</a>';
    }
    return image;
  }

  /// The width of [graphic] as the gem measures it (pixels at 0.75pt, SVG
  /// by prawn-svg's sizing in the content area).
  double _intrinsicWidth(Graphic graphic) {
    if (graphic case final SvgImage svg) {
      final (width, height) = _pageSize(_document);
      final margins = _pageMargins(_document);
      return prawnSvgSize(
        svg,
        null,
        null,
        width - margins.horizontal,
        height - margins.vertical,
      ).$1;
    }
    return graphic.intrinsicWidth * 0.75;
  }

  IndexName _indexName(String markup) =>
      IndexName(PdfConverter._plain(markup), markup);

  /// The index term [node]: an anchor where it's used (and its text, if
  /// visible), the term stored in the index (the gem's
  /// `convert_inline_indexterm`).
  String _inlineIndexterm(Inline node) {
    final visible = node.type == 'visible';
    final name = _index.nextAnchor();
    final anchor =
        '<a id="$name" type="indexterm"${visible ? ' visible="true"' : ''}>'
        '$_dummyText</a>';
    final see = switch (node.attr('see')) {
      final value? => _indexName(value),
      null => null,
    };
    final seeAlso = [
      for (final term in node.seeAlso ?? const <String>[]) _indexName(term),
    ];
    final names = visible
        ? [_indexName(node.text ?? '')]
        : [for (final term in node.terms ?? const <String>[]) _indexName(term)];
    _index.store(names, name, see: see, seeAlso: seeAlso);
    return visible ? '$anchor${node.text ?? ''}' : anchor;
  }

  /// Fills the index section (the gem's `convert_index_section`): the
  /// categories and their terms in the theme's columns.
  void _fillIndex(List<LayoutBox> slot) {
    _index
      ..linkPages((anchor) => _anchorPages[anchor], _pageLabel)
      ..linkAssociations();
    // The modern engine lists each page once unless the document asks
    // otherwise; the gem lists a page for each use.
    final style = _document.attr('index-pagenum-sequence-style') ?? 'page';
    // `index_category_headings: false` leaves out the letter headings.
    final headings = switch (_theme.value('index_category_headings')) {
      ThemeBool(:final value) => value,
      _ => indexHasCategoryHeadings(_document),
    };
    // The modern engine reads the index's font keys (`index_font_family`,
    // `_size`, `_color`, `_style`); the gem has none.
    final saved = _font;
    _font = _themeFont('index', _font);
    final List<LayoutBox> boxes;
    try {
      boxes = _collect(() {
        final termSpacing = (_n('description_list_term_spacing') ?? 0)
            .toDouble();
        final needed = termSpacing + 2 * _typesetHeight(_font);
        final termStyle =
            PdfConverter._fontStyle(_s('description_list_term_font_style')) ??
            _font.style;
        final proseMargin = (_n('prose_margin_bottom') ?? 0).toDouble();
        for (final category in _index.categories) {
          final letter = category.name.text;
          if (headings) {
            _out.add(
              CustomBox(
                _MinRoom(
                  _textBox(
                    letter,
                    _font.copyWith(style: termStyle),
                    align: 'left',
                    inlineFormat: false,
                  ),
                  needed,
                ),
                style: BoxStyle(margin: EdgeInsets(bottom: termSpacing)),
              ),
            );
          }
          for (final term in category.terms) {
            _indexTerm(term, style);
          }
          if (proseMargin > 0) _out.add(SpacerBox(proseMargin));
        }
      });
    } finally {
      _font = saved;
    }
    final columns = (_n('index_columns') ?? 1).toInt();
    slot
      ..clear()
      ..addAll(
        columns < 2
            ? boxes
            : [
                ColumnsBox(
                  boxes,
                  count: columns,
                  gap: (_n('index_column_gap') ?? 0).toDouble(),
                ),
              ],
      );
  }

  /// Adds the entry of index [term] (the gem's `convert_index_term`).
  void _indexTerm(IndexTerm term, String? style) {
    final markup = StringBuffer();
    // `index_pagenum_text_align: right` (modern engine): the page numbers
    // in a column at the right, in tabular figures, as books set them.
    final column =
        _choice('index_pagenum_text_align', const ['left', 'right']) == 'right';
    String? pagenums;
    final seeAlso = <String>[];
    // Linked only on screen (the gem's `media`).
    final screen = (_document.attr('media') ?? 'screen') == 'screen';
    String link(String anchor, String text) =>
        screen ? '<a anchor="$anchor">$text</a>' : text;
    if (!term.isContainer && screen) {
      markup.write('<a id="${term.anchor}">$_dummyText</a>');
    }
    // (A term written over lines is one line: its spaces collapse.)
    markup.write(term.name.markup.replaceAll(RegExp('[ \t\n]+'), ' '));
    if (!term.isContainer) {
      if (term.see case (final target, final name)) {
        markup
          ..write(' (see ')
          ..write(
            target == null ? name.markup : link(target.anchor, name.markup),
          )
          ..write(')');
      } else {
        final destinations = term.destinations;
        final List<String> numbers;
        switch (style) {
          // (In print, ranges, unless the document asks for each page in
          // the modern engine: `index-pagenum-sequence-style: page`.)
          case _
              when !screen &&
                  _document.attr('index-pagenum-sequence-style') == 'page':
            numbers = [
              ...{for (final d in destinations) d.page!},
            ];
          case _ when !screen:
            numbers = PdfConverter._consolidateRanges([
              ...{for (final d in destinations) d.page!},
            ]);
          case 'page':
            final seen = <String>{};
            numbers = [
              for (final d in destinations)
                if (seen.add(d.page!)) link(d.anchor, d.page!),
            ];
          case 'range':
            final first = <String, String>{};
            for (final d in destinations) {
              first.putIfAbsent(d.page!, () => d.anchor);
            }
            numbers = [
              for (final range in PdfConverter._consolidateRanges(
                first.keys.toList(),
              ))
                link(first[range.split('-').first]!, range),
            ];
          default:
            numbers = [for (final d in destinations) link(d.anchor, d.page!)];
        }
        if (column) {
          pagenums = numbers.join(', ');
        } else {
          for (final number in numbers) {
            markup.write(', $number');
          }
        }
        for (final (target, name) in term.seeAlso) {
          final also = target == null
              ? name.markup
              : link(target.anchor, name.markup);
          seeAlso.add('(see also $also)');
        }
      }
    }
    final indent =
        _length('description_list_description_indent', _font.size) ?? 0;
    final hanging = indent * 2;
    const first = 0.0;
    void entry(String text, double left, [String? numbers]) {
      final box = _textBox(
        text,
        _font,
        align: 'left',
        normalize: false,
        indent: first - hanging,
      );
      _out.add(
        CustomBox(
          numbers == null
              ? box
              : _IndexRow(
                  box,
                  _textBox(
                    numbers,
                    _font,
                    align: 'right',
                    normalize: false,
                    features: const {'tnum'},
                  ),
                  gap: _font.size,
                ),
          style: BoxStyle(margin: EdgeInsets(left: left + hanging)),
        ),
      );
    }

    entry(markup.toString(), 0, pagenums);
    if (seeAlso.isEmpty && term.isLeaf) return;
    final nested = _collect(() {
      for (final item in seeAlso) {
        entry(item, 0);
      }
      for (final subterm in term.terms) {
        _indexTerm(subterm, style);
      }
    });
    _out.add(
      BlockBox(
        nested,
        style: BoxStyle(margin: EdgeInsets(left: indent)),
      ),
    );
  }

  /// The image icon [node] names (`:icons:` set, but not to `font`): the
  /// file `<name>.<icontype>` (PNG by default) in the `iconsdir`, as tall
  /// as the line; its name in brackets when there's no such file.
  String _imageIcon(Inline node, String alt) {
    final name = node.target ?? '';
    final format = _document.attr('icontype') ?? 'png';
    final resolver = _document.pathResolver;
    final dir = resolver.posixify(_document.attr('iconsdir') ?? '');
    final file = dir.isEmpty ? '$name.$format' : '$dir/$name.$format';
    final path = resolver.isAbsolutePath(file)
        ? resolver.expandPath(file)
        : node.normalizeSystemPath(file, targetName: 'image');
    final bytes = io.isFile(path) && io.isReadable(path)
        ? io.readBytes(path)
        : null;
    if (bytes == null) {
      logger.warn("image icon for '$name' not found or not readable: $path");
      return '[$name&#93;';
    }
    final (graphic, problem) = _graphicOf(bytes, format, path: path);
    final src = path.replaceAll('"', '%22');
    if (graphic != null) _inlineGraphics[src] = graphic;
    if (problem != null) _imageProblems[src] = problem;
    final width = graphic == null ? 0.0 : _intrinsicWidth(graphic);
    return '<img src="$src" format="$format" '
        'alt="${alt.replaceAll('"', '&quot;')}" width="$width" fit="line">';
  }

  String _inlineIcon(Inline node) {
    final icons = _document.attr('icons');
    final alt = node.attr('alt') ?? '';
    if (icons != 'font') {
      if (icons != null) return _imageIcon(node, alt);
      return '[$alt&#93;';
    }
    var name = node.target ?? '';
    String? set;
    if (name.contains('@')) {
      final at = name.indexOf('@');
      set = name.substring(at + 1);
      name = name.substring(0, at);
    } else {
      set = node.attr('set');
    }
    final (resolvedSet, iconName, glyph) = _resolveIcon(name, set);
    if (glyph == null) {
      logger.warn(
        '$iconName is not a valid icon name in the $resolvedSet icon set',
      );
      return '[$alt&#93;';
    }
    if (!_iconsInstalled(resolvedSet)) return '[$alt&#93;';
    final size = switch (node.attr('size')) {
      null => '',
      'lg' => ' size="1.333em"',
      'fw' => ' width="1em"',
      final value => ' size="${value.replaceFirst('x', 'em')}"',
    };
    final role = node.role;
    final classAttr = role == null ? '' : ' class="$role"';
    return '<font name="$resolvedSet"$size$classAttr>$glyph</font>';
  }

  String _inlineFootnote(Inline node) {
    final index = node.attr('index');
    // (A footnote in an AsciiDoc table cell is its nested document's.)
    final footnote = index == null
        ? null
        : [
            ...?(node.document as Document?)?.footnotes,
            ..._document.footnotes,
          ].where((f) => f.index == index).firstOrNull;
    if (footnote != null) {
      return _footnoteReference(
        index!,
        anchored: node.type != 'xref',
        rendered: _renderedFootnotes.contains(footnote),
        caller: _streamOf(footnote) == null ? null : footnote.caller ?? index,
      );
    }
    if (node.type == 'xref') {
      final color = _theme.value('role_unresolved_font_color')?.rubyString;
      return '<sup class="wj"><font color="$color">[${node.text ?? ''}]</font></sup>';
    }
    logger.warn('unknown footnote type: ${node.type}');
    return '';
  }

  /// Whether the space before a footnote's reference goes
  /// (`footnotes_reference_space`: `keep`, the default, or `collapse`).
  bool get _footnoteSpaceCollapses =>
      _choice('footnotes_reference_space', const ['keep', 'collapse']) ==
      'collapse';

  /// The reference to footnote [index]: its number in brackets, raised,
  /// linked to the footnote ([anchored]: the footnote links back to it).
  String _footnoteReference(
    String index, {
    bool anchored = true,
    bool rendered = false,
    String? caller,
  }) {
    final anchor = anchored
        ? '<a id="_footnoteref_$index">$_dummyText</a>'
        : '';
    if (!anchored) _unanchoredFootnotes.add(index);
    final label =
        caller ??
        (_footnoteNumbering == 'document'
            ? '${_mainNumber(index)}'
            : rendered
            ? _footnoteLabels[index] ?? index
            : '${_mainNumber(index) - _mainRendered}');
    // `footnotes_reference_content` (modern engine, ADR-0010), else the
    // document's `footnote-reference-template` (every format's, ADR-0012):
    // `[1]` by default, raised, the number the link.
    final template =
        (_s('footnotes_reference_content') ??
            _document.attr('footnote-reference-template')) ??
        '[{{number}}]';
    final marker = renderNumbered(
      template,
      label,
      (n) =>
          '<a anchor="_footnotedef_$index"${_footnoteLabelKey(index)}>$n</a>',
    );
    return '<sup class="wj">$anchor$marker</sup>';
  }

  /// The label before footnote [index]'s note, numbered [label]:
  /// `footnotes_label_content` (modern engine, ADR-0010), else the
  /// document's `footnote-label-template`, `[1] ` by default, the number a
  /// link back to the reference.
  String _footnoteNoteLabel(String index, String label) => renderNumbered(
    (_s('footnotes_label_content') ??
            _document.attr('footnote-label-template')) ??
        '[{{number}}] ',
    label,
    (n) => '<a anchor="_footnoteref_$index"${_footnoteLabelKey(index)}>$n</a>',
  );

  /// How footnotes are numbered: from 1 in each `chapter` (the gem's),
  /// on each `page` (modern engine, footnotes at the bottom of the page)
  /// or through the `document` (`footnotes_numbering`).
  String get _footnoteNumbering {
    return switch (_choice('footnotes_numbering', const [
      'chapter',
      'page',
      'document',
    ])) {
      'page' when _pageFootnotes => 'page',
      'document' => 'document',
      _ => 'chapter',
    };
  }

  /// The `label` attribute that has the layout number footnote [index]'s
  /// reference and note on their page (when footnotes are numbered so).
  String _footnoteLabelKey(String index) =>
      _footnoteNumbering == 'page' && !_streamed(index)
      ? ' label="fn$index"'
      : '';

  /// Whether footnote [index] is a stream's note (by its caller, not
  /// numbered).
  bool _streamed(String index) =>
      _noteStreams.isNotEmpty &&
      _document.footnotes.any((f) => f.index == index && _streamOf(f) != null);

  /// Numbers each page's footnote references from 1, in reading order,
  /// from [result]'s anchors; the footnotes whose numbers changed.
  Set<String> _numberFootnotesByPage(LayoutResult result) {
    final references =
        [
          for (final MapEntry(:key, :value) in result.anchors.entries)
            if (key.startsWith('_footnoteref_'))
              (key.substring('_footnoteref_'.length), value),
        ]..sort((a, b) {
          final (_, p) = a;
          final (_, q) = b;
          if (p.page != q.page) return p.page.compareTo(q.page);
          if ((p.y - q.y).abs() > 0.5) return q.y.compareTo(p.y);
          return p.x.compareTo(q.x);
        });
    final changed = <String>{};
    var page = -1;
    var number = 0;
    for (final (index, position) in references) {
      if (position.page != page) {
        page = position.page;
        number = 0;
      }
      number++;
      final key = 'fn$index';
      if (_layoutLabels[key] != '$number') {
        _layoutLabels[key] = '$number';
        changed.add(index);
      }
    }
    return changed;
  }

  /// [markup] with each side note it marks taken out to [_sideNotes] (set
  /// in [font] and its role), an anchor for it in its place.
  String _takeSideNotes(String markup, _FontState font) =>
      markup.replaceAllMapped(PdfConverter._sideRx, (m) {
        final name = m[1]!;
        final plain = m[3]!
            .replaceAll(RegExp('<[^>]*>'), '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        _sideNoteTexts[name] = (
          m[2]!,
          plain.length > 40 ? '${plain.substring(0, 40)}…' : plain,
        );
        _sideNotes[name] = CustomBox(
          _textBox(
            m[3]!,
            font,
            align: _keys('role_${m[2]}').string('text_align') ?? 'left',
            hyphenate: true,
          ),
        );
        return '<a id="$name">$_dummyText</a>';
      });

  /// The column side notes are set in on page [number] of [template]
  /// (`side_notes_column`): `center`, the gap between the middle columns
  /// (the default in columns), or `outside`, the outer margin (the right
  /// one, or the left one of a verso page of a [sided] book); each inset
  /// by `side_notes_padding`.
  Rect? _sideColumn(int number, PageTemplate template, {required bool sided}) {
    final columns = (_n('page_columns') ?? 1).toInt();
    final m = template.margins;
    final size = template.size;
    final column =
        _choice('side_notes_column', const ['center', 'outside']) ??
        (columns >= 2 ? 'center' : 'outside');
    final double left;
    final double width;
    if (column == 'center' && columns >= 2) {
      final gap = (_n('page_column_gap') ?? _rootFontSize).toDouble();
      final columnWidth =
          (size.width - m.horizontal - gap * (columns - 1)) / columns;
      final before = columns ~/ 2;
      left = size.left + m.left + before * columnWidth + (before - 1) * gap;
      width = gap;
    } else if (!sided || number.isOdd) {
      (left, width) = (size.right - m.right, m.right);
    } else {
      (left, width) = (size.left, m.left);
    }
    final padding =
        _length('side_notes_padding', _rootFontSize) ?? _rootFontSize / 2;
    if (width - 2 * padding <= 0) return null;
    return Rect(
      left + padding,
      size.bottom + m.bottom,
      width - 2 * padding,
      size.height - m.vertical,
    );
  }

  /// Whether footnotes go at the bottom of the page their reference is on
  /// (the modern engine's default, `footnotes_placement: page`), rather
  /// than at the end of the chapter or document (`end`, the gem's).
  bool get _pageFootnotes =>
      (_choice('footnotes_placement', const ['page', 'end']) ?? 'page') ==
      'page';

  /// A note's opening heading (`[.heading]#…#`), and the space after it.
  static final _noteHeadingRx = RegExp(
    r'^<span class="heading">(.*?)</span>\s*',
  );

  /// The heading [markup] above a note (`footnotes_heading_*`, italic and
  /// set left by default, [spacing] above it), kept with the note.
  LayoutBox _noteHeading(String markup, double spacing) => CustomBox(
    _textBox(
      markup,
      _themeFont('footnotes_heading', _font.copyWith(style: 'italic')),
      align: _keys('footnotes_heading').string('text_align') ?? 'left',
      hyphenate: true,
    ),
    style: BoxStyle(
      margin: EdgeInsets(
        top:
            _length('footnotes_heading_margin_top', _font.size) ??
            spacing + _font.size / 2,
      ),
      keepWithNext: true,
    ),
  );

  /// The space between footnotes (`footnotes_item_spacing`, an em of the
  /// body's size).
  double get _footnoteItemSpacing =>
      _length('footnotes_item_spacing', _rootFontSize) ?? 0;

  /// The stream [footnote] is set in apart from the footnotes, if any.
  String? _streamOf(Footnote footnote) => switch (footnote.stream) {
    final stream? when _noteStreams.contains(stream) => stream,
    _ => null,
  };

  /// Footnote [index]'s number in the main series: the notes of the
  /// streams apart before it not counted.
  int _mainNumber(String index) {
    final number = int.tryParse(index) ?? 0;
    if (_noteStreams.isEmpty) return number;
    return number -
        _document.footnotes
            .where(
              (f) =>
                  _streamOf(f) != null && (int.tryParse(f.index) ?? 0) < number,
            )
            .length;
  }

  /// How many of the main series' footnotes are rendered.
  int get _mainRendered =>
      _renderedFootnotes.where((f) => _streamOf(f) == null).length;

  /// [body] with the note stream [stream]'s keys over the footnotes'.
  T _asStream<T>(String? stream, T Function() body) {
    if (stream == null) return body();
    final saved = _theme;
    _theme = _theme.overlaid(
      'note_stream_${stream.replaceAll('-', '_')}_',
      'footnotes_',
    );
    try {
      return body();
    } finally {
      _theme = saved;
    }
  }

  /// The note streams the layout sets under the footnotes.
  List<NoteStream> _layoutNoteStreams() => [
    for (final stream in _noteStreams)
      if (_noteStreamOf.containsValue(stream))
        _asStream(stream, () {
          late NoteStream made;
          _withFont('footnotes', () {
            made = NoteStream(
              stream,
              separator: _footnoteSeparator(),
              columns: (_n('footnotes_columns') ?? 1).toInt(),
              columnGap:
                  _length('footnotes_column_gap', _rootFontSize) ??
                  _rootFontSize,
              // (`note_stream_<name>_arrangement: run_in`: its notes in one
              // paragraph, `_run_in_separator` between them.)
              runIn: _s('footnotes_arrangement') == 'run_in'
                  ? NoteStream.joined(
                      separator: _s('footnotes_run_in_separator') ?? '\u2003',
                    )
                  : null,
            );
          });
          return made;
        }),
  ];

  /// The note streams set in a margin column of their own
  /// (`note_stream_<name>_column`: `left`, `right`, `outside`, `inside`),
  /// each note level with its reference: a Talmud page's commentaries, a
  /// marginal apparatus.
  List<SideNoteStream> _layoutSideNoteStreams({required bool sided}) => [
    for (final stream in _noteStreams)
      if (_sideNoteStreamOf.containsValue(stream))
        SideNoteStream(
          stream,
          (number, template) =>
              _streamColumn(stream, number, template, sided: sided),
        ),
  ];

  /// The margin column of note stream [stream] on page [number]: in the
  /// margin its `_column` names, `_column_offset` (half an em) from the
  /// text, `_column_width` wide (the margin's width less twice the
  /// offset); null when it has no room.
  Rect? _streamColumn(
    String stream,
    int number,
    PageTemplate template, {
    required bool sided,
  }) {
    final keys = _Keys(this, ['note_stream_${stream.replaceAll('-', '_')}']);
    final m = template.margins;
    final size = template.size;
    final recto = !sided || number.isOdd;
    final right = switch (keys.string('column')) {
      'right' => true,
      'outside' => recto,
      'inside' => !recto,
      _ => false,
    };
    final offset =
        keys.length('column_offset', _rootFontSize) ?? _rootFontSize / 2;
    final margin = right ? m.right : m.left;
    final width =
        keys.length('column_width', _rootFontSize) ?? margin - 2 * offset;
    if (width <= 0) return null;
    final left = right
        ? size.right - m.right + offset
        : size.left + m.left - offset - width;
    return Rect(left, size.bottom + m.bottom, width, size.height - m.vertical);
  }

  /// The rule above the footnotes at the bottom of a page: a third of the
  /// column long (`footnotes_separator_length`), `footnotes_separator_width`
  /// thick, `footnotes_margin_top` below the text.
  LayoutBox _footnoteSeparator() {
    final width = (_n('footnotes_separator_width') ?? 0.5).toDouble();
    final color = pdfColorOf(
      _c('footnotes_separator_color') ?? _c('base_border_color'),
    );
    final length = _s('footnotes_separator_length') ?? '33.33%';
    final spacing = _footnoteItemSpacing;
    // With lines from their cap heights (base_leading) the rule takes no
    // room: drawn
    // on its line, the space above and below it from there.
    final flat = _capLeading(_font) != null;
    return DrawingBox(
      flat ? 0 : width,
      (canvas, rect) {
        if (color == null || width <= 0) return;
        final long = length.endsWith('%')
            ? rect.width *
                  (double.tryParse(length.replaceAll('%', '')) ?? 0) /
                  100
            : PdfConverter._toPoints(ThemeString(length));
        canvas
          ..save()
          ..setStrokeColor(color)
          ..setLineWidth(width)
          ..moveTo(rect.left, rect.top - (flat ? 0 : width / 2))
          ..lineTo(rect.left + long, rect.top - (flat ? 0 : width / 2))
          ..stroke()
          ..restore();
      },
      style: BoxStyle(
        margin: EdgeInsets(
          top: _length('footnotes_margin_top', _rootFontSize) ?? _font.size,
          // (Each note has the item spacing above it.)
          bottom: math.max(spacing, _font.size / 2) - spacing,
        ),
      ),
    );
  }

  /// Adds the footnotes of [node] not yet rendered, at the bottom of the
  /// page by default (the gem's `ink_footnotes`); in the modern engine,
  /// each at the bottom of the page its reference is on.
  void _footnotes(AbstractBlock node) {
    final doc = _document;
    final footnotes = [
      for (final footnote in doc.footnotes)
        if (!_renderedFootnotes.contains(footnote)) footnote,
    ];
    if (footnotes.isEmpty) return;
    if (_pageFootnotes) {
      final offset = _renderedFootnotes
          .where((f) => _streamOf(f) == null)
          .length;
      final sectionText = node is Section
          ? node.xreftext(doc.attr('xrefstyle'))
          : null;
      for (final footnote in footnotes) {
        final stream = _streamOf(footnote);
        _asStream(
          stream,
          () => _withFont('footnotes', () {
            final spacing = _footnoteItemSpacing;
            // How far each note's first line is set in (footnotes_indent,
            // an em of the notes' size), and the space after its label
            // (footnotes_label_gap): a no-break space that wide.
            final indent = _length('footnotes_indent', _font.size) ?? 0;
            final gapWidth = _length('footnotes_label_gap', _font.size) ?? 0;
            final space = _fonts
                .font(_font.family, _font.style)
                .widthOf('\u00a0', 1, kerning: false);
            final gap = gapWidth > 0 && space > 0
                ? '<font size="${gapWidth / space}">\u00a0</font>'
                : '';
            final index = footnote.index;
            // (A stream's note by its caller; the main series numbered
            // without the streams' notes.)
            final label = stream != null
                ? footnote.caller ?? index
                : _footnoteNumbering == 'document'
                ? '${_mainNumber(index)}'
                : '${_mainNumber(index) - offset}';
            if (sectionText != null && stream == null) {
              _footnoteLabels[index] = '$label - $sectionText';
            }
            final id = '_footnoteref_$index';
            // (A stream in a margin column: beside its anchor.)
            final side = stream != null && _s('footnotes_column') != null;
            if (side) {
              _sideNoteStreamOf[id] = stream;
            } else if (stream != null) {
              _noteStreamOf[id] = stream;
            }
            // (A note that opens with a heading, `[.heading]#…#`: the
            // heading a paragraph of its own above it, kept with it, as a
            // study Bible heads a run of its notes.)
            final opening = _noteHeadingRx.firstMatch(footnote.text);
            final text = opening == null
                ? footnote.text
                : footnote.text.substring(opening.end);
            final note = CustomBox(
              _textBox(
                '<a id="_footnotedef_$index">$_dummyText</a>'
                '${_footnoteNoteLabel(index, label)}$gap$text',
                _font,
                align: _baseTextAlign,
                indent: indent,
                hyphenate: true,
              ),
              style: BoxStyle(margin: EdgeInsets(top: spacing)),
            );
            (side ? _sideNotes : _notes)[id] = opening == null
                ? note
                : BlockBox([_noteHeading(opening[1]!, spacing), note]);
          }),
        );
      }
      _renderedFootnotes.addAll(footnotes);
      return;
    }
    if (node is Document || node == doc.blocks.lastOrNull) {
      final margin = (_n('block_margin_bottom') ?? 0).toDouble();
      if (margin > 0) _out.add(SpacerBox(margin));
    }
    final bottom = _s('footnotes_margin_top') == 'auto';
    if (!bottom) {
      final margin = _length('footnotes_margin_top', _rootFontSize) ?? 0;
      if (margin > 0) _out.add(SpacerBox(margin));
    }
    final items = <CustomBox>[];
    _withFont('footnotes', () {
      final saved = _out;
      _out = items;
      if (doc.attr('footnotes-title') case final title?) {
        final font = _themeFont(
          'footnotes_caption',
          _themeFont('caption', _font),
        );
        items.add(
          CustomBox(
            _textBox(title, font, align: _baseTextAlign, normalize: false),
            style: BoxStyle(
              margin: EdgeInsets(
                top:
                    (_n('footnotes_caption_margin_outside') ??
                            _n('caption_margin_outside') ??
                            0)
                        .toDouble(),
                bottom:
                    (_n('footnotes_caption_margin_inside') ??
                            _n('caption_margin_inside') ??
                            0)
                        .toDouble(),
              ),
            ),
          ),
        );
      }
      _out = saved;
      final spacing = _footnoteItemSpacing;
      final offset = _renderedFootnotes.length;
      final sectionText = node is Section
          ? node.xreftext(doc.attr('xrefstyle'))
          : null;
      for (final footnote in footnotes) {
        final index = footnote.index;
        final label = _footnoteNumbering == 'document'
            ? index
            : '${(int.tryParse(index) ?? 0) - offset}';
        if (sectionText != null) {
          _footnoteLabels[index] = '$label - $sectionText';
        }
        items.add(
          CustomBox(
            _textBox(
              '<a id="_footnotedef_$index">$_dummyText</a>'
              '${_footnoteNoteLabel(index, label)}${footnote.text}',
              _font,
              align: _baseTextAlign,
              hyphenate: true,
            ),
            style: BoxStyle(margin: EdgeInsets(bottom: spacing)),
          ),
        );
      }
    });
    _renderedFootnotes.addAll(footnotes);
    _out.add(
      CustomBox(
        _Stacked(items, bottom: bottom),
        style: BoxStyle(margin: _outdented(EdgeInsets.zero)),
      ),
    );
  }

  String _inlineKbd(Inline node) {
    final keys = node.keys ?? const [];
    if (keys.length == 1) return '<kbd>${keys.first}</kbd>';
    return keys
        .map((key) => '<kbd>$key</kbd>')
        .join(_s('kbd_separator') ?? '+');
  }

  String _inlineMenu(Inline node) {
    final menu = node.attr('menu') ?? '';
    final caret = _s('menu_caret_content') ?? ' › ';
    final submenus = node.submenus ?? const [];
    final item = node.attr('menuitem');
    if (submenus.isNotEmpty) {
      return '<menu>${[menu, ...submenus, ?item].join(caret)}</menu>';
    }
    if (item != null) return '<menu>$menu$caret$item</menu>';
    return '<menu>$menu</menu>';
  }

  String _inlineQuoted(Inline node) {
    String open;
    String close;
    var isTag = true;
    var quotes = false;
    final quoteChars = switch (_theme.value('quotes')) {
      ThemeList(:final values) => [for (final v in values) v.rubyString],
      _ => const ['&#8220;', '&#8221;', '&#8216;', '&#8217;'],
    };
    if ((node.type == 'asciimath' || node.type == 'latexmath') &&
        _typesetMath) {
      final latex = node.type == 'latexmath';
      if (_inlineMath(node.text ?? '', latex: latex) case final image?) {
        return image;
      }
    }
    switch (node.type) {
      case 'emphasis':
        (open, close) = ('<em>', '</em>');
      case 'strong':
        (open, close) = ('<strong>', '</strong>');
      case 'monospaced' || 'asciimath' || 'latexmath':
        if (node.type != 'monospaced') _warnMathAsSource();
        (open, close) = ('<code>', '</code>');
      case 'superscript':
        (open, close) = ('<sup>', '</sup>');
      case 'subscript':
        (open, close) = ('<sub>', '</sub>');
      case 'double':
        (open, close) = (quoteChars[0], quoteChars[1]);
        isTag = false;
        quotes = true;
      case 'single':
        (open, close) = (quoteChars[2], quoteChars[3]);
        isTag = false;
        quotes = true;
      case 'mark':
        (open, close) = ('<mark>', '</mark>');
      default:
        (open, close) = ('', '');
        isTag = false;
    }
    var inner = node.text ?? '';
    if (quotes &&
        inner.length > 3 &&
        inner.endsWith('...') &&
        !inner.substring(0, inner.length - 3).endsWith(r'\')) {
      inner = '${inner.substring(0, inner.length - 3)}&#8230;';
    }
    final String quoted;
    if (node.role case final roles?) {
      // Spaces kept: each but the last of a run gets a zero width space
      // after it, which isn't collapsed.
      if (node.hasRole('pre-wrap') && inner.contains('  ')) {
        inner = inner.replaceAll(RegExp(' (?= )'), ' \u200b');
      }
      quoted = isTag
          ? '${open.substring(0, open.length - 1)} class="$roles">$inner$close'
          : '<span class="$roles">$open$inner$close</span>';
    } else {
      quoted = '$open$inner$close';
    }
    final anchor = node.id != null ? '<a id="${node.id}">$_dummyText</a>' : '';
    // A side note: marked here, its text substituted with the rest (the
    // macros in it are still to come), then taken out of its line.
    if (_sideRole(node) case final role?) {
      return '$anchor<side id="$sideNoteAnchorPrefix${++_sideCount}" '
          'role="$role">'
          '$quoted</side>';
    }
    return '$anchor$quoted';
  }

  /// The first role of [node] the theme sets beside the text
  /// (`role_<role>_display: side`), as a theme key part; not in
  /// asciidoctor-pdf compatibility.
  String? _sideRole(Inline node) {
    if (node.role == null || asciidoctorCompat(_document, CompatFormat.pdf)) {
      return null;
    }
    for (final role in node.roles) {
      final key = role.replaceAll('-', '_');
      if (_keys('role_$key').string('display') == 'side') return key;
    }
    return null;
  }
}
