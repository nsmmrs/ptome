/// Collation: strings ordered as a language orders them, by the Unicode
/// Collation Algorithm (UTS #10) with CLDR 48.2's root order and each
/// language's tailoring (German's, Swedish's, Spanish's..., Chinese by
/// pinyin or by stroke, Japanese's kana and its kanji in JIS order), as
/// ICU orders them; and the headings of an index in that order (ICU's
/// AlphabeticIndex: the language's index characters, Chinese's pinyin
/// letters or stroke counts).
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:plain_compression/plain_compression.dart';
import 'package:plain_unicode/src/bidi.dart' show canonicalCombiningClass;
import 'package:plain_unicode/src/properties.dart';
import 'package:plain_unicode/src/quotation_marks.dart' show cldrLocales;

part 'collation_data.g.dart';

/// A collation element: its primary, secondary and tertiary weights, and
/// whether it is variable (punctuation, symbols).
typedef _Ce = ({int p, int s, int t, bool variable, bool upper, bool mixed});

/// The root's elements, read once.
final _Table _root = _Table.parse(_rootData);

/// A table of elements: strings (a code point, a contraction) to their
/// elements, prefixed entries, and what the table's text says besides.
final class _Table {
  new _();

  final Map<String, List<_Ce>> entries = {};

  /// Each code point's longest contraction starting with it (in code
  /// points), where it starts one.
  final Map<int, int> contractions = {};

  /// Entries that apply after a prefix: by their first code point, each
  /// prefix and string (in code points) and its elements.
  final Map<int, List<(List<int>, List<int>, List<_Ce>)>> prefixed = {};

  final List<String> options = [];
  List<String> reorder = const [];
  final Set<String> suppressed = {};

  /// The common secondary and tertiary weights (root only).
  int commonS = 0;
  int commonT = 0;

  /// The last variable primary (root only): ICU's variable top, the end
  /// of the punctuation group.
  int variableTop = 0;

  /// The upper-case tertiary weights (root only).
  final Set<int> upper = {};

  /// The groups' first primaries, in order (root only).
  final List<(int, String)> groups = [];

  static _Table parse(String data) {
    final table = _Table._();
    final text = utf8.decode(brotliDecode(base64.decode(data)));
    List<int> cps(String hex) => [
      for (final c in hex.trim().split(' '))
        if (c.isNotEmpty) int.parse(c, radix: 16),
    ];
    List<_Ce> ces(String encoded) => [
      for (final ce in encoded.split(' '))
        if (ce.isNotEmpty)
          switch (ce.split(',')) {
            [final p, final s, final t, ...final rest] => (
              p: int.parse(p, radix: 36),
              s: int.parse(s, radix: 36),
              t: int.parse(t, radix: 36),
              variable: rest.isNotEmpty && rest.first.contains('*'),
              upper: rest.isNotEmpty && rest.first.contains('u'),
              mixed: rest.isNotEmpty && rest.first.contains('m'),
            ),
            _ => throw FormatException('collation element $ce'),
          },
    ];
    for (final line in const LineSplitter().convert(text)) {
      if (line.isEmpty) continue;
      switch (line[0]) {
        case 'W':
          final [_, s, t] = line.split(' ');
          table
            ..commonS = int.parse(s, radix: 36)
            ..commonT = int.parse(t, radix: 36);
        case 'V':
          table.variableTop = int.parse(line.substring(2), radix: 36);
        case 'U':
          for (final t in line.split(' ').skip(1)) {
            if (t.isNotEmpty) table.upper.add(int.parse(t, radix: 36));
          }
        case 'G':
          final [_, start, group] = line.split(' ');
          table.groups.add((int.parse(start, radix: 36), group));
        case 'O':
          table.options.add(line.substring(2));
        case 'R':
          table.reorder = line.substring(2).split(' ');
        case 'S':
          table.suppressed.add(String.fromCharCodes(cps(line.substring(2))));
        case 'P':
          final [head, encoded] = line.substring(2).split('\t');
          final [prefix, string] = head.split('|');
          final key = cps(string);
          (table.prefixed[key.first] ??= []).add((
            cps(prefix),
            key,
            ces(encoded),
          ));
        default:
          final [head, encoded] = line.split('\t');
          final key = cps(head);
          table.entries[String.fromCharCodes(key)] = ces(encoded);
          if (key.length > 1) {
            final longest = table.contractions[key.first] ?? 1;
            if (key.length > longest) {
              table.contractions[key.first] = key.length;
            }
          }
      }
    }
    return table;
  }
}

