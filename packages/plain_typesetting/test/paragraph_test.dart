// Paragraphs, independent of any backend: inline content broken into
// lines by first fit and Knuth-Plass, at UAX #14 opportunities and a
// hyphenator's points, aligned, and painted on a recording canvas with
// their links and anchors.
import 'dart:io';

import 'package:plain_fonts/plain_fonts.dart';
import 'package:plain_typesetting/plain_typesetting.dart';
import 'package:test/test.dart';

import 'support/recording.dart';

final OpenTypeShaper _serif = OpenTypeShaper(
  OpenTypeFont.parse(
    File('test/fonts/notoserif-regular-latin.ttf').readAsBytesSync(),
  ),
);
final TextStyle _body = TextStyle(_serif, 10);

const String _lorem =
    'Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do '
    'eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim '
    'ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut '
    'aliquip ex ea commodo consequat.';

List<Line> _lines(
  List<InlineContent> content, {
  double width = 150,
  LineBreaker breaker = const FirstFitLineBreaker(),
  TextAlign align = TextAlign.left,
  Hyphenator? hyphenator,
}) => breaker.breakLines(
  Paragraph(content, align: align, hyphenator: hyphenator),
  (_) => width,
);

String _text(Line line) => [
  for (final fragment in line.fragments)
    if (fragment is TextFragment) fragment.text,
].join();

/// Hyphenates every word after its third letter.
final class _AfterThree implements Hyphenator {
  const new();

  @override
  List<int> hyphenate(String word) => [if (word.length > 5) 3];
}

