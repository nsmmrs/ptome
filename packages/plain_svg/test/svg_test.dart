/// SVG images drawn on canvases that only record: what reaches a plain
/// canvas and an [SvgCanvas], fonts and raster images through their
/// callbacks, and what is reported.
// (SVG written in pieces.)
// ignore_for_file: missing_whitespace_between_adjacent_strings
library;

import 'dart:typed_data';

import 'package:plain_svg/plain_svg.dart';
import 'package:plain_typesetting/plain_typesetting.dart';
import 'package:test/test.dart';

/// A font whose every character is half an em wide.
final class MonoFont implements Font {
  @override
  String get name => 'Mono';
  @override
  double get ascender => 800;
  @override
  double get descender => -200;
  @override
  double get lineGap => 0;
  @override
  double get capHeight => 700;
  @override
  double get xHeight => 500;
  @override
  double get underlinePosition => -100;
  @override
  double get underlineThickness => 50;
  @override
  bool covers(int codePoint) => true;
  @override
  List<ShapedGlyph> shape(
    String text, {
    bool kerning = true,
    bool ligatures = false,
    Set<String> features = const {},
    bool rightToLeft = false,
  }) => [
    for (final c in text.runes) ShapedGlyph(c, String.fromCharCode(c), 500),
  ];
  @override
  double widthOf(String text, double size, {bool kerning = true}) =>
      text.runes.length * size / 2;
}

/// A canvas recording each call as a line.
class RecordingCanvas implements Canvas {
  final List<String> calls = [];

  String _value(Object? value) => switch (value) {
    final double d => d.toStringAsFixed(2),
    final Rect r =>
      'Rect(${[r.left, r.bottom, r.width, r.height].map(_value).join(', ')})',
    final Matrix m =>
      'Matrix(${[m.a, m.b, m.c, m.d, m.e, m.f].map(_value).join(', ')})',
    final RgbColor c =>
      'rgb(${[c.red, c.green, c.blue].map(_value).join(', ')})',
    final GrayColor c => 'gray(${_value(c.level)})',
    final TextStyle s =>
      '${s.font.name} ${_value(s.size)} ${s.renderMode.name}',
    _ => '$value',
  };

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName.toString().split('"')[1];
    final named = {
      for (final MapEntry(:key, :value) in invocation.namedArguments.entries)
        if (value != null) key.toString().split('"')[1]: _value(value),
    };
    final arguments = [
      ...invocation.positionalArguments.map(_value),
      for (final MapEntry(:key, :value) in named.entries) '$key: $value',
    ];
    calls.add('$name(${arguments.join(', ')})');
    return name == 'text' || name == 'glyphs' ? 0.0 : null;
  }
}

/// A recording canvas that paints groups, gradients and masks.
class RecordingSvgCanvas extends RecordingCanvas implements SvgCanvas {
  @override
  void group(Rect bounds, void Function(SvgCanvas canvas) draw) {
    calls.add('group {');
    draw(this);
    calls.add('}');
  }

  @override
  void gradient(Gradient gradient) => calls.add(switch (gradient) {
    LinearGradient(:final x1, :final y1, :final x2, :final y2, :final stops) =>
      'linear($x1 $y1 $x2 $y2 ${stops.map((s) => s.offset).toList()})',
    RadialGradient(:final cx, :final cy, :final r, :final stops) =>
      'radial($cx $cy $r ${stops.length})',
  });

  @override
  void luminosityMask(Rect bounds, void Function(SvgCanvas canvas) draw) {
    calls.add('mask {');
    draw(this);
    calls.add('}');
  }
}

const String _ns = 'xmlns="http://www.w3.org/2000/svg"';

(List<String>, List<String>) drawn(
  String text, {
  Canvas? canvas,
  SvgFontResolver? fonts,
  SvgRasterReader? rasters,
  SvgImageResolver? images,
}) {
  final svg = SvgImage.parse(
    text,
    fonts: fonts,
    rasters: rasters,
    images: images,
  );
  final target = canvas ?? RecordingCanvas();
  svg.paint(target, Rect(0, 0, svg.width, svg.height));
  return ((target as RecordingCanvas).calls, svg.warnings);
}

