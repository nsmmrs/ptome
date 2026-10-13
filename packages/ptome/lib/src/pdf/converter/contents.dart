part of '../converter.dart';

// The custom contents the converter lays out, and their helpers.

/// Content that moves to the next region unless [room] points fit below
/// it (a heading kept with what follows).
final class _NeedsRoom implements BaselineContent {
  const new(this.content, this.room);

  final CustomContent content;
  final double room;

  @override
  CustomPlacement? place(
    double width,
    double available, {
    required bool atTop,
  }) {
    if (!atTop) {
      final whole = content.place(width, double.infinity, atTop: true);
      if (whole != null && whole.height + room > available + 0.0001) {
        return null;
      }
    }
    return content.place(width, available, atTop: atTop);
  }

  @override
  double minHeight(double width) => content.minHeight(width) + room;

  @override
  double? firstBaseline(double width) => switch (content) {
    final BaselineContent c => c.firstBaseline(width),
    _ => null,
  };

  @override
  (double, double) intrinsicWidths() => content.intrinsicWidths();
}

enum _NumeralKind { decimal, letters, roman, none }

/// A list numeral (the gem's numbering: integers, letters by Ruby's
/// `String#next`, roman numerals, or none).
final class _Numeral {
  const new decimal(this.value)
    : kind = _NumeralKind.decimal,
      letters = '',
      upper = false;

  const new letters(this.letters)
    : kind = _NumeralKind.letters,
      value = 0,
      upper = false;

  const new roman(this.value, {required this.upper})
    : kind = _NumeralKind.roman,
      letters = '';

  const new none()
    : kind = _NumeralKind.none,
      value = 0,
      letters = '',
      upper = false;

  final _NumeralKind kind;
  final int value;
  final String letters;
  final bool upper;

  String get text => switch (kind) {
    _NumeralKind.decimal => '$value',
    _NumeralKind.letters => letters,
    _NumeralKind.roman => value < 1 ? '$value' : _romanOf(value, upper: upper),
    _NumeralKind.none => '',
  };

  _Numeral get next => switch (kind) {
    _NumeralKind.decimal => _Numeral.decimal(value + 1),
    _NumeralKind.letters => _Numeral.letters(_succ(letters)),
    _NumeralKind.roman => _Numeral.roman(value + 1, upper: upper),
    _NumeralKind.none => this,
  };

  _Numeral get previous => switch (kind) {
    _NumeralKind.decimal => _Numeral.decimal(value - 1),
    _NumeralKind.roman => _Numeral.roman(value - 1, upper: upper),
    _ => this,
  };

  /// Ruby's `String#succ` for letters (`z` to `aa`) and other characters
  /// (the next code point).
  static String _succ(String text) {
    if (text.isEmpty) return text;
    final runes = text.runes.toList();
    var i = runes.length - 1;
    while (i >= 0) {
      final c = runes[i];
      if (c == 0x7a || c == 0x5a) {
        runes[i] = c - 25;
        i--;
        continue;
      }
      runes[i] = c + 1;
      return String.fromCharCodes(runes);
    }
    final first = text.runes.first;
    return String.fromCharCodes([if (first == 0x7a) 0x61 else 0x41, ...runes]);
  }
}

String _romanOf(int number, {required bool upper}) {
  const values = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1];
  const letters = [
    'M',
    'CM',
    'D',
    'CD',
    'C',
    'XC',
    'L',
    'XL',
    'X',
    'IX',
    'V',
    'IV',
    'I',
  ];
  final out = StringBuffer();
  var n = number;
  for (var i = 0; i < values.length; i++) {
    while (n >= values[i]) {
      out.write(letters[i]);
      n -= values[i];
    }
  }
  return upper ? out.toString() : out.toString().toLowerCase();
}

/// Content that moves to the next region unless [minimum] points are
/// left (the gem's `allocate_space_for_list_item`).
final class _MinRoom implements BaselineContent {
  const new(this.content, this.minimum);

  final CustomContent content;
  final double minimum;

  @override
  CustomPlacement? place(
    double width,
    double available, {
    required bool atTop,
  }) {
    if (!atTop && available < minimum) return null;
    return content.place(width, available, atTop: atTop);
  }

  @override
  double minHeight(double width) => content.minHeight(width);

  @override
  double? firstBaseline(double width) => switch (content) {
    final BaselineContent c => c.firstBaseline(width),
    _ => null,
  };

  @override
  (double, double) intrinsicWidths() => content.intrinsicWidths();
}

/// Content with a marker drawn beside its first piece: [marker] laid out
/// [markerWidth] wide, [offset] points from the content's left edge.
final class _Marked implements BaselineContent {
  const new(this.content, this.marker, this.markerWidth, this.offset);

  final CustomContent content;
  final CustomContent marker;
  final double markerWidth;
  final double offset;

  @override
  CustomPlacement? place(
    double width,
    double available, {
    required bool atTop,
  }) {
    final placed = content.place(width, available, atTop: atTop);
    if (placed == null) return null;
    final mark = marker.place(markerWidth, double.infinity, atTop: true);
    return CustomPlacement(
      height: placed.height,
      rest: placed.rest,
      anchors: placed.anchors,
      lines: placed.lines,
      paint: (page, x, top) {
        mark?.paint(page, x + offset, top);
        placed.paint(page, x, top);
      },
    );
  }

  @override
  double minHeight(double width) => content.minHeight(width);

  @override
  double? firstBaseline(double width) => switch (content) {
    final BaselineContent c => c.firstBaseline(width),
    _ => null,
  };

  @override
  (double, double) intrinsicWidths() => content.intrinsicWidths();
}

/// A drop: its text, its theme category (`heading_h2_drop`,
/// `role_dropcap_drop`) and the lines it spans.
typedef _Drop = ({String text, String category, int lines});

/// Opening punctuation, which an initial takes with its letter.
final RegExp _openingPunctuation = RegExp('^[“‘"\'«‹(\\[¿¡„‚]+');

/// Text with a drop beside its first lines: [drop] drawn [width] wide at
/// the text's left, [dy] points down from its top.
final class _Dropped implements BaselineContent {
  const new(this.text, this.drop, this.width, this.dy, {this.shift = 0});

