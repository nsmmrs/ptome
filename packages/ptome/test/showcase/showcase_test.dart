// The showcase corpus's excerpts (doc/showcase.md): each work's
// `excerpt.adoc`, a page or two that shows what the work is there for,
// converted in the work's look to HTML, EPUB and PDF and compared with
// its `expected/` files: the HTML as it is, the EPUB's entries and the
// PDF by their SHA-256. The look's faces aren't installed here: the PDF
// sets every family the look names in the vendored Noto Serif, so it
// tests the layout, not the face (the works themselves are built whole,
// in their faces, by tool/showcase.dart). A change on purpose is a change
// to the expected files:
//
//   SHOWCASE_UPDATE=1 dart test test/showcase/showcase_test.dart
//
// A PDF that differs is written to the system's temporary folder, named
// in the failure, to look at.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:plain_compression/plain_compression.dart';
import 'package:ptome/src/api/file_backends.dart';
import 'package:ptome/src/cli/doctor.dart';
import 'package:ptome/src/internal.dart';
import 'package:ptome/src/look/loader.dart';
import 'package:test/test.dart';

import '../vendored_fonts.dart';

const String _corpus = 'test/showcase';

const String _noto = 'vendor/asciidoctor-pdf/data/fonts';

const String _multilingual = 'vendor/asciidoctor-epub3/fonts';

final bool _update = Platform.environment['SHOWCASE_UPDATE'] == '1';

/// The works with an excerpt, by folder name.
List<String> get _works => [
  for (final dir in Directory(_corpus).listSync().whereType<Directory>())
    if (File('${dir.path}/excerpt.adoc').existsSync())
      dir.uri.pathSegments.where((s) => s.isNotEmpty).last,
]..sort();

/// A theme over [look] (in [dir]) that sets each family it names in the
/// vendored Noto Serif.
String _theme(String dir, String look) {
  final families = lookFamilies(LookLoader(looksDir: dir).load(look));
  final multilingual = Directory(_multilingual).absolute.path;
  return [
    'extends: look',
    'font:',
    '  catalog:',
    '    merge: true',
    // (Noto Sans Math, the formulas' face, vendored: its own.)
    for (final family in families.toList()..sort())
      if (family != 'Noto Sans Math') ...[
        '    ${jsonEncode(family)}:',
        '      normal: notoserif-regular-subset.ttf',
        '      bold: notoserif-bold-subset.ttf',
        '      italic: notoserif-italic-subset.ttf',
        '      bold_italic: notoserif-bold_italic-subset.ttf',
      ],
    // (The letters the subset lacks, a schoolbook's marked vowels and
    // consonants, from the vendored multilingual Noto Serif.)
    '    Showcase Fallback:',
    '      normal: $multilingual/notoserif-regular-multilingual.ttf',
    '      bold: $multilingual/notoserif-bold-multilingual.ttf',
    '      italic: $multilingual/notoserif-italic-multilingual.ttf',
    '      bold_italic: $multilingual/notoserif-bolditalic-multilingual.ttf',
    '  fallbacks: [Showcase Fallback]',
    '',
  ].join('\n');
}

/// [path]'s text, or none.
String? _read(String path) {
  final file = File(path);
  return file.existsSync() ? file.readAsStringSync() : null;
}

