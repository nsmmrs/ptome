part of '../converter.dart';

// Images.

extension _Images on PdfConverter {
  /// The bytes of the image [target] of [node], or null (with a warning)
  /// when they can't be read.
  List<int>? _imageBytes(AbstractNode node, String target) {
    _lastImagePath = null;
    final doc = _document;
    final imagesdir = _imagesdir;
    if (_imagePath(node, target) case final path?) return _readImage(path);
    final uri = Helpers.isUriish(target)
        ? target
        : doc.pathResolver.webPath(target, imagesdir);
    if (!doc.hasAttr('allow-uri-read')) {
      logger.warn(
        'cannot embed remote image: $uri '
        '(allow-uri-read attribute not enabled)',
      );
      return null;
    }
    try {
      return doc.fetchUri(uri).body;
    } on Exception catch (error) {
      logger.warn('could not retrieve remote image: $uri; $error');
      return null;
    }
  }

  /// The document's `imagesdir`, unless it's the document's directory.
  String? get _imagesdir => switch (_document.attr('imagesdir')) {
    null || '' || '.' || './' => null,
    final dir => dir,
  };

  /// The path of the image [target] of [node] (relative to the
  /// `imagesdir`), or null when it's a URL.
  String? _imagePath(AbstractNode node, String target) {
    final imagesdir = _imagesdir;
    final resolver = _document.pathResolver;
    final isUrl = Helpers.isUriish(target);
    if (!isUrl && resolver.isAbsolutePath(target)) {
      return resolver.expandPath(resolver.posixify(target));
    }
    if (!isUrl && imagesdir != null && resolver.isAbsolutePath(imagesdir)) {
      return resolver.expandPath('${resolver.posixify(imagesdir)}/$target');
    }
    if (isUrl || (imagesdir != null && Helpers.isUriish(imagesdir))) {
      return null;
    }
    return node.normalizeSystemPath(
      target,
      start: imagesdir,
      targetName: 'image',
    );
  }

  List<int>? _readImage(String path) {
    if (io.isFile(path) && io.isReadable(path)) {
      try {
        final bytes = io.readBytes(path);
        _lastImagePath = path;
        return bytes;
      } on Exception {
        // Reported below.
      }
    }
    logger.warn('image to embed not found or not readable: $path');
    return null;
  }

  /// [bytes] as an image of [format], or null (with why) when they aren't
  /// one.
  (Graphic?, String?) _graphicOf(
    List<int> bytes,
    String format, {
    String? path,
  }) {
    try {
      return (
        format == 'svg'
            ? SvgImage.parse(
                utf8.decode(bytes, allowMalformed: true),
                pixelSize: 1,
                fonts: _fonts.svgFont,
                defaultFontFamily: 'sans-serif',
                fallbackFontFamily:
                    _s('svg_fallback_font_family') ??
                    _s('svg_font_family') ??
                    _s('base_font_family'),
                images: path == null
                    ? null
                    : (href) => _svgResource(href, path),
                // (`svg_placement: page_origin`: placed as scaled about the
                // page's origin, to five decimals.)
                scalesAboutPageOrigin:
                    _choice('svg_placement', const ['exact', 'page_origin']) ==
                    'page_origin',
              )
            : _encodingElsewhere(Uint8List.fromList(bytes)),
        null,
      );
    } on FormatException catch (error) {
      return (null, error.message);
    } on ImageFormatException catch (error) {
      return (null, error.message);
    }
  }

  /// The image in [bytes], its samples encoded on another core when the
  /// conversion is awaited and writing it encodes them (a PNG with alpha,
  /// say): the worker gets the file's bytes and gives back the streams
  /// the save would make (or nothing, and the save makes them).
  PdfImage _encodingElsewhere(Uint8List bytes) {
    final image = PdfImage.parse(bytes);
    final parallel = _parallel;
    if (parallel == null || image is! PngImage || !image.reencodes) {
      return image;
    }
    _awaiting.add(
      parallel
          .submit(_PngEncoding(bytes, nativeZlib: io.hasNativeZlib))
          .then<void>(
            (payload) => image.payload = payload,
            onError: (Object _) {},
          ),
    );
    return image;
  }

