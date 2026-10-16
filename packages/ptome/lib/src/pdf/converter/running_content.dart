part of '../converter.dart';

// Running content.

extension _RunningContent on PdfConverter {
  /// [result]'s mark anchors (see [_pageMarks]), in reading order.
  List<(String, String)?> _marksByPage(
    LayoutResult result, {
    required int pageCount,
  }) {
    final prefix = _s('running_content_marks');
    if (prefix == null || prefix.isEmpty) return const [];
    final first = <int, String>{};
    final last = <int, String>{};
    for (final MapEntry(:key, :value) in result.anchors.entries) {
      if (!key.startsWith(prefix)) continue;
      first.putIfAbsent(value.page, () => key);
      last[value.page] = key;
    }
    final marks = <(String, String)?>[];
    String? before;
    for (var page = 0; page < pageCount; page++) {
      if ((first[page], last[page]) case (final a?, final b?)) {
        marks.add((a, b));
        before = b;
      } else {
        final carried = before;
        marks.add(carried == null ? null : (carried, carried));
      }
    }
    return marks;
  }

  /// [result]'s mark anchors by the column each is in (see
  /// [_columnMarks]): the page's text block divided into its
  /// `page_columns`.
  List<List<(String, String)?>> _marksByColumn(LayoutResult result) {
    final prefix = _s('running_content_marks');
    if (prefix == null || prefix.isEmpty) return const [];
    final count = math.max(1, (_n('page_columns') ?? 1).toInt());
    final byPage = <int, List<(int, String)>>{};
    for (final MapEntry(:key, :value) in result.anchors.entries) {
      if (!key.startsWith(prefix)) continue;
      final regions = result.regions(value.page);
      if (regions.isEmpty) continue;
      final left = regions.map((r) => r.left).reduce(math.min);
      final right = regions.map((r) => r.right).reduce(math.max);
      final column = ((value.x - left) / ((right - left) / count))
          .floor()
          .clamp(0, count - 1);
      (byPage[value.page] ??= []).add((column, key));
    }
    final out = <List<(String, String)?>>[];
    String? before;
    for (var page = 0; page < result.pageCount; page++) {
      final columns = <(String, String)?>[];
      final marks = byPage[page] ?? const [];
      for (var column = 0; column < count; column++) {
        final here = [
          for (final (c, key) in marks)
            if (c == column) key,
        ];
        if (here.isNotEmpty) {
          columns.add((here.first, here.last));
          before = here.last;
        } else {
          final carried = before;
          columns.add(carried == null ? null : (carried, carried));
        }
      }
      out.add(columns);
    }
    return out;
  }

  /// [result]'s units (see [_pageUnits]).
  List<(Unit, Unit)?> _unitsByPage(
    LayoutResult result, {
    required int pageCount,
  }) {
    final name = _s('running_content_units');
    final analysis = _document.unitsSession?.analysis;
    if (name == null || name.isEmpty || analysis == null) return const [];
    final dot = name.indexOf('.');
    final (scheme, level) = dot < 0
        ? (null, name)
        : (name.substring(0, dot), name.substring(dot + 1));
    final first = <int, Unit>{};
    final last = <int, Unit>{};
    for (final u in analysis.units) {
      if (u.level.name != level ||
          (scheme != null && u.level.scheme.name != scheme)) {
        continue;
      }
      final at = result.anchors[u.id];
      if (at == null) continue;
      final page = at.page;
      final f = first[page];
      if (f == null || u.start.compareTo(f.start) < 0) first[page] = u;
      final l = last[page];
      if (l == null || u.start.compareTo(l.start) > 0) last[page] = u;
    }
    final units = <(Unit, Unit)?>[];
    Unit? before;
    for (var page = 0; page < pageCount; page++) {
      if ((first[page], last[page]) case (final a?, final b?)) {
        units.add((a, b));
        before = b;
      } else {
        final carried = before;
        units.add(carried == null ? null : (carried, carried));
      }
    }
    return units;
  }

  /// The text a mark anchor stands for: its reference text, else its id.
  String _markText(String id) => switch (_document.catalog.refs[id]) {
    final Inline inline => inline.reftext ?? id,
    final AbstractNode node => node.reftext ?? id,
    null => id,
  };

  /// The label of page [number]: its number after the front matter, else
  /// its number in lower-case roman numerals. The modern engine numbers
  /// the first page after the front matter `folio-start` (a journal's or
  /// the Federal Register's pages, numbered through a volume).
  String _pageLabel(int number) {
    final virtual = number - _skip.$2;
    if (virtual < 1) return PdfConverter._roman(number).toLowerCase();
    return '${virtual + _folioStart - 1}';
  }