final Map<String, _Table> _locales = {};

// (Weights above 2^32 as products, not shifts: on the web a shift keeps
// 32 bits, and every weight stays below 2^53.)

/// The first implicit primary (2^40), above every ranked weight.
const int _implicitBase = 0x10000000000;

/// 2^32: an implicit primary's base above its offset.
const int _shift32 = 0x100000000;

/// The fourth level's weight of an element that isn't variable (2^50).
const int _quaternaryTop = 0x4000000000000;

/// The collation of a language: compares strings, and keys them, as the
/// language orders them.
final class Collator {
  /// The collation of [language] (a BCP 47 tag: `de`, `sv`, `zh-TW`,
  /// `ja`; `zh-u-co-stroke` for Chinese by stroke), the root order for a
  /// language CLDR tailors none for.
  factory(String language) {
    final type = RegExp(r'-u(?:-\w+)*?-co-([\w]+)')
        .firstMatch(language.toLowerCase())?[1];
    final tag = language.split(RegExp('-[ux]-')).first;
    // (The tag as CLDR names a locale with a variant first: `en_US_POSIX`.)
    final subtags = tag.replaceAll('_', '-').split('-');
    final named = [
      subtags.first.toLowerCase(),
      for (final s in subtags.skip(1))
        if (s.length == 4 && int.tryParse(s[0]) == null)
          s[0].toUpperCase() + s.substring(1).toLowerCase()
        else
          s.toUpperCase(),
    ].join('-');
    for (final candidate in [
      if (subtags.any((s) => s.length >= 5)) named,
      ...cldrLocales(tag),
    ]) {
      final locale = candidate.replaceAll('-', '_');
      for (final key in [if (type != null) '$locale@$type', locale]) {
        if (_localeData[key] case final data?) {
          return Collator._(_locales[key] ??= _Table.parse(data), key);
        }
      }
      // (A language with its own index characters but no tailoring: the
      // root order.)
      if (_indexCharacters.containsKey(locale)) {
        return Collator._(null, locale);
      }
    }
    return Collator._(null, 'root');
  }

  new _(this._tailoring, this.locale) {
    final options = _tailoring?.options ?? const [];
    for (final option in options) {
      final words = option.split(RegExp(r'\s+'));
      switch (words) {
        case ['caseFirst', 'upper']:
          _upperFirst = true;
        case ['backwards', '2']:
          _backwardSecondary = true;
        case ['alternate', 'shifted']:
          _shifted = true;
      }
    }
    final reorder = _tailoring?.reorder ?? const [];
    if (reorder.isNotEmpty) _groupRanks = _reordered(reorder);
  }

  final _Table? _tailoring;

  /// The CLDR locale whose collation this is (`zh@stroke` for a type
  /// besides its default; `root` for the root order).
  final String locale;

  var _upperFirst = false;
  var _backwardSecondary = false;
  var _shifted = false;

  /// Each group's place, where the tailoring reorders them.
  Map<String, int>? _groupRanks;

  /// How [a] compares with [b]: negative before, positive after, zero
  /// where they are the same (canonically equivalent).
  int compare(String a, String b) => sortKey(a).compareTo(sortKey(b));

  /// The key [text] sorts by.
  CollationKey sortKey(String text) {
    final cps = _nfd(text);
    final ces = _elements(cps);
    final primaries = <int>[];
    final secondaries = <int>[];
    final tertiaries = <int>[];
    // (Shifted: the variable elements, punctuation and spaces, weigh
    // nothing at the first three levels and their primaries at the
    // fourth, the others the most there. A mark after one keeps its
    // weights, as ICU has it.)
    final quaternaries = <int>[];
    for (final ce in ces) {
      final (:p, :s, :t, variable: _, :upper, :mixed) = ce;
      if (_shifted) {
        if (p != 0 && p <= _root.variableTop) {
          quaternaries.add(p);
          continue;
        }
        if (p != 0 || s != 0 || t != 0) quaternaries.add(_quaternaryTop);
      }
      if (p != 0) {
        // (Reordered: each primary after its group's place.)
        if (_groupRanks case final ranks?) {
          primaries.add(ranks[_groupOf(p)] ?? ranks['others']!);
        }
        primaries.add(p);
      }
      if (s != 0) secondaries.add(s);
      if (t != 0) {
        // (Upper case first, then mixed, then lower: ICU's case bits.)
        tertiaries.add(
          _upperFirst ? (upper ? 0 : (mixed ? 1 : 2) << 20) + t : t,
        );
      }
    }
    return CollationKey._(
      primaries,
      _backwardSecondary ? secondaries.reversed.toList() : secondaries,
      tertiaries,
      quaternaries,
      cps,
      ces.map((ce) => ce.p).firstWhere((p) => p != 0, orElse: () => 0),
    );
  }

