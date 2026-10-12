// Page layout, independent of any backend: a box tree laid out on pages
// and rendered into a recording document, whose own page type the
// layout hands back, with anchors, links, decorations and page templates.
import 'dart:io';
import 'dart:math' as math;

import 'package:plain_fonts/plain_fonts.dart';
import 'package:plain_typesetting/plain_typesetting.dart';
import 'package:test/test.dart';

import 'support/recording.dart';

final OpenTypeShaper _serif = OpenTypeShaper(
  OpenTypeFont.parse(
    File('test/fonts/notoserif-regular-latin.ttf').readAsBytesSync(),
  ),
);
final TextStyle _body = TextStyle(_serif, 10);

/// The height of a line of body text.
final double _lineHeight = (_serif.ascender - _serif.descender) / 100;

ParagraphBox _para(String text, {LinkTarget? link}) => ParagraphBox(
  Paragraph([TextRun(text, _body, link: link)]),
  orphans: 1,
  widows: 1,
);

/// A page whose region holds [rows] lines of body text.
PageTemplate _rows(
  double rows, {
  void Function(Canvas canvas, PageInfo page)? background,
  void Function(Canvas canvas, PageInfo page)? foreground,
}) => PageTemplate(
  Rect(0, 0, 300, 40 + rows * _lineHeight),
  margins: const EdgeInsets.all(20),
  background: background,
  foreground: foreground,
);

