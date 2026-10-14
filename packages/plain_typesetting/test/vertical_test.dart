// Vertical writing: text whose upright characters are shaped top to
// bottom, pages whose content is laid out in a turned frame.
import 'dart:io';

import 'package:plain_fonts/plain_fonts.dart';
import 'package:plain_typesetting/plain_typesetting.dart';
import 'package:test/test.dart';

import 'support/recording.dart';

final OpenTypeShaper _jp = OpenTypeShaper(
  OpenTypeFont.parse(
    File('test/fonts/notosanscjk-jp-subset.otf').readAsBytesSync(),
  ),
);

void main() {
  group('tate-chu-yoko (JLREQ 3.2.5)', () {
    final style = TextStyle(_jp, 10, vertical: true, combineDigits: 2);
    String kinds(List<ShapedGlyph> glyphs) => [
      for (final g in glyphs)
        if (g.upright) 'U' else 'R',
    ].join();

    test('two digits set across, upright, an em along the line', () {
      final glyphs = style.shape('11月10日');
      expect(kinds(glyphs), 'UUUUUU');
      final [one, ten] = glyphs.sublist(0, 2);
      // (Half-width forms, centred across the column.)
      final half = TextStyle(_jp, 10).shape('11');
      expect(half.length, 2);
      expect(one.advance + ten.advance, 1000);
      expect(one.advance, 0);
      final width = TextStyle(
        _jp,
        10,
        features: const {'hwid'},
      ).shape('11').fold<double>(0, (sum, g) => sum + g.advance);
      expect(width, lessThanOrEqualTo(1000));
      expect(one.xOffset, closeTo(-width / 2, 1e-9));
      expect(one.yOffset, -880);
      expect(style.widthOf(glyphs.sublist(0, 2)), 10);
    });

    test('a lone digit upright in its full-width form', () {
      final [digit] = style.shape('8');
      expect(digit.upright, isTrue);
      expect(digit.advance, 1000);
      expect(digit.xOffset, closeTo(-500, 1));
    });

    test('longer numbers, decimals and words on their side', () {
      expect(kinds(style.shape('151台')), 'RRRU');
      expect(kinds(style.shape('2.5と')), 'RRRU');
      expect(kinds(style.shape('1,000円')), 'RRRRRU');
      expect(kinds(TextStyle(_jp, 10, vertical: true).shape('10日')), 'RRU');
    });

    test('combineDigits: 3 sets three across in third-width forms, where '
        'the font has them', () {
      final three = TextStyle(_jp, 10, vertical: true, combineDigits: 3);
      final glyphs = three.shape('151台');
      final widths = TextStyle(
        _jp,
        10,
        features: const {'twid'},
      ).shape('151').fold<double>(0, (sum, g) => sum + g.advance);
      expect(kinds(glyphs), widths <= 1050 ? 'UUUU' : 'RRRU');
    });

    test('combineUpright: the whole run across (!?)', () {
      final glyphs = TextStyle(
        _jp,
        10,
        vertical: true,
        combineUpright: true,
      ).shape('!?');
      expect(kinds(glyphs), 'UU');
      expect(glyphs.fold<double>(0, (sum, g) => sum + g.advance), 1000);
    });

    test('combinesAt: no quarter em beside it', () {
      expect(style.combinesAt('年10月', 1), isTrue);
      expect(style.combinesAt('年151月', 1), isFalse);
      expect(style.combinesAt('年10月', 0), isFalse);
      expect(TextStyle(_jp, 10, combineDigits: 2).combinesAt('10', 0), isFalse);
    });
  });

  group('vertical text', () {
    final style = TextStyle(_jp, 10, vertical: true);

    test('Han and kana upright, Latin and digits on their side', () {
      final glyphs = style.shape('日本PDF語2026年');
      expect(
        [
          for (final g in glyphs)
            if (g.upright) 'U' else 'R',
        ].join(),
        'UURRRURRRRU',
      );
      // (Upright: the vertical advance, the origin's offsets.)
      final day = glyphs.first;
      expect(day.advance, 1000);
      expect((day.xOffset, day.yOffset), (-500, -880));
    });

    test('punctuation takes its vertical form', () {
      final across = TextStyle(_jp, 10).shape('。「');
      final down = style.shape('。「');
      expect(down.every((g) => g.upright), isTrue);
      expect([
        for (final g in down) g.id,
      ], isNot([for (final g in across) g.id]));
    });

    test('a line measures by the vertical advances', () {
      expect(style.measure('日本語'), closeTo(30, 1e-9));
    });
  });

  group('vertical pages', () {
    const size = Rect(0, 0, 200, 300);
    const margins = EdgeInsets.all(20);

    test('the frame is the content area turned: its width the height', () {
      const template = PageTemplate(
        size,
        margins: margins,
        writingMode: WritingMode.verticalRightToLeft,
      );
      final [region] = template.regions;
      expect((region.width, region.height), (260, 160));
      final m = template.frameToPage;
      // The frame's top-left at the content area's top-right; its first
      // line's start there, running down.
      expect(m.apply(0, 160), (180, 280));
      expect(m.apply(260, 160), (180, 20));
      expect(m.apply(0, 0), (20, 280));
    });

    test('vertical-lr: lines following to the right', () {
      const template = PageTemplate(
        size,
        margins: margins,
        writingMode: WritingMode.verticalLeftToRight,
      );
      final m = template.frameToPage;
      expect(m.apply(0, 160), (20, 280));
      expect(m.apply(0, 0), (180, 280));
    });

    test('content is painted turned; an image stands upright', () {
      final layout = FlowLayout(
        template: const PageTemplate(
          size,
          margins: margins,
          writingMode: WritingMode.verticalRightToLeft,
        ),
      );
      final result = layout.layout([ImageBox(_Square(), 60, 40)]);
      final document = RecordingDocument();
      result.render(document);
      final calls = document.pages.single.canvas.calls;
      expect(calls, contains('transform 0.00 -1.00 1.00 0.00 20.00 280.00'));
      // (The image in its own upright space, 60 by 40.)
      expect(calls, contains('rect 0.00 0.00 60.00 40.00'));
    });
  });
}

/// A graphic that records where it is painted.
final class _Square implements Graphic {
  @override
  double get intrinsicWidth => 60;

  @override
  double get intrinsicHeight => 40;

  @override
  void paint(Canvas canvas, Rect rect) => canvas.rect(rect);
}
