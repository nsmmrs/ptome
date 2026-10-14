// Line-breaking strictness (CSS Text 3's line-break): the PDF's
// `base_line_break` (or the document's `line-break`), HTML's and EPUB's
// CSS; nothing under asciidoctor-compat.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:plain_compression/plain_compression.dart';
import 'package:ptome/ptome.dart';
import 'package:test/test.dart';

/// Poppler's pdftotext.
final bool _poppler =
    Process.runSync('which', ['pdftotext']).exitCode == 0 &&
    '${Process.runSync('pdftotext', ['-v']).stderr}'.contains('Poppler');

/// Noto Sans CJK, subset (its kana; not あ).
final String _cjk = File(
  '../plain_typesetting/test/fonts/notosanscjk-jp-subset.otf',
).absolute.path;

void main() {
  test('HTML: CSS line-break', () {
    expect(
      asciidoc.convert(
        'あいう',
        standalone: true,
        attributes: {'line-break': 'loose'},
      ),
      contains('<style>body{line-break:loose}</style>'),
    );
    expect(
      asciidoc.convert(
        'あいう',
        standalone: true,
        attributes: {'line-break': 'loose', 'asciidoctor-compat': ''},
      ),
      isNot(contains('line-break')),
    );
    expect(
      asciidoc.convert(
        'あいう',
        standalone: true,
        attributes: {'line-break': 'bogus'},
      ),
      isNot(contains('line-break:')),
    );
  });

  test('EPUB: CSS line-break in each chapter', () {
    final epub = asciidoc.convertToBytes(
      '= 本\n:lang: ja\n:line-break: anywhere\n\n== 章\n\nあいう\n',
      backend: Backend.epub3,
    );
    final chapters = [
      for (final entry in readZip(epub))
        if (entry.name.endsWith('.xhtml'))
          utf8.decode(entry.bytes, allowMalformed: true),
    ].join();
    expect(chapters, contains('body { line-break: anywhere; }'));
  });

  test('PDF: base_line_break: loose lets a line start with small kana', () {
    final dir = Directory.systemTemp.createTempSync('line_break.');
    addTearDown(() => dir.deleteSync(recursive: true));
    List<String> lines(String extra, {Map<String, String>? attributes}) {
      final theme = File('${dir.path}/theme.yml')
        ..writeAsStringSync('''
extends: default
page:
  size: [100, 400]
  margin: [10, 10, 10, 10]
base:
  font_family: JP
  font_size: 20
  text_align: left
font:
  catalog:
    merge: true
    JP:
      normal: $_cjk
      bold: $_cjk
      italic: $_cjk
      bold_italic: $_cjk
$extra''');
      final path = '${dir.path}/out.pdf';
      File(path).writeAsBytesSync(
        asciidoc.convertToBytes(
          'いのかきっくのは',
          backend: Backend.pdf,
          attributes: {
            'pdf-theme': theme.path,
            'reproducible': '',
            'lang': 'ja',
            'nofooter': '',
            ...?attributes,
          },
        ),
      );
      return [
        for (final line in const LineSplitter().convert(
          Process.runSync('pdftotext', [
                '-layout',
                path,
                '-',
              ], stdoutEncoding: utf8).stdout
              as String,
        ))
          if (line.trim().isNotEmpty) line.trim(),
      ];
    }

    expect(lines('').first, 'いのか');
    expect(lines('base_line_break: loose\n').first, 'いのかき');
    expect(lines('', attributes: {'line-break': 'loose'}).first, 'いのかき');
  }, skip: _poppler ? false : 'needs Poppler');
}
