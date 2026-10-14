// Warichu (`warichu:[注]`, Ptome's syntax): an inline cutting note, in the
// PDF two lines of half the text's size within the line (JLREQ 3.4), as
// near the same length as the line's breaks allow, the second never the
// longer, between the line's parentheses; in HTML and EPUB a span, in
// DocBook and man pages the note in parentheses; text under
// asciidoctor-compat. On a vertical page it and ruby stand upright.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:plain_pdf/plain_pdf.dart';
import 'package:ptome/ptome.dart';
import 'package:ptome/src/pdf/fonts.dart';
import 'package:ptome/src/pdf/warichu.dart';
import 'package:test/test.dart';

/// Poppler's pdftotext.
final bool _poppler =
    Process.runSync('which', ['pdftotext']).exitCode == 0 &&
    '${Process.runSync('pdftotext', ['-v']).stderr}'.contains('Poppler');

final String _cjkPath = File(
  '../plain_typesetting/test/fonts/notosanscjk-jp-subset.otf',
).absolute.path;

/// Noto Sans CJK, subset: every character a full em wide.
final TrueTypeFont _face = TrueTypeFont(
  'JP',
  'normal',
  EmbeddedFont.parse(File(_cjkPath).readAsBytesSync()),
);

void main() {
  test('HTML, EPUB, DocBook and man pages', () {
    expect(
      asciidoc.convert('本文warichu:[注の文]です。'),
      contains('本文<span class="warichu">（注の文）</span>です。'),
    );
    expect(
      asciidoc.convert('本文warichu:[注の文]です。', backend: Backend.docbook5),
      contains('本文（注の文）です。'),
    );
    expect(
      asciidoc.convert(r'本文\warichu:[注]です。'),
      contains('本文warichu:[注]です。'),
    );
    expect(
      asciidoc.convert(
        '本文warichu:[注]です。',
        attributes: {'asciidoctor-compat': ''},
      ),
      contains('warichu:[注]'),
    );
  });

  test('two lines as near the same length as can be, the second no longer', () {
    // (Five characters: three and two.)
    final box = InlineWarichu('あいうえお').at(_face, 20);
    // (Each line half the size: the longer 30 points, and a parenthesis's
    // ink half on each side.)
    expect(box.width, 10 + 30 + 10);
    final pieces = InlineWarichu.pieces('あ' * 40, _face, 20, 200);
    // (A line 200 points long holds two lines of 18 half-size characters
    // between the parentheses: 40 characters in three pieces.)
    expect(pieces, hasLength(greaterThan(1)));
    expect(pieces.first.opens, isTrue);
    expect(pieces.first.closes, isFalse);
    expect(pieces.last.closes, isTrue);
    expect(pieces.map((p) => p.text).join(), 'あ' * 40);
  });

  test('PDF: copied as the note in parentheses', () {
    final dir = Directory.systemTemp.createTempSync('warichu.');
    addTearDown(() => dir.deleteSync(recursive: true));
    final theme = File('${dir.path}/theme.yml')
      ..writeAsStringSync('''
extends: default
base:
  font_family: JP
font:
  catalog:
    merge: true
    JP:
      normal: $_cjkPath
      bold: $_cjkPath
      italic: $_cjkPath
      bold_italic: $_cjkPath
''');
    final path = '${dir.path}/out.pdf';
    File(path).writeAsBytesSync(
      asciidoc.convertToBytes(
        '本文warichu:[注の文]です。',
        backend: Backend.pdf,
        attributes: {'pdf-theme': theme.path, 'reproducible': ''},
      ),
    );
    final text =
        Process.runSync('pdftotext', [path, '-'], stdoutEncoding: utf8).stdout
            as String;
    expect(text.replaceAll('\n', ''), contains('（注の文）'));
  }, skip: _poppler ? false : 'needs Poppler');

  final qpdf = Process.runSync('which', ['qpdf']).exitCode == 0;
  test('on a vertical page, ruby and warichu stand upright', () {
    final dir = Directory.systemTemp.createTempSync('warichu.');
    addTearDown(() => dir.deleteSync(recursive: true));
    final theme = File('${dir.path}/theme.yml')
      ..writeAsStringSync('''
extends: default
page:
  writing_mode: vertical-rl
base:
  font_family: JP
font:
  catalog:
    merge: true
    JP:
      normal: $_cjkPath
      bold: $_cjkPath
      italic: $_cjkPath
      bold_italic: $_cjkPath
''');
    int quarterTurns(String source) {
      final path = '${dir.path}/out.pdf';
      File(path).writeAsBytesSync(
        asciidoc.convertToBytes(
          source,
          backend: Backend.pdf,
          attributes: {
            'pdf-theme': theme.path,
            'reproducible': '',
            'nofooter': '',
          },
        ),
      );
      Process.runSync('qpdf', [
        '--qdf',
        '--object-streams=disable',
        path,
        '${dir.path}/plain.pdf',
      ]);
      final plain = latin1.decode(
        File('${dir.path}/plain.pdf').readAsBytesSync(),
      );
      // (Each upright character is drawn turned a quarter turn back.)
      return RegExp(r'0 1 -1 0 [-\d.]+ [-\d.]+ cm').allMatches(plain).length;
    }

    // (The base and its reading; the note and its parentheses.)
    expect(quarterTurns('ruby:字[じ]'), greaterThanOrEqualTo(2));
    expect(quarterTurns('warichu:[あい]'), greaterThanOrEqualTo(2));
  }, skip: qpdf ? false : 'needs qpdf');
}
