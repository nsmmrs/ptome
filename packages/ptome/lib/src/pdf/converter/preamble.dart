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
    return _FontState(
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
  }
}
