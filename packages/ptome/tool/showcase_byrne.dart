// Draws the figures and the coloured symbols of the showcase's Byrne's
// Euclid (test/showcase/byrne/images): each proposition's diagram,
// redrawn from its construction after the 1847 edition's, and the
// symbols its text sets inline — lines (horizontal, as Byrne sets
// them), circles, triangles and angles (as the diagram has them).
//
//     dart run tool/showcase_byrne.dart
import 'dart:io';
import 'dart:math' as math;

const String _out = 'test/showcase/byrne/images';

/// Byrne's colours, sampled from the Getty Research Institute's copy.
const String red = '#D2402B';
const String yellow = '#E8AE2B';
const String blue = '#2B5B93';
const String black = '#1C1C1C';

extension type const P._((double, double) xy) {
  new(double x, double y) : this._((x, y));

  double get x => xy.$1;
  double get y => xy.$2;
  P operator +(P o) => P(x + o.x, y + o.y);
  P operator -(P o) => P(x - o.x, y - o.y);
  P operator *(double k) => P(x * k, y * k);
  double get length => math.sqrt(x * x + y * y);
  P get unit => this * (1 / length);
  double cross(P o) => x * o.y - y * o.x;
}

/// A shape of a figure, in the figure's units (y down).
sealed class Shape {
  const new(this.color);

  final String color;

  /// Points enough to bound it.
  Iterable<P> get bounds;

  /// Its SVG element, [map] taking its points to the image's, [stroke]
  /// the width of a line there.
  String svg(P Function(P) map, double scale, double stroke);
}

final class Line extends Shape {
  const new(this.a, this.b, super.color, {this.dotted = false});

  final P a;
  final P b;
  final bool dotted;

  @override
  Iterable<P> get bounds => [a, b];

  @override
  String svg(P Function(P) map, double scale, double stroke) {
    final (p, q) = (map(a), map(b));
    return '<line x1="${_n(p.x)}" y1="${_n(p.y)}" x2="${_n(q.x)}" '
        'y2="${_n(q.y)}" stroke="$color" stroke-width="${_n(stroke)}"'
        '${dotted ? ' stroke-dasharray="${_n(stroke)} ${_n(stroke * 0.8)}"' : ''}/>';
  }
}

final class Circle extends Shape {
  const new(this.centre, this.radius, super.color);

  final P centre;
  final double radius;

  @override
  Iterable<P> get bounds => [
    centre - P(radius, radius),
    centre + P(radius, radius),
  ];

  @override
  String svg(P Function(P) map, double scale, double stroke) {
    final c = map(centre);
    return '<circle cx="${_n(c.x)}" cy="${_n(c.y)}" r="${_n(radius * scale)}" '
        'fill="none" stroke="$color" stroke-width="${_n(stroke)}"/>';
  }
}

/// The angle at [vertex] between the lines to [from] and [to] (the
/// lesser), a sector [radius] deep: filled in its colour, or with
/// [outline] only its edge drawn.
final class Wedge extends Shape {
  const new(
    this.vertex,
    this.from,
    this.to,
    super.color, {
    this.radius = 40,
    this.outline = false,
  });

  final P vertex;
  final P from;
  final P to;
  final double radius;
  final bool outline;

  P get _start => vertex + (from - vertex).unit * radius;
  P get _end => vertex + (to - vertex).unit * radius;

  @override
  Iterable<P> get bounds sync* {
    yield vertex;
    final a = math.atan2((from - vertex).y, (from - vertex).x);
    var b = math.atan2((to - vertex).y, (to - vertex).x);
    if ((from - vertex).cross(to - vertex) >= 0) {
      if (b < a) b += 2 * math.pi;
    } else {
      if (b > a) b -= 2 * math.pi;
    }
    for (var i = 0; i <= 16; i++) {
      final t = a + (b - a) * i / 16;
      yield vertex + P(math.cos(t), math.sin(t)) * radius;
    }
  }

