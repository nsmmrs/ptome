// Looks (ADR-0023): the loader's model and its errors, the extends chain,
// and the house look's PDF theme against the theme it replaced.
@TestOn('vm')
library;

import 'dart:io';

import 'package:ptome/src/look/loader.dart';
import 'package:ptome/src/look/model.dart';
import 'package:ptome/src/pdf/look_theme.dart';
import 'package:ptome/src/pdf/theme.dart';
import 'package:test/test.dart';

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
    expect(look.tokens.colors, {'ink': const LookColor('222222')});
    expect(
      look.tokens.textSize?.of(Medium.print),
      const Length(10, LengthUnit.pt),
    );
    final dek = look.styles[const RoleTarget('dek')]!;
    expect(dek.shape, FontShape.normal);
    expect(switch (dek.size) {
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

    test('a look that extends itself', () {
      fails('extends: bad\n', contains('extends itself'));
    });
  });

  test('what the PDF cannot render is reported, by item', () {
    _look('screen', '''
tokens:
  measure: 66ch
styles:
  paragraph: { keep-with-next: true }
  .dek: { rows: none }
templates:
  footnote-reference: '{{number}}'
''');
    final warnings = <String>[];
    lookThemeEntries(_load('screen'), warn: warnings.add);
    expect(warnings, [
      contains('tokens.measure has no effect in the PDF yet'),
      contains('styles.paragraph.keep-with-next has no effect in the PDF'),
      contains('styles..dek.rows has no effect in the PDF'),
      contains('templates.footnote-reference has no effect in the PDF'),
    ]);
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
