part of '../converter.dart';

// The document.

extension _DocumentParts on PdfConverter {
  /// Converts [document] to PDF bytes (kept for [write]); returns nothing.
  String convertDocument(Document document) {
    // The gem converts the title for the document information before its
    // PDF state exists (and the title keeps that conversion).
    _document = document;
    document.doctitle();
    _converting = true;
    PdfConverter._promotePreface(document);
    for (final name in const ['outline', 'outline-title', 'pagenums']) {
      if (document.attributeUnspecified(name)) {
        document.attributes[name] = '';
      }
    }
    _phases = document.timings;
    _bytes = _save = null;
    _awaiting.clear();
    _parallel = workersAwaited
        ? Parallel.forAttribute(document.attr('jobs'))
        : null;
    _phase('pdf walk');
    _theme = PdfConverter._prepareTheme(_loadTheme(document));
    _ready = true;
    _fonts = FontCatalog(
      _theme,
      fontsDir: document
          .attr('pdf-fontsdir')
          ?.replaceAll('{docdir}', document.attr('docdir') ?? ''),
      shaping: _shaping,
      synthesizeFaces: true,
      thousandthWidths: _thousandthWidths,
      kernTableOnly: _kernTableOnly,
      singleByteFonts: _singleByteFonts,
      warn: logger.warn,
    );
    _rootFontSize = (_n('base_font_size') ?? 12).toDouble();
    final (_, pageHeight) = _pageSize(document);
    // The inline images (and why some can't be) are kept: titles are
    // converted while the document is parsed, before this.
    _text = TextContext(
      fonts: _fonts,
      rootSize: _rootFontSize,
      fallbacks: _theme.fontFallbacks,
      images: (src, format) =>
          (_inlineGraphics[src], _imageProblems[src] ?? 'not an image'),
      boundsHeight: pageHeight - _pageMargins(document).vertical,
      decorationWidth: (_n('base_text_decoration_width') ?? 1).toDouble(),
      // (`base_font_expansion`: true for microtype's 2%, or a fraction;
      // `base_hyphenate_limit_lines`: the most hyphenated lines in a row;
      // modern engine.)
      expansion: asciidoctorCompat(document, CompatFormat.pdf)
          ? 0
          : switch (_theme.value('base_font_expansion')) {
              ThemeBool(value: true) => 0.02,
              ThemeNumber(:final value) when value > 0 => value.toDouble(),
              _ => 0,
            },
      // (`base_last_line_min_width`: a fraction or a percentage of the
      // measure a paragraph's last line fills at least.)
      lastLineMin: asciidoctorCompat(document, CompatFormat.pdf)
          ? 0
          : switch (_theme.value('base_last_line_min_width')) {
              ThemeNumber(:final value) when value > 0 && value < 1 =>
                value.toDouble(),
              ThemeString(:final value) when value.trim().endsWith('%') =>
                (double.tryParse(value.trim().replaceFirst('%', '')) ?? 0) /
                    100,
              _ => 0,
            },
      maxHyphenRun: asciidoctorCompat(document, CompatFormat.pdf)
          ? null
          : switch (_n('base_hyphenate_limit_lines')) {
              final limit? when limit >= 1 => limit.toInt(),
              _ => null,
            },
      // (`caps_letter_spacing`, modern engine: capitals and small capitals
      // letterspaced, 0.05em as microtype's.)
      capsTracking: asciidoctorCompat(document, CompatFormat.pdf)
          ? 0
          : switch (_theme.value('caps_letter_spacing')) {
              ThemeNumber(:final value) => value / _rootFontSize,
              ThemeString(:final value) when value.trim().endsWith('em') =>
                double.tryParse(value.trim().replaceFirst('em', '')) ?? 0,
              _ => 0,
            },
      lineBreaking: switch (_choice('base_line_breaking', const [
        'auto',
        'optimal',
        'greedy',
        'segments',
      ])) {
        'optimal' => LineBreaking.optimal,
        'greedy' => LineBreaking.greedy,
        'segments' => LineBreaking.segments,
        _ => LineBreaking.auto,
      },
      // (As the language's orthography has it; the gem never repeats a
      // hyphen.)
      hyphenRepetition: asciidoctorCompat(document, CompatFormat.pdf)
          ? HyphenRepetition.none
          : HyphenRepetition.forLanguage(document.attr('lang')),
      typographicScripts:
          _theme.value('base_typographic_scripts') == const ThemeBool(true),
      labels: (key) => _layoutLabels[key],
      logger: logger,
    );
    _markup = MarkupTransform(
      theme: _theme,
      invertEmphasis: _invertEmphasis,
      keepIndexSpace: true,
    );
    _cjkLineBreaks = document.attr('scripts') == 'cjk';
    _resolveHyphenation(document);
    _reportTags =
        (document.hasAttr('pdf-layout-report') ||
            document.hasAttr('pdf-page-map'))
        ? {}
        : null;
    _baseTextAlign = switch (document.attr('text-align')) {
      final align?
          when const {'justify', 'left', 'center', 'right'}.contains(align) =>
        align,
      _ => _s('base_text_align') ?? 'left',
    };
    _font = _FontState(
      family: _s('base_font_family') ?? 'Helvetica',
      style: PdfConverter._fontStyle(_s('base_font_style')) ?? 'normal',
      size: _rootFontSize,
      color: _c('base_font_color'),
      lineHeight: (_n('base_line_height') ?? 1).toDouble(),
      kerning: _s('base_font_kerning') != 'none',
    );
    // (`base_line_pitch`, modern engine: the body's lines that far apart,
    // whatever the face's height, as a pleading's are 24 pt: the line
    // height that gives it, from the pitch at two.)
    _pitchedHeights.clear();
    if (_length('base_line_pitch', _rootFontSize) case final pitch?
        when !asciidoctorCompat(document, CompatFormat.pdf)) {
      _font = _pitched(_font, pitch);
    }
    _sections.clear();
    _hungLabels.clear();
    _quotationChecks.clear();
    _engineParagraphCount = 0;
    _sideFloated = false;
    _gutterLeast = 0;
    _thematicBreaks = 0;
    _madeUpAnchors.clear();
    _floatGroup = _floatNext = null;
    _hasTitlePage = _frontCover = _backCover = _noCover = false;
    _runningBackgrounds.clear();
    _importedPages.clear();
    _layout = _initialLayout(document);
    _indexSlot = null;
    _renderedFootnotes.clear();
    _bibrefRefs.clear();
    _footnoteLabels.clear();
    _out = [];

    // The document title, on a page of its own or above the content.
    final book = document.doctype == 'book';
    final media = document.attr('media') ?? 'screen';
    _ppbook = media == 'prepress' && book;
    _folio = switch (document.attr('pdf-folio-placement') ??
        (media == 'prepress' ? 'physical' : 'virtual')) {
      'physical' => (physical: true, inverted: false),
      'physical-inverted' => (physical: true, inverted: true),
      'virtual-inverted' => (physical: false, inverted: true),
      _ => (physical: false, inverted: false),
    };
    final titlePage = book || document.hasAttr('title-page');
    _frontCover = _cover('front');
    if (titlePage &&
        document.hasHeader &&
        !document.notitle &&
        _theme['title_page'] is! ThemeBool) {
      if (_ppbook) _out.add(const BreakBox.page(side: PageSide.recto));
      _titlePage(document);
      _out.add(const BreakBox.page());
      _hasTitlePage = true;
    }
    if (!titlePage) _out.add(PdfConverter._bodyMarker());
    // (`title_page_inline`, modern engine: an article's title page set at
    // the top of its first page, its slots in place of the title.)
    final inlineTitle =
        !titlePage &&
        document.hasHeader &&
        !document.notitle &&
        _theme['title_page_inline'] == const ThemeBool(true) &&
        !asciidoctorCompat(document, CompatFormat.pdf);
    if (inlineTitle) {
      _titleSlotsInto(
        document,
        _titleSlots('recto'),
        _s('title_page_text_align') ?? _baseTextAlign,
        0,
      );
      final gap = _length('title_page_inline_margin_bottom', _rootFontSize);
      _out.add(SpacerBox(gap ?? _rootFontSize * 1.5));
    } else if (!titlePage && document.hasHeader && !document.notitle) {
      final title = document.doctitle();
      if (title != null) {
        _heading(
          title,
          level: 1,
          align: _s('heading_h1_text_align') ?? 'center',
        );
      }
    }
    final placement = document.attr('toc-placement');
    final tocAtTop =
        document.hasAttr('toc') &&
        placement != 'macro' &&
        placement != 'preamble' &&
        _sectionsOf(document).isNotEmpty;
    _tocAtTop = tocAtTop;
    _tocDone = false;
    _tocNoHeader = _tocNoFooter = false;
    _notes.clear();
    _sideNotes.clear();
    // (`index-sort`, modern engine: Chicago's letter-by-letter or
    // word-by-word order.)
    _index.order = asciidoctorCompat(document, CompatFormat.pdf)
        ? IndexOrder.asciidoctor
        : IndexOrder.of(document);
    _noteStreamOf.clear();
    _sideNoteStreamOf.clear();
    _sideNoteTexts.clear();
    _sideCount = 0;
    _layoutLabels.clear();
    // The table of contents and the body, indented by the theme's
    // section indent (the gem's `indent_section`).
    final indented = _collect(() {
      if (tocAtTop) {
        if (_ppbook) _out.add(const BreakBox.page(side: PageSide.recto));
        _addToc(
          'toc',
          breakAfter: titlePage && _s('toc_break_after') != 'auto',
        );
      }
      if (_ppbook &&
          !PdfConverter._firstBlockOf(document).hasOption('nonfacing')) {
        _out
          ..add(
            const CustomBox(
              _Nothing(),
              style: BoxStyle(anchor: PdfConverter._beforeBodyAnchor),
            ),
          )
          ..add(const BreakBox.page(side: PageSide.recto));
      }
      if (titlePage) _out.add(PdfConverter._bodyMarker());
      final columns = (_n('page_columns') ?? 1).toInt();
      _inColumns = !book && columns >= 2;
      // A book's chapters in columns, their headings across them (the
      // modern engine's; the gem sets a book in one column).
      _bookColumns =
          book && columns >= 2 && !asciidoctorCompat(document, CompatFormat.pdf)
          ? columns
          : 0;
      _lineNumbering = _lineNumberingOf(document);
      _pageColumns = null;
      if (_inColumns && _columnFootnotes) {
        // (The page's own columns: each a region with its notes at its
        // foot, as the Federal Register sets a note under the column its
        // reference is in.)
        final gap = (_n('page_column_gap') ?? _rootFontSize).toDouble();
        _columnWidth = _columnWidthOf(columns, gap);
        _pageColumns = (columns, gap);
        _numbered(() {
          _manNameSection(document);
          _traverse(document);
        });
        _footnotes(document);
      } else if (_inColumns) {
        final gap = (_n('page_column_gap') ?? _rootFontSize).toDouble();
        _columnWidth = _columnWidthOf(columns, gap);
        final body = _collect(() {
          _numbered(() {
            _manNameSection(document);
            _traverse(document);
          });
          _footnotes(document);
        });
        _out.add(
          ColumnsBox(
            body,
            count: columns,
            gap: gap,
            // (`page_columns_balance`, modern engine: the last page's
            // columns as even as they can be, as a piece ends.)
            balance:
                _theme['page_columns_balance'] == const ThemeBool(true) &&
                !asciidoctorCompat(document, CompatFormat.pdf),
            rule: _columnRule('page_column'),
          ),
        );
      } else {
        _numbered(() {
          _manNameSection(document);
          _traverse(document);
        });
        _footnotes(document);
      }
    });
    if (_sectionIndent case (final left, final right)) {
      _out.add(
        BlockBox(
          indented,
          style: BoxStyle(
            margin: EdgeInsets(left: left, right: right),
          ),
        ),
      );
    } else {
      _out.addAll(indented);
    }
    _backCover = false;
    final backCover = _resolveBackgroundImage(
      'back-cover-image',
      themeKey: 'cover_back_image',
      symbols: const ['', '~'],
    );
    if (backCover?.image?.graphic case final ImportedPage page) {
      _importPage(page, advance: false);
      _backCover = true;
    } else if (backCover != null && backCover.symbol != '~') {
      _out.add(const BreakBox.page());
      if (backCover.image case final image?) {
        _out.add(
          CustomBox(
            _Absolute((page) => _drawPageImage(page.canvas, image), fill: true),
          ),
        );
      } else {
        _out.add(CustomBox(_Absolute((_) {}, fill: true)));
      }
      _backCover = true;
    }

    PageTemplate templateFor(String layout) {
      final (width, height) = _layoutSize(document, layout);
      return PageTemplate(
        Rect(0, 0, width, height),
        margins: _marginsFor(document, layout),
        columns: _pageColumns?.$1 ?? 1,
        columnGap: _pageColumns?.$2 ?? 12,
        header: _header,
        footer: _footer,
        // (`running_content_layer: over`: the header painted after the
        // page's content, as the footer is.)
        runningOver:
            _choice('running_content_layer', const ['under', 'over']) == 'over',
        background: _pageBackground,
        foreground: _pageForeground,
        bleed: _bleed,
      );
    }

    final templates = {
      for (final layout in const ['portrait', 'landscape'])
        layout: templateFor(layout),
      for (final role in _pageRoles)
        'section-role-$role': _pageRoleTemplate(role, templateFor),
      for (final MapEntry(:key, value: page) in _importedPages.entries)
        key: PageTemplate(
          Rect(0, 0, page.intrinsicWidth, page.intrinsicHeight),
          margins: EdgeInsets.zero,
          background: (canvas, info) => page.paint(canvas, info.template.size),
        ),
    };
    final layout = FlowLayout(
      // (Paragraphs the engine sets, `base_text_engine: paragraph`: broken
      // as the text box breaks justified text, Knuth and Plass's total fit
      // with TeX's costs and 2em of emergency stretch.)
      lineBreaker: _engineParagraphs
          ? KnuthPlassLineBreaker(
              emergencyStretch: 2 * _rootFontSize,
              expansion: _text.expansion,
              maxHyphenRun: _text.maxHyphenRun,
              lastLineMin: _text.lastLineMin,
            )
          : const FirstFitLineBreaker(),
      template: templates[_initialLayout(document)],
      templates: templates,
      keepTemplate: true,
      pageLabel: _pageLabel,
      notes: _notes,
      noteSeparator: _notes.isEmpty ? null : _footnoteSeparator(),
      noteStreams: _layoutNoteStreams(),
      noteStreamOf: _noteStreamOf,
      // (Notes in step with their text, modern engine: the least lines of
      // text a page with notes keeps, `footnotes_text_min_lines`, and how
      // many pages after its reference's a note may start,
      // `footnotes_lag`: a study Bible's notes.)
      notesMinText: asciidoctorCompat(document, CompatFormat.pdf)
          ? null
          : switch (_n('footnotes_text_min_lines')) {
              final lines? =>
                lines *
                    _rootFontSize *
                    (_n('base_line_height') ?? 1).toDouble(),
              null => null,
            },
      notesLag: asciidoctorCompat(document, CompatFormat.pdf)
          ? null
          : _n('footnotes_lag')?.toInt(),
      sideNotes: _sideNotes,
      sideNoteStreams: _layoutSideNoteStreams(sided: media == 'prepress'),
      sideNoteStreamOf: _sideNoteStreamOf,
      sideColumn: _sideNotes.isEmpty
          ? null
          : (number, template) =>
                _sideColumn(number, template, sided: media == 'prepress'),
      sideNoteGap:
          _length('side_notes_item_spacing', _rootFontSize) ??
          _rootFontSize / 4,
      baselineGrid: _baselineGrid(),
      // (`pagination: optimal`, modern engine: the pages' breaks chosen
      // together.)
      pagination:
          !asciidoctorCompat(document, CompatFormat.pdf) &&
              _choice('pagination', const ['first_fit', 'optimal']) == 'optimal'
          ? Pagination.optimal
          : Pagination.firstFit,
      templateForPage: media == 'prepress'
          ? (template, number) => _sidedTemplate(
              template,
              number,
              sided: _sidedLayouts(document).map((l) => templates[l]!).toSet(),
              cover: number == 1 && _hasTitlePage && !_frontCover && !_noCover,
            )
          : null,
    );
    if (PdfConverter.onWalked case final walked?) {
      _phase(null);
      walked(layout, _out);
      return '';
    }
    _phase('pdf layout');
    var result = layout.layout(_out);
    // Where the body, the table of contents and each anchor are, and the
    // front matter they make.
    void measure() {
      _bodyStart =
          (result.anchors[PdfConverter._bodyAnchor]?.page ?? result.pageCount) +
          1;
      _blankBeforeBody = _blankBefore(result);
      _anchorPages = {
        for (final MapEntry(:key, :value) in result.anchors.entries)
          key: value.page + 1,
      };
      _tocPages = switch ((
        result.anchors[PdfConverter._tocStartAnchor],
        result.anchors[PdfConverter._tocEndAnchor],
      )) {
        (final start?, final end?) => (start.page + 1, end.page + 1),
        _ => null,
      };
      _skip = _frontMatter(titlePage: titlePage);
      _openerPages = {
        for (final (section, anchor) in _sections)
          if (_opensPages(section)) ?_anchorPages[anchor],
      };
      _pageMarks = _marksByPage(result, pageCount: result.pageCount);
      _pageUnits = _unitsByPage(result, pageCount: result.pageCount);
    }

    measure();
    // `page_margin_gutter: kdp` (with `media=prepress`): the inner margin
    // KDP asks for at least at the book's page count (24-150 pages 0.375
    // in, to 300 0.5, to 500 0.625, to 700 0.75, more 0.875), laid out
    // again when the count calls for a wider one.
    if (media == 'prepress' &&
        _s('page_margin_gutter') == 'kdp' &&
        !asciidoctorCompat(document, CompatFormat.pdf)) {
      for (var pass = 0; pass < 2; pass++) {
        final least = _kdpGutter(result.pageCount);
        if (least <= _gutterLeast) break;
        _gutterLeast = least;
        _phase('pdf layout (gutter)');
        result = layout.layout(_out);
        measure();
      }
    }
    // The index, once the pages of its terms are known.
    if (_indexSlot case final slot?) {
      _phase('pdf layout (index)');
      _fillIndex(slot);
      // (Laid out again from the top-level box holding the index on.)
      final at = _out.indexWhere(
        (box) => box is BlockBox && identical(box.children, slot),
      );
      result = layout.layout(
        _out,
        reuse: at < 0 ? null : result,
        unchangedBefore: at < 0 ? 0 : at,
      );
      measure();
    }
    // Footnotes numbered on each page: numbered from where their
    // references are, then laid out again until the numbers stay.
    if (_footnoteNumbering == 'page') {
      for (var pass = 0; pass < 3; pass++) {
        final changed = _numberFootnotesByPage(result);
        if (changed.isEmpty) break;
        _phase('pdf layout (footnotes)');
        // Laid out again from the first page with a new number on, the
        // runs of pages without one kept (unless a reference without an
        // anchor has one: where it is isn't known).
        final pages = {
          for (final index in changed) ...[
            ...result.anchorPages('_footnoteref_$index'),
            ...result.anchorPages('_footnotedef_$index'),
          ],
        };
        result = layout.layout(
          _out,
          reuse: result,
          unchangedBefore: result.boundaryBefore(pages.reduce(math.min)),
          changedPages: changed.any(_unanchoredFootnotes.contains)
              ? null
              : pages,
        );
        measure();
      }
    }
    _unanchoredFootnotes.clear();
    // How the document opens (the gem's `PageModes`).
    final (pageMode, nonFullScreen) = switch (document.attr('pdf-page-mode') ??
        _s('page_mode')) {
      'fullscreen' ||
      'fullscreen outline' => (PageMode.fullScreen, PageMode.useOutlines),
      'fullscreen none' => (PageMode.fullScreen, PageMode.useNone),
      'fullscreen thumbs' => (PageMode.fullScreen, PageMode.useThumbs),
      'none' => (PageMode.useNone, null),
      'thumbs' => (PageMode.useThumbs, null),
      _ => (PageMode.useOutlines, null),
    };
    final standard = _pdfStandard(document);
    final info = _info(document);
    final pdf = PdfDocument(
      info: standard == null
          ? info
          : PdfInfo(
              title: info.title,
              author: info.author,
              subject: info.subject,
              keywords: info.keywords,
              creator: info.creator,
              producer: info.producer,
              trapped: false,
              pdfxVersion: 'PDF/X-4',
              identifier: info.identifier,
              contributors: info.contributors,
              rights: info.rights,
            ),
      pageMode: pageMode,
      nonFullScreenPageMode: nonFullScreen,
      displayTitle: true,
      language: document.attr('lang'),
    );
    if (standard != null) pdf.outputIntents.add(standard);
    _phase('pdf render');
    // A side note no page's side column has room for is left out: say so.
    for (final name in result.unsetSideNotes) {
      final (role, text) = _sideNoteTexts[name] ?? ('', name);
      logger.warn(
        'side note left out: no room for it in the side column'
        '${role.isEmpty ? '' : ' (role $role)'}: $text',
      );
    }
    _lintBlockQuotations(result);
    _lineCount = 0;
    _lineRestarts = _lineNumbering == null ? const [] : _lineRestartsOf(result);
    _hungAt = [
      for (final MapEntry(key: id, value: (text, font)) in _hungLabels.entries)
        if (result.anchors[id] case final at?)
          (at.page + 1, at.y, at.x, text, font),
    ];
    final pages = result.render(pdf, destinationName: destinationName);
    _compressingElsewhere(pages);
    if (standard != null) _preflight(standard);
    _layoutReport(document, result);
    _pageMap(document, result, pages.length);
    logger.info(
      'laid out ${pages.length} ${pages.length == 1 ? 'page' : 'pages'}',
    );
    if (_engineParagraphs) {
      logger.debug('paragraphs set by the engine: $_engineParagraphCount');
    }
    _outline(pdf, pages, result);
    if (pages.isNotEmpty) {
      final first = pages.first;
      pdf.openAction = switch (_s('page_initial_zoom')) {
        'Fit' => PdfDestination.fit(first),
        'FitV' => PdfDestination.fitHeight(first, left: 0),
        'FitH' => PdfDestination.fitWidth(first, top: pages.last.height),
        _ => null,
      };
    }
    // The same document makes the same bytes: the file identifier comes
    // from the content, the dates from the document's local date and time
    // (SOURCE_DATE_EPOCH, when set), as the gem dates it.
    _phase(null);
    final creationDate = PdfConverter._dateTime(document.attr('localdatetime'));
    _save = () {
      _phase('pdf save');
      final bytes = pdf.save(
        options: PdfConverter._writerOptions(
          nativeZlib: io.hasNativeZlib,
          creationDate: creationDate,
        ),
      );
      _phase(null);
      return bytes;
    };
    return '';
  }

