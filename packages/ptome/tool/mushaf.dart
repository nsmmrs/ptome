/// The Medina mushaf, line for line: 604 pages of 15 lines, each page
/// ending on an ayah's end, from the quran.com API's word data (each
/// word's page and line in the KFGQPC Hafs mushaf, its text in the
/// KFGQPC Hafs encoding) and set in the KFGQPC Uthmanic Script Hafs font,
/// whose ligatures turn an ayah's number into its medallion.
///
/// The data and the font are the King Fahd Complex's, free to use but not
/// ours to redistribute: they are fetched into a cache, never committed.
///
///     dart run tool/mushaf.dart [--check] [OUT]
///     ptome -b pdf OUT/mushaf.adoc
///
/// With `--check`, it also converts the mushaf and checks every page is
/// as the mushaf has it: 604, no line wrapped or moved on, no warning
/// (test/pdf/mushaf_test.dart sets two pages so on every run).
///
/// OUT is `~/.cache/asciidart-work/mushaf` by default; what is already
/// there is not fetched again. It ends with `mushaf.adoc`, its theme and
/// the font. Each page is a block of its lines: a line of verses is one
/// line of a paragraph (hard breaks between them, every line justified,
/// `base_text_align_last: justify`); a surah's title and the basmala
/// before it are lines of their own, centred, where the mushaf has them
/// (the lines no word is on).
library;

import 'dart:convert';
import 'dart:io';

import 'package:ptome/src/internal.dart';
import 'package:ptome/src/pdf/pdf.dart';

const _api = 'https://api.quran.com/api/v4';
const _fontUrl =
    'https://static-cdn.tarteel.ai/qul/fonts/UthmanicHafs1Ver18.ttf';
const _font = 'UthmanicHafs1Ver18.ttf';
const _pages = 604;
const _lines = 15;

/// A line of the mushaf.
sealed class _Line {
  const new();
}

/// A line of verses: its words, ayah ends among them.
final class _Verses extends _Line {
  new(this.words);
  final List<String> words;
}

/// A surah's title.
final class _Title extends _Line {
  const new(this.surah);
  final int surah;
}

/// The basmala before a surah.
final class _Basmala extends _Line {
  const new();
}

/// A word on the page: its line, text and verse.
typedef _Word = ({int line, String text, int surah, int ayah});

Future<void> main(List<String> arguments) async {
  final args = [...arguments];
  final check = args.remove('--check');
  final out = Directory(
    args.isNotEmpty
        ? args.first
        : '${Platform.environment['HOME']}/.cache/asciidart-work/mushaf',
  )..createSync(recursive: true);
  final client = HttpClient();
  try {
    await _fetch(client, out);
  } finally {
    client.close();
  }
  final names = _surahNames(out);
  final pages = [for (var p = 1; p <= _pages; p++) _words(out, p)];
  final layout = _layout(pages);
  final basmala = [
    for (final w in pages.first)
      if (w.surah == 1 && w.ayah == 1 && !_isEnd(w.text)) w.text,
  ].join(' ');
  File('${out.path}/mushaf.adoc')
      .writeAsStringSync(_document(layout, names, basmala));
  File('${out.path}/mushaf-theme.yml').writeAsStringSync(_theme);
  stdout.writeln('wrote ${out.path}/mushaf.adoc');
  if (check) exit(_check(out) ? 0 : 1);
}

