/// What the syllabic shapers (Indic, Khmer, Myanmar, the Universal Shaping
/// Engine) share, after HarfBuzz 14.6: their syllable grammars, scanned
/// as Ragel's scanners scan (the longest match at each position, the
/// first pattern on a tie), dotted circles inserted into broken syllables
/// (`hb-ot-shaper-syllabic.cc`) and into the vowel sequences a script
/// prohibits (`hb-ot-shaper-vowel-constraints.cc`), and the categories'
/// tables.
library;

import 'package:plain_fonts/plain_fonts.dart';
import 'package:plain_typesetting/src/shaping/normalize.dart';
import 'package:plain_typesetting/src/shaping/vowel_constraints.g.dart';

/// A pattern of a syllable grammar over categories.
sealed class Pattern {
  const new();

  /// This pattern, then [other].
  Pattern operator &(Pattern other) => _Seq(this, other);

  /// This pattern or [other].
  Pattern operator |(Pattern other) => _Alt(this, other);

  /// This pattern, zero or more times.
  Pattern get star => _Star(this);

  /// This pattern, or nothing.
  Pattern get opt => _Alt(this, const _Empty());
}

final class _Sym extends Pattern {
  const new(this.categories);
  final Set<int> categories;
}

final class _Seq extends Pattern {
  const new(this.a, this.b);
  final Pattern a;
  final Pattern b;
}

final class _Alt extends Pattern {
  const new(this.a, this.b);
  final Pattern a;
  final Pattern b;
}

final class _Star extends Pattern {
  const new(this.p);
  final Pattern p;
}

final class _Empty extends Pattern {
  const new();
}

/// A pattern matching one glyph of any of [categories].
Pattern sym(Iterable<int> categories) => _Sym(categories.toSet());

/// A pattern matching one glyph of any category.
const Pattern anyGlyph = _Sym({-1});

/// The patterns in order, as a sequence.
Pattern seq(List<Pattern> patterns) => patterns.reduce(_Seq.new);

/// A pattern compiled to a nondeterministic automaton, for the longest
/// match at a position.
final class _Machine {
  new(Pattern pattern) {
    final (start, end) = _build(pattern);
    _start = start;
    _accept = end;
  }

  late final int _start;
  late final int _accept;

  /// Each state's transitions on a category (-1: any) and its empty moves.
  final List<List<(Set<int>, int)>> _moves = [];
  final List<List<int>> _empty = [];

  int _state() {
    _moves.add([]);
    _empty.add([]);
    return _moves.length - 1;
  }

  (int, int) _build(Pattern p) {
    switch (p) {
      case _Sym(:final categories):
        final s = _state();
        final e = _state();
        _moves[s].add((categories, e));
        return (s, e);
      case _Seq(:final a, :final b):
        final (s1, e1) = _build(a);
        final (s2, e2) = _build(b);
        _empty[e1].add(s2);
        return (s1, e2);
      case _Alt(:final a, :final b):
        final s = _state();
        final e = _state();
        final (s1, e1) = _build(a);
        final (s2, e2) = _build(b);
        _empty[s]
          ..add(s1)
          ..add(s2);
        _empty[e1].add(e);
        _empty[e2].add(e);
        return (s, e);
      case _Star(p: final inner):
        final s = _state();
        final e = _state();
        final (s1, e1) = _build(inner);
        _empty[s]
          ..add(s1)
          ..add(e);
        _empty[e1]
          ..add(s1)
          ..add(e);
        return (s, e);
      case _Empty():
        final s = _state();
        return (s, s);
    }
  }

  Set<int> _closure(Set<int> states) {
    final out = {...states};
    final stack = [...states];
    while (stack.isNotEmpty) {
      for (final next in _empty[stack.removeLast()]) {
        if (out.add(next)) stack.add(next);
      }
    }
    return out;
  }

  /// The length of the longest match of the categories from [at], 0 for
  /// none.
  int longest(List<int> categories, int at) {
    var states = _closure({_start});
    var best = 0;
    for (var i = at; i < categories.length && states.isNotEmpty; i++) {
      final c = categories[i];
      final next = <int>{};
      for (final s in states) {
        for (final (set, to) in _moves[s]) {
          if (set.contains(c) || set.contains(-1)) next.add(to);
        }
      }
      states = _closure(next);
      if (states.contains(_accept)) best = i - at + 1;
    }
    return best;
  }
}

/// A syllable grammar: its patterns in order, each with the syllable type
/// it finds.
final class SyllableGrammar {
  /// A grammar of [patterns], tried in order.
  new(List<(Pattern, int)> patterns)
    : _machines = [for (final (p, type) in patterns) (_Machine(p), type)];

  final List<(_Machine, int)> _machines;

  /// Numbers [glyphs]' syllables as HarfBuzz's machines do: each glyph's
  /// [LayoutGlyph.syllable] its syllable's serial (1 to 15, again and
  /// again) times 16 plus its type; [categoryOf] gives each glyph's
  /// category. Whether a syllable of type [broken] was found.
  bool findSyllables(
    List<LayoutGlyph> glyphs,
    int Function(LayoutGlyph) categoryOf, {
    int broken = -1,
  }) {
    final categories = [for (final g in glyphs) categoryOf(g)];
    var serial = 1;
    var foundBroken = false;
    var i = 0;
    while (i < glyphs.length) {
      var length = 0;
      var type = -1;
      for (final (machine, t) in _machines) {
        final l = machine.longest(categories, i);
        if (l > length) {
          length = l;
          type = t;
        }
      }
      if (length == 0) {
        length = 1;
        type = _machines.last.$2;
      }
      if (type == broken) foundBroken = true;
      for (var k = i; k < i + length; k++) {
        glyphs[k].syllable = serial << 4 | type;
      }
      serial++;
      if (serial == 16) serial = 1;
      i += length;
    }
    return foundBroken;
  }
}