  /// Ends the running phase (recording its time) and starts [name], if
  /// given.
  void _phase(String? name) {
    final timings = _phases;
    if (timings == null) return;
    if (_runningPhase case final running?) timings.record(running);
    _runningPhase = name;
    if (name != null) timings.start(name);
  }

  /// Draws the logo of the title page, if any, where the theme puts it
  /// (it takes no room; the gem's logo in `ink_title_page`).
  void _titleLogo(Document doc, String titleAlign) {
    if (_s('title_page_logo_display') == 'none') return;
    final fromDocument = doc.attr('title-logo-image');
    final value = fromDocument ?? _s('title_page_logo_image');
    if (value == null) return;
    var target = value;
    var attrs = <String, String>{};
    if (PdfConverter._imageMacroOf(value, const ['alt', 'width', 'height'])
        case (final macroTarget, final macroAttrs)?) {
      target = macroTarget;
      attrs = {...macroAttrs};
    }
    if (fromDocument == null) {
      target = _applySubsDiscretely(
        target,
        const {},
        subs: const [Sub.attributes],
      );
    }
    final format = PdfConverter._imageFormat(target);
    if (format == 'pdf') {
      logger.error(
        'PDF format not supported for title page logo image: $target',
      );
      return;
    }
    const aligns = {'left', 'center', 'right'};
    final align =
        [
          attrs.remove('align'),
          _s('title_page_logo_align'),
          titleAlign,
        ].whereType<String>().where(aligns.contains).firstOrNull ??
        'left';
    final bytes = fromDocument != null
        ? _imageBytes(doc, target)
        : _themeImageBytes(target);
    final (graphic, problem) = bytes == null
        ? (null, null)
        : _graphicOf(bytes, format, path: _lastImagePath);
    if (bytes == null && fromDocument == null) {
      logger.warn(
        'image to embed not found or not readable: '
        '${_themeImagePath(target) ?? target}',
      );
    } else if (graphic == null && problem != null) {
      logger.warn('could not embed image: $target; $problem');
    }
    final topValue = switch (attrs['top']) {
      final top? => ThemeString(top),
      null => _theme['title_page_logo_top'],
    };
    final top = topValue == null ? 0.0 : _titlePageTop(topValue);
    final left = (_n('title_page_logo_margin_left') ?? 0).toDouble();
    final right = (_n('title_page_logo_margin_right') ?? 0).toDouble();
    final (pageWidth, pageHeight) = _pageSize(doc);
    final margins = _pageMargins(doc);
    // An image that can't be embedded: its alt text in its place (the
    // gem's `on_image_error`).
    final CustomContent content;
    if (graphic == null) {
      final path = fromDocument != null
          ? _imagePath(doc, target) ?? target
          : _themeImagePath(target) ?? target;
      final template =
          _s('image_alt_content') ??
          '%{link}[%{alt}]%{/link} | <em>%{target}</em>';
      if (template.isEmpty) return;
      final link = attrs['link'];
      final text = template
          .replaceAll('%{link}', link == null ? '' : '<a href="$link">')
          .replaceAll('%{/link}', link == null ? '' : '</a>')
          .replaceAll('%{alt}', attrs['alt'] ?? '')
          .replaceAll('%{target}', path);
      content = _textBox(
        text,
        _themeFont('image_alt', _font),
        align: align,
        normalize: false,
      );
    } else {
      content = _ImageContent(
        graphic,
        width: _imageWidthOf((name) => attrs[name]),
        align: align,
        pageWidth: pageWidth,
      );
    }
    _out.add(
      CustomBox(
        _Absolute((page) {
          // Scaled down to fit the page below its top, as the gem fits it.
          final placed = content.place(
            pageWidth - margins.horizontal - left - right,
            math.max(0, pageHeight - margins.vertical - top),
            atTop: true,
          );
          placed?.paint(
            page,
            margins.left + left,
            pageHeight - margins.top - top,
          );
        }),
      ),
    );
  }