  final CustomContent text;
  final CustomContent drop;
  final double width;
  final double dy;

  /// How far left of the text's edge the drop starts (its opening
  /// punctuation's width).
  final double shift;

  @override
  CustomPlacement? place(
    double width,
    double available, {
    required bool atTop,
  }) {
    final placed = text.place(width, available, atTop: atTop);
    if (placed == null) return null;
    final mark = drop.place(this.width, double.infinity, atTop: true);
    // (A paragraph shorter than its drop as deep as the drop, so that
    // what follows clears it.)
    final depth = mark == null ? 0.0 : dy + mark.height;
    return CustomPlacement(
      height: placed.rest == null && depth > placed.height
          ? depth
          : placed.height,
      rest: placed.rest,
      anchors: placed.anchors,
      lines: placed.lines,
      paint: (page, x, top) {
        mark?.paint(page, x - shift, top - dy);
        placed.paint(page, x, top);
      },
    );
  }

  @override
  double minHeight(double width) => text.minHeight(width);

  @override
  double? firstBaseline(double width) => switch (text) {
    final BaselineContent c => c.firstBaseline(width),
    _ => null,
  };

  @override
  (double, double) intrinsicWidths() => text.intrinsicWidths();
}

/// Nothing: no room taken, nothing drawn.
final class _Nothing implements CustomContent {
  const new();

  @override
  CustomPlacement? place(
    double width,
    double available, {
    required bool atTop,
  }) => CustomPlacement(height: 0, paint: (page, x, top) {});

  @override
  double minHeight(double width) => 0;

  @override
  (double, double) intrinsicWidths() => (0, 0);
}

/// [content], drawn only when [shown] says so as the page is drawn (it
/// takes its room either way): a thematic break's mark set where the break
/// falls at a page's top or bottom.
final class _ShownWhen implements BaselineContent {
  const new(this.content, this.shown);

  final CustomContent content;
  final bool Function() shown;

  @override
  CustomPlacement? place(
    double width,
    double available, {
    required bool atTop,
  }) {
    final placed = content.place(width, available, atTop: atTop);
    if (placed == null) return null;
    return CustomPlacement(
      height: placed.height,
      paint: (page, x, top) {
        if (shown()) placed.paint(page, x, top);
      },
      anchors: placed.anchors,
    );
  }

  @override
  double minHeight(double width) => content.minHeight(width);

  @override
  (double, double) intrinsicWidths() => content.intrinsicWidths();

  // (On a baseline grid as the content would be, shown or not: a scene
  // break one line deep.)
  @override
  double? firstBaseline(double width) => switch (content) {
    final BaselineContent text => text.firstBaseline(width),
    _ => null,
  };
}

/// How wide an image is asked to be.
enum _ImageWidthKind { natural, points, percent, scale, viewport }

/// The width asked of an image: its own, [value] points, a [value]
/// fraction of the available width or of the page's, or its own scaled by
/// [value]; [constrain]ed to the available width.
final class _ImageWidth {
  const new natural()
    : kind = _ImageWidthKind.natural,
      value = 0,
      constrain = false;

  const new points(this.value, {this.constrain = false})
    : kind = _ImageWidthKind.points;

  const new percent(this.value, {this.constrain = false})
    : kind = _ImageWidthKind.percent;

  const new scale(this.value) : kind = _ImageWidthKind.scale, constrain = false;

  const new viewport(this.value)
    : kind = _ImageWidthKind.viewport,
      constrain = false;

  final _ImageWidthKind kind;
  final double value;
  final bool constrain;

  /// The width in points for [available] points and a page [pageWidth]
  /// wide, or null for the image's own (or a scale).
  double? resolve(double available, double pageWidth) {
    final width = switch (kind) {
      _ImageWidthKind.points => value,
      _ImageWidthKind.percent => value * available,
      _ImageWidthKind.viewport => value * pageWidth,
      _ImageWidthKind.natural || _ImageWidthKind.scale => null,
    };
    return width != null && constrain ? math.min(width, available) : width;
  }
}

/// A border around an image.
final class _Border {
  const new(
    this.width,
    this.color,
    this.radius, {
    required this.fitWidth,
    this.widths,
    this.style,
  });

  final double width;
  final Color color;
  final double radius;

  /// The widths side by side (top, right, bottom, left), if they differ.
  final List<double>? widths;

  /// The line style (`dashed`...).
  final String? style;

  /// Whether the border spans the available width, not the image's.
  final bool fitWidth;
}

/// [content] as wide as it needs (its widest line), at the left, in the
/// middle or at the right of the room ([align]).
final class _Aligned implements CustomContent {
  const new(this.content, {this.align = 'left'});

  final CustomContent content;
  final String align;

  @override
  CustomPlacement? place(
    double width,
    double available, {
    required bool atTop,
  }) {
    final wide = math.min(width, content.intrinsicWidths().$2);
    final placed = content.place(wide, available, atTop: atTop);
    if (placed == null) return null;
    final offset = switch (align) {
      'center' => (width - wide) / 2,
      'right' => width - wide,
      _ => 0.0,
    };
    return CustomPlacement(
      height: placed.height,
      anchors: [
        for (final (name, x, y) in placed.anchors) (name, x + offset, y),
      ],
      lines: placed.lines._shifted(dx: offset),
      rest: placed.rest == null ? null : _Aligned(placed.rest!, align: align),
      paint: (page, x, top) => placed.paint(page, x + offset, top),
    );
  }

  @override
  double minHeight(double width) => content.minHeight(width);

  @override
  (double, double) intrinsicWidths() => content.intrinsicWidths();
}

/// A block image sized and placed as asciidoctor-pdf places it: no wider
/// than the available width, moved to the next page when it doesn't fit
/// (with its [caption] below it), else shrunk to fit.
final class _ImageContent implements CustomContent {
  const new(
    this.graphic, {
    required this.width,
    required this.align,
    required this.pageWidth,
    this.caption,
    this.border,
    this.link,
    this.whole = false,
  });

