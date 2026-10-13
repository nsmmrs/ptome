/// Sets one fixture in Ptome and in the free engines it is compared with
/// (TASK-s6bbsz): WeasyPrint (HTML and CSS Paged Media), Typst and
/// ConTeXt, the same text and page in each, and measures what each made
/// of four things paged media asks for:
///
/// - **leaders**: a table of contents whose entries' page numbers line up
///   at the right, dots leading to them;
/// - **running heads**: each page's head, the title of the chapter it is
///   in (CSS's `string-set`, GCPM);
/// - **footnotes**: each note at the foot of the page its reference is on;
/// - **column balancing**: two columns that end level where the text
///   ends, mid-page.
///
/// ```sh
/// dart run tool/oracle_compare.dart [--ptome <exe>] [--typst <exe>] [--keep <dir>]
/// ```
///
/// Writes a Markdown table to standard output (`doc/oracles.md` records
/// one). An engine that isn't installed is left out. It reads the PDFs
/// with poppler's pdftotext.
library;

import 'dart:io';
import 'dart:math' as math;

/// The chapters: a title, paragraphs (`^n` marks footnote n's place), and
/// whether the last ones are set in two balanced columns.
final List<(String, List<String>, bool)> _chapters = [
  (
    'Origins',
    _paragraphsOf('''
The first press in the city was set up in a cellar near the river, and its
owner printed almanacs, sermons and the ordinances of the council for nearly
forty years.^1 Little of that work survives, but what does shows a careful
hand.

Paper came by barge from the mills upstream, and type from a foundry two
days away by road. A single fount of pica served for everything, and its
worn sorts can be traced from one imprint to the next.^2

The council paid well and late. Its accounts record the sheets it ordered
and, a season afterwards, the money it sent, with a clerk's complaint about
the delay in the margin.

When the owner died his widow kept the shop open, and it was under her name
that the press printed its best known book, a herbal with two hundred
cuts.^3
'''),
    false,
  ),
  (
    'The Trade',
    _paragraphsOf('''
By the end of the century there were five shops, and the guild that had
admitted printers grudgingly now counted them among its wealthiest members.
Apprentices served seven years.^4

Each shop kept its own customs: a different way of counting a token, a
different hour for the evening meal, a different saint for the chapel feast.

The booksellers on the bridge took most of what was printed, and their
lists, pasted in the backs of almanacs, are the best record of the trade
that remains.^5

A fire in the hard winter destroyed two of the shops and most of their
stock, and with them the guild's own books.
'''),
    false,
  ),
  (
    'Decline',
    _paragraphsOf('''
The coming of the railway brought cheaper books from the capital, and the
city's presses turned to jobbing work: bills, tickets and the forms of the
new insurance offices.

One shop survived into the last century, printing the parish magazine and
the programmes of the theatre, its old wooden presses kept for show in the
front room.

The last owner gave the presses to the museum, where they stand today beside
the cases of type that fed them.

Visitors may set a line themselves on the first Saturday of each month, and
print it on a card to take home.

The museum keeps the shop's order books too, a run of ledgers that names
nearly every customer for sixty years.
'''),
    true,
  ),
];

/// The paragraphs of [text], blank lines apart, each on one line.
List<String> _paragraphsOf(String text) => [
  for (final p in text.trim().split('\n\n')) p.replaceAll('\n', ' '),
];

/// Paragraphs that run each chapter past its opening page, so that its
/// next pages carry its running head.
final List<String> _filler = _paragraphsOf('''
Records of the period are scattered among the parish chests, the guild's
surviving papers and the letters of the families who owned the shops, and
none of them was kept with the press in mind.

What they show, read together, is a trade that grew slowly, depended on a
handful of customers and was never far from ruin when one of them took its
work elsewhere or failed to pay.

The printers themselves wrote little. A few prefaces, a petition to the
council about the price of paper and one long complaint about a rival are
nearly all that is left in their own words.

Their books speak for them instead: the care taken over a title page, the
ornaments bought at great cost and used for decades, the errata lists that
grew longer as the shops grew busier.

Collectors began to look for the town's imprints only late, when most of the
cheap work had already gone to light fires and line trunks, and their
catalogues are thin as a result.

Even so, enough survives to follow each shop from its first to its last
book, and to see the hands of particular compositors in the way a page was
set.
''');

