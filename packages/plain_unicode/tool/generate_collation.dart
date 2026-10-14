/// Generates `lib/src/collation_data.g.dart` from CLDR 48.2's collation
/// data in `vendor/cldr/48.2.0/collation`: the root collation (UCA's
/// `allkeys_CLDR.txt`, CLDR's root order) and each locale's tailoring
/// (its `common/collation/<locale>.xml` rules, ICU's syntax), applied
/// here, so the library reads tables, not rules.
///
/// ```sh
/// dart run tool/generate_collation.dart [--import CLDR_COMMON]
/// ```
///
/// With `--import`, the vendored files are copied first from an unpacked
/// `cldr-common-48.2.zip`'s `common` folder (and its conformance test,
/// short and gzipped, to `test/unicode`).
///
/// A tailoring's elements are given weights between the root's (each
/// level's weights kept as fractions while the rules are applied, a long
/// chain of primaries spread evenly over its gap), then every level's
/// weights, the root's and every locale's, are replaced by their ranks,
/// so the tables hold small integers in the same order.
library;

import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

import 'package:plain_unicode/src/bidi.dart' show canonicalCombiningClass;
import 'package:plain_unicode/src/properties.dart';

const String _version = '48.2.0';

/// The locales whose collation the library carries: every CLDR locale
/// with a tailoring, and the types an index chooses among.
const Map<String, List<String>> _types = {
  'zh': ['pinyin', 'stroke'],
  'zh_Hant': ['stroke'],
};

late final String _vendor;

/// The root's greatest tertiary weight.
late final _W _maxRootTertiary;

void main(List<String> args) {
  final root = File(Platform.script.toFilePath()).parent.parent.path;
  _vendor = '$root/vendor/cldr/$_version/collation';
  if (args.length == 2 && args.first == '--import') _import(args[1]);
  final table = _Root.read('$_vendor/allkeys_CLDR.txt');
  _maxRootTertiary = table.entries.values
      .expand((ces) => ces)
      .map((ce) => ce.t)
      .reduce((a, b) => a > b ? a : b);
  final locales = <String, _Tailored>{};
  for (final file
      in Directory(_vendor).listSync().whereType<File>().toList()
        ..sort((a, b) => a.path.compareTo(b.path))) {
    final name = file.uri.pathSegments.last;
    if (!name.endsWith('.xml') || name == 'root.xml') continue;
    final locale = name.substring(0, name.length - 4);
    final wanted = _types[locale] ?? [_defaultType(locale)];
    for (final type in wanted) {
      // (A type the locale names but its parent defines: zh_Hant's
      // stroke, zh's.)
      var source = locale;
      while (!_collationsOf(source).containsKey(type) && source.contains('_')) {
        source = source.substring(0, source.lastIndexOf('_'));
      }
      if (!_collationsOf(source).containsKey(type)) continue;
      final key = type == _defaultType(locale) ? locale : '$locale@$type';
      try {
        locales[key] = _Tailored.apply(table, _rules(source, type));
      } on FormatException catch (e) {
        stderr.writeln('$key: $e (left to the root)');
      }
    }
  }
  _write(root, table, locales);
}

// ---------------------------------------------------------------- weights

/// A collation element: its weights at the three levels (fractions while
/// tailoring), and whether it is variable (punctuation, symbols).
final class _Ce {
  const new(
    this.p,
    this.s,
    this.t, {
    this.variable = false,
    this.cased,
    this.mixed = false,
  });

  final _W p;
  final _W s;
  final _W t;
  final bool variable;

  /// Whether the element is of upper case where the tailoring says (its
  /// string's own case), else null.
  final bool? cased;

  /// Whether the element is of mixed case (a tailored contraction of upper
  /// and lower case letters: `Aa`).
  final bool mixed;

  /// Whether the element is of upper case (for `caseFirst upper`): a
  /// tailored one's as its string's root elements are, a root one's by
  /// its tertiary weight (UCA's 0x08 to 0x0C).
  bool get upper => cased ?? (t.whole >= 0x08 && t.whole <= 0x0c);

  _Ce copyWith({_W? p, _W? s, _W? t, bool? upper, bool? mixed}) => _Ce(
    p ?? this.p,
    s ?? this.s,
    t ?? this.t,
    variable: variable,
    cased: upper ?? cased,
    mixed: mixed ?? this.mixed,
  );

  @override
  String toString() => '[$p.$s.$t]';
}

/// The first primary of the implicit weights (Han, unassigned): UCA's
/// `FB00`, below which the regular weights lie.
final _W _implicitStart = _W.of(0xfb00);

/// A weight, exactly: an integer weight scaled by 2^768, so a tailoring's
/// weights between two can be halved and halved again (hundreds of
/// Korean readings after one syllable's final consonant) and stay apart.
@immutable
final class _W implements Comparable<_W> {
  const new _(this._value);

  /// The integer weight [w].
  new of(int w) : _value = BigInt.from(w) << _bits;

  static const int _bits = 768;
  static final _W zero = _W._(BigInt.zero);
  static final _W one = _W.of(1);

  final BigInt _value;

  _W operator +(_W other) => _W._(_value + other._value);
  _W operator -(_W other) => _W._(_value - other._value);

  /// This weight divided by 2^[n] (n of the low bits, exactly).
  _W shifted(int n) => _W._(_value >> n);

  /// This weight divided by [n].
  _W divide(int n) => _W._(_value ~/ BigInt.from(n));

  /// Halfway between this weight and [other].
  _W halfway(_W other) => _W._((_value + other._value) >> 1);