  /// The distance from the top of the content area that the title page
  /// value [value] gives (the gem's `resolve_top` on a new page).
  double _titlePageTop(ThemeValue value) {
    final (_, pageHeight) = _pageSize(_document);
    final margins = _pageMargins(_document);
    final contentHeight = pageHeight - margins.vertical;
    switch (value) {
      case ThemeNumber(:final value):
        return value.toDouble();
      case final other:
        final text = other.rubyString;
        if (text.endsWith('vh')) {
          final top = pageHeight * (1 - PdfConverter._toF(text) / 100);
          return pageHeight - margins.top - top;
        }
        if (text.endsWith('%')) {
          return contentHeight * PdfConverter._toF(text) / 100;
        }
        return strToPoints(text);
    }
  }

  /// The title page's slots on [side] (`recto`, `verso`): the theme's
  /// `title_page_<side>` (ADR-0023), else the gem's fixed order on the
  /// recto and no verso.
  List<_TitleSlot> _titleSlots(String side) =>
      switch (_keys('title_page').value(side)) {
        ThemeList(:final values) => [
          for (final value in values)
            switch (value) {
              ThemeMap(:final entries) => _TitleSlot(
                part: switch (entries['content']) {
                  final ThemeValue part => _titlePart(part.rubyString),
                  null => null,
                },
                attribute: entries['attribute']?.rubyString,
                role: entries['role']?.rubyString,
                marginTop: switch (entries['margin_top']) {
                  ThemeNumber(:final value) => value.toDouble(),
                  _ => null,
                },
                marginBottom: switch (entries['margin_bottom']) {
                  ThemeNumber(:final value) => value.toDouble(),
                  _ => null,
                },
                before: entries['before']?.rubyString,
                separator: entries['separator']?.rubyString,
              ),
              final part => _TitleSlot.part(_titlePart(part.rubyString)),
            },
        ],
        _ when side == 'recto' => [
          for (final part in TitlePart.values) _TitleSlot.part(part),
        ],
        _ => const [],
      };

  /// The part [name] names; null for an unknown name (the slot shows
  /// nothing).
  TitlePart? _titlePart(String name) =>
      TitlePart.values.asNameMap()[name] ??
      () {
        logger.warn('unknown title page part: $name');
        return null;
      }();

  /// Adds the title page of [doc]: its slots (the theme's
  /// `title_page_recto`; by default the title, subtitle, authors and
  /// revision, as the gem's `ink_title_page`), and a verso, when the
  /// theme gives `title_page_verso`, on the page after it.
  void _titlePage(Document doc) {
    final align = _s('title_page_text_align') ?? _baseTextAlign;
    final recto = _titleSlots('recto');
    if (recto.any((slot) => slot.part == TitlePart.logo)) {
      _titleLogo(doc, align);
    }
    // (Slots the theme lists are placed by their margins alone; the gem's
    // order starts at `title_page_title_top`.)
    var offset = 0.0;
    if (_theme['title_page_title_top'] case final top?
        when _theme.value('title_page_recto') == null) {
      offset = _titlePageTop(top);
    }
    _titleSlotsInto(doc, recto, align, offset);
    final verso = _titleSlots('verso');
    if (verso.isNotEmpty) {
      _out.add(const BreakBox.page());
      _titleSlotsInto(doc, verso, align, 0);
    }
  }

  /// Adds [slots] of [doc]'s title page, [top] below the top.
  void _titleSlotsInto(
    Document doc,
    List<_TitleSlot> slots,
    String align,
    double top,
  ) {
    var offset = top;
    final base = _themeFont('title_page', _font);
    void gap(double points) {
      if (points != 0) offset += points;
    }

    void prose(
      String text,
      String category, {
      bool normalize = true,
      String? role,
    }) {
      var font = _themeFont(category, base);
      if (role != null) font = _themeFont('role_$role', font);
      var content = text;
      if (font.transform case final transform? when transform != 'none') {
        content = transformText(content, transform);
      }
      final left = (_keys(category).number('margin_left') ?? 0).toDouble();
      final right = (_keys(category).number('margin_right') ?? 0).toDouble();
      // The modern engine: the text sheared as a block, by an angle in
      // degrees leaning right (`<category>_skew`).
      final degrees = _keys(category).number('skew');
      _out.add(
        BlockBox(
          [
            CustomBox(
              _textBox(
                content,
                font,
                align: align,
                normalize: normalize,
                skew: degrees == null
                    ? null
                    : math.tan(degrees.toDouble() * math.pi / 180),
              ),
            ),
          ],
          style: BoxStyle(
            padding: EdgeInsets(top: offset),
            margin: EdgeInsets(left: left, right: right),
          ),
        ),
      );
      offset = 0;
    }

    /// [text] in [slot], styled by [category], within the slot's margins
    /// (else the category's).
    void place(
      _TitleSlot slot,
      String text,
      String category, {
      bool normalize = true,
    }) {
      gap(
        slot.marginTop ??
            (_keys(category).number('margin_top') ?? 0).toDouble(),
      );
      prose(
        '${slot.before ?? ''}$text',
        category,
        normalize: normalize,
        role: slot.role,
      );
      gap(
        slot.marginBottom ??
            (_keys(category).number('margin_bottom') ?? 0).toDouble(),
      );
    }

    final title = doc.partitionedTitle(separator: doc.attr('title-separator'));
    // (The whole title, when no slot shows the subtitle.)
    final subtitled = slots.any((slot) => slot.part == TitlePart.subtitle);
    for (final slot in slots) {
      switch (slot) {
        case _TitleSlot(part: TitlePart.title)
            when _s('title_page_title_display') != 'none' && title != null:
          place(
            slot,
            subtitled ? title.main : title.combined,
            'title_page_title',
          );
        case _TitleSlot(part: TitlePart.subtitle)
            when _s('title_page_subtitle_display') != 'none':
          if (title?.subtitle case final subtitle?) {
            place(slot, subtitle, 'title_page_subtitle');
          }
        case _TitleSlot(part: TitlePart.authors)
            when _s('title_page_authors_display') != 'none' &&
                doc.hasAttr('authors'):
          place(slot, _titleAuthors(doc, slot.separator), 'title_page_authors');
        case _TitleSlot(part: TitlePart.revision)
            when _s('title_page_revision_display') != 'none':
          final revision = [
            if (doc.attr('revnumber') case final number?)
              '${doc.attr('version-label') ?? ''} $number',
            ?doc.attr('revdate'),
          ];
          if (revision.isEmpty) continue;
          var text = revision.join(
            slot.separator ?? _s('title_page_revision_delimiter') ?? ', ',
          );
          if (doc.attr('revremark') case final remark?) text = '$text: $remark';
          place(slot, text, 'title_page_revision', normalize: false);
        case _TitleSlot(part: null, attribute: final name?):
          if (doc.attr(name) case final value? when value.isNotEmpty) {
            place(slot, value, 'title_page');
          }
        case _:
      }
    }
  }

