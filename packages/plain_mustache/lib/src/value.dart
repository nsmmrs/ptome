/// The values a template renders: text, booleans, lists, maps and lambdas.
library;

import 'package:meta/meta.dart';
import 'package:plain_mustache/src/renderer.dart' show MustacheLambdaContext;

/// A value in a template's context.
///
/// A missing value and a Dart `null` render alike: as nothing, and as
/// false in a section.
@immutable
sealed class MustacheValue {
  const new();

  /// The text `{{name}}` writes for this value (before escaping).
  ///
  /// Lists and maps write as Dart writes them (`[a, b]`, `{k: v}`), so a
  /// template that shows one by mistake still shows what it holds.
  String get display;
}

/// A text, written as it is. Numbers are given as their text.
///
/// Any text, the empty one too, is true in a section: the section is
/// rendered once with the text on top of the context.
final class MustacheText extends MustacheValue {
  /// [text] as a value.
  const new(this.text);

  /// The text.
  final String text;

  @override
  String get display => text;

  @override
  bool operator ==(Object other) => other is MustacheText && other.text == text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => 'MustacheText($text)';
}

/// True or false: a section is rendered once (true) or not at all.
final class MustacheBoolean extends MustacheValue {
  /// [value] as a value.
  // ignore: avoid_positional_boolean_parameters
  const new(this.value);

  /// Whether it is true.
  final bool value;

  @override
  String get display => '$value';

  @override
  bool operator ==(Object other) =>
      other is MustacheBoolean && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'MustacheBoolean($value)';
}

/// A list: a section is rendered once for each of its items, with the item
/// on top of the context, and an empty list is false.
///
/// A name made of digits looks an item up by its index (`items.0.title`).
final class MustacheList extends MustacheValue {
  /// [items] as a value.
  const new(this.items);

  /// The items.
  final List<MustacheValue?> items;

  @override
  String get display => '[${items.map(_nested).join(', ')}]';

  @override
  String toString() => 'MustacheList($items)';
}

/// A map of names to values: names are looked up in it, and a section is
/// rendered once with it on top of the context.
///
/// A name the map holds, even with a `null` value, stops the lookup there;
/// a name it doesn't hold is looked up further down the context. Any [Map]
/// works, so a lazy one can compute its values when they are looked up.
final class MustacheMap extends MustacheValue {
  /// [entries] as a value.
  const new(this.entries);

  /// The values by name.
  final Map<String, MustacheValue?> entries;

  @override
  String get display {
    final pairs = [
      for (final MapEntry(:key, :value) in entries.entries)
        '$key: ${_nested(value)}',
    ];
    return '{${pairs.join(', ')}}';
  }

  @override
  String toString() => 'MustacheMap($entries)';
}

/// Code run where the template names it.
///
/// For `{{name}}` the [function] gets a context with no section and its
/// result is written (escaped, unless the tag is `{{{name}}}` or
/// `{{&name}}`). For `{{#name}}...{{/name}}` it gets the section's
/// unrendered [MustacheLambdaContext.source] and can render it; its result
/// is written as it is. A `null` result writes nothing. To have the result
/// rendered as a template, as the specification's lambdas are, return
/// `context.renderSource(text)`.
final class MustacheLambda extends MustacheValue {
  /// [function] as a value.
  const new(this.function);

  /// The code.
  final String? Function(MustacheLambdaContext context) function;

  @override
  String get display => 'lambda';

  @override
  String toString() => 'MustacheLambda';
}

/// [value] written inside a list or a map (as Dart writes `null`).
String _nested(MustacheValue? value) => value?.display ?? 'null';