void main() {
  test('lines go on to the next page, in order', () {
    final document = RecordingDocument();
    final words = [for (var i = 1; i <= 10; i++) 'line$i'];
    final pages = FlowLayout(template: _rows(4))
        .layout([_para(words.join('\n'))])
        .render(document);
    expect(pages, hasLength(3));
    expect(pages, document.pages);
    expect(
      [for (final page in pages) page.texts.map((t) => t.trim()).join(' ')],
      ['line1 line2 line3 line4', 'line5 line6 line7 line8', 'line9 line10'],
    );
  });

  test('a block whose bottom padding is past the page end splits', () {
    // Three rows left for a three-line block: its lines fit, its bottom
    // padding doesn't (and its margin below, larger, goes at the page's
    // end), so its last line goes on to the next page with the padding.
    final document = RecordingDocument();
    final pages = FlowLayout(template: _rows(4))
        .layout([
          _para('first'),
          BlockBox(
            [_para('line1\nline2\nline3')],
            style: BoxStyle(
              padding: EdgeInsets(bottom: _lineHeight / 2),
              margin: EdgeInsets(bottom: _lineHeight),
            ),
          ),
        ])
        .render(document);
    expect(
      [for (final page in pages) page.texts.map((t) => t.trim()).join(' ')],
      ['first line1 line2', 'line3'],
    );
  });

  test("a cell's first margin: dropped, or kept, as measured", () {
    // The y of each line, for a table of one cell whose paragraph has a
    // margin above, with a line after the table.
    Map<String, double> lines({required bool keep}) {
      final document = RecordingDocument();
      FlowLayout(template: _rows(6))
          .layout([
            TableBox(
              [
                TableRow([
                  TableCell([
                    ParagraphBox(
                      Paragraph([TextRun('cell', _body)]),
                      style: const BoxStyle(margin: EdgeInsets(top: 10)),
                    ),
                  ], padding: EdgeInsets.zero),
                ]),
              ],
              columns: const [ColumnWidth.fraction(1)],
              cellsContainMargins: keep,
            ),
            _para('after'),
          ])
          .render(document);
      return {
        for (final call in document.pages.single.canvas.calls)
          if (RegExp(r'^glyphs "\s*(\S+)\s*" at \S+ (\S+)').firstMatch(call)
              case final m?)
            m[1]!: double.parse(m[2]!),
      };
    }

    // Dropped, the cell is as tall as its line (it was measured with the
    // margin it isn't placed with); kept, all is 10 lower.
    final dropped = lines(keep: false);
    expect(
      (dropped['after']! - dropped['cell']!).abs(),
      closeTo(_lineHeight, .01),
    );
    final kept = lines(keep: true);
    expect((kept['after']! - kept['cell']!).abs(), closeTo(_lineHeight, .01));
    expect((kept['cell']! - dropped['cell']!).abs(), closeTo(10, .01));
  });

  test('a block its region cuts the bottom edge off reaches the end', () {
    // Content that fits in a little less room than it takes (as a text
    // box's last line may run its gap below past the room), in a block
    // whose bottom padding then doesn't fit: the block ends at the
    // region's end, not past it, with splitToRegionEnd.
    final region = 4 * _lineHeight;
    final rects = <Rect>[];
    FlowLayout(template: _rows(4))
        .layout([
          BlockBox(
            [CustomBox(_Overrunning(region - 5, slack: 8))],
            style: BoxStyle(
              padding: const EdgeInsets(bottom: 10),
              splitToRegionEnd: true,
              decoration: (page, rect, {required first, required last}) =>
                  rects.add(rect),
            ),
          ),
        ])
        .render(RecordingDocument());
    expect(rects, hasLength(1));
    expect(rects.single.height, closeTo(region, 1e-6));
  });

  test("anchors become the document's, at their page and point", () {
    final document = RecordingDocument();
    final result = FlowLayout(template: _rows(4)).layout([
      _para('a\nb\nc\nd'),
      BlockBox([_para('e')], style: const BoxStyle(anchor: 'second')),
    ])..render(document, destinationName: (anchor) => 'x-$anchor');
    expect(result.pageOf('second'), 2);
    final (page, left, top) = document.anchors['x-second']!;
    expect(page, 1);
    expect(left, 20);
    expect(top, closeTo(document.pages[1].box.top - 20, 1e-6));
  });

  test('as much content as fits with its notes under it', () {
    // Eight rows a page; seven one-line items, each with a one-line note:
    // four items and their notes fill the first page (not seven items with
    // their notes all on the next).
    final document = RecordingDocument();
    final pages =
        FlowLayout(
              template: _rows(8),
              notes: {for (var i = 1; i <= 7; i++) 'n$i': _para('note$i')},
            )
            .layout([
              for (var i = 1; i <= 7; i++)
                BlockBox([_para('item$i')], style: BoxStyle(anchor: 'n$i')),
            ])
            .render(document);
    expect(
      [for (final page in pages) page.texts.map((t) => t.trim()).join(' ')],
      [
        'item1 item2 item3 item4 note1 note2 note3 note4',
        'item5 item6 item7 note5 note6 note7',
      ],
    );
  });

  test('balanced columns: the last region of a set as even as can be', () {
    // Where each line is drawn: its text, x and y.
    Map<String, (double, double)> placed({required bool balance}) {
      final document = RecordingDocument();
      FlowLayout(template: _rows(8))
          .layout([
            ColumnsBox([
              for (var i = 1; i <= 6; i++) _para('l$i'),
            ], balance: balance),
            _para('after'),
          ])
          .render(document);
      return {
        for (final call in document.pages.single.canvas.calls)
          if (RegExp(r'^glyphs "\s*(\S+)\s*" at (\S+) (\S+)').firstMatch(call)
              case final m?)
            m[1]!: (double.parse(m[2]!), double.parse(m[3]!)),
      };
    }

    // Unbalanced, all six lines fit in the first column; balanced, three
    // and three, the paragraph after them right under the third line.
    final plain = placed(balance: false);
    expect(plain['l4']!.$1, plain['l1']!.$1);
    final even = placed(balance: true);
    expect(even['l4']!.$1, greaterThan(even['l1']!.$1));
    expect(even['l4']!.$2, closeTo(even['l1']!.$2, 1e-6));
    expect(even['l6']!.$2, closeTo(even['l3']!.$2, 1e-6));
    expect(even['after']!.$1, even['l1']!.$1);
    expect(even['after']!.$2, lessThan(even['l3']!.$2));
    expect(even['after']!.$2, greaterThan(plain['after']!.$2));
  });

  test('a float that spans the columns goes across the top', () {
    final document = RecordingDocument();
    FlowLayout(template: _rows(8))
        .layout([
          ColumnsBox([
            for (var i = 1; i <= 3; i++) _para('l$i'),
            BlockBox(
              [_para('map')],
              style: const BoxStyle(float: FloatPlacement.top, floatSpan: true),
            ),
            for (var i = 4; i <= 6; i++) _para('l$i'),
          ], balance: true),
        ])
        .render(document);
    final at = {
      for (final call in document.pages.single.canvas.calls)
        if (RegExp(r'^glyphs "\s*(\S+)\s*" at (\S+) (\S+)').firstMatch(call)
            case final m?)
          m[1]!: (double.parse(m[2]!), double.parse(m[3]!)),
    };
    // The map at the top, at the left margin; the columns under it, the
    // lines in their order as if it weren't there.
    expect(at['map']!.$2, greaterThan(at['l1']!.$2));
    expect(at['map']!.$1, at['l1']!.$1);
    expect(at['l4']!.$1, greaterThan(at['l1']!.$1));
    expect(at['l4']!.$2, closeTo(at['l1']!.$2, 1e-6));
  });

  test('numbered lines: where they are on each page, for the template', () {
    final seen = <int, List<TypesetLine>>{};
    final template = PageTemplate(
      Rect(0, 0, 300, 40 + 3 * _lineHeight),
      margins: const EdgeInsets.all(20),
      foreground: (canvas, page) => seen[page.number] = [...page.lines],
    );
    FlowLayout(template: template)
        .layout([
          _para('before'),
          BlockBox([
            _para('a1\na2'),
            _para('b1\nb2'),
          ], style: const BoxStyle(numberLines: true)),
          _para('after'),
        ])
        .render(RecordingDocument());
    // Two numbered lines on the first page, two on the second; the first
    // line of each paragraph starts a line, the next goes on with it.
    expect(seen[1]!.map((l) => l.continues), [false, true]);
    expect(seen[2]!.map((l) => l.continues), [false, true]);
    expect(seen[1]![0].baseline, greaterThan(seen[1]![1].baseline));
    expect(seen[1]![0].left, closeTo(20, 1e-6));
    expect(seen[1]![0].right, greaterThan(20));
  });

  test('on a baseline grid, text lines keep to it past other things', () {
    final document = RecordingDocument();
    final head = ParagraphBox(
      Paragraph([TextRun('Head', TextStyle(_serif, 17))]),
    );
    // The grid: a body line's height apart, the first where a body line
    // at the top of the region has its baseline.
    final body = const FirstFitLineBreaker()
        .breakLines(_para('b0').paragraph, (_) => 1000)
        .single;
    final grid = BaselineGrid(body.height, offset: body.baseline);
    FlowLayout(template: _rows(30), baselineGrid: grid)
        .layout([
          _para('b1'),
          head,
          const SpacerBox(7),
          _para('b2\nb3'),
          const SpacerBox(3.3),
          ColumnsBox([_para('c1\nc2'), head, _para('c3\nc4')], balance: true),
        ])
        .render(document);
    final top = 20 + 30 * _lineHeight;
    var checked = 0;
    for (final call in document.pages.single.canvas.calls) {
      final m = RegExp(r'^glyphs "\s*([bc]\d)\s*" at \S+ (\S+)')
          .firstMatch(call);
      if (m == null) continue;
      final down = top - double.parse(m[2]!) - grid.offset;
      final lines = down / grid.step;
      expect(lines, closeTo(lines.roundToDouble(), 0.01), reason: m[1]);
      checked++;
    }
    expect(checked, 7);
  });

  test('a rule between columns with content, down the taller', () {
    final document = RecordingDocument();
    FlowLayout(template: _rows(8))
        .layout([
          ColumnsBox(
            [for (var i = 1; i <= 3; i++) _para('l$i')],
            count: 3,
            balance: true,
            rule: const ColumnRule(width: 0.25),
          ),
        ])
        .render(document);
    final calls = document.pages.single.canvas.calls;
    // Three columns 78.67 wide, 12 apart: rules 6 left of the second
    // and third.
    final moves = [
      for (final call in calls)
        if (call.startsWith('moveTo ')) call,
    ];
    expect(calls, contains('lineWidth 0.25'));
    expect(moves, hasLength(2));
    expect(double.parse(moves.first.split(' ')[1]), closeTo(104.67, 0.01));
  });

  test(
    'a side float in a column: beside it there, in the next, or in the flow',
    () {
      Map<String, (double, double)> placed(String float, {int before = 0}) {
        final document = RecordingDocument();
        FlowLayout(template: _rows(8))
            .layout([
              ColumnsBox([
                for (var i = 1; i <= before; i++) _para('b$i'),
                BlockBox(
                  [_para(float)],
                  style: const BoxStyle(
                    side: FloatSide.left,
                    sideWidth: 40,
                    sideGap: 6,
                  ),
                ),
                for (var i = 1; i <= 10; i++) _para('l$i'),
              ]),
            ])
            .render(document);
        return {
          for (final call in document.pages.first.canvas.calls)
            if (RegExp(r'^glyphs "\s*(\S+)\s*" at (\S+) (\S+)').firstMatch(call)
                case final m?)
              m[1]!: (double.parse(m[2]!), double.parse(m[3]!)),
        };
      }

      // Two columns 124 wide, 12 apart: the float at the first one's left
      // edge, the lines beside it from 66, then below it from 20; the
      // second column's lines from 156, nothing floating there.
      final beside = placed('s1\ns2');
      expect(beside['s1']!.$1, closeTo(20, 1e-6));
      expect(beside['l1']!.$1, closeTo(66, 1e-6));
      expect(beside['l1']!.$2, closeTo(beside['s1']!.$2, 1e-6));
      expect(beside['l3']!.$1, closeTo(20, 1e-6));
      expect(beside['l10']!.$1, closeTo(156, 1e-6));
      // Taller than the column, it can't go to a side there: set in the
      // flow, the lines after it below it.
      final tall = placed([for (var i = 1; i <= 9; i++) 's$i'].join('\n'));
      expect(tall['s1']!.$1, closeTo(20, 1e-6));
      expect(tall['l1']!.$1, closeTo(156, 1e-6));
      // Too tall for the room left in its column: at the top of the next,
      // the lines after it beside it there.
      final next = placed('s1\ns2\ns3\ns4', before: 6);
      expect(next['b6']!.$1, closeTo(20, 1e-6));
      expect(next['s1']!.$1, closeTo(156, 1e-6));
      expect(next['l1']!.$1, closeTo(202, 1e-6));
    },
  );

  test('side notes beside their lines, pushed down, carried over', () {
    final document = RecordingDocument();
    FlowLayout(
          template: _rows(8),
          sideNotes: {
            'a1': _para('n1'),
            'a2': _para('n2a\nn2b\nn2c'),
            'a3': _para('n3'),
            'a8': _para('n8a\nn8b'),
          },
          sideColumn: (number, template) {
            final size = template.size;
            return Rect(200, 20, 80, size.height - 40);
          },
          sideNoteGap: 0,
        )
        .layout([
          for (var i = 1; i <= 12; i++)
            BlockBox([_para('l$i')], style: BoxStyle(anchor: 'a$i')),
        ])
        .render(document);
    Map<String, double> texts(int page) => {
      for (final call in document.pages[page].canvas.calls)
        if (RegExp(r'^glyphs "\s*(\S+)\s*" at \S+ (\S+)').firstMatch(call)
            case final m?)
          m[1]!: double.parse(m[2]!),
    };
    final first = texts(0);
    final second = texts(1);
    // n1 and n2 level with their lines; n3 under n2 (pushed down from its
    // line); n8, too long for the room left under its line, at the top
    // of the next page.
    expect(first['n1'], first['l1']);
    expect(first['n2a'], first['l2']);
    expect(first['n3'], first['l5']);
    expect(first.containsKey('n8a'), isFalse);
    expect(second['n8a'], second['l9']);
    expect(second['n8b'], second['l10']);
  });

  test('side notes stay above the notes at the bottom of the page', () {
    final document = RecordingDocument();
    FlowLayout(
          template: _rows(8),
          notes: {'a1': _para('foot')},
          sideNotes: {'a5': _para('m5a\nm5b\nm5c'), 'a6': _para('m6')},
          sideColumn: (number, template) =>
              Rect(200, 20, 80, template.size.height - 40),
          sideNoteGap: 0,
        )
        .layout([
          for (var i = 1; i <= 6; i++)
            BlockBox([_para('l$i')], style: BoxStyle(anchor: 'a$i')),
        ])
        .render(document);
    Map<String, double> at(int page) => {
      for (final call in document.pages[page].canvas.calls)
        if (RegExp(r'^glyphs "\s*(\S+)\s*" at \S+ (\S+)').firstMatch(call)
            case final m?)
          m[1]!: double.parse(m[2]!),
    };
    final first = at(0);
    // The footnote on the last row; m5 on the three rows above it, m6
    // (with no room left beside the text) on a page of its own after the
    // text's last.
    expect(first['m5a'], first['l5']);
    expect(first['m5c'], greaterThan(first['foot']!));
    expect(first.containsKey('m6'), isFalse);
    expect(document.pages, hasLength(2));
    expect(at(1).keys, ['m6']);
  });

  test('side notes still waiting when the text ends: pages of their own', () {
    final document = RecordingDocument();
    final result =
        FlowLayout(
            template: _rows(8),
            sideNotes: {
              'a1': _para([for (var i = 1; i <= 12; i++) 'long$i'].join('\n')),
              'a2': _para('after'),
            },
            sideColumn: (number, template) =>
                Rect(200, 20, 80, template.size.height - 40),
            sideNoteGap: 0,
          ).layout([
            for (var i = 1; i <= 2; i++)
              BlockBox([_para('l$i')], style: BoxStyle(anchor: 'a$i')),
          ])
          ..render(document);
    final texts = [
      for (final page in document.pages)
        for (final call in page.canvas.calls)
          if (RegExp(r'^glyphs "\s*(\S+)\s*"').firstMatch(call) case final m?)
            m[1]!,
    ];
    // Every line of the long note, then the one after it: none dropped.
    expect(texts.where((t) => t.startsWith('long')), hasLength(12));
    expect(texts, contains('after'));
    expect(document.pages.length, greaterThan(1));
    expect(result.unsetSideNotes, isEmpty);
  });

  test('a side note no column can take is reported, not dropped silently', () {
    final result =
        FlowLayout(
          template: _rows(8),
          sideNotes: {'a1': _para('wide')},
          // A column with no height.
          sideColumn: (number, template) => const Rect(200, 20, 80, 0),
        ).layout([
          BlockBox([_para('l1')], style: const BoxStyle(anchor: 'a1')),
        ]);
    expect(result.unsetSideNotes, ['a1']);
    expect(result.pageCount, 1);
  });

  test('a side float: blocks beside it, the rest on the next page', () {
    final document = RecordingDocument();
    FlowLayout(template: _rows(8))
        .layout([
          BlockBox([
            _para('head'),
            _para('l1'),
            BlockBox(
              [
                _para([for (var i = 1; i <= 10; i++) 's$i'].join('\n')),
              ],
              style: const BoxStyle(
                side: FloatSide.right,
                sideWidth: 100,
                sideGap: 10,
              ),
            ),
            for (var i = 1; i <= 7; i++) _para('b$i'),
            _para('c1\nc2\nc3'),
          ], repeatedHead: 1),
        ])
        .render(document);
    Map<String, (double, double)> at(int page) => {
      for (final call in document.pages[page].canvas.calls)
        if (RegExp(r'^glyphs "\s*(\S+)\s*" at (\S+) (\S+)').firstMatch(call)
            case final m?)
          m[1]!: (double.parse(m[2]!), double.parse(m[3]!)),
    };
    final first = at(0);
    final second = at(1);
    // The float at the right from the third row, the blocks after it
    // beside it at the left; six of its lines here, four at the top of
    // the next page.
    expect(first['s1']!.$1, closeTo(180, 1e-6));
    expect(first['s1']!.$2, first['b1']!.$2);
    expect(first['b1']!.$1, 20);
    expect(first['s6']!.$2, first['b6']!.$2);
    expect(first.containsKey('s7'), isFalse);
    // The next page: the rest of the float at its top, the repeated head
    // and b7 beside it; c, three lines, doesn't fit in the two rows left
    // beside it, so it starts under it.
    expect(second['s7']!.$1, closeTo(180, 1e-6));
    expect(second['head']!.$2, second['s7']!.$2);
    expect(second['b7']!.$2, second['s8']!.$2);
    expect(second['c1']!.$2, lessThan(second['s10']!.$2));
    expect(second['c1']!.$1, 20);
  });

  test('a block narrowed beside a side float wraps in its width', () {
    final document = RecordingDocument();
    FlowLayout(template: _rows(8))
        .layout([
          BlockBox(
            [_para('s1\ns2\ns3\ns4')],
            style: const BoxStyle(
              side: FloatSide.left,
              sideWidth: 160,
              sideGap: 10,
            ),
          ),
          _para('alpha beta gamma delta epsilon'),
        ])
        .render(document);
    final lines = [
      for (final call in document.pages.single.canvas.calls)
        if (RegExp(r'^glyphs "([^"]*)" at (\S+) (\S+)').firstMatch(call)
            case final m? when !m[1]!.trim().startsWith('s'))
          (m[1]!.trim(), double.parse(m[2]!)),
    ];
    // Beside the float (from x 190 on, 90 wide), the paragraph takes more
    // than one line.
    expect(lines.length, greaterThan(1));
    expect(lines.first.$2, closeTo(190, 1e-6));
  });

  test('a paragraph runs around a side float: beside it, then below', () {
    List<(double, double, double, int)> pieces({required bool around}) {
      final log = <(double, double, double, int)>[];
      FlowLayout(template: _rows(10))
          .layout([
            BlockBox(
              [_para('s1\ns2\ns3')],
              style: const BoxStyle(
                side: FloatSide.right,
                sideWidth: 160,
                sideGap: 10,
              ),
            ),
            CustomBox(_Words(40, log), style: BoxStyle(runsAround: around)),
          ])
          .render(RecordingDocument());
      return log;
    }

    // As many lines as fit beside the float, in the 90 points left of
    // it; the rest set again across the page (260 points) under the
    // float (no line fits in what is left beside it).
    final around = pieces(around: true);
    expect(around, hasLength(2));
    final (x, top, width, lines) = around.first;
    expect((x, width), (20, 90));
    expect(lines, (3 * _lineHeight / _Words.lineHeight).floor());
    expect(around.last.$1, 20);
    expect(around.last.$3, 260);
    // (PDF's y, up the page.)
    expect(around.last.$2, closeTo(top - 3 * _lineHeight, 1e-6));
    // Without: the whole paragraph below the float, at its width.
    final below = pieces(around: false);
    expect(below.single.$3, 260);
    expect(below.single.$2, lessThan(top - 3 * _lineHeight + 1e-6));
  });

  test("a paragraph runs around a float's outline, line by line", () {
    // A float 160 wide, 72 tall, at the right: its outline a triangle, its
    // left edge 20 further right each band of 12 (so the room beside it
    // grows down the page).
    final insets = <double>[];
    FlowLayout(template: _rows(10))
        .layout([
          BlockBox(
            const [SpacerBox(72)],
            style: BoxStyle(
              side: FloatSide.right,
              sideWidth: 160,
              sideGap: 10,
              sideShape: FloatShape(12, [
                for (var i = 0; i < 6; i++) (i * 20.0, 160.0),
              ]),
            ),
          ),
          CustomBox(
            _ShapedWords(60, insets),
            style: const BoxStyle(runsAround: true),
          ),
        ])
        .render(RecordingDocument());
    // Beside each band, the room it leaves (the float's left at 100 +
    // 20 per band, less the gap): 270 - 100 - 20 i + 10 at the right.
    expect(insets.take(6), [for (var i = 0; i < 6; i++) 170.0 - 20 * i]);
  });

  test('links are made on the page the text is on', () {
    final document = RecordingDocument();
    FlowLayout(template: _rows(4))
        .layout([_para('see', link: const LinkTarget.named('there'))])
        .render(document);
    expect(document.pages.single.links.single, endsWith('-> #there'));
  });

  test('the header is painted before the content, or after it', () {
    // The texts drawn on the page, in order, the header in its margin.
    List<String> drawn({required bool over}) {
      final document = RecordingDocument();
      FlowLayout(
        template: PageTemplate(
          const Rect(0, 0, 300, 200),
          margins: const EdgeInsets.all(40),
          header: (page) => [_para('header')],
          runningOver: over,
        ),
      ).layout([_para('body')]).render(document);
      return [for (final t in document.pages.single.texts) t.trim()];
    }

    expect(drawn(over: false), ['header', 'body']);
    expect(drawn(over: true), ['body', 'header']);
  });

  test('templates and decorations paint on the pages the layout made', () {
    final document = RecordingDocument();
    final order = <String>[];
    final decorated = <LayoutPage>[];
    FlowLayout(
          template: _rows(
            4,
            background: (canvas, page) =>
                order.add('background ${page.number}'),
            foreground: (canvas, page) =>
                order.add('foreground ${page.number}'),
          ),
        )
        .layout([
          BlockBox(
            [_para('a\nb\nc\nd\ne')],
            style: BoxStyle(
              decoration: (page, rect, {required first, required last}) =>
                  decorated.add(page),
            ),
          ),
        ])
        .render(document);
    expect(order, [
      'background 1',
      'foreground 1',
      'background 2',
      'foreground 2',
    ]);
    // The block is split: a piece on each page, decorated there.
    expect(decorated, document.pages);
  });
}

