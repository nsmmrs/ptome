// Dates in the document's language: the "Last updated" date and time and
// an ISO revdate in CLDR's patterns (date-format's length, long by default
// outside English), the attributes themselves left ISO; nothing of it
// under asciidoctor-compat.
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

const String _source = '= Book\nTaro\nv1.0, 2026-10-14\n\nText.\n';

void main() {
  String html(Map<String, String> attributes) => asciidoc.convert(
    _source,
    standalone: true,
    attributes: {'docdatetime': '2026-10-14 17:46:40 +0900', ...attributes},
  );

  test('Japanese: the revision date and the last update', () {
    final out = html({'lang': 'ja'});
    expect(out, contains('<span id="revdate">2026年10月14日</span>'));
    expect(out, contains('最終更新 2026年10月14日 17:46:40 GMT+9'));
  });

  test("date-format's lengths, and the language's digits", () {
    expect(
      html({'lang': 'de', 'date-format': 'short'}),
      contains('<span id="revdate">14.10.26</span>'),
    );
    expect(
      html({'lang': 'fr', 'date-format': 'full'}),
      contains('<span id="revdate">mercredi 14 octobre 2026</span>'),
    );
    expect(
      html({'lang': 'ar-EG'}),
      contains('<span id="revdate">١٤ أكتوبر ٢٠٢٦</span>'),
    );
    expect(
      html({'lang': 'ar-EG', 'numbering-system': 'latn'}),
      contains('<span id="revdate">14 أكتوبر 2026</span>'),
    );
  });

  test('English, iso, a date not ISO and asciidoctor-compat keep it as '
      'written', () {
    expect(html({}), contains('<span id="revdate">2026-10-14</span>'));
    expect(
      html({'lang': 'en', 'date-format': 'long'}),
      contains('<span id="revdate">October 14, 2026</span>'),
    );
    expect(
      html({'lang': 'ja', 'date-format': 'iso'}),
      contains('<span id="revdate">2026-10-14</span>'),
    );
    expect(
      html({'lang': 'ja', 'asciidoctor-compat': ''}),
      contains('2026-10-14 17:46:40 +0900'),
    );
    expect(
      asciidoc.convert(
        '= Book\nTaro\nv1.0, Spring 2026\n',
        standalone: true,
        attributes: {'lang': 'ja'},
      ),
      contains('<span id="revdate">Spring 2026</span>'),
    );
  });

  test("the PDF's title page", () {
    final dir = Directory.systemTemp.createTempSync('dates.');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/out.pdf';
    File(path).writeAsBytesSync(
      asciidoc.convertToBytes(
        _source,
        backend: Backend.pdf,
        attributes: {'lang': 'de', 'doctype': 'book', 'reproducible': ''},
      ),
    );
    final text =
        Process.runSync('pdftotext', [path, '-'], stdoutEncoding: utf8).stdout
            as String;
    expect(text, contains('14. Oktober 2026'));
  }, skip: _poppler ? false : 'needs Poppler');

  test("calendar, or lang's -u-ca-: the Japanese, Buddhist and ROC "
      'calendars', () {
    expect(
      html({'lang': 'ja', 'calendar': 'japanese'}),
      contains('<span id="revdate">令和8年10月14日</span>'),
    );
    expect(
      html({'lang': 'ja-u-ca-japanese'}),
      contains('最終更新 令和8年10月14日 17:46:40 GMT+9'),
    );
    expect(
      html({'lang': 'th', 'calendar': 'buddhist'}),
      contains('<span id="revdate">14 ตุลาคม 2569</span>'),
    );
    expect(
      html({'lang': 'zh-Hant', 'calendar': 'roc'}),
      contains('<span id="revdate">民國115年10月14日</span>'),
    );
    // (In English too: a calendar other than the Gregorian is long by
    // default.)
    expect(
      html({'calendar': 'japanese'}),
      contains('<span id="revdate">October 14, 8 Reiwa</span>'),
    );
    expect(
      html({'lang': 'ja', 'calendar': 'japanese', 'asciidoctor-compat': ''}),
      contains('<span id="revdate">2026-10-14</span>'),
    );
  });
}
