part of '../converter.dart';

// Tables.

extension _Tables on PdfConverter {
  /// Converts the table [node] (the gem's `convert_table`, prawn-table's
  /// layout on plain_pdf's tables).
  void convertTable(Table node) {
    // The modern engine styles a table with a role by the theme's
    // table_role_<role>_* keys, over its table_* keys.
    if (node.roles.isNotEmpty) {
      final saved = _theme;
      for (final role in node.roles) {
        _theme = _theme.overlaid(
          'table_role_${role.replaceAll('-', '_')}_',
          'table_',
        );
      }
      if (!identical(_theme, saved)) {
        try {
          _convertTable(node);
        } finally {
          _theme = saved;
        }
        return;
      }
    }
    _convertTable(node);
  }

  void _convertTable(Table node) {
    final captionTop = (_s('table_caption_end') ?? 'top') == 'top';
    final unbreakable = node.hasOption('unbreakable');
    final outside = _font;
    final boxes = _collect(
      () => _withFont('table', () => _table(node, outside: outside)),
    );
    if (boxes.isEmpty) return;
    var caption = node.hasTitle
        ? _captionBox(
            node,
            category: 'table',
            bottom: !captionTop,
            blockAlign: _tableAlign,
          )
        : null;
    if (caption != null) {
      caption = _fitCaption(
        caption,
        _tableWidth,
        setting: _s('table_caption_max_width') ?? 'fit-content',
        captionKey: 'table_caption',
        blockAlign: _tableAlign,
      );
    }
    final next = _nextEnclosedBlock(node);
    final margin = _marginBelow(node, next: next);
    _out.add(
      BlockBox(
        [if (captionTop) ?caption, ...boxes, if (!captionTop) ?caption],
        style: BoxStyle(
          anchor: node.id,
          keepTogether: unbreakable,
          margin: EdgeInsets(bottom: margin),
        ),
      ),
    );
  }

  /// The [caption] of a block as wide as [tableWidth] gives for the room
  /// no wider than [setting] says (`fit-content`, `fit-content(N%)`, a
  /// percentage or a width; the gem's `ink_caption` with a block width);
  /// [captionKey] is its theme category (`table_caption`...), [blockAlign]
  /// the block's alignment.
  CustomBox _fitCaption(
    CustomBox caption,
    double Function(double width) tableWidth, {
    required String? setting,
    required String captionKey,
    required String blockAlign,
  }) {
    if (setting == null || setting == 'none') return caption;
    var align = _keys(captionKey).string('align') ?? _s('caption_align');
    if (align == 'inherit') align = blockAlign;
    align ??= _baseTextAlign;
    (double, double) indents(double width) {
      var left = 0.0;
      var right = 0.0;
      double maxWidth;
      var by = blockAlign;
      if (setting.startsWith('fit-content')) {
        final block = tableWidth(width);
        final percent = RegExp(r'^fit-content\((\d+(?:\.\d+)?)%?\)$')
            .firstMatch(setting);
        if (percent != null) {
          final delta = block - block * PdfConverter._toF(percent[1]!) / 100;
          if (delta > 0) {
            switch (align) {
              case 'right':
                left += delta;
              case 'center':
                left += delta / 2;
                right += delta / 2;
              default:
                right += delta;
            }
          }
        }
        maxWidth = block;
      } else if (setting.endsWith('%')) {
        maxWidth = math.min(PdfConverter._toF(setting) / 100 * width, width);
        by = align!;
      } else {
        maxWidth = math.min(PdfConverter._toF(setting), width);
        by = align!;
      }
      final remainder = width - maxWidth;
      if (remainder > 0) {
        switch (by) {
          case 'right':
            left += remainder;
          case 'center':
            left += remainder / 2;
            right += remainder / 2;
          default:
            right += remainder;
        }
      }
      return (left, right);
    }

    return CustomBox(_Indented(caption.content, indents), style: caption.style);
  }

