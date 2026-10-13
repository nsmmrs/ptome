/// A template, read once and rendered as often as needed.
library;

import 'package:plain_mustache/src/parser.dart';
import 'package:plain_mustache/src/renderer.dart';
import 'package:plain_mustache/src/value.dart';

/// [text] escaped for HTML and XML: `&`, `<`, `>`, `"` and `'`.
String escapeHtml(String text) {
  if (!text.contains(_special)) return text;
  return text.replaceAllMapped(
    _special,
    (m) => switch (m[0]) {
      '&' => '&amp;',
      '<' => '&lt;',
      '>' => '&gt;',
      '"' => '&quot;',
      _ => '&#39;',
    },
  );
}

final RegExp _special = RegExp('[&<>"\']');

/// A Mustache template.
///
/// ```dart
/// final template = MustacheTemplate('Hello, {{name}}!');
/// template.render(const MustacheMap({'name': MustacheText('world')}));
/// // 'Hello, world!'
/// ```
final class MustacheTemplate {
  /// [source] read as a template; throws a `MustacheException` when it
  /// can't be.
  ///
  /// [partials] gives the source of the partial (or parent) named, or
  /// `null` when there is none, which renders as nothing; each is read
  /// once. [escape] escapes what `{{name}}` writes (HTML by default; pass
  /// `(text) => text` to write values as they are).
  new(this.source, {this.partials, this.escape = escapeHtml})
    : _nodes = parse(source);

  /// The template's source.
  final String source;

  /// Escapes what `{{name}}` writes.
  final String Function(String text) escape;

  /// Gives the source of the partial named (`null`: there is none).
  final String? Function(String name)? partials;

  final List<Node> _nodes;

  /// The partials read so far, by name (`null`: none of that name).
  final Map<String, List<Node>?> _partialNodes = {};

  /// The template rendered against [context] (usually a [MustacheMap]).
  String render(MustacheValue? context) =>
      Renderer(context, escape: escape, partial: _partial).render(_nodes);

  List<Node>? _partial(String name) {
    final partials = this.partials;
    if (partials == null) return null;
    return _partialNodes.putIfAbsent(name, () {
      final source = partials(name);
      return source == null ? null : parse(source);
    });
  }
}