  /// The integer part.
  int get whole => (_value >> _bits).toInt();

  /// The fraction's top 16 bits.
  int get fraction16 =>
      ((_value - (BigInt.from(whole) << _bits)) >> (_bits - 16)).toInt();

  bool get isZero => _value == BigInt.zero;
  bool get isPositive => _value > BigInt.zero;
  bool operator <(_W other) => _value < other._value;
  bool operator >(_W other) => _value > other._value;
  bool operator <=(_W other) => _value <= other._value;
  bool operator >=(_W other) => _value >= other._value;

  @override
  int compareTo(_W other) => _value.compareTo(other._value);

  @override
  bool operator ==(Object other) => other is _W && other._value == _value;

  @override
  int get hashCode => _value.hashCode;

  @override
  String toString() => '$whole+${fraction16.toRadixString(16)}';
}

/// The root collation: `allkeys_CLDR.txt`'s elements.
final class _Root {
  const new _(this.entries);

  /// The root of `allkeys_CLDR.txt` at [path].
  factory read(String path) {
    final entries = <String, List<_Ce>>{};
    final ce = RegExp(r'\[([.*])([0-9A-F]{4})\.([0-9A-F]{4})\.([0-9A-F]{4})\]');
    for (final line in File(path).readAsLinesSync()) {
      final data = line.split('#').first.trim();
      if (data.isEmpty || data.startsWith('@')) continue;
      final [chars, weights] = data.split(';');
      final key = String.fromCharCodes([
        for (final c in chars.trim().split(' ')) int.parse(c, radix: 16),
      ]);
      final raw = [
        for (final m in ce.allMatches(weights))
          _Ce(
            _W.of(int.parse(m[2]!, radix: 16)),
            _W.of(int.parse(m[3]!, radix: 16)),
            _W.of(int.parse(m[4]!, radix: 16)),
            variable: m[1] == '*',
          ),
      ];
      // (An implicit weight's two elements, its lead `FBxx` and its
      // offset, as one: the library computes them so.)
      final merged = <_Ce>[];
      for (var i = 0; i < raw.length; i++) {
        final ce = raw[i];
        if (ce.p >= _implicitStart &&
            ce.p < _W.of(0xfc00) &&
            i + 1 < raw.length &&
            raw[i + 1].s.isZero &&
            raw[i + 1].t.isZero) {
          merged.add(ce.copyWith(p: ce.p + raw[i + 1].p.shifted(16)));
          i++;
        } else {
          merged.add(ce);
        }
      }
      entries[key] = merged;
    }
    return _Root._(entries);
  }

  /// The elements of each string (a code point or a contraction).
  final Map<String, List<_Ce>> entries;
}

/// The implicit elements of [c] (UTS #10 10.1.3): Han and the scripts
/// with implicit weights by their own bases, the rest as unassigned.
List<_Ce> _implicit(int c) {
  final (int base, int offset) = switch (c) {
    // (UCA 17's Table 16: Tangut and its supplement; its components
    // and theirs; Nushu; Khitan.)
    >= 0x17000 && <= 0x187ff ||
    >= 0x18d00 && <= 0x18d7f => (0xfb00, c - 0x17000),
    >= 0x18800 && <= 0x18aff ||
    >= 0x18d80 && <= 0x18dff => (0xfb01, c - 0x18800),
    >= 0x1b170 && <= 0x1b2ff => (0xfb02, c - 0x1b170),
    >= 0x18b00 && <= 0x18cff => (0xfb03, c - 0x18b00),
    _ when _isUnifiedIdeograph(c) =>
      (c >= 0x4e00 && c <= 0x9fff) || (c >= 0xf900 && c <= 0xfaff)
          ? (0xfb40 + (c >> 15), c & 0x7fff)
          : (0xfb80 + (c >> 15), c & 0x7fff),
    _ => (0xfbc0 + (c >> 15), c & 0x7fff),
  };
  return [
    _Ce(
      _W.of(base) + _W.of(offset | 0x8000).shifted(16),
      _W.of(0x20),
      _W.of(0x02),
    ),
  ];
}

/// The Unified_Ideograph ranges (PropList.txt).
final List<(int, int)> _unifiedIdeographs = () {
  final out = <(int, int)>[];
  final file = File(
    '${File(Platform.script.toFilePath()).parent.parent.path}'
    '/vendor/ucd/17.0.0/PropList.txt',
  );
  for (final line in file.readAsLinesSync()) {
    final data = line.split('#').first.trim();
    if (!data.contains('Unified_Ideograph')) continue;
    final range = data.split(';').first.trim().split('..');
    final first = int.parse(range.first, radix: 16);
    out.add((first, range.length > 1 ? int.parse(range[1], radix: 16) : first));
  }
  return out;
}();

bool _isUnifiedIdeograph(int c) =>
    _unifiedIdeographs.any((r) => c >= r.$1 && c <= r.$2);

/// [text]'s canonical decomposition, its marks in canonical order.
List<int> _nfd(String text) {
  final out = <int>[];
  void decompose(int c) {
    switch (canonicalDecomposition(c)) {
      case (final first, final second):
        decompose(first);
        if (second != null) decompose(second);
      case null:
        out.add(c);
    }
  }

  text.runes.forEach(decompose);
  for (var i = 0; i < out.length;) {
    if (canonicalCombiningClass(out[i]) == 0) {
      i++;
      continue;
    }
    var end = i;
    while (end < out.length && canonicalCombiningClass(out[end]) != 0) {
      end++;
    }
    final run = out.sublist(i, end).indexed.toList()
      ..sort((a, b) {
        final d = canonicalCombiningClass(a.$2) - canonicalCombiningClass(b.$2);
        return d != 0 ? d : a.$1 - b.$1;
      });
    out.setRange(i, end, [for (final (_, c) in run) c]);
    i = end;
  }
  return out;
}