/// Converts the mushaf in [out] and checks it: no warning, 604 pages (a
/// line too wide for the measure would wrap, a page of 15 lines then run
/// onto another), the Fatiha on the first and an-Nas on the last.
bool _check(Directory out) {
  registerPdf();
  final logger = MemoryLogger();
  LoggerManager.logger = logger;
  convertFile(
    '${out.path}/mushaf.adoc',
    AsciidoctorOptions(safe: SafeMode.unsafe, backend: 'pdf', toDir: out.path),
  );
  final problems = [
    for (final m in logger.messages)
      if (m.severity.index >= Severity.warn.index) 'warning: ${m.message}',
  ];
  final pdf = '${out.path}/mushaf.pdf';
  final info = '${Process.runSync('pdfinfo', [pdf]).stdout}';
  if (!RegExp('Pages:\\s+$_pages\n').hasMatch(info)) {
    problems.add('not $_pages pages: $info');
  }
  String page(int number) {
    final range = ['-f', '$number', '-l', '$number'];
    final text = Process.runSync('pdftotext', [
      ...range,
      pdf,
      '-',
    ], stdoutEncoding: utf8);
    return '${text.stdout}';
  }

  if (!page(1).contains('سورة الفاتحة')) problems.add('no Fatiha on page 1');
  if (!page(_pages).contains('سورة الناس')) {
    problems.add('no an-Nas on page $_pages');
  }
  stdout.writeln(
    problems.isEmpty ? 'every page as the mushaf has it' : problems.join('\n'),
  );
  return problems.isEmpty;
}

/// Fetches what [out] doesn't have yet: the font, the surahs' names and
/// each page's words.
Future<void> _fetch(HttpClient client, Directory out) async {
  Future<List<int>> get(String url) async {
    for (var attempt = 1; ; attempt++) {
      try {
        final request = await client.getUrl(Uri.parse(url));
        final response = await request.close();
        final bytes = await response.fold<List<int>>(
          [],
          (a, b) => a..addAll(b),
        );
        if (response.statusCode != 200) {
          throw HttpException('$url: ${response.statusCode}');
        }
        return bytes;
      } on IOException {
        if (attempt == 3) rethrow;
        await Future<void>.delayed(Duration(seconds: attempt * 2));
      }
    }
  }

  final font = File('${out.path}/$_font');
  if (!font.existsSync()) font.writeAsBytesSync(await get(_fontUrl));
  final chapters = File('${out.path}/chapters.json');
  if (!chapters.existsSync()) {
    chapters.writeAsBytesSync(await get('$_api/chapters?language=ar'));
  }
  final dir = Directory('${out.path}/pages')..createSync();
  final missing = [
    for (var p = 1; p <= _pages; p++)
      if (!File(_pagePath(dir, p)).existsSync()) p,
  ];
  // A few at a time.
  for (var i = 0; i < missing.length; i += 8) {
    await Future.wait([
      for (final p in missing.skip(i).take(8))
        get(
          '$_api/verses/by_page/$p?words=true&per_page=50'
          '&word_fields=text_qpc_hafs,line_number',
        ).then((bytes) => File(_pagePath(dir, p)).writeAsBytesSync(bytes)),
    ]);
  }
}

String _pagePath(Directory dir, int page) =>
    '${dir.path}/${page.toString().padLeft(3, '0')}.json';

/// The surahs' Arabic names, by number.
Map<int, String> _surahNames(Directory out) {
  final json = jsonDecode(File('${out.path}/chapters.json').readAsStringSync());
  return {
    if (json case {'chapters': final List<Object?> chapters})
      for (final chapter in chapters)
        if (chapter case {'id': final int id, 'name_arabic': final String name})
          id: name,
  };
}

/// Page [page]'s words, in order.
List<_Word> _words(Directory out, int page) {
  final json = jsonDecode(
    File(_pagePath(Directory('${out.path}/pages'), page)).readAsStringSync(),
  );
  if (json case {'pagination': {'total_pages': final int total}}
      when total != 1) {
    throw StateError('page $page: more verses than one request holds');
  }
  return [
    if (json case {'verses': final List<Object?> verses})
      for (final verse in verses)
        if (verse case {
          'verse_key': final String key,
          'words': final List<Object?> words,
        })
          for (final word in words)
            if (word case {
              'line_number': final int line,
              'text_qpc_hafs': final String text,
            })
              (
                line: line,
                text: text,
                surah: int.parse(key.split(':').first),
                ayah: int.parse(key.split(':').last),
              ),
  ];
}