  /// Page label [label] (or a range of them, `12-15`) as the pages show
  /// it (Ptome's; not under `asciidoctor-compat`): its numbers in the
  /// counter style `page_numbering_style` names (`cjk-decimal`,
  /// `arabic-indic`, `upper-roman`), else in the document's numbering
  /// system's digits ([localDigits]).
  String _shownPage(String label) {
    if (asciidoctorCompat(_document, CompatFormat.pdf)) return label;
    if (_s('page_numbering_style') case final name?) {
      if (CounterStyle.named(name) case final style?) {
        return label.replaceAllMapped(
          RegExp('[0-9]+'),
          (m) => style.format(int.parse(m[0]!)),
        );
      }
    }
    return localDigits(_document, label);
  }

  /// The number of the first page after the front matter (`folio-start`;
  /// modern engine).
  int get _folioStart => _folioStartValue ??= () {
    final value = _document.attr('folio-start');
    if (value == null || asciidoctorCompat(_document, CompatFormat.pdf)) {
      return 1;
    }
    final start = int.tryParse(value.trim());
    if (start == null || start < 1) {
      logger.warn('folio-start is a page number, not $value; starting at 1');
      return 1;
    }
    return start;
  }();

  List<LayoutBox> _header(PageInfo page) => _running('header', page);
  List<LayoutBox> _footer(PageInfo page) => _running('footer', page);

  /// The four sides of the margin theme value [value], `inherit` taking
  /// [inherit]'s values on the left and right (the gem's
  /// `expand_margin_value`).
  List<double> _trimValues(ThemeValue? value, List<double> inherit) {
    const inherited = [
      ThemeNumber(0),
      ThemeString('inherit'),
      ThemeNumber(0),
      ThemeString('inherit'),
    ];
    final raw = switch (value) {
      ThemeList(:final values) => values,
      null => inherited,
      final one => [one],
    };
    final four = switch (raw.length) {
      1 => [raw[0], raw[0], raw[0], raw[0]],
      2 => [raw[0], raw[1], raw[0], raw[1]],
      3 => [raw[0], raw[1], raw[2], raw[1]],
      _ => raw.sublist(0, 4),
    };
    return [
      for (final (i, v) in four.indexed)
        if (i.isOdd && v is ThemeString && v.value == 'inherit')
          inherit[i]
        else
          PdfConverter._toPoints(v),
    ];
  }

