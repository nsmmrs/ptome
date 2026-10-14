// A tagged PDF (ISO 32000-2, 14.7–14.8): content marked as its elements'
// (an MCID each) or as artifacts, the structure tree with each element's
// marked content and links, the parent tree back from the pages, and
// PDF/UA's identification in the XMP metadata.
import 'dart:convert';

import 'package:plain_pdf/plain_pdf.dart';
import 'package:plain_typesetting/plain_typesetting.dart';
import 'package:test/test.dart';

final TextStyle _body = TextStyle(StandardFont.helvetica, 10);

String _save(PdfDocument document) => latin1.decode(
  document.save(
    options: const PdfWriterOptions(compress: false, deterministic: true),
  ),
);

void main() {
  test('content marked as its elements, the structure tree written', () {
    final document = PdfDocument(
      tagged: true,
      language: 'en',
      info: const PdfInfo(title: 'Tagged', pdfuaPart: 1),
    );
    final heading = StructureElement('H1');
    final list = StructureElement('L');
    final item = StructureElement('LI');
    final figure = StructureElement('Figure', alt: 'A red square');
    final page = document.addPage(const Rect(0, 0, 200, 200));
    page.canvas
      ..beginArtifact()
      ..text('running head', 10, 190, _body)
      ..endArtifact()
      ..beginStructure(heading)
      ..text('Title', 10, 170, _body)
      ..endStructure()
      ..beginStructure(list)
      ..beginStructure(item)
      ..save()
      ..text('item', 10, 150, _body)
      ..restore()
      ..endStructure()
      ..endStructure()
      ..beginStructure(figure)
      ..rect(const Rect(10, 100, 20, 20))
      ..fill()
      ..endStructure();
    page.link(const Rect(10, 150, 20, 10), const UriTarget('https://x.org'));
    // (A second page: the list goes on.)
    document.addPage(const Rect(0, 0, 200, 200)).canvas
      ..beginStructure(list)
      ..beginStructure(StructureElement('LI'))
      ..text('more', 10, 170, _body)
      ..endStructure()
      ..endStructure();
    final pdf = _save(document);
    // Each element's content marked with its id on its page; the running
    // head an artifact; a sequence begun inside a save ends before its
    // restore.
    expect(pdf, contains('/Artifact BMC'));
    expect(pdf, contains('/H1 << /MCID 0 >> BDC'));
    expect(pdf, contains('/LI << /MCID 1 >> BDC'));
    expect(
      pdf,
      matches(RegExp(r'/LI << /MCID 1 >> BDC[^Q]*EMC\s+Q', dotAll: true)),
    );
    expect(pdf, contains('/Figure << /MCID 2 >> BDC'));
    expect(pdf, contains('/LI << /MCID 0 >> BDC'));
    // The catalog's marks, the tree, the pages' keys to it.
    expect(pdf, contains('/MarkInfo << /Marked true >>'));
    expect(pdf, contains('/Type /StructTreeRoot'));
    expect(pdf, contains('/StructParents 0'));
    expect(pdf, contains('/StructParents 1'));
    expect(pdf, contains('/Tabs /S'));
    expect(pdf, contains('/S /Document'));
    expect(pdf, contains('/Alt (A red square)'));
    // (The list one element across the pages, its two items.)
    expect(RegExp(r'/S /L\b').allMatches(pdf), hasLength(1));
    expect(RegExp(r'/S /LI\b').allMatches(pdf), hasLength(2));
    // A link a Link element of the element whose text it is, the
    // annotation its object, described, keyed in the parent tree.
    expect(pdf, contains('/S /Link'));
    expect(pdf, contains('/Type /OBJR'));
    expect(pdf, contains('/StructParent 2'));
    expect(pdf, contains('/Contents (https://x.org)'));
    expect(pdf, contains('/ParentTreeNextKey 3'));
    expect(pdf, contains('<pdfuaid:part>1</pdfuaid:part>'));
    expect(pdf, contains('/Lang (en)'));
  });

  test('text in another language marked with its own (14.9.2.2)', () {
    final document = PdfDocument(tagged: true, language: 'en');
    final german = StructureElement('P', language: 'de');
    document.addPage(const Rect(0, 0, 200, 200)).canvas
      ..beginStructure(StructureElement('P'))
      ..text('English ', 10, 170, _body.copyWith(language: 'en'))
      ..text('français', 50, 170, _body.copyWith(language: 'fr'))
      ..text(' again', 90, 170, _body)
      ..endStructure()
      ..beginStructure(german)
      ..text('Deutsch', 10, 150, _body.copyWith(language: 'de'))
      ..text('English', 50, 150, _body.copyWith(language: 'EN'))
      ..endStructure()
      ..beginArtifact()
      ..text('page 1', 10, 10, _body.copyWith(language: 'fr'))
      ..endArtifact();
    final pdf = _save(document);
    // (French in the English paragraph, English in the German one; the
    // German element's own Lang; nothing in an artifact.)
    expect(
      RegExp(r'/Span << /Lang \((\w+)\) >> BDC')
          .allMatches(pdf)
          .map((m) => m[1]),
      ['fr', 'EN'],
    );
    expect(pdf, contains('/Lang (de)'));
  });

  test('an untagged document marks nothing', () {
    final document = PdfDocument();
    document.addPage(const Rect(0, 0, 200, 200)).canvas
      ..beginStructure(StructureElement('P'))
      ..text('text', 10, 170, _body)
      ..endStructure();
    final pdf = _save(document);
    expect(pdf, isNot(contains('BDC')));
    expect(pdf, isNot(contains('StructTreeRoot')));
  });
}