void main() {
  test('first fit fills each line, and keeps the words in order', () {
    final lines = _lines([TextRun(_lorem, _body)]);
    expect(lines.length, greaterThan(2));
    for (final line in lines) {
      expect(line.width, lessThanOrEqualTo(150 + 1e-6));
    }
    expect(lines.map(_text).join(' ').split(RegExp(r'\s+')), _lorem.split(' '));
    // Each line but the last couldn't take the next word.
    for (var i = 0; i + 1 < lines.length; i++) {
      final next = _text(lines[i + 1]).trim().split(' ').first;
      expect(lines[i].width + _body.measure(' $next'), greaterThan(150 - 1e-6));
    }
  });

  test('Knuth-Plass evens out the lines first fit leaves ragged', () {
    double raggedness(List<Line> lines) => [
      for (final line in lines.take(lines.length - 1))
        (150 - line.width) * (150 - line.width),
    ].fold(0, (a, b) => a + b);
    final firstFit = _lines([TextRun(_lorem, _body)]);
    final knuthPlass = _lines([
      TextRun(_lorem, _body),
    ], breaker: const KnuthPlassLineBreaker());
    expect(
      raggedness(knuthPlass),
      lessThanOrEqualTo(raggedness(firstFit) + 1e-6),
    );
  });

  test('font expansion: letters a little wider or narrower, lines full', () {
    final lines = _lines(
      [TextRun(_lorem, _body)],
      breaker: const KnuthPlassLineBreaker(expansion: 0.02),
      align: TextAlign.justify,
    );
    final scales = [
      for (final line in lines.take(lines.length - 1))
        for (final fragment in line.fragments)
          if (fragment is TextFragment) fragment.style.horizontalScaling,
    ];
    // Every line but the last fills the measure; its letters within 2%.
    for (final line in lines.take(lines.length - 1)) {
      expect(line.width, closeTo(150, 1e-6));
    }
    expect(scales.every((s) => s >= 98 - 1e-9 && s <= 102 + 1e-9), isTrue);
    expect(scales.any((s) => (s - 100).abs() > 0.01), isTrue);
    // Without it, letters as they are.
    final plain = _lines(
      [TextRun(_lorem, _body)],
      breaker: const KnuthPlassLineBreaker(),
      align: TextAlign.justify,
    );
    expect(
      plain
          .expand((l) => l.fragments)
          .whereType<TextFragment>()
          .every((f) => f.style.horizontalScaling == 100),
      isTrue,
    );
  });

  test('alignment: right and center move the line, justify fills it', () {
    final left = _lines([TextRun(_lorem, _body)]).first;
    final right = _lines([
      TextRun(_lorem, _body),
    ], align: TextAlign.right).first;
    final center = _lines([
      TextRun(_lorem, _body),
    ], align: TextAlign.center).first;
    expect(right.fragments.first.x, closeTo(150 - left.width, 1e-6));
    expect(center.fragments.first.x, closeTo((150 - left.width) / 2, 1e-6));
    final justified = _lines([
      TextRun(_lorem, _body),
    ], align: TextAlign.justify).first;
    final last = justified.fragments.last;
    expect(last.x + last.width, closeTo(150, 1e-6));
  });

  test("a word's pieces measured within it: its ligatures counted", () {
    // "official" broken after "off" (its "ffi" a ligature when whole):
    // the pieces add up to the word as drawn whole, the ligature's width
    // counted with the piece after the break.
    final ligated = TextStyle(
      OpenTypeShaper(
        OpenTypeFont.parse(
          File('test/fonts/notoserif-features.ttf').readAsBytesSync(),
        ),
      ),
      10,
      ligatures: true,
    );
    final items = paragraphItems(
      Paragraph([
        TextRun('official', ligated),
      ], hyphenator: const _AfterThree()),
    );
    final pieces = [
      for (final item in items)
        if (item case BoxItem(:final text, :final width)) (text, width),
    ];
    expect([for (final (text, _) in pieces) text], ['off', 'icial']);
    expect(pieces.first.$2, closeTo(ligated.measure('off'), 1e-9));
    expect(
      pieces.first.$2 + pieces.last.$2,
      closeTo(ligated.measure('official'), 1e-9),
    );
    expect(
      ligated.measure('off') + ligated.measure('icial'),
      isNot(closeTo(ligated.measure('official'), 1e-3)),
    );
  });

  test("a justified paragraph's last line wider than its measure shrinks", () {
    // One line, a point wider than its measure (as a breaker may set a
    // last line, its spaces shrunk): set to the measure, not past it.
    final run = TextRun('aaa bbb ccc ddd', _body);
    final paragraph = Paragraph([run], align: TextAlign.justify);
    final items = paragraphItems(paragraph);
    final width = _body.measure('aaa bbb ccc ddd') - 1;
    final lines = buildLines(paragraph, items, [
      items.length - 1,
    ], (_) => width);
    final last = lines.single.fragments.last;
    expect(last.x + last.width, closeTo(width, 1e-6));
  });

  test("protrusion hangs a justified line's full stop past its end", () {
    // The first line, "aaaa bbbb.", justified: its stop hangs 0.7 of its
    // width past the measure (microtype's amount), the line that much
    // wider.
    final width = _body.measure('aaaa bbbb. c');
    final line = const FirstFitLineBreaker()
        .breakLines(
          Paragraph(
            [TextRun('aaaa bbbb. cccc dddd eeee', _body)],
            align: TextAlign.justify,
            protrusion: 1,
          ),
          (_) => width,
        )
        .first;
    expect(_text(line).trim(), 'aaaa bbbb.');
    final last = line.fragments.last;
    expect(
      last.x + last.width,
      closeTo(width + 0.7 * _body.font.widthOf('.', _body.size), 1e-6),
    );
  });

  test("a hyphenator's points break words that don't fit", () {
    // "an extraordinary" doesn't fit; "an ext-" does.
    final width = _body.measure('an extra');
    final lines = _lines(
      [TextRun('an extraordinary day', _body)],
      width: width,
      hyphenator: const _AfterThree(),
    );
    expect(lines.first.hyphenated, isTrue);
    // (Its hyphen the soft hyphen, which the font has: a word divided.)
    expect(_text(lines.first), 'an ext\u00ad');
    final plain = _lines([
      TextRun('an extraordinary day', _body),
    ], width: width);
    expect(_text(plain.first).trim(), 'an');
  });

  test("a compound's hyphen repeated on the next line, by language", () {
    // "arco-da-velha" broken after "arco-": "-da-velha" in Portuguese.
    final width = _body.measure('o arco-da');
    for (final breaker in [
      const FirstFitLineBreaker(),
      const KnuthPlassLineBreaker(),
      const KnuthPlassLineBreaker(raggedStretch: 20),
    ]) {
      List<String> lines(String text, HyphenRepetition repetition) => [
        for (final line in breaker.breakLines(
          Paragraph([TextRun(text, _body)], hyphenRepetition: repetition),
          (_) => width,
        ))
          _text(line).trim(),
      ];
      expect(lines('o arco-da-velha', HyphenRepetition.none), [
        'o arco-',
        'da-velha',
      ]);
      expect(lines('o arco-da-velha', HyphenRepetition.always), [
        'o arco-',
        '-da-velha',
      ]);
      // Spanish: not before a capital.
      expect(lines('o arco-Da-velha', HyphenRepetition.beforeLowercase), [
        'o arco-',
        'Da-velha',
      ]);
      expect(lines('o arco-da-velha', HyphenRepetition.beforeLowercase), [
        'o arco-',
        '-da-velha',
      ]);
    }
    expect(HyphenRepetition.forLanguage('pt-BR'), HyphenRepetition.always);
    expect(
      HyphenRepetition.forLanguage('es'),
      HyphenRepetition.beforeLowercase,
    );
    expect(HyphenRepetition.forLanguage('en'), HyphenRepetition.none);
    expect(HyphenRepetition.forLanguage(null), HyphenRepetition.none);
  });

  test('painted: glyph runs at the baseline, colors, links and anchors', () {
    final page = RecordingPage(const Rect(0, 0, 200, 100));
    final calls = page.canvas.calls;
    final links = <(Rect, LinkTarget)>[];
    final anchors = <String>[];
    final line =
        _lines([
          TextRun('See ', _body),
          TextRun(
            'this',
            _body,
            color: const Color.rgb(1, 0, 0),
            link: const LinkTarget.uri('https://example.org'),
            anchor: 'here',
            underline: true,
          ),
        ]).single..paint(
          page.canvas,
          10,
          90,
          link: (rect, target) => links.add((rect, target)),
          anchor: (name, x, y) => anchors.add(name),
        );
    expect(page.texts, ['See ', 'this']);
    expect(calls, contains('fill color rgb 1.00 0.00 0.00'));
    // The underline: a filled rectangle.
    expect(calls.where((c) => c.startsWith('rect')), isNotEmpty);
    expect(links.single.$2, isA<UriTarget>());
    expect(links.single.$1.width, closeTo(_body.measure('this'), 1e-6));
    expect(anchors, ['here']);
    final baseline = 90 - line.baseline;
    expect(page.canvas.calls.first, 'save');
    expect(
      page.canvas.calls,
      contains(
        'glyphs "See " at 10.00 ${baseline.toStringAsFixed(2)} '
        '${_serif.name} 10.00',
      ),
    );
  });

  test("a split graphic's pieces beside one another on a line drawn as "
      'one, the line breaking between them', () {
    final painted = <int>[];
    final note = Object();
    InlineImage piece(Object group) =>
        InlineImage(_Piece(group, painted), 10, 10);
    // (Five pieces of one group, then one of another: the first line
    // holds four, 40 points wide.)
    final lines = _lines([
      for (var i = 0; i < 5; i++) piece(note),
      piece(Object()),
    ], width: 40);
    expect(lines, hasLength(2));
    for (final line in lines) {
      line.paint(RecordingCanvas(), 0, 100);
    }
    expect(painted, [4, 1, 1]);
  });

  test("an image reaching over what is beside it is set in at a line's "
      'start and end (ruby, JLREQ 3.3.9)', () {
    const image = InlineImage(
      _Blank(),
      30,
      10,
      startOverhang: 5,
      endOverhang: 4,
    );
    final ab = _body.widthOf(_body.shape('ab '));
    final [start] = _lines([image, TextRun(' ab', _body)]);
    expect((start.fragments.first as ImageFragment).x, 5);
    final [middle] = _lines([
      TextRun('ab ', _body),
      image,
      TextRun(' cd', _body),
    ]);
    expect(
      middle.fragments.whereType<ImageFragment>().single.x,
      closeTo(ab, 1e-9),
    );
    final [end] = _lines([TextRun('ab ', _body), image]);
    expect(end.width, closeTo(ab + 30 + 4, 1e-6));
  });
}

/// An image that draws nothing.
/// A piece of a split graphic: its paints, the pieces each drew.
final class _Piece implements SplitGraphic {
  new(this.group, this.painted);

  @override
  final Object group;

  final List<int> painted;

  @override
  double get intrinsicWidth => 10;

  @override
  double get intrinsicHeight => 10;

  @override
  void paint(Canvas canvas, Rect rect) => painted.add(1);

  @override
  void paintPieces(Canvas canvas, List<(SplitGraphic, Rect)> pieces) =>
      painted.add(pieces.length);
}

final class _Blank implements Graphic {
  const new();

  @override
  double get intrinsicWidth => 30;

  @override
  double get intrinsicHeight => 10;

  @override
  void paint(Canvas canvas, Rect rect) {}
}
