// ParagraphContent: a paragraph as custom content (lines broken once per
// width, a rest broken again where it goes on, orphans and widows, the
// room it needs to start), and the run features it was made for: slots,
// artifacts, decoration outsets, break opportunities at spaces only.
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

String _text(Line line) => [
  for (final fragment in line.fragments)
    if (fragment is TextFragment) fragment.text,
].join().trim();

ParagraphContent _content(
  String text, {
  int orphans = 2,
  int widows = 2,
  double slant = 0,
  LineBreaker breaker = const FirstFitLineBreaker(),
  LineHeight lineHeight = const FontLineHeight(),
}) => ParagraphContent(
  Paragraph([TextRun(text, _body)], lineHeight: lineHeight),
  lineBreaker: breaker,
  orphans: orphans,
  widows: widows,
  slant: slant,
);

final String _words = [for (var i = 1; i <= 30; i++) 'word$i'].join(' ');

List<String> _drawn(RecordingPage page) => page.texts;

void main() {
  group('ParagraphContent', () {
    test('sets the lines its breaker breaks, once per width', () {
      final content = _content(_words);
      final lines = content.linesAt(100);
      final expected = const FirstFitLineBreaker().breakLines(
        content.paragraph,
        (_) => 100,
      );
      expect(lines.map(_text), expected.map(_text));
      expect(identical(content.linesAt(100), lines), isTrue);
      expect(content.lineCount(100), lines.length);
      expect(content.firstBaseline(100), lines.first.baseline);
    });

    test('an empty paragraph is one empty line', () {
      final content = _content('');
      expect(content.lineCount(100), 1);
      final placement = content.place(100, 100, atTop: true)!;
      expect(placement.height, greaterThan(0));
      expect(placement.rest, isNull);
    });

    test('what goes on after a break is broken again at its width', () {
      final content = _content(_words);
      final first = content.linesAt(100);
      final placement = content.placeLines(100, 2);
      expect(placement.lines, hasLength(2));
      final rest = placement.rest! as ParagraphContent;
      final wider = rest.linesAt(200);
      final remaining = first.skip(2).map(_text).join(' ');
      expect(wider.map(_text).join(' '), remaining);
      expect(wider.length, lessThan(first.length - 2));
      // (A break that wasn't forced: the rest's first line goes on.)
      final next = rest.placeLines(200, 1);
      expect(next.lines.single.continues, isTrue);
    });

    test('a line after a hard break does not go on', () {
      final content = _content('one\ntwo');
      final placement = content.placeLines(100, 2);
      expect(placement.lines.map((l) => l.continues), [false, false]);
      final wrapped = _content(_words).placeLines(60, 2);
      expect(wrapped.lines.map((l) => l.continues), [false, true]);
    });

    test('keeps orphans and widows, or nothing away from the top', () {
      final content = _content(_words);
      final lines = content.linesAt(100);
      final one = lines.first.height;
      // (Room for one line: fewer than the orphans.)
      expect(content.place(100, one + 0.1, atTop: false), isNull);
      final forced = content.place(100, one + 0.1, atTop: true)!;
      expect(forced.lines, hasLength(1));
      // (Room for all but one: the widows pull a line over.)
      final most = lines
          .take(lines.length - 1)
          .fold<double>(0, (s, l) => s + l.height);
      final placement = content.place(100, most + 0.1, atTop: false)!;
      expect(placement.lines, hasLength(lines.length - 2));
    });

    test('the room it needs: its orphans, or all of a short one', () {
      final long = _content(_words);
      final lines = long.linesAt(100);
      expect(lines.length, greaterThan(3));
      final two = lines[0].height + lines[1].height;
      expect(long.minHeight(100), lessThanOrEqualTo(two));
      expect(long.minHeight(100), greaterThan(lines[0].height));
      final short = _content('word1 word2 word3');
      // (Three lines: a break would leave fewer than its orphans or widows.)
      final three = short.linesAt(60);
      expect(three, hasLength(3));
      final all = three.fold<double>(0, (s, l) => s + l.height);
      expect(short.minHeight(60), lessThanOrEqualTo(all));
      expect(
        short.minHeight(60),
        greaterThan(three[0].height + three[1].height),
      );
    });

    test(
      'a placement that breaks leaves out the space under its last line',
      () {
        final content = _content(
          _words,
          lineHeight: const FontLineHeight(leading: 4),
        );
        final lines = content.linesAt(100);
        final placement = content.placeLines(100, 2);
        expect(placement.height, lessThan(lines[0].height + lines[1].height));
        final whole = content.placeLines(100, lines.length);
        expect(whole.rest, isNull);
        expect(
          whole.height,
          closeTo(lines.fold(0.0, (s, l) => s + l.height), 1e-9),
        );
      },
    );

    test('a slant shifts each line by its height above the last', () {
      final plain = _content('one\ntwo\nthree').placeLines(100, 3);
      final slanted = _content(
        'one\ntwo\nthree',
        slant: 0.5,
      ).placeLines(100, 3);
      final lefts = [for (final line in slanted.lines) line.left];
      expect(lefts.last, closeTo(plain.lines.last.left, 1e-9));
      expect(lefts.first, greaterThan(lefts[1]));
      expect(lefts[1], greaterThan(lefts.last));
    });

    test('runs around what its insets leave, the paragraph broken whole', () {
      final content = _content(_words, breaker: const KnuthPlassLineBreaker());
      final placement = content.placeAround(
        200,
        double.infinity,
        atTop: true,
        insets: (top, bottom) => top < 20 ? (80, 0) : (0, 0),
      )!;
      final page = RecordingPage(const Rect(0, 0, 300, 300));
      placement.paint(page, 0, 290);
      final xs = [
        for (final call in page.canvas.calls)
          if (call.startsWith('glyphs'))
            double.parse(call.split(' at ')[1].split(' ')[0]),
      ];
      expect(xs.first, greaterThanOrEqualTo(80 - 1e-2));
      expect(xs.last, lessThan(80));
      expect(placement.lines.first.right, lessThanOrEqualTo(120 + 1e-6));
      expect(placement.rest, isNull);
    });

    test('its widths: the widest word, and the line unbroken', () {
      final content = _content('a widestword b');
      final (least, most) = content.intrinsicWidths();
      expect(least, closeTo(_body.widthOf(_body.shape('widestword')), 1e-6));
      expect(most, greaterThan(least));
      expect(content.linesAt(most), hasLength(1));
    });

    test('paints its lines and reports its anchors', () {
      final content = ParagraphContent(
        Paragraph([TextRun('marked text', _body, anchor: 'here')]),
      );
      final placement = content.placeLines(200, 1);
      final page = RecordingPage(const Rect(0, 0, 300, 300));
      placement.paint(page, 10, 290);
      expect(_drawn(page).join(), contains('marked'));
      expect(placement.anchors.map((a) => a.$1), ['here']);
    });
  });

  group('slots', () {
    double width(String text) => _body.widthOf(_body.shape(text));

    Line line(TextRun run) => const FirstFitLineBreaker()
        .breakLines(Paragraph([run]), (_) => 200)
        .single;

    String glyphsCall(TextRun run) {
      final page = RecordingPage(const Rect(0, 0, 300, 300));
      line(run).paint(page.canvas, 0, 100);
      return page.canvas.calls.firstWhere((c) => c.startsWith('glyphs'));
    }

    double xOf(String call) =>
        double.parse(call.split(' at ')[1].split(' ')[0]);

    test("a slot takes its width, whatever its text's", () {
      expect(
        line(TextRun('12', _body, slotWidth: 40)).width,
        closeTo(40, 1e-9),
      );
    });

    test('its text sits in it as aligned', () {
      final w = width('12');
      expect(xOf(glyphsCall(TextRun('12', _body, slotWidth: 40))), 0);
      expect(
        xOf(
          glyphsCall(
            TextRun('12', _body, slotWidth: 40, slotAlign: TextAlign.center),
          ),
        ),
        closeTo((40 - w) / 2, 1e-2),
      );
      expect(
        xOf(
          glyphsCall(
            TextRun('12', _body, slotWidth: 40, slotAlign: TextAlign.right),
          ),
        ),
        closeTo(40 - w, 1e-2),
      );
    });

    test('a slot is never broken, even wider than the line', () {
      final lines = const FirstFitLineBreaker().breakLines(
        Paragraph([TextRun('several words here', _body, slotWidth: 300)]),
        (_) => 100,
      );
      expect(lines, hasLength(1));
      expect(_text(lines.single), 'several words here');
    });

    test('a slot of spaces is fixed space, which never stretches', () {
      final lines = const KnuthPlassLineBreaker().breakLines(
        Paragraph([
          TextRun('a', _body),
          TextRun(' ', _body, slotWidth: 20),
          TextRun('b', _body),
        ], align: TextAlign.justify),
        (_) => 200,
      );
      expect(lines.single.width, closeTo(width('a') + 20 + width('b'), 1e-6));
    });
  });

  group('run marks', () {
    test('an artifact is marked content that reads as nothing', () {
      final page = RecordingPage(const Rect(0, 0, 300, 300));
      const FirstFitLineBreaker()
          .breakLines(
            Paragraph([
              TextRun('code ', _body),
              TextRun('(1)', _body, artifact: true),
            ]),
            (_) => 200,
          )
          .single
          .paint(page.canvas, 0, 100);
      final calls = page.canvas.calls;
      final begin = calls.indexOf('begin Span');
      expect(begin, isNonNegative);
      expect(calls[begin + 1], startsWith('glyphs "(1)"'));
      expect(calls[begin + 2], 'end');
    });

    test("a decoration's outset makes it taller", () {
      List<String> rects(double outset) {
        final page = RecordingPage(const Rect(0, 0, 300, 300));
        const FirstFitLineBreaker()
            .breakLines(
              Paragraph([
                TextRun(
                  'key',
                  _body,
                  decoration: InlineDecoration(
                    background: const GrayColor(0.9),
                    outset: outset,
                  ),
                ),
              ]),
              (_) => 200,
            )
            .single
            .paint(page.canvas, 0, 100);
        return page.canvas.calls
            .where((c) => c.startsWith('rect') || c.startsWith('rounded'))
            .toList();
      }

      double height(String call) => double.parse(call.split(' ').last);
      expect(
        height(rects(2).single) - height(rects(0).single),
        closeTo(4, 1e-6),
      );
    });

    test("a line's width leaves out the tracking after its last glyph", () {
      final tracked = TextStyle(_serif, 10, characterSpacing: 1);
      final line = const FirstFitLineBreaker()
          .breakLines(Paragraph([TextRun('abc', tracked)]), (_) => 200)
          .single;
      expect(
        line.width,
        closeTo(tracked.widthOf(tracked.shape('abc')) - 1, 1e-9),
      );
    });
  });

  group('break opportunities', () {
    List<String> broken(String text, BreakOpportunities opportunities) =>
        const FirstFitLineBreaker()
            .breakLines(
              Paragraph([
                TextRun(text, _body),
              ], breakOpportunities: opportunities),
              (_) => _body.widthOf(_body.shape('xx ab/')),
            )
            .map(_text)
            .toList();

    test('at spaces and hyphens only, not after a slash', () {
      expect(broken('xx ab/cd', BreakOpportunities.unicode).first, 'xx ab/');
      expect(
        broken('xx ab/cd', BreakOpportunities.spacesAndHyphens).first,
        'xx',
      );
      expect(
        broken('aa bb-cc', BreakOpportunities.spacesAndHyphens),
        isNot(contains('aa bb-cc')),
      );
    });

    test('copyWith carries them and the line height', () {
      final paragraph = Paragraph([TextRun('x', _body)]).copyWith(
        breakOpportunities: BreakOpportunities.spacesAndHyphens,
        lineHeight: const MultipleLineHeight(2),
      );
      expect(paragraph.breakOpportunities, BreakOpportunities.spacesAndHyphens);
      expect(paragraph.lineHeight, isA<MultipleLineHeight>());
    });
  });
}