  /// Lays out the table [node] in the table's font; AsciiDoc cells use the
  /// font [outside] the table when the theme's `table_asciidoc_cell_style`
  /// is `initial`.
  void _table(Table node, {required _FontState outside}) {
    final rows = node.rows;
    final numRows = rows.head.length + rows.body.length + rows.foot.length;
    // (A table without rows or columns gets one empty cell, as the gem's.)
    final numCols = math.max(node.columns.length, 1);
    ThemeColor? color(String key, [ThemeColor? fallback]) {
      final value = _c(key);
      return value is TransparentColor ? fallback : value ?? fallback;
    }

    final tableBackground = color('table_background_color');
    final headBackground = color(
      'table_head_background_color',
      tableBackground,
    );
    final footBackground = color(
      'table_foot_background_color',
      tableBackground,
    );
    final bodyBackground = color(
      'table_body_background_color',
      tableBackground,
    );
    final stripeBackground = color(
      'table_body_stripe_background_color',
      tableBackground,
    );
    final bodyPadding = _edgeValues(
      _theme.value('table_cell_padding') ?? const ThemeNumber(0),
    );
    final tableFont = _font;

    // The cells, row by row: (row, column, cell data).
    final grid = <List<_TableCellData>>[];
    final headFont = _themeFont('table_head', tableFont);
    if (rows.head.isNotEmpty) {
      final lineHeight =
          (_n('table_head_line_height') ??
                  _n('table_cell_line_height') ??
                  headFont.lineHeight)
              .toDouble();
      final font = headFont.copyWith(lineHeight: lineHeight);
      final metrics = _lineMetrics(font);
      final padding = _theme.value('table_head_cell_padding') == null
          ? [...bodyPadding]
          : _edgeValues(_theme.value('table_head_cell_padding'));
      padding[0] += metrics.paddingTop;
      padding[2] += metrics.paddingBottom;
      final transform = _s('table_head_text_transform');
      for (final row in rows.head) {
        grid.add([
          for (final cell in row)
            _TableCellData(
              text: _hyphenated(
                transform == null || transform == 'none'
                    ? cell.text.trim()
                    : transformText(
                        cell.text.trim(),
                        transform,
                        language: _language,
                      ),
                cell.attr('halign') ?? 'left',
              ),
              font: font,
              padding: padding,
              background: headBackground,
              colspan: cell.colspan ?? 1,
              rowspan: 1,
              align: cell.attr('halign') ?? 'left',
              valign: cell.attr('valign') ?? 'top',
            ),
        ]);
      }
    }
    final bodyLineHeight =
        (_n('table_cell_line_height') ?? tableFont.lineHeight).toDouble();
    final bodyFont = tableFont.copyWith(lineHeight: bodyLineHeight);
    for (final row in [...rows.body, ...rows.foot]) {
      final cells = <_TableCellData>[];
      for (final cell in row) {
        var font = bodyFont;
        ThemeColor? background;
        String? transform;
        var inline = true;
        var cellAlign = cell.attr('halign') ?? 'left';
        String? content;
        List<LayoutBox>? blocks;
        switch (cell.style) {
          case 'emphasis':
            font = font.copyWith(style: 'italic');
          case 'strong':
            font = font.copyWith(style: 'bold');
          case 'header':
            final header = _themeFont(
              'table_header_cell',
              _themeFont('table_head', tableFont),
            );
            font = header;
            transform = header.transform;
            background = color(
              'table_header_cell_background_color',
              headBackground,
            );
          case 'monospaced':
            final mono = _themeFont('codespan', tableFont);
            font = mono.copyWith(
              style: tableFont.style,
              lineHeight: tableFont.lineHeight,
            );
          case 'literal':
            content = PdfConverter._guardIndentation(cell.sourceText ?? '');
            inline = false;
            final code = _themeFont('code', tableFont);
            font = code.copyWith(
              style: tableFont.style,
              size: code.size * (bodyFont.size / _rootFontSize),
            );
          case 'asciidoc':
            if (cell.innerDocument case final inner?) {
              // Paragraphs alone follow the cell's alignment.
              final halign = cell.attr('halign');
              final savedAlign = _baseTextAlign;
              if ((halign == 'center' || halign == 'right') &&
                  inner.blocks.isNotEmpty &&
                  inner.blocks.every(
                    (b) => b.context == BlockContext.paragraph,
                  )) {
                _baseTextAlign = halign!;
              }
              final savedFont = _font;
              if (_s('table_asciidoc_cell_style') == 'initial') {
                _font = outside;
              }
              // The modern engine's `table_base_*` keys: the base keys of
              // the cells' blocks (`table_base_text_align_last`...).
              final savedTheme = _theme;
              _theme = _theme.overlaid('table_base_', 'base_');
              // A cell's own alignment comes first.
              if (_s('table_base_text_align') case final align?
                  when _baseTextAlign == savedAlign) {
                _baseTextAlign = align;
              }

              try {
                blocks = _collect(() => _traverse(inner));
                // The cell's footnotes are the document's (listed with
                // its own), as the gem shares the catalog's list.
                for (final footnote in inner.footnotes) {
                  if (!_document.footnotes.contains(footnote)) {
                    _document.footnotes.add(footnote);
                  }
                }
              } finally {
                _baseTextAlign = savedAlign;
                _font = savedFont;
                _theme = savedTheme;
              }
            }
        }
        final List<double> padding;
        if (blocks != null) {
          padding = [...bodyPadding];
        } else {
          final metrics = _lineMetrics(font);
          padding = [...bodyPadding];
          padding[0] += metrics.paddingTop;
          padding[2] += metrics.paddingBottom;
        }
        if (content == null && blocks == null) {
          var text = cell.text.trim();
          if (transform != null && transform != 'none') {
            text = transformText(text, transform, language: _language);
          }
          text = _hyphenated(text, cell.attr('halign') ?? 'left');
          if (_cjkLineBreaks) text = PdfConverter._breakCjk(text);
          content = text;
          // The modern engine styles a cell whose whole text has a role
          // (`[.paid]#Paid#`) by the theme's table_cell_role_<role>_*
          // keys.
          if (PdfConverter._cellRole(text) case final role?) {
            final key = 'table_cell_role_${role.replaceAll('-', '_')}';
            background = _keys(key).color('background_color') ?? background;
            font = _themeFont(key, font);
            cellAlign = _keys(key).string('text_align') ?? cellAlign;
          }
        }
        cells.add(
          _TableCellData(
            text: content ?? '',
            blocks: blocks,
            font: font,
            padding: padding,
            background: background,
            colspan: cell.colspan ?? 1,
            rowspan: cell.rowspan ?? 1,
            align: cellAlign,
            valign: cell.attr('valign') ?? 'top',
            inlineFormat: inline,
          ),
        );
      }
      grid.add(cells);
    }
    if (grid.isEmpty) {
      logger.warn('no rows found in table');
      grid.add([
        for (var c = 0; c < numCols; c++)
          // prawn-table's own cell: its default padding.
          _TableCellData(
            text: '',
            font: bodyFont,
            padding: const [5, 5, 5, 5],
            colspan: 1,
            rowspan: 1,
            align: 'left',
            valign: 'top',
          ),
      ]);
    }

    // Borders.
    const transparent = ThemeString('transparent');
    final borderColor = PdfConverter._rectValues(
      _theme.value('table_border_color'),
      transparent,
    );
    final borderStyle = PdfConverter._rectValues(
      _theme.value('table_border_style'),
      const ThemeString('solid'),
    );
    final borderWidth = [
      for (final v in PdfConverter._rectValues(
        _theme.value('table_border_width'),
        const ThemeNumber(0),
      ))
        PdfConverter._width(v),
    ];
    final gridColor = PdfConverter._gridValues(
      _theme.value('table_grid_color') ??
          ThemeList([borderColor[0]!, borderColor[3]!]),
      transparent,
    );
    final gridStyle = PdfConverter._gridValues(
      _theme.value('table_grid_style') ??
          ThemeList([borderStyle[0]!, borderStyle[3]!]),
      const ThemeString('solid'),
    );
    final gridWidth = [
      for (final v in PdfConverter._gridValues(
        _theme.value('table_grid_width') ??
            ThemeList([
              ThemeNumber(borderWidth[0]),
              ThemeNumber(borderWidth[3]),
            ]),
        const ThemeNumber(0),
      ))
        PdfConverter._width(v),
    ];
    final headerSize = rows.head.length;
    final headBottomColor =
        _theme.value('table_head_border_bottom_color') ?? gridColor[0];
    final headBottomStyle =
        _theme.value('table_head_border_bottom_style') ?? gridStyle[0];
    final headBottomWidth =
        (_n('table_head_border_bottom_width') ?? gridWidth[0] * 2.5).toDouble();
    final gridSetting =
        node.attr('grid') ?? _document.attr('table-grid') ?? 'all';
    switch (gridSetting) {
      case 'all':
        break;
      case 'cols':
        gridWidth[0] = 0;
      case 'rows':
        gridWidth[1] = 0;
      default:
        gridWidth[0] = gridWidth[1] = 0;
    }
    final frame = node.attr('frame') ?? _document.attr('table-frame') ?? 'all';
    switch (frame) {
      case 'all':
        break;
      case 'topbot' || 'ends':
        borderWidth[1] = borderWidth[3] = 0;
      case 'sides':
        borderWidth[0] = borderWidth[2] = 0;
      default:
        borderWidth[0] = borderWidth[1] = borderWidth[2] = borderWidth[3] = 0;
    }

    // Each cell's place in the grid, skipping the columns spans take.
    final taken = <(int, int)>{};
    final placed = <(int, int, _TableCellData)>[];
    for (final (r, row) in grid.indexed) {
      var c = 0;
      for (final data in row) {
        while (taken.contains((r, c))) {
          c++;
        }
        placed.add((r, c, data));
        for (var dr = 0; dr < data.rowspan; dr++) {
          for (var dc = 0; dc < data.colspan; dc++) {
            taken.add((r + dr, c + dc));
          }
        }
        c += data.colspan;
      }
    }

    // Stripes (prawn-table's row colors, counted from the first body row).
    final stripes = switch (node.attr('stripes') ??
        _document.attr('table-stripes')) {
      'all' => [stripeBackground],
      'even' => [bodyBackground, stripeBackground],
      'odd' => [stripeBackground, bodyBackground],
      _ => [bodyBackground],
    };
    final footRow = rows.foot.isEmpty ? -1 : numRows - 1;
    final footColor = _c('table_foot_font_color');
    final footSize = _n('table_foot_font_size')?.toDouble();
    final footFamily = _s('table_foot_font_family');
    final footStyle = _s('table_foot_font_style');

    final tableRows = <List<TableCell>>[for (final _ in grid) []];
    for (final (r, c, data) in placed) {
      var font = data.font;
      var background = data.background;
      if (r == footRow) {
        background = footBackground;
        font = font.copyWith(
          color: footColor,
          size: footSize,
          family: footFamily,
          style: footStyle,
        );
      }
      final lastRow = r + data.rowspan - 1;
      final lastCol = c + data.colspan - 1;
      // Grid lines, then the header's bottom border, then the frame.
      final sides = <_Side>[
        _Side(gridWidth[0], gridColor[0], gridStyle[0]),
        _Side(gridWidth[1], gridColor[1], gridStyle[1]),
        _Side(gridWidth[0], gridColor[0], gridStyle[0]),
        _Side(gridWidth[1], gridColor[1], gridStyle[1]),
      ];
      if (gridSetting == 'none' && frame == 'none') {
        for (var i = 0; i < 4; i++) {
          sides[i] = const _Side(0, null, null);
        }
      }
      if (headerSize > 0) {
        final head = _Side(headBottomWidth, headBottomColor, headBottomStyle);
        if (lastRow == headerSize - 1) sides[2] = head;
        if (gridSetting != 'none' || frame != 'none') {
          if (r == headerSize && numRows > headerSize) sides[0] = head;
        }
      }
      if (gridSetting != 'none' || frame != 'none') {
        if (r == 0) {
          sides[0] = _Side(borderWidth[0], borderColor[0], borderStyle[0]);
        }
        if (lastCol == numCols - 1) {
          sides[1] = _Side(borderWidth[1], borderColor[1], borderStyle[1]);
        }
        if (lastRow == numRows - 1) {
          sides[2] = _Side(borderWidth[2], borderColor[2], borderStyle[2]);
        }
        if (c == 0) {
          sides[3] = _Side(borderWidth[3], borderColor[3], borderStyle[3]);
        }
      }
      tableRows[r].add(_tableCell(data, font, background, sides));
    }

    // A column with no width can't hold its text: prawn-table gives up
    // on the table (the gem reports it and leaves the table out).
    if (!node.hasOption('autowidth')) {
      final (pageWidth, _) = _pageSize(_document);
      final contentWidth =
          (pageWidth - _pageMargins(_document).horizontal) * node.pcwidth / 100;
      for (final (_, c, data) in placed) {
        final column = node.columns.elementAtOrNull(c);
        if (column == null || data.colspan != 1 || data.blocks != null) {
          continue;
        }
        // The room for the text (with prawn-table's point of tolerance)
        // and the widest character it must hold.
        final room =
            (column.pcwidth ?? 0) / 100 * contentWidth -
            data.padding[1] -
            data.padding[3] +
            1;
        final font = _fonts.font(data.font.family, data.font.style);
        final widest = [
          for (final rune in PdfConverter._plain(data.text).runes)
            if (rune > 32)
              font.widthOf(String.fromCharCode(rune), data.font.size),
        ].fold<double>(0, math.max);
        if (widest > room) {
          // The modern engine keeps the table, the text set past the
          // column's edge where it must be.
          logger.warn(
            'table column ${c + 1} is too narrow for its text; '
            'the text overflows it',
            at: node.sourceLocation,
          );
          break;
        }
      }
    }

    // Column widths: by the columns' percentages, or (autowidth) by
    // prawn-table's natural widths.
    final List<ColumnWidth> columns;
    final pc = (node.pcwidth) / 100;
    if (node.hasOption('autowidth')) {
      columns = _autoWidths(
        node,
        placed,
        numCols,
        node.hasAttr('width')
            ? pc
            : node.hasRole('stretch')
            ? 1.0
            : null,
      );
    } else if (node.columns.isEmpty) {
      // (The one empty cell of a table without rows, across its width.)
      columns = [ColumnWidth.computed((width) => width * pc)];
    } else {
      columns = [
        for (final column in node.columns)
          ColumnWidth.computed(
            (width) => (column.pcwidth ?? 0) * width * pc / 100,
          ),
      ];
    }
    // The table's width, for its caption.
    _tableWidth = (width) => [
      for (final column in columns)
        switch (column) {
          ComputedColumnWidth(width: final of) => of(width),
          FixedColumnWidth(:final points) => points,
          _ => 0.0,
        },
    ].fold<double>(0, (a, b) => a + b);
    final alignAttr = node.attr('align');
    final align =
        (alignAttr != null &&
                const {'left', 'center', 'right'}.contains(alignAttr)
            ? alignAttr
            : node.roles
                  .where(const {'left', 'center', 'right'}.contains)
                  .lastOrNull) ??
        _s('table_align') ??
        'left';
    _tableAlign = align;
    _out.add(
      TableBox(
        // (A right-to-left document's table mirrored: its first column at
        // the right.)
        [
          for (final cells in tableRows)
            TableRow(_rightToLeft ? cells.reversed.toList() : cells),
        ],
        columns: _rightToLeft ? columns.reversed.toList() : columns,
        headerRows: headerSize,
        borders:
            _choice('table_borders', const ['above', 'with-cells']) ==
                'with-cells'
            ? TableBorders.withCells
            : TableBorders.above,
        stripes: [for (final color in stripes) pdfColorOf(color)],
        cellsContainMargins:
            _choice('table_cell_margin_top', const ['drop', 'keep']) == 'keep',
        align: switch (align) {
          'center' => BoxAlign.center,
          'right' => _rightToLeft ? BoxAlign.left : BoxAlign.right,
          _ => _rightToLeft ? BoxAlign.right : BoxAlign.left,
        },
        style: BoxStyle(structure: _struct('Table')),
      ),
    );
  }

