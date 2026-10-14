// Hyphenation in the scripts that shape: each place the patterns of a
// language hyphenate its sample words leaves two halves that shape on
// their own, no cluster broken (the half after the break starting with no
// mark, joiner or vowel sign, no dotted circle where the word had none).
import 'dart:io';

import 'package:plain_fonts/plain_fonts.dart';
import 'package:plain_hyphenation/plain_hyphenation.dart';
import 'package:plain_typesetting/plain_typesetting.dart';
import 'package:plain_unicode/plain_unicode.dart';
import 'package:test/test.dart';

const String _fixtures = 'test/fixtures/scripts';

/// Each language with patterns for a script that shapes: its sample text
/// and a font for it.
const List<(String, String, String)> _languages = [
  ('hi', 'devanagari.txt', 'notosansdevanagari-subset.ttf'),
  ('mr', 'devanagari.txt', 'notosansdevanagari-subset.ttf'),
  ('sa', 'devanagari.txt', 'notosansdevanagari-subset.ttf'),
  ('bn', 'bengali.txt', 'notosansbengali-subset.ttf'),
  ('as', 'bengali.txt', 'notosansbengali-subset.ttf'),
  ('pa', 'gurmukhi.txt', 'notosansgurmukhi-subset.ttf'),
  ('gu', 'gujarati.txt', 'notosansgujarati-subset.ttf'),
  ('or', 'oriya.txt', 'notosansoriya-subset.ttf'),
  ('ta', 'tamil.txt', 'notosanstamil-subset.ttf'),
  ('te', 'telugu.txt', 'notosanstelugu-subset.ttf'),
  ('kn', 'kannada.txt', 'notosanskannada-subset.ttf'),
  ('ml', 'malayalam.txt', 'notosansmalayalam-subset.ttf'),
  ('cop', 'coptic.txt', 'notosanscoptic-subset.ttf'),
  ('ka', 'georgian.txt', 'notosansgeorgian-subset.ttf'),
  ('mul-ethi', 'ethiopic.txt', 'notosansethiopic-subset.ttf'),
  ('th', 'thai.txt', 'notosansthai-subset.ttf'),
  ('grc', 'greek.txt', 'notoserif-scripts.ttf'),
  ('el-polyton', 'greek.txt', 'notoserif-scripts.ttf'),
];

/// The words of [file]: its lines' runs of letters and marks.
List<String> _words(String file) => [
  for (final line in File('$_fixtures/$file').readAsLinesSync())
    if (!line.startsWith('#'))
      for (final word in line.split(RegExp(r'[\s\p{P}\d]+', unicode: true)))
        if (word.runes.length >= 4) word,
];

/// A language's patterns as the paragraph's hyphenator.
final class _Patterns implements Hyphenator {
  const new(this.patterns);

  final PatternHyphenator patterns;

  @override
  List<int> hyphenate(String word) => patterns.hyphenate(word);
}

void main() {
  for (final (language, file, fontFile) in _languages) {
    test('$language: hyphenated words shape in two halves', () {
      final hyphenator = hyphenatorFor(language);
      expect(hyphenator, isNotNull, reason: 'patterns for $language');
      final font = OpenTypeShaper(
        OpenTypeFont.parse(File('test/fonts/$fontFile').readAsBytesSync()),
      );
      final style = TextStyle(font, 12);
      int circles(String text) =>
          style.shape(text).where((g) => g.text.contains('◌')).length;
      var breaks = 0;
      final broken = <String>[];
      for (final word in _words(file)) {
        final runes = word.runes.toList();
        for (final at in hyphenator!.hyphenate(word)) {
          breaks++;
          final before = String.fromCharCodes(runes.take(at));
          final after = String.fromCharCodes(runes.skip(at));
          final first = runes[at];
          final last = runes[at - 1];
          final bad =
              isMark(first) ||
              first == 0x200c ||
              first == 0x200d ||
              last == 0x200d ||
              // (A conjunct divided; Tamil's pulli is written, no
              // conjunct, and breaks after it.)
              (indicSyllabicCategory(last) == IndicSyllabicCategory.virama &&
                  scriptOf(last) != 'Taml') ||
              circles(before) + circles(after) > circles(word);
          if (bad) broken.add('$before-$after');
        }
      }
      expect(broken, isEmpty, reason: '$breaks breaks');
      printOnFailure('$language: $breaks breaks');
    });
  }

  test("a fully shaped line's hyphen is drawn (BUG-0rtx6p)", () {
    final font = OpenTypeShaper(
      OpenTypeFont.parse(
        File('test/fonts/notosansdevanagari-subset.ttf').readAsBytesSync(),
      ),
    );
    final style = TextStyle(font, 12);
    const word = 'कुरुक्षेत्रे';
    final lines = const FirstFitLineBreaker().breakLines(
      Paragraph([
        TextRun('$word $word', style),
      ], hyphenator: _Patterns(hyphenatorFor('hi')!)),
      (_) => style.measure('$word कुरु-') + 1,
    );
    final first = lines.first.fragments.whereType<TextFragment>().single;
    expect(first.text, endsWith('\u00ad'));
    final hyphen = first.glyphs.last;
    // (The font's hyphen, read as the soft hyphen that rejoins the word.)
    expect(hyphen.text, '\u00ad');
    expect(hyphen.id, style.shape('-').single.id);
    expect(hyphen.advance, greaterThan(0));
  });
}