/// The elements of [text] in [entries] (longest contractions first,
/// contiguous: the strings a rule names), else implicit.
List<_Ce> _elementsOf(Map<String, List<_Ce>> entries, String text) {
  final cps = _nfd(text);
  final out = <_Ce>[];
  for (var i = 0; i < cps.length;) {
    var matched = false;
    for (var end = cps.length; end > i; end--) {
      final key = String.fromCharCodes(cps.sublist(i, end));
      if (entries[key] case final ces?) {
        out.addAll(ces);
        i = end;
        matched = true;
        break;
      }
    }
    if (!matched) {
      out.addAll(_implicit(cps[i]));
      i++;
    }
  }
  return out;
}

// ----------------------------------------------------------------- rules

/// The `<collation>` types of [locale]'s file, with their rules.
Map<String, String> _collationsOf(String locale) {
  final file = File('$_vendor/$locale.xml');
  if (!file.existsSync()) return const {};
  final xml = file.readAsStringSync();
  // (A type's `alt='short'` version where it has one: ICU builds its data
  // from them, the rarer characters left to their implicit order.)
  final out = <String, String>{};
  final short = <String>{};
  for (final m in RegExp(
    r'''<collation\s+type=['"]([\w-]+)['"]([^>]*)>(.*?)</collation\s*>''',
    dotAll: true,
  ).allMatches(xml)) {
    final type = m[1]!;
    final isShort =
        m[2]!.contains("alt='short'") || m[2]!.contains('alt="short"');
    if (m[2]!.contains('alt=') && !isShort) continue;
    if (!isShort && short.contains(type)) continue;
    if (isShort) short.add(type);
    out[type] = [
      for (final r in RegExp(
        r'<!\[CDATA\[(.*?)\]\]>',
        dotAll: true,
      ).allMatches(m[3]!))
        r[1]!,
    ].join('\n');
  }
  return out;
}

/// The collation [locale] uses by default (its `defaultCollation`, else
/// `standard`).
String _defaultType(String locale) {
  final file = File('$_vendor/$locale.xml');
  if (file.existsSync()) {
    final m = RegExp(r'<defaultCollation>([\w-]+)</defaultCollation>')
        .firstMatch(file.readAsStringSync());
    if (m != null) return m[1]!;
  }
  return 'standard';
}

/// The rules of [locale]'s collation [type], imports resolved, comments
/// out.
String _rules(String locale, String type, [Set<String>? seen]) {
  final visited = seen ?? <String>{};
  if (!visited.add('$locale/$type')) return '';
  final source = locale == 'und' ? 'root' : locale;
  final rules = _collationsOf(source)[type];
  if (rules == null) {
    throw FormatException('no collation $type in $source');
  }
  final out = StringBuffer();
  for (final line in rules.split('\n')) {
    final text = _stripComment(line);
    final import = RegExp(r'\[import\s+([\w-]+?)(?:-u-co-([\w-]+))?\]')
        .firstMatch(text);
    if (import != null) {
      final from = import[1]!.replaceAll('-', '_');
      final what = switch (import[2]) {
        null => _defaultType(from == 'und' ? 'root' : from),
        final short => _longTypes[short] ?? short,
      };
      out
        ..writeln(_rules(from, what, visited))
        ..writeln(text.replaceRange(import.start, import.end, ''));
    } else {
      out.writeln(text);
    }
  }
  return out.toString();
}

/// Between a prefixed entry's prefix and its string, in an entry's key
/// (a noncharacter: no text has it).
const String _prefixed = '\ufffe';

/// An unquoted `-`, in a string as read: a range in a starred list
/// (`<*a-z`), else a hyphen.
const String _range = '\uffff';

/// The characters of a starred list [text], its ranges spread out.
List<String> _starred(String text) {
  final runes = text.runes.toList();
  final out = <String>[];
  for (var i = 0; i < runes.length; i++) {
    if (i + 2 < runes.length && runes[i + 1] == 0xffff) {
      for (var c = runes[i]; c <= runes[i + 2]; c++) {
        out.add(String.fromCharCode(c));
      }
      i += 2;
    } else if (runes[i] == 0xffff) {
      out.add('-');
    } else {
      out.add(String.fromCharCode(runes[i]));
    }
  }
  return out;
}

/// [text] with its `\uXXXX` and `\UXXXXXXXX` escapes resolved.
String _unescape(String text) => text.replaceAllMapped(
  RegExp(r'\\u([0-9A-Fa-f]{4})|\\U([0-9A-Fa-f]{8})'),
  (m) => String.fromCharCode(int.parse(m[1] ?? m[2]!, radix: 16)),
);

/// The collation types by their BCP 47 names (`-u-co-phonebk`).
const Map<String, String> _longTypes = {
  'phonebk': 'phonebook',
  'trad': 'traditional',
  'dict': 'dictionary',
  'gb2312': 'gb2312han',
  'big5han': 'big5han',
};

/// [line] without its `#` comment (one outside quotes).
String _stripComment(String line) {
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (c == r'\') {
      i++;
    } else if (c == "'") {
      quoted = !quoted;
    } else if (c == '#' && !quoted) {
      return line.substring(0, i);
    }
  }
  return line;
}