  final Graphic graphic;
  final _ImageWidth width;
  final String align;
  final double pageWidth;
  final CustomBox? caption;
  final _Border? border;
  final String? link;

  /// Whether it starts only whole (modern engine): its height is the
  /// least a heading before it keeps with it.
  final bool whole;

  /// The image's size for [available] points of width (and [height] of
  /// region, for SVG sizes in percent).
  (double, double) _size(double available, double height) {
    final asked = width.resolve(available, pageWidth);
    switch (graphic) {
      case final SvgImage svg:
        var (w, h) = prawnSvgSize(svg, asked, null, available, height);
        if (width.kind == _ImageWidthKind.scale) {
          (w, h) = prawnSvgSize(
            svg,
            math.min(available, w * width.value),
            null,
            available,
            height,
          );
        } else if (asked == null &&
            svg.rootAttribute('width') != null &&
            w > available) {
          (w, h) = prawnSvgSize(svg, available, null, available, height);
        }
        return (w, h);
      case final other:
        final natural = other.intrinsicWidth * 0.75;
        final w =
            asked ??
            (width.kind == _ImageWidthKind.scale
                ? natural * width.value
                : math.min(available, natural));
        return (w, other.intrinsicHeight * w / other.intrinsicWidth);
    }
  }

  @override
  CustomPlacement? place(
    double width,
    double available, {
    required bool atTop,
  }) {
    final captionHeight = switch (caption) {
      final CustomBox box? =>
        (box.content.place(width, double.infinity, atTop: true)?.height ?? 0) +
            box.style.margin.vertical,
      null => 0.0,
    };
    final regionHeight = available.isFinite ? available : 1000000000.0;
    var (w, h) = _size(width, regionHeight);
    final room = available - captionHeight;
    if (h > room + 1e-6) {
      if (!atTop) return null;
      if (room > 0) {
        if (graphic case final SvgImage svg) {
          (w, h) = prawnSvgSize(svg, null, room, width, regionHeight);
        } else {
          w = w * room / h;
          h = room;
        }
      }
    }
    final left = switch (align) {
      'center' => (width - w) * 0.5,
      'right' => width - w,
      _ => 0.0,
    };
    return CustomPlacement(
      height: h,
      paint: (page, x, top) {
        final rect = Rect(x + left, top - h, w, h);
        final canvas = page.canvas;
        switch (graphic) {
          case final PdfImage image:
            image.paint(canvas, rect);
          case final other:
            canvas.save();
            other.paint(canvas, rect);
            canvas.restore();
        }
        if (border case final border?) {
          final frame = border.fitWidth ? Rect(x, top - h, width, h) : rect;
          PdfConverter._strokeBounds(
            canvas,
            frame,
            border.color,
            width: border.width,
            widths: border.widths,
            style: border.style,
            radius: border.radius,
          );
        }
        if (link case final link?) {
          page.link(
            rect,
            link.startsWith('#')
                ? LinkTarget.named(destinationName(link.substring(1)))
                : LinkTarget.uri(link),
          );
        }
      },
    );
  }

  @override
  double minHeight(double width) => whole ? _size(width, 1000000000).$2 : 0;

  @override
  (double, double) intrinsicWidths() => (0, graphic.intrinsicWidth);
}

/// A table cell's content and style, before it is laid out.
final class _TableCellData {
  const new({
    required this.text,
    required this.font,
    required this.padding,
    required this.colspan,
    required this.rowspan,
    required this.align,
    required this.valign,
    this.blocks,
    this.background,
    this.inlineFormat = true,
  });

  final String text;
  final List<LayoutBox>? blocks;
  final _FontState font;
  final List<double> padding;
  final ThemeColor? background;
  final int colspan;
  final int rowspan;
  final String align;
  final String valign;
  final bool inlineFormat;
}

/// One side of a table cell's border.
final class _Side {
  const new(this.width, this.color, this.style);

  final double width;
  final ThemeValue? color;
  final ThemeValue? style;
}

/// [content] laid out [extra] points wider than it is given (prawn-table
/// widens a cell's text by its `FPTolerance`, a point).
final class _Widened implements BaselineContent {
  const new(this.content, this.extra);

  final CustomContent content;
  final double extra;

  @override
  CustomPlacement? place(
    double width,
    double available, {
    required bool atTop,
  }) => content.place(width + extra, available, atTop: atTop);

  @override
  double minHeight(double width) => content.minHeight(width + extra);

  @override
  double? firstBaseline(double width) => switch (content) {
    final BaselineContent c => c.firstBaseline(width + extra),
    _ => null,
  };

  @override
  (double, double) intrinsicWidths() => content.intrinsicWidths();
}

/// A jump line's cross reference: its target and text.
final RegExp _jumpAnchorRx = RegExp(
  r'^<a anchor="([^"]+)">(.*)</a>$',
  dotAll: true,
);

/// Text worded only once the pages are laid out: [text] measured with a
/// placeholder page (`000`) and painted with [page]'s.
final class _LateText implements CustomContent {
  const new(this.text, this.page);

  final CustomContent Function(String page) text;
  final String Function() page;

  @override
  CustomPlacement? place(
    double width,
    double available, {
    required bool atTop,
  }) {
    final measured = text('000').place(width, available, atTop: atTop);
    if (measured == null || measured.rest != null) return measured;
    return CustomPlacement(
      height: measured.height,
      anchors: measured.anchors,
      lines: measured.lines,
      paint: (canvas, x, top) =>
          text(page())
              .place(width, double.infinity, atTop: true)
              ?.paint(canvas, x, top),
    );
  }

  @override
  double minHeight(double width) => text('000').minHeight(width);

  @override
  (double, double) intrinsicWidths() => text('000').intrinsicWidths();
}

/// A heading's number: its title's first `[.number]` span (group 1), and
/// the space after it.
final RegExp _headingNumberRx = RegExp(
  r'^(<span class="(?:[^"]* )?number(?: [^"]*)?">.*?</span>)\s*',
);

/// A heading's [title] with its [number] hung left of its edge: [hang]
/// from it, or the number's width and [gap] when that is more, at the
/// title's top (their first lines' baselines meet).
final class _Hung implements BaselineContent {
  const new(this.title, this.number, this.hang, {required this.gap});