  @override
  String svg(P Function(P) map, double scale, double stroke) {
    final (v, s, e) = (map(vertex), map(_start), map(_end));
    final sweep = (from - vertex).cross(to - vertex) >= 0 ? 1 : 0;
    final r = _n(radius * scale);
    final paint = outline
        ? 'fill="none" stroke="$color" stroke-width="${_n(stroke * 0.6)}"'
        : 'fill="$color"';
    return '<path d="M${_n(v.x)} ${_n(v.y)}L${_n(s.x)} ${_n(s.y)}'
        'A$r $r 0 0 $sweep ${_n(e.x)} ${_n(e.y)}Z" $paint/>';
  }
}

String _n(double v) {
  final s = v.toStringAsFixed(2);
  return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
}

/// The root element of an SVG image [width] by [height] points.
String _open(double width, double height) =>
    '<svg xmlns="http://www.w3.org/2000/svg" width="${_n(width)}" '
    'height="${_n(height)}" viewBox="0 0 ${_n(width)} ${_n(height)}">';

/// [shapes] as an SVG image [height] points high (or [width] wide), its
/// lines [stroke] points wide, with [pad] points around them.
String _svg(
  List<Shape> shapes, {
  double? height,
  double? width,
  double stroke = 2.4,
  double pad = 2,
}) {
  final points = [for (final shape in shapes) ...shape.bounds];
  final minX = points.map((p) => p.x).reduce(math.min);
  final maxX = points.map((p) => p.x).reduce(math.max);
  final minY = points.map((p) => p.y).reduce(math.min);
  final maxY = points.map((p) => p.y).reduce(math.max);
  final scale = width != null
      ? (width - 2 * pad) / (maxX - minX)
      : (height! - 2 * pad) / (maxY - minY);
  final w = (maxX - minX) * scale + 2 * pad;
  final h = (maxY - minY) * scale + 2 * pad;
  P map(P p) => P((p.x - minX) * scale + pad, (p.y - minY) * scale + pad);
  return [
    _open(w, h),
    for (final shape in shapes) shape.svg(map, scale, stroke),
    '</svg>',
    '',
  ].join('\n');
}

/// A line of the text: [parts] (a colour, or a colour and `:dotted`)
/// set end to end, horizontal, as long as [length] em of 12 points.
String _strokes(List<String> parts, {double length = 2.4}) {
  const height = 7.0;
  const y = 3.4;
  const stroke = 2.2;
  final width = length * 12;
  final each = width / parts.length;
  return [
    _open(width, height),
    for (final (i, part) in parts.indexed)
      Line(
        P(i * each, y),
        P((i + 1) * each, y),
        _colors[part.split(':').first]!,
        dotted: part.endsWith(':dotted'),
      ).svg((p) => p, 1, stroke),
    '</svg>',
    '',
  ].join('\n');
}

const Map<String, String> _colors = {
  'red': red,
  'yellow': yellow,
  'blue': blue,
  'black': black,
};

/// The images: each file's name and its SVG.
final Map<String, String> _images = {};

void _line(List<String> parts, {double length = 2.4}) {
  final name = parts.map((p) => p.replaceAll(':', '')).join('-');
  _images['line-$name.svg'] = _strokes(parts, length: length);
}

void _figure(String name, List<Shape> shapes, {double width = 215}) =>
    _images['$name.svg'] = _svg(shapes, width: width, stroke: 2.6);

void _symbol(String name, List<Shape> shapes, {double height = 18}) =>
    _images['$name.svg'] = _svg(shapes, height: height * 1.25, stroke: 2);

/// The apex of the equilateral triangle on [a] and [b] nearer [near].
P _equilateral(P a, P b, P near) {
  final m = (a + b) * 0.5;
  final d = b - a;
  final h = P(-d.y, d.x) * (math.sqrt(3) / 2);
  final one = m + h;
  final two = m - h;
  return (one - near).length < (two - near).length ? one : two;
}

