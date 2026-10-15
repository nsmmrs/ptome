// Generated numbers in the language's numerals (CLDR's default numbering
// system, or `numbering-system`), ordered lists in CSS's counter styles,
// `sectnums-style` and the PDF's `page_numbering_style`; nothing of it
// under asciidoctor-compat.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:plain_compression/plain_compression.dart';
import 'package:ptome/ptome.dart';
import 'package:test/test.dart';

import 'support/oracles.dart';
import 'support/pdf_tools.dart';

/// Noto Naskh Arabic, subset: its letters and both sets of digits.
final String _naskh = File(
  '../plain_typesetting/test/fonts/notonaskharabic-subset.ttf',
).absolute.path;

/// Noto Serif, its Latin letters (the roman page numbers).
final String _latin = File(
  '../plain_typesetting/test/fonts/notoserif-regular-latin.ttf',
).absolute.path;

const String _arabic = '''
= كتاب
:doctype: book
:sectnums:

== فصل

نص.footnote:[حاشية]

.جدول
|===
|ا
|===

. ا
. ب
''';

/// The tools' runs, recorded (test/oracles/numbering.json.gz,
/// test/support/oracles.dart; ORACLES=record asks them again).
late final Oracle _recorded;

void main() {
  _recorded = Oracle('numbering', compressed: true);
  String html(String source, Map<String, String> attributes) =>
      asciidoc.convert(source, standalone: true, attributes: attributes);

  test('Egyptian Arabic: sections, captions, footnotes and lists in '
      'Arabic-Indic digits', () {
    final out = html(_arabic, {'lang': 'ar-EG'});
    expect(out, contains('<h2 id="_فصل">١. فصل</h2>'));
    expect(out, contains('جدول ١.'));
    expect(out, contains('title="View footnote.">١</a>]'));
    expect(out, contains('<a href="#_footnoteref_1">١</a>.'));
    expect(out, contains('style="list-style-type: arabic-indic"'));
  });

  test('Arabic as such, CLDR says, keeps 0 to 9; numbering-system chooses', () {
    expect(html(_arabic, {'lang': 'ar'}), contains('>1. فصل</h2>'));
    expect(
      html(_arabic, {'lang': 'ar', 'numbering-system': 'arab'}),
      contains('>١. فصل</h2>'),
    );
    expect(html(_arabic, {'lang': 'ar-u-nu-arab'}), contains('>١. فصل</h2>'));
    expect(html(_arabic, {'lang': 'fa'}), contains('>۱. فصل</h2>'));
    expect(
      html(_arabic, {'lang': 'ar-EG', 'numbering-system': 'latn'}),
      contains('>1. فصل</h2>'),
    );
  });

  test('a list in a counter style CSS defines; the head defines the ones '
      "browsers don't know", () {
    const source = '= Doc\n\n[hiragana]\n. a\n. b\n\n[hangul]\n. c\n';
    final out = html(source, {});
    expect(
      out,
      contains(
        '<ol class="hiragana" style="list-style-type: '
        'hiragana">',
      ),
    );
    expect(out, contains('style="list-style-type: hangul"'));
    expect(out, contains('@counter-style hangul { system: alphabetic;'));
    expect(out, isNot(contains('@counter-style hiragana')));
  });

  test('sectnums-style', () {
    const source = '= Doc\n:sectnums:\n\n== One\n\n== Two\n\n=== Sub\n';
    final out = html(source, {'sectnums-style': 'upper-roman'});
    expect(out, contains('>II. Two</h2>'));
    expect(out, contains('>II.I. Sub</h3>'));
  });

  test('EPUB: the list styles and the counter style rules', () {
    final epub = asciidoc.convertToBytes(
      '= 책\n:lang: ko\n\n== 장\n\n[hangul]\n. 가\n',
      backend: Backend.epub3,
    );
    final chapters = [
      for (final entry in readZip(epub))
        if (entry.name.endsWith('.xhtml'))
          utf8.decode(entry.bytes, allowMalformed: true),
    ].join();
    expect(chapters, contains('style="list-style-type: hangul"'));
    expect(chapters, contains('@counter-style hangul {'));
  });

  test("asciidoctor-compat keeps Asciidoctor's numbers", () {
    final out = html(_arabic, {'lang': 'ar-EG', 'asciidoctor-compat': ''});
    expect(out, contains('>1. فصل</h2>'));
    expect(out, isNot(contains('list-style-type')));
    const source = '= Doc\n\n[hiragana]\n. a\n';
    expect(
      html(source, {'asciidoctor-compat': ''}),
      isNot(contains('list-style-type')),
    );
  });

  test("PDF: list markers, footnotes and page numbers in the language's "
      'digits; page_numbering_style', () {
    final dir = Directory.systemTemp.createTempSync('numbering.');
    addTearDown(() => dir.deleteSync(recursive: true));
    String text(Map<String, String> attributes, {String theme = ''}) {
      final file = File('${dir.path}/theme.yml')
        ..writeAsStringSync('''
extends: default
base:
  font_family: Naskh
font:
  catalog:
    merge: true
    Naskh:
      normal: $_naskh
      bold: $_naskh
      italic: $_naskh
      bold_italic: $_naskh
    Latin:
      normal: $_latin
      bold: $_latin
      italic: $_latin
      bold_italic: $_latin
  fallbacks: [Latin]
$theme''');
      final path = '${dir.path}/out.pdf';
      File(path).writeAsBytesSync(
        asciidoc.convertToBytes(
          // (A second page, which shows its number.)
          '$_arabic\n<<<\n\nنص.\n',
          backend: Backend.pdf,
          attributes: {
            'pdf-theme': file.path,
            'reproducible': '',
            'lang': 'ar-EG',
            ...attributes,
          },
        ),
      );
      // (Its bidi controls out: pdftotext writes right-to-left lines in
      // embeddings.)
      final out =
          recordedRunSync(_recorded, 'pdftotext', [
                path,
                '-',
              ], stdoutEncoding: utf8).stdout
              as String;
      return out.replaceAll(RegExp('[\u202a-\u202e\u2066-\u2069]'), '');
    }

    bool line(String out, String text) =>
        RegExp('^\\s*$text\\s*\$', multiLine: true).hasMatch(out);
    final out = text({});
    // (The list's markers, the footnote's reference and label, the
    // second page's number: counted, as pdftotext versions order a
    // right-to-left line's digits and marks differently.)
    expect('١'.allMatches(out).length, greaterThanOrEqualTo(3), reason: out);
    expect('٢'.allMatches(out).length, greaterThanOrEqualTo(2), reason: out);
    expect(line(out, '٢'), isTrue, reason: out);
    expect(out, isNot(contains(RegExp('[0-9]'))));
    expect(text({'asciidoctor-compat': ''}), isNot(contains('١')));
    final roman = text({}, theme: 'page:\n  numbering_style: upper-roman\n');
    expect(line(roman, 'II'), isTrue, reason: roman);
  });
}
