// `reproducible`: no dates in the PDF's document information or its XMP
// metadata, as asciidoctor-pdf leaves them out (BUG-d2dtqb).
@TestOn('vm')
library;

import 'dart:convert';

import 'package:ptome/ptome.dart';
import 'package:test/test.dart';

void main() {
  String pdf(Map<String, String> attributes) => latin1.decode(
    asciidoc.convertToBytes(
      'Text.',
      backend: Backend.pdf,
      attributes: {'pdf-theme': 'base', ...attributes},
    ),
  );

  test('with reproducible, no dates', () {
    final text = pdf({'reproducible': ''});
    expect(text, isNot(contains('xmp:CreateDate')));
    expect(text, isNot(contains('xmp:ModifyDate')));
    expect(pdf({'reproducible': ''}), text);
  });

  test('without it, the local date and time', () {
    expect(
      pdf({'localdatetime': '2026-10-14 08:00:00 +0000'}),
      contains('<xmp:CreateDate>2026-10-14T08:00:00Z</xmp:CreateDate>'),
    );
  });
}
