// The logical structure the flow paints on a structure canvas: a tagged
// box's content between its element's begin and end, a tagged table's
// rows and cells as TR and TH or TD, a repeated header and the page
// template's content as artifacts.
import 'dart:io';

import 'package:plain_fonts/plain_fonts.dart';
import 'package:plain_typesetting/plain_typesetting.dart';
import 'package:test/test.dart';

final OpenTypeShaper _serif = OpenTypeShaper(
  OpenTypeFont.parse(
    File('test/fonts/notoserif-regular-latin.ttf').readAsBytesSync(),
  ),
);
final TextStyle _body = TextStyle(_serif, 10);

/// A canvas recording the structure painted on it and the text drawn.
final class _Structured implements StructureCanvas {
  final List<String> calls = [];

  @override
  void beginStructure(StructureElement element) =>
      calls.add('<${element.role}>');

  @override
  void endStructure() => calls.add('</>');

  @override
  void beginArtifact() => calls.add('<artifact>');

  @override
  void endArtifact() => calls.add('</artifact>');

  @override
  double glyphs(List<ShapedGlyph> glyphs, double x, double y, TextStyle s) {
    calls.add(glyphs.map((g) => g.text).join());
    return 0;
  }

  @override
  Object? noSuchMethod(Invocation invocation) =>
      invocation.memberName == #text ? 0.0 : null;
}

/// [calls] joined, the empty artifacts (a template's nothing) left out.
String _joined(List<String> calls) =>
    calls.join(' ').replaceAll(RegExp('<artifact> </artifact> ?'), '').trim();

final class _Page implements LayoutPage {
  @override
  final _Structured canvas = _Structured();

  @override
  void link(Rect rect, LinkTarget target) {}
}

final class _Document implements LayoutDocument<_Page> {
  final List<_Page> pages = [];

  @override
  _Page addPage(Rect mediaBox, {Rect? bleedBox, Rect? trimBox}) {
    final page = _Page();
    pages.add(page);
    return page;
  }

  @override
  Object? noSuchMethod(Invocation invocation) => null;
}

ParagraphBox _para(String text, {StructureElement? element}) => ParagraphBox(
  Paragraph([TextRun(text, _body)]),
  style: BoxStyle(structure: element),
);

void main() {
  test("tagged boxes' content between their elements' begin and end", () {
    final document = _Document();
    FlowLayout(
          template: PageTemplate(
            const Rect(0, 0, 300, 400),
            margins: const EdgeInsets.all(30),
            footer: (page) => [_para('${page.number}')],
          ),
        )
        .layout([
          _para('Heading', element: StructureElement('H1')),
          BlockBox([
            BlockBox([
              _para('item', element: StructureElement('P')),
            ], style: BoxStyle(structure: StructureElement('LI'))),
          ], style: BoxStyle(structure: StructureElement('L'))),
          _para('untagged'),
        ])
        .render(document);
    expect(
      _joined(document.pages.single.canvas.calls),
      '<H1> Heading </> <L> <LI> <P> item </> </> </> untagged '
      '<artifact> 1 </artifact>',
    );
  });

  test("a tagged table's rows and cells, its repeated header artifacts", () {
    TableCell cell(String text) => TableCell([_para(text)]);
    final document = _Document();
    FlowLayout(
          template: const PageTemplate(
            Rect(0, 0, 300, 70),
            margins: EdgeInsets.all(10),
          ),
        )
        .layout([
          TableBox(
            [
              TableRow([cell('h1'), cell('h2')]),
              for (var i = 1; i <= 3; i++) TableRow([cell('a$i'), cell('b$i')]),
            ],
            columns: const [ColumnWidth.fraction(1), ColumnWidth.fraction(1)],
            headerRows: 1,
            style: BoxStyle(structure: StructureElement('Table')),
          ),
        ])
        .render(document);
    final pages = [
      for (final page in document.pages) _joined(page.canvas.calls),
    ];
    expect(pages.length, greaterThan(1));
    // (Each cell its row's, a header cell a TH.)
    expect(pages.first, startsWith('<Table> <TR> <TH> h1 </> </>'));
    expect(pages.first, contains('<TR> <TD> a1 </> </>'));
    // (On the next page, the header again as an artifact.)
    expect(pages[1], contains('<artifact> h1 </artifact>'));
  });
}
