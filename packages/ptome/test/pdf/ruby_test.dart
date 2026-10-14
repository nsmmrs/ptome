// Ruby and emphasis marks in the PDF: the reading set over its base and
// the base alone copied; the marks reading as nothing.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:ptome/ptome.dart';
import 'package:test/test.dart';

/// Poppler's pdftotext (another one, Windows CI's, reads the text
/// otherwise).
final bool _poppler =
    Process.runSync('which', ['pdftotext']).exitCode == 0 &&
    '${Process.runSync('pdftotext', ['-v']).stderr}'.contains('Poppler');

/// A Noto Sans CJK subset with kana and the Han characters used here.
final String _cjkFont = File(
  '../plain_typesetting/test/fonts/notosanscjk-jp-subset.otf',
).absolute.path;

void main() {
  group('PDF', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('ruby_test.'));
    tearDown(() => dir.deleteSync(recursive: true));

    String pdfText(String source) {
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
  fallbacks: [JP]
role:
  bouten:
    text_emphasis: sesame
''');
      final bytes = asciidoc.convertToBytes(
        source,
        backend: Backend.pdf,
        attributes: {'pdf-theme': theme.path, 'reproducible': ''},
      );
      final pdf = File('${dir.path}/out.pdf')..writeAsBytesSync(bytes);
      if (!_poppler) return '';
      return Process.runSync('pdftotext', [
            pdf.path,
            '-',
          ], stdoutEncoding: utf8).stdout
          as String;
    }

    test('ruby is set above its base and copied as the base', () {
      final text = pdfText('の読み方と ruby:東京[とう きょう]、それに ruby:明日[あした]。');
      if (!_poppler) return;
      expect(text, contains('東京'));
      expect(text, contains('明日'));
      expect(text, isNot(contains('きょう')));
    }, skip: _poppler ? false : 'needs pdftotext');

    test('emphasis marks read as nothing', () {
      final text = pdfText('日本語の[.bouten]##文章##は、書きます。');
      if (!_poppler) return;
      expect(text, contains('日本語の文章は、書きます。'));
    }, skip: _poppler ? false : 'needs pdftotext');
  });
}
