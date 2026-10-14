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