/// A token of a tailoring's rules.
sealed class _Token;

/// `[option ...]`.
final class _Option extends _Token {
  new(this.text);
  final String text;
}

/// `&` and what it resets to, a string or a special position, with
/// `[before n]`.
final class _Reset extends _Token {
  new(this.text, {this.before = 0, this.special});
  final String text;
  final int before;
  final String? special;
}

/// A relation: its strength (1-3, 4 for `=`), whether starred (each
/// character an element), its prefix and extension, and its string.
final class _Relation extends _Token {
  new(
    this.strength,
    this.text, {
    this.star = false,
    this.prefix,
    this.extension,
  });
  final int strength;
  final String text;
  final bool star;
  final String? prefix;
  final String? extension;
}

/// The tokens of [rules] (ICU's syntax: quoting with `'`, `\uXXXX` and
/// `\UXXXXXXXX` escapes, whitespace ignored outside quotes).
List<_Token> _tokens(String rules) {
  final tokens = <_Token>[];
  var i = 0;
  String readString() {
    final out = StringBuffer();
    while (i < rules.length) {
      final c = rules[i];
      if (c == "'") {
        final end = rules.indexOf("'", i + 1);
        if (end == i + 1) {
          out.write("'");
        } else {
          // (Escapes count inside quotes too: `'\uFDD0A'`.)
          out.write(_unescape(rules.substring(i + 1, end)));
        }
        i = end + 1;
      } else if (c == r'\') {
        final n = rules[i + 1];
        if (n == 'u') {
          out.writeCharCode(
            int.parse(rules.substring(i + 2, i + 6), radix: 16),
          );
          i += 6;
        } else if (n == 'U') {
          out.writeCharCode(
            int.parse(rules.substring(i + 2, i + 10), radix: 16),
          );
          i += 10;
        } else {
          out.write(n);
          i += 2;
        }
      } else if (RegExp('[\\s\u200e\u200f&<=|/\\[\\]]').hasMatch(c)) {
        break;
      } else if (c == '-') {
        // (Unquoted, a range in a starred list: marked.)
        out.write(_range);
        i++;
      } else {
        final unit = rules.codeUnitAt(i);
        if (unit >= 0xd800 && unit <= 0xdbff && i + 1 < rules.length) {
          out
            ..writeCharCode(unit)
            ..writeCharCode(rules.codeUnitAt(i + 1));
          i += 2;
        } else {
          out.writeCharCode(unit);
          i++;
        }
      }
    }
    return out.toString();
  }

  void skipSpace() {
    // (Pattern_White_Space: the directional marks too.)
    while (i < rules.length && RegExp('[\\s\u200e\u200f]').hasMatch(rules[i])) {
      i++;
    }
  }

  while (true) {
    skipSpace();
    if (i >= rules.length) break;
    final c = rules[i];
    if (c == '[') {
      var depth = 0;
      final start = i;
      do {
        if (rules[i] == '[') depth++;
        if (rules[i] == ']') depth--;
        i++;
      } while (depth > 0 && i < rules.length);
      tokens.add(_Option(rules.substring(start + 1, i - 1).trim()));
    } else if (c == '&') {
      i++;
      skipSpace();
      var before = 0;
      String? special;
      while (i < rules.length && rules[i] == '[') {
        final end = rules.indexOf(']', i);
        final inner = rules.substring(i + 1, end).trim();
        i = end + 1;
        skipSpace();
        if (inner.startsWith('before')) {
          before = int.parse(inner.split(RegExp(r'\s+')).last);
        } else {
          special = inner;
        }
      }
      tokens.add(
        _Reset(
          special != null ? '' : readString().replaceAll(_range, '-'),
          before: before,
          special: special,
        ),
      );
    } else if (c == '<' || c == '=') {
      var strength = 0;
      if (c == '=') {
        strength = 4;
        i++;
      } else {
        while (i < rules.length && rules[i] == '<') {
          strength++;
          i++;
        }
      }
      final star = i < rules.length && rules[i] == '*';
      if (star) i++;
      skipSpace();
      var text = readString();
      skipSpace();
      String? prefix;
      if (i < rules.length && rules[i] == '|') {
        i++;
        skipSpace();
        prefix = text.replaceAll(_range, '-');
        text = readString();
        skipSpace();
      }
      String? extension;
      if (i < rules.length && rules[i] == '/') {
        i++;
        skipSpace();
        extension = readString().replaceAll(_range, '-');
      }
      tokens.add(
        _Relation(
          strength,
          text,
          star: star,
          prefix: prefix,
          extension: extension,
        ),
      );
    } else {
      throw FormatException('unexpected ${jsonEncode(c)} at $i');
    }
  }
  return tokens;
}

// -------------------------------------------------------------- tailoring

/// A locale's tailoring: the entries it changes (strings, and prefixed
/// strings `prefix|string`), its options, its reordering, and the root
/// contractions it suppresses.
final class _Tailored {
  new _();

  final Map<String, List<_Ce>> entries = {};
  final List<String> options = [];
  List<String> reorder = const [];
  final Set<String> suppressed = {};