  /// The header or footer ([periphery]) of [page] (the gem's
  /// `ink_running_content`), drawn where the gem draws it.
  List<LayoutBox> _running(String periphery, PageInfo page) {
    final doc = _document;
    if (periphery == 'header' ? doc.noheader : doc.nofooter) return const [];
    final height = (_keys(periphery).number('height') ?? 0).toDouble();
    if (height == 0) return const [];
    if (page.count < _bodyStart) return const [];
    final number = page.number;
    if (number <= _skip.$1) return const [];
    if (_backCover && number == page.count) return const [];
    // The modern engine leaves blank pages (before a recto start, say)
    // blank, unless running_content_on_blank_pages is true.
    if (page.isEmpty &&
        _theme.value('running_content_on_blank_pages') !=
            const ThemeBool(true)) {
      return const [];
    }
    if (_tocPages case (final first, final last)
        when number >= first &&
            number <= last &&
            (periphery == 'header' ? _tocNoHeader : _tocNoFooter)) {
      return const [];
    }
    // A page that opens a part or chapter, unless the theme says
    // otherwise; the pages of a part or chapter with the `noheader` or
    // `nofooter` option (as the gem reads it on the toc macro).
    if (_openerPages.contains(number) &&
        _theme.value('running_content_on_openers') != const ThemeBool(true) &&
        // (`<periphery>_on_openers: true`: this one only, a printing's
        // signatures at the foot of a chapter's first page, no head.)
        _keys(periphery).value('on_openers') != const ThemeBool(true)) {
      return const [];
    }
    if (_pageSection(page)?.hasOption('no$periphery') ?? false) {
      return const [];
    }

    final virtual = number - _skip.$2;
    final label = _shownPage(_pageLabel(number));
    final side = _sideOf(_folio.physical ? number : virtual);
    final pageWidth = page.template.size.width;
    final pageHeight = page.template.size.height;
    final margins = page.template.margins;
    final pageMargin = [
      margins.top,
      margins.right,
      margins.bottom,
      margins.left,
    ];
    // (A right-to-left document's pages mirrored: the theme's left, its
    // start, at the right; the page's own margins are already.)
    final mirror = _documentRightToLeft;
    List<double> mirrored(ThemeValue? given, List<double> values) =>
        mirror && given != null
        ? [values[0], values[3], values[2], values[1]]
        : values;
    final trimGiven =
        _keys(periphery).value('${side}_margin') ??
        _keys(periphery).value('margin');
    final trimMargin = mirrored(trimGiven, _trimValues(trimGiven, pageMargin));
    final contentGiven =
        _keys(periphery).value('${side}_content_margin') ??
        _keys(periphery).value('content_margin');
    final contentMargin = mirrored(
      contentGiven,
      _trimValues(contentGiven, [
        for (var i = 0; i < 4; i++) pageMargin[i] - trimMargin[i],
      ]),
    );
    final paddingValue =
        _keys(periphery).value('${side}_padding') ??
        _keys(periphery).value('padding');
    final padding = paddingValue == null
        ? contentMargin
        : [
            for (final (i, v) in mirrored(
              paddingValue,
              _edgeValues(paddingValue),
            ).indexed)
              v + contentMargin[i],
          ];
    final baseFont = _themeFont(periphery, _font);
    final metrics = _lineMetrics(baseFont);
    final borderWidth = (_keys(periphery).number('border_width') ?? 0)
        .toDouble();
    final top = periphery == 'header'
        ? pageHeight - trimMargin[0]
        : height + trimMargin[2];
    final left = trimMargin[3];
    final width = pageWidth - left - trimMargin[1];
    final contentLeft = left + padding[3];
    final contentWidth = width - padding[1] - padding[3];
    final contentHeight = height - padding[0] - padding[2] - borderWidth * 0.5;
    final proseHeight =
        contentHeight - metrics.paddingTop - metrics.paddingBottom;
    final contentOffset = periphery == 'footer' ? borderWidth * 0.5 : 0.0;
    var valign = _keys(periphery).string('vertical_align') ?? 'middle';
    if (valign == 'middle') valign = 'center';

    // The columns: their alignment, width and left edge.
    final columns = <String, (String, double, double)>{};
    final spec =
        _keys(periphery).value('${side}_columns') ??
        _keys(periphery).value('columns');
    if (spec != null) {
      final parts = spec.rubyString.replaceAll(',', ' ').split(RegExp(r'\s+'))
        ..removeWhere((p) => p.isEmpty);
      final specs = switch (parts.length) {
        0 ||
        1 => {'left': '0', 'center': parts.firstOrNull ?? '100', 'right': '0'},
        2 => {'left': parts[0], 'center': '0', 'right': parts[1]},
        _ => {'left': parts[0], 'center': parts[1], 'right': parts[2]},
      };
      var total = 0.0;
      final relative = <String, (String, double)>{};
      for (final MapEntry(key: position, :value) in specs.entries) {
        final first = value.isEmpty ? '' : value[0];
        final (align, amount) = int.tryParse(first) != null
            ? ('left', PdfConverter._toF(value))
            : (
                switch (first) {
                  '=' => 'center',
                  '>' => 'right',
                  _ => 'left',
                },
                PdfConverter._toF(value.substring(1)),
              );
        total += amount;
        relative[position] = (align, amount);
      }
      final widths = {
        for (final MapEntry(key: position, value: (align, amount))
            in relative.entries)
          position: (align, total == 0 ? 0.0 : amount / total * contentWidth),
      };
      final leftWidth = widths['left']!.$2;
      final centerWidth = widths['center']!.$2;
      columns['left'] = (widths['left']!.$1, leftWidth, 0);
      columns['center'] = (widths['center']!.$1, centerWidth, leftWidth);
      columns['right'] = (
        widths['right']!.$1,
        widths['right']!.$2,
        leftWidth + centerWidth,
      );
    } else {
      for (final position in const ['left', 'center', 'right']) {
        columns[position] = (position, contentWidth, 0);
      }
    }
    // (Its columns too: the theme's left column at the right, aligned
    // there; a recto's outer edge, where its folio goes, at its left.)
    if (mirror) {
      for (final MapEntry(key: position, value: (align, w, x))
          in columns.entries.toList()) {
        columns[position] = (
          switch (align) {
            'left' => 'right',
            'right' => 'left',
            final other => other,
          },
          w,
          contentWidth - x - w,
        );
      }
    }

    // The attributes the content refers to.
    final attributes = _runningAttributes(periphery, page, label);
    final pieces = <void Function(LayoutPage page)>[];
    final background = PdfConverter._color(
      _keys(periphery).color('background_color'),
    );
    final borderColor = borderWidth > 0
        ? pdfColorOf(
            _keys(periphery).color('border_color') ?? _c('base_border_color'),
          )
        : null;
    // (`page_layer_clip: page`: the background and border clipped to the
    // page, as asciidoctor-pdf's stamps are by their bounding box.)
    final clipToPage = _pageLayerClip;
    if (background != null || (borderWidth > 0 && borderColor != null)) {
      pieces.add((pdfPage) {
        final canvas = pdfPage.canvas;
        if (clipToPage) {
          canvas
            ..save()
            ..rect(Rect(0, 0, pageWidth, pageHeight))
            ..clip();
        }
        if (background != null) {
          canvas
            ..save()
            ..setFillColor(background)
            ..rect(Rect(left, top - height, width, height))
            ..fill()
            ..restore();
        }
        if (borderWidth > 0 && borderColor != null) {
          PdfConverter._horizontalRule(
            canvas,
            borderColor,
            left,
            left + width,
            periphery == 'header' ? top - height : top,
            borderWidth,
            _keys(periphery).string('border_style'),
          );
        }
        if (clipToPage) canvas.restore();
      });
    }
    // The background image, in the middle of the running content's area.
    if (_runningBackgrounds.putIfAbsent(
          periphery,
          () => _resolveBackgroundImage('${periphery}_background_image')?.image,
        )
        case final image?) {
      pieces.add((pdfPage) {
        final canvas = pdfPage.canvas
          ..save()
          ..translate(left, top - height);
        _drawPageImage(canvas, image, size: (width, height));
        canvas.restore();
      });
    }
    // Rules between columns, a spacing apart (the gem leaves the spacing
    // out of each column after the first, and half of it out of the
    // first).
    final ruleWidth = (_keys(periphery).number('column_rule_width') ?? 0)
        .toDouble();
    final ruleColor = ruleWidth > 0
        ? pdfColorOf(_keys(periphery).color('column_rule_color'))
        : null;
    final ruleSpacing = (_keys(periphery).number('column_rule_spacing') ?? 0)
        .toDouble();
    final ruleStyle = _keys(periphery).string('column_rule_style');
    String? previous;
    // (A page that opens a part or chapter, where its running content
    // shows there, by the theme's `<periphery>_opener` columns when it
    // has any, in place of the side's: a schoolbook's folio at the foot of
    // its opening pages alone, in brackets.)
    final columnsOf =
        _openerPages.contains(number) &&
            const ['left', 'center', 'right'].any(
              (position) =>
                  _keys(periphery).string('opener_${position}_content') != null,
            )
        ? 'opener'
        : side;
    for (final position in const ['left', 'center', 'right']) {
      var template = _keys(periphery)
          .string('${columnsOf}_${position}_content');
      if (template == null || template.isEmpty) continue;
      var (align, columnWidth, x) = columns[position]!;
      if (columnWidth <= 0) continue;
      if (ruleColor != null && columnWidth < contentWidth) {
        if (previous != null) {
          // (Between it and the column before, at its start.)
          final ruleX = contentLeft + x + (mirror ? columnWidth : 0);
          final ruleTop = top - padding[0] - contentOffset;
          pieces.add(
            (pdfPage) => PdfConverter._verticalRule(
              pdfPage.canvas,
              ruleColor,
              ruleX,
              ruleTop,
              ruleTop - contentHeight,
              ruleWidth,
              ruleStyle,
            ),
          );
          if (!mirror) x += ruleSpacing * 0.5;
          columnWidth -= ruleSpacing;
        } else {
          columnWidth -= ruleSpacing * 0.5;
        }
      }
      previous = position;
      if (PdfConverter._imageMacroOf(template, const ['alt', 'width'])
          case (final rawTarget, final attrs)?) {
        final target = _applySubsDiscretely(
          rawTarget,
          const {},
          subs: const [Sub.attributes],
        );
        final format = attrs['format'] ?? PdfConverter._imageFormat(target);
        final bytes = _themeImageBytes(target);
        final graphic = bytes == null
            ? null
            : _graphicOf(bytes, format, path: _lastImagePath).$1;
        if (graphic != null) {
          final boxLeft = contentLeft + x;
          final boxTop = top - padding[0] - contentOffset;
          final imageValign = switch (_keys(periphery)
              .string('image_vertical_align')) {
            null => valign,
            'middle' => 'center',
            final other => other,
          };
          pieces.add(
            (pdfPage) => _runningImage(
              pdfPage,
              graphic,
              attrs,
              Rect(boxLeft, boxTop - contentHeight, columnWidth, contentHeight),
              align,
              imageValign,
            ),
          );
          continue;
        }
        // Not readable: the macro's text reports it and shows the alt text.
        final attrlist = template.substring(
          template.indexOf('[') + 1,
          template.length - 1,
        );
        template = 'image:$target[$attrlist]';
      }
      final font = _themeFont('${periphery}_${side}_$position', baseFont);
      String? content;
      if (template == '{page-number}') {
        content = doc.hasAttr('pagenums') ? label : null;
      } else {
        // A Mustache template (ADR-0010; optional parts) first, then the
        // gem's attribute references.
        content = _applySubsDiscretely(
          template.contains('{{') ? _render(template, attributes) : template,
          attributes,
          unset: const {
            'part-numeral',
            'chapter-numeral',
          }.difference(attributes.keys.toSet()),
          dropLines: true,
        );
        if (font.transform case final transform? when transform != 'none') {
          content = transformText(content, transform, language: _language);
        }
      }
      if (content == null || content.isEmpty) continue;
      final prawnFont = _fonts.font(font.family, font.style);
      final box = _textBox(
        content,
        font.copyWith(lineHeight: baseFont.lineHeight),
        align: align,
        gaps: false,
        // (The page's sides: a running head's columns aren't mirrored,
        // and run across on a vertical page.)
        mirrored: false,
        vertical: false,
      );
      var y = top - padding[0] - contentOffset;
      if (valign == 'center') y -= prawnFont.descenderAt(font.size) * 0.5;
      final placed = box.place(columnWidth, proseHeight, atTop: true);
      if (placed == null) continue;
      final shift = switch (valign) {
        'center' =>
          (proseHeight - placed.height - prawnFont.descenderAt(font.size)) *
              0.5,
        'bottom' => proseHeight - placed.height,
        _ => 0.0,
      };
      pieces.add(
        (pdfPage) => placed.paint(pdfPage, contentLeft + x, y - shift),
      );
    }
    if (pieces.isEmpty) return const [];
    return [
      CustomBox(
        _Absolute((pdfPage) {
          for (final piece in pieces) {
            piece(pdfPage);
          }
        }),
      ),
    ];
  }

