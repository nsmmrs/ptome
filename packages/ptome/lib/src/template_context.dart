/// Pre-flattened Mustache render context for template-converter nodes.
///
/// Port foundation for the render context of
/// `lib/asciidoctor/converter/template.rb` (ADR-0002, T2). Asciidoctor's
/// Tilt templates execute with the node as `self`, so they call arbitrary
/// node methods.
/// A Mustache context is a typed `MustacheValue` tree (plain_mustache),
/// so [buildTemplateContext] flattens each node to a [MustacheMap] before
/// rendering.
///
/// ## Context vocabulary
///
/// Every render receives these keys (`null` when the node has no value, which
/// renders as empty output, see `template.dart`):
///
/// - `content`: Converted content: `AbstractBlock.content()`, the text of an
///   [Inline], else `null`.
/// - `text`: Inline/list-item text (`Inline.text`, `ListItem.text`), else
///   `null`.
/// - `id`: The node id (`AbstractNode.id`).
/// - `role`: The node role (`AbstractNode.role`).
/// - `roles`: All roles (`AbstractNode.roles`).
/// - `title`: Converted block title (`AbstractBlock.title`, caption excluded;
///   the doctitle on documents), else `null`.
/// - `caption`: Block caption (`AbstractBlock.caption`), else `null`.
/// - `context`: The node context (e.g. `'paragraph'`).
/// - `node_name`: The node name (e.g. `'inline_quoted'` on inlines).
/// - `attributes`: Shallow copy of the node attribute map (supports dotted
///   lookups such as `{{attributes.foo}}` and truthiness sections).
/// - `attr`: Section lambda for attributes with arguments:
///   `{{#attr}}name{{/attr}}`, with an optional `=default` suffix
///   (`{{#attr}}lang=en{{/attr}}`). Falls back to the document attributes,
///   as `attr` does.
/// - `document`: Shallow document map (`title`, `attributes`); `null` while the
///   node is detached. Never nested recursively.
/// - `items`: List items, each pre-flattened with [buildTemplateContext]
///   (description-list pairs become `{'terms': [...], 'description': ...}`);
///   `null` on non-list nodes.
/// - `sections`: Child sections of a document or section node, each
///   pre-flattened with [buildTemplateContext] (so
///   `{{#sections}}{{title}}{{/sections}}` lists them and nesting recurses);
///   `null` on other nodes. This is what a custom `outline` template iterates.
///
/// The per-call options (`toclevels`, `sectnumlevels`) and `helpers`
/// (path-(a) lambdas per ADR-0002 T4) are merged in as top-level keys; on
/// collision the explicit call-site values win over the node-derived ones.
///
/// Numbers (`toclevels`, `sectnumlevels`) are given as their text.
library;

import 'package:plain_mustache/plain_mustache.dart';
import 'package:ptome/src/abstract_block.dart';
import 'package:ptome/src/abstract_node.dart';
import 'package:ptome/src/converter.dart' show ConvertOptions;
import 'package:ptome/src/inline.dart';
import 'package:ptome/src/list.dart';

/// Computes one custom helper value for [node] on every render.
///
/// Helpers are path-(a) Dart lambdas (ADR-0002 T4): unlike Asciidoctor's
/// per-directory `helpers.rb` (arbitrary loadable code), this port
/// receives helper code through registration, and the context builder injects
/// each computed value into the render context under its registered name.
typedef TemplateHelper = MustacheValue? Function(AbstractNode node);