/// The start and end of each syllable of [glyphs].
Iterable<(int, int)> syllables(List<LayoutGlyph> glyphs) sync* {
  var start = 0;
  while (start < glyphs.length) {
    var end = start + 1;
    while (end < glyphs.length &&
        glyphs[end].syllable == glyphs[start].syllable) {
      end++;
    }
    yield (start, end);
    start = end;
  }
}

/// The glyphs from [start] to [end] given the smallest cluster among them
/// (HarfBuzz's `merge_clusters`, extended to the clusters' other glyphs
/// as it is).
void mergeClusters(List<LayoutGlyph> glyphs, int start, int end) {
  if (end - start < 2) return;
  var cluster = glyphs[start].cluster;
  for (var i = start + 1; i < end; i++) {
    if (glyphs[i].cluster < cluster) cluster = glyphs[i].cluster;
  }
  // (Extended to the glyphs of the clusters at either end.)
  final first = glyphs[start].cluster;
  final last = glyphs[end - 1].cluster;
  var s = start;
  while (s > 0 && glyphs[s - 1].cluster == first) {
    s--;
  }
  var e = end;
  while (e < glyphs.length && glyphs[e].cluster == last) {
    e++;
  }
  for (var i = s; i < e; i++) {
    glyphs[i].cluster = cluster;
  }
}

/// A dotted circle (U+25CC) inserted at the start of each broken syllable
/// of [glyphs] (of type [broken]), after any glyphs of category [repha]
/// there; it has category [category] and position [position] (HarfBuzz's
/// `hb_syllabic_insert_dotted_circles`). Whether any was.
bool insertDottedCircles(
  List<LayoutGlyph> glyphs,
  int Function(int) glyphFor, {
  required int broken,
  required int category,
  int repha = -1,
  int position = -1,
}) {
  if (!glyphs.any((g) => g.syllable & 0x0f == broken)) return false;
  final dottedCircle = glyphFor(0x25cc);
  if (dottedCircle == 0) return false;
  final out = <LayoutGlyph>[];
  var last = 0;
  var i = 0;
  while (i < glyphs.length) {
    final g = glyphs[i];
    if (last != g.syllable && g.syllable & 0x0f == broken) {
      last = g.syllable;
      final circle = LayoutGlyph(dottedCircle, g.cluster, mask: g.mask)
        ..char = 0x25cc
        ..syllable = g.syllable
        ..category = category;
      setUnicodeProps(circle);
      if (position >= 0) circle.position = position;
      if (repha >= 0) {
        while (i < glyphs.length &&
            glyphs[i].syllable == last &&
            glyphs[i].category == repha) {
          out.add(glyphs[i++]);
        }
      }
      out.add(circle);
    } else {
      out.add(glyphs[i++]);
    }
  }
  glyphs
    ..clear()
    ..addAll(out);
  return true;
}

/// A dotted circle inserted before the last character of each vowel
/// sequence [script] prohibits (HarfBuzz's
/// `_hb_preprocess_text_vowel_constraints`).
void insertVowelConstraintCircles(List<LayoutGlyph> glyphs, String script) {
  final constraints = vowelConstraints[script];
  if (constraints == null) return;
  final out = <LayoutGlyph>[];
  var i = 0;
  while (i + 1 < glyphs.length) {
    List<int>? matched;
    for (final c in constraints) {
      if (i + c.length > glyphs.length) continue;
      var all = true;
      for (var k = 0; k < c.length && all; k++) {
        all = glyphs[i + k].char == c[k];
      }
      if (all) {
        matched = c;
        break;
      }
    }
    if (matched == null) {
      out.add(glyphs[i++]);
      continue;
    }
    for (var k = 0; k < matched.length - 1; k++) {
      out.add(glyphs[i++]);
    }
    final next = glyphs[i];
    out
      ..add(
        LayoutGlyph(0, next.cluster, mask: next.mask)
          ..char = 0x25cc
          ..apply(setUnicodeProps),
      )
      ..add(glyphs[i++]);
  }
  out.addAll(glyphs.skip(i));
  glyphs
    ..clear()
    ..addAll(out);
}

/// The value [ranges] (first, last, value triples, in order) gives
/// [codePoint], else [otherwise].
int rangeValue(List<int> ranges, int codePoint, int otherwise) {
  var lo = 0;
  var hi = ranges.length ~/ 3 - 1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    final first = ranges[mid * 3];
    if (codePoint < first) {
      hi = mid - 1;
    } else if (codePoint > ranges[mid * 3 + 1]) {
      lo = mid + 1;
    } else {
      return ranges[mid * 3 + 2];
    }
  }
  return otherwise;
}

extension on LayoutGlyph {
  void apply(void Function(LayoutGlyph) f) => f(this);
}
