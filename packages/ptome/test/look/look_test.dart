// Looks (ADR-0023): the loader's model and its errors, the extends chain,
// and the house look's PDF theme against the theme it replaced.
@TestOn('vm')
library;

import 'dart:io';

import 'package:ptome/src/look/css.dart';
import 'package:ptome/src/look/loader.dart';
import 'package:ptome/src/look/model.dart';
import 'package:ptome/src/pdf/look_theme.dart';
import 'package:ptome/src/pdf/theme.dart';
import 'package:ptome/src/pdf/yaml11.dart';
import 'package:test/test.dart';

import '../../tool/style_table.dart' show withValues;

late Directory _dir;

/// A look file [name]-look.yml in the scratch folder.
String _look(String name, String text) {
  File('${_dir.path}/$name-look.yml').writeAsStringSync(text);
  return name;
}

Look _load(String name) => LookLoader(looksDir: _dir.path).load(name);

void main() {
  setUp(() => _dir = Directory.systemTemp.createTempSync('ptome-look.'));
  tearDown(() => _dir.deleteSync(recursive: true));

  test('the house look compiles to the theme it replaced, key for key', () {
    final warnings = <String>[];
    final compiled = lookTheme(LookLoader().load('ptome'), warn: warnings.add);
    final before = ThemeLoader().loadFile(
      'test/look/ptome-theme-before-looks.yml',
    );
    expect(warnings, isEmpty);
    final keys = {...compiled.keys, ...before.keys};
    final differences = [
      for (final key in keys)
        if ('${compiled[key]}' != '${before[key]}')
          '$key: ${compiled[key]}, was ${before[key]}',
    ];
    expect(differences, isEmpty, reason: differences.join('\n'));
  });

  test('a look extends another: later values win, null removes one', () {
    _look('base', '''
tokens:
  color: { ink: '#111111', link: '#2156A5' }
  size: { text: 10pt }
styles:
  .dek: { size: 1.25, style: italic }
''');
    _look('child', '''
extends: base
tokens:
  color: { ink: '#222', link: ~ }
styles:
  .dek: { style: normal }
''');
    final look = _load('child');
    expect(look.name, 'child');
    expect(look.tokens.colors.keys, ['ink']);
    expect(
      look.tokens.colors['ink']?.of(Medium.screen),
      const LookColor('222222'),
    );
    expect(
      look.tokens.textSize?.of(Medium.print),
      const Length(10, LengthUnit.pt),
    );
    final dek = look.styles[const RoleTarget('dek')]!;
    expect(dek.shape?.all, FontShape.normal);
    expect(switch (dek.size?.all) {
      SizeRatio(:final ratio) => ratio,
      _ => null,
    }, 1.25);
  });

  test('a value by medium: each medium its own, or all', () {
    _look('media', '''
tokens:
  leading: { print: 1.4, screen: 1.6 }
  align: justify
''');
    final tokens = _load('media').tokens;
    expect(tokens.leading?.of(Medium.print), 1.4);
    expect(tokens.leading?.of(Medium.screen), 1.6);
    expect(tokens.leading?.of(Medium.ebook), isNull);
    expect(tokens.align?.of(Medium.ebook), Alignment.justify);
  });

  group('errors name the item, with its line and column', () {
    void fails(String text, Matcher message) {
      _look('bad', text);
      expect(
        () => _load('bad'),
        throwsA(isA<LookException>().having((e) => '$e', 'message', message)),
      );
    }

    test('an unknown token', () {
      fails(
        'tokens:\n  colour: { ink: "#000" }\n',
        allOf(contains('bad-look.yml:2:3'), contains('unknown tokens.colour')),
      );
    });

    test('a length without its unit', () {
      fails(
        'tokens:\n  size: { text: 10.5 }\n',
        allOf(contains(':2:17'), contains('tokens.size.text is a length')),
      );
    });

    test('a color YAML reads as a number', () {
      fails(
        'tokens:\n  color: { ink: 191919 }\n',
        contains("tokens.color.ink is a color: '#RRGGBB'"),
      );
    });

    test('an unknown element', () {
      fails(
        'styles:\n  dek: { size: 1.25 }\n',
        contains('unknown element dek (a role starts with a dot: .dek'),
      );
    });

    // Each kind of mistake, with what the error says.
    for (final (text, message) in [
      ('- a list\n', 'a look is a mapping'),
      ('colours: {}\n', 'unknown part colours'),
      ('pdf: 3\n', 'pdf is a mapping of theme keys'),
      ('css: [a]\n', 'css is a string'),
      ('tokens: 3\n', 'tokens is a mapping'),
      ('tokens:\n  font: { text: 3 }\n', 'tokens.font.text is a mapping'),
      (
        'tokens:\n  size: { headings: 26pt }\n',
        'tokens.size.headings is a list',
      ),
      ('tokens:\n  leading: -1\n', 'tokens.leading is a positive number'),
      ('tokens:\n  hyphenate: maybe\n', 'tokens.hyphenate is true or false'),
      ('tokens:\n  align: middle\n', 'tokens.align is one of start'),
      ('tokens:\n  page: { margin: [1in, 1in, 1in] }\n', '1, 2 or 4 lengths'),
      (
        'tokens:\n  leading: { print: 1.4, paper: 1.2 }\n',
        'unknown medium tokens.leading.paper',
      ),
      ('styles:\n  heading: { weight: 650 }\n', 'normal, bold or a weight'),
      ('styles:\n  heading: { border: { color: ink } }\n', 'has no width'),
      ('styles:\n  heading: { border: thick }\n', 'is none or { width'),
      ('styles:\n  heading: { color: 3 }\n', "a color token's name"),
      ('styles:\n  heading: { size: [1] }\n', 'is a single value'),
      ('styles:\n  heading: { font: { family: x } }\n', 'styles.heading.font'),
      ('styles:\n  heading: { tint: x }\n', 'unknown styles.heading.tint'),
      ('extends: nowhere\n', 'no look named nowhere'),
    ]) {
      test(message, () => fails(text, contains(message)));
    }

    test('a look that extends itself', () {
      fails('extends: bad\n', contains('extends itself'));
    });
  });

  test('what the PDF cannot render is reported, by item', () {
    _look('screen', '''
tokens:
  leading: { screen: 1.6 }
styles:
  paragraph: { keep-with-next: true }
  .dek: { rows: none }
templates:
  footnote-reference: '{{number}}'
''');
    final warnings = <String>[];
    lookThemeEntries(_load('screen'), warn: warnings.add);
    expect(warnings, [
      contains('styles.paragraph.keep-with-next has no effect in the PDF'),
      contains('styles..dek.rows has no effect in the PDF'),
      contains('templates.footnote-reference has no effect in the PDF'),
    ]);
  });

  group('CSS', () {
    test("the house look's screen rules are the house stylesheet's", () {
      final css = lookCss(LookLoader().load('ptome'), CssTarget.html);
      final screen = css.substring(0, css.indexOf('@media print'));
      expect(
        screen,
        allOf(
          contains(
            '@media screen{#header,#content,#footnotes,#footer'
            '{max-width:42em}}',
          ),
          contains(
            'h1,h2,h3,#toctitle,.sidebarblock>.content>.title,h4,h5,h6'
            '{font-weight:600;color:var(--ptome-color-ink-strong)}',
          ),
          contains('--ptome-color-ink-strong:#191919'),
          contains('.listingblock pre,.literalblock pre{border:0}'),
          contains('table.frame-all{border-width:var(--ptome-rule-heavy) 0}'),
        ),
      );
      // The print values in print alone.
      expect(screen, isNot(contains('10.5pt')));
      expect(css, contains('@media print{'));
    });

    test('a role and a value by medium, in HTML and an EPUB', () {
      _look('dek', '''
tokens:
  color: { accent: '#AA0000' }
styles:
  .dek: { size: 1.25, style: italic, color: accent, weight: { screen: 300 } }
''');
      final look = _load('dek');
      final html = lookCss(look, CssTarget.html);
      expect(
        html,
        contains(
          '.dek{font-weight:300;font-style:italic;font-size:1.25em;'
          'color:var(--ptome-color-accent)}',
        ),
      );
      final epub = lookCss(look, CssTarget.epub);
      expect(
        epub,
        contains('.dek{font-style:italic;font-size:1.25em;color:#AA0000}'),
      );
    });

    test("an e-book's body text is the reader's unless the look says", () {
      final reader = lookCss(LookLoader().load('ptome'), CssTarget.epub);
      expect(reader, contains('{text-align:inherit}'));
      expect(reader, contains('body{line-height:normal}'));
      expect(reader, contains('hyphens:auto'));
      _look('set', '''
tokens:
  leading: { ebook: 1.5 }
  align: { ebook: justify }
''');
      final set = lookCss(_load('set'), CssTarget.epub);
      expect(set, contains('body{line-height:1.5;text-align:justify}'));
      expect(set, isNot(contains('text-align:inherit')));
      expect(set, isNot(contains('line-height:normal')));
    });
  });

  group('title pages', () {
    const look = '''
templates:
  title-page:
    recto:
      - { slot: authors, space-before: { print: 1in, screen: 2em }, separator: ' & ' }
      - title
      - subtitle
      - { attribute: publisher, style: .publisher, space-after: 6pt }
    verso:
      - { attribute: copyright }
      - { slot: revision, before: 'Edition: ' }
''';

    test('slots: parts by name, or what they show and how', () {
      final page = _load(_look('tp', look)).templates.titlePage!;
      expect(
        [for (final slot in page.recto) '${slot.content}'],
        ['authors', 'title', 'subtitle', 'attribute publisher'],
      );
      final authors = page.recto.first;
      expect(authors.separator, ' & ');
      expect('${authors.spaceBefore?.of(Medium.print)}', '1in');
      expect('${authors.spaceBefore?.of(Medium.screen)}', '2em');
      expect(page.recto.last.role, 'publisher');
      expect(page.verso.last.before, 'Edition: ');
      // A look that extends it may give a verso alone.
      _look('child', 'extends: tp\ntemplates:\n  title-page:\n    verso: ~\n');
      final child = _load('child').templates.titlePage!;
      expect(child.recto, hasLength(4));
      expect(child.verso, isEmpty);
      expect(_load('child').templates.named, isEmpty);
    });

    test("the PDF's title_page_recto and title_page_verso", () {
      final entries = lookThemeEntries(_load(_look('tp', look)));
      late String Function(MapEntry<String, Y>) entry;
      String show(Y value) => switch (value) {
        YScalar(:final value) => value.rubyString,
        YList(:final items) => '[${items.map(show).join(', ')}]',
        YMap(:final entries) => '{${entries.entries.map(entry).join(', ')}}',
      };
      entry = (e) => '${e.key}: ${show(e.value)}';
      expect(
        show(entries['title_page_recto']!),
        '[{content: authors, margin_top: 1in, separator:  &amp; }, title, '
        'subtitle, {attribute: publisher, role: publisher, margin_bottom: 6}]',
      );
      expect(
        show(entries['title_page_verso']!),
        '[{attribute: copyright}, {content: revision, before: Edition: }]',
      );
    });

    test('CSS: the space around slots, by medium; a verso on its page', () {
      final page = _load(_look('tp', look));
      final html = lookCss(page, CssTarget.html);
      expect(html, contains('#header .title-page-authors{margin-top:2em}'));
      expect(
        html,
        contains(
          '@media print{'
          '#header .title-page-authors{margin-top:1in}',
        ),
      );
      expect(
        html,
        contains('#header .title-page-publisher{margin-bottom:6pt}'),
      );
      expect(html, contains('#header>.verso{break-before:page'));
      final epub = lookCss(page, CssTarget.epub);
      expect(
        epub,
        contains('.titlepage .title-page-publisher{margin-bottom:6pt}'),
      );
      expect(epub, contains('.titlepage.verso{break-before:page'));
      expect(epub, isNot(contains('title-page-authors{')));
    });

    group('errors', () {
      void fails(String slots, Matcher message) {
        _look('bad', 'templates:\n  title-page:\n    recto:\n$slots');
        expect(
          () => _load('bad'),
          throwsA(isA<LookException>().having((e) => '$e', 'message', message)),
        );
      }

      test('an unknown part', () {
        fails(
          '      - colophon\n',
          allOf(
            contains('bad-look.yml:4:9'),
            contains('unknown templates.title-page.recto[0] colophon'),
          ),
        );
      });
      test('a part and an attribute both', () {
        fails(
          '      - { slot: title, attribute: x }\n',
          contains(
            'shows a part (slot: title, subtitle, authors, revision, '
            'logo) or an attribute',
          ),
        );
      });
      test('a style without its dot', () {
        fails(
          '      - { slot: title, style: big }\n',
          contains('recto[0].style is a role, written with its dot'),
        );
      });
      test('an unknown property', () {
        fails(
          '      - { slot: title, color: red }\n',
          contains('unknown templates.title-page.recto[0].color'),
        );
      });
      test('not a list', () {
        fails('      title\n', contains('recto is a list of slots'));
      });
    });
  });

  test("doc/style.md's values are the house look's", () {
    final doc = File('doc/style.md').readAsStringSync();
    expect(withValues(doc), doc, reason: 'run dart run tool/style_table.dart');
  });

  test('the built-in looks are embedded as they are in data/looks', () {
    final check = Process.runSync(Platform.resolvedExecutable, [
      'run',
      'tool/embed_looks.dart',
      '--check',
    ]);
    expect(check.exitCode, 0, reason: '${check.stderr}');
  });
}