  /// Draws the running content image [graphic] in [box] (its width from
  /// [attrs], else fit to the box), aligned (the gem's image in
  /// `ink_running_content`).
  void _runningImage(
    LayoutPage page,
    Graphic graphic,
    Map<String, String> attrs,
    Rect box,
    String align,
    String valign,
  ) {
    final width = _imageWidthOf(
      (name) => attrs[name],
      fallback: false,
    ).resolve(box.width, _pageSize(_document).$1);
    final (naturalWidth, naturalHeight) = switch (graphic) {
      final SvgImage svg => prawnSvgSize(
        svg,
        null,
        null,
        box.width,
        box.height,
      ),
      final other => (other.intrinsicWidth, other.intrinsicHeight),
    };
    final ratio = naturalHeight / naturalWidth;
    double w;
    double h;
    if (width != null) {
      (w, h) = (width, width * ratio);
    } else if (naturalWidth / naturalHeight > box.width / box.height) {
      (w, h) = (box.width, box.width * ratio);
    } else {
      (w, h) = (box.height / ratio, box.height);
    }
    final left = switch (align) {
      'center' => box.left + (box.width - w) / 2,
      'right' => box.right - w,
      _ => box.left,
    };
    final top = switch (valign) {
      'center' => box.top - (box.height - h) / 2,
      'bottom' => box.bottom + h,
      _ => box.top,
    };
    final rect = Rect(left, top - h, w, h);
    final canvas = page.canvas;
    switch (graphic) {
      case final PdfImage image:
        image.paint(canvas, rect);
      case final other:
        canvas.save();
        other.paint(canvas, rect);
        canvas.restore();
    }
    if (attrs['link'] case final link?) {
      page.link(
        rect,
        link.startsWith('#')
            ? LinkTarget.named(destinationName(link.substring(1)))
            : LinkTarget.uri(link),
      );
    }
  }

