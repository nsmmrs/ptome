part of '../converter.dart';

// The preamble.

extension _Preamble on PdfConverter {
  /// Converts the preamble: its first paragraph is the lead (when the
  /// document has sections), and a block margin follows it.
  void convertPreamble(Block node) {
    final blocks = node.blocks;
    if (blocks.isNotEmpty &&
        blocks.first.context == BlockContext.paragraph &&
        _document.sections.isNotEmpty &&
        blocks.first.role == null) {
      blocks.first.setAttr('role', 'lead');
    }
    _traverse(node);
    final margin = _marginBelow(node);
    if (margin > 0) _out.add(SpacerBox(margin));
    convertToc(node, placement: 'preamble');
  }

  /// The font of theme [category] over [inherited] (the gem's
  /// `theme_font category`).
  _FontState _themeFont(String category, _FontState inherited) {
    final sizeValue = _keys(category).value('font_size');
    final size = switch (sizeValue) {
      ThemeNumber(:final value) => value.toDouble(),
      ThemeString(:final value) => resolveFontSize(
        value,
        inherited.size,
        _rootFontSize,
      ),
      _ => inherited.size,
    };
    final font = _FontState(
      family: _keys(category).string('font_family') ?? inherited.family,
      style:
          PdfConverter._fontStyle(_keys(category).string('font_style')) ??
          inherited.style,
      size: size,
      color: _keys(category).color('font_color') ?? inherited.color,
      lineHeight:
          (_keys(category).number('line_height') ?? inherited.lineHeight)
              .toDouble(),
      kerning: switch (_keys(category).string('font_kerning')) {
        'none' => false,
        'normal' => true,
        _ => inherited.kerning,
      },
      transform:
          _keys(category).string('text_transform') ?? inherited.transform,
      leadingKey: _keys(category).value('leading') != null
          ? '${category}_leading'
          : inherited.leadingKey,
      letterSpacing:
          _keys(category).letterSpacing('letter_spacing', size) ??
          inherited.letterSpacing,
    );
    // (`<category>_line_pitch`, modern engine: its lines that far apart,
    // whatever the face's height, as `base_line_pitch` sets the body's.)
    if (_keys(category).length('line_pitch', size) case final pitch?
        when !asciidoctorCompat(_document, CompatFormat.pdf)) {
      return _pitched(font, pitch);
    }
    return font;
  }

  /// [font] with the line height that sets its lines [pitch] apart (found
  /// from the pitches at one and two).
  _FontState _pitched(_FontState font, double pitch) {
    if (pitch <= 0) return font;
    final key = (font.family, font.style, font.size, pitch);
    final height = _pitchedHeights[key] ??= () {
      double at(double height) => _textBox(
        'Ag Ag',
        font.copyWith(lineHeight: height),
        align: 'left',
      ).linePitch(1);
      final (one, two) = (at(1), at(2));
      return two - one > 1e-6 ? 1 + (pitch - one) / (two - one) : null;
    }();
    return height == null ? font : font.copyWith(lineHeight: height);
  }
}