  /// The title page's authors, each by the theme's content template,
  /// joined by [separator] (else the theme's delimiter).
  String _titleAuthors(Document doc, String? separator) {
    final generic = _s('title_page_authors_content');
    final templates = {
      'name_only': _s('title_page_authors_content_name_only') ?? generic,
      'with_email': _s('title_page_authors_content_with_email') ?? generic,
      'with_url': _s('title_page_authors_content_with_url') ?? generic,
    };
    // Each author's content, with the author's attributes in effect
    // (the gem's `with_author`): `url` is the email as a mailto: link,
    // or the URL in its place.
    final names = [
      for (final (i, author) in doc.authors.indexed)
        () {
          final attributes = <String, String>{};
          final unset = <String>{'url'};
          String? email;
          if (i == 0) {
            email = doc.attr('email');
          } else {
            for (final (name, value) in [
              ('author', author.name),
              ('authorinitials', author.initials),
              ('firstname', author.firstname),
              ('middlename', author.middlename),
              ('lastname', author.lastname),
              ('email', author.email),
            ]) {
              if (value == null) {
                unset.add(name);
              } else {
                attributes[name] = value;
              }
            }
            email = author.email;
          }
          String? url;
          if (email != null) {
            url = email.contains('@') ? 'mailto:$email' : email;
            attributes['url'] = url;
            unset.remove('url');
          }
          final key = url == null
              ? 'name_only'
              : url.startsWith('mailto:')
              ? 'with_email'
              : 'with_url';
          final template = templates[key];
          if (template == null) {
            return i == 0
                ? doc.attr('author') ?? ''
                : attributes['author'] ?? '';
          }
          return _applySubsDiscretely(
            template,
            attributes,
            unset: unset,
            dropLines: true,
          );
        }(),
    ];
    // The delimiter's spaces as they are (a gap between names in a row;
    // the gem collapses them).
    return names.join(
      (separator ?? _s('title_page_authors_delimiter') ?? ', ').replaceAll(
        RegExp(' (?= )'),
        '&#160;',
      ),
    );
  }

  /// Adds the table of contents at [anchor] (the gem's `allocate_toc`):
  /// then a page break when [breakAfter], else the block margin.
  void _addToc(String anchor, {required bool breakAfter, bool titled = true}) {
    _tocDone = true;
    _out
      ..add(CustomBox(const _Nothing(), style: BoxStyle(anchor: anchor)))
      ..add(
        const CustomBox(
          _Nothing(),
          style: BoxStyle(anchor: PdfConverter._tocStartAnchor),
        ),
      );
    _toc(_document, titled: titled);
    _out.add(
      const CustomBox(
        _Nothing(),
        style: BoxStyle(anchor: PdfConverter._tocEndAnchor),
      ),
    );
    if (breakAfter) {
      _out.add(const BreakBox.page());
    } else {
      final margin = (_n('block_margin_bottom') ?? 0).toDouble();
      if (margin > 0) _out.add(SpacerBox(margin));
    }
  }

  /// Converts the toc macro [node], or the table of contents after the
  /// preamble (with [placement] `preamble`), when the document places it
  /// there (the gem's `convert_toc`).
  void convertToc(AbstractBlock node, {String placement = 'macro'}) {
    final doc = _document;
    if (_tocDone ||
        doc.attr('toc-placement') != placement ||
        !doc.hasAttr('toc') ||
        _sectionsOf(doc).isEmpty) {
      return;
    }
    final book = doc.doctype == 'book';
    final macro = placement == 'macro';
    // In the modern engine, a toc macro that opens a section is that
    // section's contents: on its page, under its heading (no title of
    // its own), the section listed as any other (a Contents chapter);
    // unless `toc_macro_in_section` is false.
    final parent = node.parent;
    final ownsSection =
        _theme.value('toc_macro_in_section') != const ThemeBool(false) &&
        macro &&
        parent is Section &&
        parent.blocks.firstOrNull == node;
    if (book && !ownsSection) {
      _out.add(
        BreakBox.page(
          side: _ppbook && !(macro && node.hasOption('nonfacing'))
              ? PageSide.recto
              : null,
        ),
      );
    }
    _addToc(
      macro ? node.id ?? 'toc' : PdfConverter._tocStartAnchor,
      breakAfter: book || doc.hasAttr('title-page'),
      titled: !ownsSection,
    );
    if (macro) {
      _tocNoHeader = node.hasOption('noheader');
      _tocNoFooter = node.hasOption('nofooter');
    }
  }

  /// Whether [section] is a part or chapter of a book whose title is set.
  bool _opensPages(Section section) {
    if (_document.doctype != 'book' ||
        !(section.sectname == 'part' || section.level == 1) ||
        section.hasOption('notitle')) {
      return false;
    }
    // A styled role may keep the running content on its first page
    // (section_role_<role>_running_content_on_openers: a foreword set as
    // an ordinary heading).
    final role = _boxedRole(section);
    return role == null ||
        _keys('section_role_$role').value('running_content_on_openers') !=
            const ThemeBool(true);
  }

  /// The number of levels the table of contents lists (the gem's
  /// `resolve_toclevels`).
  int get _tocLevels {
    final levels = int.tryParse(_document.attr('toclevels') ?? '2') ?? 0;
    if (levels >= 1) return levels;
    return _document.doctype == 'book' &&
            _document.sections.whereType<Section>().any(
              (s) => s.sectname == 'part',
            )
        ? 0
        : 1;
  }

  /// Adds the table of contents of [doc] (the gem's `ink_toc`).
  void _toc(Document doc, {bool titled = true}) {
    final title = doc.attr('toc-title');
    if (titled && title != null && title.isNotEmpty) {
      final font = _themeFont('toc_title', _headingFont(2));
      _heading(
        title,
        level: 2,
        align:
            _s('toc_title_text_align') ??
            _s('heading_h2_text_align') ??
            _s('heading_text_align') ??
            _baseTextAlign,
        font: font,
        outdent: true,
      );
    }
    final levels = _tocLevels;
    if (levels < 0) return;
    final toc = _themeFont('toc', _font);
    var dotStyle =
        PdfConverter._fontStyle(_s('toc_dot_leader_font_style')) ?? 'normal';
    final dotSize = switch (_theme.value('toc_dot_leader_font_size')) {
      ThemeNumber(:final value) => value.toDouble(),
      ThemeString(:final value) => resolveFontSize(
        value,
        toc.size,
        _rootFontSize,
      ),
      _ => toc.size,
    };
    final hanging = (_n('toc_hanging_indent') ?? 0).toDouble();
    final dotFont = toc.copyWith(
      style: dotStyle,
      size: dotSize,
      color: _c('toc_dot_leader_font_color') ?? toc.color,
    );
    final dotLevels = switch (_theme['toc_dot_leader_levels']) {
      ThemeString(value: 'none') => const <int>{},
      ThemeString(value: 'all') || null => null,
      final value => {
        for (final part in value.rubyString.split(RegExp(r'\s+')))
          ?int.tryParse(part),
      },
    };
    final dotText = _s('toc_dot_leader_content') ?? '. ';
    final dotPrawn = _fonts.font(dotFont.family, dotFont.style);
    final dotWidth = dotText.isEmpty
        ? 0.0
        : dotPrawn.widthOf(dotText, dotSize, kerning: dotFont.kerning);
    final spacerSize = dotSize * 0.25;
    final spacerWidth = dotPrawn.widthOf(' ', spacerSize, kerning: false);
    dotStyle = dotFont.style;
    final margin = (_n('toc_margin_top') ?? 0).toDouble();
    if (margin > 0) _out.add(SpacerBox(margin));
    final indent = (_n('toc_indent') ?? 0).toDouble();
    // With lines set from their cap heights (base_leading) each entry is
    // a paragraph of its own: the entries the leading apart
    // (toc_entry_spacing).
    final gap = (_n('toc_entry_spacing') ?? _capLeading(toc) ?? 0).toDouble();
    var first = true;
    void level(List<Section> entries, int levels, double left) {
      for (final entry in entries) {
        // Ptome's `notoc` option: a section left out of the contents.
        if (entry.hasOption('notoc')) continue;
        final entryLevel = (entry.level ?? 0) + 1;
        final entryLevels =
            int.tryParse(entry.attr('toclevels') ?? '') ?? levels;
        if (entryLevels < entryLevel - 1) continue;
        if (entry.hasOption('notitle') &&
            entry == doc.blocks.lastOrNull &&
            entry.blocks.isEmpty) {
          continue;
        }
        // The modern engine's `toc_entry_content` template (ADR-0010):
        // `title`, `numbered-title`, `number`.
        var title = _numberedTitle(entry, formal: false);
        if (_s('toc_entry_content') case final template?) {
          title = _render(template, {
            'title': entry.title,
            'numbered-title': title,
            'number': _isNumbered(entry)
                ? (entry.sectname == 'part' ? entry.numeral : entry.sectnum())
                : null,
          });
        }

        if (title.isEmpty) continue;
        final font = _themeFont('toc_h$entryLevel', toc);
        title = title.replaceAll(RegExp(r'<(?:a\b[^>]*|/a)>'), '');
        if (font.transform case final transform? when transform != 'none') {
          title = transformText(title, transform);
        }
        final anchor = _sectionAnchor(entry);
        final placeholder = _fonts
            .font(font.family, font.style)
            .widthOf('0' * 3, font.size, kerning: font.kerning);
        final showDots =
            dotWidth > 0 &&
            (dotLevels == null || dotLevels.contains(entryLevel - 1));
        final entryBox = CustomBox(
          _TocEntry(
            hanging: hanging,
            // Prawn's alignment (the gem passes none).
            _textBox(
              title,
              font,
              align: 'left',
              indent: -hanging,
              inherit: (_decoration('toc', entryLevel) ?? Fragment(''))
                ..anchor = anchor
                ..color = font.color,
              normalize: false,
              normalizeLineHeight: true,
            ),
            placeholder,
            (width, startDots) {
              final label = anchor == null ? '?' : _anchorLabel(anchor);
              final prawn = _fonts.font(font.family, font.style);
              final labelWidth = prawn.widthOf(
                label,
                font.size,
                kerning: font.kerning,
              );
              // Linked, in the entry's color (not the link color).
              final color = font.color?.rubyString;
              final colored = color == null
                  ? label
                  : '<font color="$color">$label</font>';
              final number = anchor == null
                  ? label
                  : '<a anchor="$anchor">$colored</a>';
              final String markup;
              if (showDots) {
                final dots = math.max(
                  ((width - startDots - spacerWidth - labelWidth) / dotWidth)
                      .floor(),
                  0,
                );
                final dotColor = dotFont.color?.rubyString;
                markup =
                    '<font name="${dotFont.family}" size="$dotSize"'
                    '${dotColor == null ? '' : ' color="$dotColor"'}>'
                    '${PdfConverter._styled(dotText * dots, dotStyle)}</font>'
                    '<font size="$spacerSize"> </font>'
                    '${PdfConverter._styled(number, font.style)}';
              } else {
                markup = number;
              }
              return _textBox(markup, font, align: 'right', normalize: false);
            },
          ),
          style: BoxStyle(
            margin: EdgeInsets(left: left, top: first ? 0 : gap),
          ),
        );
        // An empty index is left out, its entry with it: known when the
        // contents are laid out, once the whole document is read.
        _out.add(
          entry.sectname == 'index'
              ? CustomBox(
                  _Unless(
                    () => _index.isEmpty,
                    entryBox.content,
                    gap: first ? 0 : gap,
                  ),
                  style: BoxStyle(margin: EdgeInsets(left: left)),
                )
              : entryBox,
        );
        first = false;
        if (entryLevels >= entryLevel) {
          level(_sectionsOf(entry), entryLevels, left + indent);
        }
      }
    }

    level(_sectionsOf(doc), levels, 0);
  }

