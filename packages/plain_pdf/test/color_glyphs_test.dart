// Color glyphs in the PDF (COLR/CPAL, CBDT, sbix): a Type 3 font whose
// glyph procedures paint each glyph's form, text that reads back as the
// text set; and the pages they make against HarfBuzz's own painting
// (hb-cairo, tool/oracles/harfbuzz-cairo), rasterized by Poppler, every
// color glyph of the color test fonts (plain_typesetting's).
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:plain_pdf/plain_pdf.dart';
import 'package:plain_typesetting/plain_typesetting.dart';
import 'package:test/test.dart';

bool _has(String tool) => Process.runSync('which', [tool]).exitCode == 0;

/// Poppler's pdftotext (Git for Windows ships xpdf's, whose text
/// extraction differs).
final bool _poppler =
    _has('pdftotext') &&
    '${Process.runSync('pdftotext', ['-v']).stderr}'.contains('Poppler');

const String _fonts = '../plain_typesetting/test/fonts';
const String _render = 'tool/oracles/harfbuzz-cairo/hb-render';

EmbeddedFont _font(String name) =>
    EmbeddedFont.parse(File('$_fonts/$name').readAsBytesSync());

/// The pixels of the binary PPM at [path].
Uint8List _ppm(String path) {
  final bytes = File(path).readAsBytesSync();
  var lines = 0;
  var at = 0;
  while (lines < 3) {
    if (bytes[at++] == 10) lines++;
  }
  return Uint8List.sublistView(bytes, at);
}

void main() {
  final ready = Directory(_fonts).existsSync();

  test('a Type 3 font paints them; text reads back as it was set', () {
    final document = PdfDocument();
    final canvas = document.addPage(const Rect(0, 0, 400, 200)).canvas;
    final emoji = _font('notocolrv1-subset.ttf');
    final style = TextStyle(emoji, 20, ligatures: true);
    final colr = _font('colr-test.ttf');
    canvas
      ..text('😀 👍🏽 👨‍👩‍👧 🇯🇵 🏳️‍🌈 1️⃣ ❤️', 10, 150, style)
      ..text(
        String.fromCharCodes([for (var c = 0x1F600; c <= 0x1F60F; c++) c]),
        10,
        100,
        TextStyle(colr, 20),
      )
      ..text('😀', 10, 50, TextStyle(_font('notocoloremoji-subset.ttf'), 20));
    final pdf = latin1.decode(
      document.save(options: const PdfWriterOptions(compress: false)),
    );
    expect(pdf, contains('/Subtype /Type3'));
    expect(pdf, contains(' 0 d0'));
    // (A composite in the source's alpha, and a blend mode.)
    expect(pdf, contains('/S /Alpha'));
    expect(pdf, contains('/BM /Multiply'));
    // (A gradient: a shading; a bitmap: an image.)
    expect(pdf, contains('/ShadingType 2'));
    expect(pdf, contains('/Subtype /Image'));
    // (The ToUnicode maps read the codes as the emoji sequences.)
    expect(pdf, contains('<D83DDC68200DD83DDC69200DD83DDC67>'));
  }, skip: ready ? false : 'needs the color test fonts');

  test(
    'pdftotext reads them back',
    () {
      final dir = Directory.systemTemp.createTempSync('color.');
      addTearDown(() => dir.deleteSync(recursive: true));
      final document = PdfDocument();
      final canvas = document.addPage(const Rect(0, 0, 400, 100)).canvas;
      // (No spaces: an emoji font's are wide, words apart to Poppler.)
      const text = '😀👍🏽👨‍👩‍👧🇯🇵🏳️‍🌈1️⃣❤️🐻‍❄️';
      for (final (i, name) in [
        'notocolrv1-subset.ttf',
        'notocoloremoji-subset.ttf',
      ].indexed) {
        canvas.text(
          text,
          10,
          70 - 40.0 * i,
          TextStyle(_font(name), 12, ligatures: true),
        );
      }
      final path = '${dir.path}/emoji.pdf';
      File(path).writeAsBytesSync(document.save());
      final out = Process.runSync('pdftotext', [
        path,
        '-',
      ], stdoutEncoding: utf8);
      expect(
        const LineSplitter()
            .convert('${out.stdout}')
            .where((l) => l.trim().isNotEmpty),
        [text, text],
      );
    },
    skip: !ready
        ? 'needs the color test fonts'
        : _poppler
        ? false
        : "needs Poppler's pdftotext",
  );

  for (final name in [
    'notocolrv1-subset.ttf',
    'colr-test.ttf',
    'notocoloremoji-subset.ttf',
    'sbix-test.ttf',
  ]) {
    test(
      'every color glyph of $name as HarfBuzz paints it',
      () {
        final dir = Directory.systemTemp.createTempSync('color.');
        addTearDown(() => dir.deleteSync(recursive: true));
        const em = 64.0;
        final font = _font(name);
        final colors = font.font.colorGlyphs!;
        final glyphs = [
          for (var g = 0; g < font.font.numGlyphs; g++)
            if (colors.hasGlyph(g)) g,
        ];
        // Ours: a page of 2 ems a glyph, its origin half an em in.
        final document = PdfDocument();
        for (final g in glyphs) {
          document
              .addPage(const Rect(0, 0, 2 * em, 2 * em))
              .canvas
              .glyphs(
                [ShapedGlyph(g, '', 0)],
                em / 2,
                em / 2,
                TextStyle(font, em),
              );
        }
        File('${dir.path}/ours.pdf').writeAsBytesSync(document.save());
        Process.runSync('pdftoppm', [
          '-r',
          '72',
          '${dir.path}/ours.pdf',
          '${dir.path}/ours',
        ]);
        final r = Process.runSync('sh', [
          '-c',
          r'printf "%s\n" $2 | "$0" "$1" 64 "$3"',
          _render,
          '$_fonts/$name',
          glyphs.join(' '),
          dir.path,
        ]);
        expect(r.exitCode, 0, reason: '${r.stderr}');
        // Each pixel's largest difference in a channel: on average and
        // how many differ by more than a quarter, as rasterizers'
        // antialiasing (and bitmaps' resampling) differ.
        final bitmaps = name.contains('emoji-') || name.startsWith('sbix');
        final differ = <String>[];
        final digits = '${glyphs.length}'.length;
        for (final (i, g) in glyphs.indexed) {
          final ours = _ppm(
            '${dir.path}/ours-${'${i + 1}'.padLeft(digits, '0')}.ppm',
          );
          final theirs = _ppm('${dir.path}/$g.ppm');
          var sum = 0;
          var far = 0;
          final pixels = ours.length ~/ 3;
          for (var p = 0; p < pixels; p++) {
            var d = 0;
            for (var c = 0; c < 3; c++) {
              final x = (ours[3 * p + c] - theirs[3 * p + c]).abs();
              if (x > d) d = x;
            }
            sum += d;
            if (d > 64) far++;
          }
          final mean = sum / pixels;
          final share = far / pixels;
          if (mean > (bitmaps ? 8 : 4) || share > (bitmaps ? 0.05 : 0.02)) {
            differ.add(
              'glyph $g: mean ${mean.toStringAsFixed(2)}, '
              '${(100 * share).toStringAsFixed(2)}% far',
            );
          }
        }
        expect(differ, isEmpty);
      },
      tags: ['pdf-tools'],
      skip: !ready
          ? 'needs the color test fonts'
          : !File(_render).existsSync()
          ? 'run tool/oracles/harfbuzz-cairo/setup.sh'
          : _has('pdftoppm')
          ? false
          : 'needs pdftoppm',
    );
  }
}
