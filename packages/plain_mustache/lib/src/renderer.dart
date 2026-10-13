/// Rendering a parsed template against a context.
library;

import 'package:plain_mustache/src/parser.dart';
import 'package:plain_mustache/src/value.dart';

/// What a [MustacheLambda] gets: the section it stands for, and the
/// context to render with.
final class MustacheLambdaContext {
  new _(this._renderer, this._section);

  final Renderer _renderer;

  final SectionNode? _section;

  /// The section's unrendered text (empty for `{{name}}`).
  String get source => _section?.source ?? '';

  /// The section's content rendered against the context, with [value] on
  /// top of it when given.
  ///
  /// Throws a [StateError] for `{{name}}`, which has no content.
  String render([MustacheValue? value]) {
    final section = _section;
    if (section == null) {
      throw StateError('only a section has content to render');
    }
    return _renderer.renderApart(section.children, value);
  }

  /// [source] rendered as a template against the context, with [value] on
  /// top of it when given: read with the section's delimiters, or the
  /// default ones for `{{name}}`.
  String renderSource(String source, [MustacheValue? value]) {
    final section = _section;
    final nodes = section == null
        ? parse(source)
        : parse(source, open: section.open, close: section.close);
    return _renderer.renderApart(nodes, value);
  }

  /// The value of the dotted [name] in the context.
  MustacheValue? lookup(String name) => _renderer.lookup(name);
}

/// Where the output goes: a partial's indentation goes before each of its
/// lines, once something is written on it.
final class _Output {
  final StringBuffer buffer = StringBuffer();

  /// The indentation of the partials being rendered.
  String indent = '';

  /// Whether a line of the template has just ended.
  bool atLineStart = false;

  /// Writes [text] of the template, indenting each of its lines.
  void text(String text) {
    var from = 0;
    while (from < text.length) {
      final newline = text.indexOf('\n', from);
      final to = newline < 0 ? text.length : newline + 1;
      value(text.substring(from, to));
      if (newline >= 0) atLineStart = true;
      from = to;
    }
  }

  /// Writes [text] of a value: its own line breaks aren't indented.
  void value(String text) {
    if (text.isEmpty) return;
    if (atLineStart) {
      buffer.write(indent);
      atLineStart = false;
    }
    buffer.write(text);
  }
}

/// Renders nodes against a stack of context values.
final class Renderer {
  /// A renderer for [context], escaping values with [escape] and finding
  /// partials' trees with [partial].
  new(MustacheValue? context, {required this.escape, required this.partial})
    : _stack = [context];

  /// Escapes a value written by `{{name}}`.
  final String Function(String text) escape;

  /// The tree of the partial named, or `null` when there is none.
  final List<Node>? Function(String name) partial;

  final List<MustacheValue?> _stack;

  /// The blocks given by the parents being rendered.
  Map<String, BlockNode> _blocks = const {};

  _Output _output = _Output();

  /// How many partials deep the rendering is.
  int _depth = 0;

  /// [nodes] rendered.
  String render(List<Node> nodes) {
    _nodes(nodes);
    return _output.buffer.toString();
  }

  /// [nodes] rendered on their own, with [value] on top of the context.
  String renderApart(List<Node> nodes, MustacheValue? value) {
    final output = _output;
    _output = _Output();
    if (value != null) _stack.add(value);
    try {
      _nodes(nodes);
      return _output.buffer.toString();
    } finally {
      if (value != null) _stack.removeLast();
      _output = output;
    }
  }

  void _nodes(List<Node> nodes) {
    for (final node in nodes) {
      switch (node) {
        case TextNode(:final text):
          _output.text(text);
        case VariableNode(:final name, :final escaped):
          final text = switch (lookup(name)) {
            final MustacheLambda lambda =>
              lambda.function(MustacheLambdaContext._(this, null)) ?? '',
            final value => value?.display ?? '',
          };
          _output.value(escaped ? escape(text) : text);
        case SectionNode():
          _section(node);
        case final ParentNode parent:
          _partial(parent, parent.blocks);
        case final PartialNode partial:
          _partial(partial, const {});
        case final BlockNode block:
          _block(block);
      }
    }
  }

