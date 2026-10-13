/// Reading a template: its tags, its standalone lines, its tree.
library;

import 'package:plain_mustache/src/exception.dart';

/// A part of a parsed template.
sealed class Node {
  const new();
}

/// Text written as it is.
final class TextNode extends Node {
  /// A node of the given parts.
  const new(this.text);

  /// The text.
  final String text;
}

/// `{{name}}`, or `{{{name}}}` and `{{&name}}` (not [escaped]).
final class VariableNode extends Node {
  /// A node of the given parts.
  const new(this.name, {required this.escaped});

  /// The dotted name.
  final String name;

  /// Whether the value is escaped.
  final bool escaped;
}

/// `{{#name}}...{{/name}}`, or `{{^name}}...{{/name}}` ([inverted]).
final class SectionNode extends Node {
  /// A node of the given parts.
  const new(
    this.name,
    this.children, {
    required this.inverted,
    required this.source,
    required this.open,
    required this.close,
  });

  /// The dotted name.
  final String name;

  /// What is between the tags.
  final List<Node> children;

  /// Whether it is rendered when the value is false.
  final bool inverted;

  /// The unrendered text between the tags, for lambdas.
  final String source;

  /// The delimiters in effect at the opening tag.
  final String open;

  /// (See [open].)
  final String close;
}

/// `{{>name}}`, or `{{>*name}}` ([dynamic]: the name is looked up).
final class PartialNode extends Node {
  /// A node of the given parts.
  const new(this.name, {required this.dynamic, required this.indent});

  /// The partial's name, or the dotted name of the value that names it.
  final String name;

  /// Whether [name] is looked up.
  final bool dynamic;

  /// The indentation of a standalone tag, given to each line of the
  /// partial; `null` when the tag isn't standalone.
  final String? indent;
}

/// `{{<name}}...{{/name}}`: a partial whose [blocks] are given.
final class ParentNode extends PartialNode {
  /// A node of the given parts.
  const new(
    super.name,
    this.blocks, {
    required super.dynamic,
    required super.indent,
  });

  /// The blocks given, by name.
  final Map<String, BlockNode> blocks;
}

/// `{{$name}}...{{/name}}`: content a parent's caller can replace.
final class BlockNode extends Node {
  /// A node of the given parts.
  const new(
    this.name,
    this.children, {
    required this.definitionIndent,
    required this.expansionIndent,
  });

  /// The block's name.
  final String name;

  /// The default content, or the content given.
  final List<Node> children;

  /// The indentation taken off each line of this content when it replaces
  /// a block elsewhere (its first line's), or `null` when the opening tag
  /// isn't standalone.
  final String? definitionIndent;

  /// The indentation put on each line of content that replaces this block
  /// (its default content's first line's, or the tag's when it has none),
  /// or `null` when the opening tag isn't standalone.
  final String? expansionIndent;
}

/// The kinds of tag.
enum _Kind {
  variable,
  unescaped,
  section,
  inverted,
  end,
  comment,
  partial,
  delimiters,
  block,
  parent;

  /// Whether a line holding only this tag (and whitespace) is left out of
  /// the output.
  bool get standalone => this != variable && this != unescaped;

  /// Whether it opens content an end tag closes.
  bool get opens =>
      this == section || this == inverted || this == block || this == parent;
}

/// A token of the source.
sealed class _Token {
  const new(this.start);

  /// Where it starts in the source.
  final int start;
}

/// Text, holding at most one line break, at its end.
final class _Text extends _Token {
  const new(super.start, this.text);

  final String text;
}

/// A tag.
final class _Tag extends _Token {
  new(
    super.start,
    this.end,
    this.kind,
    this.name, {
    required this.open,
    required this.close,
  });

  /// Where it ends in the source.
  final int end;

  final _Kind kind;

  /// Its trimmed content.
  final String name;

  /// The delimiters it was read with.
  final String open;

  /// (See [open].)
  final String close;

  /// The tag an end tag closes.
  _Tag? opener;

  /// Whether it stands alone on its line.
  bool standalone = false;

  /// The whitespace before it, when [standalone].
  String indent = '';
}

/// The tree of [source], read with the delimiters [open] and [close].
List<Node> parse(String source, {String open = '{{', String close = '}}'}) {
  final tokens = _standalone(_scan(source, open, close));
  final (nodes, _) = _tree(source, tokens, 0, null);
  return nodes;
}