  /// The anchor of [section] (its id, or the one made up for it).
  String? _sectionAnchor(Section section) {
    if (section.id case final id?) return id;
    for (final (s, anchor) in _sections) {
      if (s == section) return anchor;
    }
    return _madeUpAnchor(section);
  }

  /// The page label of [anchor]'s page, or `?`.
  String _anchorLabel(String anchor) {
    final page = _anchorPages[anchor];
    return page == null ? '?' : _pageLabel(page);
  }

  /// The information of the PDF (the gem's `build_pdf_info`; the producer
  /// is Ptome unless the document names one).
  PdfInfo _info(Document doc) {
    String? plain(String? text) =>
        text == null ? null : PdfConverter._plain(text);
    final String? author;
    if (doc.attributeLocked('author') && !doc.attributeLocked('authors')) {
      author = doc.attr('author');
    } else {
      author = doc.attr('authors') ?? doc.attr('author');
    }
    return PdfInfo(
      title: plain(PdfConverter._resolveDoctitle(doc)),
      author: plain(author),
      subject: plain(doc.attr('subject')),
      keywords: plain(doc.attr('keywords')),
      creator: plain(doc.attr('publisher') ?? author) ?? '',
      producer: plain(doc.attr('producer')) ?? 'ptome',
      // The book's ISBN, editors and copyright in the XMP metadata, as
      // the EPUB's OPF has them (modern engine).
      identifier: switch (doc.attr('isbn')) {
        final String isbn when isbn.trim().isNotEmpty =>
          'urn:isbn:${isbn.replaceAll(RegExp(r'[\s-]'), '')}',
        _ => null,
      },
      contributors: [
        for (final editor in (doc.attr('editor') ?? '').split(';'))
          if (editor.trim().isNotEmpty) plain(editor.trim())!,
      ],
      rights: plain(doc.attr('copyright')),
    );
  }

  /// The theme's section indent (left and right), if any.
  (double, double)? get _sectionIndent =>
      switch (_theme.value('section_indent')) {
        ThemeNumber(:final value) when value != 0 => (
          value.toDouble(),
          value.toDouble(),
        ),
        ThemeList(:final values) when values.isNotEmpty => (
          PdfConverter._toPoints(values[0]),
          values.length > 1 ? PdfConverter._toPoints(values[1]) : 0.0,
        ),
        _ => null,
      };

  /// [margin] reaching out over the section indent (the gem's
  /// `outdent_section`).
  EdgeInsets _outdented(EdgeInsets margin) {
    final (left, right) = _sectionIndent ?? (0.0, 0.0);
    return EdgeInsets(
      top: margin.top,
      right: margin.right - right,
      bottom: margin.bottom,
      left: margin.left - left,
    );
  }

  /// Adds the [face] (`front`) cover, if any: a page of its own with the
  /// cover image (the gem's `ink_cover_page`).
  bool _cover(String face) {
    final cover = _resolveBackgroundImage(
      '$face-cover-image',
      themeKey: 'cover_${face}_image',
      symbols: const ['', '~'],
    );
    if (cover?.symbol == '~') _noCover = true;
    if (cover == null || cover.symbol == '~') return false;
    if (cover.image?.graphic case final ImportedPage page) {
      _importPage(page);
      return true;
    }
    if (cover.image case final image?) {
      _out.add(
        CustomBox(
          _Absolute((page) => _drawPageImage(page.canvas, image), fill: true),
        ),
      );
    } else {
      _out.add(CustomBox(_Absolute((_) {}, fill: true)));
    }
    _out.add(const BreakBox.page(force: true));
    return true;
  }

  /// The page background image of [key] (an attribute, else the theme's
  /// [themeKey]): a symbolic value of [symbols], or the image and how it
  /// sits on the page; null when there's none (the gem's
  /// `resolve_background_image`).
  ({String? symbol, _PageImage? image})? _resolveBackgroundImage(
    String key, {
    String? themeKey,
    List<String> symbols = const [],
  }) {
    final doc = _document;
    final fromDocument = doc.attr(key);
    final value = fromDocument ?? _s(themeKey ?? key.replaceAll('-', '_'));
    if (value == null) return null;
    if (symbols.contains(value)) return (symbol: value, image: null);
    if (value == 'none') return null;
    var target = value;
    var attrs = <String, String>{};
    var relativeToImagesdir = false;
    if (PdfConverter._imageMacroOf(value, const ['alt', 'width'])
        case (final macroTarget, final macroAttrs)?) {
      target = macroTarget;
      attrs = macroAttrs;
      relativeToImagesdir = true;
    }
    target = target.replaceAll('{page-layout}', 'portrait');
    final fromTheme = fromDocument == null;
    if (fromTheme) {
      target = _applySubsDiscretely(
        target,
        const {},
        subs: const [Sub.attributes],
      );
    }
    final format = attrs['format'] ?? PdfConverter._imageFormat(target);
    final List<int>? bytes;
    if (format == 'pdf') {
      // A page of a PDF file: imported as it is, if it exists.
      final path = fromTheme
          ? _themeImagePath(target)
          : relativeToImagesdir
          ? _imagePath(doc, target)
          : doc.normalizeSystemPath(target);
      if (path == null || !io.isFile(path) || !io.isReadable(path)) {
        final name = key.replaceAll(RegExp('[-_]'), ' ');
        logger.warn('$name not found or readable: ${path ?? target}');
        return null;
      }
      final page = _pdfPages(path, target)?.elementAtOrNull(
        math.max((int.tryParse(attrs['page'] ?? '') ?? 1) - 1, 0),
      );
      return page == null
          ? null
          : (
              symbol: null,
              image: _PageImage(
                page,
                fit: 'fill',
                position: 'center',
                vposition: 'center',
              ),
            );
    }
    if (fromTheme) {
      bytes = _themeImageBytes(target);
    } else if (relativeToImagesdir) {
      bytes = _imageBytes(doc, target);
    } else {
      final resolver = doc.pathResolver;
      final path = doc.normalizeSystemPath(target);
      bytes = io.isFile(path) && io.isReadable(path)
          ? io.readBytes(path)
          : null;
      if (bytes != null) _lastImagePath = resolver.posixify(path);
    }
    if (bytes == null) {
      final name = key.replaceAll(RegExp('[-_]'), ' ');
      logger.warn('$name not found or readable: $target');
      return null;
    }
    final (graphic, problem) = _graphicOf(bytes, format, path: _lastImagePath);
    if (graphic == null) {
      final name = key.replaceAll('-', ' ');
      logger.warn('could not embed $name: $target; $problem');
      return null;
    }
    var fit = attrs['fit'] ?? 'contain';
    if (format == 'svg' && fit == 'fill') fit = 'contain';
    var (position, vposition) = ('center', 'center');
    if (attrs['position'] case final value?) {
      if (PdfConverter._backgroundPosition(value) case final resolved?) {
        (position, vposition) = resolved;
      }
    }
    final (pageWidth, _) = _pageSize(doc);
    return (
      symbol: null,
      image: _PageImage(
        graphic,
        fit: fit,
        width: _imageWidthOf(
          (name) => attrs[name],
          fallback: false,
        ).resolve(pageWidth, pageWidth),
        position: position,
        vposition: vposition,
      ),
    );
  }

  /// Draws [image] on a page by its fit and position.
  void _drawPageImage(
    Canvas canvas,
    _PageImage image, {
    (double, double)? size,
  }) {
    final (pageWidth, pageHeight) = size ?? _pageSize(_document);
    final graphic = image.graphic;
    final (naturalWidth, naturalHeight) = switch (graphic) {
      final SvgImage svg => prawnSvgSize(
        svg,
        null,
        null,
        pageWidth,
        pageHeight,
      ),
      final other => (other.intrinsicWidth, other.intrinsicHeight),
    };
    final ratio = naturalHeight / naturalWidth;
    (double, double) contain() =>
        naturalWidth / naturalHeight > pageWidth / pageHeight
        ? (pageWidth, pageWidth * ratio)
        : (pageHeight / ratio, pageHeight);
    final (w, h) = switch (image.fit) {
      'none' =>
        image.width == null
            ? (naturalWidth, naturalHeight)
            : (image.width!, image.width! * ratio),
      'scale-down' =>
        naturalWidth > pageWidth || naturalHeight > pageHeight
            ? contain()
            : (naturalWidth, naturalHeight),
      'cover' =>
        pageWidth * ratio < pageHeight
            ? (pageHeight / ratio, pageHeight)
            : (pageWidth, pageWidth * ratio),
      'fill' => (pageWidth, pageHeight),
      _ => contain(),
    };
    final left = switch (image.position) {
      'left' => 0.0,
      'right' => pageWidth - w,
      _ => (pageWidth - w) / 2,
    };
    final top = switch (image.vposition) {
      'top' => pageHeight,
      'bottom' => h,
      _ => pageHeight - (pageHeight - h) / 2,
    };
    final rect = Rect(left, top - h, w, h);
    switch (graphic) {
      case final PdfImage raster:
        raster.paint(canvas, rect);
      case final other:
        canvas.save();
        other.paint(canvas, rect);
        canvas.restore();
    }
  }

  /// Paints the background of [page]: the page's background color and
  /// image (the title page's own, if any; none on cover pages; the gem's
  /// `init_page`).
  void _pageBackground(Canvas canvas, PageInfo page) {
    final number = page.number;
    if ((_frontCover && number == 1) || (_backCover && number == page.count)) {
      return;
    }
    final titlePageNumber = _frontCover ? 2 : 1;
    final onTitlePage = _hasTitlePage && number == titlePageNumber;
    final background =
        (onTitlePage ? _c('title_page_background_color') : null) ??
        _c('page_background_color');
    final pageWidth = page.template.size.width;
    final pageHeight = page.template.size.height;
    if (background != const HexColor('FFFFFF')) {
      if (PdfConverter._color(background) case final color?) {
        // Into the bleed, when there is one.
        final bleed = page.template.bleed ?? 0;
        canvas
          ..save()
          ..setFillColor(color)
          ..rect(
            Rect(-bleed, -bleed, pageWidth + 2 * bleed, pageHeight + 2 * bleed),
          )
          ..fill()
          ..restore();
      }
    }
    final image = onTitlePage && _titlePageImage != null
        ? _titlePageImage.image
        : _pageImages[_sideOf(number)];
    if (image != null) {
      _drawPageImage(canvas, image, size: (pageWidth, pageHeight));
    }
    _pageFrame(canvas, page);
  }