  /// The part or chapter [page] is in (a chapter before the part it is
  /// in), if any.
  Section? _pageSection(PageInfo page) {
    Section? at(String? mark) {
      final index = int.tryParse(mark ?? '');
      return index == null || index >= _sections.length
          ? null
          : _sections[index].$1;
    }

    final part = int.tryParse(page.mark('part') ?? '') ?? -1;
    final chapter = int.tryParse(page.mark('chapter') ?? '') ?? -1;
    return chapter > part ? at(page.mark('chapter')) : at(page.mark('part'));
  }

  /// The attributes the running content of [page] refers to: the
  /// document's, with the page number, the page count and the titles of
  /// the part, chapter and section the page is in.
  Map<String, String> _runningAttributes(
    String periphery,
    PageInfo page,
    String label,
  ) {
    final doc = _document;
    final book = doc.doctype == 'book';
    final attributes = <String, String>{};
    final title = doc.hasHeader
        ? doc.partitionedTitle(separator: doc.attr('title-separator'))
        : DocumentTitle(
            doc.attr('untitled-label') ?? '',
            separator: doc.attr('title-separator'),
          );
    if (title != null) {
      attributes['doctitle'] = title.combined;
      attributes['document-title'] = title.main;
      if (title.subtitle case final subtitle?) {
        attributes['document-subtitle'] = subtitle;
      }
    }
    attributes['page-count'] = '${page.count - _skip.$2}';
    if (doc.hasAttr('pagenums')) attributes['page-number'] = label;
    // `<periphery>_title_style`: `document` (the default) as headings are
    // titled, `toc` as the contents list them, `basic` without numbers.
    final titleStyle = _keys(periphery).string('title_style');
    String titleOf(String? mark) {
      final index = int.tryParse(mark ?? '');
      if (index == null || index >= _sections.length) return '';
      final section = _sections[index].$1;
      return switch (titleStyle) {
        'basic' => section.title ?? '',
        'toc' => _numberedTitle(section, formal: false),
        _ => _numberedTitle(section),
      };
    }

    // The numeral of a numbered part or chapter (none for a preface, the
    // table of contents, an unnumbered section).
    String? numeralOf(String? mark) {
      final index = int.tryParse(mark ?? '');
      if (index == null || index >= _sections.length) return null;
      return _sections[index].$1.numeral;
    }

    // The first and last mark on the page (`running_content_marks`): a
    // Bible's first and last verse, `{page-first-mark}–{page-last-mark}`.
    if (_pageMarks.elementAtOrNull(page.number - 1) case (
      final first,
      final last,
    )) {
      attributes['page-first-mark'] = _markText(first);
      attributes['page-last-mark'] = _markText(last);
    }
    // Each column's (`{column-1-last-mark}`): the guide words a dictionary
    // heads each of its columns with.
    if (_columnMarks.elementAtOrNull(page.number - 1) case final columns?) {
      for (final (i, marks) in columns.indexed) {
        if (marks case (final first, final last)) {
          attributes['column-${i + 1}-first-mark'] = _markText(first);
          attributes['column-${i + 1}-last-mark'] = _markText(last);
        }
      }
    }
    // The printer's signature (`{page-signature}`), on the first page of
    // each gathering.
    if (_signatureOf(page.number - _skip.$2) case final signature?) {
      attributes['page-signature'] = signature;
    }
    // The catchword (`{page-catchword}`), the next page's first word.
    if (_catchwords.elementAtOrNull(page.number - 1) case final word?) {
      attributes['page-catchword'] = word;
    }
    // The page's units (`running_content_units`): `{page-units}` is the
    // range they make as their scheme cites it, what its ends share said
    // once (`Gen 2:20–3:7`; `{page-units-long}`: `Genesis 2:20–3:7`).
    if (_pageUnits.elementAtOrNull(page.number - 1) case (
      final first,
      final last,
    )) {
      final config = _document.unitsSession!.config;
      attributes
        ..['page-first-unit'] = passageText(Passage(first, first), config)
        ..['page-last-unit'] = passageText(Passage(last, last), config)
        ..['page-units'] = passageText(Passage(first, last), config)
        ..['page-units-long'] = passageText(
          Passage(first, last),
          config,
          long: true,
        );
      // Structured: each level's label at the page's first and last unit
      // (`{page-first-chapter}`, `{page-last-verse}`), for a template of
      // its own (`{page-first-chapter}:{page-first-verse}`).
      for (final (unit, end) in [(first, 'first'), (last, 'last')]) {
        final levels = unit.level.scheme.levels;
        for (final (i, label) in unit.labels.indexed) {
          if (label == null || i >= levels.length) continue;
          attributes['page-$end-${levels[i].name}'] = levels[i].bare(label);
        }
      }
    }
    final sectlevels = (_keys(periphery).number('sectlevels') ?? 2).toInt();
    final partMark = page.mark('part');
    var chapterMark = page.mark('chapter');
    var sectionMark = page.mark('section-$sectlevels');
    // A part ends the chapter before it, and a part or a chapter the
    // section before it.
    final partIndex = int.tryParse(partMark ?? '') ?? -1;
    final chapterIndex = int.tryParse(chapterMark ?? '') ?? -1;
    final sectionIndex = int.tryParse(sectionMark ?? '') ?? -1;
    final partStarted = partMark != null && partMark.isNotEmpty;
    if (partStarted && chapterIndex < partIndex) chapterMark = null;
    if (sectionIndex < math.max(partStarted ? partIndex : -1, chapterIndex)) {
      sectionMark = null;
    }
    final part = titleOf(partMark);
    String chapter;
    String? chapterNumeral;
    String section;
    final toc = _tocPages;
    if (toc != null && page.number >= toc.$1 && page.number <= toc.$2) {
      final tocTitle = doc.attr('toc-title') ?? '';
      if (book) {
        chapter = tocTitle;
        section = '';
      } else {
        chapter = '';
        section = sectionMark == null ? tocTitle : titleOf(sectionMark);
      }
    } else if (book && chapterMark == null && !partStarted) {
      chapter = page.number < _bodyStart
          ? doc.doctitle() ?? ''
          : doc.attr('preface-title') ??
                (doc.attributes.containsKey('preface-title') ? '' : 'Preface');
      section = titleOf(sectionMark);
    } else {
      chapter = titleOf(chapterMark);
      chapterNumeral = numeralOf(chapterMark);
      section = titleOf(sectionMark);
    }
    attributes['part-title'] = part;
    if (numeralOf(partMark) case final numeral?) {
      attributes['part-numeral'] = numeral;
    }
    attributes['chapter-title'] = chapter;
    attributes['chapter-title-spread'] = _spreadTitle(
      chapterMark,
      page,
      chapter,
    );
    if (chapterNumeral case final numeral?) {
      attributes['chapter-numeral'] = numeral;
    }
    attributes['section-title'] = section;
    attributes['section-or-chapter-title'] = section.isNotEmpty
        ? section
        : chapter;
    // As a running head sees it at the page's top (TeX's `\topmark`): the
    // last part or
    // chapter that started before the page, else the document's title.
    // (A section without a shown title, a dedication, has no heading.)
    int shown(String? mark) => switch (int.tryParse(mark ?? '')) {
      final index?
          when index < _sections.length &&
              !_sections[index].$1.hasOption('notitle') =>
        index,
      _ => -1,
    };
    final topPart = shown(page.topMark('part'));
    final topChapter = shown(page.topMark('chapter'));
    if (topChapter > topPart) {
      attributes['top-title'] = titleOf('$topChapter');
      if (numeralOf('$topChapter') case final numeral?) {
        attributes['top-numeral'] = numeral;
      }
    } else if (topPart >= 0) {
      attributes['top-title'] = titleOf('$topPart');
    } else {
      attributes['top-title'] = doc.doctitle() ?? '';
    }
    return attributes;
  }

