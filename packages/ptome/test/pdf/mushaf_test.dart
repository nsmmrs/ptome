// A mushaf's pages as tool/mushaf.dart lays them out (its whole 604 pages
// checked by hand: `dart run tool/mushaf.dart --check`): every line of a
// page a hard-broken line of one paragraph, justified to the measure, on
// a fixed pitch of 15 lines to an A5 page; a surah's title and the
// basmala before it centred lines of their own; the opening page's lines
// centred. Two pages of the Tanzil text the units corpus holds
// (test/units/corpus/NOTICE.md: verbatim, with attribution to tanzil.net)
// in Noto Naskh Arabic, lines broken where this test says (the Medina
// mushaf's own lines aren't ours to copy). No line may wrap or move to
// another page: Poppler reads each page's lines back, its answers
// recorded in test/oracles/pdf_mushaf.json.gz (test/support/oracles.dart;
// ORACLES=record asks it again).
@TestOn('vm')
library;

import 'dart:io';

import 'package:ptome/src/internal.dart';
import 'package:ptome/src/pdf/pdf.dart';
import 'package:test/test.dart';

import '../support/oracles.dart';
import '../support/pdf_tools.dart';

const String _surahs = 'test/units/corpus/quran/ar/surahs';

/// The ayahs of the surah file [name], in order.
List<String> _ayahs(String name) => [
  for (final line in File('$_surahs/$name.adoc').readAsLinesSync())
    if (line.startsWith('@ ')) line.substring(2).trim(),
];

/// A page's lines: a surah's title, the basmala, or ayahs.
sealed class _Line {
  const new();
}

final class _Title extends _Line {
  const new(this.name);
  final String name;
}

final class _Basmala extends _Line {
  const new();
}

final class _Verses extends _Line {
  const new(this.ayahs);
  final List<String> ayahs;
}

/// An A5 page of 15 lines on a fixed pitch filling the text block, every
/// line justified (tool/mushaf.dart's theme, in Noto Naskh Arabic).
const String _theme = '''
extends: base
font:
  catalog:
    Naskh:
      normal: notonaskharabic-mushaf.ttf
      bold: notonaskharabic-mushaf.ttf
      italic: notonaskharabic-mushaf.ttf
      bold_italic: notonaskharabic-mushaf.ttf
page:
  size: A5
  margin: [16mm, 14mm, 20mm, 14mm]
base:
  font-family: Naskh
  font-size: 15.4
  line-pitch: 32.15
  text-align: justify
  text-align-last: justify
  hyphens: false
prose:
  margin-bottom: 0
role:
  surah:
    font-size: 13
footer:
  height: 14mm
  border-width: 0
  recto:
    left:
      content: ~
    center:
      content: '{page-number}'
    right:
      content: ~
  verso:
    left:
      content: ~
    center:
      content: '{page-number}'
    right:
      content: ~
''';

/// [pages] as tool/mushaf.dart writes them: each page's lines of verses
/// one paragraph of hard-broken lines (centred on the opening page), the
/// titles and basmalas paragraphs of their own.
String _document(List<List<_Line>> pages, String basmala) {
  final fonts = Directory('test/pdf/fixtures/fonts').absolute.path;
  final out = StringBuffer()
    ..writeln('= المصحف')
    ..writeln(':lang: ar')
    ..writeln(':dir: rtl')
    ..writeln(':doctype: book')
    ..writeln(':notitle:')
    ..writeln(':reproducible:')
    ..writeln(':pdf-themesdir: {docdir}')
    ..writeln(':pdf-theme: mushaf-theme.yml')
    ..writeln(':pdf-fontsdir: $fonts');
  for (final (p, page) in pages.indexed) {
    out.writeln();
    if (p > 0) {
      out
        ..writeln('<<<')
        ..writeln();
    }
    final verses = <String>[];
    void flush() {
      if (verses.isEmpty) return;
      if (p == 0) out.writeln('[.text-center]');
      out
        ..writeln(verses.join(' +\n'))
        ..writeln();
      verses.clear();
    }

    for (final line in page) {
      switch (line) {
        case _Verses(:final ayahs):
          verses.add(ayahs.join(' '));
        case _Title(:final name):
          flush();
          out
            ..writeln('[.text-center.surah]')
            ..writeln('سورة $name')
            ..writeln();
        case _Basmala():
          flush();
          out
            ..writeln('[.text-center.basmala]')
            ..writeln(basmala)
            ..writeln();
      }
    }
    flush();
  }
  return '$out';
}

void main() {
  final recorded = Oracle('pdf_mushaf', compressed: true);

  test('two pages as a mushaf sets them: no line wrapped or moved on', () {
    registerPdf();
    final fatiha = _ayahs('001-al-faatiha');
    final ikhlas = _ayahs('112-al-ikhlaas');
    final falaq = _ayahs('113-al-falaq');
    final nas = _ayahs('114-an-naas');
    // (Al-Fatiha's first ayah is the basmala.)
    final basmala = fatiha.first;
    final pages = [
      [
        const _Title('الفاتحة'),
        for (final ayah in fatiha) _Verses([ayah]),
      ],
      [
        const _Title('الإخلاص'),
        const _Basmala(),
        _Verses(ikhlas.sublist(0, 2)),
        _Verses(ikhlas.sublist(2)),
        const _Title('الفلق'),
        const _Basmala(),
        _Verses(falaq.sublist(0, 2)),
        _Verses([falaq[2]]),
        _Verses(falaq.sublist(3)),
        const _Title('الناس'),
        const _Basmala(),
        _Verses(nas.sublist(0, 3)),
        _Verses([nas[3]]),
        _Verses([nas[4]]),
        _Verses([nas[5]]),
      ],
    ];
    expect([for (final page in pages) page.length], [8, 15]);

    final work = Directory.systemTemp.createTempSync('mushaf.');
    addTearDown(() => work.deleteSync(recursive: true));
    File('${work.path}/mushaf-theme.yml').writeAsStringSync(_theme);
    final source = File('${work.path}/mushaf.adoc')
      ..writeAsStringSync(_document(pages, basmala));
    final logger = MemoryLogger();
    final previous = LoggerManager.logger;
    LoggerManager.logger = logger;
    try {
      convertFile(
        source.path,
        AsciidoctorOptions(
          safe: SafeMode.unsafe,
          backend: 'pdf',
          toDir: work.path,
        ),
      );
    } finally {
      LoggerManager.logger = previous;
    }
    expect([
      for (final m in logger.messages)
        if (m.severity.index >= Severity.warn.index) '${m.message}',
    ], isEmpty);
    final pdf = File('${work.path}/mushaf.pdf').readAsBytesSync();
    final info = poppler(recorded, 'pdfinfo', pdf).stdout;
    expect(info, matches(RegExp(r'Pages:\s+2\n')));
    // Each page's lines, read back: as many as it has (a line too wide
    // for the measure would wrap, and run on), the page number last.
    for (final (p, page) in pages.indexed) {
      final text = pdftotext(
        recorded,
        pdf,
        options: ['-f', '${p + 1}', '-l', '${p + 1}', '-layout'],
      );
      final lines = [
        for (final line in text.split('\n'))
          // (Poppler marks the right-to-left runs with embedding controls.)
          if (line.replaceAll(RegExp('[\u202a-\u202e]'), '').trim()
              case final bare when bare.isNotEmpty)
            bare,
      ];
      expect(lines, hasLength(page.length + 1), reason: text);
      expect(lines.last, '${p + 1}');
      for (final line in page.whereType<_Title>()) {
        expect(text, contains(line.name), reason: 'page ${p + 1}');
      }
    }
  });
}