  final CustomContent title;
  final CustomContent number;
  final double hang;
  final double gap;

  @override
  CustomPlacement? place(
    double width,
    double available, {
    required bool atTop,
  }) {
    final placed = title.place(width, available, atTop: atTop);
    if (placed == null) return null;
    final numberWidth = number.intrinsicWidths().$2;
    final mark = number.place(numberWidth + 1, double.infinity, atTop: true);
    final offset = math.max(hang, numberWidth + gap);
    return CustomPlacement(
      height: placed.height,
      rest: placed.rest,
      anchors: placed.anchors,
      lines: placed.lines,
      paint: (page, x, top) {
        placed.paint(page, x, top);
        mark?.paint(page, x - offset, top);
      },
    );
  }

  @override
  double minHeight(double width) => title.minHeight(width);

  @override
  double? firstBaseline(double width) => switch (title) {
    final BaselineContent c => c.firstBaseline(width),
    _ => null,
  };

  @override
  (double, double) intrinsicWidths() => title.intrinsicWidths();
}

/// [content] with a [gap] above it at the top of a page (a heading's
/// `margin_page_top`).
final class _PageTopGap implements CustomContent {
  const new(this.content, this.gap);

  final CustomContent content;
  final double gap;

  @override
  CustomPlacement? place(
    double width,
    double available, {
    required bool atTop,
  }) {
    if (!atTop) return content.place(width, available, atTop: atTop);
    final placed = content.place(width, available - gap, atTop: true);
    if (placed == null) return null;
    return CustomPlacement(
      height: placed.height + gap,
      rest: placed.rest,
      anchors: [for (final (name, x, y) in placed.anchors) (name, x, y + gap)],
      lines: placed.lines._shifted(dy: gap),
      paint: (page, x, top) => placed.paint(page, x, top - gap),
    );
  }

  @override
  double minHeight(double width) => content.minHeight(width);

  @override
  (double, double) intrinsicWidths() => content.intrinsicWidths();
}

/// Content drawn where [paint] draws it, taking no room (or, with
/// [fill], the rest of the region: a cover page).
final class _Absolute implements CustomContent {
  const new(this.paint, {this.fill = false});

  final void Function(LayoutPage page) paint;
  final bool fill;

  @override
  CustomPlacement? place(
    double width,
    double available, {
    required bool atTop,
  }) => CustomPlacement(
    height: fill && available.isFinite ? available : 0,
    paint: (page, x, top) => paint(page),
  );

  @override
  double minHeight(double width) => 0;

  @override
  (double, double) intrinsicWidths() => (0, 0);
}

/// The platform's zlib (the Dart VM's), faster than plain_pdf's own.
/// A PNG image's samples encoded as the PDF is saved with
/// ([PngImage.encode]), from the file's [bytes].
final class _PngEncoding extends Job<PngPayload> {
  const new(this.bytes, {required this.nativeZlib});

  final Uint8List bytes;
  final bool nativeZlib;

  @override
  PngPayload run() =>
      PngImage.parse(bytes)
          .encode(PdfConverter._writerOptions(nativeZlib: nativeZlib));
}

/// A stream's [data] encoded as the PDF is saved with ([encodeStream]).
final class _StreamEncoding extends Job<StreamPayload> {
  const new(this.data, {required this.nativeZlib});

  final Uint8List data;
  final bool nativeZlib;

  @override
  StreamPayload run() =>
      encodeStream(data, PdfConverter._writerOptions(nativeZlib: nativeZlib));
}

final class _NativeZlib implements ZlibCodec {
  const new();

  @override
  Uint8List encode(List<int> data, int level) =>
      Uint8List.fromList(io.zlibEncode(data, level));

  @override
  Uint8List decode(List<int> data) => Uint8List.fromList(io.zlibDecode(data));
}

/// A formula set on its own (a STEM block): aligned in the room, scaled
/// down to fit it when wider, copied as its [source].
final class _DisplayMath implements CustomContent {
  const new(this.box, this.source, {required this.align, this.color});

  final MathBox box;
  final String source;
  final String align;
  final Color? color;

  @override
  CustomPlacement? place(
    double width,
    double available, {
    required bool atTop,
  }) {
    final scale = box.width > width ? width / box.width : 1.0;
    final height = (box.height + box.depth) * scale;
    if (height > available + 1e-6 && !atTop) return null;
    final left = switch (align) {
      'left' => 0.0,
      'right' => width - box.width * scale,
      _ => (width - box.width * scale) / 2,
    };
    return CustomPlacement(
      height: height,
      paint: (page, x, top) {
        final canvas = page.canvas
          ..save()
          ..beginMarkedContent('Span', actualText: source);
        if (color case final color?) {
          canvas
            ..setFillColor(color)
            ..setStrokeColor(color);
        }
        box.paint(
          canvas,
          Rect(x + left, top - height, box.width * scale, height),
        );
        canvas
          ..endMarkedContent()
          ..restore();
      },
    );
  }

  @override
  double minHeight(double width) =>
      (box.height + box.depth) * (box.width > width ? width / box.width : 1.0);

  @override
  (double, double) intrinsicWidths() => (box.width, box.width);
}

/// An entry of the table of contents: its title (as wide as the room
/// less a [placeholder] for the page number), then a dot leader and the
/// page number on its last line, made by [leader] for the width and where
/// the dots start.
final class _TocEntry implements CustomContent {
  const new(
    this.title,
    this.placeholder,
    this.leader, {
    this.hanging = 0,
    this.rightToLeft = false,
  });

  /// The title: a text box, or what is left of one the engine sets.
  final CustomContent title;
  final double placeholder;
  final CustomContent Function(double width, double startDots) leader;

  /// How much the lines after the first are indented (the title is set
  /// that much in, its first line as much out).
  final double hanging;

  /// Whether the entry is mirrored (a right-to-left document's): its
  /// title at the right, the hanging indent there, the leader and the
  /// page number at the left; [leader] is then given the width from the
  /// right edge to the title's last line's start.
  final bool rightToLeft;