  /// The group of primary [p]: the root's run it is in, an implicit
  /// weight's (Han) `Hani`.
  static String _groupOf(int p) {
    if (p >= _implicitBase) {
      final base = (p - _implicitBase) ~/ _shift32;
      return base >= 0xfb40 && base < 0xfbc0 ? 'Hani' : 'Zzzz';
    }
    final groups = _root.groups;
    var low = 0;
    var high = groups.length - 1;
    while (low < high) {
      final mid = (low + high + 1) >> 1;
      if (groups[mid].$1 <= p) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return groups.isEmpty ? 'Zzzz' : groups[low].$2;
  }

  /// The groups' places for the reordering [codes] (ICU's rules): the
  /// special groups first unless named, then the named groups in order,
  /// then the rest (`others`, `Zzzz`: where they go).
  static Map<String, int> _reordered(List<String> codes) {
    const special = ['space', 'punct', 'symbol', 'currency', 'digit'];
    final defaultOrder = <String>[];
    for (final (_, group) in _root.groups) {
      if (!defaultOrder.contains(group)) defaultOrder.add(group);
    }
    final named = [
      for (final c in codes)
        if (c == 'others' || c == 'Zzzz')
          'others'
        else
          c[0].toUpperCase() + c.substring(1).toLowerCase(),
    ].map((c) => special.contains(c.toLowerCase()) ? c.toLowerCase() : c);
    final order = <String>[
      for (final s in special)
        if (!named.contains(s)) s,
      for (final c in named)
        if (c != 'others') c,
    ];
    final rest = [
      for (final g in defaultOrder)
        if (!order.contains(g)) g,
    ];
    final at = named.toList().indexOf('others');
    final ranks = <String, int>{};
    var rank = 0;
    if (at < 0) {
      for (final g in [...order, ...rest, 'Zzzz']) {
        ranks[g] ??= rank++;
      }
    } else {
      final before = order.take(
        special.where((s) => !named.contains(s)).length + at,
      );
      final after = order.skip(before.length);
      for (final g in [...before, ...rest, ...after, 'Zzzz']) {
        ranks[g] ??= rank++;
      }
    }
    ranks['others'] = ranks['Zzzz']!;
    return ranks;
  }

  /// The elements of [cps] (canonically decomposed): each place's longest
  /// match, contiguous then discontiguous (UTS #10 S2.1), its prefixed
  /// entry where the text before matches, else its implicit elements.
  List<_Ce> _elements(List<int> cps) {
    final out = <_Ce>[];
    final text = [...cps];
    var i = 0;
    while (i < text.length) {
      final c = text[i];
      // (A prefixed entry: the longest prefix the text before ends with.)
      if (_tailoring?.prefixed[c] case final rules?) {
        List<_Ce>? best;
        var bestLength = -1;
        var bestEnd = i + 1;
        for (final (prefix, string, ces) in rules) {
          if (prefix.length > i || prefix.length <= bestLength) continue;
          if (i + string.length > text.length) continue;
          var matches = true;
          for (var k = 0; k < prefix.length && matches; k++) {
            if (text[i - prefix.length + k] != prefix[k]) matches = false;
          }
          for (var k = 0; k < string.length && matches; k++) {
            if (text[i + k] != string[k]) matches = false;
          }
          if (matches) {
            best = ces;
            bestLength = prefix.length;
            bestEnd = i + string.length;
          }
        }
        if (best != null) {
          out.addAll(best);
          i = bestEnd;
          continue;
        }
      }
      final longest = math.max(
        _tailoring?.contractions[c] ?? 1,
        _root.contractions[c] ?? 1,
      );
      var end = i + 1;
      List<_Ce>? found;
      for (var e = math.min(text.length, i + longest); e > i; e--) {
        final ces = _lookup(String.fromCharCodes(text.sublist(i, e)));
        if (ces != null) {
          found = ces;
          end = e;
          break;
        }
      }
      if (found == null) {
        out.add(_implicit(c));
        i++;
        continue;
      }
      // Discontiguous: an unblocked non-starter that extends the match.
      var matched = text.sublist(i, end);
      var j = end;
      var lastClass = 0;
      while (j < text.length) {
        final ccc = canonicalCombiningClass(text[j]);
        if (ccc == 0) break;
        if (lastClass != 0 && lastClass >= ccc) {
          lastClass = ccc;
          j++;
          continue;
        }
        final extended = _lookup(String.fromCharCodes([...matched, text[j]]));
        if (extended != null && matched.length < longest) {
          found = extended;
          matched = [...matched, text[j]];
          text.removeAt(j);
          continue;
        }
        lastClass = ccc;
        j++;
      }
      out.addAll(found!);
      i = end;
    }
    return out;
  }

  /// The elements of [key]: the tailoring's, else the root's (but for a
  /// contraction the tailoring suppresses).
  List<_Ce>? _lookup(String key) {
    final tailoring = _tailoring;
    if (tailoring != null) {
      if (tailoring.entries[key] case final ces?) return ces;
      if (tailoring.suppressed.contains(key)) return null;
    }
    return _root.entries[key];
  }

  /// [c]'s implicit element (UTS #10 10.1.3): Han and the scripts with
  /// implicit weights by their bases, the rest as unassigned; one element
  /// standing for UCA's two.
  _Ce _implicit(int c) {
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
    return (
      p: _implicitBase + base * _shift32 + (offset | 0x8000) * 0x10000,
      s: _root.commonS,
      t: _root.commonT,
      variable: false,
      upper: false,
      mixed: false,
    );
  }

  /// The index's headings for terms in this collation: the language's
  /// index characters (Chinese's pinyin letters, its stroke counts), in
  /// order, each with the key from which terms go under it.
  late final List<(String, CollationKey)> _labels = () {
    final out = <(String, CollationKey)>[];
    // (Chinese's tailorings mark them: `\uFDD0` and the label.)
    final tailoring = _tailoring;
    if (tailoring != null) {
      for (final key in tailoring.entries.keys) {
        if (key.startsWith('\ufdd0') && key.length > 1) {
          var label = key.substring(1);
          final c = label.runes.first;
          // (Stroke counts as braille patterns: `\u2801` for 1.)
          if (c >= 0x2800 && c <= 0x28ff) label = '${c - 0x2800}劃';
          out.add((label, sortKey(key)));
        }
      }
    }
    if (out.isEmpty) {
      final language = locale.split('@').first;
      final pattern =
          _indexCharacters[language] ??
          _indexCharacters[language.split('_').first] ??
          _indexCharacters['root'] ??
          '';
      for (final label in _setItems(pattern)) {
        out.add((label, sortKey(label)));
      }
    }
    out.sort((a, b) => a.$2.compareTo(b.$2));
    // (A label the same at the primary level as one before it goes, as
    // ICU drops it: Lithuanian's `Ą` with `A`.)
    final distinct = <(String, CollationKey)>[];
    for (final label in out) {
      if (distinct.isNotEmpty &&
          distinct.last.$2.comparePrimary(label.$2) == 0) {
        continue;
      }
      distinct.add(label);
    }
    return distinct;
  }();

  /// The index heading [text] goes under (ICU's AlphabeticIndex): the
  /// last label not after it at the primary level; null before the first
  /// (symbols, numerals) or in another script than the labels'.
  String? indexLabel(String text) {
    final key = sortKey(text);
    if (_pinyin) {
      // (Pinyin's letters take Latin terms and Han, no other script.)
      switch (_groupOf(key._first)) {
        case 'Latn':
          return _latinLabel(key);
        case 'Hani':
          break;
        default:
          return null;
      }
    }
    String? found;
    for (final (label, labelKey) in _labels) {
      if (labelKey.comparePrimary(key) <= 0) {
        found = label;
      } else {
        break;
      }
    }
    if (found == null || _labels.isEmpty) return null;
    // (Past the last label, in a later script than its: an overflow, as
    // ICU's. Chinese's labels take Latin as well.)
    final last = _labels.last.$2;
    if (last.comparePrimary(key) < 0 &&
        _groupOf(key._first) != _groupOf(last._first) &&
        !_pinyin) {
      return null;
    }
    return found;
  }

  /// Whether the index's labels are pinyin's letters, which take Latin
  /// terms too, as ICU merges them.
  late final bool _pinyin =
      _labels.isNotEmpty &&
      _labels.every((l) => RegExp(r'^[A-Z]$').hasMatch(l.$1)) &&
      _tailoring?.entries.keys.any((k) => k.startsWith('\ufdd0')) == true;

  /// The Latin letter a term under pinyin's index goes under: its first
  /// letter's, as ICU merges the pinyin and Latin buckets.
  String? _latinLabel(CollationKey key) {
    String? found;
    for (final letter in 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('')) {
      if (sortKey(letter).comparePrimary(key) <= 0) found = letter;
    }
    return found;
  }

  /// The locales with tailorings (`zh@stroke`: a type besides the
  /// default).
  static Iterable<String> get tailoredLocales => _localeData.keys;

  /// The strings this collation's tailoring orders (not the index
  /// boundaries), for checks.
  Iterable<String> get tailoredStrings => [
    for (final key in _tailoring?.entries.keys ?? const <String>[])
      if (!key.startsWith('\ufdd0')) key,
  ];

  /// The index headings in order (pinyin's every Latin letter, those no
  /// syllable starts with too, as ICU lists them).
  List<String> get indexLabels => _pinyin
      ? 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('')
      : [for (final (label, _) in _labels) label];
}

/// The labels a UnicodeSet pattern of index characters lists (`[A B C]`,
/// `[あ か さ]`, `{AB}` sequences; ranges `a-c`).
List<String> _setItems(String pattern) {
  final inner = pattern.trim().replaceAll(RegExp(r'^\[|\]$'), '');
  final out = <String>[];
  final runes = inner.runes.toList();
  for (var i = 0; i < runes.length; i++) {
    final c = runes[i];
    if (c == 0x20) continue;
    if (c == 0x7b) {
      // (`{...}`: a string.)
      final end = runes.indexOf(0x7d, i);
      out.add(String.fromCharCodes(runes.sublist(i + 1, end)));
      i = end;
    } else if (c == 0x5c && i + 1 < runes.length) {
      out.add(String.fromCharCode(runes[++i]));
    } else if (i + 2 < runes.length && runes[i + 1] == 0x2d) {
      for (var x = c; x <= runes[i + 2]; x++) {
        out.add(String.fromCharCode(x));
      }
      i += 2;
    } else {
      out.add(String.fromCharCode(c));
    }
  }
  return out;
}

/// The key a string sorts by in a [Collator]: its weights level by level,
/// then its code points.
final class CollationKey implements Comparable<CollationKey> {
  new _(
    this._primaries,
    this._secondaries,
    this._tertiaries,
    this._quaternaries,
    this._identical,
    this._first,
  );

