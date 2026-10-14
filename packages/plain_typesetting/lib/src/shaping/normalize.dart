/// Normalization as HarfBuzz 14.6 does it before shaping
/// (`hb-ot-shape-normalize.cc`): each cluster decomposed as far as the
/// font has the parts, its marks put in canonical order (HarfBuzz's
/// modified classes), and recomposed where the font has the composite,
/// as the shaper prefers.
library;

import 'package:plain_fonts/plain_fonts.dart';
import 'package:plain_unicode/plain_unicode.dart';

/// How a shaper wants its text normalized.
enum NormalizationMode {
  /// Left as it is.
  none,

  /// Decomposed.
  decomposed,

  /// Diacritics recomposed.
  composedDiacritics,

  /// Diacritics recomposed, every cluster decomposed first.
  composedDiacriticsNoShortCircuit,

  /// The shaper doesn't say: [composedDiacritics].
  auto,
}

/// The hooks a shaper gives normalization.
abstract interface class NormalizationHooks {
  /// The mode.
  NormalizationMode get normalization;

  /// [ab]'s decomposition (one step), or null; HarfBuzz's default is
  /// Unicode's canonical one.
  (int, int)? decompose(int ab);

  /// The composite of [a] and [b], or null.
  int? compose(int a, int b);

  /// Reorders the marks [glyphs] has from [start] to [end], after they
  /// are in canonical order (Arabic's modifier marks).
  void reorderMarks(List<LayoutGlyph> glyphs, int start, int end);
}

/// Unicode's canonical decomposition of [ab], one step (a singleton as
/// (a, 0)), as HarfBuzz's Unicode functions give it.
(int, int)? unicodeDecompose(int ab) => switch (canonicalDecomposition(ab)) {
  (final a, final b) => (a, b ?? 0),
  null => null,
};

/// Unicode's canonical composition of [a] and [b].
int? unicodeCompose(int a, int b) => canonicalComposition(a, b);

/// [codePoint]'s combining class as HarfBuzz modifies it (Hebrew's and
/// Arabic's points in their typographic order, a few others moved).
int modifiedCombiningClass(int codePoint) {
  if (codePoint == 0x1a60 || codePoint == 0x0fc6) return 254;
  if (codePoint == 0x0f39) return 127;
  final ccc = canonicalCombiningClass(codePoint);
  return _modified[ccc] ?? ccc;
}

const Map<int, int> _modified = {
  // Hebrew.
  10: 22, 11: 15, 12: 16, 13: 17, 14: 23, 15: 18, 16: 19, 17: 20, 18: 21, //
  19: 14, 20: 24, 21: 12, 22: 25, 23: 13, 24: 10, 25: 11, 26: 26,
  // Arabic.
  27: 28, 28: 29, 29: 30, 30: 31, 31: 32, 32: 33, 33: 27, 34: 34, 35: 35,
  // Syriac.
  36: 36,
  // Telugu.
  84: 4, 91: 5,
  // Thai.
  103: 3, 107: 107,
  // Lao.
  118: 118, 122: 122,
  // Tibetan.
  129: 129, 130: 132, 132: 131,
};

/// [glyph] given its character's properties (its General_Category, its
/// modified combining class if a mark, its default-ignorable flags).
void setUnicodeProps(LayoutGlyph glyph) {
  final c = glyph.char;
  final gc = generalCategory(c);
  glyph
    ..generalCategory = gc.index
    ..combiningClass = _isMarkCategory(gc) ? modifiedCombiningClass(c) : 0
    ..flags = unicodeFlags(c);
}

bool _isMarkCategory(GeneralCategory gc) =>
    gc == GeneralCategory.nonspacingMark ||
    gc == GeneralCategory.spacingMark ||
    gc == GeneralCategory.enclosingMark;

/// Whether [glyph]'s character is a mark.
bool isUnicodeMark(LayoutGlyph glyph) =>
    _isMarkCategory(GeneralCategory.values[glyph.generalCategory]);