void main() {
  late Directory scratch;
  setUpAll(() {
    // (The vendored fonts on the font path, Noto Sans Math among them, for
    // a textbook's equations.)
    useVendoredFonts();
    registerFileBackend('pdf');
    registerFileBackend('epub3');
    scratch = Directory.systemTemp.createTempSync('ptome-showcase.');
    // (Each backend's first conversion loads what every later one reuses
    // (the fonts, the hyphenation patterns, the stylesheets): once here,
    // so that each work's test times its own.)
    final warm = File('${scratch.path}/warm.adoc')
      ..writeAsStringSync(
        '= Warm\n:doctype: book\n:lang: en\n:hyphens:\n\n== One\n\n'
        '${'Typographical considerations notwithstanding, ' * 12}\n\n'
        '[verse]\n____\n_Lines_ of *verse*\n____\n\n'
        '[.sc]#Small capitals#, a note.footnote:[A note.]\n\n'
        '[quote, Someone]\n____\nA quotation.\n____\n\n'
        '|===\n|A |B\n|===\n\nTerm:: Its description.\n',
      );
    final theme = File('${scratch.path}/warm-theme.yml')
      ..writeAsStringSync(_theme(scratch.path, 'ptome'));
    final logger = MemoryLogger();
    final previous = LoggerManager.logger;
    LoggerManager.logger = logger;
    try {
      for (final backend in const ['html5', 'epub3', 'pdf']) {
        convertFile(
          warm.path,
          AsciidoctorOptions(
            safe: SafeMode.unsafe,
            backend: backend,
            toFile: '${warm.path}.$backend',
            attributes: {
              'reproducible': '',
              'pdf-theme': theme.absolute.path,
              'pdf-fontsdir': Directory(_noto).absolute.path,
            },
          ),
        );
      }
    } finally {
      LoggerManager.logger = previous;
    }
    // (And each work's look once, a line in it, so that its test times
    // the excerpt rather than the look's first compiling and loading.)
    try {
      LoggerManager.logger = logger;
      for (final slug in _works) {
        final dir = '$_corpus/$slug';
        final look = RegExp(
          r'^:look: (\S+)$',
          multiLine: true,
        ).firstMatch(File('$dir/excerpt.adoc').readAsStringSync())?[1];
        if (look == null) continue;
        final lookTheme = File('${scratch.path}/warm-$slug-theme.yml')
          ..writeAsStringSync(_theme(dir, look));
        final doc = File('${scratch.path}/warm-$slug.adoc')
          ..writeAsStringSync(
            '= Warm\n:doctype: book\n:lang: en\n:look: $look\n'
            ':looksdir: ${Directory(dir).absolute.path}\n\n== One\n\nA line.\n',
          );
        convertFile(
          doc.path,
          AsciidoctorOptions(
            safe: SafeMode.unsafe,
            backend: 'pdf',
            toFile: '${doc.path}.pdf',
            attributes: {
              'reproducible': '',
              'pdf-theme': lookTheme.absolute.path,
              'pdf-themesdir': Directory(dir).absolute.path,
              'pdf-fontsdir': Directory(_noto).absolute.path,
            },
          ),
        );
      }
    } finally {
      LoggerManager.logger = previous;
    }
    // (And the reading of what they wrote.)
    for (final entry in readZip(File('${warm.path}.epub3').readAsBytesSync())) {
      sha256.convert(entry.bytes);
    }
    sha256.convert(File('${warm.path}.pdf').readAsBytesSync());
  });
  tearDownAll(() => scratch.deleteSync(recursive: true));

  /// [slug]'s excerpt converted by [backend] (its PDF in the vendored
  /// fonts), checked to convert without a warning: what it wrote.
  List<int> convert(String slug, String backend) {
    final dir = '$_corpus/$slug';
    final look = RegExp(
      r'^:look: (\S+)$',
      multiLine: true,
    ).firstMatch(File('$dir/excerpt.adoc').readAsStringSync())?[1];
    expect(look, isNotNull, reason: '$dir/excerpt.adoc names no look');
    final theme = File('${scratch.path}/$slug-theme.yml');
    if (backend == 'pdf') theme.writeAsStringSync(_theme(dir, look!));
    final file = '${scratch.path}/$slug.$backend';
    final logger = MemoryLogger();
    final previous = LoggerManager.logger;
    LoggerManager.logger = logger;
    try {
      convertFile(
        '$dir/excerpt.adoc',
        AsciidoctorOptions(
          safe: SafeMode.unsafe,
          backend: backend,
          toFile: file,
          attributes: {
            'reproducible': '',
            if (backend == 'pdf') ...{
              'pdf-theme': theme.absolute.path,
              // (The look's images, a page's frame, found beside it.)
              'pdf-themesdir': Directory(dir).absolute.path,
              'pdf-fontsdir': Directory(_noto).absolute.path,
            },
          },
        ),
      );
    } finally {
      LoggerManager.logger = previous;
    }
    expect(
      [
        for (final m in logger.messages)
          if (m.severity.index >= Severity.warn.index)
            '${m.severity.name}: ${m.message.text}',
      ],
      isEmpty,
      reason: 'the excerpt converts without a warning',
    );
    return File(file).readAsBytesSync();
  }

  /// [actual] as [slug]'s expected [name], or written there when
  /// updating.
  void compare(String slug, String name, String actual) {
    final expected = '$_corpus/$slug/expected/$name';
    if (_update) {
      File(expected)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(actual);
      return;
    }
    expect(actual, _read(expected), reason: expected);
  }

  for (final slug in _works) {
    group('$slug: the excerpt', () {
      test('in HTML', () {
        compare(slug, 'excerpt.html', utf8.decode(convert(slug, 'html5')));
      });

      test('in EPUB: its entries', () {
        final entries = [
          for (final entry in readZip(convert(slug, 'epub3')))
            '${sha256.convert(entry.bytes)}  ${entry.name}\n',
        ].join();
        compare(slug, 'excerpt.epub.txt', entries);
      });

      test('in PDF', () {
        final pdf = convert(slug, 'pdf');
        final digest = '${sha256.convert(pdf)}\n';
        final expected = _read('$_corpus/$slug/expected/excerpt.pdf.sha256');
        if (!_update && digest != expected) {
          final kept = File('${Directory.systemTemp.path}/showcase-$slug.pdf')
            ..writeAsBytesSync(pdf);
          fail(
            'the PDF is ${digest.trim()}, not ${expected?.trim()} (it is in '
            '${kept.path}; SHOWCASE_UPDATE=1 takes it as expected)',
          );
        }
        compare(slug, 'excerpt.pdf.sha256', digest);
      });
    });
  }
}