  /// The printer's signature on page [number] (`{page-signature}`): the
  /// letter that marks the first page of each gathering for the binder,
  /// every `running_content_signature_interval` pages (16, an octavo in
  /// sixteens) from page `_signature_first` (1), lettered from
  /// `_signature_start` (`B`, the title's gathering being A) in the
  /// printers' alphabet (`_signature_letters`, `ABCDEFGHIKLMNOPQRSTUXYZ`:
  /// no J, V or W), doubled once it runs out (`AA`, `BB`); numbered
  /// instead with `_signature_numbering: decimal`, from `_signature_start`
  /// (1), as a nineteenth-century American schoolbook numbers its
  /// gatherings (the footer's `2, {page-signature}.`, the Second Reader's
  /// second); null on the other pages.
  String? _signatureOf(int number) {
    final keys = _keys('running_content_signature');
    final interval = (keys.number('interval') ?? 16).toInt();
    final first = (keys.number('first') ?? 1).toInt();
    if (interval < 1 || number < first) return null;
    // (`_signature_signed`: the gathering's first leaves signed, each its
    // recto, the first by its letter, the others by its letter and the
    // leaf's number (`_signature_leaf_template`, `{{signature}} {{leaf}}`:
    // a duodecimo's A, A 2 … A 6).)
    final signed = (keys.number('signed') ?? 1).toInt();
    final offset = (number - first) % interval;
    if (offset.isOdd || offset ~/ 2 >= math.max(1, signed)) return null;
    final leaf = offset ~/ 2 + 1;
    final gathering = number - offset;
    // (Worded by `_signature_template`, `{{signature}}` the letter or the
    // number: the Second Reader's `2, {{signature}}.`.)
    String worded(String signature) {
      final mark = leaf == 1
          ? signature
          : (keys.string('leaf_template') ?? '{{signature}} {{leaf}}')
                .replaceAll('{{signature}}', signature)
                .replaceAll('{{leaf}}', '$leaf');
      return switch (keys.string('template')) {
        final template? => template.replaceAll('{{signature}}', mark),
        null => mark,
      };
    }

    if (keys.string('numbering') == 'decimal') {
      final start =
          keys.number('start')?.toInt() ??
          int.tryParse(keys.string('start') ?? '') ??
          1;
      return worded('${start + (gathering - first) ~/ interval}');
    }
    final letters = keys.string('letters') ?? 'ABCDEFGHIKLMNOPQRSTUXYZ';
    final start = letters.indexOf(keys.string('start') ?? 'B');
    final index = (start < 0 ? 0 : start) + (gathering - first) ~/ interval;
    final letter = letters[index % letters.length];
    return worded(letter * (index ~/ letters.length + 1));
  }