/// The [UnicodeFlags] of [code]: a default ignorable, a joiner, a
/// non-joiner, hidden (HarfBuzz's `_hb_glyph_info_set_unicode_props`).
int unicodeFlags(int code) {
  if (code < 0x80 || !isDefaultIgnorable(code)) return 0;
  var flags = UnicodeFlags.ignorable;
  if (code == 0x200c) {
    flags |= UnicodeFlags.zwnj;
  } else if (code == 0x200d) {
    flags |= UnicodeFlags.zwj;
  } else if ((code >= 0x180b && code <= 0x180d) ||
      code == 0x180f ||
      (code >= 0xe0020 && code <= 0xe007f) ||
      code == 0x034f) {
    flags |= UnicodeFlags.hidden;
  }
  return flags;
}

/// Whether [code] is a variation selector normalization leaves alone.
bool _isVariationSelector(int code) =>
    (code >= 0xfe00 && code <= 0xfe0f) || (code >= 0xe0100 && code <= 0xe01ef);

/// [glyphs] normalized for [hooks]'s shaper, each glyph its character's
/// nominal glyph ([glyphFor]; 0: none) and properties.
List<LayoutGlyph> normalize(
  List<LayoutGlyph> glyphs,
  NormalizationHooks hooks,
  int Function(int codePoint) glyphFor,
) {
  if (glyphs.isEmpty) return glyphs;
  var mode = hooks.normalization;
  if (mode == NormalizationMode.auto) {
    mode = NormalizationMode.composedDiacritics;
  }
  final alwaysShortCircuit = mode == NormalizationMode.none;
  final mightShortCircuit =
      alwaysShortCircuit ||
      (mode != NormalizationMode.decomposed &&
          mode != NormalizationMode.composedDiacriticsNoShortCircuit);

  // First round: decompose.
  final out = <LayoutGlyph>[];
  LayoutGlyph copy(LayoutGlyph from, int char, int glyph) =>
      LayoutGlyph(glyph, from.cluster, mask: from.mask)
        ..char = char
        ..syllable = from.syllable
        ..category = from.category
        ..position = from.position
        ..props = from.props;
  void output(LayoutGlyph from, int char, int glyph) =>
      out.add(copy(from, char, glyph)..apply(setUnicodeProps));

  // Returns 0 if it didn't decompose, else the number of characters.
  int decompose(LayoutGlyph from, int ab, {required bool shortest}) {
    final parts = hooks.decompose(ab);
    if (parts == null) return 0;
    final (a, b) = parts;
    final bGlyph = b == 0 ? 0 : glyphFor(b);
    if (b != 0 && bGlyph == 0) return 0;
    final aGlyph = glyphFor(a);
    final hasA = aGlyph != 0;
    if (shortest && hasA) {
      output(from, a, aGlyph);
      if (b != 0) {
        output(from, b, bGlyph);
        return 2;
      }
      return 1;
    }
    final inner = decompose(from, a, shortest: shortest);
    if (inner != 0) {
      if (b != 0) {
        output(from, b, bGlyph);
        return inner + 1;
      }
      return inner;
    }
    if (hasA) {
      output(from, a, aGlyph);
      if (b != 0) {
        output(from, b, bGlyph);
        return 2;
      }
      return 1;
    }
    return 0;
  }

  void decomposeCurrent(LayoutGlyph g, {required bool shortest}) {
    final u = g.char;
    final glyph = glyphFor(u);
    if (shortest && glyph != 0) {
      out.add(g..glyph = glyph);
      return;
    }
    if (decompose(g, u, shortest: shortest) != 0) return;
    if (!shortest && glyph != 0) {
      out.add(g..glyph = glyph);
      return;
    }
    if (u == 0x2011) {
      final other = glyphFor(0x2010);
      if (other != 0) {
        out.add(g..glyph = other);
        return;
      }
    }
    // (A space the font lacks: the space's glyph, its width adjusted
    // later as HarfBuzz's fallback does.)
    if (generalCategory(u) == GeneralCategory.spaceSeparator) {
      final space = glyphFor(0x20);
      if (space != 0) {
        out.add(g..glyph = space);
        return;
      }
    }
    out.add(g..glyph = glyph);
  }

  var allSimple = true;
  var idx = 0;
  final count = glyphs.length;
  while (idx < count) {
    var end = idx + 1;
    while (end < count && !isUnicodeMark(glyphs[end])) {
      end++;
    }
    if (end < count) end--; // Leave one base for the marks to cluster with.
    while (idx < end) {
      decomposeCurrent(glyphs[idx], shortest: mightShortCircuit);
      idx++;
    }
    if (idx == count) break;
    allSimple = false;
    end = idx + 1;
    while (end < count && isUnicodeMark(glyphs[end])) {
      end++;
    }
    // One cluster of a base and marks.
    final hasVariationSelector = [for (var i = idx; i < end; i++) glyphs[i]]
        .any((g) => _isVariationSelector(g.char));
    if (hasVariationSelector) {
      // (Given up on: each character passed on as it is.)
      for (; idx < end; idx++) {
        final g = glyphs[idx];
        out.add(g..glyph = glyphFor(g.char));
      }
    } else {
      for (; idx < end; idx++) {
        decomposeCurrent(glyphs[idx], shortest: alwaysShortCircuit);
      }
    }
  }

  // Second round: reorder the marks (in place).
  if (!allSimple) {
    for (var i = 0; i < out.length; i++) {
      if (out[i].combiningClass == 0) continue;
      var end = i + 1;
      while (end < out.length && out[end].combiningClass != 0) {
        end++;
      }
      if (end - i <= 32) {
        // (Stable, as HarfBuzz's buffer sort is.)
        final run = out.sublist(i, end).indexed.toList()
          ..sort((a, b) {
            final c = a.$2.combiningClass - b.$2.combiningClass;
            return c != 0 ? c : a.$1 - b.$1;
          });
        out.setRange(i, end, [for (final (_, g) in run) g]);
        hooks.reorderMarks(out, i, end);
      }
      i = end;
    }
    // A COMBINING GRAPHEME JOINER that blocked no reordering is skipped.
    for (var i = 1; i + 1 < out.length; i++) {
      if (out[i].char == 0x034f &&
          (out[i + 1].combiningClass == 0 ||
              out[i - 1].combiningClass <= out[i + 1].combiningClass)) {
        out[i].flags &= ~UnicodeFlags.hidden;
      }
    }
  }

  // Third round: recompose.
  if (!allSimple &&
      (mode == NormalizationMode.composedDiacritics ||
          mode == NormalizationMode.composedDiacriticsNoShortCircuit)) {
    final composed = <LayoutGlyph>[out.first];
    var starter = 0;
    for (var i = 1; i < out.length; i++) {
      final cur = out[i];
      if (isUnicodeMark(cur)) {
        final prev = composed.last;
        if (starter == composed.length - 1 ||
            prev.combiningClass < cur.combiningClass) {
          final ab = hooks.compose(composed[starter].char, cur.char);
          if (ab != null) {
            final glyph = glyphFor(ab);
            if (glyph != 0) {
              final s = composed[starter];
              if (cur.cluster < s.cluster) s.cluster = cur.cluster;
              s
                ..char = ab
                ..glyph = glyph
                ..apply(setUnicodeProps);
              continue;
            }
          }
        }
      }
      composed.add(cur);
      if (cur.combiningClass == 0) starter = composed.length - 1;
    }
    return composed;
  }
  return out;
}

extension on LayoutGlyph {
  /// [f] applied to it.
  void apply(void Function(LayoutGlyph) f) => f(this);
}
