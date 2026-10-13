/// What a language's matchers would work out from its expressions the
/// first time it is used, worked out once by
/// `tool/generate_first_chars.dart` instead: each rule's [FirstChars] and
/// group count ([precomputedTable]). Reading them is several times faster
/// than reading the expressions (TASK-lznpxv: 46 of the 110 ms the first
/// highlighting of a book's listings took).
///
/// The table is unsigned LEB128 numbers and bytes: the number of
/// languages, then for each its name (a length and UTF-8 bytes) and the
/// length of its entries; then each language's entries, one per source
/// [ruleSources] gives, in that order: its group count, the length of
/// its encoded [FirstChars] (see [encodeFirstChars]) and those bytes.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:plain_highlighting/src/compiler_extensions.dart' as ext;
import 'package:plain_highlighting/src/first_chars.dart';
import 'package:plain_highlighting/src/first_chars_table.g.dart';
import 'package:plain_highlighting/src/grammar.dart';
import 'package:plain_highlighting/src/languages/all.g.dart';
import 'package:plain_highlighting/src/mode.dart';
import 'package:plain_highlighting/src/mode_compiler.dart';
import 'package:plain_highlighting/src/regex.dart' as regex;

/// The sources of the rules of the matchers of a compiled language's
/// modes ([root] and every mode it reaches), each once, in the order of
/// a walk of the modes: each mode's contained modes' begins, its
/// terminator and its illegal expression.
List<String> ruleSources(Mode root) {
  final seen = <Mode>{};
  final sources = <String>{};
  void walk(Mode mode) {
    if (!seen.add(mode)) return;
    for (final term in (mode.contains ?? const []).whereType<Mode>()) {
      sources.add(ext.sourceOf(term.begin) ?? '');
      walk(term);
    }
    if (mode.terminatorEnd case final end? when end.isNotEmpty) {
      sources.add(end);
    }
    if (ext.truthy(mode.illegal)) sources.add(ext.sourceOf(mode.illegal)!);
    if (mode.starts case final starts?) walk(starts);
  }

  walk(root);
  return sources.toList();
}

/// The table of every language's rules (see the library's comment),
/// worked out from their expressions.
Uint8List buildPrecomputedTable() {
  // (Worked out afresh: the table there is may be for other grammars.)
  _building = true;
  try {
    return _build();
  } finally {
    _building = false;
  }
}

/// Whether [buildPrecomputedTable] is running (the table isn't read).
bool _building = false;

Uint8List _build() {
  final entries = <(String, Uint8List)>[];
  for (final (_, _, at) in allLanguages) {
    final language = readGrammar(at);
    final root = compileLanguage(language);
    final out = BytesBuilder(copy: false);
    for (final source in ruleSources(root)) {
      _uint(out, regex.countMatchGroups(source));
      final first = BytesBuilder(copy: false);
      encodeFirstChars(
        firstChars(
          source,
          ignoreCase: language.caseInsensitive,
          unicode: language.unicodeRegex,
        ),
        first,
      );
      _uint(out, first.length);
      out.add(first.takeBytes());
    }
    entries.add((language.name, out.takeBytes()));
  }
  final out = BytesBuilder(copy: false);
  _uint(out, entries.length);
  for (final (name, bytes) in entries) {
    final encoded = utf8.encode(name);
    _uint(out, encoded.length);
    out.add(encoded);
    _uint(out, bytes.length);
  }
  for (final (_, bytes) in entries) {
    out.add(bytes);
  }
  return out.takeBytes();
}

void _uint(BytesBuilder out, int value) {
  var v = value;
  while (v >= 0x80) {
    out.addByte((v & 0x7f) | 0x80);
    v >>= 7;
  }
  out.addByte(v);
}

/// The table, decoded.
final Uint8List _table = base64Decode(precomputedTable);

/// Where each language's entries start and end in [_table], by name.
final Map<String, (int, int)> _languages = () {
  var i = 0;
  int uint() {
    var value = 0;
    var shift = 0;
    while (true) {
      final b = _table[i++];
      value |= (b & 0x7f) << shift;
      if (b < 0x80) return value;
      shift += 7;
    }
  }

  final names = <(String, int)>[];
  for (var n = uint(); n > 0; n--) {
    final length = uint();
    final name = utf8.decode(Uint8List.sublistView(_table, i, i + length));
    i += length;
    names.add((name, uint()));
  }
  return {for (final (name, length) in names) name: (i, i += length)};
}();

/// The group count of each rule of the language named [name], in the
/// order of [ruleSources], with where its [FirstChars] is (for
/// [precomputedFirstChars]), or null for a language the table doesn't
/// have.
List<(int, int)>? precomputedRules(String name) {
  // (In JavaScript the matchers search with the platform's engine and
  // never ask: the table is left out.)
  if (_onJavaScript || _building) return null;
  final (start, end) = _languages[name] ?? (-1, -1);
  if (start < 0) return null;
  final rules = <(int, int)>[];
  var i = start;
  int uint() {
    var value = 0;
    var shift = 0;
    while (true) {
      final b = _table[i++];
      value |= (b & 0x7f) << shift;
      if (b < 0x80) return value;
      shift += 7;
    }
  }

  while (i < end) {
    final groups = uint();
    final length = uint();
    rules.add((groups, i));
    i += length;
  }
  return rules;
}

/// The [FirstChars] (or null) at [at] in the table (see
/// [precomputedRules]).
FirstChars? precomputedFirstChars(int at) => decodeFirstChars(_table, at).$1;

/// Whether this runs as JavaScript (or WebAssembly).
const bool _onJavaScript = bool.fromEnvironment('dart.library.js_interop');