void _propositionI() {
  final a = P(0, 0);
  final b = P(100, 0);
  final c = _equilateral(a, b, P(50, -90));
  _figure('prop-1', [
    Circle(a, 100, blue),
    Circle(b, 100, red),
    Line(a, b, black),
    Line(a, c, yellow),
    Line(c, b, red),
  ], width: 230);
  _symbol('prop-1-circle-blue', [
    Circle(a, 100, blue),
    Line(a, b, black),
  ], height: 22);
  _symbol('prop-1-circle-red', [
    Circle(b, 100, red),
    Line(b, a, black),
  ], height: 22);
  _symbol('prop-1-triangle', [
    Line(a, c, yellow),
    Line(c, b, red),
    Line(a, b, black),
  ]);
}

void _propositionII() {
  final b = P(280, 425);
  final c = P(175, 410);
  final a = P(330, 370);
  final d = _equilateral(a, b, P(255, 355));
  final radius = (c - b).length;
  final g = b + (b - d).unit * radius;
  final big = (g - d).length;
  final l = d + (a - d).unit * big;
  _figure('prop-2', [
    Circle(d, big, red),
    Circle(b, radius, blue),
    Line(b, c, black),
    Line(a, b, black, dotted: true),
    Line(d, a, red),
    Line(d, b, red),
    Line(b, g, yellow),
    Line(a, l, blue),
  ]);
  final t1 = P(0, 0);
  final t2 = P(20, 0);
  final t3 = _equilateral(t1, t2, P(10, -20));
  _symbol('prop-2-triangle', [
    Line(t1, t3, red),
    Line(t3, t2, red),
    Line(t1, t2, black, dotted: true),
  ]);
  _symbol('prop-2-circle-blue', [
    Circle(b, radius, blue),
    Line(b, c, black),
  ], height: 22);
  _symbol('prop-2-circle-red', [
    Circle(d, big, red),
    Line(d, b, red),
    Line(b, g, yellow),
  ], height: 22);
}

void _propositionIII() {
  final a = P(540, 310);
  const r = 190.0;
  final e = a + P(r, 0);
  final b = e + P(75, 0);
  final f = a + (P(670, 175) - a).unit * r;
  final top = P(765, 330);
  _figure('prop-3', [
    Circle(a, r, blue),
    Line(a, f, red),
    Line(a, e, black),
    Line(e, b, black, dotted: true),
    Line(top, top + P(0, r), blue),
  ], width: 195);
  _symbol('prop-3-circle', [Circle(a, r, blue), Line(a, f, red)], height: 22);
}

void _propositionIV() {
  final a = P(225, 148);
  final b = P(60, 455);
  final c = P(318, 355);
  List<Shape> triangle(P shift) {
    final (a1, b1, c1) = (a + shift, b + shift, c + shift);
    return [
      Wedge(a1, b1, c1, yellow, radius: 90),
      Wedge(b1, a1, c1, blue, radius: 75),
      Wedge(c1, a1, b1, red, radius: 70),
      Line(a1, b1, red),
      Line(a1, c1, blue),
      Line(b1, c1, black),
    ];
  }

  _figure('prop-4', [...triangle(P(0, 0)), ...triangle(P(260, 0))]);
  _symbol('prop-4-angle-yellow', [Wedge(a, b, c, yellow, radius: 90)]);
  _symbol('prop-4-angle-blue', [Wedge(b, a, c, blue, radius: 75)]);
  _symbol('prop-4-angle-red', [Wedge(c, a, b, red, radius: 70)]);
  _symbol('prop-4-triangle', [
    Line(a, b, red),
    Line(a, c, blue),
    Line(b, c, black),
  ], height: 22);
}