  /// The rules framing the page's text (`page_frame_width`, a width or
  /// widths from the outside in: `[3, 1]`, the Oxford rule's thick and
  /// thin; `page_frame_gap` between them, `page_frame_color`,
  /// `page_frame_offset` outside the text area; modern engine).
  void _pageFrame(Canvas canvas, PageInfo page) {
    if (asciidoctorCompat(_document, CompatFormat.pdf)) return;
    final widths = switch (_theme.value('page_frame_width')) {
      ThemeNumber(:final value) when value > 0 => [value.toDouble()],
      ThemeList(:final values) => [
        for (final value in values) PdfConverter._toPoints(value),
      ],
      _ => const <double>[],
    };
    if (widths.isEmpty) return;
    final color = PdfConverter._color(
      _c('page_frame_color') ?? _c('base_font_color'),
    );
    if (color == null) return;
    final gap =
        _length('page_frame_gap', _rootFontSize) ?? widths.reduce(math.max);
    final offset = _length('page_frame_offset', _rootFontSize) ?? _rootFontSize;
    final size = page.template.size;
    final margins = page.template.margins;
    // From the outside in: the first rule [offset] outside the text area
    // and the others its width and the gap inside each other.
    final inner =
        widths.fold<double>(0, (a, b) => a + b) + gap * (widths.length - 1);
    var out = offset + inner;
    canvas
      ..save()
      ..setStrokeColor(color);
    for (final width in widths) {
      final inset = out - width / 2;
      canvas
        ..setLineWidth(width)
        ..rect(
          Rect(
            size.left + margins.left - inset,
            size.bottom + margins.bottom - inset,
            size.width - margins.horizontal + 2 * inset,
            size.height - margins.vertical + 2 * inset,
          ),
        )
        ..stroke();
      out -= width + gap;
    }
    canvas.restore();
  }

  /// Paints the foreground of [page] (the gem's `stamp_foreground_image`).
  void _pageForeground(Canvas canvas, PageInfo page) {
    if (_frontCover && page.number == 1) return;
    // Labels hung left of their lines, `units_<level>_label_hang_gap` (a
    // third of an em) from the text.
    for (final (number, baseline, left, text, font) in _hungAt) {
      if (number != page.number) continue;
      final box = _textBox(text, font, align: 'right');
      const width = 60.0;
      final placed = box.place(width, double.infinity, atTop: true);
      if (placed == null) continue;
      final gap = font.size / 3;
      placed.paint(
        _CanvasPage(canvas),
        left - gap - width,
        baseline + (box.firstBaseline(width) ?? 0),
      );
    }
    if (_lineNumbering case final numbering?) {
      _drawLineNumbers(canvas, page, numbering);
    }
    if (_foregroundImage case final image?) {
      _drawPageImage(
        canvas,
        image,
        size: (page.template.size.width, page.template.size.height),
      );
    }
  }

  /// The line numbering [document] asks for (modern engine): its
  /// `line-numbers` attribute, `typeset` (empty too), `logical` or `grid`,
  /// set by the theme's `line_numbers_*` keys.
  _LineNumbering? _lineNumberingOf(Document document) {
    final kind = switch (document.attr('line-numbers')) {
      null => null,
      '' || 'typeset' => _LineKind.typeset,
      'logical' => _LineKind.logical,
      'grid' => _LineKind.grid,
      final other => () {
        logger.warn(
          'line-numbers is typeset, logical or grid, not $other; '
          'numbering the typeset lines',
        );
        return _LineKind.typeset;
      }(),
    };
    if (kind == null || asciidoctorCompat(document, CompatFormat.pdf)) {
      return null;
    }
    final font = _themeFont(
      'line_numbers',
      _font.copyWith(size: _rootFontSize * 0.8),
    );
    final body = _textBox('Ag Ag', _font, align: 'left');
    return _LineNumbering(
      kind,
      interval: math.max(1, (_n('line_numbers_interval') ?? 1).toInt()),
      restart:
          _choice('line_numbers_restart', const ['page', 'section', 'none']) ??
          'page',
      side:
          _choice('line_numbers_side', const [
            'left',
            'right',
            'outer',
            'inner',
          ]) ??
          'left',
      gap: _length('line_numbers_gap', _rootFontSize) ?? _rootFontSize,
      // (`line_numbers_align`: the numbers flush left or right in a
      // column `line_numbers_width` wide (two figures' room by default),
      // its near edge the gap from the text; toward the text unless set.)
      align: _choice('line_numbers_align', const ['left', 'right']),
      width: _length('line_numbers_width', font.size) ?? font.size * 1.2,
      font: font,
      pitch:
          _length('line_numbers_grid_pitch', _rootFontSize) ??
          body.linePitch(1),
      firstBaseline: body.firstBaseline(1) ?? _rootFontSize,
      // (`line_numbers_rule`: `single` or `double`, a vertical line
      // between the numbers and the text down the page, as pleading paper
      // separates them; `_rule_width`, `_rule_color`.)
      rules: switch (_choice('line_numbers_rule', const [
        'none',
        'single',
        'double',
      ])) {
        'single' => [_length('line_numbers_rule_width', _rootFontSize) ?? 0.5],
        'double' => [
          for (var i = 0; i < 2; i++)
            _length('line_numbers_rule_width', _rootFontSize) ?? 0.5,
        ],
        _ => const [],
      },
      ruleColor: PdfConverter._color(
        _c('line_numbers_rule_color') ?? _c('base_font_color'),
      ),
    );
  }

  /// Where the line count starts again in [result]: each first-level
  /// section (`line_numbers_restart: section`), and each unit of the level
  /// `line_numbers_restart_units` names (`section`, `stephanus.section`:
  /// Burnet's Plato counts from each Stephanus section, a Bekker
  /// edition from each column), its label set beside its first line.
  List<(int, double, String?)> _lineRestartsOf(LayoutResult result) {
    final restarts = <(int, double, String?)>[
      if (_lineNumbering?.restart == 'section')
        for (final (section, anchor) in _sections)
          if ((section.level ?? 0) <= 1)
            if (result.anchors[anchor] case final at?)
              (at.page + 1, at.y, null),
    ];
    final name = _s('line_numbers_restart_units');
    final session = _document.unitsSession;
    final analysis = session?.analysis;
    if (name != null &&
        name.isNotEmpty &&
        session != null &&
        analysis != null) {
      final dot = name.indexOf('.');
      final (scheme, level) = dot < 0
          ? (null, name)
          : (name.substring(0, dot), name.substring(dot + 1));
      for (final unit in analysis.units) {
        if (unit.level.name != level ||
            (scheme != null && unit.level.scheme.name != scheme)) {
          continue;
        }
        if (result.anchors[unit.id] case final at?) {
          restarts.add((
            at.page + 1,
            at.y,
            passageText(Passage(unit, unit), session.config),
          ));
        }
      }
    }
    return restarts;
  }

  /// Adds [content] with its lines numbered, when the document numbers
  /// them.
  void _numbered(void Function() content) {
    if (_lineNumbering == null) {
      content();
      return;
    }
    _out.add(
      BlockBox(_collect(content), style: const BoxStyle(numberLines: true)),
    );
  }

  /// Draws the numbers of [page]'s lines (or, for a grid, of the lines of
  /// its text area) in its margin, as [numbering] says.
  void _drawLineNumbers(
    Canvas canvas,
    PageInfo page,
    _LineNumbering numbering,
  ) {
    final template = page.template;
    final margins = template.margins;
    final area = Rect(
      template.size.left + margins.left,
      template.size.bottom + margins.bottom,
      template.size.width - margins.horizontal,
      template.size.height - margins.vertical,
    );
    if (numbering.restart == 'page' || numbering.kind == _LineKind.grid) {
      _lineCount = 0;
    }
    final lines = switch (numbering.kind) {
      _LineKind.grid => [
        for (
          var y = area.top - numbering.firstBaseline;
          y >= area.bottom;
          y -= numbering.pitch
        )
          TypesetLine(y, left: area.left, right: area.right),
      ],
      _ => page.lines,
    };
    final recto = page.number.isOdd;
    final right = switch (numbering.side) {
      'right' => true,
      'outer' => recto,
      'inner' => !recto,
      _ => false,
    };
    // The rules midway between the numbers and the text, two of them
    // their width apart about that line.
    if (numbering.ruleColor case final color? when numbering.rules.isNotEmpty) {
      final middle = right
          ? area.right + numbering.gap / 2
          : area.left - numbering.gap / 2;
      final size = template.size;
      canvas
        ..save()
        ..setStrokeColor(color);
      for (final (i, width) in numbering.rules.indexed) {
        final x = numbering.rules.length == 1
            ? middle
            : middle + (i == 0 ? -1.5 : 1.5) * width;
        canvas
          ..setLineWidth(width)
          ..moveTo(x, size.bottom)
          ..lineTo(x, size.top)
          ..stroke();
      }
      canvas.restore();
    }
    final restarts = [
      for (final (number, y, label) in _lineRestarts)
        if (number == page.number) (y, label),
    ]..sort((a, b) => b.$1.compareTo(a.$1));
    for (final line in lines) {
      if (numbering.kind == _LineKind.logical && line.continues) continue;
      // (Past the start of a section or a unit: from 1 again, the unit's
      // label beside its first line.)
      String? label;
      while (restarts.isNotEmpty && line.baseline <= restarts.first.$1 + 1e-6) {
        label = restarts.removeAt(0).$2 ?? label;
        _lineCount = 0;
      }
      _lineCount++;
      if (label == null && _lineCount % numbering.interval != 0) continue;
      final align = numbering.align ?? (right ? 'left' : 'right');
      final text = _textBox(
        label ?? '$_lineCount',
        numbering.font,
        align: align,
      );
      // (Set in a box wide enough for any number, its edge at the
      // column's.)
      const width = 60.0;
      final placed = text.place(width, double.infinity, atTop: true);
      if (placed == null) continue;
      final baseline = text.firstBaseline(width) ?? 0;
      final column = right
          ? area.right + numbering.gap
          : area.left - numbering.gap - numbering.width;
      final x = align == 'left' ? column : column + numbering.width - width;
      placed.paint(_CanvasPage(canvas), x, line.baseline + baseline);
    }
  }

  /// Whether [result] has a blank page before the body.
  bool _blankBefore(LayoutResult result) =>
      switch (result.anchors[PdfConverter._beforeBodyAnchor]?.page) {
        final page? => page + 1 < _bodyStart,
        null => false,
      };

  /// The side (`recto`, `verso`) of page [number] by the folio placement.
  String _sideOf(int number) =>
      number.isOdd != _folio.inverted ? 'recto' : 'verso';

  /// The layouts whose pages get recto and verso margins: the initial
  /// one, and the other one unless it has margins of its own
  /// (`page_margin_rotated`).
  List<String> _sidedLayouts(Document document) {
    final initial = _initialLayout(document);
    final rotated =
        document.attr('pdf-page-margin-rotated') != null ||
        _theme.value('page_margin_rotated') != null;
    final other = initial == 'portrait' ? 'landscape' : 'portrait';
    return [initial, if (!rotated) other];
  }

