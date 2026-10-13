part of '../converter.dart';

// Text.

extension _Text on PdfConverter {
  /// A text box of [markup] in [font] (the gem's `typeset_text` with the
  /// line metrics of the font's line height).
  TextBox _textBox(
    String markup,
    _FontState font, {
    required String align,
    double indent = 0,
    Set<String> inheritedStyles = const {},
    Fragment? inherit,
    bool normalize = true,
    bool normalizeLineHeight = false,
    double characterSpacing = 0,
    bool cell = false,
    bool inlineFormat = true,
    bool gaps = true,
    bool singleLine = false,
    bool shrinkToFit = false,
    bool mirrored = true,
    int orphans = 1,
    int widows = 1,
    double? wrapIndent,
    bool wrapMarker = false,
    bool hyphenate = false,
    Set<String> features = const {},
    double? skew,
    bool overhang = true,
    int dropLines = 0,
    double dropIndent = 0,
  }) {
    final taken = markup.contains('<side ')
        ? _takeSideNotes(markup, font)
        : markup;
    var text = hyphenate ? _hyphenated(taken, align) : taken;
    if (normalize) text = text.replaceAll(RegExp('[ \t\n]+'), ' ');
    // A label left out of the text (`role_<role>_display: none`,
    // `units_<level>_label_display: none`) takes the space after it with
    // it.
    if (text.contains(PdfConverter._hiddenMark)) {
      text = text.replaceAll(
        RegExp('${PdfConverter._hiddenMark}[ \u00a0]?'),
        '',
      );
    }
    // `footnotes_reference_space: collapse`: no space before a footnote's
    // reference (a note's number follows its word or punctuation without
    // a space, as The Chicago Manual of Style has it).
    if (_footnoteSpaceCollapses && text.contains('<sup class="wj"><a ')) {
      text = text.replaceAll(PdfConverter._spaceBeforeFootnoteRx, '');
    }
    // The modern engine: variation selectors take no room (they choose a
    // glyph's form, which the fonts here don't vary).
    text = text.replaceAll(RegExp('[\ufe00-\ufe0f]'), '');

    if (_cjkLineBreaks && !cell) text = PdfConverter._breakCjk(text);
    // Links broken at The Chicago Manual of Style's points (`www.` links
    // too), or after their delimiters alone (`url_breaks: delimiters`).
    final delimiters = _urlDelimiterBreaks;
    if (text.contains('://') || (!delimiters && text.contains('www.'))) {
      text = PdfConverter._breakUrls(
        text,
        markup: inlineFormat,
        delimiters: delimiters,
      );
    }
    // (Prose: preformatted text, set as it is, keeps its lines.)
    if (normalize && text.contains('/') && _slashBreaks) {
      text = PdfConverter._breakAfterSlashes(text, markup: inlineFormat);
    }
    final nodes = inlineFormat ? parseMarkup(text) : [MarkupText(text)];
    final List<Fragment> fragments;
    final inherited = inheritedStyles.isEmpty && inherit == null
        ? null
        : ((inherit?.copy() ?? Fragment(''))
            ..styles = {
              ...?inherit?.styles,
              for (final style in inheritedStyles)
                if (style == 'bold')
                  FragmentStyle.bold
                else
                  FragmentStyle.italic,
            });
    if (nodes == null) {
      logger.error(
        'failed to parse formatted text: ${text.replaceAll('­', '')}',
      );
      fragments = [inherited?.copy(text: text) ?? Fragment(text)];
    } else {
      fragments = _markup.apply(nodes, null, inherited);
    }
    final metrics = _lineMetrics(font);
    return TextBox(
      fragments,
      TextState(
        family: font.family,
        style: font.style,
        size: font.size,
        color: font.color,
        kerning: font.kerning,
        characterSpacing: characterSpacing + font.letterSpacing * font.size,
        features: {..._baseFeatures, ...features},
      ),
      TextLayout(
        align: align,
        mirrored: mirrored,
        leading: metrics.leading,
        initialGap: cell || !gaps ? 0 : metrics.paddingTop,
        paddingBottom: cell || !gaps ? 0 : metrics.paddingBottom,
        trailingLineGap: cell,
        singleLine: singleLine,
        shrinkToFit: shrinkToFit,
        indentFirstLine: indent,
        normalizeLineHeight: normalizeLineHeight,
        orphans: orphans,
        widows: widows,
        wrapIndent: wrapIndent,
        wrapMarker: wrapMarker,
        at: _at,
        skew: skew,
        overhang: overhang ? _overhangAmount() : 0,
        capLines: _capLeading(font) != null,
        dropLines: dropLines,
        dropIndent: dropIndent,
        justifyWidest:
            _choice('base_justify_width', const ['room', 'widest']) == 'widest',
        alignLast: _choice('base_text_align_last', const [
          'left',
          'center',
          'right',
          'justify',
        ]),
      ),
      _text,
    );
  }

