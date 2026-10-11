// `ptome look explain` (ADR-0023 decision 4): what each item of a look
// became in each output, the drops the compilers warn of, and the command.
@TestOn('vm')
library;

import 'dart:io';

import 'package:ptome/src/cli/look.dart';
import 'package:ptome/src/look/css.dart';
import 'package:ptome/src/look/explain.dart';
import 'package:ptome/src/look/loader.dart';
import 'package:ptome/src/look/model.dart';
import 'package:ptome/src/look/outcome.dart';
import 'package:ptome/src/pdf/look_theme.dart';
import 'package:test/test.dart';

late Directory _dir;

/// A look file [name]-look.yml in the scratch folder.
String _look(String name, String text) {
  File('${_dir.path}/$name-look.yml').writeAsStringSync(text);
  return name;
}

Look _load(String name) => LookLoader(looksDir: _dir.path).load(name);

/// The lines under [item] in [explanation], up to the next item.
List<String> _under(String explanation, String item) {
  final lines = explanation.split('\n');
  final start = lines.indexOf(item);
  expect(start, isNot(-1), reason: '$item not in\n$explanation');
  return [
    for (final line
        in lines.skip(start + 1).takeWhile((l) => l.startsWith(' ')))
      line.trim().replaceAll(RegExp(' {2,}'), '  '),
  ];
}

/// A look that sets what an output can't render, and a token without an
/// e-book value.
const String _awkward = '''
tokens:
  color: { ink: '#111111', accent: { print: '#AA0000', screen: '#CC0000' } }
  measure: 34em
styles:
  paragraph: { keep-with-next: true }
  caption: { rows: { width: 1pt } }
  link: { color: accent }
  subtitle: { color: accent }
  table: { frame: { width: 2pt, color: accent }, frame-sides: none }
''';