/// An ayah's end (its number, which the font sets in a medallion).
bool _isEnd(String text) => RegExp(r'^[٠-٩]+$').hasMatch(text);

/// Each page's lines: the words' lines, and in the lines no word is on, a
/// surah's title and its basmala, in that order, before its first ayah
/// (they may straddle a page's end).
List<List<_Line?>> _layout(List<List<_Word>> pages) {
  final layout = [for (final _ in pages) List<_Line?>.filled(_lines, null)];
  // Every slot in reading order, the empty ones waiting for the surah that
  // starts after them.
  final empty = <(int, int)>[];
  for (var p = 0; p < pages.length; p++) {
    final byLine = <int, List<_Word>>{};
    for (final w in pages[p]) {
      (byLine[w.line] ??= []).add(w);
    }
    final last = p == 0 || p == 1
        ? byLine.keys.reduce((a, b) => a > b ? a : b)
        : _lines;
    for (var l = 1; l <= last; l++) {
      final words = byLine[l];
      if (words == null) {
        empty.add((p, l - 1));
        continue;
      }
      if (empty.isNotEmpty) {
        final surah = words.first.surah;
        if (words.first.ayah != 1) {
          throw StateError('page ${p + 1} line $l: empty lines before it');
        }
        final lines = <_Line>[
          _Title(surah),
          if (surah != 1 && surah != 9) const _Basmala(),
        ];
        if (lines.length != empty.length) {
          throw StateError(
            'page ${p + 1}: ${empty.length} empty lines before surah $surah',
          );
        }
        for (var i = 0; i < lines.length; i++) {
          final (ep, el) = empty[i];
          layout[ep][el] = lines[i];
        }
        empty.clear();
      }
      layout[p][l - 1] = _Verses([for (final w in words) w.text]);
    }
  }
  if (empty.isNotEmpty) throw StateError('empty lines at the end');
  return layout;
}

String _document(
  List<List<_Line?>> layout,
  Map<int, String> names,
  String basmala,
) {
  final out = StringBuffer()
    ..writeln('= المصحف الشريف')
    ..writeln(':lang: ar')
    ..writeln(':dir: rtl')
    ..writeln(':doctype: book')
    ..writeln(':notitle:')
    ..writeln(':reproducible:')
    ..writeln(':pdf-themesdir: {docdir}')
    ..writeln(':pdf-theme: mushaf-theme.yml')
    ..writeln(':pdf-fontsdir: {docdir}')
    ..writeln()
    ..writeln('// Generated by tool/mushaf.dart from the quran.com API.');
  for (var p = 0; p < layout.length; p++) {
    out.writeln();
    if (p > 0) {
      out
        ..writeln('<<<')
        ..writeln();
    }
    // The opening pages' few lines centred, as the mushaf sets them.
    final opening = p < 2;
    final verses = <String>[];
    void flush() {
      if (verses.isEmpty) return;
      if (opening) out.writeln('[.text-center]');
      out
        ..writeln(verses.join(' +\n'))
        ..writeln();
      verses.clear();
    }

    for (final line in layout[p]) {
      switch (line) {
        case null:
          break;
        case _Verses(:final words):
          verses.add(words.join(' '));
        case _Title(:final surah):
          flush();
          out
            ..writeln('[.text-center.surah]')
            ..writeln('سورة ${names[surah]}')
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
  return out.toString();
}

/// An A5 page, 15 lines on a fixed pitch filling the text block, every
/// line justified.
const _theme = '''
extends: base
font:
  catalog:
    Hafs:
      normal: UthmanicHafs1Ver18.ttf
      bold: UthmanicHafs1Ver18.ttf
      italic: UthmanicHafs1Ver18.ttf
      bold_italic: UthmanicHafs1Ver18.ttf
page:
  size: A5
  margin: [16mm, 14mm, 20mm, 14mm]
base:
  font-family: Hafs
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
