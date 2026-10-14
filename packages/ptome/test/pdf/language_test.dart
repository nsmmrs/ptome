// The text's language (the document's `lang`, a block's, Ptome's inline
// `[lang=...]#...#`) choosing the fonts' language systems: Han characters
// in their Japanese, Simplified or Traditional Chinese forms.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:ptome/ptome.dart';
import 'package:test/test.dart';

/// Poppler's pdftotext.
final bool _poppler =
    Process.runSync('which', ['pdftotext']).exitCode == 0 &&
    '${Process.runSync('pdftotext', ['-v']).stderr}'.contains('Poppler');

/// qpdf, which writes a PDF's streams uncompressed.
final bool _qpdf = Process.runSync('which', ['qpdf']).exitCode == 0;

final String _cjkFont = File(
  '../plain_typesetting/test/fonts/notosanscjk-jp-subset.otf',
).absolute.path;

void main() {
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
    final qdf = Process.runSync('qpdf', [
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
  }, skip: _qpdf ? false : 'needs qpdf');

  test("a block's and a span's language", () {
    final ja = glyphs('直骨今', attributes: {'lang': 'ja'});
    final zh = glyphs('直骨今', attributes: {'lang': 'zh-Hans'});
    expect(glyphs('[lang=zh-Hans]\n直骨今', attributes: {'lang': 'ja'}), zh);
    expect(glyphs('[lang=zh-Hans]#直骨今#', attributes: {'lang': 'ja'}), zh);
    expect(glyphs('[lang=ja]#直骨今#', attributes: {'lang': 'zh-Hans'}), ja);
  }, skip: _qpdf ? false : 'needs qpdf');

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
  }, skip: _qpdf ? false : 'needs qpdf');

  test("text_transform upper-cases in the text's language", () {
    String text(String lang) {
      final theme = File('${dir.path}/upper.yml')
        ..writeAsStringSync(
          'extends: default\nheading_text_transform: uppercase\n',
        );
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
      return Process.runSync('pdftotext', [
            pdf.path,
            '-',
          ], stdoutEncoding: utf8).stdout
          as String;
    }

    expect(text('tr'), contains('İSTANBUL'));
    expect(text('en'), contains('ISTANBUL'));
  }, skip: _poppler ? false : 'needs pdftotext');
}
