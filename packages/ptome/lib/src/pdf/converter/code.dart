part of '../converter.dart';

// Code.

extension _Code on PdfConverter {
  /// Converts the listing or literal block [node] (without syntax
  /// highlighting).
  void convertCode(Block node) {
    // The modern engine styles a block with a role by the theme's
    // code_role_<role>_* keys, over its code_* keys.
    if (node.roles.isNotEmpty) {
      final saved = _theme;
      for (final role in node.roles) {
        _theme = _theme.overlaid(
          'code_role_${role.replaceAll('-', '_')}_',
          'code_',
        );
      }
      if (!identical(_theme, saved)) {
        try {
          _convertCode(node);
        } finally {
          _theme = saved;
        }
        return;
      }
    }
    _convertCode(node);
  }

  void _convertCode(Block node) {
    final font = _themeFont('code', _font);
    var source = '';
    _withFont(
      'code',
      () => source = PdfConverter._guardIndentation(node.content() ?? ''),
    );
    // Highlighted by plain_highlighting (`source-highlighter=highlight.js`):
    // the modern engine colors the tokens as the `highlightjs-theme` does
    // (github by default); `code_highlight: none` leaves them as text.
    if (source.contains('<span class="hljs-') &&
        _choice('code_highlight', const ['colors', 'none']) == 'none') {
      source = PdfConverter._withoutHighlightSpans(source);
    }
    if (source.contains('<span class="hljs-')) {
      // A line's indentation inside a token (a string that runs over
      // lines) kept as well: its first space a no-break one.
      source = source.replaceAllMapped(
        RegExp(r'(^|\n)((?:<[^>]*>)+) '),
        (m) => '${m[1]}${m[2]}\u00a0',
      );
      final theme = _document.attr('highlightjs-theme') ?? 'github';
      if (_highlightStyles.putIfAbsent(theme, () => HighlightStyle.named(theme))
          case final style?) {
        source = style.markup(source);
      }
    }
    final captionBelow = _s('code_caption_end') == 'bottom';
    if (!captionBelow && node.hasTitle) _caption(node, category: 'code');
    // The modern engine splits a listing between lines, leaving at least
    // code_orphans and code_widows lines on either side (2 each), and
    // marks a line that wraps, going on with a hanging indent
    // (code_wrap_indent, 1em; code_wrap_marker: none leaves the arrow
    // out).
    final wrapIndent = _length('code_wrap_indent', font.size) ?? font.size;
    final wrapMarker =
        _choice('code_wrap_marker', const ['arrow', 'none']) != 'none';
    // Without a hanging indent or a marker, a long line wraps at the
    // line breaking algorithm's breaks (UAX #14; after a slash too), as
    // many words on a line as fit.
    // (Segments line breaking wraps code as Prawn's line wrap does: at
    // spaces and hyphens, else between characters.)
    final segments =
        _choice('base_line_breaking', const [
          'auto',
          'optimal',
          'greedy',
          'segments',
        ]) ==
        'segments';
    final plainWrap = wrapIndent == 0 && !wrapMarker && !segments;
    // (Autofit text is sized so its lines don't wrap, measured as they
    // are.)
    final autofit =
        node.hasOption('autofit') || _document.hasAttr('autofit-option');
    if (plainWrap && !autofit) source = PdfConverter._breakAfterSlashes(source);
    final box = _textBox(
      source,
      font.copyWith(color: _c('code_font_color') ?? font.color),
      align: 'left',
      normalize: false,
      orphans: (_n('code_orphans') ?? 2).toInt(),
      widows: (_n('code_widows') ?? 2).toInt(),
      wrapIndent: plainWrap ? null : wrapIndent,
      wrapMarker: wrapMarker,
    );
    CustomContent content = box;
    if (autofit) {
      final minimum =
          _theme.value('code_font_size_min') ??
          _theme.value('base_font_size_min');
      content = AutofitTextBox(
        box,
        minimum: switch (minimum) {
          ThemeNumber(:final value) => value.toDouble(),
          ThemeString(:final value) => resolveFontSize(
            value,
            font.size,
            _rootFontSize,
          ),
          _ => null,
        },
      );
    }
    _out.add(
      BlockBox(
        [CustomBox(content)],
        style: BoxStyle(
          padding: _padding('code_padding'),
          margin: EdgeInsets(bottom: captionBelow ? 0 : _marginBelow(node)),
          keepTogether: node.hasOption('unbreakable'),
          splitToRegionEnd: _splitToRegionEnd,
          anchor: node.id,
          decoration: _blockDecoration('code'),
        ),
      ),
    );
    if (captionBelow && node.hasTitle) {
      _caption(node, category: 'code');
      final margin = _marginBelow(node);
      if (margin > 0) _out.add(SpacerBox(margin));
    }
  }

  /// Converts the passthrough block [node]: its content as code text
  /// (the gem's `convert_pass`).
  void convertPass(Block node) {
    // (Left aligned, as raw text is set.)
    final font = _themeFont(
      'code',
      _font,
    ).copyWith(color: _c('base_font_color'));
    _out.add(
      CustomBox(
        _textBox(
          PdfConverter._guardIndentation(node.content() ?? ''),
          font,
          align: 'left',
          normalize: false,
          inlineFormat: false,
        ),
        style: BoxStyle(margin: EdgeInsets(bottom: _marginBelow(node))),
      ),
    );
  }