  @override
  CustomPlacement? place(
    double width,
    double available, {
    required bool atTop,
  }) {
    final room = width - placeholder - hanging;
    final placed = title.place(room, available, atTop: atTop);
    if (placed == null) return null;
    // (The title's offset: mirrored, past the page number's room.)
    final offset = rightToLeft ? placeholder : hanging;
    if (placed.rest case final rest?) {
      return CustomPlacement(
        height: placed.height,
        anchors: placed.anchors,
        rest: _TocEntry(
          rest,
          placeholder,
          leader,
          hanging: hanging,
          rightToLeft: rightToLeft,
        ),
        paint: (page, x, top) => placed.paint(page, x + offset, top),
      );
    }
    final last = switch (title) {
      final TextBox box => box.lastFragment(room),
      final ParagraphContent paragraph => paragraphLastFragment(
        paragraph,
        room,
      ),
      _ => null,
    };
    return CustomPlacement(
      height: placed.height,
      anchors: placed.anchors,
      paint: (page, x, top) {
        placed.paint(page, x + offset, top);
        if (last == null) return;
        final dots = leader(
          width,
          rightToLeft ? width - (offset + last.left) : last.right + offset,
        );
        final line = dots.place(width, double.infinity, atTop: true);
        if (line == null) return;
        // On the title's last line, on its baseline (else at the top of
        // its last fragment).
        final drop = switch (dots) {
          TextBox(:final lastFragment) => switch (lastFragment(width)) {
            final own? => last.baseline - own.baseline,
            null => null,
          },
          _ => null,
        };
        final multiline = last.top - last.firstTop > 1;
        line.paint(
          page,
          x,
          top - (drop ?? (multiline ? last.top - last.firstTop : 0.0)),
        );
      },
    );
  }

  @override
  double minHeight(double width) => title.minHeight(width - placeholder);

  @override
  (double, double) intrinsicWidths() => title.intrinsicWidths();
}

/// [content] [gap] below what comes before it, or nothing (no room, no
/// gap) when [hidden] says so as it's laid out.
final class _Unless implements CustomContent {
  const new(this.hidden, this.content, {this.gap = 0});

  final bool Function() hidden;
  final CustomContent content;
  final double gap;

  @override
  CustomPlacement? place(
    double width,
    double available, {
    required bool atTop,
  }) {
    if (hidden()) return CustomPlacement(height: 0, paint: (page, x, top) {});
    final placed = content.place(width, available - gap, atTop: atTop);
    if (placed == null) return null;
    return CustomPlacement(
      height: placed.height + gap,
      anchors: [for (final (name, x, y) in placed.anchors) (name, x, y + gap)],
      rest: placed.rest,
      paint: (page, x, top) => placed.paint(page, x, top - gap),
    );
  }

  @override
  double minHeight(double width) =>
      hidden() ? 0 : content.minHeight(width) + gap;

  @override
  (double, double) intrinsicWidths() =>
      hidden() ? (0, 0) : content.intrinsicWidths();
}

/// An index entry with its page numbers in a column: the [term] at the
/// left, the [numbers] right-aligned at the right (as wide as they are,
/// up to half the width), [gap] apart, both from the top.
final class _IndexRow implements CustomContent {
  const new(this.term, this.numbers, {required this.gap});

  final TextBox term;
  final TextBox numbers;
  final double gap;

  double _numbersWidth(double width) =>
      math.min(numbers.intrinsicWidths().$2, width / 2);

  @override
  CustomPlacement? place(
    double width,
    double available, {
    required bool atTop,
  }) {
    final numbersWidth = _numbersWidth(width);
    final room = atTop ? double.infinity : available;
    final left = term.place(width - numbersWidth - gap, room, atTop: atTop);
    final right = numbers.place(numbersWidth, room, atTop: atTop);
    // An entry isn't split: it moves on whole.
    if (left == null || right == null) return null;
    if (left.rest != null || right.rest != null) return null;
    final height = math.max(left.height, right.height);
    if (!atTop && height > available) return null;
    final offset = width - numbersWidth;
    return CustomPlacement(
      height: height,
      anchors: [
        ...left.anchors,
        for (final (name, ax, ay) in right.anchors) (name, ax + offset, ay),
      ],
      paint: (page, x, top) {
        left.paint(page, x, top);
        right.paint(page, x + offset, top);
      },
    );
  }

  @override
  double minHeight(double width) {
    final numbersWidth = _numbersWidth(width);
    return math.max(
      term.minHeight(width - numbersWidth - gap),
      numbers.minHeight(numbersWidth),
    );
  }

  @override
  (double, double) intrinsicWidths() {
    final (termMin, termMax) = term.intrinsicWidths();
    final (numbersMin, numbersMax) = numbers.intrinsicWidths();
    return (termMin + gap + numbersMin, termMax + gap + numbersMax);
  }
}

/// [items] one below the other, at the bottom of the region when
/// [bottom] and they fit there (footnotes), else flowing on (an item that
/// doesn't fit split where it breaks).
final class _Stacked implements CustomContent {
  const new(this.items, {required this.bottom});

  final List<CustomBox> items;
  final bool bottom;

  @override
  CustomPlacement? place(
    double width,
    double available, {
    required bool atTop,
  }) {
    final placements = <(CustomPlacement, double, double)>[];
    var height = 0.0;
    List<CustomBox>? rest;
    for (final (i, item) in items.indexed) {
      final margin = item.style.margin;
      final fresh = atTop && height == 0;
      final top = fresh ? 0.0 : margin.top;
      final placed = item.content.place(
        width - margin.horizontal,
        available - height - top,
        atTop: fresh,
      );
      if (placed == null) {
        rest = items.sublist(i);
        break;
      }
      placements.add((placed, height + top, margin.left));
      if (placed.rest case final more?) {
        height += top + placed.height;
        rest = [
          CustomBox(
            more,
            style: BoxStyle(margin: EdgeInsets(bottom: margin.bottom)),
          ),
          ...items.sublist(i + 1),
        ];
        break;
      }
      height += top + placed.height + margin.bottom;
    }
    if (placements.isEmpty && !atTop) return null;
    final shift = rest == null && bottom && available.isFinite
        ? math.max(0, available - height - 0.0001)
        : 0.0;
    return CustomPlacement(
      height: height + shift,
      anchors: [
        for (final (placed, y, x) in placements)
          for (final (name, ax, ay) in placed.anchors)
            (name, ax + x, ay + y + shift),
      ],
      rest: rest == null || rest.isEmpty ? null : _Stacked(rest, bottom: false),
      paint: (page, x, top) {
        for (final (placed, y, left) in placements) {
          placed.paint(page, x + left, top - shift - y);
        }
      },
    );
  }