/// A graphic recording where it is painted.
final class FakeRaster implements Graphic {
  final List<Rect> painted = [];
  @override
  double get intrinsicWidth => 4;
  @override
  double get intrinsicHeight => 2;
  @override
  void paint(Canvas canvas, Rect rect) => painted.add(rect);
}

void main() {
  test('shapes as paths, filled and stroked', () {
    final (calls, warnings) = drawn(
      '<svg $_ns width="10" height="10">'
      '<rect x="1" y="2" width="3" height="4" fill="red" stroke="blue"/></svg>',
    );
    expect(warnings, isEmpty);
    expect(
      calls,
      containsAllInOrder([
        'setFillColor(rgb(1.00, 0.00, 0.00))',
        'moveTo(1.00, 2.00)',
        'fill(evenOdd: false)',
        'setStrokeColor(rgb(0.00, 0.00, 1.00))',
        'setLineWidth(1.00)',
        'stroke()',
      ]),
    );
  });

  group('groups, gradients and masks', () {
    const opaque =
        '<g opacity="0.5"><rect width="2" height="2" '
        'fill-opacity="0.8"/></g>';
    const gradient =
        '<defs><linearGradient id="g">'
        '<stop offset="0" stop-color="red"/>'
        '<stop offset="1" stop-color="blue" stop-opacity="0.5"/>'
        '</linearGradient></defs>'
        '<rect width="4" height="4" fill="url(#g)"/>';

    test('on an SvgCanvas, as such', () {
      final (calls, warnings) = drawn(
        '<svg $_ns width="4" height="4">$opaque$gradient</svg>',
        canvas: RecordingSvgCanvas(),
      );
      expect(warnings, isEmpty);
      expect(
        calls,
        containsAllInOrder([
          'opacity(fill: 0.50, stroke: 0.50)',
          'group {',
          'opacity(fill: 0.80)',
          '}',
          'mask {',
          'linear(0.0 0.0 1.0 0.0 [0.0, 1.0])',
          '}',
          'linear(0.0 0.0 1.0 0.0 [0.0, 1.0])',
        ]),
      );
    });

    test('on another canvas, element by element and in one color', () {
      final (calls, warnings) = drawn(
        '<svg $_ns width="4" height="4">$opaque$gradient</svg>',
      );
      expect(warnings, [
        'group opacity is applied to each element',
        'gradients are drawn in their first color on this canvas',
      ]);
      expect(
        calls,
        containsAllInOrder([
          'opacity(fill: 0.40)',
          'setFillColor(rgb(1.00, 0.00, 0.00))',
        ]),
      );
      expect(calls.where((c) => c.startsWith('group')), isEmpty);
    });
  });

  group('text', () {
    const text =
        '<text x="10" y="20" font-family="Nope" '
        'text-anchor="middle">abcd</text>';

    test('in the font the resolver gives, else its sans-serif', () {
      final asked = <String>[];
      final (calls, warnings) = drawn(
        '<svg $_ns width="40" height="40">$text</svg>',
        fonts: (family, {required bold, required italic}) {
          asked.add(family);
          return family == 'sans-serif' ? MonoFont() : null;
        },
      );
      expect(asked, ['Nope', 'sans-serif']);
      expect(warnings, ['no font for Nope; using sans-serif']);
      // Anchored in the middle: 4 characters of 8 points at 16 points.
      expect(
        calls,
        contains(
          'transform(Matrix(1.00, 0.00, 0.00, -1.00, '
          '-6.00, 20.00))',
        ),
      );
      expect(calls, contains('text(abcd, 0.00, 0.00, Mono 16.00 fill)'));
    });

    test('without fonts, not drawn', () {
      final (calls, warnings) = drawn(
        '<svg $_ns width="40" height="40">$text</svg>',
      );
      expect(warnings, ['no font for Nope; the text is not drawn']);
      expect(calls.where((c) => c.startsWith('text(')), isEmpty);
    });
  });

  group('images', () {
    const png = 'data:image/png;base64,iVBORw0KGgo=';

    test('raster ones through the reader, at their size in pixels', () {
      final raster = FakeRaster();
      Uint8List? read;
      final (_, warnings) = drawn(
        '<svg $_ns width="40" height="40">'
        '<image x="1" y="2" width="8" height="2" href="$png"/></svg>',
        rasters: (bytes) {
          read = bytes;
          return raster;
        },
      );
      expect(warnings, isEmpty);
      expect(read!.take(4), [0x89, 0x50, 0x4e, 0x47]);
      // Fitted (xMidYMid meet): 4 by 2 pixels into 8 by 2, centered.
      expect(raster.painted.single.width, 4);
      expect(raster.painted.single.height, 2);
    });

    test('raster ones without a reader, or unreadable, are reported', () {
      expect(
        drawn('<svg $_ns><image width="2" height="2" href="$png"/></svg>').$2,
        ['raster image $png is not drawn: no reader for it'],
      );
      expect(
        drawn(
          '<svg $_ns><image width="2" height="2" href="$png"/></svg>',
          rasters: (_) => throw const FormatException('not a PNG'),
        ).$2,
        ['image $png could not be read: not a PNG'],
      );
    });

    test('SVG ones drawn in place, by href through the resolver', () {
      final (calls, warnings) = drawn(
        '<svg $_ns width="40" height="40">'
        '<image width="10" height="10" href="inner.svg"/></svg>',
        images: (href) => Uint8List.fromList(
          '<svg $_ns width="5" height="5"><circle r="2" fill="lime"/></svg>'
              .codeUnits,
        ),
      );
      expect(warnings, isEmpty);
      expect(calls, contains('setFillColor(rgb(0.00, 1.00, 0.00))'));
    });
  });

  test('entities the document declares are expanded', () {
    final (calls, _) = drawn(
      '<!DOCTYPE svg [<!ENTITY st0 "fill:#00FF00;">]>'
      '<svg $_ns width="4" height="4"><rect width="4" height="4" '
      'style="&st0;"/></svg>',
    );
    expect(calls, contains('setFillColor(rgb(0.00, 1.00, 0.00))'));
  });

  group('what would never end, or has nothing to start from', () {
    test('a clip path that clips itself shows nothing', () {
      final (calls, warnings) = drawn(
        '<svg $_ns width="4" height="4"><clipPath id="c" clip-path="url(#c)">'
        '<rect width="2" height="2"/></clipPath>'
        '<rect width="4" height="4" clip-path="url(#c)"/></svg>',
      );
      expect(warnings, ['clip-path url(#c) refers to itself']);
      expect(calls, contains('rect(Rect(0.00, 0.00, 0.00, 0.00))'));
    });

    test('an image that shows itself is drawn once', () {
      final (_, warnings) = drawn(
        '<svg $_ns width="4" height="4"><image width="4" height="4" '
        'href="self.svg"/></svg>',
        images: (href) => Uint8List.fromList(
          '<svg $_ns width="4" height="4"><image width="4" height="4" '
                  'href="self.svg"/></svg>'
              .codeUnits,
        ),
      );
      expect(warnings, ['image self.svg refers to itself']);
    });

    test('numbers after a close path end the path data', () {
      expect(
        SvgPath.parse('M0 0 L5 5 z 6 5').segments.map((s) => s.runtimeType),
        [MoveSegment, LineSegment, CloseSegment],
      );
    });

    test('path data must begin with a move', () {
      expect(SvgPath.parse('A 5 5 0 0 1 10 10').isEmpty, isTrue);
      final (calls, _) = drawn(
        '<svg $_ns width="4" height="4"><path d="A 5 5 0 0 1 10 10"/></svg>',
      );
      expect(calls.where((c) => c.startsWith('curveTo')), isEmpty);
    });
  });

  test('what is not an SVG document', () {
    expect(
      () => SvgImage.parse('<svg><rect></svg>'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          'not an SVG document: <rect> closed by </svg> (line 1, column 12)',
        ),
      ),
    );
    expect(
      () => SvgImage.parse('<html/>'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          'not an SVG document: the root element is not <svg>',
        ),
      ),
    );
  });
}