  /// The plain_pdf cell of [data] in [font], with prawn-table's borders.
  TableCell _tableCell(
    _TableCellData data,
    _FontState font,
    ThemeColor? background,
    List<_Side> sides,
  ) {
    // (A right-to-left document's table mirrored: each cell's start, its
    // left, at its right.)
    final padding = _mirrorInsets(
      EdgeInsets(
        top: data.padding[0],
        right: data.padding[1],
        bottom: data.padding[2],
        left: data.padding[3],
      ),
    );
    final List<LayoutBox> content;
    double Function(double, double)? offset;
    if (data.blocks case final blocks?) {
      content = blocks;
      if (data.valign != 'top') {
        offset = (room, height) => switch (data.valign) {
          'middle' => math.max(0, (room - height) / 2),
          _ => math.max(0, room - height),
        };
      }
    } else {
      final box = _textBox(
        data.text,
        font,
        align: data.align,
        normalize: data.inlineFormat && !data.text.contains('\n\n'),
        cell: true,
        inlineFormat: data.inlineFormat,
      );
      // (A point wider than its room, as Prawn sets a cell's text.)
      content = [
        switch (_engineOr(
          box,
          style: BoxStyle(margin: _mirrorInsets(const EdgeInsets(right: -1))),
        )) {
          final ParagraphBox paragraph => paragraph,
          _ => CustomBox(_Widened(box, 1)),
        },
      ];
      // Prawn aligns the text in a box a point taller than the room (its
      // FPTolerance), by the text's height without the trailing line gap.
      final gap = _fonts.font(font.family, font.style).lineGapAt(font.size);
      offset = switch (data.valign) {
        'middle' => (room, height) => (room + 1 - (height - gap)) / 2,
        'bottom' => (room, height) => room + 1 - (height - gap),
        _ => null,
      };
    }
    return TableCell(
      content,
      colSpan: data.colspan,
      rowSpan: data.rowspan,
      padding: padding,
      background: pdfColorOf(background),
      verticalOffset: offset,
      decoration: (page, rect, {required first, required last}) {
        final canvas = page.canvas;
        void side(_Side side, double x1, double y1, double x2, double y2) {
          final color = pdfColorOf(themeColor(side.color));
          if (side.width <= 0 || color == null) return;
          canvas
            ..save()
            ..setStrokeColor(color)
            ..setLineWidth(side.width);
          switch (side.style?.rubyString) {
            case 'dashed':
              canvas.dash([side.width * 4]);
            case 'dotted':
              canvas.dash([side.width]);
          }
          canvas
            ..moveTo(x1, y1)
            ..lineTo(x2, y2)
            ..stroke()
            ..restore();
        }

        final [top, end, bottom, start] = sides;
        final (right, left) = _rightToLeft ? (start, end) : (end, start);
        final t = rect.top;
        final b = rect.bottom;
        side(top, rect.left, t, rect.right, t);
        side(bottom, rect.left, b, rect.right, b);
        side(
          left,
          rect.left,
          t + top.width / 2,
          rect.left,
          b - bottom.width / 2,
        );
        side(
          right,
          rect.right,
          t + top.width / 2,
          rect.right,
          b - bottom.width / 2,
        );
      },
    );
  }