  @override
  double minHeight(double width) => 0;

  @override
  (double, double) intrinsicWidths() => (0, 0);
}

/// A paragraph after a floated image: its text as it flows, and as it is
/// set beside the image (no gaps above and below), with what the gem
/// measures it by.
final class _FloatParagraph {
  const new(
    this.text,
    this.boxText, {
    required this.marginBottom,
    required this.blockMargin,
    required this.paddingTop,
    required this.paddingBottom,
    required this.lineLength,
    required this.descender,
    this.anchor,
  });

  final TextBox text;
  final TextBox boxText;
  final double marginBottom;
  final double blockMargin;
  final double paddingTop;
  final double paddingBottom;
  final double lineLength;
  final double descender;
  final String? anchor;
}

/// A floated image and the paragraphs after it, which wrap around it
/// while they start beside it (the gem's `init_float_box` and
/// `ink_paragraph_in_float_box`), then flow on below.
final class _FloatGroup implements CustomContent {
  new(
    this.image, {
    required this.side,
    required this.gaps,
    this.caption,
    this.captionBottom = true,
  });

  final _ImageContent image;
  final CustomBox? caption;
  final bool captionBottom;
  final String side;
  final (double, double) gaps;
  final List<_FloatParagraph> paragraphs = [];

  CustomBox _flowing(_FloatParagraph paragraph) => CustomBox(
    paragraph.text,
    style: BoxStyle(
      margin: EdgeInsets(bottom: paragraph.marginBottom),
      anchor: paragraph.anchor,
    ),
  );

  @override
  CustomPlacement? place(
    double width,
    double available, {
    required bool atTop,
  }) {
    final regionHeight = available.isFinite ? available : 1000000000.0;
    final (imageWidth, _) = image._size(width, regionHeight);
    // The image (with its caption) as it's drawn.
    final pieces = <(CustomPlacement, double, double)>[];
    var blockHeight = 0.0;
    void addCaption() {
      final box = caption;
      if (box == null) return;
      final margin = box.style.margin;
      final placed = box.content.place(
        imageWidth,
        double.infinity,
        atTop: true,
      );
      if (placed == null) return;
      final x = side == 'right' ? width - imageWidth : 0.0;
      pieces.add((placed, blockHeight + margin.top, x));
      blockHeight += margin.top + placed.height + margin.bottom;
    }

    if (!captionBottom) addCaption();
    final placedImage = image.place(
      width,
      available - blockHeight,
      atTop: atTop,
    );
    if (placedImage == null) return null;
    pieces.add((placedImage, blockHeight, 0));
    blockHeight += placedImage.height;
    if (captionBottom) addCaption();
    final anchors = <(String, double, double)>[];
    var cursor = 0.0;
    var queue = <CustomBox>[];
    var index = 0;
    if (imageWidth < width) {
      final (gapX, gapY) = gaps;
      final boxLeft = side == 'right' ? 0.0 : imageWidth + gapX;
      final boxWidth = width - imageWidth - gapX;
      final boxHeight = math.min(regionHeight, blockHeight + gapY);
      var inFloat = true;
      while (inFloat && index < paragraphs.length) {
        final paragraph = paragraphs[index++];
        final start = cursor;
        final limit = math.min(
          regionHeight - start,
          boxHeight - start + paragraph.lineLength,
        );
        final placed = paragraph.boxText.place(
          boxWidth,
          limit - paragraph.paddingTop,
          atTop: false,
        );
        final printed = placed != null && placed.height > 0;
        if (paragraph.anchor case final id?) anchors.add((id, boxLeft, start));
        var end = start;
        if (printed) {
          pieces.add((placed, start + paragraph.paddingTop, boxLeft));
          end =
              start +
              paragraph.paddingTop +
              placed.height +
              paragraph.paddingBottom;
        }
        final overflow = placed == null ? paragraph.boxText : placed.rest;
        final moreParagraphs = index < paragraphs.length;
        if (overflow == null) {
          if (moreParagraphs) {
            cursor = end + paragraph.marginBottom;
            inFloat = cursor < start + limit;
          } else if (end < blockHeight) {
            cursor = blockHeight + paragraph.blockMargin;
            inFloat = false;
          } else {
            cursor = end + paragraph.marginBottom;
            inFloat = false;
          }
        } else {
          if (!printed && start < boxHeight) end = boxHeight;
          cursor = end;
          final text = overflow is TextBox
              ? overflow.restyled(paragraph.text.state, paragraph.text.layout)
              : overflow;
          queue.add(
            CustomBox(
              text,
              style: BoxStyle(
                margin: EdgeInsets(bottom: paragraph.marginBottom),
              ),
            ),
          );
          inFloat = false;
        }
      }
    }
    queue = [...queue, for (final p in paragraphs.skip(index)) _flowing(p)];
    if (imageWidth >= width) cursor = blockHeight;
    CustomContent? rest;
    if (queue.isNotEmpty) {
      final flow = _Stacked(
        queue,
        bottom: false,
      ).place(width, available - cursor, atTop: false);
      if (flow == null) {
        rest = _Stacked(queue, bottom: false);
      } else {
        pieces.add((flow, cursor, 0));
        cursor += flow.height;
        rest = flow.rest;
      }
    }
    final height = math.max(cursor, imageWidth >= width ? blockHeight : 0.0);
    return CustomPlacement(
      height: height,
      anchors: [
        ...anchors,
        for (final (placed, y, x) in pieces)
          for (final (name, ax, ay) in placed.anchors) (name, ax + x, ay + y),
      ],
      rest: rest,
      paint: (page, x, top) {
        for (final (placed, y, left) in pieces) {
          placed.paint(page, x + left, top - y);
        }
      },
    );
  }