  /// The value of theme key [key] when it is one of [values] (the keys
  /// with a set of values); another value is reported once and read as
  /// unset.
  String? _choice(String key, List<String> values) {
    final value = _s(key);
    if (value == null) return value;
    if (values.contains(value)) return value;
    if (_reportedChoices.add(key)) {
      logger.warn(
        'theme key $key: unknown value $value; expected one of '
        '${values.join(', ')}',
      );
    }
    return null;
  }

  /// The theme's `image_placement`.
  String? get _imagePlacement => _choice('image_placement', const [
    'here',
    'auto',
    'top',
    'bottom',
    'next',
  ]);

  /// How far punctuation hangs into the margin (`base_overhang`): `true`
  /// is 1 (the fractions of each character's width `_overhang` names),
  /// `false` 0, a number scales them.
  double _overhangAmount() => switch (_theme.value('base_overhang')) {
    ThemeBool(:final value) => value ? 1 : 0,
    ThemeNumber(:final value) => math.max(0, value.toDouble()),
    ThemeString(value: 'true') => 1,
    _ => 0,
  };

  /// Sets the hyphenation of [document]: as the gem does when the
  /// `hyphens` attribute (a language, or empty for the document's `lang`)
  /// or, when the attribute is unspecified, the theme's `base_hyphens`
  /// asks for it; in the modern engine, of justified text in the
  /// document's language otherwise, unless `hyphens` is unset.
  void _resolveHyphenation(Document document) {
    _hyphenator = null;
    _hyphenateAll = false;
    final unspecified = document.attributeUnspecified('hyphens');
    var asked = document.attr('hyphens');
    if (asked == null && unspecified) {
      // `base_hyphens: false`: no hyphenation, not even of justified text.
      if (_theme.value('base_hyphens') case ThemeBool(value: false)) return;
      asked = switch (_theme.value('base_hyphens')) {
        ThemeString(:final value) => value,
        ThemeBool(:final value) when value => '',
        _ => null,
      };
    }
    final explicit = asked != null;
    if (!explicit && (!unspecified)) return;
    var language = asked ?? '';
    if (language.isEmpty) language = document.attr('lang') ?? '';
    if (language.isEmpty || language == 'en') language = 'en_us';
    final hyphenator = hyphenatorFor(language);
    if (hyphenator == null) {
      if (explicit) {
        logger.warn('no hyphenation patterns for $language; not hyphenating');
      }
      return;
    }
    _hyphenator = hyphenator;
    _hyphenateAll = explicit;
  }

  /// [markup] with soft hyphens where its words may break, when text set
  /// with [align] is hyphenated (the gem's `hyphenate_text`; the modern
  /// engine leaves code spans whole).
  String _hyphenated(String markup, String align) {
    final hyphenator = _hyphenator;
    if (hyphenator == null || (!_hyphenateAll && align != 'justify')) {
      return markup;
    }
    return hyphenateMarkup(
      markup,
      hyphenator,
      skipCode: true,
      lettersOnly: true,
      // A word goes on across formatting (its letters in two styles are
      // one word); the gem hyphenates each text between tags alone.
      acrossTags: !asciidoctorCompat(_document, CompatFormat.pdf),
    );
  }

  /// The underline or strike-through of theme [category] (of heading
  /// [level], when given, before the category's), as a fragment to inherit
  /// from; null when it has none (the gem's `apply_text_decoration`).
  Fragment? _decoration(String category, [int? level]) {
    String key(String name) =>
        level != null && _keys(category).value('h${level}_$name') != null
        ? '${category}_h${level}_$name'
        : '${category}_$name';
    final style = switch (_s(key('text_decoration'))) {
      'underline' => FragmentStyle.underline,
      'line-through' => FragmentStyle.strikethrough,
      _ => null,
    };
    if (style == null) return null;
    return Fragment('')
      ..styles = {style}
      ..textDecorationColor = _c(key('text_decoration_color'))
      ..textDecorationWidth = _n(key('text_decoration_width'));
  }

  /// The leading of [font]'s text when its lines are set from their cap
  /// heights (`<category>_leading`, else `base_leading`), in the modern
  /// engine.
  double? _capLeading(_FontState font) =>
      _length(font.leadingKey ?? 'base_leading', font.size);

  /// The gem's `calc_line_metrics`: the leading of the line height, half
  /// of it above the text (plus the font's line gap) and half below.
  ({double leading, double paddingTop, double paddingBottom}) _lineMetrics(
    _FontState font,
  ) {
    final prawnFont = _fonts.font(font.family, font.style);
    // The modern engine with `base_leading`: lines set from their cap
    // heights (as CSS's `text-box-edge: cap alphabetic`). Each line's box
    // runs from its cap height to its baseline, the leading between boxes;
    // a text's first line has its cap height at the top, its last line
    // ends at its baseline (the space between blocks from baseline to cap
    // height).
    if (_capLeading(font) case final leading?) {
      // The text box sets the lines on their cap heights (capLines).
      return (leading: leading, paddingTop: 0.0, paddingBottom: 0.0);
    }

    final leading = font.lineHeight * font.size - font.size;
    return (
      leading: leading,
      paddingTop: leading / 2 + prawnFont.lineGapAt(font.size),
      paddingBottom: leading / 2,
    );
  }
}
