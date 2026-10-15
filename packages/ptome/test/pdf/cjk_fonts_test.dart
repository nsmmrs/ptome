// Han, kana and Hangul no font of the theme has: the installed Noto CJK
// face of the text's language's region (FEAT-stxzq9). The faces installed
// are the test's own: subsets in test/pdf/fixtures/fonts/cjk (its
// README), never the machine's.
@TestOn('vm')
library;

import 'dart:io';

import 'package:ptome/src/font_index.dart';
import 'package:ptome/src/internal.dart';
import 'package:ptome/src/pdf/pdf.dart';
import 'package:test/test.dart';

import '../support/oracles.dart';
import '../support/pdf_tools.dart';

const String _fonts = '../plain_typesetting/test/fonts';

/// The tools' runs, recorded (test/oracles/pdf_cjk_fonts.json.gz,
/// test/support/oracles.dart; ORACLES=record asks them again).
late final Oracle _recorded;

void main() {
  _recorded = Oracle('pdf_cjk_fonts', compressed: true);
  setUpAll(registerPdf);
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('cjk_fonts_test.'));
  tearDown(() => dir.deleteSync(recursive: true));

  /// The warnings converting [source] gives, its PDF at `doc.pdf`.
  List<String> convert(String source, {Map<String, String>? attributes}) {
    File('${dir.path}/doc.adoc').writeAsStringSync(source);
    final logger = MemoryLogger();
    convertFile(
      '${dir.path}/doc.adoc',
      AsciidoctorOptions(
        safe: SafeMode.unsafe,
        backend: 'pdf',
        toFile: '${dir.path}/doc.pdf',
        attributes: {'reproducible': '', 'nofooter': '', ...?attributes},
        logger: logger,
      ),
    );
    return [
      for (final m in logger.messages)
        if (m.severity == Severity.warn) '${m.message}',
    ];
  }

  group('with only the fonts given', () {
    late String theme;
    setUp(() {
      Directory('${dir.path}/fonts').createSync();
      theme =
          (File('${dir.path}/theme.yml')..writeAsStringSync('''
extends: base
font:
  catalog:
    Serif:
      normal: ${File('$_fonts/notoserif-features.ttf').absolute.path}
base:
  font_family: Serif
'''))
              .path;
    });
    tearDown(() => Fonts.installed = null);

    void install({required bool cjk}) {
      final installed = File('${dir.path}/fonts/notosanscjk-jp-subset.otf');
      if (cjk) {
        File('$_fonts/notosanscjk-jp-subset.otf').copySync(installed.path);
      } else if (installed.existsSync()) {
        installed.deleteSync();
      }
      // (Indexed afresh.)
      final cache = File('${dir.path}/cache.tsv');
      if (cache.existsSync()) cache.deleteSync();
      Fonts.installed = FontIndex([
        '${dir.path}/fonts',
      ], cacheFile: '${dir.path}/cache.tsv');
    }

    test('an installed Noto CJK face sets what the theme has no font for', () {
      install(cjk: true);
      for (final lang in ['ja', 'zh-Hans', 'ko', 'en']) {
        expect(
          convert('直骨今', attributes: {'pdf-theme': theme, 'lang': lang}),
          isEmpty,
          reason: lang,
        );
      }
    });

    test('without one, the warning says to install it', () {
      install(cjk: false);
      expect(convert('直骨今', attributes: {'pdf-theme': theme, 'lang': 'ja'}), [
        contains('install Noto Sans CJK or Noto Serif CJK'),
      ]);
    });

    test('not under asciidoctor-compat', () {
      List<int> pdf({required bool cjk, required bool compat}) {
        install(cjk: cjk);
        convert(
          '直骨今',
          attributes: {
            'pdf-theme': theme,
            'lang': 'ja',
            if (compat) 'asciidoctor-compat': '',
          },
        );
        return File('${dir.path}/doc.pdf').readAsBytesSync();
      }

      // (The same PDF with Noto CJK installed or not.)
      expect(pdf(cjk: true, compat: true), pdf(cjk: false, compat: true));
      expect(
        pdf(cjk: true, compat: false),
        isNot(pdf(cjk: false, compat: false)),
      );
    });
  });

  test("each text in its language's region's face, serif beside serif", () {
    // (Noto Serif CJK's five regions and Noto Sans CJK SC Bold, installed.)
    Fonts.installed = FontIndex([
      Directory('test/pdf/fixtures/fonts/cjk').absolute.path,
    ], cacheFile: '${dir.path}/cache.tsv');
    addTearDown(() => Fonts.installed = null);
    convert('''
= 字体
:lang: zh-Hans

直骨今

[lang=zh-TW]
直骨今

[lang=ja]
直骨今

[lang=ko]
한국어

Inline [lang=zh-HK]#直骨今#.
''');
    final fonts =
        recordedRunSync(_recorded, 'pdffonts', ['${dir.path}/doc.pdf']).stdout
            as String;
    for (final face in [
      'NotoSerifCJKsc-Regular',
      'NotoSerifCJKtc-Regular',
      'NotoSerifCJKjp-Regular',
      'NotoSerifCJKkr-Regular',
      'NotoSerifCJKhk-Regular',
      // (The title, in the theme's sans.)
      'NotoSansCJKsc-Bold',
    ]) {
      expect(fonts, contains(face));
    }
  });
}