  @override
  double minHeight(double width) => 0;

  @override
  (double, double) intrinsicWidths() => (0, 0);
}

/// A page-sized image: how it fits the page and where it sits.
final class _PageImage {
  const new(
    this.graphic, {
    required this.fit,
    required this.position,
    required this.vposition,
    this.width,
  });

  final Graphic graphic;
  final String fit;
  final double? width;
  final String position;
  final String vposition;
}

/// [content] indented by [indents] (left and right) for the width it's
/// given.
final class _Indented implements BaselineContent {
  const new(this.content, this.indents);

  final CustomContent content;
  final (double, double) Function(double width) indents;

  @override
  CustomPlacement? place(
    double width,
    double available, {
    required bool atTop,
  }) {
    final (left, right) = indents(width);
    final placed = content.place(width - left - right, available, atTop: atTop);
    if (placed == null) return null;
    return CustomPlacement(
      height: placed.height,
      rest: placed.rest,
      anchors: [for (final (name, x, y) in placed.anchors) (name, x + left, y)],
      lines: placed.lines._shifted(dx: left),
      paint: (page, x, top) => placed.paint(page, x + left, top),
    );
  }

  @override
  double minHeight(double width) {
    final (left, right) = indents(width);
    return content.minHeight(width - left - right);
  }

  @override
  double? firstBaseline(double width) {
    final (left, right) = indents(width);
    return switch (content) {
      final BaselineContent c => c.firstBaseline(width - left - right),
      _ => null,
    };
  }

  @override
  (double, double) intrinsicWidths() => content.intrinsicWidths();
}

extension on List<PieceLine> {
  /// These lines [dx] further right and [dy] further down.
  List<PieceLine> _shifted({double dx = 0, double dy = 0}) => [
    for (final line in this)
      PieceLine(
        line.baseline + dy,
        left: line.left + dx,
        right: line.right + dx,
        continues: line.continues,
      ),
  ];
}

/// Which lines are numbered: those the text is set in, the source's
/// (a wrapped line counted once), or a fixed grid down the page.
enum _LineKind { typeset, logical, grid }

/// How the body's lines are numbered (`line-numbers`, `line_numbers_*`).
final class _LineNumbering {
  const new(
    this.kind, {
    required this.interval,
    required this.restart,
    required this.side,
    required this.gap,
    required this.width,
    required this.font,
    required this.pitch,
    required this.firstBaseline,
    this.align,
    this.rules = const [],
    this.ruleColor,
  });

  /// The widths of the vertical rules between the numbers and the text,
  /// the page's height (pleading paper's single or double line), and
  /// their color.
  final List<double> rules;
  final Color? ruleColor;

  final _LineKind kind;

  /// Every how many lines a number is shown.
  final int interval;

  /// Where the count starts again: `page`, `section` or `none`.
  final String restart;

  /// The margin the numbers are in: `left`, `right`, `outer`, `inner`.
  final String side;

  /// The space between the text and the numbers.
  final double gap;

  /// How the numbers align in their column, `left` or `right` (null:
  /// toward the text), and the column's width.
  final String? align;
  final double width;

  final _FontState font;

  /// A grid's line pitch and its first line's baseline below the top.
  final double pitch;
  final double firstBaseline;
}

/// A page that is only its [canvas] (no links): for text drawn over a
/// page's content.
final class _CanvasPage implements LayoutPage {
  const new(this.canvas);

  @override
  final Canvas canvas;

  @override
  void link(Rect rect, LinkTarget target) {}
}

/// A line of a listing as the engine sets it: the line, how far in it is
/// drawn, and whether its text goes on in the next (it wrapped).
typedef _CodeLine = ({Line line, double x, bool wrapped, bool continues});

/// A listing set by the engine's paragraphs (modern engine): each of its
/// lines a paragraph of its own (its text and the width of its leading
/// spaces), broken greedily at spaces and hyphens (between characters
/// where a word is wider than the line), a line that wraps going on
/// [wrapIndent] in from its own indentation, at most half the width,
/// with an arrow after it where [marker] asks, as the text box sets code.
final class _EngineCode implements LinedContent, BaselineContent {
  new(
    this.paragraphs, {
    required this.wrapIndent,
    required this.marker,
    required this.orphans,
    required this.widows,
  }) : _fixed = null;

  new _rest(_EngineCode source, List<_CodeLine> this._fixed)
    : paragraphs = const [],
      wrapIndent = source.wrapIndent,
      marker = source.marker,
      orphans = source.orphans,
      widows = source.widows;

  /// Each line of the listing: its paragraph and the width of its leading
  /// spaces.
  final List<(Paragraph, double)> paragraphs;

  final double wrapIndent;
  final bool marker;

  @override
  final int orphans;

  @override
  final int widows;

  /// The lines left after a break, set at the width they were broken at.
  final List<_CodeLine>? _fixed;

  final Map<double, List<_CodeLine>> _lines = {};

  List<_CodeLine> _linesAt(double width) =>
      _fixed ??
      (_lines[width] ??= [
        for (final (paragraph, own) in paragraphs)
          ...() {
            // (Its lines after the first in by its own indent and the
            // hanging indent: the first one that far out.)
            final x = math.min(own + wrapIndent, width / 2);
            final set = ParagraphContent(
              paragraph.copyWith(firstLineIndent: -x),
              lineBreaker: const FirstFitLineBreaker(),
            ).linesAt(width - x);
            return [
              for (final (i, line) in set.indexed)
                (
                  line: line,
                  x: x,
                  wrapped: marker && i < set.length - 1,
                  continues: i > 0,
                ),
            ];
          }(),
      ]);

  @override
  int lineCount(double width) => _linesAt(width).length;

  @override
  int linesThatFit(double width, double available) {
    var top = 0.0;
    var count = 0;
    for (final (:line, x: _, wrapped: _, continues: _) in _linesAt(width)) {
      if (top + line.baseline - line.descent > available + 1e-6) break;
      top += line.height;
      count++;
    }
    return count;
  }