/// The tokens of [source].
List<_Token> _scan(String source, String initialOpen, String initialClose) {
  final tokens = <_Token>[];
  final opened = <_Tag>[];
  var open = initialOpen;
  var close = initialClose;
  void text(int start, int end) {
    // A token a line, so standalone lines can be found.
    var from = start;
    while (from < end) {
      final newline = source.indexOf('\n', from);
      final to = newline < 0 || newline >= end ? end : newline + 1;
      tokens.add(_Text(from, source.substring(from, to)));
      from = to;
    }
  }

  var at = 0;
  while (at < source.length) {
    final start = source.indexOf(open, at);
    if (start < 0) break;
    text(at, start);
    var from = start + open.length;
    final sigil = from < source.length ? source[from] : '';
    final (kind, endMark) = switch (sigil) {
      '{' => (_Kind.unescaped, '}$close'),
      '&' => (_Kind.unescaped, close),
      '#' => (_Kind.section, close),
      '^' => (_Kind.inverted, close),
      '/' => (_Kind.end, close),
      '!' => (_Kind.comment, close),
      '>' => (_Kind.partial, close),
      '=' => (_Kind.delimiters, '=$close'),
      r'$' => (_Kind.block, close),
      '<' => (_Kind.parent, close),
      _ => (_Kind.variable, close),
    };
    if (kind != .variable) from++;
    final contentEnd = source.indexOf(endMark, from);
    if (contentEnd < 0) {
      throw MustacheException('tag not closed by "$endMark"', source, start);
    }
    final content = source.substring(from, contentEnd);
    final end = contentEnd + endMark.length;
    final tag = _Tag(
      start,
      end,
      kind,
      content.trim(),
      open: open,
      close: close,
    );
    switch (kind) {
      case .delimiters:
        final parts = tag.name.split(RegExp(r'\s+'));
        if (parts.length != 2 || parts.any((p) => p.contains('='))) {
          throw MustacheException(
            'a delimiter change needs two delimiters, without "="',
            source,
            start,
          );
        }
        [open, close] = parts;
      case .comment:
        break;
      case _ when tag.name.isEmpty:
        throw MustacheException('tag without a name', source, start);
      case .end:
        if (opened.isEmpty) {
          throw MustacheException(
            'closes "${tag.name}", which isn\'t open',
            source,
            start,
          );
        }
        final opener = opened.removeLast();
        if (opener.name != tag.name) {
          throw MustacheException(
            '"${opener.name}" closed by "${tag.name}"',
            source,
            start,
          );
        }
        tag.opener = opener;
      case _ when kind.opens:
        opened.add(tag);
      case _:
        break;
    }
    tokens.add(tag);
    at = end;
  }
  text(at, source.length);
  if (opened.isNotEmpty) {
    final tag = opened.last;
    throw MustacheException('"${tag.name}" never closed', source, tag.start);
  }
  return tokens;
}

final RegExp _blank = RegExp(r'^[ \t]*(\r?\n)?$');

/// [tokens] without the whitespace of standalone lines: a line holding
/// one tag that writes nothing of its own (a section's, a comment, a
/// partial...), or only parent and block tags, and otherwise whitespace,
/// is left out of the output, its indentation kept for a partial's lines.
List<_Token> _standalone(List<_Token> tokens) {
  final kept = <_Token>[];
  var lineStart = 0;
  for (var i = 0; i < tokens.length; i++) {
    final token = tokens[i];
    final lineEnds =
        i == tokens.length - 1 || token is _Text && token.text.endsWith('\n');
    if (!lineEnds) continue;
    final line = tokens.sublist(lineStart, i + 1);
    lineStart = i + 1;
    final tags = line.whereType<_Tag>().toList();
    final blank = line.every(
      (t) => t is _Tag || _blank.hasMatch((t as _Text).text),
    );
    final alone =
        blank &&
        switch (tags) {
          [final tag] => tag.kind.standalone,
          [_, _, ...] => tags.every(
            (t) => switch (t.opener?.kind ?? t.kind) {
              .parent || .block => true,
              _ => false,
            },
          ),
          _ => false,
        };
    if (!alone) {
      kept.addAll(line);
      continue;
    }
    final indent = switch (line.first) {
      final _Text text => text.text,
      _ => '',
    };
    for (final tag in tags) {
      tag
        ..standalone = true
        ..indent = indent;
    }
    kept.addAll(tags);
  }
  return kept;
}

/// The nodes of [tokens] from [from] up to the end tag closing [opener]
/// (or the end), and the index after it.
(List<Node>, int) _tree(
  String source,
  List<_Token> tokens,
  int from,
  _Tag? opener,
) {
  final nodes = <Node>[];
  final text = StringBuffer();
  void flush() {
    if (text.isNotEmpty) nodes.add(TextNode(text.toString()));
    text.clear();
  }

  var i = from;
  while (i < tokens.length) {
    final token = tokens[i++];
    switch (token) {
      case _Text():
        text.write(token.text);
        continue;
      case _Tag(kind: .end) when identical(token.opener, opener):
        flush();
        return (nodes, i);
      case _Tag(kind: .comment || .delimiters || .end):
        continue;
      case _Tag(kind: final kind && (.variable || .unescaped), :final name):
        flush();
        nodes.add(VariableNode(name, escaped: kind == .variable));
      case _Tag(kind: .partial, :final name):
        flush();
        final (partial, dynamic) = _dynamic(name);
        nodes.add(
          PartialNode(
            partial,
            dynamic: dynamic,
            indent: token.standalone ? token.indent : null,
          ),
        );
      case _Tag(kind: .section || .inverted || .block || .parent):
        flush();
        final (children, next) = _tree(source, tokens, i, token);
        final close = tokens[next - 1] as _Tag;
        i = next;
        nodes.add(switch (token.kind) {
          .block => BlockNode(
            token.name,
            children,
            definitionIndent: token.standalone ? _indentOf(children) : null,
            expansionIndent: token.standalone
                ? (children.isEmpty ? token.indent : _indentOf(children))
                : null,
          ),
          .parent => _parent(token, children),
          _ => SectionNode(
            token.name,
            children,
            inverted: token.kind == .inverted,
            source: source.substring(token.end, close.start),
            open: token.open,
            close: token.close,
          ),
        });
    }
  }
  flush();
  return (nodes, i);
}

/// The parent [tag] opens, given the blocks among its [children] (the
/// rest is left out).
ParentNode _parent(_Tag tag, List<Node> children) {
  final (name, dynamic) = _dynamic(tag.name);
  return ParentNode(
    name,
    {
      for (final child in children)
        if (child is BlockNode) child.name: child,
    },
    dynamic: dynamic,
    indent: tag.standalone ? tag.indent : null,
  );
}

/// [name] without a leading `*`, and whether it had one.
(String, bool) _dynamic(String name) =>
    name.startsWith('*') ? (name.substring(1).trim(), true) : (name, false);

/// The whitespace starting the first line of [children].
String _indentOf(List<Node> children) => switch (children.firstOrNull) {
  TextNode(:final text) => RegExp('^[ \t]*').stringMatch(text)!,
  _ => '',
};