  /// The content streams of [pages] compressed on other cores, when the
  /// conversion is awaited.
  void _compressingElsewhere(List<PdfPage> pages) {
    final parallel = _parallel;
    if (parallel == null) return;
    for (final page in pages) {
      _awaiting.add(
        parallel
            .submit(_StreamEncoding(page.content, nativeZlib: io.hasNativeZlib))
            .then<void>(
              (payload) => page.contentPayload = payload,
              onError: (Object _) {},
            ),
      );
    }
  }

  /// The file an SVG image at [svgPath] refers to by [href]: relative to
  /// the image, inside the document's directory unless the safe mode
  /// allows any (prawn-svg's file requests); a URI with allow-uri-read.
  Uint8List? _svgResource(String href, String svgPath) {
    final doc = _document;
    if (Helpers.isUriish(href) && !href.startsWith('file:')) {
      if (!doc.hasAttr('allow-uri-read')) return null;
      try {
        return Uint8List.fromList(doc.fetchUri(href).body);
      } on Exception {
        return null;
      }
    }
    final resolver = doc.pathResolver;
    var path = href.startsWith('file://') ? href.substring(7) : href;
    final slash = svgPath.lastIndexOf('/');
    final base = slash < 0 ? '.' : svgPath.substring(0, slash);
    path = resolver.isAbsolutePath(path)
        ? resolver.expandPath(path)
        : resolver.expandPath('$base/$path');
    if (doc.safe >= SafeMode.safe) {
      final root = resolver.expandPath(doc.baseDir);
      if (path != root && !path.startsWith('$root/')) return null;
    }
    if (!io.isFile(path) || !io.isReadable(path)) return null;
    try {
      return Uint8List.fromList(io.readBytes(path));
    } on Exception {
      return null;
    }
  }

  /// [path], relative to the theme's directory.
  String? _themeImagePath(String path) {
    final resolver = _document.pathResolver;
    if (resolver.isAbsolutePath(path)) return path;
    final dir = _theme.directory;
    if (dir == null) return null;
    return resolver.expandPath('${resolver.posixify(dir)}/$path');
  }

  /// Reads the image at [path] relative to the theme's directory (the
  /// gem's `resolve_image_path` with the themesdir).
  List<int>? _themeImageBytes(String path) {
    final resolved = _themeImagePath(path);
    if (resolved == null || !io.isFile(resolved) || !io.isReadable(resolved)) {
      return null;
    }
    try {
      final bytes = io.readBytes(resolved);
      _lastImagePath = resolved;
      return bytes;
    } on Exception {
      return null;
    }
  }