  @override
  CustomPlacement placeLines(double width, int count) {
    final all = _linesAt(width);
    final placed = all.sublist(0, count);
    final anchors = <(String, double, double)>[];
    final lines = <PieceLine>[];
    var y = 0.0;
    for (final (:line, :x, wrapped: _, :continues) in placed) {
      for (final fragment in line.fragments) {
        if (fragment case TextFragment(:final run, :final style)
            when run.anchor != null) {
          anchors.add((
            run.anchor!,
            x + fragment.x,
            y +
                line.baseline -
                (run.anchorOnBaseline
                    ? 0
                    : style.font.ascender * style.size / 1000),
          ));
        }
      }
      final start = x + (line.fragments.firstOrNull?.x ?? 0);
      lines.add(
        PieceLine(
          y + line.baseline,
          left: start,
          right: start + line.width,
          continues: continues,
        ),
      );
      y += line.height;
    }
    // (A piece the region ends after: down to its last line's text, the
    // space under it going at the break.)
    if (count < all.length) {
      final last = placed.last.line;
      y -= math.max(0, last.height - last.baseline + last.descent);
    }
    return CustomPlacement(
      height: y,
      rest: count < all.length
          ? _EngineCode._rest(this, all.sublist(count))
          : null,
      anchors: anchors,
      lines: lines,
      paint: (page, left, top) {
        var at = top;
        for (final (:line, :x, :wrapped, continues: _) in placed) {
          line.paint(page.canvas, left + x, at, link: page.link);
          if (wrapped) _arrow(page.canvas, line, left + width, at);
          at -= line.height;
        }
      },
    );
  }

  /// The arrow after a line that wraps, at [right], the line's top at
  /// [top] (as the text box draws it).
  static void _arrow(Canvas canvas, Line line, double right, double top) {
    final last = line.fragments.whereType<TextFragment>().lastOrNull;
    if (last == null) return;
    final size = last.style.size;
    final baseline = top - line.baseline;
    final left = right + size * 0.2;
    final bend = baseline + size * 0.2;
    canvas
      ..save()
      ..setStrokeColor(last.run.color ?? const Color.gray(0))
      ..setLineWidth(size * 0.06)
      ..setLineCap(LineCap.round)
      ..setLineJoin(LineJoin.round)
      ..moveTo(left + size * 0.55, baseline + size * 0.6)
      ..lineTo(left + size * 0.55, bend)
      ..lineTo(left + size * 0.05, bend)
      ..moveTo(left + size * 0.25, bend + size * 0.2)
      ..lineTo(left + size * 0.05, bend)
      ..lineTo(left + size * 0.25, bend - size * 0.2)
      ..stroke()
      ..restore();
  }

  @override
  CustomPlacement? place(
    double width,
    double available, {
    required bool atTop,
  }) {
    final all = _linesAt(width);
    if (all.isEmpty) {
      return CustomPlacement(height: 0, paint: (page, x, top) {});
    }
    var count = linesThatFit(width, available);
    if (count < all.length && count > 0) {
      if (count < orphans) count = 0;
      if (all.length - count < widows) {
        count = math.max(0, all.length - widows);
        if (count < orphans) count = 0;
      }
    }
    if (count == 0) {
      if (!atTop) return null;
      count = 1;
    }
    return placeLines(width, count);
  }

  /// The room it needs where it starts: its first [orphans] lines, or all
  /// of it when it's too short to split (as the text box reserves).
  @override
  double minHeight(double width) {
    final lines = _linesAt(width);
    if (lines.isEmpty) return 0;
    final least = math.max(1, orphans);
    final unsplit = math.max(least, least + widows - 1);
    final count = lines.length <= unsplit ? lines.length : least;
    // (Down to the last line's text: the space under it goes at a break.)
    final last = lines[count - 1].line;
    final below = math.max(0, last.height - last.baseline + last.descent);
    return lines.take(count).fold<double>(0, (sum, l) => sum + l.line.height) -
        below;
  }

  @override
  double? firstBaseline(double width) =>
      _linesAt(width).firstOrNull?.line.baseline;

  @override
  (double, double) intrinsicWidths() {
    // (Each line's right end: its last fragment's, a first line's from
    // as far out as its indent.)
    var widest = 0.0;
    for (final (:line, :x, wrapped: _, continues: _) in _linesAt(1000000)) {
      for (final fragment in line.fragments) {
        widest = math.max(widest, x + fragment.x + fragment.width);
      }
    }
    return (widest, widest);
  }
}

/// A paragraph the engine sets that depends on the width it's set in (an
/// inline image a share of it): made at each width, by [at].
final class _EngineAtWidth
    implements LinedContent, BaselineContent, ShapedContent {
  new(this.at);

  final ParagraphContent? Function(double width) at;
  final Map<double, ParagraphContent?> _made = {};

  ParagraphContent? _of(double width) => _made[width] ??= at(width);

  @override
  int get orphans =>
      _made.values.whereType<ParagraphContent>().firstOrNull?.orphans ?? 2;

  @override
  int get widows =>
      _made.values.whereType<ParagraphContent>().firstOrNull?.widows ?? 2;

  @override
  int lineCount(double width) => _of(width)?.lineCount(width) ?? 0;

  @override
  int linesThatFit(double width, double available) =>
      _of(width)?.linesThatFit(width, available) ?? 0;

  @override
  CustomPlacement placeLines(double width, int count) =>
      _of(width)!.placeLines(width, count);

  @override
  CustomPlacement? place(
    double width,
    double available, {
    required bool atTop,
  }) => _of(width)?.place(width, available, atTop: atTop);

  @override
  CustomPlacement? placeAround(
    double width,
    double available, {
    required bool atTop,
    required (double, double) Function(double top, double bottom) insets,
  }) => _of(width)?.placeAround(width, available, atTop: atTop, insets: insets);

  @override
  double minHeight(double width) => _of(width)?.minHeight(width) ?? 0;

  @override
  double? firstBaseline(double width) => _of(width)?.firstBaseline(width);

  @override
  (double, double) intrinsicWidths() =>
      _of(1000000)?.intrinsicWidths() ?? (0, 0);
}
