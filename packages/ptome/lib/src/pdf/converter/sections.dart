part of '../converter.dart';

// Sections.

extension _Sections on PdfConverter {
  /// Converts [section]: its heading, then its blocks.
  void convertSection(Section section) {
    // A section whose role has page keys (modern engine): on pages of its
    // own, laid out by the role's page template, the pages after it by
    // the layout's again (a magazine's piece).
    if (_pageRoleOf(section) case final role?) {
      _pageRoles.add(role);
      _out.add(BreakBox.page(template: 'section-role-$role'));
      _section(section);
      if (!PdfConverter._lastInDocument(section)) {
        _out.add(BreakBox.page(template: _layout));
      }
      return;
    }
    _section(section);
  }

  /// The role of [section] that has a page template (any of the theme's
  /// `section_role_<role>_page_*` keys), in the modern engine.
  String? _pageRoleOf(Section section) {
    if (asciidoctorCompat(_document, CompatFormat.pdf)) return null;
    for (final role in section.roles) {
      final name = role.replaceAll('-', '_');
      if (PdfConverter._pageRoleKeys.any(
        (key) => _keys('section_role_$name').value(key) != null,
      )) {
        return name;
      }
    }
    return null;
  }

  /// The page template of the section role [role]: the layout's page,
  /// with the role's margins (`section_role_<role>_page_margin`), its
  /// background (`_page_background_color`, `_page_background_image`) and
  /// no running content when `_page_running_content` is `none`.
  PageTemplate _pageRoleTemplate(
    String role,
    PageTemplate Function(String layout) templateFor,
  ) {
    final base = templateFor(_initialLayout(_document));
    final prefix = 'section_role_${role}_page';
    final margins = switch (_keys(prefix).value('margin')) {
      null => base.margins,
      final value => switch (_edgeValues(value)) {
        [final top, final right, final bottom, final left] => EdgeInsets(
          top: top,
          right: right,
          bottom: bottom,
          left: left,
        ),
        _ => base.margins,
      },
    };
    final color = switch (_keys(prefix).color('background_color')) {
      final c? => PdfConverter._color(c),
      null => null,
    };
    final image = _resolveBackgroundImage(
      'section-role-$role-page-background-image',
      themeKey: '${prefix}_background_image',
    )?.image;
    final running = _keys(prefix).string('running_content') != 'none';
    return PageTemplate(
      base.size,
      margins: margins,
      header: running ? base.header : null,
      footer: running ? base.footer : null,
      runningOver: base.runningOver,
      background: color == null && image == null
          ? base.background
          : (canvas, info) {
              final (width, height) = (
                info.template.size.width,
                info.template.size.height,
              );
              if (color != null) {
                final bleed = info.template.bleed ?? 0;
                canvas
                  ..save()
                  ..setFillColor(color)
                  ..rect(
                    Rect(-bleed, -bleed, width + 2 * bleed, height + 2 * bleed),
                  )
                  ..fill()
                  ..restore();
              }
              if (image != null) {
                _drawPageImage(canvas, image, size: (width, height));
              }
            },
      foreground: base.foreground,
      bleed: base.bleed,
    );
  }