void _propositionV() {
  final a = P(580, 108);
  final b = P(475, 340);
  final c = P(685, 340);
  const k = (510 - 108) / (340 - 108);
  final d = a + (b - a) * k;
  final e = a + (c - a) * k;
  final wedges = {
    'a': Wedge(a, b, c, black, radius: 45),
    'b-blue': Wedge(b, a, c, blue, radius: 55),
    'b-yellow': Wedge(b, c, e, yellow, radius: 55),
    'c-blue': Wedge(c, a, b, blue, radius: 55),
    'c-yellow': Wedge(c, b, d, yellow, radius: 55),
    'd': Wedge(d, a, c, red, radius: 65),
    'e': Wedge(e, a, b, red, radius: 65),
  };
  _figure('prop-5', [
    ...wedges.values,
    Line(a, b, red),
    Line(a, c, red),
    Line(b, d, yellow),
    Line(c, e, yellow),
    Line(b, c, black),
    Line(b, e, blue),
    Line(c, d, blue),
  ], width: 195);
  _symbol('prop-5-triangle', [
    Line(a, b, red),
    Line(a, c, red),
    Line(b, c, black),
  ]);
  _symbol('prop-5-triangle-adc', [
    wedges['a']!,
    Line(a, b, red),
    Line(b, d, yellow),
    Line(a, c, red),
    Line(d, c, blue),
  ], height: 34);
  _symbol('prop-5-triangle-aeb', [
    wedges['a']!,
    Line(a, b, red),
    Line(a, c, red),
    Line(c, e, yellow),
    Line(e, b, blue),
  ], height: 34);
  _symbol('prop-5-triangle-bdc', [
    Line(b, d, yellow),
    Line(d, c, blue),
    Line(b, c, black),
  ], height: 20);
  _symbol('prop-5-triangle-ceb', [
    Line(c, e, yellow),
    Line(e, b, blue),
    Line(c, b, black),
  ], height: 20);
  for (final name in ['a', 'b-blue', 'c-blue', 'b-yellow', 'c-yellow']) {
    _symbol('prop-5-angle-$name', [wedges[name]!], height: 14);
  }
  _symbol('prop-5-angle-d', [wedges['d']!]);
  _symbol('prop-5-angle-e', [wedges['e']!]);
  _symbol('prop-5-angle-b', [wedges['b-blue']!, wedges['b-yellow']!]);
  _symbol('prop-5-angle-c', [wedges['c-blue']!, wedges['c-yellow']!]);
  _symbol('prop-5-angle-b-external', [
    wedges['b-yellow']!,
    Wedge(b, e, d, black, radius: 55, outline: true),
  ]);
  _symbol('prop-5-angle-c-external', [
    wedges['c-yellow']!,
    Wedge(c, d, e, black, radius: 55, outline: true),
  ]);
}

void main() {
  for (final parts in [
    ['black'],
    ['red'],
    ['yellow'],
    ['blue'],
    ['black:dotted'],
    ['red', 'blue'],
    ['yellow', 'red'],
    ['red', 'yellow'],
    ['black', 'black:dotted'],
  ]) {
    _line(parts, length: parts.length == 1 ? 2.4 : 3.4);
  }
  // (The sign of equality, long, as Byrne's is.)
  _images['equals.svg'] = [
    _open(15, 8),
    for (final y in [2.6, 6.0])
      Line(P(1, y), P(14, y), black).svg((p) => p, 1, 1.2),
    '</svg>',
    '',
  ].join('\n');
  // (The sign for therefore, three dots, which the text's face lacks.)
  _images['therefore.svg'] = [
    _open(9, 8),
    for (final (x, y) in [(1.6, 6.6), (4.5, 2.4), (7.4, 6.6)])
      '<circle cx="${_n(x)}" cy="${_n(y)}" r="1.1" fill="$black"/>',
    '</svg>',
    '',
  ].join('\n');
  _propositionI();
  _propositionII();
  _propositionIII();
  _propositionIV();
  _propositionV();
  Directory(_out).createSync(recursive: true);
  for (final MapEntry(:key, :value) in _images.entries) {
    File('$_out/$key').writeAsStringSync(value);
  }
  stdout.writeln('${_images.length} images in $_out');
}
