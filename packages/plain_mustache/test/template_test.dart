/// What the specification leaves open, as plain_mustache settles it, and
/// its errors.
library;

import 'package:plain_mustache/plain_mustache.dart';
import 'package:test/test.dart';

String render(
  String template,
  Map<String, MustacheValue?> context, {
  Map<String, String> partials = const {},
}) => MustacheTemplate(
  template,
  partials: (name) => partials[name],
).render(MustacheMap(context));

void main() {
  group('values', () {
    test('any text is true in a section, the empty one too', () {
      expect(
        render('{{#a}}[{{.}}]{{/a}}', {'a': const MustacheText('')}),
        '[]',
      );
      expect(render('{{^a}}no{{/a}}', {'a': const MustacheText('')}), '');
    });

    test('a list writes as Dart writes it, items looked up by index', () {
      const list = MustacheList([
        MustacheText('a'),
        null,
        MustacheMap({'k': MustacheText('v')}),
      ]);
      expect(render('{{list}}', {'list': list}), '[a, null, {k: v}]');
      expect(render('{{list.0}}{{list.2.k}}{{list.9}}', {'list': list}), 'av');
      expect(render('{{list.99999999999999999999999}}', {'list': list}), '');
    });

    test('a name held with no value stops the lookup', () {
      expect(
        render('{{#inner}}{{a}}{{/inner}}', {
          'a': const MustacheText('outer'),
          'inner': const MustacheMap({'a': null}),
        }),
        '',
      );
    });

    test('booleans write as true and false', () {
      expect(
        render('{{t}} {{f}}', {
          't': const MustacheBoolean(true),
          'f': const MustacheBoolean(false),
        }),
        'true false',
      );
    });

    test('values compare by content', () {
      expect(const MustacheText('a'), const MustacheText('a'));
      expect(const MustacheBoolean(true), isNot(const MustacheBoolean(false)));
    });
  });

  group('escaping', () {
    test('HTML by default, apostrophes too', () {
      expect(
        render('{{a}}|{{{a}}}|{{&a}}', {'a': const MustacheText('<&"\'>')}),
        '&lt;&amp;&quot;&#39;&gt;|<&"\'>|<&"\'>',
      );
    });

    test('or as given', () {
      expect(
        MustacheTemplate(
          '{{a}}',
          escape: (text) => text.toUpperCase(),
        ).render(const MustacheMap({'a': MustacheText('<b>')})),
        '<B>',
      );
    });
  });

  group('lambdas', () {
    test('a section lambda renders its content and writes the result', () {
      final lambda = MustacheLambda(
        (context) => '(${context.render().trim()})',
      );
      expect(
        render('{{#l}} {{x}} {{/l}}', {
          'l': lambda,
          'x': const MustacheText('{{y}}'),
        }),
        '({{y}})',
      );
    });

    test('rendering with a value on top', () {
      final lambda = MustacheLambda(
        (context) =>
            context.render(const MustacheMap({'x': MustacheText('in')})),
      );
      expect(
        render('{{#l}}{{x}}{{/l}}', {
          'l': lambda,
          'x': const MustacheText('out'),
        }),
        'in',
      );
    });

    test('a variable lambda has no content to render, but looks up', () {
      expect(
        () => render('{{l}}', {'l': MustacheLambda((c) => c.render())}),
        throwsStateError,
      );
      expect(
        render('{{l}}', {
          'l': MustacheLambda((c) => c.lookup('x')?.display),
          'x': const MustacheText('<x>'),
        }),
        '&lt;x&gt;',
      );
    });
  });

  group('partials', () {
    test('a missing one writes nothing; a dynamic name must be found', () {
      expect(render('[{{>none}}]', {}), '[]');
      expect(
        render(
          '[{{>*name}}]',
          {'name': const MustacheText('p')},
          partials: {'p': 'P'},
        ),
        '[P]',
      );
      expect(render('[{{>*name}}]', {}, partials: {'p': 'P'}), '[]');
    });

    test('runaway recursion stops', () {
      expect(
        () => render('{{>p}}', {}, partials: {'p': '{{>p}}'}),
        throwsStateError,
      );
    });

    test('each partial is read once', () {
      var reads = 0;
      final template = MustacheTemplate(
        '{{>p}}{{>p}}',
        partials: (name) {
          reads++;
          return 'x';
        },
      );
      expect(template.render(null), 'xx');
      expect(template.render(null), 'xx');
      expect(reads, 1);
    });
  });

  group('errors', () {
    void fails(String template, String message, int line, int column) {
      expect(
        () => MustacheTemplate(template),
        throwsA(
          isA<MustacheException>()
              .having((e) => e.message, 'message', message)
              .having((e) => e.line, 'line', line)
              .having((e) => e.column, 'column', column)
              .having((e) => '$e', 'toString', contains('line $line')),
        ),
      );
    }

    test('are reported where they are', () {
      fails('a {{b', 'tag not closed by "}}"', 1, 3);
      fails('{{{b}}', 'tag not closed by "}}}"', 1, 1);
      fails('x\n{{#a}}', '"a" never closed', 2, 1);
      fails('{{#a}}{{/b}}', '"a" closed by "b"', 1, 7);
      fails('{{/a}}', 'closes "a", which isn\'t open', 1, 1);
      fails('{{ }}', 'tag without a name', 1, 1);
      fails(
        '{{=| | |=}}',
        'a delimiter change needs two delimiters, '
            'without "="',
        1,
        1,
      );
    });
  });
}