/// Flattens [node] to the Mustache render context described above.
///
/// [helpers] are evaluated against [node] and injected by name; [opts] are
/// merged in as top-level keys (winning on collision).
MustacheMap buildTemplateContext(
  AbstractNode node, {
  Map<String, TemplateHelper> helpers = const <String, TemplateHelper>{},
  ConvertOptions? opts,
}) {
  final context = <String, MustacheValue?>{
    'content': _text(_contentOf(node)),
    'text': _text(_textOf(node)),
    'id': _text(node.id),
    'role': _text(node.role),
    'roles': MustacheList([for (final role in node.roles) MustacheText(role)]),
    'title': _text(node is AbstractBlock ? node.title : null),
    'caption': _text(node is AbstractBlock ? node.caption : null),
    'context': MustacheText(node.contextName),
    'node_name': MustacheText(node.nodeName),
    'attributes': _attributes(node.attributes),
    'attr': _attrLambda(node),
    'document': _documentOf(node),
    'items': _itemsOf(node),
    'sections': _sectionsOf(node),
  };
  for (final entry in helpers.entries) {
    context[entry.key] = entry.value(node);
  }
  if (opts?.toclevels case final toclevels?) {
    context['toclevels'] = MustacheText('$toclevels');
  }
  if (opts?.sectnumlevels case final levels?) {
    context['sectnumlevels'] = MustacheText('$levels');
  }
  return MustacheMap(context);
}

/// [text] as a value (`null` stays `null`).
MustacheText? _text(String? text) => text == null ? null : MustacheText(text);

/// A copy of [attributes] as a value.
MustacheMap _attributes(Map<String, String> attributes) => MustacheMap({
  for (final MapEntry(:key, :value) in attributes.entries)
    key: MustacheText(value),
});

/// The converted content of [node].
String? _contentOf(AbstractNode node) {
  if (node is AbstractBlock) return node.content();
  if (node is Inline) return node.text;
  return null;
}

/// The primary text of [node] when it has one (inlines, list items).
String? _textOf(AbstractNode node) {
  if (node is Inline) return node.text;
  if (node is ListItem) return node.text;
  return null;
}

/// Section lambda resolving `{{#attr}}name[=default]{{/attr}}`.
///
/// The section body is rendered first (so it may itself contain tags), then
/// looked up with document fallback, as `attr` does.
MustacheLambda _attrLambda(AbstractNode node) => MustacheLambda((context) {
  final spec = context.render().trim();
  final equals = spec.indexOf('=');
  if (equals == -1) return node.attr(spec, null, spec) ?? '';
  final name = spec.substring(0, equals);
  return node.attr(name, spec.substring(equals + 1), name) ?? '';
});

/// Shallow document map for [node]'s document (`null` while detached).
///
/// Deliberately shallow (title + attributes only): the full document tree is
/// never nested into its own render context.
MustacheMap? _documentOf(AbstractNode node) {
  final doc = node.document;
  if (doc == null) return null;
  return MustacheMap({
    'title': _text(doc.attr('doctitle')),
    'attributes': _attributes(doc.attributes),
  });
}

/// Pre-flattened list items, or `null` when [node] is not a list.
///
/// Outline-list items flatten to their own render contexts.
/// Description-list pairs flatten to `{'terms': [...], 'description': ...}`.
MustacheList? _itemsOf(AbstractNode node) {
  if (node is! ListBlock) return null;
  if (node.context == BlockContext.dlist) {
    return MustacheList([
      for (final entry in node.entries) _flattenDlistEntry(entry),
    ]);
  }
  return MustacheList([
    for (final item in node.items) buildTemplateContext(item),
  ]);
}

/// Pre-flattened child sections, or `null` on non-sectioned nodes.
///
/// Only document and section nodes carry sections; each child section
/// flattens to its own render context (recursing into subsections), so a
/// custom `outline` template iterates them with `{{#sections}}`. The
/// recursion always terminates: section nesting is finite and the
/// flattened children never re-enter their own ancestors.
MustacheList? _sectionsOf(AbstractNode node) {
  if (node is! AbstractBlock) return null;
  if (node.context != .document && node.context != .section) return null;
  return MustacheList([
    for (final section in node.sections) buildTemplateContext(section),
  ]);
}

/// Flattens one description-list entry.
MustacheMap _flattenDlistEntry(DlistEntry entry) {
  final description = entry.description;
  return MustacheMap({
    'terms': MustacheList([
      for (final term in entry.terms) buildTemplateContext(term),
    ]),
    'description': description == null
        ? null
        : buildTemplateContext(description),
  });
}