  static _Tailored apply(_Root root, String rules) {
    final t = _Tailored._();
    final table = Map<String, List<_Ce>>.of(root.entries);
    // The weights in use at each level, for the gaps between them.
    final primaries = _Weights.of(
      table.values
          .expand((ces) => ces)
          .map((ce) => ce.p)
          .where((p) => p.isPositive),
    );
    // (Secondaries in use with each primary, tertiaries with each primary
    // and secondary: they are compared only there.)
    final secondaries = _LevelWeights();
    final tertiaries = _LevelWeights();
    for (final ce in table.values.expand((ces) => ces)) {
      if (ce.s.isPositive) secondaries.of(ce.p).add(ce.s);
      if (ce.t.isPositive) tertiaries.of(ce.p, ce.s).add(ce.t);
    }
    final tokens = _tokens(rules);
    List<_Ce>? current;
    // (The next primary below which a chain's primaries fit, and its step.)
    _W? ceiling;
    var step = _W.zero;
    for (var k = 0; k < tokens.length; k++) {
      switch (tokens[k]) {
        case _Option(:final text):
          final words = text.split(RegExp(r'\s+'));
          switch (words.first) {
            case 'reorder':
              t.reorder = words.sublist(1);
            case 'suppressContractions':
              final set = _unicodeSet(
                text.substring('suppressContractions'.length).trim(),
              );
              for (final key in [...table.keys]) {
                if (key.runes.length > 1 && set.contains(key.runes.first)) {
                  table.remove(key);
                  t.suppressed.add(key);
                }
              }
            case 'caseFirst' ||
                'backwards' ||
                'alternate' ||
                'strength' ||
                'caseLevel':
              t.options.add(text);
            case 'normalization' || 'optimize' || 'import':
              break;
            default:
              throw FormatException('option [$text]');
          }
        case _Reset(:final text, :final before, :final special):
          var ces = special != null
              ? _special(table, special)
              : _elementsOf(table, text);
          if (ces.isEmpty) throw FormatException('reset to nothing: $text');
          if (before > 0) {
            ces = _before(ces, before, primaries, secondaries, tertiaries);
          }
          current = ces;
          // The chain's primaries spread over the gap after the reset.
          var count = 0;
          for (var j = k + 1; j < tokens.length; j++) {
            final next = tokens[j];
            if (next is _Reset) break;
            if (next is _Relation && next.strength == 1) {
              count += next.star ? _starred(next.text).length : 1;
            }
          }
          final last = ces.lastWhere(
            (ce) => ce.p.isPositive,
            orElse: () => ces.last,
          );
          ceiling = primaries.firstAfter(last.p) ?? last.p + _W.one;
          // (Regular weights stay below the implicit ones: a chain after
          // the last regular primary, Han by pinyin, fills that gap.)
          if (last.p < _implicitStart && ceiling > _implicitStart) {
            ceiling = _implicitStart;
          }
          step = (ceiling - last.p).divide(count + 1);
        case final _Relation relation:
          if (current == null) {
            throw const FormatException('relation before reset');
          }
          final strings = relation.star
              ? _starred(relation.text)
              : [relation.text.replaceAll(_range, '-')];
          for (final string in strings) {
            final ces = _after(
              current!,
              relation.strength,
              step,
              ceiling!,
              primaries,
              secondaries,
              tertiaries,
            );
            current = ces;
            // (Its case its own, as its root elements have it.)
            final roots = [
              for (final ce in _elementsOf(root.entries, string))
                if (ce.p.isPositive) ce,
            ];
            final uppers = roots.where((ce) => ce.upper).length;
            final upper = uppers > 0 && uppers == roots.length;
            final mixed = uppers > 0 && uppers < roots.length;
            final cased = [
              for (final (i, ce) in ces.indexed)
                if (i == ces.length - 1)
                  ce.copyWith(upper: upper, mixed: mixed)
                else
                  ce,
            ];
            final full = [
              ...cased,
              if (relation.extension case final e?) ..._elementsOf(table, e),
            ];
            final key = relation.prefix == null
                ? String.fromCharCodes(_nfd(string))
                : '${String.fromCharCodes(_nfd(relation.prefix!))}$_prefixed'
                      '${String.fromCharCodes(_nfd(string))}';
            if (relation.prefix == null) table[key] = full;
            t.entries[key] = full;
          }
      }
    }
    return t;
  }
}

/// The elements of a special reset position.
List<_Ce> _special(Map<String, List<_Ce>> table, String position) {
  final all = table.values.expand((ces) => ces).toList();
  List<_Ce> pick(bool Function(_Ce ce) test, {required bool last}) {
    final matching = all.where(test).toList()
      ..sort((a, b) {
        final p = a.p.compareTo(b.p);
        if (p != 0) return p;
        final s = a.s.compareTo(b.s);
        return s != 0 ? s : a.t.compareTo(b.t);
      });
    if (matching.isEmpty) throw FormatException('no [$position]');
    return [if (last) matching.last else matching.first];
  }

  return switch (position) {
    'last regular' => pick(
      (ce) => ce.p.isPositive && !ce.variable && ce.p < _implicitStart,
      last: true,
    ),
    'first regular' => pick(
      (ce) => ce.p.isPositive && !ce.variable,
      last: false,
    ),
    'last variable' => pick((ce) => ce.variable, last: true),
    'first variable' => pick((ce) => ce.variable, last: false),
    'last primary ignorable' => pick(
      (ce) => ce.p.isZero && ce.s.isPositive,
      last: true,
    ),
    'first primary ignorable' => pick(
      (ce) => ce.p.isZero && ce.s.isPositive,
      last: false,
    ),
    // (CLDR's root has no element of tertiary weight alone: these are
    // the completely ignorable one, as ICU has them.)
    // (CLDR's root has no element of tertiary weight alone: these are the
    // completely ignorable one, as ICU has them.)
    'last secondary ignorable' ||
    'first secondary ignorable' ||
    'last tertiary ignorable' ||
    'first tertiary ignorable' => [_Ce(_W.zero, _W.zero, _W.zero)],
    _ => throw FormatException('reset [$position]'),
  };
}

