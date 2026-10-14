// Direction per block and per span: a block's `dir` (or a `lang` written
// the other way from the document) set from its own side in the PDF and
// written as `lang` and `dir` in HTML and EPUB; a span's `dir` as a
// bidirectional isolate in the PDF and an attribute in HTML; nothing of it
// under asciidoctor-compat.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:plain_compression/plain_compression.dart';
import 'package:ptome/ptome.dart';
import 'package:ptome/src/font_index.dart' show FontIndex, Fonts;
import 'package:ptome/src/internal.dart' as impl;
import 'package:ptome/src/pdf/pdf.dart' show registerPdf;
import 'package:test/test.dart';

/// Poppler's pdftotext.
final bool _poppler =
    Process.runSync('which', ['pdftotext']).exitCode == 0 &&
    '${Process.runSync('pdftotext', ['-v']).stderr}'.contains('Poppler');

/// Noto Serif, its Latin letters (no bidirectional controls).
final String _latin = File(
  '../plain_typesetting/test/fonts/notoserif-regular-latin.ttf',
).absolute.path;

/// Noto Naskh Arabic, subset.
final String _naskh = File(
  '../plain_typesetting/test/fonts/notonaskharabic-subset.ttf',
).absolute.path;

const String _source = '''
= Doc

A paragraph in English.

[lang=ar]
نص عربي في فقرة.

[dir=rtl]
. أول
. ثان

English with [dir=rtl]#نص# and [lang=fr]#français#.
''';

void main() {
  String html(String source, [Map<String, String> attributes = const {}]) =>
      asciidoc.convert(source, standalone: true, attributes: attributes);

  test("HTML: a block's own language and direction on its element", () {
    final out = html(_source);
    expect(out, contains('<div lang="ar" dir="rtl" class="paragraph">'));
    expect(out, contains('<div dir="rtl" class="olist arabic">'));
    expect(out, contains('<span dir="rtl">نص</span>'));
    expect(out, contains('<span lang="fr">français</span>'));
  });

  test('a block in the language of a right-to-left document sets no dir; '
      'one in English there is left to right', () {
    final out = html(
      '= Doc\n:dir: rtl\n:lang: ar\n\n[lang=ar]\nنص.\n\n[lang=en]\nEnglish.\n',
    );
    expect(out, contains('<div lang="ar" class="paragraph">'));
    expect(out, contains('<div lang="en" dir="ltr" class="paragraph">'));
  });

  test('EPUB: the same attributes', () {
    final epub = asciidoc.convertToBytes(
      '= Doc\n\n== One\n\n$_source',
      backend: Backend.epub3,
    );
    final chapters = [
      for (final entry in readZip(epub))
        if (entry.name.endsWith('.xhtml'))
          utf8.decode(entry.bytes, allowMalformed: true),
    ].join();
    expect(chapters, contains('lang="ar" dir="rtl"'));
    expect(chapters, contains('<span dir="rtl">نص</span>'));
  });

  test('asciidoctor-compat writes none of it', () {
    final out = html(_source, {'asciidoctor-compat': ''});
    expect(out, isNot(contains('dir="rtl"')));
    expect(out, isNot(contains('lang="fr"')));
  });

  test('PDF: a right-to-left block set from the right, an English one from '
      'the left', () {
    final dir = Directory.systemTemp.createTempSync('block_direction.');
    addTearDown(() => dir.deleteSync(recursive: true));
    final theme = File('${dir.path}/theme.yml')
      ..writeAsStringSync('''
extends: default
font:
  catalog:
    merge: true
    Naskh:
      normal: $_naskh
      bold: $_naskh
      italic: $_naskh
      bold_italic: $_naskh
  fallbacks: [Naskh]
''');
    final path = '${dir.path}/out.pdf';
    File(path).writeAsBytesSync(
      asciidoc.convertToBytes(
        _source,
        backend: Backend.pdf,
        attributes: {'pdf-theme': theme.path, 'reproducible': ''},
      ),
    );
    final bbox =
        Process.runSync('pdftotext', [
              '-bbox',
              path,
              '-',
            ], stdoutEncoding: utf8).stdout
            as String;
    // (Each line's left and right ends, top to bottom: pdftotext writes
    // Arabic words in its own order, which versions differ in; words of a
    // line in different fonts have different tops, but their middles are
    // within a few points.)
    final words = [
      for (final m in RegExp(
        'xMin="([0-9.]+)" yMin="([0-9.]+)" xMax="([0-9.]+)" yMax="([0-9.]+)"',
      ).allMatches(bbox))
        (
          double.parse(m[1]!),
          (double.parse(m[2]!) + double.parse(m[4]!)) / 2,
          double.parse(m[3]!),
        ),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    final ordered = <(double, double)>[];
    var middle = double.negativeInfinity;
    for (final (l, y, r) in words) {
      if (y - middle > 6) {
        ordered.add((l, r));
        middle = y;
      } else {
        final (left, right) = ordered.last;
        ordered.last = (l < left ? l : left, r > right ? r : right);
      }
    }
    // (The text area runs from 48.24 to 547.04 points: after the title,
    // the English starts at its left; the Arabic and the list's items end
    // at its right, the last line's English starts at its left.)
    final [_, english, arabic, first, second, mixed, ...] = ordered;
    expect(english.$1, closeTo(48.24, 1));
    expect(arabic.$2, closeTo(547.04, 1));
    expect(first.$2, closeTo(547.04, 10));
    expect(second.$2, closeTo(547.04, 10));
    expect(mixed.$1, closeTo(48.24, 1));
  }, skip: _poppler ? false : 'needs Poppler');

  test("a span's isolate, which no font has, is set unwarned of; warned of "
      'under asciidoctor-compat, as Asciidoctor PDF does', () {
    final dir = Directory.systemTemp.createTempSync('block_direction.');
    addTearDown(() => dir.deleteSync(recursive: true));
    final theme = File('${dir.path}/theme.yml')
      ..writeAsStringSync('''
extends: default
base:
  font_family: Latin
font:
  catalog:
    merge: true
    Latin:
      normal: $_latin
      bold: $_latin
      italic: $_latin
      bold_italic: $_latin
    Naskh:
      normal: $_naskh
      bold: $_naskh
      italic: $_naskh
      bold_italic: $_naskh
  fallbacks: [Naskh]
''');
    // (No installed fonts, which may have the isolates: the theme's only.)
    Fonts.installed = FontIndex([dir.path], cacheFile: '${dir.path}/cache.tsv');
    addTearDown(() => Fonts.installed = null);
    List<String> warnings(
      String source, [
      Map<String, String> more = const {},
    ]) {
      registerPdf();
      final logger = impl.MemoryLogger();
      impl.convertToTarget(
        source,
        impl.AsciidoctorOptions(
          safe: impl.SafeMode.unsafe,
          backend: 'pdf',
          toFile: '${dir.path}/out.pdf',
          attributes: {'pdf-theme': theme.path, 'reproducible': '', ...more},
          logger: logger,
        ),
      );
      return [for (final m in logger.messages) '${m.message}'];
    }

    expect(
      warnings('English with [dir=rtl]#نص#.\n'),
      isNot(contains(contains('Could not locate'))),
    );
    expect(
      warnings('x\u2067y\n', {'asciidoctor-compat': ''}),
      contains(contains('Could not locate the character')),
    );
  });
}