  void _section(Section section) {
    final sectname = section.sectname;
    if (_isAbstract(section)) {
      _abstract(section);
      return;
    }
    // An empty index is left out.
    final indexSection = sectname == 'index';
    if (indexSection && _index.isEmpty) return;
    var title = _headingText(section);
    final separator =
        section.attr('separator') ?? _document.attr('title-separator') ?? '';
    if (separator.isNotEmpty && title.contains('$separator ')) {
      final at = title.lastIndexOf('$separator ');
      title =
          '${title.substring(0, at)}\n<em class="subtitle">'
          '${title.substring(at + separator.length + 1)}</em>';
    }
    final hlevel = (section.level ?? 0) + 1;
    final align =
        _keys('heading_h$hlevel').string('text_align') ??
        _s('heading_text_align') ??
        _baseTextAlign;
    final anchor = section.id ?? _madeUpAnchor(section);
    // `heading_h<n>_drop_lines` (modern engine): the heading set as a drop
    // beside the first lines of the section's first paragraph (a Bible's
    // chapter number), its text from `heading_h<n>_drop_content` (the
    // section's numeral by default; its attributes as `attr-<name>`).
    _pendingDrop = null;
    final dropLines = (_keys('heading_h$hlevel').number('drop_lines') ?? 0)
        .toInt();
    String? dropText;
    if (dropLines >= 2 && !asciidoctorCompat(_document, CompatFormat.pdf)) {
      dropText = _render(
        _keys('heading_h$hlevel').string('drop_content') ?? '{{numeral}}',
        {
          'title': section.title,
          'numeral': section.numeral,
          for (final MapEntry(:key, :value) in section.attributes.entries)
            'attr-$key': value,
        },
      ).trim();
      if (dropText.isEmpty) dropText = null;
    }
    // `heading_h<n>_display: margin` (modern engine): the heading hung in
    // the margin left of the first line of the section's first paragraph
    // (a reader's edition's chapter number), its text from
    // `heading_h<n>_margin_content` (the numeral by default), styled by
    // `heading_h<n>_margin_font_*`.
    _pendingMargin = null;
    String? marginText;
    if (dropText == null &&
        _keys('heading_h$hlevel').string('display') == 'margin' &&
        !asciidoctorCompat(_document, CompatFormat.pdf)) {
      marginText = _render(
        _keys('heading_h$hlevel').string('margin_content') ?? '{{numeral}}',
        {
          'title': section.title,
          'numeral': section.numeral,
          for (final MapEntry(:key, :value) in section.attributes.entries)
            'attr-$key': value,
        },
      ).trim();
      if (marginText.isEmpty) marginText = null;
    }
    final hidden =
        section.hasOption('notitle') || dropText != null || marginText != null;
    final part = sectname == 'part';
    final chapterlike =
        !part &&
        (sectname == 'chapter' ||
            (_document.doctype == 'book' && section.level == 1));
    var startedNew = false;
    if (part) {
      if (_s('heading_part_break_before') == 'always') startedNew = true;
    } else if (chapterlike) {
      final parent = section.parent;
      final firstOfPart =
          parent is Section &&
          parent.sectname == 'part' &&
          parent.blocks.whereType<Section>().firstOrNull == section;
      final partAfter = _s('heading_part_break_after');
      if ((_s('heading_chapter_break_before') == 'always' &&
              !(partAfter == 'avoid' && firstOfPart)) ||
          (partAfter == 'always' && firstOfPart)) {
        startedNew = true;
      }
    }
    if (startedNew) {
      _out.add(
        BreakBox.page(
          side: _ppbook && !section.hasOption('nonfacing')
              ? PageSide.recto
              : null,
        ),
      );
    }
    // A section with a role the theme styles (`section_role_<role>_*`,
    // modern engine): its heading and content in a box, as a sidebar.
    final boxed = _boxedRole(section);
    void content() {
      // `heading_h<n>_repeat` (modern engine): the heading set again at the
      // top of each page the section goes on to.
      final start = _out.length;
      var head = 0;
      final repeat =
          !hidden &&
          !asciidoctorCompat(_document, CompatFormat.pdf) &&
          _keys('heading_h$hlevel').value('repeat') == const ThemeBool(true);
      // (A cut set before the heading, `role_<role>_before_heading`.)
      if (!hidden) {
        if (_blockBeforeHeading(section) case final block?) {
          _convertFloating(block);
          _beforeHeading.add(block);
        }
      }
      if (hidden) {
        // No heading, but the section still names its pages' running
        // content.
        _out.add(
          CustomBox(
            const _Nothing(),
            style: BoxStyle(
              anchor: anchor,
              marks: _sectionMarks(section, part: part),
            ),
          ),
        );
      } else {
        // The modern engine: a section that starts its parent's, its
        // heading right after the parent's, the spaces between them
        // collapse.
        final parent = section.parent;
        final collapse =
            _collapseMargins &&
                !startedNew &&
                parent is Section &&
                parent.blocks.firstOrNull == section &&
                !parent.hasOption('notitle') &&
                _boxedRole(parent) == null
            ? (_keys('heading_h${(parent.level ?? 0) + 1}')
                          .number('margin_bottom') ??
                      _n('heading_margin_bottom') ??
                      0)
                  .toDouble()
            : 0.0;
        _heading(
          title,
          level: hlevel,
          align: align,
          anchor: anchor,
          arrange: !startedNew,
          hasContent: section.blocks.isNotEmpty,
          marks: _sectionMarks(section, part: part),
          outdent: true,
          collapse: collapse,
          ownMarginTop: _ownMarginTop(section),
        );
        head = _out.length - start;
      }
      if (dropText case final text?) {
        _pendingDrop = (
          text: text,
          category: 'heading_h${hlevel}_drop',
          lines: dropLines,
        );
      }
      // (`heading_h<n>_initial_lines`: an initial from the first letter
      // of the section's first paragraph.)
      _pendingInitial = null;
      if (!asciidoctorCompat(_document, CompatFormat.pdf) && dropText == null) {
        final lines = (_keys('heading_h$hlevel').number('initial_lines') ?? 0)
            .toInt();
        if (lines >= 2) _pendingInitial = ('heading_h${hlevel}_initial', lines);
      }
      if (marginText case final text?) {
        _pendingMargin = (
          text: text,
          font: _themeFont('heading_h${hlevel}_margin', _font),
          category: 'heading_h${hlevel}_margin',
        );
      }
      _sections.add((section, anchor));
      if (indexSection) {
        final slot = _indexSlot = <LayoutBox>[];
        _out.add(
          BlockBox(slot, style: BoxStyle(margin: _outdented(EdgeInsets.zero))),
        );
      } else if (chapterlike && _bookColumns >= 2) {
        // The chapter's content in the book's columns, balanced where it
        // ends (what follows starts under its shorter column).
        final gap = (_n('page_column_gap') ?? _rootFontSize).toDouble();
        final body = _inColumnSet(
          _bookColumns,
          gap,
          () => _collect(() => _traverse(section)),
        );
        _out.add(
          ColumnsBox(
            body,
            count: _bookColumns,
            gap: gap,
            balance: true,
            rule: _columnRule('page_column'),
          ),
        );
      } else if (_columnSetOf(section) case final count?) {
        _out.add(_columns(section, count, () => _traverse(section)));
      } else {
        _traverse(section);
      }
      if (repeat && head > 0) {
        final boxes = _out.sublist(start);
        _out
          ..removeRange(start, _out.length)
          ..add(BlockBox(boxes, repeatedHead: head));
      }
    }

    if (boxed == null) {
      content();
    } else {
      final category = 'section_role_$boxed';
      final saved = _headingRole;
      final savedTheme = _theme;
      _headingRole = category;
      // Inside the section, its role's keys in place of the theme's
      // (section_role_<role>_prose_margin_bottom for prose_margin_bottom).
      _theme = _theme.overlaid('${category}_', '');
      final List<LayoutBox> children;
      try {
        children = _collect(() => _withFont(category, content));
      } finally {
        _headingRole = saved;
        _theme = savedTheme;
      }
      _out.add(
        BlockBox(
          children,
          style: BoxStyle(
            padding: _keys(category).edges('padding'),
            cloneEdges: _cloneEdges(category),
            splitToRegionEnd: _splitToRegionEnd,
            margin: _outdented(
              EdgeInsets(
                top: (_keys(category).number('margin_top') ?? 0).toDouble(),
                bottom: _marginBelow(section),
              ),
            ),
            decoration: _blockDecoration(category),
            // In the middle or at the bottom of its page, when it starts
            // the page and fits on it (a dedication).
            verticalAlign: switch (_choice(
              '${category}_vertical_align',
              PdfConverter._alignsV,
            )) {
              'middle' || 'center' => VerticalAlign.middle,
              'bottom' => VerticalAlign.bottom,
              _ => null,
            },
          ),
        ),
      );
    }
    if (chapterlike) _footnotes(section);
  }