  /// The first primary weight, as the table has it (not reordered).
  final int _first;

  final List<int> _primaries;
  final List<int> _secondaries;
  final List<int> _tertiaries;
  final List<int> _quaternaries;
  final List<int> _identical;

  @override
  int compareTo(CollationKey other) {
    for (final (a, b) in [
      (_primaries, other._primaries),
      (_secondaries, other._secondaries),
      (_tertiaries, other._tertiaries),
      (_quaternaries, other._quaternaries),
      (_identical, other._identical),
    ]) {
      final c = _compareLists(a, b);
      if (c != 0) return c;
    }
    return 0;
  }

  @override
  String toString() => '$_primaries $_secondaries $_tertiaries';

  /// How this key compares with [other] at the primary level alone.
  int comparePrimary(CollationKey other) =>
      _compareLists(_primaries, other._primaries);

  static int _compareLists(List<int> a, List<int> b) {
    final n = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < n; i++) {
      final c = a[i].compareTo(b[i]);
      if (c != 0) return c;
    }
    return a.length.compareTo(b.length);
  }
}

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

/// Whether [c] is a unified ideograph (Han: UCA's implicit bases).
bool _isUnifiedIdeograph(int c) {
  for (var i = 0; i < _unifiedIdeographs.length; i += 2) {
    if (c < _unifiedIdeographs[i]) return false;
    if (c <= _unifiedIdeographs[i + 1]) return true;
  }
  return false;
}