/// The footnotes, by number.
const Map<int, String> _notes = {
  1: "The council's accounts name him only as the printer.",
  2: 'A broken capital R recurs in eleven imprints.',
  3: 'Two copies are known, one of them incomplete.',
  4: "The guild's register lists forty-one apprentices.",
  5: 'Some forty lists survive, the earliest undated.',
};

/// The page: A5, 20 mm margins, the text 10 on 13.
const String _page = 'A5';

void main(List<String> args) {
  String? option(String name) {
    final i = args.indexOf(name);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  final ptome = option('--ptome') ?? 'ptome';
  final typst = option('--typst') ?? 'typst';
  final keep = option('--keep');
  final dir = keep != null
      ? (Directory(keep)..createSync(recursive: true))
      : Directory.systemTemp.createTempSync('oracles.');
  final engines = <String, String Function()>{
    'Ptome': () => _ptome(dir, ptome),
    'WeasyPrint': () => _weasyprint(dir),
    'Typst': () => _typst(dir, typst),
    'ConTeXt': () => _context(dir),
  };
  final results = <String, _Result>{};
  for (final MapEntry(key: name, value: run) in engines.entries) {
    try {
      final pdf = run();
      results[name] = _measure(pdf);
    } on ProcessException catch (e) {
      stderr.writeln('$name: not installed (${e.executable})');
    } on _Failed catch (e) {
      stderr.writeln('$name: ${e.message}');
    }
  }
  stdout.write(_table(results));
  if (keep == null) dir.deleteSync(recursive: true);
}

final class _Failed implements Exception {
  const new(this.message);
  final String message;
}

String _run(String executable, List<String> args, Directory dir) {
  final result = Process.runSync(executable, args, workingDirectory: dir.path);
  if (result.exitCode != 0) {
    throw _Failed('${result.stdout}${result.stderr}'.trim().split('\n').last);
  }
  return '${result.stdout}';
}

/// The paragraphs of [chapter] with footnote marks as [mark] makes them.
List<String> _texts(
  (String, List<String>, bool) chapter,
  String Function(int n, String note) mark,
) => [
  for (final p in chapter.$2)
    p.replaceAllMapped(
      RegExp(r'\^(\d)'),
      (m) => mark(int.parse(m[1]!), _notes[int.parse(m[1]!)]!),
    ),
];

// The engines.

String _ptome(Directory dir, String exe) {
  final out = StringBuffer(
    "= A Town's Presses\n:doctype: book\n:toc:\n:toc-title: Contents\n"
    ':notitle:\n:sectnums!:\n\n',
  );
  for (final chapter in _chapters) {
    out.write('== ${chapter.$1}\n\n');
    final texts = _texts(chapter, (n, note) => 'footnote:[$note]');
    final split = chapter.$3 ? 1 : texts.length;
    for (final p in [...texts.take(split), ..._filler, ..._filler.reversed]) {
      out.write('$p\n\n');
    }
    if (chapter.$3) {
      out.write('[.columns]\n--\n${texts.skip(split).join('\n\n')}\n--\n\n');
    }
  }
  File('${dir.path}/fixture.adoc').writeAsStringSync('$out');
  File('${dir.path}/fixture-theme.yml').writeAsStringSync('''
extends: default
page:
  size: $_page
  margin: [20mm, 20mm, 20mm, 20mm]
base:
  font_size: 10
  line_pitch: 13
  text_align: justify
heading:
  h2:
    font_size: 14
header:
  height: 15mm
  vertical_align: bottom
  recto: { center: { content: '{chapter-title}' } }
  verso: { center: { content: '{chapter-title}' } }
footer:
  recto: { right: { content: '{page-number}' } }
  verso: { left: { content: '{page-number}' } }
''');
  _run(exe, [
    '-b',
    'pdf',
    '-a',
    'pdf-theme=fixture-theme.yml',
    '-o',
    'ptome.pdf',
    'fixture.adoc',
  ], dir);
  return '${dir.path}/ptome.pdf';
}

String _escape(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

String _weasyprint(Directory dir) {
  final out = StringBuffer('''
<!doctype html><html lang="en"><head><meta charset="utf-8">
<style>
@page { size: $_page; margin: 20mm;
  @top-center { content: string(chapter); font-size: 9pt }
  @bottom-right { content: counter(page); font-size: 9pt } }
body { font: 10pt/13pt serif; text-align: justify; hyphens: auto }
h1 { string-set: chapter content(); break-before: page; font-size: 14pt }
p { margin: 0 0 6pt }
.fn { float: footnote; font-size: 8pt }
nav li { list-style: none }
nav a { text-decoration: none; color: inherit }
nav a::after { content: leader('.') target-counter(attr(href), page) }
.cols { columns: 2; column-gap: 12pt; column-fill: balance }
</style></head><body>
<nav><h2>Contents</h2><ol>
''');
  for (final (i, chapter) in _chapters.indexed) {
    out.write('<li><a href="#c$i">${_escape(chapter.$1)}</a></li>\n');
  }
  out.write('</ol></nav>\n');
  for (final (i, chapter) in _chapters.indexed) {
    out.write('<h1 id="c$i">${_escape(chapter.$1)}</h1>\n');
    final texts = _texts(
      chapter,
      (n, note) => '<span class="fn">${_escape(note)}</span>',
    );
    final split = chapter.$3 ? 1 : texts.length;
    for (final p in [
      ...texts.take(split),
      ..._filler.map(_escape),
      ..._filler.reversed.map(_escape),
    ]) {
      out.write('<p>$p</p>\n');
    }
    if (chapter.$3) {
      out.write('<div class="cols">');
      for (final p in texts.skip(split)) {
        out.write('<p>$p</p>\n');
      }
      out.write('</div>\n');
    }
  }
  out.write('</body></html>\n');
  File('${dir.path}/fixture.html').writeAsStringSync('$out');
  _run('weasyprint', ['fixture.html', 'weasyprint.pdf'], dir);
  return '${dir.path}/weasyprint.pdf';
}

String _typst(Directory dir, String exe) {
  String esc(String s) => s
      .replaceAll(r'\', r'\\')
      .replaceAll('#', r'\#')
      .replaceAll('*', r'\*')
      .replaceAll('_', r'\_')
      .replaceAll('[', r'\[')
      .replaceAll(']', r'\]')
      .replaceAll(r'$', r'\$');
  final out = StringBuffer('''
#set page(paper: "a5", margin: 20mm,
  header: context {
    let hs = query(heading.where(level: 1).before(here()))
    let here-hs = query(heading.where(level: 1)).filter(h => h.location().page() == here().page())
    let h = if here-hs.len() > 0 { here-hs.first() } else if hs.len() > 0 { hs.last() } else { none }
    if h != none { align(center, text(9pt, h.body)) }
  },
  footer: context align(if calc.even(here().page()) { left } else { right }, text(9pt, counter(page).display())))
#set text(size: 10pt, lang: "en")
#set par(justify: true, leading: 3pt, spacing: 6pt)
#show heading.where(level: 1): it => { pagebreak(weak: true); text(14pt, it) }
#outline(title: [Contents])
''');
  for (final chapter in _chapters) {
    out.write('\n= ${esc(chapter.$1)}\n\n');
    final texts = _texts(chapter, (n, note) => '#footnote[${esc(note)}]');
    final split = chapter.$3 ? 1 : texts.length;
    for (final p in [...texts.take(split), ..._filler, ..._filler.reversed]) {
      out.write('${_typstText(p)}\n\n');
    }
    if (chapter.$3) {
      out.write('#columns(2, gutter: 12pt)[\n');
      for (final p in texts.skip(split)) {
        out.write('${_typstText(p)}\n\n');
      }
      out.write(']\n');
    }
  }
  File('${dir.path}/fixture.typ').writeAsStringSync('$out');
  _run(exe, ['compile', 'fixture.typ', 'typst.pdf'], dir);
  return '${dir.path}/typst.pdf';
}

/// A paragraph for Typst: its text escaped, the footnotes as they are.
String _typstText(String p) {
  final parts = p.split(RegExp(r'(?=#footnote\[)|(?<=#footnote\[[^\]]*\])'));
  return [
    for (final part in parts)
      if (part.startsWith('#footnote['))
        part
      else
        part.replaceAll('#', r'\#').replaceAll('*', r'\*'),
  ].join();
}

String _context(Directory dir) {
  final out = StringBuffer(r'''
\setuppapersize[A5]
\setuplayout[topspace=8mm,header=12mm,headerdistance=0mm,backspace=20mm,
  width=middle,height=middle,footer=8mm,footerdistance=0mm,bottomspace=12mm]
\setupbodyfont[serif,10pt]
\setupinterlinespace[line=13pt]
\setupalign[hz,hanging]
\setupwhitespace[6pt]
\setupindenting[no]
\setupheadertexts[chapter]
\setupfootertexts[][pagenumber]
\setuphead[chapter][style=\bfb,page=yes,number=no,header=empty]
\setuplist[chapter][alternative=c]
\starttext
\completecontent[title={Contents}]
''');
  for (final chapter in _chapters) {
    out.write('\\startchapter[title={${chapter.$1}}]\n');
    final texts = _texts(chapter, (n, note) => '\\footnote{$note}');
    final split = chapter.$3 ? 1 : texts.length;
    for (final p in [...texts.take(split), ..._filler, ..._filler.reversed]) {
      out.write('$p\n\n');
    }
    if (chapter.$3) {
      out.write('\\startcolumns[n=2,balance=yes]\n');
      for (final p in texts.skip(split)) {
        out.write('$p\n\n');
      }
      out.write('\\stopcolumns\n');
    }
    out.write('\\stopchapter\n');
  }
  out.write('\\stoptext\n');
  File('${dir.path}/fixture.tex')
      .writeAsStringSync('$out'.replaceAll("'", '’'));
  _run('context', ['--batchmode', '--purgeall', 'fixture.tex'], dir);
  File('${dir.path}/fixture.pdf').renameSync('${dir.path}/context.pdf');
  return '${dir.path}/context.pdf';
}

// Measuring.

typedef _Line = ({
  double xMin,
  double xMax,
  double yMin,
  double yMax,
  String text,
});

final class _Result {
  const new({
    required this.leaders,
    required this.heads,
    required this.openers,
    required this.notes,
    required this.balance,
  });

  /// The table of contents: whether its numbers line up (their right
  /// edges' spread, pt), and whether dots lead to them.
  final (double, bool) leaders;

  /// The running heads: of the pages with text, how many show the
  /// chapter the page is in, and how many pages.
  final (int, int) heads;

  /// The pages that open a chapter: how many have a head, of all.
  final (int, int) openers;

  /// The footnotes: how many are on their reference's page, of all.
  final (int, int) notes;

  /// The two columns: the difference between their last baselines, in
  /// lines (null: no second column found).
  final double? balance;
}

List<List<_Line>> _lines(String pdf) {
  final xml =
      Process.runSync('pdftotext', ['-bbox-layout', pdf, '-']).stdout as String;
  return [
    for (final page in xml.split('<page ').skip(1))
      [
        for (final m in RegExp(
          r'<line xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" '
          r'yMax="([\d.]+)">(.*?)</line>',
          dotAll: true,
        ).allMatches(page))
          (
            xMin: double.parse(m[1]!),
            yMin: double.parse(m[2]!),
            xMax: double.parse(m[3]!),
            yMax: double.parse(m[4]!),
            // (Typographic apostrophes as the fixture's.)
            text: [
              for (final w in RegExp('>([^<]*)</word>').allMatches(m[5]!))
                w[1]!,
            ].join(' ').replaceAll('\u2019', "'").replaceAll('&apos;', "'"),
          ),
      ],
  ];
}

_Result _measure(String pdf) {
  final pages = _lines(pdf);
  final titles = [for (final c in _chapters) c.$1];
  // The table of contents: the page that names every chapter.
  final toc = pages.indexWhere(
    (lines) => titles.every((t) => lines.any((l) => l.text.contains(t))),
  );
  var spread = double.nan;
  var dots = false;
  if (toc >= 0) {
    final entries = [
      for (final l in pages[toc])
        if (titles.any(l.text.contains)) l,
    ];
    final rights = [for (final e in entries) e.xMax];
    spread = rights.reduce(math.max) - rights.reduce(math.min);
    dots = entries.every(
      (e) => e.text.contains('...') || e.text.contains('. .'),
    );
  }
  // The chapter each page is in: the last to start on or before it.
  final starts = <int, String>{};
  for (final (i, lines) in pages.indexed) {
    if (i == toc) continue;
    for (final t in titles) {
      if (lines.any((l) => l.text.trim() == t && !starts.containsValue(t))) {
        starts[i] = t;
      }
    }
  }
  // (The head: what is in the top margin, 20 mm.)
  String head(List<_Line> lines) => [
    for (final l in lines)
      if (l.yMax < 20 / 25.4 * 72) l.text.trim(),
  ].join(' ');
  var right = 0;
  var counted = 0;
  var openers = 0;
  String? current;
  for (final (i, lines) in pages.indexed) {
    if (i == toc || lines.isEmpty) continue;
    current = starts[i] ?? current;
    if (current == null) continue;
    if (starts.containsKey(i)) {
      if (head(lines).isNotEmpty) openers++;
      continue;
    }
    counted++;
    if (head(lines) == current) right++;
  }
  // Footnotes: each note's text on the page whose body has its mark.
  var placed = 0;
  for (final MapEntry(key: n, value: note) in _notes.entries) {
    final words = note.split(' ').take(4).join(' ');
    final notePage = pages.indexWhere(
      (lines) => lines.any((l) => l.text.contains(words)),
    );
    // (The paragraph before the mark: the words just before `^n`.)
    final before = _chapters
        .expand((c) => c.$2)
        .firstWhere((p) => p.contains('^$n'));
    final lead = before
        .substring(0, before.indexOf('^$n'))
        .split(' ')
        .reversed
        .take(3)
        .toList()
        .reversed
        .join(' ');
    // (Letters alone: line ends hyphenate words, however a hyphen reads.)
    String letters(String s) => s.replaceAll(RegExp('[^A-Za-z]'), '');
    final markPage = pages.indexWhere(
      (lines) =>
          letters(lines.map((l) => l.text).join()).contains(letters(lead)),
    );
    if (notePage >= 0 && notePage == markPage) placed++;
  }
  // Columns: on the last chapter's last page, the lines in two groups by
  // their left edge; the difference of their lowest baselines.
  double? balance;
  final last = pages.lastIndexWhere((lines) => lines.length > 3);
  if (last >= 0) {
    final body = [
      for (final l in pages[last])
        if (l.text.split(' ').length > 3) l,
    ];
    if (body.isNotEmpty) {
      final mid =
          (body.map((l) => l.xMin).reduce(math.min) +
              body.map((l) => l.xMax).reduce(math.max)) /
          2;
      final left = body.where((l) => l.xMax < mid + 1).toList();
      final rightColumn = body.where((l) => l.xMin > mid - 1).toList();
      if (left.isNotEmpty && rightColumn.isNotEmpty) {
        final pitch = left.length > 1
            ? (left.last.yMax - left.first.yMax) / (left.length - 1)
            : 13;
        final lowLeft = left.map((l) => l.yMax).reduce(math.max);
        final lowRight = rightColumn.map((l) => l.yMax).reduce(math.max);
        balance = (lowLeft - lowRight).abs() / pitch;
      }
    }
  }
  return _Result(
    leaders: (spread, dots),
    heads: (right, counted),
    openers: (openers, starts.length),
    notes: (placed, _notes.length),
    balance: balance,
  );
}

String _table(Map<String, _Result> results) {
  final out = StringBuffer()
    ..writeln(
      '| Engine | Leaders: numbers aligned (spread), dots | '
      'Running heads: the chapter | Heads on chapter openers | '
      'Footnotes on their page | '
      'Columns balanced (lines apart) |',
    )
    ..writeln('| --- | --- | --- | --- | --- | --- |');
  for (final MapEntry(key: name, value: r) in results.entries) {
    final (spread, dots) = r.leaders;
    final aligned = spread.isNaN
        ? 'no contents found'
        : '${spread.toStringAsFixed(2)} pt';
    out.writeln(
      '| $name | $aligned, '
      '${dots ? 'dots' : 'no dots'} | ${r.heads.$1} of ${r.heads.$2} pages | '
      '${r.openers.$1} of ${r.openers.$2} | '
      '${r.notes.$1} of ${r.notes.$2} | '
      '${r.balance == null ? 'one column' : r.balance!.toStringAsFixed(1)} |',
    );
  }
  return '$out';
}
