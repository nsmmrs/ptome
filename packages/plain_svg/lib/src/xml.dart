/// Reading XML 1.0 documents (W3C Recommendation, fifth edition) into a
/// tree of elements and text, with namespaces (Namespaces in XML 1.0).
///
/// As the specification has it: line breaks are normalized (2.11),
/// attribute values too (3.3.3), and character references, the predefined
/// entities and the general entities the document type declaration's
/// internal subset declares are replaced (4.4). Comments, processing
/// instructions and the document type declaration leave no node.
///
/// Leniently, as SVG renderers and the earlier reader were: an `&` that
/// starts no reference, a reference to an entity not declared (or to a
/// character XML doesn't allow), and a `<` in an attribute value are kept
/// as they are written, repeated attributes are all kept, and names are
/// any run of characters that aren't markup. What breaks the structure (a
/// tag left open or closed by another, a second root, an attribute without
/// a quoted value) is an error.
library;

/// A node of the tree.
sealed class XmlNode {
  const new();
}

/// Text, from character data or a CDATA section ([cdata]).
final class XmlText extends XmlNode {
  /// [text], from a CDATA section when [cdata].
  const new(this.text, {this.cdata = false});

  /// The text, its references replaced.
  final String text;

  /// Whether it is a CDATA section's.
  final bool cdata;
}

/// An attribute.
final class XmlAttribute {
  /// The attribute [name] (as written: `xlink:href`) with [value], in
  /// [namespaceUri].
  const new(this.name, this.value, this.namespaceUri);

  /// The qualified name, as written.
  final String name;

  /// The value, normalized and its references replaced.
  final String value;

  /// The namespace its prefix is bound to (none without a prefix).
  final String? namespaceUri;

  /// The name without its prefix.
  String get localName => _local(name);
}

/// An element.
final class XmlElement extends XmlNode {
  /// An element named [name] (as written: `svg:rect`) in [namespaceUri].
  new(this.name, this.namespaceUri, this.attributes, this.parent);

  /// The qualified name, as written.
  final String name;

  /// The namespace of its prefix, or the default namespace.
  final String? namespaceUri;

  /// The attributes, in order.
  final List<XmlAttribute> attributes;

  /// The element it is in, or none for the root.
  final XmlElement? parent;

  /// What is in it, in order.
  final List<XmlNode> children = [];

  /// The name without its prefix.
  String get localName => _local(name);

  /// The value of the (first) attribute named [name] as written.
  String? getAttribute(String name) {
    for (final attribute in attributes) {
      if (attribute.name == name) return attribute.value;
    }
    return null;
  }

  /// The value of the (first) attribute [localName] in [namespaceUri].
  String? getAttributeNS(String namespaceUri, String localName) {
    for (final attribute in attributes) {
      if (attribute.namespaceUri == namespaceUri &&
          attribute.localName == localName) {
        return attribute.value;
      }
    }
    return null;
  }

  /// The elements in it.
  Iterable<XmlElement> get childElements => children.whereType<XmlElement>();

  /// The elements in it at any depth, in document order.
  Iterable<XmlElement> get descendantElements sync* {
    for (final child in childElements) {
      yield child;
      yield* child.descendantElements;
    }
  }

  /// All the text in it, at any depth.
  String get innerText {
    final out = StringBuffer();
    void collect(XmlElement element) {
      for (final child in element.children) {
        switch (child) {
          case XmlText(:final text):
            out.write(text);
          case final XmlElement element:
            collect(element);
        }
      }
    }

    collect(this);
    return out.toString();
  }
}

String _local(String name) => name.substring(name.indexOf(':') + 1);

/// The root element of the XML document [text]; throws a
/// [FormatException] (with the line and column) when it isn't one.
XmlElement parseXml(String text) => _Reader(_newlines(text)).document();

/// [text] with each `\r\n` and lone `\r` as `\n` (2.11).
String _newlines(String text) => text.contains('\r')
    ? text.replaceAll('\r\n', '\n').replaceAll('\r', '\n')
    : text;

const String _xmlNamespace = 'http://www.w3.org/XML/1998/namespace';

/// The most text entities may expand to, against documents that blow up
/// (entities of entities of entities...).
const int _expansionLimit = 1 << 22;

final class _Reader {
  new(this._text);

  final String _text;
  int _at = 0;

  /// The general entities the internal subset declares, by name.
  final Map<String, String> _entities = {};

