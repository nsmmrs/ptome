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
  TextStyle? style,
  LineStartBrackets lineStartBrackets = LineStartBrackets.solid,
  bool hangingPunctuation = false,
  LineBreakStrictness lineBreak = LineBreakStrictness.strict,
}) => const FirstFitLineBreaker().breakLines(
  Paragraph(
    [TextRun(text, style ?? _style)],
    align: align,
    alignLast: align,
    eastAsian: eastAsian,
    lineStartBrackets: lineStartBrackets,
    hangingPunctuation: hangingPunctuation,
    lineBreak: lineBreak,
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
  test('line-break: loose lets a line start with small kana, strict not '
      '(CSS Text 3)', () {
    final ja = TextStyle(_jp, 10, language: 'ja');
    // (Four characters a line: the fifth is small.)
    final strict = _lines('あいかきっくのは', 40, style: ja);
    expect(_text(strict[1]).startsWith('っ'), isFalse);
    expect(_text(strict[0]), 'あいか');
    final loose = _lines(
      'あいかきっくのは',
      40,
      style: ja,
      lineBreak: LineBreakStrictness.loose,
    );
    expect(_text(loose[0]), 'あいかき');
    expect(_text(loose[1]).startsWith('っ'), isTrue);
  });

  test('a closing mark before an opening one is set half wide', () {
    // 括 弧 」 （ 丸: four ems and the closing bracket's half.
    final [line] = _lines('括弧」（丸', 200);
    expect(_width(line), closeTo(45, 1e-6));
    final [plain] = _lines('括弧」（丸', 200, eastAsian: false);
    expect(_width(plain), closeTo(50, 1e-6));
  });

  test('the second of two opening marks is set half wide', () {
    // （ whole, 「 half, 括, 」 whole: brackets at the line's ends kept
    // full width.
    final [line] = _lines(
      '（「括」',
      200,
      lineStartBrackets: LineStartBrackets.fullWidth,
      style: TextStyle(_jp, 10, language: 'zh-Hant-HK'),
    );
    expect(_width(line), closeTo(35, 1e-6));
  });

  group("a line's ends (JIS X 4051, JLREQ 3.1.5 and 3.8.3)", () {
    test('an opening bracket starting it, and a closing bracket or comma '
        'ending it, set solid', () {
      final [line] = _lines('（「括」', 200);
      expect(_width(line), closeTo(25, 1e-6));
      final [comma] = _lines('括弧、', 200);
      expect(_width(comma), closeTo(25, 1e-6));
    });

    test('a full stop ending it keeps its half em', () {
      final [line] = _lines('括弧。', 200);
      expect(_width(line), closeTo(30, 1e-6));
    });

    test('novel style: full width where the paragraph starts, solid where '
        'a line wraps', () {
      final lines = _lines(
        '「括弧括弧括弧」「括弧括弧括弧」',
        80,
        lineStartBrackets: LineStartBrackets.novel,
      );
      expect(lines.length, greaterThan(1));
      final first = lines.first.fragments.whereType<TextFragment>().first;
      final second = lines[1].fragments.whereType<TextFragment>().first;
      expect(first.glyphs.first.advance, 1000);
      if (second.text.startsWith('「')) {
        expect(second.glyphs.first.advance, lessThan(1000));
      }
    });
  });

  group("line adjustment in JLREQ 3.8's order", () {
    /// The kerning after each glyph of [text] justified [extra] points
    /// wider than it is.
    List<double> kerning(String text, double extra) {
      final [natural] = _lines(text, 500);
      final [line] = _lines(
        text,
        _width(natural) + extra,
        align: TextAlign.justify,
      );
      return [
        for (final f in line.fragments.whereType<TextFragment>())
          for (final g in f.glyphs) g.kerning,
      ];
    }

    test('stretching: the quarter em beside Latin first, to half an em', () {
      // (や|P D F|や 括 弧: two mixed places, three between characters.)
      final k = kerning('やPDFや括弧', 2);
      expect(k.first, closeTo(250 + 100, 1e-6));
      expect(k[3], closeTo(250 + 100, 1e-6));
      // (Between the characters, nothing yet.)
      expect(k[4], closeTo(0, 1e-6));
      expect(k[5], closeTo(0, 1e-6));
    });

    test('then between the characters, once the mixed places are full', () {
      final k = kerning('やPDFや括弧', 5 + 2 * 2);
      expect(k.first, closeTo(500, 1e-6));
      expect(k[4], closeTo(200, 1e-6));
      expect(k[5], closeTo(200, 1e-6));
    });

    test("shrinking: a mark's blank half before the mixed places", () {
      final [natural] = _lines('括弧、括弧括弧', 500);
      final [line] = const KnuthPlassLineBreaker().breakLines(
        Paragraph(
          [TextRun('括弧、括弧括弧', _style)],
          align: TextAlign.justify,
          alignLast: TextAlign.justify,
        ),
        (_) => _width(natural) - 3,
      );
      final k = [
        for (final f in line.fragments.whereType<TextFragment>())
          for (final g in f.glyphs) g.kerning,
      ];
      // (After the comma, 3 points of its blank half.)
      expect(k[2], closeTo(-300, 1e-6));
    });
  });

  group('hanging punctuation (burasagari, JLREQ 2.5.1)', () {
    test('a full stop or comma that would wrap hangs past the end', () {
      // (Four characters fit; the fifth, a comma, hangs.)
      final hung = _lines('括弧括弧、括弧', 40, hangingPunctuation: true);
      expect(_text(hung.first), '括弧括弧、');
      final wrapped = _lines('括弧括弧、括弧', 40);
      expect(_text(wrapped.first), isNot('括弧括弧、'));
    });
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

  group('punctuation by region (CLREQ)', () {
    double width(String text, String language) {
      final [line] = const FirstFitLineBreaker().breakLines(
        Paragraph([TextRun(text, TextStyle(_jp, 10, language: language))]),
        (_) => 500,
      );
      return _width(line);
    }

    test('mainland and Japanese squeeze two marks in a row', () {
      expect(width('括弧」（丸', 'zh-Hans'), closeTo(45, 1e-6));
      expect(width('括弧」（丸', 'ja'), closeTo(45, 1e-6));
    });

    test('Taiwan squeezes none', () {
      expect(width('括弧」（丸', 'zh-TW'), closeTo(50, 1e-6));
      expect(width('括弧」（丸', 'zh-Hant'), closeTo(50, 1e-6));
    });

    test('Hong Kong squeezes brackets, not pauses and stops', () {
      expect(width('括弧」（丸', 'zh-HK'), closeTo(45, 1e-6));
      expect(width('括、（丸', 'zh-HK'), closeTo(40, 1e-6));
      expect(width('括、（丸', 'zh-Hans'), closeTo(35, 1e-6));
    });

    test('a mark ending a mainland line is half wide', () {
      expect(width('括弧。', 'zh-Hans'), closeTo(25, 1e-6));
      expect(width('括弧。', 'ja'), closeTo(30, 1e-6));
    });

    test('the style of a language', () {
      expect(PunctuationStyle.of('zh'), PunctuationStyle.mainland);
      expect(PunctuationStyle.of('zh-Hant-HK'), PunctuationStyle.hongKong);
      expect(PunctuationStyle.of('zh-Hant'), PunctuationStyle.taiwan);
      expect(PunctuationStyle.of('yue'), PunctuationStyle.hongKong);
      expect(PunctuationStyle.of('ko'), PunctuationStyle.japanese);
    });
  });
}