  /// Converts the STEM block [node]: AsciiMath typeset in display style
  /// (ADR-0014), centered (`stem_text_align`); LaTeX, for now, as its
  /// source in a code block (the gem's `convert_stem` without a math
  /// renderer).
  void convertStem(Block node) {
    final style = node.style ?? node.attr('style');
    if ((style == 'asciimath' || style == 'latexmath') && _typesetMath) {
      final source = PdfConverter._unescapeXml(node.content() ?? '');
      final latex = style == 'latexmath';
      if (_mathOf(source, latex: latex, display: true) case final formula?) {
        if (node.hasTitle) _caption(node, category: 'code');
        final box = _math!.layout(
          formula,
          size: _themeFont('stem', _font).size,
          display: true,
        );
        _out.add(
          CustomBox(
            _DisplayMath(
              box,
              source,
              align: _s('stem_text_align') ?? 'center',
              color: PdfConverter._color(_themeFont('stem', _font).color),
            ),
            style: BoxStyle(
              margin: EdgeInsets(bottom: _marginBelow(node)),
              keepTogether: true,
              anchor: node.id,
            ),
          ),
        );
        return;
      }
    }
    _warnMathAsSource();
    if (node.hasTitle) _caption(node, category: 'code');
    final font = _themeFont('code', _font);
    _out.add(
      BlockBox(
        [
          CustomBox(
            // The source as written (`<`, not `&lt;`).
            _textBox(
              PdfConverter._guardIndentation(
                PdfConverter._unescapeXml(node.content() ?? ''),
              ),
              font,
              align: 'left',
              normalize: false,
              inlineFormat: false,
            ),
          ),
        ],
        style: BoxStyle(
          padding: _padding('code_padding'),
          margin: EdgeInsets(bottom: _marginBelow(node)),
          keepTogether: node.hasOption('unbreakable'),
          splitToRegionEnd: _splitToRegionEnd,
          anchor: node.id,
          decoration: _blockDecoration('code'),
        ),
      ),
    );
  }

  /// Whether math is typeset (`stem_math: typeset`), or shown as its source
  /// (`source`, as asciidoctor-pdf shows it without a math renderer).
  bool get _typesetMath =>
      _choice('stem_math', const ['typeset', 'source']) != 'source';

  /// The formula of the AsciiMath (or with [latex], LaTeX) [source] (its
  /// MathML), or null when it can't be set (no math font, or MathML the
  /// layout can't read). A LaTeX command it doesn't know is reported.
  ///
  /// The same formula is converted once per document; its warning, if
  /// any, comes again for each occurrence.
  MathNode? _mathOf(String source, {bool latex = false, bool display = false}) {
    if (_math == null) return null;
    final (math, warning) = _formulas[(source, latex)] ??=
        PdfConverter._convertMath(source, latex: latex);
    if (warning != null) logger.warn(warning);
    return math;
  }

  /// The image markup of the inline AsciiMath (or with [latex], LaTeX)
  /// [text] (escaped as the text is), its formula registered as an inline
  /// graphic, or null.
  String? _inlineMath(String text, {bool latex = false}) {
    final source = PdfConverter._unescapeXml(text);
    final formula = _mathOf(source, latex: latex);
    if (formula == null) return null;
    final src = 'math:${_mathCount++}';
    _inlineGraphics[src] = InlineMath(formula, _math!, source: source);
    final alt = PdfConverter._escapeXml(source);
    return '<img src="$src" format="math" alt="$alt">';
  }

  /// Says once per document, in the modern engine, that math is set as
  /// its source (ADR-0014: the PDF lays out no math yet).
  void _warnMathAsSource() {
    if (_warnedMath) return;
    _warnedMath = true;
    logger.warn('math is shown as its source in the PDF (not typeset yet)');
  }

  /// Converts the audio or video block [node]: a link to the media (or
  /// the video's poster image), as the gem's `convert_audio` and
  /// `convert_video` do.
  void convertMedia(Block node) {
    final doc = _document;
    final target = node.attr('target') ?? '';
    final audio = node.context == BlockContext.audio;
    String path;
    String type;
    var poster = audio ? null : node.attr('poster');
    switch (poster) {
      case 'youtube':
        path = 'https://www.youtube.com/watch?v=$target';
        poster = doc.hasAttr('allow-uri-read')
            ? 'https://img.youtube.com/vi/$target/maxresdefault.jpg'
            : null;
        type = 'YouTube video';
      case 'vimeo':
        path = 'https://vimeo.com/$target';
        poster = null;
        type = 'Vimeo video';
      default:
        path = node.mediaUri(target);
        type = audio ? 'audio' : 'video';
    }
    if (poster != null && poster.isNotEmpty) {
      final saved = {...node.attributes};
      node.attributes
        ..['target'] = poster
        ..['link'] = path;
      try {
        convertImage(node);
      } finally {
        node.attributes
          ..clear()
          ..addAll(saved);
      }
      return;
    }
    final play = doc.attr('icons') == 'font' && _iconsInstalled('fas')
        ? '<font name="fas">${iconGlyph('fas', 'play') ?? ''}</font>'
        : '►';
    _out.add(
      CustomBox(
        _textBox(
          '$play <a href="$path">$path</a> <em>($type)</em>',
          _font,
          align: _baseTextAlign,
          normalize: false,
        ),
        style: BoxStyle(anchor: node.id),
      ),
    );
    if (node.hasTitle) _caption(node, labeled: false, bottom: true);
    final margin = _marginBelow(node);
    if (margin > 0) _out.add(SpacerBox(margin));
  }
}