  void _section(SectionNode node) {
    final value = lookup(node.name);
    if (node.inverted) {
      if (switch (value) {
        null || MustacheBoolean(value: false) => true,
        MustacheList(:final items) => items.isEmpty,
        _ => false,
      }) {
        _nodes(node.children);
      }
      return;
    }
    switch (value) {
      case null || MustacheBoolean(value: false):
        break;
      case MustacheList(:final items):
        for (final item in items) {
          _with(item, node.children);
        }
      case MustacheLambda(:final function):
        _output.value(function(MustacheLambdaContext._(this, node)) ?? '');
      case _:
        _with(value, node.children);
    }
  }

  void _with(MustacheValue? value, List<Node> nodes) {
    _stack.add(value);
    try {
      _nodes(nodes);
    } finally {
      _stack.removeLast();
    }
  }

  void _partial(PartialNode node, Map<String, BlockNode> blocks) {
    final name = node.dynamic
        ? switch (lookup(node.name)) {
            MustacheText(:final text) => text,
            null => null,
            final value => value.display,
          }
        : node.name;
    final nodes = name == null ? null : partial(name);
    if (nodes == null) return;
    if (++_depth > 1000) {
      throw StateError('partials nested more than 1000 deep');
    }
    final output = _output;
    final indent = output.indent;
    final outer = _blocks;
    // The blocks given further out win.
    if (blocks.isNotEmpty) _blocks = {...blocks, ...outer};
    if (node.indent case final more?) {
      output
        ..indent = indent + more
        ..atLineStart = true;
    }
    try {
      _nodes(nodes);
    } finally {
      output.indent = indent;
      _blocks = outer;
      _depth--;
    }
  }

  void _block(BlockNode node) {
    final given = _blocks[node.name];
    if (given == null) {
      _nodes(node.children);
      return;
    }
    // The content given, rendered where the block is, its indentation
    // moved from where it was given to where it goes.
    final outer = _blocks;
    _blocks = {...outer}..remove(node.name);
    String text;
    try {
      text = renderApart(given.children, null);
    } finally {
      _blocks = outer;
    }
    if (given.definitionIndent case final indent? when indent.isNotEmpty) {
      text = text.splitMapJoin(
        RegExp('^${RegExp.escape(indent)}', multiLine: true),
        onMatch: (_) => '',
      );
    }
    if (node.expansionIndent case final indent?) {
      text = text.splitMapJoin(
        RegExp('^(?=.)', multiLine: true),
        onMatch: (_) => indent,
      );
      if (text.isNotEmpty && !text.endsWith('\n')) text = '$text\n';
    }
    _output.text(text);
  }

  /// The value of the dotted [name]: its first part looked up from the top
  /// of the stack down, each next part in the value found.
  MustacheValue? lookup(String name) {
    if (name == '.') return _stack.last;
    final parts = name.split('.');
    var (found, value) = (false, null as MustacheValue?);
    for (var i = _stack.length - 1; i >= 0 && !found; i--) {
      (found, value) = _member(_stack[i], parts.first);
    }
    for (var i = 1; i < parts.length && found; i++) {
      (found, value) = _member(value, parts[i]);
    }
    return found ? value : null;
  }

  static final RegExp _index = RegExp(r'^[0-9]+$');

  /// Whether [value] holds [name], and its value.
  static (bool, MustacheValue?) _member(MustacheValue? value, String name) =>
      switch (value) {
        MustacheMap(:final entries) when entries.containsKey(name) => (
          true,
          entries[name],
        ),
        MustacheList(:final items) when _index.hasMatch(name) =>
          switch (int.tryParse(name)) {
            final index? when index < items.length => (true, items[index]),
            _ => (false, null),
          },
        _ => (false, null),
      };
}
