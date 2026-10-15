// Math drawn on a PDF page (plain_typesetting's math layout in an
// embedded Noto Sans Math), read back by pdftotext (its runs recorded in
// test/oracles/math.json, test/support/oracles.dart; ORACLES=record asks
// it again).
import 'dart:io';

import 'package:plain_math/plain_math.dart';
import 'package:plain_pdf/plain_pdf.dart';
import 'package:plain_typesetting/plain_typesetting.dart';
import 'package:test/test.dart';

import 'support/oracles.dart';
import 'support/pdf_tools.dart';

void main() {
  final recorded = Oracle('math');
  final font = EmbeddedFont.parse(
    File('test/fonts/notosansmath-subset.ttf').readAsBytesSync(),
  );
  final layout = MathLayout(font);
  MathBox box(String mathml, {bool display = false}) =>
      layout.layout(parseMathML(mathml), size: 10, display: display);
  String math(String inner) =>
      '<math xmlns="http://www.w3.org/1998/Math/MathML">$inner</math>';

  test('drawn: identifiers in math italic', () {
    final doc = PdfDocument();
    final page = doc.addPage(const Rect(0, 0, 200, 100));
    box(math('<mi>x</mi><mo>+</mo><mn>1</mn>')).paintAt(page.canvas, 10, 50);
    final text = pdftotext(
      recorded,
      doc.save(options: const PdfWriterOptions(deterministic: true)),
    );
    expect(text.trim(), '\u{1d465}+1');
  });
}