  /// The running title of the chapter [mark] names on [page]
  /// (`{chapter-title-spread}`): the chapter's `running-title`, else its
  /// [title], divided across the spread where a `|` divides it, as
  /// Victorian books divide a long title (`DOWN THE` on the verso,
  /// `RABBIT-HOLE.` on the recto); whole on a page whose facing page has
  /// no running head of the chapter (a verso before a chapter's opening
  /// page or the end, a recto after one).
  String _spreadTitle(String? mark, PageInfo page, String title) {
    final index = int.tryParse(mark ?? '');
    final section = index == null || index >= _sections.length
        ? null
        : _sections[index].$1;
    // (The section's own, else the document's: one for every chapter, a
    // schoolbook's series and title.)
    final running =
        section?.attr('running-title', null, 'running-title') ??
        _document.attr('running-title');
    if (running == null) return title;
    final bar = running.indexOf('|');
    if (bar < 0) return running;
    final whole =
        '${running.substring(0, bar).trimRight()} '
        '${running.substring(bar + 1).trimLeft()}';
    final number = page.number;
    final virtual = number - _skip.$2;
    final verso = _sideOf(_folio.physical ? number : virtual) == 'verso';
    final facing = verso ? number + 1 : number - 1;
    // (`running_content_spread_whole: false`: divided on every page, as a
    // schoolbook's series and title head its versos and rectos whatever
    // faces them.)
    if (_theme.value('running_content_spread_whole') !=
            const ThemeBool(false) &&
        (facing < 1 ||
            facing > page.count ||
            _openerPages.contains(facing) ||
            _openerPages.contains(number))) {
      return whole;
    }
    return verso
        ? running.substring(0, bar).trim()
        : running.substring(bar + 1).trim();
  }

