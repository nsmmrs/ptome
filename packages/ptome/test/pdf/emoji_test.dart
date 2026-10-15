// Emoji in the PDF: an emoji sequence (a flag, a ZWJ sequence, a skin
// tone, a keycap, U+FE0F) set whole in a font with color glyphs (a
// fallback of the theme's, else the installed Noto Color Emoji), drawn
// as that font paints it (plain_pdf's Type 3 color fonts), its text
// read back as it was written; nothing of it under asciidoctor-compat.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:plain_pdf/plain_pdf.dart';
import 'package:ptome/ptome.dart';
import 'package:test/test.dart';

import '../support/oracles.dart';
import '../support/pdf_tools.dart';

/// Noto Color Emoji's COLRv1 build, subset (plain_typesetting's).
final String _emojiFont = File(
  '../plain_typesetting/test/fonts/notocolrv1-subset.ttf',
).absolute.path;

const String _source =
    '= Emoji\n\nHello 😀 👍🏽 👨‍👩‍👧 🇯🇵 🏳️‍🌈 1️⃣ ❤️ world.\n';

/// The tools' runs, recorded (test/oracles/pdf_emoji.json.gz,
/// test/support/oracles.dart; ORACLES=record asks them again).
late final Oracle _recorded;

void main() {
  _recorded = Oracle('pdf_emoji', compressed: true);
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('emoji_test.'));
  tearDown(() => dir.deleteSync(recursive: true));

  /// [source] as a PDF, the theme's fallback font the emoji font.
  Uint8List pdf(String source, {Map<String, String> attributes = const {}}) {
    final theme = File('${dir.path}/theme.yml')
      ..writeAsStringSync('''
extends: default
font:
  catalog:
    merge: true
    Emoji:
      normal: $_emojiFont
      bold: $_emojiFont
      italic: $_emojiFont
      bold_italic: $_emojiFont
  fallbacks: [Emoji]
''');
    return asciidoc.convertToBytes(
      source,
      backend: Backend.pdf,
      attributes: {
        'pdf-theme': theme.path,
        'reproducible': '',
        'nofooter': '',
        ...attributes,
      },
    );
  }

  /// The Type 3 fonts of [bytes].
  int type3Fonts(Uint8List bytes) {
    final file = PdfFile.parse(bytes);
    final size = switch (file.trailer['Size']) {
      PdfInt(:final value) => value,
      _ => 0,
    };
    var count = 0;
    for (var n = 1; n < size; n++) {
      if (file.object(n) case PdfDict(
        entries: {'Subtype': PdfName(value: 'Type3')},
      )) {
        count++;
      }
    }
    return count;
  }

  test("emoji drawn in color from the theme's fallback font", () {
    expect(type3Fonts(pdf(_source)), 1);
  });

  test('pdftotext reads the emoji sequences back as they were written', () {
    final path = '${dir.path}/out.pdf';
    File(path).writeAsBytesSync(pdf(_source));
    final text =
        recordedRunSync(_recorded, 'pdftotext', [
              path,
              '-',
            ], stdoutEncoding: utf8).stdout
            as String;
    expect(text, contains('Hello 😀 👍🏽 👨‍👩‍👧 🇯🇵 🏳️‍🌈 1️⃣ ❤️ world.'));
  });

  test('asciidoctor-compat leaves the variation selectors out', () {
    final path = '${dir.path}/out.pdf';
    File(path)
        .writeAsBytesSync(pdf(_source, attributes: {'asciidoctor-compat': ''}));
    final text =
        recordedRunSync(_recorded, 'pdftotext', [
              path,
              '-',
            ], stdoutEncoding: utf8).stdout
            as String;
    expect(text, isNot(contains('\u{fe0f}')));
  });
}