  /// The role of [section] the theme styles as a box (it has keys
  /// `section_role_<role>_...`; a hyphen in the role is an underscore
  /// there, as in other theme keys), in the modern engine.
  String? _boxedRole(Section section) {
    for (final role in section.roles) {
      final name = role.replaceAll('-', '_');
      final prefix = 'section_role_${name}_';
      if (_theme.keys.any((key) => key.startsWith(prefix))) return name;
    }
    return null;
  }

  /// The text of [section]'s heading: its numbered title, or in the
  /// modern engine the theme's `heading_h<n>_content` template (ADR-0010)
  /// with `title`, `numbered-title`, `number` (`1.2.`, a part's `I`),
  /// `numeral` (`1`, `I`) and `signifier` (`Chapter`, `Part`); a label
  /// on a line of its own, in gray: see doc/pdf.md.
  String _headingText(Section section) {
    final numbered = _numberedTitle(section);
    final level = (section.level ?? 0) + 1;
    final template = _keys('heading_h$level').string('content');
    if (template == null) return numbered;
    final isNumbered = _isNumbered(section);
    final part = section.sectname == 'part';
    final signifier = !isNumbered || _document.doctype != 'book'
        ? null
        : part
        ? _document.attributes['part-signifier'] ?? _english('Part')
        : section.level == 1
        ? _document.attributes['chapter-signifier'] ?? _english('Chapter')
        : null;
    return _render(template, {
      'title': section.title ?? '',
      'numbered-title': numbered,
      'number': isNumbered
          ? (part ? section.numeral : section.sectnum())
          : null,
      'numeral': isNumbered ? section.numeral : null,
      'signifier': signifier == null || signifier.isEmpty
          ? null
          : PdfConverter._escapeMarkup(signifier),
    });
  }