void main() {
  setUp(() => _dir = Directory.systemTemp.createTempSync('ptome-look.'));
  tearDown(() => _dir.deleteSync(recursive: true));

  test('the house look, item by item', () {
    final explanation = explainLook(LookLoader().load('ptome'));
    expect(explanation, startsWith('look ptome'));
    expect(_under(explanation, 'tokens.size.text'), [
      'PDF  base_font_size: 10.5',
      'HTML  body{font-size:10.5pt}  (print)',
      'EPUB  — set for print only',
    ]);
    expect(_under(explanation, 'tokens.color.link'), [
      'PDF  — read by the styles that name it',
      'HTML  --ptome-color-link:#2156A5',
      'EPUB  — read by the styles that name it',
    ]);
    expect(_under(explanation, 'styles.link.color'), [
      'PDF  link_font_color: 2156A5',
      'HTML  a{color:var(--ptome-color-link)}',
      'EPUB  body a:link{color:#2156A5}',
    ]);
    // An e-book's alignment and line spacing are the reader's.
    expect(
      _under(explanation, 'tokens.align'),
      contains(startsWith("EPUB  left out: is the reader's in an EPUB")),
    );
    expect(explanation, isNot(contains('warning')));
  });

  test('what an output drops, and the warnings, agree', () {
    final look = _load(_look('awkward', _awkward));
    for (final compile
        in <
          void Function(
            void Function(String) warn,
            void Function(LookOutcome) trace,
          )
        >[
          (warn, trace) => lookThemeEntries(look, warn: warn, trace: trace),
          (warn, trace) =>
              lookCss(look, CssTarget.html, warn: warn, trace: trace),
          (warn, trace) =>
              lookCss(look, CssTarget.epub, warn: warn, trace: trace),
        ]) {
      final warnings = <String>[];
      final outcomes = <LookOutcome>[];
      compile(warnings.add, outcomes.add);
      expect(warnings, isNotEmpty);
      expect(warnings, [
        for (final outcome in outcomes)
          if (outcome case Dropped(:final item, :final why, warned: true))
            'look awkward: $item $why',
      ]);
    }
  });

  test('drops, media and tokens without a value, explained', () {
    final explanation = explainLook(_load(_look('awkward', _awkward)));
    expect(_under(explanation, 'styles.paragraph.keep-with-next'), [
      'PDF  left out: has no effect in the PDF (a warning)',
      'HTML  .paragraph>p{break-after:avoid}',
      '.paragraph>p{page-break-after:avoid}',
      'EPUB  body p{break-after:avoid}',
      'body p{page-break-after:avoid}',
    ]);
    expect(_under(explanation, 'styles.caption.rows'), [
      'PDF  left out: has no effect in the PDF (a warning)',
      'HTML  left out: has no effect in HTML (a warning)',
      'EPUB  left out: has no effect in an EPUB (a warning)',
    ]);
    expect(_under(explanation, 'styles.link.color'), [
      'PDF  link_font_color: AA0000',
      // (The same in print, where the property is print's.)
      'HTML  a{color:var(--ptome-color-accent)}',
      'EPUB  left out: the color token accent has no ebook value',
    ]);
    // (HTML has no separate subtitle: left out by design.)
    expect(
      _under(explanation, 'styles.subtitle.color'),
      contains('HTML  left out: HTML has no such element'),
    );
    expect(_under(explanation, 'tokens.measure'), [
      'PDF  page_measure: 34em',
      'HTML  #header, … (4 more){max-width:34em}  (screen)',
      '#header, … (4 more){max-width:34em}  (print)',
      "EPUB  left out: is the reader's in an EPUB (a warning)",
    ]);
    // A table's frame and its sides make one key, and one declaration:
    // both items name it; the rule's color, a part of the frame, is the
    // frame's.
    expect(
      _under(explanation, 'styles.table.frame'),
      containsAll([
        'PDF  table_border_width: [2, 0]',
        'table_border_color: AA0000',
        'EPUB  left out: the color token accent has no ebook value',
        'table.table-framed-all{border-width:2pt 0}',
      ]),
    );
    expect(
      _under(explanation, 'styles.table.frame-sides'),
      contains('PDF  table_border_width: [2, 0]'),
    );
    expect(explanation, endsWith("can't render.\n"));
  });

  test('each result is in the output it explains', () {
    final look = _load(_look('awkward', _awkward));
    final keys = lookThemeEntries(look).keys.toSet();
    lookThemeEntries(
      look,
      trace: (outcome) {
        if (outcome case Became(:final result)) {
          expect(keys, contains(result.split(':').first));
        }
      },
    );
    for (final target in CssTarget.values) {
      final css = lookCss(look, target);
      lookCss(
        look,
        target,
        trace: (outcome) {
          if (outcome case Became(:final result) when result.contains('{')) {
            final brace = result.indexOf('{');
            expect(css, contains(result.substring(0, brace + 1)));
            expect(
              css,
              contains(result.substring(brace + 1, result.length - 1)),
            );
          }
        },
      );
    }
  });

  group('ptome look', () {
    (int, String, String) run(List<String> args) {
      final out = StringBuffer();
      final err = StringBuffer();
      final status = runLook(args, out: out, err: err);
      return (status, '$out', '$err');
    }

    test('explain a look in its folder, for one output', () {
      _look('awkward', _awkward);
      final (status, out, err) = run([
        'explain',
        '--looksdir=${_dir.path}',
        '--format',
        'pdf',
        'awkward',
      ]);
      expect((status, err), (0, ''));
      expect(out, contains('  PDF  link_font_color: AA0000'));
      expect(out, isNot(contains('HTML')));
      expect(out, isNot(contains('EPUB')));
    });

    test('a list of outputs, and a manual page', () {
      final (status, out, _) = run([
        'explain',
        '--format=html,epub3,manpage',
        'ptome',
      ]);
      expect(status, 0);
      expect(out, startsWith('manpage: a manual page takes no look'));
      expect(out, contains('  HTML  '));
      expect(out, contains('  EPUB  '));
      expect(out, isNot(contains('  PDF  ')));
    });

    test('a look that cannot be read', () {
      _look('broken', 'tokens:\n  colour: {}\n');
      final (status, out, err) = run([
        'explain',
        '--looksdir',
        _dir.path,
        'broken',
      ]);
      expect((status, out), (1, ''));
      expect(err, startsWith('ptome look: '));
      expect(err, contains('broken-look.yml:2:3: '));
    });

    test('help and misuse', () {
      expect(run(['--help']), (0, lookUsage, ''));
      expect(run(['explain', '-h']), (0, lookUsage, ''));
      for (final args in [
        <String>[],
        ['show'],
        ['explain', '--format=docx'],
        ['explain', '--frobnicate'],
        ['explain', 'a', 'b'],
      ]) {
        final (status, out, err) = run(args);
        expect((status, out), (64, ''), reason: '$args');
        expect(err, endsWith(lookUsage));
      }
    });
  });
}