/// [ces] moved just before themselves at [level]: their last element's
/// weight at that level the one between it and the one before.
List<_Ce> _before(
  List<_Ce> ces,
  int level,
  _Weights primaries,
  _LevelWeights secondaries,
  _LevelWeights tertiaries,
) {
  final last = ces.last;
  final _Ce moved;
  switch (level) {
    case 1:
      final below = primaries.lastBefore(last.p) ?? _W.zero;
      final p = below.halfway(last.p);
      primaries.add(p);
      moved = last.copyWith(p: p);
    case 2:
      final below = secondaries.of(last.p).lastBefore(last.s) ?? _W.zero;
      final s = below.halfway(last.s);
      secondaries.of(last.p).add(s);
      moved = last.copyWith(s: s);
    default:
      final below = tertiaries.of(last.p, last.s).lastBefore(last.t) ?? _W.zero;
      final t = below.halfway(last.t);
      tertiaries.of(last.p, last.s).add(t);
      moved = last.copyWith(t: t);
  }
  return [...ces.sublist(0, ces.length - 1), moved];
}

/// The elements of a string just after [current] at [strength]: a
/// primary [step] on (below [ceiling]), a secondary or tertiary halfway
/// to the next in use; the same for `=`.
List<_Ce> _after(
  List<_Ce> current,
  int strength,
  _W step,
  _W ceiling,
  _Weights primaries,
  _LevelWeights secondaries,
  _LevelWeights tertiaries,
) {
  if (strength == 4) return current;
  final head = current.sublist(0, current.length - 1);
  final last = current.last;
  switch (strength) {
    case 1:
      var p = last.p + step;
      if (p >= ceiling) p = last.p.halfway(ceiling);
      primaries.add(p);
      secondaries.of(p).add(_W.of(0x20));
      tertiaries.of(p, _W.of(0x20)).add(_W.of(0x02));
      return [...head, _Ce(p, _W.of(0x20), _W.of(0x02))];
    case 2:
      final set = secondaries.of(last.p);
      final s = last.s.halfway(set.firstAfter(last.s) ?? last.s + _W.one);
      set.add(s);
      tertiaries.of(last.p, s).add(_W.of(0x02));
      return [...head, _Ce(last.p, s, _W.of(0x02), variable: last.variable)];
    default:
      final set = tertiaries.of(last.p, last.s);
      // (A tertiary difference after a completely ignorable element is
      // above every tertiary weight of the root, as ICU has it: Arabic's
      // and Urdu's vowel marks.)
      final base = last.p.isZero && last.s.isZero && last.t.isZero
          ? _maxRootTertiary
          : last.t;
      final t = base.halfway(set.firstAfter(base) ?? base + _W.one);
      set.add(t);
      return [...head, last.copyWith(t: t)];
  }
}

/// A level's weights in use, in order.
final class _Weights {
  new of(Iterable<_W> values) {
    for (final v in values) {
      _map[v] = true;
    }
  }

  final SplayTreeMap<_W, bool> _map = SplayTreeMap();

  void add(_W weight) => _map[weight] = true;

  /// The least weight above [weight], if any.
  _W? firstAfter(_W weight) => _map.firstKeyAfter(weight);

  /// The greatest weight below [weight], if any.
  _W? lastBefore(_W weight) => _map.lastKeyBefore(weight);
}

/// A level's weights in use by the weights above it: secondaries by
/// primary, tertiaries by primary and secondary.
final class _LevelWeights {
  final Map<(_W, _W?), _Weights> _sets = {};

  _Weights of(_W primary, [_W? secondary]) =>
      _sets[(primary, secondary)] ??= _Weights.of(const []);
}

/// The code points of a UnicodeSet pattern (`[Љ-ђ]`, `[ab]`): ranges and
/// characters.
Set<int> _unicodeSet(String pattern) {
  final inner = pattern.replaceAll(RegExp(r'^\[|\]$'), '');
  final runes = inner.runes.toList();
  final out = <int>{};
  for (var i = 0; i < runes.length; i++) {
    if (i + 2 < runes.length && runes[i + 1] == 0x2d) {
      for (var c = runes[i]; c <= runes[i + 2]; c++) {
        out.add(c);
      }
      i += 2;
    } else {
      out.add(runes[i]);
    }
  }
  return out;
}

// ---------------------------------------------------------------- output

