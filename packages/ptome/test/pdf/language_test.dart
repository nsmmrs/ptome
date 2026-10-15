// The text's language (the document's `lang`, a block's, Ptome's inline
// `[lang=...]#...#`) choosing the fonts' language systems: Han characters
// in their Japanese, Simplified or Traditional Chinese forms.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:ptome/ptome.dart';
import 'package:test/test.dart';

import '../support/oracles.dart';
import '../support/pdf_tools.dart';

/// qpdf, which writes a PDF's streams uncompressed.

final String _cjkFont = File(
  '../plain_typesetting/test/fonts/notosanscjk-jp-subset.otf',
).absolute.path;

/// The tools' runs, recorded (test/oracles/pdf_language.json.gz,
/// test/support/oracles.dart; ORACLES=record asks them again).
late final Oracle _recorded;

void main() {
  _recorded = Oracle('pdf_language', compressed: true);
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('language_test.'));
  tearDown(() => dir.deleteSync(recursive: true));

  /// The glyph codes the text of [source] is shown with (each `TJ`'s hex
  /// strings, in order).
  List<String> glyphs(String source, {Map<String, String>? attributes}) {
    final theme = File('${dir.path}/theme.yml')
      ..writeAsStringSync('''
extends: default
font:
  catalog:
    merge: true
    JP:
      normal: $_cjkFont
      bold: $_cjkFont
      italic: $_cjkFont
      bold_italic: $_cjkFont
base:
  font_family: JP
''');
    final pdf = File('${dir.path}/out.pdf')
      ..writeAsBytesSync(
        asciidoc.convertToBytes(
          source,
          backend: Backend.pdf,
          attributes: {
            'pdf-theme': theme.path,
            'reproducible': '',
            'nofooter': '',
            ...?attributes,
          },
        ),
      );
    final qdf = recordedRunSync(_recorded, 'qpdf', [
      '--qdf',
      '--object-streams=disable',
      pdf.path,
      '-',
    ], stdoutEncoding: latin1);
    return [
      for (final m in RegExp(
        r'\[<([0-9a-fA-F]+)>\] TJ',
      ).allMatches('${qdf.stdout}'))
        m[1]!,
    ];
  }

  test("the document's language", () {
    final ja = glyphs('直骨今', attributes: {'lang': 'ja'});
    final zh = glyphs('直骨今', attributes: {'lang': 'zh-Hans'});
    expect(ja, isNotEmpty);
    expect(zh, isNot(ja));
  });

  test("a block's and a span's language", () {
    final ja = glyphs('直骨今', attributes: {'lang': 'ja'});
    final zh = glyphs('直骨今', attributes: {'lang': 'zh-Hans'});
    expect(glyphs('[lang=zh-Hans]\n直骨今', attributes: {'lang': 'ja'}), zh);
    expect(glyphs('[lang=zh-Hans]#直骨今#', attributes: {'lang': 'ja'}), zh);
    expect(glyphs('[lang=ja]#直骨今#', attributes: {'lang': 'zh-Hans'}), ja);
  });

  test('under asciidoctor-compat the language is not applied', () {
    final ja = glyphs(
      '直骨今',
      attributes: {'lang': 'ja', 'asciidoctor-compat': ''},
    );
    final zh = glyphs(
      '直骨今',
      attributes: {'lang': 'zh-Hans', 'asciidoctor-compat': ''},
    );
    expect(zh, ja);
  });

  test("text_transform upper-cases in the text's language", () {
    String text(String lang) {
      // (A font with `İ`: without the default theme's, a built-in PDF
      // font has none.)
      final font = File(
        'vendor/asciidoctor-epub3/fonts/mplus1p-regular-latin-ext.ttf',
      ).absolute.path;
      final theme = File('${dir.path}/upper.yml')
        ..writeAsStringSync('''
extends: default
font:
  catalog:
    merge: true
    Latin:
      normal: $font
      bold: $font
      italic: $font
      bold_italic: $font
base:
  font_family: Latin
heading_font_family: Latin
heading_text_transform: uppercase
''');
      final pdf = File('${dir.path}/upper.pdf')
        ..writeAsBytesSync(
          asciidoc.convertToBytes(
            '== istanbul\n\nmetin',
            backend: Backend.pdf,
            attributes: {
              'pdf-theme': theme.path,
              'lang': lang,
              'reproducible': '',
            },
          ),
        );
      return recordedRunSync(_recorded, 'pdftotext', [
            pdf.path,
            '-',
          ], stdoutEncoding: utf8).stdout
          as String;
    }

    expect(text('tr'), contains('İSTANBUL'));
    expect(text('en'), contains('ISTANBUL'));
  });

  test('Korean wraps at spaces, by default and by base_word_break', () {
    final hangul = File(
      '../plain_typesetting/test/fonts/notosanscjk-hangul-subset.otf',
    ).absolute.path;
    List<String> lines(String lang, {String wordBreak = ''}) {
      final theme = File('${dir.path}/ko.yml')
        ..writeAsStringSync('''
extends: default
font:
  catalog:
    merge: true
    KO:
      normal: $hangul
      bold: $hangul
      italic: $hangul
      bold_italic: $hangul
base:
  font_family: KO
$wordBreak
''');
      final pdf = File('${dir.path}/ko.pdf')
        ..writeAsBytesSync(
          asciidoc.convertToBytes(
            '한국어 한글 훈민정음 ' * 40,
            backend: Backend.pdf,
            attributes: {
              'pdf-theme': theme.path,
              'lang': lang,
              'reproducible': '',
              'nofooter': '',
            },
          ),
        );
      return [
        for (final line
            in (recordedRunSync(_recorded, 'pdftotext', [
                      pdf.path,
                      '-',
                    ], stdoutEncoding: utf8).stdout
                    as String)
                .split('\n'))
          if (line.trim().isNotEmpty) line.trim(),
      ];
    }

    bool wordsWhole(List<String> lines) => lines.every(
      (line) => line
          .split(' ')
          .every((word) => const {'한국어', '한글', '훈민정음'}.contains(word)),
    );
    expect(wordsWhole(lines('ko')), isTrue);
    expect(wordsWhole(lines('en')), isFalse);
    expect(
      wordsWhole(lines('ko', wordBreak: 'base_word_break: normal')),
      isFalse,
    );
    expect(
      wordsWhole(lines('en', wordBreak: 'base_word_break: keep-all')),
      isTrue,
    );
  });

  test("typographic quotes in the text's language's marks", () {
    final font = File(
      'vendor/asciidoctor-epub3/fonts/mplus1p-regular-latin-ext.ttf',
    ).absolute.path;
    final theme = File('${dir.path}/quotes.yml')
      ..writeAsStringSync('''
extends: default
font:
  catalog:
    merge: true
    Latin:
      normal: $font
      bold: $font
      italic: $font
      bold_italic: $font
base:
  font_family: Latin
''');
    String text(Map<String, String> attributes) {
      final pdf = File('${dir.path}/quotes.pdf')
        ..writeAsBytesSync(
          asciidoc.convertToBytes(
            '"`Hallo`" und \'`Welt`\'.',
            backend: Backend.pdf,
            attributes: {
              'pdf-theme': theme.path,
              'reproducible': '',
              ...attributes,
            },
          ),
        );
      return recordedRunSync(_recorded, 'pdftotext', [
            pdf.path,
            '-',
          ], stdoutEncoding: utf8).stdout
          as String;
    }

    expect(text({'lang': 'de'}), contains('„Hallo“ und ‚Welt‘.'));
    expect(
      text({'lang': 'de', 'asciidoctor-compat': ''}),
      contains('“Hallo” und ‘Welt’.'),
    );
  });
}
