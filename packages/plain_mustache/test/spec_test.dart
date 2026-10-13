/// The Mustache specification (github.com/mustache/spec, `test/spec/`):
/// every case of its required modules and of the optional inheritance,
/// dynamic names and lambdas.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:plain_mustache/plain_mustache.dart';
import 'package:test/test.dart';

/// [json] as a context value; a lambda (`{"__tag__": "code", ...}`) is
/// [lambda].
MustacheValue? valueOf(Object? json, MustacheValue? lambda) => switch (json) {
  null => null,
  final String text => MustacheText(text),
  final num number => MustacheText('$number'),
  final bool value => MustacheBoolean(value),
  final List<Object?> items => MustacheList([
    for (final item in items) valueOf(item, lambda),
  ]),
  {'__tag__': 'code'} => lambda,
  final Map<String, Object?> map => MustacheMap({
    for (final MapEntry(:key, :value) in map.entries)
      key: valueOf(value, lambda),
  }),
  _ => throw ArgumentError.value(json),
};

/// The specification's lambdas (given in other languages), by case name,
/// written in Dart: each result rendered as a template, as the
/// specification asks.
MustacheValue lambdaFor(String name) {
  var calls = 0;
  String Function(MustacheLambdaContext) expand(
    String Function(String source) text,
  ) =>
      (context) => context.renderSource(text(context.source));
  return MustacheLambda(switch (name) {
    'Interpolation' => expand((_) => 'world'),
    'Interpolation - Expansion' => expand((_) => '{{planet}}'),
    'Interpolation - Alternate Delimiters' => expand(
      (_) => '|planet| => {{planet}}',
    ),
    'Interpolation - Multiple Calls' => expand((_) => '${++calls}'),
    'Escaping' => expand((_) => '>'),
    'Section' => expand((source) => source == '{{x}}' ? 'yes' : 'no'),
    'Section - Expansion' => expand((source) => '$source{{planet}}$source'),
    'Section - Alternate Delimiters' => expand(
      (source) => '$source{{planet}} => |planet|$source',
    ),
    'Section - Multiple Calls' => expand((source) => '__${source}__'),
    'Inverted Section' => (_) => null,
    _ => throw ArgumentError.value(name),
  });
}

void main() {
  final files =
      Directory('test/spec')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  test('every module is here', () {
    expect(files.map((f) => f.uri.pathSegments.last), [
      'comments.json',
      'delimiters.json',
      'interpolation.json',
      'inverted.json',
      'partials.json',
      'sections.json',
      '~dynamic-names.json',
      '~inheritance.json',
      '~lambdas.json',
    ]);
  });
  for (final file in files) {
    final spec = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    group(file.uri.pathSegments.last, () {
      for (final item in spec['tests']! as List<Object?>) {
        final testCase = item! as Map<String, Object?>;
        final {
          'name': name as String,
          'desc': description as String,
          'template': template as String,
          'expected': expected as String,
        } = testCase;
        final partials = switch (testCase) {
          {'partials': final Map<String, Object?> partials} => partials,
          _ => const <String, Object?>{},
        };
        test('$name: $description', () {
          final data = testCase['data'];
          final lambda = file.path.contains('lambdas') ? lambdaFor(name) : null;
          final rendered = MustacheTemplate(
            template,
            partials: (name) => partials[name] as String?,
          ).render(valueOf(data, lambda));
          expect(rendered, expected);
        });
      }
    });
  }
}