  /// How many characters entities have expanded to.
  int _expanded = 0;

  /// The entities whose replacement this reader reads (to stop recursion).
  final Set<String> _open = {};

  Never _fail(String message, [int? at]) {
    final offset = at ?? _at;
    final before = _text.substring(0, offset.clamp(0, _text.length));
    final line = '\n'.allMatches(before).length + 1;
    final column = offset - before.lastIndexOf('\n');
    throw FormatException('$message (line $line, column $column)');
  }

  XmlElement document() {
    if (_text.startsWith('﻿')) _at = 1;
    _misc(prolog: true);
    if (!_text.startsWith('<', _at) || _at + 1 >= _text.length) {
      _fail('no root element');
    }
    final root = _element(null, const {});
    _misc(prolog: false);
    if (_at < _text.length) {
      _fail(
        _text.startsWith('<', _at)
            ? 'a second root element'
            : 'text after the root element',
      );
    }
    return root;
  }

  bool _space(int c) => c == 0x20 || c == 0x9 || c == 0xa || c == 0xd;

  void _skipSpace() {
    while (_at < _text.length && _space(_text.codeUnitAt(_at))) {
      _at++;
    }
  }

  /// Skips white space, comments and processing instructions, and in the
  /// [prolog] the XML and document type declarations.
  void _misc({required bool prolog}) {
    for (;;) {
      _skipSpace();
      if (_text.startsWith('<!--', _at)) {
        _skipPast('-->', 'comment');
      } else if (_text.startsWith('<?', _at)) {
        _skipPast('?>', 'processing instruction');
      } else if (prolog && _text.startsWith('<!DOCTYPE', _at)) {
        _doctype();
      } else {
        return;
      }
    }
  }

  void _skipPast(String end, String what) {
    final i = _text.indexOf(end, _at);
    if (i < 0) _fail('$what not closed');
    _at = i + end.length;
  }

  /// A document type declaration: its internal subset's general entity
  /// declarations are kept, the rest skipped.
  void _doctype() {
    final start = _at;
    _at += '<!DOCTYPE'.length;
    while (_at < _text.length) {
      switch (_text[_at]) {
        case '>':
          _at++;
          return;
        case '"' || "'":
          _quoted();
        case '[':
          _at++;
          _subset();
        default:
          _at++;
      }
    }
    _fail('document type declaration not closed', start);
  }

  /// The quoted literal at [_at], without its quotes.
  String _quoted() {
    final quote = _text[_at];
    final end = _text.indexOf(quote, _at + 1);
    if (end < 0) _fail('literal not closed');
    final value = _text.substring(_at + 1, end);
    _at = end + 1;
    return value;
  }

  /// The internal subset, up to its `]`.
  void _subset() {
    for (;;) {
      _skipSpace();
      if (_at >= _text.length) _fail('internal subset not closed');
      if (_text.startsWith(']', _at)) {
        _at++;
        return;
      }
      if (_text.startsWith('<!--', _at)) {
        _skipPast('-->', 'comment');
      } else if (_text.startsWith('<?', _at)) {
        _skipPast('?>', 'processing instruction');
      } else if (_text.startsWith('<!ENTITY', _at)) {
        _entity();
      } else if (_text.startsWith('<!', _at)) {
        _declaration();
      } else {
        // A parameter entity reference (`%name;`), or anything else.
        _at++;
      }
    }
  }

  /// A markup declaration, skipped (its literals may hold `>`).
  void _declaration() {
    final start = _at;
    while (_at < _text.length) {
      switch (_text[_at]) {
        case '>':
          _at++;
          return;
        case '"' || "'":
          _quoted();
        default:
          _at++;
      }
    }
    _fail('declaration not closed', start);
  }

  /// An entity declaration: an internal general entity is kept; a
  /// parameter or external one is skipped.
  void _entity() {
    final start = _at;
    _at += '<!ENTITY'.length;
    _skipSpace();
    final parameter = _text.startsWith('%', _at);
    if (parameter) {
      _at++;
      _skipSpace();
    }
    final name = _name();
    _skipSpace();
    if (_at < _text.length && (_text[_at] == '"' || _text[_at] == "'")) {
      final value = _quoted();
      // The first declaration binds (4.2).
      if (!parameter) _entities.putIfAbsent(name, () => value);
    }
    _at = start;
    _declaration();
  }

  bool _nameChar(int c) =>
      !_space(c) &&
      c != 0x3c && // <
      c != 0x3e && // >
      c != 0x2f && // /
      c != 0x3d && // =
      c != 0x22 && // "
      c != 0x27; // '