  /// [template] for page [number] with `media=prepress`: one of the
  /// [sided] templates gets the theme's inner and outer margins on the
  /// side of the binding and the side away from it (the first page keeps
  /// its margins when it's the [cover], a title page).
  PageTemplate _sidedTemplate(
    PageTemplate template,
    int number, {
    required Set<PageTemplate> sided,
    required bool cover,
  }) {
    if (cover || !sided.contains(template)) return template;
    // (A rule's margins are a recto's: inner on the left.)
    final ruled = asciidoctorCompat(_document, CompatFormat.pdf)
        ? null
        : _ruledMargins(_document);
    // (A rule the theme names before the inner and outer margins it
    // inherits: asciidoctor-pdf's default theme gives those.)
    final outer = ruled?.right ?? _n('page_margin_outer')?.toDouble();
    var inner = ruled?.left ?? _n('page_margin_inner')?.toDouble();
    // (`page_margin_gutter: kdp`: no less than KDP's least inner margin
    // for the book's page count.)
    if (_gutterLeast > 0) {
      inner = math.max(inner ?? template.margins.left, _gutterLeast);
    }
    if (outer == null && inner == null) return template;
    final m = template.margins;
    // (An inverted folio placement swaps the sides, margins too.)
    final recto = number.isOdd != _folio.inverted;
    return PageTemplate(
      template.size,
      margins: EdgeInsets(
        top: m.top,
        bottom: m.bottom,
        left: (recto ? inner : outer) ?? m.left,
        right: (recto ? outer : inner) ?? m.right,
      ),
      columns: template.columns,
      columnGap: template.columnGap,
      header: template.header,
      footer: template.footer,
      runningOver: template.runningOver,
      background: template.background,
      foreground: template.foreground,
      bleed: template.bleed,
    );
  }

  /// The output intent of a PDF/X-4 document (`pdf-standard=PDF/X-4`,
  /// with `pdf-output-intent` the ICC profile of the printing condition
  /// and `pdf-output-condition` its identifier), or null for a plain PDF.
  PdfOutputIntent? _pdfStandard(Document document) {
    final standard = document.attr('pdf-standard');
    if (standard == null) return null;
    if (standard.toUpperCase() != 'PDF/X-4') {
      logger.warn(
        'unknown pdf-standard: $standard (PDF/X-4 is available); '
        'writing a plain PDF',
      );
      return null;
    }
    final target = document.attr('pdf-output-intent');
    if (target == null || target.isEmpty) {
      logger.error(
        'PDF/X-4 needs the ICC profile of the printing condition: set '
        'pdf-output-intent to its file; writing a plain PDF',
      );
      return null;
    }
    final path = document.normalizeSystemPath(target);
    if (!io.isFile(path) || !io.isReadable(path)) {
      logger.error(
        'output intent profile not found or not readable: $target; '
        'writing a plain PDF',
      );
      return null;
    }
    final intent = PdfOutputIntent(
      io.readBytes(path),
      identifier: document.attr('pdf-output-condition') ?? 'Custom',
      info: target.split('/').last,
    );
    if (intent.components == null) {
      logger.error('not an ICC profile: $target; writing a plain PDF');
      return null;
    }
    return intent;
  }

  /// Reports what keeps the document from conforming to PDF/X-4 with
  /// [intent]: fonts not embedded, a profile that isn't for output, RGB
  /// colors with a CMYK printing condition.
  void _preflight(PdfOutputIntent intent) {
    for (final font in _fonts.loaded) {
      if (font is AfmFont) {
        logger.error(
          'PDF/X-4 needs every font embedded: ${font.family} is a built-in '
          'PDF font; give the theme a font file for it',
        );
      }
    }
    if (intent.deviceClass != 'prtr') {
      logger.warn(
        'the output intent profile is not an output (printer) profile '
        '(${intent.deviceClass}), as PDF/X-4 asks',
      );
    }
    if (intent.components == 4) {
      logger.warn(
        'the text, lines and images are in RGB and the printing condition '
        'in CMYK: PDF/X-4 asks for colors the output intent can describe; '
        'use an RGB output profile, or convert the PDF',
      );
    }
  }

  /// Writes the layout report (`pdf-layout-report`, a file next to the
  /// PDF): each block that breaks across pages, with where it starts in
  /// the source, for proofreading.
  void _layoutReport(Document document, LayoutResult result) {
    final tags = _reportTags;
    final target = document.attr('pdf-layout-report');
    if (tags == null || target == null) return;
    final lines = <String>[];
    for (final MapEntry(key: tag, value: (block, at)) in tags.entries) {
      final pages = result.tagPages[tag];
      if (pages == null || pages.first == pages.last) continue;
      final where = at == null
          ? ''
          : '${at.path ?? at.file ?? ''}: line ${at.lineno}: ';
      lines.add(
        '$where${block.context.name} on pages ${_pageLabel(pages.first)}'
        '-${_pageLabel(pages.last)}',
      );
    }
    final dir = document.attr('outdir') ?? document.attr('docdir') ?? '.';
    final path = target.startsWith('/') ? target : '$dir/$target';
    io.writeString(path, lines.isEmpty ? '' : '${lines.join('\n')}\n');
    logger.info(
      'layout report: ${lines.length} '
      '${lines.length == 1 ? 'block breaks' : 'blocks break'} across pages '
      '($path)',
    );
  }

  /// Writes the page map (`pdf-page-map`, a JSON file next to the PDF):
  /// the page labels, and for each block, where it starts in the source
  /// and the pages it is on, so an EPUB of the same source can mark the
  /// print edition's pages (`epub-page-map`, ADR-0012).
  void _pageMap(Document document, LayoutResult result, int pageCount) {
    final tags = _reportTags;
    final target = document.attr('pdf-page-map');
    if (tags == null || target == null) return;
    final blocks = <String, (int, int)>{};
    for (final MapEntry(key: tag, value: (_, at)) in tags.entries) {
      final pages = result.tagPages[tag];
      if (pages == null || at == null) continue;
      blocks['${at.path ?? at.file ?? ''}:${at.lineno}'] = (
        pages.first,
        pages.last,
      );
    }
    final map = PageMap(
      labels: [for (var i = 1; i <= pageCount; i++) _pageLabel(i)],
      blocks: blocks,
    );
    final dir = document.attr('outdir') ?? document.attr('docdir') ?? '.';
    final path = target.startsWith('/') ? target : '$dir/$target';
    io.writeString(path, map.toJson());
  }

  /// Tags the box [block] added last (after any caption) after [before],
  /// for the layout report.
  void _tagLast(int before, AbstractBlock block) {
    final tags = _reportTags!;
    for (var i = _out.length - 1; i >= before; i--) {
      final tag = 'b${tags.length}';
      final tagged = switch (_out[i]) {
        BlockBox(:final children, :final style) => BlockBox(
          children,
          style: style.withTag(tag),
        ),
        CustomBox(:final content, :final style) => CustomBox(
          content,
          style: style.withTag(tag),
        ),
        ParagraphBox(
          :final paragraph,
          :final style,
          :final orphans,
          :final widows,
        ) =>
          ParagraphBox(
            paragraph,
            style: style.withTag(tag),
            orphans: orphans,
            widows: widows,
          ),
        TableBox(:final rows, :final columns, :final style) && final table =>
          TableBox(
            rows,
            columns: columns,
            headerRows: table.headerRows,
            width: table.width,
            shrinkToContent: table.shrinkToContent,
            borders: table.borders,
            align: table.align,
            stripes: table.stripes,
            cellsContainMargins: table.cellsContainMargins,
            style: style.withTag(tag),
          ),
        _ => null,
      };
      if (tagged == null) continue;
      _out[i] = tagged;
      tags[tag] = (block, block.sourceLocation ?? _at);
      return;
    }
  }

  /// How far the modern engine's sheets run past the page for print
  /// (`page_bleed`): null for no print boxes, unless the document is
  /// PDF/X, which needs them.
  double? get _bleed {
    final bleed = switch (_theme.value('page_bleed')) {
      ThemeNumber(:final value) => value.toDouble(),
      ThemeString(:final value) => strToPoints(value),
      _ => null,
    };
    return bleed ?? (_document.hasAttr('pdf-standard') ? 0 : null);
  }

  /// The pages before the running content and the page numbers start
  /// (the gem's `num_front_matter_pages`, without covers).
  (int, int) _frontMatter({required bool titlePage}) {
    final bodyOffset = _bodyStart - 1;
    ThemeValue? startAt(String key) => _theme[key];
    if (!titlePage) {
      int offset(ThemeValue? value) => switch (value) {
        ThemeNumber(:final value) =>
          bodyOffset + math.max(value.toInt() - 1, _blankBeforeBody ? -1 : 0),
        _ => bodyOffset,
      };
      final numbering = startAt('page_numbering_start_at');
      return (
        offset(startAt('running_content_start_at')),
        numbering is ThemeString && numbering.value == 'cover' && _frontCover
            ? 0
            : offset(numbering),
      );
    }
    final hasTitlePage =
        _document.hasHeader &&
        !_document.notitle &&
        _theme['title_page'] is! ThemeBool;
    final zero = _frontCover ? 1 : 0;
    final first = hasTitlePage ? zero + 1 : zero;
    final tocAtTop = _tocAtTop;
    String resolve(ThemeValue? value, void Function(int) integer) {
      switch (value) {
        case ThemeNumber(:final value):
          integer(
            bodyOffset + math.max(value.toInt() - 1, _blankBeforeBody ? -1 : 0),
          );
          return 'body';
        case final other?:
          return switch (other.rubyString) {
            'cover' when _frontCover => 'cover',
            'cover' => hasTitlePage ? 'title' : 'toc',
            'title' when !hasTitlePage => 'toc',
            'toc' when !tocAtTop => 'body',
            'after-toc' => 'body',
            final setting => setting,
          };
        case null:
          return 'body';
      }
    }

    var runningBody = bodyOffset;
    var numberingBody = bodyOffset;
    final running = resolve(
      startAt('running_content_start_at'),
      (v) => runningBody = v,
    );
    final numbering = resolve(
      startAt('page_numbering_start_at'),
      (v) => numberingBody = v,
    );
    if (numbering == 'cover') numberingBody = 0;
    var skips = switch ((running, numbering)) {
      ('title', 'title') => (zero, zero),
      ('title', 'toc') => (zero, first),
      ('title', _) => (zero, numberingBody),
      ('toc', 'title') => (first, zero),
      ('toc', 'toc') => (first, first),
      ('toc', _) => (first, numberingBody),
      (_, 'title') => (runningBody, zero),
      (_, 'toc') => (runningBody, first),
      _ => (runningBody, numberingBody),
    };
    // A table of contents placed elsewhere starts them by its pages.
    if (_tocPages case (final start, final end) when !tocAtTop) {
      String? setting(String key) => startAt(key)?.rubyString;
      int skip(String key, int value) => switch (setting(key)) {
        'toc' => start - 1,
        'after-toc' => _ppbook && end.isOdd ? end + 1 : end,
        _ => value,
      };
      skips = (
        skip('running_content_start_at', skips.$1),
        skip('page_numbering_start_at', skips.$2),
      );
    }
    return skips;
  }