  /// Whether [section] shows a number (numbered, no caption of its own,
  /// within `sectnumlevels`).
  bool _isNumbered(Section section) {
    final sectnumlevels =
        int.tryParse(_document.attr('sectnumlevels') ?? '') ?? 3;
    return section.numbered &&
        section.caption == null &&
        (section.level ?? 0) <= sectnumlevels &&
        section.numeral != null;
  }

  /// [source], a Mustache template (ADR-0010), rendered with [values]
  /// (an empty value counts as none, for optional parts).
  String _render(String source, Map<String, String?> values) =>
      renderTemplate(source, values);

  /// The running marks a section's heading sets (for the running
  /// content): a part or chapter of a book, else a section, by the
  /// levels it counts for.
  Map<String, String> _sectionMarks(Section section, {required bool part}) {
    final index = '${_sections.length}';
    final level = section.level ?? 1;
    if (_document.doctype == 'book' && (part || level == 1)) {
      if (part) {
        _inPart = true;
        return {'part': index};
      }
      return {
        'chapter': index,
        if (section.sectname == 'appendix' && _inPart) 'part': '',
      };
    }
    return {for (var k = level; k <= 6; k++) 'section-$k': index};
  }

  /// Converts the discrete heading [node] (the gem's
  /// `convert_floating_title`): a heading kept with what follows it.
  void convertFloatingTitle(Block node) {
    final hlevel = (node.level ?? 0) + 1;
    final align =
        PdfConverter._alignOf(node.roles) ??
        _keys('heading_h$hlevel').string('text_align') ??
        _s('heading_text_align') ??
        _baseTextAlign;
    final last = node.parent?.blocks.lastOrNull == node;
    _heading(
      node.title ?? '',
      level: hlevel,
      align: align,
      anchor: node.id,
      arrange: !last,
      hasContent: !last,
      outdent: node.parent is Section,
    );
  }

  /// The section title as the gem numbers it (`numbered_title formal:
  /// true`).
  String _numberedTitle(Section section, {bool formal = true}) {
    final title = section.title ?? '';
    final level = section.level ?? 0;
    final doc = _document;
    final sectnumlevels = int.tryParse(doc.attr('sectnumlevels') ?? '') ?? 3;
    if (section.numbered && section.caption == null && level <= sectnumlevels) {
      if (doc.doctype == 'book' && level <= 1) {
        final numbered = level == 0
            ? '${section.sectnum('.', ':')} $title'
            : '${section.sectnum()} $title';
        if (!formal) return numbered;
        final signifier = level == 0
            ? doc.attributes['part-signifier'] ?? _english('Part')
            : doc.attributes['chapter-signifier'] ?? _english('Chapter');
        return signifier.isEmpty ? numbered : '$signifier $numbered';
      }
      return '${section.sectnum()} $title';
    }
    if (level == 0) return title;
    return section.captionedTitle();
  }

  /// [word], the English signifier the gem gives a part or chapter
  /// without one, unless the labels are in the document's language and
  /// its locale file has no word for it (empty: none).
  String _english(String word) => localeLabelsApply(_document) ? '' : word;

  /// The tracking theme key [key] gives text [size] points, in ems: a
  /// length (points) or ems (modern engine); null when it gives none.
  double? _letterSpacing(String key, double size) =>
      switch (_theme.value(key)) {
        _ when asciidoctorCompat(_document, CompatFormat.pdf) => null,
        ThemeNumber(:final value) => value / size,
        ThemeString(:final value) when value.trim().endsWith('em') =>
          double.tryParse(value.trim().replaceFirst('em', '')),
        _ => null,
      };