  /// Converts the block image [node].
  void convertImage(Block node) {
    final target = node.attr('target') ?? '';
    final data = PdfConverter._dataUri.firstMatch(target);
    final format = data != null
        ? switch (data[1]!) {
            'jpg' => 'jpeg',
            'svg+xml' => 'svg',
            final other => other,
          }
        : node.attr('format') ?? PdfConverter._imageFormat(target);
    const blockAligns = {'left', 'center', 'right'};
    final floatTo = node.attr('float');
    final String align;
    if (floatTo != null && blockAligns.contains(floatTo)) {
      align = floatTo;
    } else if (node.attr('align') case final value?) {
      align = blockAligns.contains(value) ? value : 'left';
    } else {
      align =
          node.roles.reversed.where(blockAligns.contains).firstOrNull ??
          _s('image_align') ??
          'left';
    }
    // A text file (ASCII art) in the modern engine: its text, as it is,
    // in the code font (or `image_text_*`), the block as wide as its
    // longest line and aligned as an image.
    if (format == 'txt' && data == null) {
      if (_imageBytes(node, target) case final bytes?) {
        _textImage(node, utf8.decode(bytes, allowMalformed: true), align);
        return;
      }
    }
    List<int>? bytes;
    if (format == 'gif') {
      logger.warn('GIF image format not supported; convert $target to PNG');
    } else if (format == 'pdf' && data == null) {
      // (A PDF file that isn't there: its alt text, as a missing image's.)
      if (_insertPdf(node, target)) return;
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
    if (bytes != null) {
      final (parsed, problem) = _graphicOf(
        bytes,
        format,
        path: data == null ? _lastImagePath : null,
      );
      graphic = parsed;
      if (problem != null) {
        logger.warn('could not embed image: $target; $problem');
      }
    }
    if (graphic == null) {
      _imageAlt(node, target, align);
      return;
    }
    final captionBottom = (_s('image_caption_end') ?? 'bottom') == 'bottom';
    var caption = node.hasTitle
        ? _captionBox(
            node,
            category: 'image',
            bottom: captionBottom,
            blockAlign: align,
          )
        : null;
    // No wider than the theme's image_caption_max_width says (a floated
    // image's caption is in the float's box, as wide as the image).
    final captionMaxWidth = _s('image_caption_max_width');
    final floated = floatTo == 'left' || floatTo == 'right';
    if (caption != null && captionMaxWidth != null && !floated) {
      final sizing = _ImageContent(
        graphic,
        width: _imageWidth(node),
        align: align,
        pageWidth: _pageSize(_document).$1,
      );
      caption = _fitCaption(
        caption,
        (width) => sizing._size(width, double.infinity).$1,
        setting: captionMaxWidth,
        captionKey: 'image_caption',
        blockAlign: align,
      );
    }
    final next = _nextEnclosedBlock(node);
    var margin = _marginBelow(node, next: next);
    final border = node.hasRole('noborder') ? null : _imageBorder();
    // A floated image followed by a paragraph: the paragraphs after it
    // wrap around it (the gem's `init_float_box`).
    var side = floatTo == 'left' || floatTo == 'right' ? floatTo! : null;
    // (In columns, modern engine: one that would leave the text beside it
    // narrower than 12 ems takes its column instead, across it.)
    var across = false;
    if (side != null &&
        !node.hasAttr('shape') &&
        !asciidoctorCompat(_document, CompatFormat.pdf)) {
      if (_columnWidth case final column?) {
        final width = _imageWidth(node)
            .resolve(column, _pageSize(_document).$1);
        if (width != null && column - width < 12 * _font.size) {
          side = null;
          across = true;
        }
      }
    }
    // (One with a `shape`, in the modern engine: a block floating to a side
    // (`_sideFloat`) the text runs around.)
    final shaped =
        node.hasAttr('shape') &&
        !asciidoctorCompat(_document, CompatFormat.pdf);
    if (side != null &&
        !shaped &&
        next is Block &&
        next.context == BlockContext.paragraph) {
      final paragraph = next;
      final gaps = switch (_theme.value('image_float_gap')) {
        ThemeList(:final values) => (
          values.isNotEmpty ? PdfConverter._toPoints(values[0]) : 12.0,
          values.length > 1 ? PdfConverter._toPoints(values[1]) : 6.0,
        ),
        ThemeNumber(:final value) => (value.toDouble(), value.toDouble()),
        _ => (12.0, 6.0),
      };
      final group = _FloatGroup(
        _ImageContent(
          graphic,
          width: _imageWidth(node),
          align: side,
          pageWidth: _pageSize(_document).$1,
          border: border,
          link: node.attr('link'),
        ),
        caption: caption,
        captionBottom: captionBottom,
        side: side,
        gaps: gaps,
      );
      _out.add(CustomBox(group, style: BoxStyle(anchor: node.id)));
      _floatGroup = group;
      _floatNext = paragraph;
      return;
    }
    // `image_placement` (modern engine): the image and its caption float,
    // to the top of the next page when they don't fit, the text after them
    // filling the room; when they fit, to the top or bottom of the page
    // (`top`, `bottom`, `auto`: the nearer), or they stay (`next`).
    // An image in a list, a table or a sidebar stays there.
    final parent = node.parent;
    final topLevel =
        parent is Section ||
        parent is Document ||
        parent?.context == BlockContext.preamble;
    // (The block's own `placement` attribute first: `none` keeps it where
    // it is.)
    // In columns, a figure that spans them floats across the top or bottom
    // of its page (`auto` unless its placement says).
    final span = _spans(node);
    final float = topLevel
        ? switch (node.attr('placement') ?? (span ? 'auto' : _imagePlacement)) {
            'auto' => FloatPlacement.auto,
            'top' => FloatPlacement.top,
            'bottom' => FloatPlacement.bottom,
            'next' => FloatPlacement.next,
            _ => null,
          }
        : null;
    final shown = graphic;
    // (One floating to a side with a shape: as wide as its float, which
    // its width sets.)
    final width = (shaped && side != null) || across
        ? const _ImageWidth.percent(1)
        : _imageWidth(node);
    // A floating image: no margin of its own, its clearance
    // (`image_float_clearance`) between it and the text instead.
    if (float != null && float != FloatPlacement.next) margin = 0;
    final figure = _collect(() {
      if (caption != null && !captionBottom) _out.add(caption);
      _out.add(
        CustomBox(
          _ImageContent(
            shown,
            width: width,
            align: align,
            pageWidth: _pageSize(_document).$1,
            caption: captionBottom ? caption : null,
            border: border,
            link: node.attr('link'),
            whole: !asciidoctorCompat(_document, CompatFormat.pdf),
          ),
          style: BoxStyle(
            anchor: node.id,
            margin: EdgeInsets(
              bottom: caption != null && captionBottom ? 0 : margin,
            ),
          ),
        ),
      );
      if (caption != null && captionBottom) {
        _out.add(caption);
        if (margin > 0) _out.add(SpacerBox(margin));
      }
    });
    if (float != null) {
      _out.add(
        BlockBox(
          figure,
          style: BoxStyle(
            keepTogether: true,
            float: float,
            floatClearance: _imageFloatClearance,
            floatSpan: span,
          ),
        ),
      );
    } else {
      _out.addAll(figure);
    }
  }

  /// Whether the figure [node], in columns, spans them (LaTeX's
  /// `figure*`): its `scope` attribute (`parent` or `page`), else
  /// `image_role_<role>_scope` for one of its roles, else `image_scope`.
  bool _spans(AbstractBlock node) {
    if (!_inColumns) return false;
    var scope = node.attr('scope');
    for (final role in node.roles) {
      scope ??= _keys('image_role_${role.replaceAll('-', '_')}')
          .string('scope');
    }
    scope ??= _s('image_scope');
    return scope == 'parent' || scope == 'page';
  }

  /// The space between a floating image and the text
  /// (`image_float_clearance`, modern engine).
  double get _imageFloatClearance =>
      _length('image_float_clearance', _font.size) ?? 0;

  /// The image [node] that is the [text] of a text file (see
  /// [convertImage]): kept whole, captioned and floated as an image is.
  void _textImage(Block node, String text, String align) {
    final font = _themeFont('image_text', _themeFont('code', _font));
    // Every line kept, the empty one after a final line break too.
    final box = _textBox(
      PdfConverter._guardIndentation(
        text.endsWith('\n') ? '$text\u00a0' : text,
      ),
      font,
      align: 'left',
      normalize: false,
      inlineFormat: false,
    );
    final captionBottom = (_s('image_caption_end') ?? 'bottom') == 'bottom';
    final caption = node.hasTitle
        ? _captionBox(
            node,
            category: 'image',
            bottom: captionBottom,
            blockAlign: align,
          )
        : null;
    var margin = _marginBelow(node, next: _nextEnclosedBlock(node));
    final parent = node.parent;
    final topLevel =
        parent is Section ||
        parent is Document ||
        parent?.context == BlockContext.preamble;
    // The block's own `placement` attribute, else the theme's.
    final placement =
        node.attr('placement') ?? (_spans(node) ? 'auto' : _imagePlacement);
    final span = _spans(node);
    final float = topLevel
        ? switch (placement) {
            'auto' => FloatPlacement.auto,
            'top' => FloatPlacement.top,
            'bottom' => FloatPlacement.bottom,
            'next' => FloatPlacement.next,
            _ => null,
          }
        : null;
    if (float != null && float != FloatPlacement.next) margin = 0;
    final figure = [
      if (caption != null && !captionBottom) caption,
      CustomBox(
        _Aligned(box, align: align),
        style: BoxStyle(
          anchor: node.id,
          margin: EdgeInsets(
            bottom: caption != null && captionBottom ? 0 : margin,
          ),
        ),
      ),
      if (caption != null && captionBottom) ...[
        caption,
        if (margin > 0) SpacerBox(margin),
      ],
    ];
    _out.add(
      BlockBox(
        figure,
        style: BoxStyle(
          keepTogether: true,
          float: float,
          floatClearance: _imageFloatClearance,
          floatSpan: span,
        ),
      ),
    );
  }

  /// The width [node] asks of its image (the gem's
  /// `resolve_explicit_width`, with the theme's `image_width` fallback).
  _ImageWidth _imageWidth(AbstractNode node, {bool fallback = true}) =>
      _imageWidthOf(node.attr, fallback: fallback);
  _ImageWidth _imageWidthOf(
    String? Function(String name) attr, {
    bool fallback = true,
    bool vw = true,
  }) {
    _ImageWidth percent(String value) =>
        _ImageWidth.percent(PdfConverter._toF(value) / 100);
    if (attr('pdfwidth') case final width?) {
      if (width.endsWith('%')) return percent(width);
      if (width.endsWith('iw')) {
        return _ImageWidth.scale(
          PdfConverter._toF(width.substring(0, width.length - 2)) / 100,
        );
      }
      if (vw && width.endsWith('vw')) {
        return _ImageWidth.viewport(
          PdfConverter._toF(width.substring(0, width.length - 2)) / 100,
        );
      }
      return _ImageWidth.points(strToPoints(width));
    }
    if (attr('scale') case final scale?) {
      return _ImageWidth.scale(PdfConverter._toF(scale) / 100);
    }
    if (attr('scaledwidth') case final width?) {
      return width.endsWith('%')
          ? percent(width)
          : _ImageWidth.points(strToPoints(width));
    }
    switch (fallback ? _theme.value('image_width') : null) {
      case ThemeNumber(:final value):
        return _ImageWidth.points(value.toDouble());
      case final ThemeValue value:
        final width = value.rubyString;
        if (width.endsWith('%')) return percent(width);
        if (width.endsWith('vw')) {
          return _ImageWidth.viewport(
            PdfConverter._toF(width.substring(0, width.length - 2)) / 100,
          );
        }
        return _ImageWidth.points(strToPoints(width));
      case null:
        break;
    }
    if (attr('width') case final width?) {
      if (width.endsWith('%')) {
        return _ImageWidth.percent(
          PdfConverter._toF(width) / 100,
          constrain: true,
        );
      }
      if (RegExp(r'^\d+$').hasMatch(width)) {
        return _ImageWidth.points(
          PdfConverter._toF(width) * 0.75,
          constrain: true,
        );
      }
    }
    return const _ImageWidth.natural();
  }

  /// The border the theme draws around images, if any.
  _Border? _imageBorder() {
    final widthValue = _theme.value('image_border_width');
    final widths = _sideWidths(widthValue);
    final width = switch (widthValue) {
      ThemeNumber(:final value) => value.toDouble(),
      _ => widths?.fold<double>(0, math.max) ?? 0.0,
    };
    if (width <= 0) return null;
    final color = pdfColorOf(
      _c('image_border_color') ?? _c('base_border_color'),
    );
    if (color == null) return null;
    return _Border(
      width,
      color,
      widths == null ? (_n('image_border_radius') ?? 0).toDouble() : 0,
      widths: widths,
      style: _s('image_border_style'),
      fitWidth: _s('image_border_fit') == 'auto',
    );
  }

  /// The text that stands in for the image [node] that can't be embedded
  /// (the gem's `on_image_error`).
  void _imageAlt(Block node, String target, String align) {
    final template =
        _s('image_alt_content') ??
        '%{link}[%{alt}]%{/link} | <em>%{target}</em>';
    if (template.isNotEmpty) {
      final link = node.attr('link');
      final text = template
          .replaceAll('%{link}', link == null ? '' : '<a href="$link">')
          .replaceAll('%{/link}', link == null ? '' : '</a>')
          .replaceAll('%{alt}', node.attr('alt') ?? '')
          .replaceAll('%{target}', target);
      _withFont('image_alt', () {
        _out.add(
          CustomBox(
            _textBox(text, _font, align: align, normalize: false),
            style: BoxStyle(anchor: node.id),
          ),
        );
      });
      if (node.hasTitle) _caption(node, category: 'image', bottom: true);
      final margin = _marginBelow(node);
      if (margin > 0) _out.add(SpacerBox(margin));
    }
  }
}