  /// [value] with the document's normal substitutions (or [subs]), with
  /// [attributes] set, those of [unset] removed and missing attributes
  /// skipped; with [dropLines], each line with a reference that didn't
  /// resolve is dropped (the gem's `apply_subs_discretely`).
  String _applySubsDiscretely(
    String value,
    Map<String, String> attributes, {
    Set<String> unset = const {},
    List<Sub>? subs,
    bool dropLines = false,
  }) {
    final doc = _document;
    final docAttributes = doc.attributes;
    final saved = <String, String?>{
      for (final key in [...attributes.keys, ...unset, 'attribute-missing'])
        key: docAttributes[key],
    };
    unset.forEach(docAttributes.remove);
    docAttributes
      ..addAll(attributes)
      ..['attribute-missing'] = 'skip';
    final escaped = value.contains(r'\{');
    var text = escaped ? value.replaceAll(r'\{', r'\\\{') : value;
    final before = text;
    try {
      text = subs == null ? doc.applySubs(text) : doc.applySubs(text, subs);
    } finally {
      for (final MapEntry(:key, :value) in saved.entries) {
        if (value == null) {
          docAttributes.remove(key);
        } else {
          docAttributes[key] = value;
        }
      }
    }
    if (dropLines && text.contains('{')) {
      text = text
          .split('\n')
          .where((line) {
            final match = PdfConverter._attributeReference.firstMatch(line);
            return match == null || !before.contains('{${match[1]}}');
          })
          .join('\n');
    }
    return escaped ? text.replaceAll(r'\{', '{') : text;
  }
}

/// The catchword of a page whose next page starts with [text]: its first
/// word, with the word after it when that is a number (a dictionary's
/// sense, `2. One`), escaped for running content; a word opening with a
/// drop initial and the capital printed after it (`LOrd,`) in its own
/// case (`Lord,`).
String? _catchwordOf(String? text) {
  if (text == null) return null;
  final words = text.trim().split(RegExp(r'\s+'));
  if (words.isEmpty || words.first.isEmpty) return null;
  var first = words.first;
  if (RegExp(r'^\p{Lu}\p{Lu}\p{Ll}', unicode: true).hasMatch(first)) {
    first = '${first[0]}${first[1].toLowerCase()}${first.substring(2)}';
  }
  final numeral = RegExp(r'^(\d+|[ivxlcdm]+|[IVXLCDM]+)[.)]?$|^\W+$')
      .hasMatch(first);
  final word = numeral && words.length > 1 ? '$first ${words[1]}' : first;
  return word
      .replaceAll('\u00ad', '')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;');
}