  /// The keys of heading level [level]: the heading role's
  /// (`<role>_heading_*`, with [role]), the level's (`heading_h<n>_*`),
  /// then every heading's (`heading_*`).
  _Keys _headingKeys(int level, {bool role = true}) => _Keys(this, [
    if (role && _headingRole != null) '${_headingRole}_heading',
    'heading_h$level',
    'heading',
  ]);

  /// The font of heading level [level] (the gem's `theme_font :heading,
  /// level:`).
  _FontState _headingFont(int level) {
    final role = _headingRole;
    final keys = _headingKeys(level);
    // (Some keys aren't a role's: the level's, then every heading's.)
    final levelKeys = _headingKeys(level, role: false);
    final size = switch (keys.value('font_size')) {
      ThemeNumber(:final value) => value.toDouble(),
      ThemeString(:final value) => resolveFontSize(
        value,
        _rootFontSize,
        _rootFontSize,
      ),
      _ => _rootFontSize,
    };
    final font = _FontState(
      family:
          keys.string('font_family') ?? _s('base_font_family') ?? _font.family,
      style: PdfConverter._fontStyle(keys.string('font_style')) ?? 'normal',
      size: size,
      color: keys.color('font_color') ?? _font.color,
      lineHeight: (levelKeys.number('line_height') ?? _font.lineHeight)
          .toDouble(),
      kerning: switch (keys.string('font_kerning')) {
        'normal' => true,
        'none' => false,
        _ => _font.kerning,
      },
      transform: keys.string('text_transform'),
      letterSpacing: keys.letterSpacing('letter_spacing', size) ?? 0,
      // Lines from their cap heights: the level's leading
      // (heading_h<n>_leading).
      leadingKey: [
        if (role != null) '${role}_heading_h${level}_leading',
        'heading_h${level}_leading',
        'heading_leading',
      ].where((key) => _theme.value(key) != null).firstOrNull,
    );
    // (`heading_line_pitch`, `heading_h<n>_line_pitch`; modern engine: a
    // heading's lines that far apart, whatever the face's height.)
    if (levelKeys.length('line_pitch', size) case final pitch?
        when !asciidoctorCompat(_document, CompatFormat.pdf)) {
      return _pitched(font, pitch);
    }
    return font;
  }

