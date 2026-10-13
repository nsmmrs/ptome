/// Templates for text converters generate (ADR-0010): Mustache templates
/// a document or theme sets in place of the text a converter writes by
/// default (a footnote's marker, a caption's number).
library;

import 'package:plain_mustache/plain_mustache.dart';
import 'package:ptome/src/lru.dart';

/// (At most 256 kept: templates come from documents.)
final LruCache<String, MustacheTemplate> _parsed = LruCache(256);

/// [template] rendered with [values] (an empty or missing value leaves a
/// `{{#name}}...{{/name}}` part out). Values are written as they are: the
/// caller escapes them for its output.
String renderTemplate(String template, Map<String, String?> values) => _parsed
    .putIfAbsent(template, () => MustacheTemplate(template, escape: _raw))
    .render(
      MustacheMap({
        for (final MapEntry(:key, :value) in values.entries)
          if (value != null && value.isNotEmpty) key: MustacheText(value),
      }),
    );

String _raw(String text) => text;

/// [template] rendered for [number] (`{{number}}`), the number written by
/// [link] (a link to what it numbers): `[{{number}}]` gives `[`, the link,
/// `]`.
String renderNumbered(
  String template,
  String number,
  String Function(String number) link,
) {
  const token = '\u0000number\u0000';
  return renderTemplate(template, {
    'number': token,
  }).replaceAll(token, link(number));
}