  Theme _loadTheme(Document document) {
    var name = document.attr('pdf-theme');
    final dir = document
        .attr('pdf-themesdir')
        ?.replaceAll('{docdir}', document.attr('docdir') ?? '');
    final compat = asciidoctorCompat(document, CompatFormat.pdf);
    // The default is the document's look (ADR-0023), the house look
    // unless it names another (ADR-0011); `pdf-theme=ptome` is the house
    // look's. With asciidoctor-compat (ADR-0015), asciidoctor-pdf's
    // theme: no look applies.
    if ((name == null && !compat) || name == 'ptome') {
      return _lookTheme(document, house: name == 'ptome');
    }
    if (name == null && (document.attr('media') ?? 'screen') != 'screen') {
      name = 'default-for-print';
    }
    final loader = ThemeLoader(
      logger: logger,
      looks: (look) => _lookTheme(document, house: look == 'ptome'),
    );
    Theme theme;
    try {
      theme = loader.load(name, dir);
    } on ThemeException catch (error) {
      logger.error(error.message);
      theme = ThemeLoader(logger: logger).load();
    }
    if (asciidoctorCompat(document, CompatFormat.pdf)) {
      for (final MapEntry(:key, :value)
          in PdfConverter.asciidoctorPdfLook.entries) {
        if (theme[key] == null) theme[key] = value;
      }
    }
    return theme;
  }

  /// The PDF theme of the document's look (`look`, found in `looksdir`
  /// before the built-in looks), or of the house look; a look that can't
  /// be read is reported and the house look used.
  Theme _lookTheme(Document document, {bool house = false}) {
    return lookTheme(
      documentLook(document, house: house),
      loader: ThemeLoader(logger: logger),
      warn: logger.warn,
    );
  }

  /// The page size of the initial layout (the gem's page size: a named
  /// size, `[w, h]` or `w x h`; turned for landscape).
  (double, double) _pageSize(Document document) =>
      _layoutSize(document, _initialLayout(document));

  /// The initial page layout (`portrait` or `landscape`).
  String _initialLayout(Document document) {
    final layout = document.attr('pdf-page-layout') ?? _s('page_layout');
    return layout == 'landscape' ? 'landscape' : 'portrait';
  }

  /// The page size of [layout].
  (double, double) _layoutSize(Document document, String layout) {
    double? dimension(String text) {
      final match = RegExp(r'^(\d+(?:\.\d+)?)(in|mm|cm|p[txc])?$')
          .firstMatch(text.trim());
      if (match == null) return null;
      final points = strToPoints(text.trim());
      final truncated = (points * 10000).truncate() / 10000;
      return truncated > 0 ? truncated : null;
    }

    (double, double)? size;
    final attr = document.attr('pdf-page-size');
    final match = attr == null
        ? null
        : RegExp(
            '^(?:\\[(${PdfConverter._measurement}), ?(${PdfConverter._measurement})\\]|'
            '(${PdfConverter._measurement})(?: x |x)(${PdfConverter._measurement})|\\S+)\$',
          ).firstMatch(attr);
    if (match != null) {
      final w = match[1] ?? match[3];
      final h = match[2] ?? match[4];
      if (w != null && h != null) {
        final (dw, dh) = (dimension(w), dimension(h));
        if (dw != null && dh != null) size = (dw, dh);
      } else {
        size = _pageSizes[match[0]!.toUpperCase()];
      }
    } else {
      switch (_theme.value('page_size')) {
        case ThemeList(:final values) when values.isNotEmpty:
          double? of(ThemeValue value) => switch (value) {
            ThemeNumber(:final value) when value > 0 => value.toDouble(),
            final other => dimension(other.rubyString),
          };
          final w = of(values[0]);
          final h = of(values.length > 1 ? values[1] : values[0]);
          if (w != null && h != null) size = (w, h);
        case final ThemeValue value:
          size = _pageSizes[value.rubyString.toUpperCase()];
        case null:
          break;
      }
    }
    final (w, h) = size ?? _pageSizes['A4']!;
    return layout == 'landscape' ? (h, w) : (w, h);
  }

  /// The page margins of [layout]: the theme's (or `pdf-page-margin`),
  /// the rotated margins for the layout that isn't the initial one.
  EdgeInsets _marginsFor(Document document, String layout) {
    if (layout != _initialLayout(document)) {
      final rotated = document.attr('pdf-page-margin-rotated') != null
          ? ThemeString(document.attr('pdf-page-margin-rotated')!)
          : _theme.value('page_margin_rotated');
      if (rotated != null) {
        final values = _edgeValues(rotated);
        return EdgeInsets(
          top: values[0],
          right: values[1],
          bottom: values[2],
          left: values[3],
        );
      }
    }
    return _pageMargins(document);
  }

  EdgeInsets _pageMargins(Document document) {
    final given = document.attr('pdf-page-margin');
    // (Margins from a rule, modern engine, unless the document gives
    // them: `page_margin_canon`, `page_margin_div`, a measured profile.)
    if (given == null && !asciidoctorCompat(document, CompatFormat.pdf)) {
      if (_ruledMargins(document) case final ruled?) return ruled;
    }
    final values = _edgeValues(
      given != null ? ThemeString(given) : _theme.value('page_margin'),
    );
    // A measure (`page_measure`) sets the side margins that center a text
    // block that wide, unless the document gives the margins.
    if (given == null) {
      if (_theme.value('page_measure') case final measure?) {
        final width = _pageSize(document).$1;
        final double side = math.max(0, (width - _measure(measure)) / 2);
        return EdgeInsets(
          top: values[0],
          right: side,
          bottom: values[2],
          left: side,
        );
      }
    }
    return EdgeInsets(
      top: values[0],
      right: values[1],
      bottom: values[2],
      left: values[3],
    );
  }

  /// The margins a rule gives (modern engine), the inner one on the left
  /// (a recto's), or null for the theme's `page_margin`:
  ///
  /// - `page_margin_canon: n`: the classical canon, inner W/n, outer 2W/n,
  ///   head H/n, foot 2H/n of the page's width W and height H (9: Van de
  ///   Graaf's and Tschichold's);
  /// - `page_margin_div: n` with `page_margin_bcor` (a length, the
  ///   binding's allowance): KOMA-Script's type area, the page less the
  ///   allowance in n stripes each way, inner one stripe and the
  ///   allowance, outer two, head one, foot two;
  /// - `page_margin_profile`: margins measured from books,
  ///   `university-press` (6×9 in books' medians: inner 0.79, outer 0.83,
  ///   head 0.88, foot 1 in), `ucl-press` (inner 0.94, outer 1.11 in, the
  ///   head and foot `page_margin`'s), `trade` (5.5×8.5 in books: the
  ///   gutter 1.3 times the fore-edge of `page_margin`).
  ///
  /// With `page_margin_div`, or `page_margin_whole_lines: true`, the foot
  /// is as much larger as makes the text area hold whole body lines.
  EdgeInsets? _ruledMargins(Document document) {
    final (width, height) = _pageSize(document);
    final theme = _edgeValues(_theme.value('page_margin'));
    EdgeInsets? margins;
    if (_n('page_margin_canon') case final n? when n > 2) {
      margins = EdgeInsets(
        top: height / n,
        bottom: 2 * height / n,
        left: width / n,
        right: 2 * width / n,
      );
    } else if (_n('page_margin_div') case final div? when div > 3) {
      final bcor = _length('page_margin_bcor', _rootFontSize) ?? 0;
      final stripe = (width - bcor) / div;
      margins = EdgeInsets(
        top: height / div,
        bottom: 2 * height / div,
        left: stripe + bcor,
        right: 2 * stripe,
      );
    } else {
      const inch = 72.0;
      margins = switch (_s('page_margin_profile')) {
        'university-press' => const EdgeInsets(
          top: 0.88 * inch,
          bottom: 1.0 * inch,
          left: 0.79 * inch,
          right: 0.83 * inch,
        ),
        'ucl-press' => EdgeInsets(
          top: theme[0],
          bottom: theme[2],
          left: 0.94 * inch,
          right: 1.11 * inch,
        ),
        'trade' => EdgeInsets(
          top: theme[0],
          bottom: theme[2],
          left: 1.3 * theme[1],
          right: theme[1],
        ),
        _ => null,
      };
    }
    if (margins == null) return null;
    final whole =
        _n('page_margin_div') != null ||
        _theme.value('page_margin_whole_lines') == const ThemeBool(true);
    if (!whole) return margins;
    // (The text area a whole number of body lines tall.)
    final pitch = _bodyPitch();
    final area = height - margins.vertical;
    if (pitch <= 0 || area <= pitch) return margins;
    final lines = (area / pitch + 1e-6).floor();
    return EdgeInsets(
      top: margins.top,
      bottom: margins.bottom + (area - lines * pitch),
      left: margins.left,
      right: margins.right,
    );
  }

  /// The distance between two body lines (`base_line_pitch`, else the
  /// body font's height and its leading).
  double _bodyPitch() {
    if (_length('base_line_pitch', _rootFontSize) case final pitch?) {
      return pitch;
    }
    final face = _fonts.font(
      _s('base_font_family') ?? 'Helvetica',
      PdfConverter._fontStyle(_s('base_font_style')) ?? 'normal',
    );
    final lineHeight = (_n('base_line_height') ?? 1).toDouble();
    return face.heightAt(_rootFontSize) + (lineHeight - 1) * _rootFontSize;
  }

  /// KDP's least inner margin for a book of [pages] pages, in points.
  static double _kdpGutter(int pages) =>
      72 *
      switch (pages) {
        <= 150 => 0.375,
        <= 300 => 0.5,
        <= 500 => 0.625,
        <= 700 => 0.75,
        _ => 0.875,
      };

  /// A measure in points: a length, or `ch` (the width of a zero in the
  /// text face at the text size) or `em` (the text size).
  double _measure(ThemeValue measure) {
    final text = measure.rubyString.trim();
    if (RegExp(r'^([\d.]+)\s*(ch|r?em)$').firstMatch(text) case final m?) {
      final count = double.parse(m[1]!);
      return m[2] != 'ch'
          ? count * _rootFontSize
          : count *
                _fonts
                    .font(_font.family, _font.style)
                    .widthOf('0', _rootFontSize, kerning: false);
    }
    return PdfConverter._toPoints(measure);
  }

  /// A margin or padding value: one number for all sides, or two, three or
  /// four (CSS order).
  List<double> _edgeValues(ThemeValue? value) {
    final numbers = switch (value) {
      ThemeList(:final values) => [
        for (final v in values) PdfConverter._toPoints(v),
      ],
      ThemeNumber(:final value) => [value.toDouble()],
      ThemeString(:final value) => [
        for (final part
            in value
                .replaceAll(RegExp(r'[\[\]]'), '')
                .split(RegExp(r'[,\s]+'))
                .where((p) => p.isNotEmpty))
          strToPoints(part),
      ],
      _ => const [36.0],
    };
    return switch (numbers.length) {
      0 => [36, 36, 36, 36],
      1 => [numbers[0], numbers[0], numbers[0], numbers[0]],
      2 => [numbers[0], numbers[1], numbers[0], numbers[1]],
      3 => [numbers[0], numbers[1], numbers[2], numbers[1]],
      _ => numbers.sublist(0, 4),
    };
  }
}
