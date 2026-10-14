// East Asian composition (JLREQ, CLREQ): punctuation squeezed, a quarter
// em between Han or kana and Latin, justification between characters,
// and UAX #14's line-start and line-end prohibitions.
import 'dart:io';

import 'package:plain_fonts/plain_fonts.dart';
import 'package:plain_typesetting/plain_typesetting.dart';
import 'package:plain_unicode/plain_unicode.dart' show lineBreaks;
import 'package:test/test.dart';

import 'support/recording.dart';

final OpenTypeShaper _jp = OpenTypeShaper(
  OpenTypeFont.parse(
    File('test/fonts/notosanscjk-jp-subset.otf').readAsBytesSync(),
  ),
);

final TextStyle _style = TextStyle(_jp, 10);

List<Line> _lines(
  String text,
  double width, {
  TextAlign align = TextAlign.left,
  bool eastAsian = true,
}) => const FirstFitLineBreaker().breakLines(
  Paragraph(
    [TextRun(text, _style)],
    align: align,
    alignLast: align,
    eastAsian: eastAsian,
  ),
  (_) => width,
);

double _width(Line line) =>
    [for (final f in line.fragments) f.width].fold(0, (a, b) => a + b);

String _text(Line line) => [
  for (final f in line.fragments)
    if (f is TextFragment) f.text,
].join();

void main() {
  test('a closing mark before an opening one is set half wide', () {
    // 括 弧 」 （ 丸: four ems and the closing bracket's half.
    final [line] = _lines('括弧」（丸', 200);
    expect(_width(line), closeTo(45, 1e-6));
    final [plain] = _lines('括弧」（丸', 200, eastAsian: false);
    expect(_width(plain), closeTo(50, 1e-6));
  });

  test('the second of two opening marks is set half wide', () {
    final [line] = _lines('（「括」', 200);
    // （ whole, 「 half, 括, 」 whole at the end.
    expect(_width(line), closeTo(35, 1e-6));
  });

  test('a quarter em between kana and Latin, either way', () {
    final [line] = _lines('やPDFや', 200);
    expect(_width(line), closeTo(_style.measure('PDF') + 20 + 2 * 2.5, 1e-6));
  });

  test('a justified line stretches between its characters', () {
    final lines = _lines(
      '日本語の文章は単語の間に空白を入れずに書きます',
      83,
      align: TextAlign.justify,
    );
    expect(lines.length, greaterThan(1));
    for (final line in lines.take(lines.length - 1)) {
      expect(_width(line), closeTo(83, 1e-6), reason: _text(line));
    }
  });

  test('no line starts with a closing mark or small kana, nor ends with '
      'an opening mark', () {
    const text =
        '日本語の文章は、単語の間に「空白」を入れずに書きます。'
        'ちょっとキャッシュ、ラーメン！';
    // (From three and a half em: narrower, a run that may not be divided,
    // シュ、, is wider than the line and is divided anyway.)
    for (var width = 35.0; width < 120; width += 5) {
      final lines = _lines(text, width);
      for (final line in lines.skip(1)) {
        expect(
          '、。」！ょャッー'.contains(_text(line)[0]),
          isFalse,
          reason: '$width: ${lines.map(_text).join(' | ')}',
        );
      }
      for (final line in lines) {
        expect(_text(line).trimRight().endsWith('「'), isFalse);
      }
    }
  });

  test('the breaker counts the stretch between characters', () {
    final items = paragraphItems(Paragraph([TextRun('日本語の文章', _style)]));
    expect(
      items.whereType<GlueItem>().where((g) => g.stretch.isFinite),
      hasLength(5),
    );
  });

  test('a justified line of Thai stretches between its words alone', () {
    final thai = TextStyle(
      OpenTypeShaper(
        OpenTypeFont.parse(
          File('test/fonts/notosansthai-subset.ttf').readAsBytesSync(),
        ),
      ),
      10,
    );
    // ภาษา|ไทย|สวัสดี|ครับ, three times.
    final lines = const FirstFitLineBreaker().breakLines(
      Paragraph([
        TextRun('ภาษาไทยสวัสดีครับ' * 3, thai),
      ], align: TextAlign.justify),
      (_) => 120,
    );
    expect(lines.length, greaterThan(1));
    final first = lines.first;
    expect(_width(first), closeTo(120, 1e-6));
    final fragment = first.fragments.whereType<TextFragment>().single;
    // (The space after the last glyph of each word but the line's last.)
    final words = lineBreaks(fragment.text).length - 1;
    expect(fragment.glyphs.where((g) => g.kerning > 0), hasLength(words));
  });

  group('emphasis marks', () {
    Line line(String text, {String? mark, bool under = false}) =>
        const FirstFitLineBreaker()
            .breakLines(
              Paragraph([
                TextRun(text, _style, emphasisMark: mark, emphasisUnder: under),
              ]),
              (_) => 200,
            )
            .single;

    test('one over each character but punctuation, reading as nothing', () {
      final canvas = RecordingCanvas();
      line('日本語、文章', mark: '\ufe45').paint(canvas, 0, 100);
      expect(canvas.calls.where((c) => c.startsWith('ellipse')), hasLength(5));
      expect(canvas.calls, contains('begin Span'));
    });

    test('the line taller by their band, or deeper under', () {
      final plain = line('日本');
      final over = line('日本', mark: '\u2022');
      final under = line('日本', mark: '\u2022', under: true);
      expect(over.ascent - plain.ascent, closeTo(emphasisExtent(_style), 1e-6));
      expect(over.descent, plain.descent);
      expect(
        plain.descent - under.descent,
        closeTo(emphasisExtent(_style), 1e-6),
      );
    });
  });
}