void _write(String root, _Root table, Map<String, _Tailored> locales) {
  final ideographs = [
    for (final (a, b) in _unifiedIdeographs) ...[a, b],
  ].map((c) => '0x${c.toRadixString(16)}').join(', ');
  // Every level's weights ranked: the root's and every tailoring's.
  final allCes = [
    ...table.entries.values.expand((c) => c),
    for (final t in locales.values) ...t.entries.values.expand((c) => c),
  ];
  Map<_W, int> rank(Iterable<_W> values) {
    final sorted = values.toSet().toList()..sort();
    return {for (final (i, v) in sorted.indexed) v: i};
  }

  // (Primaries from the implicit start on keep their own values above
  // every rank: the implicit weights are computed from code points.)
  final pRank = rank(allCes.map((c) => c.p).where((p) => p < _implicitStart));
  final sRank = rank(allCes.map((c) => c.s));
  final tRank = rank(allCes.map((c) => c.t));
  String encode(List<_Ce> ces) => [
    for (final ce in ces)
      [
        (ce.p >= _implicitStart
                ? (1 << 40) + (ce.p.whole << 32) + (ce.p.fraction16 << 16)
                : pRank[ce.p]!)
            .toRadixString(36),
        sRank[ce.s]!.toRadixString(36),
        tRank[ce.t]!.toRadixString(36),
        '${ce.variable ? '*' : ''}${ce.upper ? 'u' : ''}${ce.mixed ? 'm' : ''}',
      ].join(','),
  ].join(' ');
  String key(String s) =>
      [for (final r in s.runes) r.toRadixString(16)].join(' ');

  final rootLines = StringBuffer()
    ..writeln(
      'W ${sRank[_W.of(0x20)]!.toRadixString(36)} '
      '${tRank[_W.of(0x02)]!.toRadixString(36)}',
    );
  // The tertiary weights of upper case (UCA's 0x08 to 0x0C), for
  // `caseFirst upper`.
  final uppers = [
    for (final MapEntry(key: t, value: r) in tRank.entries)
      if (t.whole >= 0x08 && t.whole <= 0x0c) r.toRadixString(36),
  ];
  rootLines.writeln('U ${uppers.join(' ')}');
  // Each primary's group, for `[reorder]`: the special groups by their
  // characters' general category, else their script; runs of primaries
  // of one group, by their first.
  // (The special groups are the root order's start, up to its last digit:
  // past it, a primary is of its characters' script, punctuation of a
  // script sorted with its letters, Tibetan's shad, included.)
  var lastDigit = 0;
  for (final MapEntry(key: string, value: ces) in table.entries.entries) {
    if (string.runes.length != 1) continue;
    if (_groupOf(string.runes.first) != 'digit') continue;
    for (final ce in ces) {
      if (ce.p.isPositive &&
          ce.p < _implicitStart &&
          pRank[ce.p]! > lastDigit) {
        lastDigit = pRank[ce.p]!;
      }
    }
  }
  final groupOf = <int, String>{};
  void classify(String key, List<_Ce> ces) {
    if (key.runes.length != 1 && !key.startsWith('\ufdd0')) return;
    final c = key.runes.first;
    // (Chinese's index boundaries: Han's, with the characters they mark.)
    if (c == 0xfdd0) {
      for (final ce in ces) {
        if (ce.p.isPositive && ce.p < _implicitStart) {
          groupOf[pRank[ce.p]!] ??= 'Hani';
        }
      }
      return;
    }
    for (final ce in ces) {
      if (!ce.p.isPositive || ce.p >= _implicitStart) continue;
      final rank = pRank[ce.p]!;
      var group = _groupOf(c);
      if (rank > lastDigit && _specialGroups.contains(group)) {
        group = switch (scriptOf(c)) {
          'Zyyy' || 'Zinh' || 'Zzzz' => group,
          'Hira' || 'Kana' => 'Kana',
          final script => script,
        };
      } else if (rank <= lastDigit && !_specialGroups.contains(group)) {
        group = 'symbol';
      }
      groupOf[rank] ??= group;
      break;
    }
  }

  for (final MapEntry(:key, :value) in table.entries.entries) {
    classify(key, value);
  }
  for (final t in locales.values) {
    for (final MapEntry(:key, :value) in t.entries.entries) {
      classify(key, value);
    }
  }
  // The variable top (ICU's maxVariable, punct): the last primary of the
  // space and punctuation groups, for `alternate shifted`.
  // (The root's alone: a tailoring may put punctuation anywhere.)
  var variableTop = 0;
  for (final MapEntry(key: string, value: ces) in table.entries.entries) {
    if (string.runes.length != 1) continue;
    final group = _groupOf(string.runes.first);
    if (group != 'space' && group != 'punct') continue;
    for (final ce in ces) {
      if (ce.p.isPositive &&
          ce.p < _implicitStart &&
          pRank[ce.p]! > variableTop) {
        variableTop = pRank[ce.p]!;
      }
    }
  }
  rootLines.writeln('V ${variableTop.toRadixString(36)}');
  String? last;
  for (var r = 0; r < pRank.length; r++) {
    final group = groupOf[r] ?? last;
    if (group != null && group != last) {
      rootLines.writeln('G ${r.toRadixString(36)} $group');
      last = group;
    }
  }
  for (final MapEntry(key: s, value: ces) in table.entries.entries) {
    rootLines.writeln('${key(s)}\t${encode(ces)}');
  }
  final out = StringBuffer()
    ..writeln(
      '// GENERATED by tool/generate_collation.dart from CLDR $_version',
    )
    ..writeln('// (vendor/cldr/$_version/collation). Do not edit.')
    ..writeln('// dart format off')
    ..writeln('// ignore_for_file: lines_longer_than_80_chars')
    ..writeln()
    ..writeln("part of 'collation.dart';")
    ..writeln()
    ..writeln('/// The root collation, brotli-compressed, in base64.')
    ..writeln("const String _rootData = '${_compress('$rootLines')}';")
    ..writeln()
    ..writeln("/// Each locale's tailoring (`zh@stroke`: a type besides its")
    ..writeln('/// default), brotli-compressed, in base64.')
    ..writeln('const Map<String, String> _localeData = {');
  for (final MapEntry(key: locale, value: t) in locales.entries) {
    final lines = StringBuffer();
    for (final o in t.options) {
      lines.writeln('O $o');
    }
    if (t.reorder.isNotEmpty) lines.writeln('R ${t.reorder.join(' ')}');
    for (final s in t.suppressed) {
      lines.writeln('S ${key(s)}');
    }
    for (final MapEntry(key: s, value: ces) in t.entries.entries) {
      final at = s.indexOf(_prefixed);
      lines.writeln(
        at < 0
            ? '${key(s)}\t${encode(ces)}'
            : 'P ${key(s.substring(0, at))}|${key(s.substring(at + 1))}\t'
                  '${encode(ces)}',
      );
    }
    out.writeln("  '$locale': '${_compress('$lines')}',");
  }
  out
    ..writeln('};')
    ..writeln()
    ..writeln(
      '/// The Unified_Ideograph ranges (first and last, in pairs), for',
    )
    ..writeln("/// the implicit weights' bases.")
    ..writeln('const List<int> _unifiedIdeographs = [$ideographs];')
    ..writeln()
    ..writeln("/// Each language's index characters (CLDR's exemplars), for an")
    ..writeln("/// index's headings.")
    ..writeln('const Map<String, String> _indexCharacters = {');
  for (final line in File('$_vendor/index_characters.tsv').readAsLinesSync()) {
    if (line.startsWith('#') || !line.contains('\t')) continue;
    final [locale, pattern] = line.split('\t');
    out.writeln("  '$locale': ${_dartString(pattern)},");
  }
  out.writeln('};');
  File('$root/lib/src/collation_data.g.dart').writeAsStringSync('$out');
  stdout.writeln(
    'wrote the root (${table.entries.length} entries) and '
    '${locales.length} tailorings; ${pRank.length} primaries',
  );
}

