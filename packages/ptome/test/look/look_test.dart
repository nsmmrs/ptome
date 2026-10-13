// Looks (ADR-0023): the loader's model and its errors, the extends chain,
// and the house look's PDF theme against the theme it replaced.
@TestOn('vm')
library;

import 'dart:io';

import 'package:ptome/src/internal.dart';
import 'package:ptome/src/look/css.dart';
import 'package:ptome/src/look/loader.dart';
import 'package:ptome/src/look/looks.g.dart';
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
    // (Besides the line spacings as exact pitches, which the theme only
    // reached in faces shorter than them.)
    bool pitch(String key) => key.endsWith('_line_pitch');
    final keys = {...compiled.keys, ...before.keys}.where((k) => !pitch(k));
    final differences = [
      for (final key in keys)
        if ('${compiled[key]}' != '${before[key]}')
          '$key: ${compiled[key]}, was ${before[key]}',
    ];
    expect(differences, isEmpty, reason: differences.join('\n'));
    expect(
      {for (final key in compiled.keys.where(pitch)) key: '${compiled[key]}'},
      {
        'base_line_pitch': 'ThemeString(1.4em)',
        'heading_line_pitch': 'ThemeString(1.2em)',
        'code_line_pitch': 'ThemeString(1.35em)',
      },
    );
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
    ]);
  });

  test("a look's templates are their attributes' defaults", () {
    final dir = _dir.path;
    File('$dir/tpl-look.yml').writeAsStringSync(
      "templates:\n  multipage-nav-next: 'Continued in {{title}}'\n",
    );
    Document parse(String header) => load(
      '= Doc\n:look: tpl\n:looksdir: $dir\n$header\nText.\n',
      options: const AsciidoctorOptions(safe: SafeMode.unsafe),
    );
    expect(
      parse('').attr('multipage-nav-next-template'),
      'Continued in {{title}}',
    );
    // The document's own wins.
    expect(
      parse(':multipage-nav-next-template: Next')
          .attr('multipage-nav-next-template'),
      'Next',
    );
  });

  group('CSS', () {
    test("the house look's screen rules are the house stylesheet's", () {
      final css = lookCss(LookLoader().load('ptome'), CssTarget.html);
      final screen = css.substring(0, css.indexOf('@media print'));
      expect(
        screen,
        allOf(
          contains(
            '@media screen{#header,#content,#footnotes,#footer,.multipage-nav'
            '{max-width:75ch}}',
          ),
          contains(
            'h1,h2,h3,#toctitle,.sidebarblock>.content>.title,h4,h5,h6'
            '{font-weight:600;color:var(--ptome-color-ink-strong)}',
          ),
          contains('--ptome-color-ink-strong:#191919'),
          contains('pre[class^="highlight "]{border:0}'),
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

  test('tracking: letter_spacing in print, letter-spacing on the web', () {
    _look('tracked', 'styles:\n  .kicker: { tracking: 0.14em }\n');
    final look = _load('tracked');
    expect(
      lookThemeEntries(look)['role_kicker_letter_spacing'],
      isA<YScalar>().having(
        (y) => y.value,
        'value',
        const ThemeString('0.14em'),
      ),
    );
    expect(lookCss(look, CssTarget.html), contains('letter-spacing:0.14em'));
  });

  test('a page on a baseline grid', () {
    _look('grid', 'tokens:\n  page: { grid: true }\n');
    expect(
      lookThemeEntries(_load('grid'))['page_baseline_grid'],
      isA<YScalar>().having((y) => y.value, 'value', const ThemeBool(true)),
    );
  });

  test('a trim size; paragraphs indented after paragraphs alone', () {
    _look('trim', '''
tokens:
  page: { size: [6.25in, 9.25in] }
  paragraph: { signal: indent, indent: 2.5em }
''');
    final look = _load('trim');
    final entries = lookThemeEntries(look);
    expect(
      [
        for (final key in [
          'page_size',
          'prose_margin_inner',
          'prose_text_indent_inner',
        ])
          switch (entries[key]) {
            YList(:final items) => [
              for (final item in items)
                if (item case YScalar(:final value)) value.rubyString,
            ].join(' '),
            YScalar(:final value) => value.rubyString,
            _ => null,
          },
      ],
      ['6.25in 9.25in', '0', '2.5em'],
    );
    expect(entries.containsKey('prose_text_indent'), isFalse);
    expect(
      lookCss(look, CssTarget.html),
      contains('@page{size:6.25in 9.25in}'),
    );
  });

  test('rem: the base font size, in CSS and the theme', () {
    _look(
      'rem',
      'tokens:\n  size: { text: { screen: 1.0625rem } }\n'
          '  measure: 30rem\n',
    );
    final look = _load('rem');
    expect(lookCss(look, CssTarget.html), contains('font-size:1.0625rem'));
    final measure = lookThemeEntries(look)['page_measure'];
    expect(measure is YScalar ? measure.value.rubyString : null, '30rem');
  });

  test("a heading's number: hung, or on a line of its own", () {
    _look('num', '''
styles:
  heading: { number: hang, hang: 3em }
  h3: { number: line }
  paragraph: { number: line }
''');
    final look = _load('num');
    final warnings = <String>[];
    final entries = lookThemeEntries(look, warn: warnings.add);
    String? key(String name) => switch (entries[name]) {
      YScalar(:final value) => value.rubyString,
      _ => null,
    };
    expect(key('heading_number_placement'), 'hang');
    expect(key('heading_number_hang'), '3em');
    expect(key('heading_h3_number_placement'), 'line');
    expect(warnings, [
      'look num: styles.paragraph.number has no effect in the PDF',
    ]);
    final css = lookCss(look, CssTarget.html);
    expect(
      css,
      contains(
        'h1>.number:first-child,h2>.number:first-child,h3>.number:first-child',
      ),
    );
    expect(css, contains('{float:left;width:3em;margin-left:-3em}'));
    expect(css, contains('h3>.number:first-child{display:block}'));
  });

  test('a font stack: the PDF sets its first family, CSS all of them', () {
    _look('stack', '''
tokens:
  font:
    text: { family: [Palatino Linotype, Palatino, serif] }
    display: { family: [Bodoni Moda] }
''');
    final look = _load('stack');
    final family = lookThemeEntries(look)['base_font_family'];
    expect(
      family is YScalar ? family.value.rubyString : null,
      'Palatino Linotype',
    );
    final css = lookCss(look, CssTarget.html);
    expect(
      css,
      contains('--ptome-font-text:"Palatino Linotype","Palatino",serif'),
    );
    // (No generic family in the stack: the role's.)
    expect(css, contains('--ptome-font-display:"Bodoni Moda",sans-serif'));
  });

  test("the house look's prose on screen: print-grade where it can be", () {
    final look = LookLoader().load('ptome');
    // (Hyphenated, its last lines balanced, old-style figures, hung
    // punctuation: prose alone, never headings or code; the measure in
    // the face's own characters.)
    final own = lookOwnCss(look, CssTarget.html);
    expect(own, contains('#content .paragraph>p,'));
    expect(own, contains('hyphens:auto;text-wrap:pretty'));
    expect(own, contains('.nohyphens #content p'));
    expect(own, contains('font-variant-numeric:oldstyle-nums'));
    expect(own, contains('hanging-punctuation:first allow-end last'));
    expect(own, contains('h6,#toctitle,.sidebarblock>.content>.title'));
    expect(lookCss(look, CssTarget.html), contains('max-width:75ch'));
    // (Not in an e-book: the reader's.)
    expect(lookOwnCss(look, CssTarget.epub), isNot(contains('text-wrap')));
  });

  test('the docs-site look: code first, a sidebar, a dark mode', () {
    final look = LookLoader().load('docs-site');
    final css = lookCss(look, CssTarget.html);
    final own = lookOwnCss(look, CssTarget.html);
    // (The reader's interface sans, 1.65 on a 46em measure.)
    expect(css, contains('--ptome-font-text:system-ui,'));
    expect(css, contains('line-height:1.65'));
    expect(css, contains('max-width:46em'));
    // (Admonitions by type, a 5 px border; the contents beside the page;
    // the colors again for a dark scheme.)
    expect(own, contains('border-left:5px solid var(--admonition)'));
    expect(own, contains('.admonitionblock.caution{--admonition:#EF4444'));
    expect(own, contains('#toc.toc,#toc.toc2{position:fixed'));
    expect(own, contains('(prefers-color-scheme:dark)'));
  });

  test('every built-in look compiles for each output without a warning', () {
    for (final name in builtInLooks.keys) {
      final look = LookLoader().load(name);
      final warnings = <String>[];
      lookTheme(look, warn: warnings.add);
      lookCss(look, CssTarget.html, warn: warnings.add);
      lookCss(look, CssTarget.epub, warn: warnings.add);
      expect(warnings, isEmpty, reason: name);
    }
    expect(
      builtInLooks.keys,
      containsAll(['ptome', 'troff', 'tech-book', 'us-code', 'magazine']),
    );
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