  /// A heading of [level]: its text box, margins, and the space it needs
  /// below it to stay on its page (the gem's `arrange_heading` with a
  /// numeric `heading_min_height_after`).
  void _heading(
    String title, {
    required int level,
    required String align,
    String? anchor,
    bool arrange = false,
    bool hasContent = false,
    Map<String, String> marks = const {},
    _FontState? font,
    bool outdent = false,
    double collapse = 0,
    double? ownMarginTop,
  }) {
    font ??= _headingFont(level);
    var text = title;
    if (font.transform case final transform? when transform != 'none') {
      text = transformText(text, transform, language: _language);
    }
    final styles = <String>{
      if (font.style == 'bold' || font.style == 'bold_italic') 'bold',
      if (font.style == 'italic' || font.style == 'bold_italic') 'italic',
    };
    TextBox textBox(String markup, {String? align_}) => _textBox(
      markup,
      font!,
      align: align_ ?? align,
      inheritedStyles: styles,
      inherit: _decoration('heading', level),
      normalize: false,
    );
    // The title's number (its first `[.number]` span, ADR-0023): hung
    // left of the title's edge, or on a line of its own.
    final levelKeys = _headingKeys(level, role: false);
    final placement = levelKeys.string('number_placement');
    final number = placement == 'hang' || placement == 'line'
        ? _headingNumberRx.firstMatch(text)
        : null;
    final CustomContent box;
    if (number != null && placement == 'line') {
      box = textBox('${number[1]}<br>${text.substring(number.end)}');
    } else if (number != null) {
      final hang =
          levelKeys.length('number_hang', font.size) ?? 2.5 * font.size;
      box = _Hung(
        textBox(text.substring(number.end)),
        textBox(number[1]!, align_: 'left'),
        hang,
        gap: font.size / 2,
      );
    } else {
      box = textBox(text);
    }
    final keys = _headingKeys(level);
    // (Right after another heading, the larger of its space below and
    // this one's above: [collapse] is that space below.)
    final marginTop =
        ownMarginTop ??
        math.max<double>(
          0,
          (keys.number('margin_top') ?? 0).toDouble() - collapse,
        );
    final marginBottom = (keys.number('margin_bottom') ?? 0).toDouble();
    var content = box;
    // The modern engine's `heading_min_height_after: auto`: the heading
    // stays with what starts after it (as much of it as may start a page:
    // a paragraph's first lines): a heading is never the last thing on a
    // page.
    final sticky =
        arrange &&
        hasContent &&
        _theme.value('heading_min_height_after') == const ThemeString('auto');
    if (arrange) {
      final minAfter = _theme.value('heading_min_height_after');
      var below = switch (minAfter) {
        ThemeNumber(:final value) when hasContent => value.toDouble(),
        _ => 0.0,
      };
      if (below > 0) below += marginBottom;
      content = _NeedsRoom(box, below);
    }
    // (Its own `margin-top` at the top of a page too, where the theme
    // keeps a block's own margin there, `base_margin_break: keep`.)
    final pageTop =
        (ownMarginTop != null && _s('base_margin_break') == 'keep'
                ? ownMarginTop
                : _keys('heading_h$level').number('margin_page_top') ??
                      _n('heading_margin_page_top') ??
                      0)
            .toDouble();
    if (pageTop > 0) content = _PageTopGap(content, pageTop);
    final category = 'heading_h$level';
    // (The modern engine: the level's side margins, negative to reach out
    // past the content's edges, as a banner.)
    final modern = !asciidoctorCompat(_document, CompatFormat.pdf);
    final sides = EdgeInsets(
      top: marginTop,
      bottom: marginBottom,
      left: modern ? _keys(category).length('margin_left', _font.size) ?? 0 : 0,
      right: modern
          ? _keys(category).length('margin_right', _font.size) ?? 0
          : 0,
    );
    final margin = outdent ? _outdented(sides) : sides;
    // The padding and border of the level (the gem's `pad_box` and
    // `theme_fill_and_stroke_bounds`), and in the modern engine its
    // background.
    final padding = _keys(category).value('padding');
    final background = modern
        ? switch (_keys(category).color('background_color')) {
            TransparentColor() || null => null,
            final color => pdfColorOf(color),
          }
        : null;
    final border =
        (_keys(category).value('border_width') != null &&
                (_keys(category).color('border_color') ??
                        _c('base_border_color')) !=
                    null) ||
            background != null
        ? _headingBorder(category, background: background)
        : null;
    // Floating images wait for no heading: it follows them (unless
    // `heading_float_barrier` is false: headings pass floats waiting for
    // the next page).
    final barrier =
        _theme.value('heading_float_barrier') != const ThemeBool(false);
    // In the middle or at the bottom of its page, when it starts the page
    // (a part's title).
    final verticalAlign = switch (_choice(
      '${category}_vertical_align',
      PdfConverter._alignsV,
    )) {
      'middle' || 'center' => VerticalAlign.middle,
      'bottom' => VerticalAlign.bottom,
      _ => null,
    };
    // The modern engine: a rule under the heading, a box of its own (beside
    // a block floating to a side, the rule may go under it, the heading
    // beside it).
    final rule = modern ? _headingRule(category) : null;
    if (padding == null && border == null && verticalAlign == null) {
      // (In a right-to-left document, a heading asking for room after it
      // set by the engine too, kept with what follows it: the text box
      // sets text left to right only.)
      final roomKept = _rightToLeft && content is _NeedsRoom;
      final style = BoxStyle(
        margin: margin,
        anchor: anchor,
        marks: marks,
        floatBarrier: barrier,
        keepWithNext: sticky || rule != null || roomKept,
        unnumbered: _headingsUnnumbered,
        structure: _headingStruct(level),
      );
      // (Set by the engine's paragraphs where it can: a heading of text
      // alone, kept whole, asking for no room after it.)
      _out.add(switch (content) {
        _NeedsRoom(content: final TextBox text, room: 0) ||
        final TextBox text => _engineOr(text, style: style, whole: true),
        _NeedsRoom(content: final TextBox text) when roomKept => _engineOr(
          text,
          style: style,
          whole: true,
        ),
        _ => CustomBox(content, style: style),
      });
    } else {
      _out.add(
        BlockBox(
          [CustomBox(content)],
          style: BoxStyle(
            margin: margin,
            padding: _keys(category).edges('padding'),
            anchor: anchor,
            marks: marks,
            decoration: border,
            floatBarrier: barrier,
            verticalAlign: verticalAlign,
            keepWithNext: sticky || rule != null,
            unnumbered: _headingsUnnumbered,
            structure: _headingStruct(level),
          ),
        ),
      );
    }
    if (rule != null) _out.add(rule);
  }