  String _name() {
    final start = _at;
    while (_at < _text.length && _nameChar(_text.codeUnitAt(_at))) {
      _at++;
    }
    if (_at == start) _fail('a name expected');
    return _text.substring(start, _at);
  }

  /// The element at [_at], in [parent], where [namespaces] binds prefixes
  /// (`''`: the default namespace).
  XmlElement _element(XmlElement? parent, Map<String, String?> namespaces) {
    final start = _at;
    _at++; // <
    final name = _name();
    final raw = <(String, String)>[];
    var empty = false;
    for (;;) {
      final before = _at;
      _skipSpace();
      if (_at >= _text.length) _fail('start tag <$name> not closed', start);
      if (_text.startsWith('/>', _at)) {
        _at += 2;
        empty = true;
        break;
      }
      if (_text.codeUnitAt(_at) == 0x3e) {
        _at++;
        break;
      }
      if (_at == before) _fail('white space expected before an attribute');
      final attribute = _name();
      _skipSpace();
      if (!_text.startsWith('=', _at)) _fail('"=" expected after $attribute');
      _at++;
      _skipSpace();
      if (_at >= _text.length || !(_text[_at] == '"' || _text[_at] == "'")) {
        _fail('a quoted value expected for $attribute');
      }
      raw.add((attribute, _attributeValue(_quoted())));
    }
    // Namespace declarations first: they hold for the element's own name
    // and attributes.
    var scope = namespaces;
    for (final (attribute, value) in raw) {
      if (attribute == 'xmlns' || attribute.startsWith('xmlns:')) {
        if (identical(scope, namespaces)) scope = {...namespaces};
        scope[attribute == 'xmlns' ? '' : attribute.substring(6)] =
            value.isEmpty ? null : value;
      }
    }
    String? namespaceOf(String qualified, {required bool attribute}) {
      final colon = qualified.indexOf(':');
      if (colon < 0) return attribute ? null : scope[''];
      final prefix = qualified.substring(0, colon);
      if (prefix == 'xml') return _xmlNamespace;
      if (prefix == 'xmlns') return 'http://www.w3.org/2000/xmlns/';
      return scope[prefix];
    }

    final element = XmlElement(name, namespaceOf(name, attribute: false), [
      for (final (attribute, value) in raw)
        XmlAttribute(
          attribute,
          value,
          attribute == 'xmlns'
              ? 'http://www.w3.org/2000/xmlns/'
              : namespaceOf(attribute, attribute: true),
        ),
    ], parent);
    if (empty) return element;
    _content(element, scope, name, start);
    return element;
  }

  /// The content of [element] up to its end tag `</name>`; text is
  /// gathered in [pending] (an entity's replacement read as content leaves
  /// its last text there, to go on with what follows the reference).
  void _content(
    XmlElement element,
    Map<String, String?> scope,
    String name,
    int start, [
    StringBuffer? pending,
  ]) {
    final text = pending ?? StringBuffer();
    void flush() {
      if (text.isNotEmpty) {
        element.children.add(XmlText(text.toString()));
        text.clear();
      }
    }

    for (;;) {
      if (_at >= _text.length) _fail('element <$name> not closed', start);
      final c = _text.codeUnitAt(_at);
      if (c == 0x3c) {
        if (_text.startsWith('</', _at)) {
          if (pending == null) flush();
          final end = _at;
          _at += 2;
          final close = _name();
          _skipSpace();
          if (!_text.startsWith('>', _at)) _fail('">" expected');
          _at++;
          if (close != name) {
            if (name.startsWith('\u0000')) {
              _fail('</$close> closes an element the entity did not open', end);
            }
            // (The end of an entity's replacement: the element is open.)
            if (close.startsWith('\u0000')) {
              _fail('element <$name> not closed', start);
            }
            _fail('<$name> closed by </$close>', end);
          }
          return;
        }
        if (_text.startsWith('<![CDATA[', _at)) {
          final end = _text.indexOf(']]>', _at);
          if (end < 0) _fail('CDATA section not closed');
          flush();
          element.children.add(
            XmlText(_text.substring(_at + 9, end), cdata: true),
          );
          _at = end + 3;
        } else if (_text.startsWith('<!--', _at)) {
          flush();
          _skipPast('-->', 'comment');
        } else if (_text.startsWith('<?', _at)) {
          flush();
          _skipPast('?>', 'processing instruction');
        } else {
          flush();
          element.children.add(_element(element, scope));
        }
      } else if (c == 0x26) {
        _reference(element, scope, text);
      } else {
        var end = _at;
        while (end < _text.length) {
          final d = _text.codeUnitAt(end);
          if (d == 0x3c || d == 0x26) break;
          end++;
        }
        text.write(_text.substring(_at, end));
        _at = end;
      }
    }
  }

