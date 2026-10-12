part of '../converter.dart';

// Captions.

extension _Captions on PdfConverter {
  /// The caption of [node] (its title; with [labeled], its captioned
  /// title) above it (the gem's `ink_caption`, at the top).
  void _caption(
    AbstractBlock node, {
    String? category,
    bool labeled = true,
    bool bottom = false,
    String? blockAlign,
  }) {
    _out.add(
      _captionBox(
        node,
        category: category,
        labeled: labeled,
        bottom: bottom,
        blockAlign: blockAlign,
      ),
    );
  }

  /// The caption of [node] (see [_caption]), or nothing for a node without
  /// a title.
  CustomBox _captionBox(
    AbstractBlock node, {
    String? category,
    bool labeled = true,
    bool bottom = false,
    String? blockAlign,
    String? title,
  }) {
    title ??= labeled ? node.captionedTitle() : node.title;
    if (title == null || title.isEmpty) {
      return const CustomBox(_Nothing());
    }
    final captionKey = category == null ? 'caption' : '${category}_caption';
    final outside =
        (_n('${captionKey}_margin_outside') ??
                _n('caption_margin_outside') ??
                0)
            .toDouble();
    final inside =
        (_n('${captionKey}_margin_inside') ?? _n('caption_margin_inside') ?? 0)
            .toDouble();
    var align =
        _s('${captionKey}_align') ?? _s('caption_align') ?? _baseTextAlign;
    if (align == 'inherit') align = blockAlign ?? _baseTextAlign;
    var textAlign =
        _s('${captionKey}_text_align') ?? _s('caption_text_align') ?? align;
    if (textAlign == 'inherit') textAlign = align;
    var font = _themeFont('caption', _font);
    if (category != null) font = _themeFont(captionKey, font);
    var text = title;
    if (font.transform case final transform? when transform != 'none') {
      text = transformText(text, transform);
    }
    // The modern engine's `<category>_caption_indent`: set in from the
    // left (a code block's caption over its padded code).
    final indent =
        _length('${captionKey}_indent', font.size) ??
        _length('caption_indent', font.size) ??
        0.0;
    // A background behind the text, as wide as the block's room.
    final background = pdfColorOf(
      _c('${captionKey}_background_color') ?? _c('caption_background_color'),
    );
    return CustomBox(
      _textBox(
        text,
        font,
        align: textAlign,
        inherit: _decoration('caption'),
        normalize: false,
        normalizeLineHeight: true,
        hyphenate: true,
      ),
      style: BoxStyle(
        margin: bottom
            ? EdgeInsets(top: inside, bottom: outside, left: indent)
            : EdgeInsets(top: outside, bottom: inside, left: indent),
        // A caption above its block stays with it in the modern engine.
        keepWithNext: !bottom,
        decoration: background == null
            ? null
            : (page, rect, {required first, required last}) => page.canvas
                ..save()
                ..setFillColor(background)
                ..rect(rect)
                ..fill()
                ..restore(),
      ),
    );
  }
}