const Set<String> _specialGroups = {
  'space',
  'punct',
  'symbol',
  'currency',
  'digit',
};

/// The group of [c] for reordering: `space`, `punct`, `symbol`,
/// `currency`, `digit`, else its script (`Latn`; Han, kana and Hangul as
/// `Hani`, `Kana` and `Hang`, ICU's group codes).
String _groupOf(int c) => switch (generalCategory(c)) {
  GeneralCategory.spaceSeparator ||
  GeneralCategory.lineSeparator ||
  GeneralCategory.paragraphSeparator ||
  GeneralCategory.control => 'space',
  GeneralCategory.currencySymbol => 'currency',
  GeneralCategory.decimalNumber ||
  GeneralCategory.otherNumber ||
  GeneralCategory.letterNumber when scriptOf(c) == 'Zyyy' => 'digit',
  GeneralCategory.decimalNumber => 'digit',
  GeneralCategory.connectorPunctuation ||
  GeneralCategory.dashPunctuation ||
  GeneralCategory.openPunctuation ||
  GeneralCategory.closePunctuation ||
  GeneralCategory.initialPunctuation ||
  GeneralCategory.finalPunctuation ||
  GeneralCategory.otherPunctuation => 'punct',
  GeneralCategory.mathSymbol ||
  GeneralCategory.modifierSymbol ||
  GeneralCategory.otherSymbol => 'symbol',
  _ => switch (scriptOf(c)) {
    'Hira' || 'Kana' => 'Kana',
    'Zinh' || 'Zyyy' => 'symbol',
    final script => script,
  },
};

/// [text] as a Dart string literal, its non-ASCII characters escaped.
String _dartString(String text) {
  final out = StringBuffer("'");
  for (final r in text.runes) {
    if (r == 0x27 || r == 0x5c || r == 0x24) {
      out.write('\\${String.fromCharCode(r)}');
    } else if (r < 0x20 || r > 0x7e) {
      out.write('\\u{${r.toRadixString(16)}}');
    } else {
      out.writeCharCode(r);
    }
  }
  out.write("'");
  return '$out';
}

String _compress(String text) {
  final input = File('${Directory.systemTemp.path}/collation-in.txt')
    ..writeAsStringSync(text);
  final result = Process.runSync('brotli', [
    '-c',
    '-q',
    '11',
    input.path,
  ], stdoutEncoding: null);
  if (result.exitCode != 0) throw StateError('brotli: ${result.stderr}');
  return base64.encode(result.stdout as List<int>);
}

/// Copies the vendored files from CLDR's `common` folder [common].
void _import(String common) {
  Directory(_vendor).createSync(recursive: true);
  File('$common/uca/allkeys_CLDR.txt').copySync('$_vendor/allkeys_CLDR.txt');
  // (The conformance test, its short form, gzipped for the tests.)
  final test = File('$common/uca/CollationTest_CLDR_NON_IGNORABLE_SHORT.txt')
      .readAsBytesSync();
  File(
    '${Directory(_vendor).parent.parent.parent.parent.path}'
    '/test/unicode/CollationTest_CLDR_NON_IGNORABLE_SHORT.txt.gz',
  ).writeAsBytesSync(gzip.encode(test));
  for (final f in Directory('$common/collation').listSync().whereType<File>()) {
    f.copySync('$_vendor/${f.uri.pathSegments.last}');
  }
  // Each language's index characters (its `exemplarCharacters`
  // `type="index"`), for an index's headings.
  final index = StringBuffer(
    "# From CLDR $_version common/main: each locale's index characters\n"
    '# (exemplarCharacters type="index"), under the Unicode License v3.\n',
  );
  final files = Directory('$common/main').listSync().whereType<File>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final f in files) {
    final name = f.uri.pathSegments.last.replaceAll('.xml', '');
    final m = RegExp(
      '<exemplarCharacters type="index">(.*?)</exemplarCharacters>',
    ).firstMatch(f.readAsStringSync());
    if (m != null) index.writeln('$name\t${m[1]}');
  }
  File('$_vendor/index_characters.tsv').writeAsStringSync('$index');
}