  static final RegExp _referencePattern = RegExp(
    '&(#[0-9]+|#x[0-9a-fA-F]+|[^\\s&;<>"\']+);',
  );

  /// The reference at [_at] in content: its text added to [text], or a
  /// declared entity's replacement read as content.
  void _reference(
    XmlElement element,
    Map<String, String?> scope,
    StringBuffer text,
  ) {
    final match = _referencePattern.matchAsPrefix(_text, _at);
    if (match == null) {
      text.write('&');
      _at++;
      return;
    }
    _at = match.end;
    final name = match[1]!;
    if (_character(name) ?? _predefined(name) case final replaced?) {
      text.write(replaced);
      return;
    }
    final replacement = _entities[name];
    if (replacement == null) {
      text.write(match[0]);
      return;
    }
    if (!replacement.contains('<')) {
      text.write(_expand(replacement, {..._open, name}, attribute: false));
      return;
    }
    // Markup in the replacement text: read as content in place (4.4.2),
    // by a reader of its own sharing the entities.
    if (_open.contains(name)) {
      text.write(match[0]);
      return;
    }
    _expanded += replacement.length;
    if (_expanded > _expansionLimit) _fail('entities expand too far');
    final marker = '\u0000$name';
    final reader = _Reader('${_newlines(replacement)}</$marker>')
      .._entities.addAll(_entities)
      .._open.addAll({..._open, name})
      .._expanded = _expanded;
    try {
      reader._content(element, scope, marker, 0, text);
    } on FormatException catch (error) {
      final message = error.message;
      final position = message.lastIndexOf(' (line ');
      _fail(
        'in entity &$name;: '
        '${position < 0 ? message : message.substring(0, position)}',
      );
    }
    _expanded = reader._expanded;
  }

  /// The character the reference `&#...;` [name] stands for, or none when
  /// it isn't one or stands for a character XML doesn't allow.
  static String? _character(String name) {
    if (!name.startsWith('#')) return null;
    final code = name.startsWith('#x')
        ? int.tryParse(name.substring(2), radix: 16)
        : int.tryParse(name.substring(1));
    if (code == null) return null;
    final allowed =
        code == 0x9 ||
        code == 0xa ||
        code == 0xd ||
        (code >= 0x20 && code <= 0xd7ff) ||
        (code >= 0xe000 && code <= 0xfffd) ||
        (code >= 0x10000 && code <= 0x10ffff);
    return allowed ? String.fromCharCode(code) : null;
  }

  static String? _predefined(String name) => switch (name) {
    'lt' => '<',
    'gt' => '>',
    'amp' => '&',
    'quot' => '"',
    'apos' => "'",
    _ => null,
  };

  /// [text] with its references replaced, entities [open] being expanded
  /// (to stop recursion); in an [attribute] value, white space becomes
  /// spaces, but what character references give.
  String _expand(String text, Set<String> open, {required bool attribute}) {
    if (!text.contains('&') && !(attribute && text.contains(_whitespace))) {
      return text;
    }
    final out = StringBuffer();
    var at = 0;
    void plain(String part) =>
        out.write(attribute ? part.replaceAll(_whitespace, ' ') : part);
    for (final match in _referencePattern.allMatches(text)) {
      plain(text.substring(at, match.start));
      at = match.end;
      final name = match[1]!;
      if (_character(name) ?? _predefined(name) case final replaced?) {
        out.write(replaced);
        continue;
      }
      final replacement = _entities[name];
      if (replacement == null || open.contains(name) || _open.contains(name)) {
        plain(match[0]!);
        continue;
      }
      _expanded += replacement.length;
      if (_expanded > _expansionLimit) _fail('entities expand too far');
      out.write(_expand(replacement, {...open, name}, attribute: attribute));
    }
    plain(text.substring(at));
    return out.toString();
  }

  String _attributeValue(String raw) => _expand(raw, {}, attribute: true);

  static final RegExp _whitespace = RegExp('[\t\n\r]');
}