  /// prawn-table's column widths for an autowidth table: each column as
  /// wide as its widest text unwrapped, shrunk toward the narrowest the
  /// cells allow when that's too wide ([fraction] of the width asks a
  /// width).
  List<ColumnWidth> _autoWidths(
    Table node,
    List<(int, int, _TableCellData)> placed,
    int numCols,
    double? fraction,
  ) {
    final mWidths = <(String, String, double), double>{};
    double widthOfM(_FontState font) =>
        mWidths[(font.family, font.style, font.size)] ??= _fonts
            .font(font.family, font.style)
            .widthOf('M', font.size, kerning: font.kerning);
    List<double>? cache;
    double? cachedFor;
    List<double> widths(double available) {
      if (cache != null && cachedFor == available) return cache!;
      final naturals = List<double>.filled(numCols, 0);
      final mins = List<double>.filled(numCols, 0);
      for (final (_, c, data) in placed) {
        final padding = data.padding[1] + data.padding[3];
        final double content;
        if (data.blocks != null) {
          content = available - padding;
        } else {
          final box = _textBox(
            data.text,
            data.font,
            align: 'left',
            normalize: data.inlineFormat && !data.text.contains('\n\n'),
            cell: true,
            inlineFormat: data.inlineFormat,
          );
          content = math.min(box.intrinsicWidths().$2, available);
        }
        if (data.colspan == 1) {
          naturals[c] = math.max(naturals[c], padding + content);
          mins[c] = math.max(
            mins[c],
            padding + math.min(content, widthOfM(data.font)),
          );
        }
      }
      final natural = naturals.fold<double>(0, (a, b) => a + b);
      final least = mins.fold<double>(0, (a, b) => a + b);
      final width = fraction != null
          ? available * fraction
          : math.min(natural, available);
      List<double> result;
      if (width < natural - 1e-9 && natural > least) {
        final f = (width - least) / (natural - least);
        result = [
          for (var c = 0; c < numCols; c++)
            f * (naturals[c] - mins[c]) + mins[c],
        ];
      } else if (width > natural + 1e-9) {
        // Grown toward each column's most (the available width).
        final most = available * numCols;
        final f = (width - natural) / (most - natural);
        result = [
          for (var c = 0; c < numCols; c++)
            f * (available - naturals[c]) + naturals[c],
        ];
      } else {
        result = naturals;
      }
      cachedFor = available;
      return cache = result;
    }

    return [
      for (var c = 0; c < numCols; c++)
        ColumnWidth.computed((available) => widths(available)[c]),
    ];
  }
}