  /// The rule under a heading of theme [category] (`heading_h3_rule_width`,
  /// `_color`, `_margin_top`, `_margin_bottom`; `_dash`, lengths of dashes
  /// and gaps in turn, and `_cap`, `round` or `square`, for a rule of
  /// segments), if any.
  LayoutBox? _headingRule(String category) {
    final width = (_keys(category).number('rule_width') ?? 0).toDouble();
    final color = pdfColorOf(
      _keys(category).color('rule_color') ?? _c('base_border_color'),
    );
    if (width <= 0 || color == null) return null;
    final dash = switch (_keys(category).value('rule_dash')) {
      ThemeList(:final values) => [
        for (final v in values) PdfConverter._toPoints(v),
      ],
      _ => const <double>[],
    };
    final cap = switch (_keys(category).string('rule_cap')) {
      'round' => LineCap.round,
      'square' => LineCap.projectingSquare,
      _ => LineCap.butt,
    };
    // (A round or square cap reaches half the width past each end.)
    final inset = cap == LineCap.butt ? 0.0 : width / 2;
    return BlockBox(
      const [],
      style: BoxStyle(
        padding: EdgeInsets(top: width),
        margin: _outdented(
          EdgeInsets(
            top: _keys(category).length('rule_margin_top', _font.size) ?? 0,
            bottom:
                _keys(category).length('rule_margin_bottom', _font.size) ?? 0,
          ),
        ),
        keepWithNext: true,
        decoration: (page, rect, {required first, required last}) {
          final y = rect.top - width / 2;
          final canvas = page.canvas
            ..save()
            ..setStrokeColor(color)
            ..setLineWidth(width)
            ..setLineCap(cap);
          if (dash.isNotEmpty) canvas.dash(dash);
          canvas
            ..moveTo(rect.left + inset, y)
            ..lineTo(rect.right - inset, y)
            ..stroke()
            ..restore();
        },
      ),
    );
  }

  /// The border of heading theme [category] (`heading_h2`...), around the
  /// heading and its padding, over its [background].
  BoxDecoration _headingBorder(String category, {Color? background}) {
    final widthValue = _keys(category).value('border_width');
    final width = switch (widthValue) {
      ThemeNumber(:final value) => value.toDouble(),
      _ => 0.0,
    };
    final widths = _sideWidths(widthValue);
    final color = pdfColorOf(
      _keys(category).color('border_color') ?? _c('base_border_color'),
    );
    final style = _keys(category).string('border_style');
    final radius = widths == null
        ? (_keys(category).number('border_radius') ?? 0).toDouble()
        : 0.0;
    return (page, rect, {required first, required last}) {
      if (background != null) {
        final canvas = page.canvas
          ..save()
          ..setFillColor(background);
        radius > 0 ? canvas.roundedRect(rect, radius) : canvas.rect(rect);
        canvas
          ..fill()
          ..restore();
      }
      if (color == null || (width <= 0 && widths == null)) return;
      PdfConverter._strokeBounds(
        page.canvas,
        rect,
        color,
        width: width,
        widths: widths,
        style: style,
        radius: radius,
      );
    };
  }

  /// A heading's element of the logical structure at [level]: the levels
  /// shifted, with the theme's `heading_tag_shift: true`, so that the
  /// document's first heading is H1 when no title before it is (a book
  /// without a title page, `:notitle:`), as PDF/UA-1 7.4.2 asks
  /// (BUG-ljj0fk).
  StructureElement? _headingStruct(int level) {
    final shift = _headingShift ??=
        _titleTagged || _theme['heading_tag_shift'] != const ThemeBool(true)
        ? 0
        : math.max(0, level - 1);
    return _struct('H${(level - shift).clamp(1, 6)}');
  }
}