/// Content [height] tall that is placed whole in [slack] less room.
final class _Overrunning implements CustomContent {
  const new(this.height, {required this.slack});

  final double height;
  final double slack;

  @override
  CustomPlacement? place(
    double width,
    double available, {
    required bool atTop,
  }) => available + slack >= height || atTop
      ? CustomPlacement(height: height, paint: (page, x, top) {})
      : null;

  @override
  double minHeight(double width) => height;

  @override
  (double, double) intrinsicWidths() => (0, 0);
}

/// [words] words of [wordWidth] each on lines of [lineHeight], set at any
/// width from word [from] on; each piece placed logged (x, top, width,
/// lines).
base class _Words implements CustomContent {
  new(this.words, this.log, {this.from = 0});

  static const double lineHeight = 12;
  static const double wordWidth = 30;

  final int words;
  final List<(double, double, double, int)> log;
  final int from;

  @override
  CustomPlacement? place(
    double width,
    double available, {
    required bool atTop,
  }) {
    final perLine = math.max(1, (width / wordWidth).floor());
    final total = ((words - from) / perLine).ceil();
    var lines = math.min(total, (available / lineHeight + 1e-6).floor());
    if (lines == 0) {
      if (!atTop) return null;
      lines = 1;
    }
    final next = from + lines * perLine;
    return CustomPlacement(
      height: lines * lineHeight,
      rest: next < words ? _Words(words, log, from: next) : null,
      paint: (page, x, top) => log.add((x, top, width, lines)),
    );
  }

  @override
  double minHeight(double width) => lineHeight;

  @override
  (double, double) intrinsicWidths() => (wordWidth, words * wordWidth);
}

/// [words] words of [_Words.wordWidth] on lines of [_Words.lineHeight],
/// set around a float's outline: the right inset of each line placed is
/// logged in [insets].
final class _ShapedWords extends _Words implements ShapedContent {
  new(int words, this.insets) : super(words, []);

  final List<double> insets;

  @override
  CustomPlacement? placeAround(
    double width,
    double available, {
    required bool atTop,
    required (double, double) Function(double top, double bottom) insets,
  }) {
    var next = from;
    var lines = 0;
    while (next < words &&
        (lines + 1) * _Words.lineHeight <= available + 1e-6) {
      final (left, right) = insets(
        lines * _Words.lineHeight,
        (lines + 1) * _Words.lineHeight,
      );
      this.insets.add(right);
      next += math.max(1, ((width - left - right) / _Words.wordWidth).floor());
      lines++;
    }
    if (lines == 0) return null;
    return CustomPlacement(
      height: lines * _Words.lineHeight,
      rest: next < words ? _Words(words, [], from: next) : null,
      paint: (page, x, top) {},
    );
  }
}
